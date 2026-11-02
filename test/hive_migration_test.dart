import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:pdf_listener/models/chunk.dart';
import 'package:pdf_listener/models/document.dart';
import 'package:pdf_listener/services/repository.dart';

/// Writes documents the way the v1 schema did: no pipelineVersion (14) or
/// chunkCount (15).
class _LegacyDocumentAdapter extends TypeAdapter<Document> {
  @override
  final int typeId = 0;
  @override
  Document read(BinaryReader reader) => throw UnimplementedError();
  @override
  void write(BinaryWriter w, Document d) {
    final fields = <int, Object?>{
      0: d.id, 1: d.title, 2: d.originalFileName, 3: d.pdfPath, 4: d.startPage, //
      5: d.endPage, 6: d.status.name, 7: d.progress, 8: d.error, 9: d.audioPath,
      10: d.totalDuration?.inMicroseconds, 11: d.lastPosition.inMicroseconds,
      12: d.createdAt.millisecondsSinceEpoch, 13: d.pageCount,
    };
    w.writeByte(fields.length);
    fields.forEach((k, v) => w
      ..writeByte(k)
      ..write(v));
  }
}

/// v1 chunks: no isHeading (5).
class _LegacyChunkAdapter extends TypeAdapter<Chunk> {
  @override
  final int typeId = 1;
  @override
  Chunk read(BinaryReader reader) => throw UnimplementedError();
  @override
  void write(BinaryWriter w, Chunk c) {
    w
      ..writeByte(5)
      ..writeByte(0)
      ..write(c.index)
      ..writeByte(1)
      ..write(c.text)
      ..writeByte(2)
      ..write(c.pageNumber)
      ..writeByte(3)
      ..write(c.startOffset.inMicroseconds)
      ..writeByte(4)
      ..write(c.duration.inMicroseconds);
  }
}

void main() {
  test('v1 records load and are flagged for reconversion', () async {
    final dir = Directory.systemTemp.createTempSync('hive_migration');
    addTearDown(() async {
      await Hive.close();
      Hive.resetAdapters();
      dir.deleteSync(recursive: true);
    });
    Hive.init(dir.path);
    Hive.registerAdapter(_LegacyDocumentAdapter());
    Hive.registerAdapter(_LegacyChunkAdapter());

    final docs = await Hive.openBox<Document>('documents');
    final chunks = await Hive.openBox<List>('chunks');
    await docs.put('a', Document(
      id: 'a',
      title: 'Old book',
      originalFileName: 'old.pdf',
      pdfPath: '/x/old.pdf',
      pageCount: 10,
      startPage: 1,
      endPage: 10,
      createdAt: DateTime(2026, 1, 1),
      status: DocStatus.ready,
      audioPath: '/x/audio.wav',
      totalDuration: const Duration(minutes: 5),
      lastPosition: const Duration(minutes: 1),
    ));
    await chunks.put('a', [
      const Chunk(index: 0, text: 'A whole page of text.', pageNumber: 1,
          duration: Duration(minutes: 5)),
    ]);
    await Hive.close();

    Hive.resetAdapters();
    final repo = await DocumentRepository.open();
    final doc = repo.get('a')!;
    expect(doc.title, 'Old book');
    expect(doc.pipelineVersion, 1);
    expect(doc.needsReconversion, isTrue);
    expect(doc.isPlayable, isFalse);
    expect(doc.lastPosition, const Duration(minutes: 1));

    final migrated = repo.chunks('a').single;
    expect(migrated.isHeading, isFalse);
    expect(migrated.text, 'A whole page of text.');

    // Saving with the current adapter round-trips the new fields.
    await repo.put(doc.copyWith(pipelineVersion: kPipelineVersion));
    expect(repo.get('a')!.needsReconversion, isFalse);
  });
}
