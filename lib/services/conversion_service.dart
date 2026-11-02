import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/app_settings.dart';
import '../models/chunk.dart';
import '../models/document.dart';
import 'chunker.dart';
import 'pdf_extractor.dart';
import 'repository.dart';
import 'storage.dart';
import 'text_cleaner.dart';
import 'tts_synth.dart';
import 'wav_merger.dart';

const scannedPdfMessage =
    "No text found — this PDF looks scanned. Scanned PDFs aren't supported.";

class ConversionException implements Exception {
  ConversionException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _Cancelled implements Exception {}

/// Runs conversions one at a time: extract → clean → chunk → synthesise
/// each chunk → merge. Resumable: chunk text and the settings snapshot are
/// persisted, finished chunk WAVs are skipped on the next run.
class ConversionService {
  ConversionService(this._repo, this._storage, this._tts);

  final DocumentRepository _repo;
  final AppStorage _storage;
  final TtsSynth _tts;

  final _queue = <String>[];
  bool _running = false;
  String? _currentId;
  bool _cancelCurrent = false;

  /// Queues a conversion. If chunks from an interrupted run exist they are
  /// reused; call [reset] first to start from scratch.
  Future<void> enqueue(String id) async {
    if (_queue.contains(id) || _currentId == id) return;
    await _repo.update(
        id, (d) => d.copyWith(status: DocStatus.queued, clearError: true));
    _queue.add(id);
    _pump();
  }

  /// Re-queues conversions that were in progress when the app was killed.
  Future<void> resumeInterrupted() async {
    for (final doc in _repo.all().reversed) {
      if (doc.isBusy) await enqueue(doc.id);
    }
  }

  /// Stops any conversion of [id], whether queued or running.
  Future<void> cancel(String id) async {
    _queue.remove(id);
    if (_currentId == id) {
      _cancelCurrent = true;
      await _tts.stop();
      while (_currentId == id) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  /// Discards audio, partial chunks and stored chunk text.
  Future<int> reset(String id) async {
    await cancel(id);
    final freed = await _storage.deleteAudio(id);
    await _repo.deleteChunks(id);
    await _repo.update(
        id,
        (d) => d.copyWith(
            status: DocStatus.idle,
            progress: 0,
            clearError: true,
            clearAudio: true,
            chunkCount: 0));
    return freed;
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    await WakelockPlus.enable();
    try {
      while (_queue.isNotEmpty) {
        final id = _queue.removeAt(0);
        _currentId = id;
        _cancelCurrent = false;
        await _convert(id);
        _currentId = null;
      }
    } finally {
      _currentId = null;
      _running = false;
      await WakelockPlus.disable();
    }
  }

  void _checkCancelled(String id) {
    if (_cancelCurrent || _repo.get(id) == null) throw _Cancelled();
  }

  Future<void> _convert(String id) async {
    var doc = _repo.get(id);
    if (doc == null) return;
    try {
      final chunkDir = _storage.chunkDir(id);
      final snapshotFile = File(p.join(chunkDir.path, 'synth.json'));
      var chunks = _repo.chunks(id);
      final AppSettings settings;

      final canResume = chunks.isNotEmpty &&
          doc.pipelineVersion == kPipelineVersion &&
          await snapshotFile.exists();
      if (canResume) {
        settings = AppSettings.fromMap(
            jsonDecode(await snapshotFile.readAsString()) as Map<String, dynamic>);
      } else {
        settings = _repo.settings;
        await _storage.deleteChunks(id);
        await chunkDir.create(recursive: true);
        await _repo.update(id,
            (d) => d.copyWith(status: DocStatus.extracting, progress: 0, clearError: true));

        final pages =
            await PdfExtractor.extractLines(doc.pdfPath, doc.startPage, doc.endPage);
        _checkCancelled(id);
        final blocks = cleanPages(pages,
            config: CleanerConfig(readCodeBlocks: settings.readCodeBlocks));
        if (spokenAlnumCount(blocks) < max(30, 5 * pages.length)) {
          throw ConversionException(scannedPdfMessage);
        }
        final drafts = chunkBlocks(blocks)
            .where((c) => RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(c.text))
            .toList();
        chunks = [
          for (var i = 0; i < drafts.length; i++)
            Chunk(
              index: i,
              text: drafts[i].text,
              pageNumber: drafts[i].pageNumber,
              isHeading: drafts[i].isHeading,
            ),
        ];
        await _repo.putChunks(id, chunks);
        await snapshotFile.writeAsString(jsonEncode(settings.toMap()));
        await _repo.update(id,
            (d) => d.copyWith(pipelineVersion: kPipelineVersion, chunkCount: chunks.length));
      }

      _checkCancelled(id);
      await _repo.update(id, (d) => d.copyWith(status: DocStatus.converting));
      await _tts.configure(settings);

      final paths = <String>[];
      for (var i = 0; i < chunks.length; i++) {
        _checkCancelled(id);
        final path = p.join(chunkDir.path, 'chunk_${i.toString().padLeft(5, '0')}.wav');
        paths.add(path);
        if (!await isValidWav(path)) {
          await _synthesizeChunk(chunks[i].text, path);
        }
        // Reserve the last 2% for the merge.
        final progress = (i + 1) / chunks.length * 0.98;
        await _repo.update(id, (d) => d.copyWith(progress: progress));
      }

      _checkCancelled(id);
      final audioPath = _storage.audioPath(id);
      final merged = await mergeWavFiles(paths, audioPath);
      final timed = [
        for (var i = 0; i < chunks.length; i++)
          chunks[i].withTiming(merged.startOffsets[i], merged.durations[i]),
      ];
      await _repo.putChunks(id, timed);
      await _storage.deleteChunks(id);
      await _repo.update(
          id,
          (d) => d.copyWith(
                status: DocStatus.ready,
                progress: 1,
                audioPath: audioPath,
                totalDuration: merged.total,
                lastPosition: Duration.zero,
                pipelineVersion: kPipelineVersion,
                chunkCount: timed.length,
                clearError: true,
              ));
    } on _Cancelled {
      // Deleted or reset while running; whoever cancelled owns the state.
    } on Object catch (e) {
      if (!_cancelCurrent && _repo.get(id) != null) {
        await _repo.update(id,
            (d) => d.copyWith(status: DocStatus.failed, error: e.toString()));
      }
    }
  }

  /// Writes to a temporary name and renames once valid, so a run killed
  /// mid-write never leaves a truncated chunk that looks finished.
  Future<void> _synthesizeChunk(String text, String path) async {
    final part = '$path.part';
    for (var attempt = 1;; attempt++) {
      final partFile = File(part);
      if (await partFile.exists()) await partFile.delete();
      try {
        await _tts.synthesizeToFile(text, part);
        if (!await isValidWav(part)) {
          throw TtsException('The TTS engine wrote an invalid audio file');
        }
        await partFile.rename(path);
        return;
      } on TtsException {
        if (_cancelCurrent || attempt >= 2) rethrow;
      }
    }
  }
}
