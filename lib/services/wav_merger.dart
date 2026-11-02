import 'dart:io';
import 'dart:typed_data';

class WavFormatException implements Exception {
  WavFormatException(this.message);
  final String message;
  @override
  String toString() => 'WavFormatException: $message';
}

/// Format and data location of a RIFF/WAVE file.
class WavInfo {
  const WavInfo({
    required this.audioFormat,
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.blockAlign,
    required this.dataOffset,
    required this.dataSize,
  });

  final int audioFormat;
  final int channels;
  final int sampleRate;
  final int bitsPerSample;
  final int blockAlign;
  final int dataOffset;
  final int dataSize;

  int get byteRate => sampleRate * blockAlign;

  Duration get duration => durationOf(dataSize);

  Duration durationOf(int bytes) =>
      Duration(microseconds: bytes * 1000000 ~/ byteRate);

  bool sameFormatAs(WavInfo o) =>
      audioFormat == o.audioFormat &&
      channels == o.channels &&
      sampleRate == o.sampleRate &&
      bitsPerSample == o.bitsPerSample;

  String get formatLabel =>
      '${sampleRate}Hz/${channels}ch/${bitsPerSample}bit (format $audioFormat)';
}

/// Parses a WAV header by walking its RIFF chunks; no fixed 44-byte layout
/// is assumed. [bytes] is a prefix of the file that contains the "data"
/// chunk header; [fileLength] is the full file size, used when the declared
/// data size is missing or larger than the file (streamed or truncated
/// writes).
WavInfo parseWavHeader(Uint8List bytes, {required int fileLength}) {
  if (bytes.length < 12) throw WavFormatException('File too short');
  final view = ByteData.sublistView(bytes);
  String tag(int at) => String.fromCharCodes(bytes, at, at + 4);
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') {
    throw WavFormatException('Not a RIFF/WAVE file');
  }
  int? audioFormat, channels, sampleRate, bitsPerSample, blockAlign;
  var pos = 12;
  while (pos + 8 <= bytes.length) {
    final id = tag(pos);
    final size = view.getUint32(pos + 4, Endian.little);
    final body = pos + 8;
    if (id == 'fmt ') {
      if (body + 16 > bytes.length) throw WavFormatException('Truncated fmt chunk');
      audioFormat = view.getUint16(body, Endian.little);
      channels = view.getUint16(body + 2, Endian.little);
      sampleRate = view.getUint32(body + 4, Endian.little);
      blockAlign = view.getUint16(body + 12, Endian.little);
      bitsPerSample = view.getUint16(body + 14, Endian.little);
      if (audioFormat == 0xFFFE && size >= 40 && body + 26 <= bytes.length) {
        // WAVE_FORMAT_EXTENSIBLE: the real format is the subformat GUID's
        // first two bytes.
        audioFormat = view.getUint16(body + 24, Endian.little);
      }
    } else if (id == 'data') {
      if (audioFormat == null) throw WavFormatException('"data" before "fmt "');
      if (channels == 0 || sampleRate == 0 || blockAlign == 0) {
        throw WavFormatException('Invalid fmt values');
      }
      final available = fileLength - body;
      var dataSize = (size == 0 || size == 0xFFFFFFFF || size > available)
          ? available
          : size;
      dataSize -= dataSize % blockAlign!;
      return WavInfo(
        audioFormat: audioFormat,
        channels: channels!,
        sampleRate: sampleRate!,
        bitsPerSample: bitsPerSample!,
        blockAlign: blockAlign,
        dataOffset: body,
        dataSize: dataSize < 0 ? 0 : dataSize,
      );
    }
    pos = body + size + (size.isOdd ? 1 : 0);
  }
  throw WavFormatException('No "data" chunk found');
}

/// Builds a canonical 44-byte PCM header.
Uint8List buildWavHeader({
  required int channels,
  required int sampleRate,
  required int bitsPerSample,
  required int dataSize,
  int audioFormat = 1,
}) {
  final blockAlign = channels * bitsPerSample ~/ 8;
  final b = ByteData(44);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, 36 + dataSize, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, audioFormat, Endian.little);
  b.setUint16(22, channels, Endian.little);
  b.setUint32(24, sampleRate, Endian.little);
  b.setUint32(28, sampleRate * blockAlign, Endian.little);
  b.setUint16(32, blockAlign, Endian.little);
  b.setUint16(34, bitsPerSample, Endian.little);
  tag(36, 'data');
  b.setUint32(40, dataSize, Endian.little);
  return b.buffer.asUint8List();
}

const _headerProbeBytes = 64 * 1024;

Future<WavInfo> readWavInfo(String path) async {
  final file = File(path);
  final raf = await file.open();
  try {
    final length = await raf.length();
    final prefix = await raf.read(length < _headerProbeBytes ? length : _headerProbeBytes);
    return parseWavHeader(prefix, fileLength: length);
  } finally {
    await raf.close();
  }
}

/// True when [path] exists and has a parseable WAV header.
Future<bool> isValidWav(String path) async {
  if (!await File(path).exists()) return false;
  try {
    await readWavInfo(path);
    return true;
  } on Object {
    return false;
  }
}

class MergeResult {
  const MergeResult(this.startOffsets, this.durations, this.total);

  /// Start of each input within the merged audio, from cumulative bytes.
  final List<Duration> startOffsets;
  final List<Duration> durations;
  final Duration total;
}

/// Concatenates the PCM data of [inputs] into a single WAV at [outputPath],
/// streaming so memory stays flat for multi-hour audio. All inputs must
/// share one format. Returns each input's duration in order.
Future<MergeResult> mergeWavFiles(List<String> inputs, String outputPath) async {
  if (inputs.isEmpty) throw WavFormatException('Nothing to merge');
  final infos = <WavInfo>[];
  for (final path in inputs) {
    infos.add(await readWavInfo(path));
  }
  final first = infos.first;
  for (var i = 1; i < infos.length; i++) {
    if (!infos[i].sameFormatAs(first)) {
      throw WavFormatException('Chunk $i is ${infos[i].formatLabel}, '
          'expected ${first.formatLabel}');
    }
  }
  final totalData = infos.fold<int>(0, (n, w) => n + w.dataSize);
  if (totalData > 0xFFFFFFFF - 36) {
    throw WavFormatException('Audio exceeds the 4 GB WAV limit; '
        'convert a smaller page range');
  }

  final tmpPath = '$outputPath.tmp';
  final out = await File(tmpPath).open(mode: FileMode.write);
  try {
    await out.writeFrom(buildWavHeader(
      channels: first.channels,
      sampleRate: first.sampleRate,
      bitsPerSample: first.bitsPerSample,
      dataSize: totalData,
      audioFormat: first.audioFormat,
    ));
    for (var i = 0; i < inputs.length; i++) {
      final info = infos[i];
      final src = await File(inputs[i]).open();
      try {
        await src.setPosition(info.dataOffset);
        var remaining = info.dataSize;
        while (remaining > 0) {
          final block = await src.read(remaining < 1 << 20 ? remaining : 1 << 20);
          if (block.isEmpty) {
            throw WavFormatException('Chunk $i ended early');
          }
          await out.writeFrom(block);
          remaining -= block.length;
        }
      } finally {
        await src.close();
      }
    }
  } finally {
    await out.close();
  }
  await File(tmpPath).rename(outputPath);

  final durations = <Duration>[];
  final startOffsets = <Duration>[];
  var bytesSoFar = 0;
  for (final w in infos) {
    startOffsets.add(first.durationOf(bytesSoFar));
    durations.add(w.duration);
    bytesSoFar += w.dataSize;
  }
  return MergeResult(startOffsets, durations, first.durationOf(totalData));
}
