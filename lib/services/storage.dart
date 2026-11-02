import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// File layout, one folder per document:
/// ```
/// library/<id>/source.pdf   copied PDF
/// library/<id>/audio.wav    merged audio
/// library/<id>/chunks/      per-chunk WAVs while converting
/// ```
class AppStorage {
  AppStorage(this.root);

  final Directory root;

  static Future<AppStorage> open() async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'library'));
    await root.create(recursive: true);
    return AppStorage(root);
  }

  Directory docDir(String id) => Directory(p.join(root.path, id));
  String pdfPath(String id) => p.join(docDir(id).path, 'source.pdf');
  String audioPath(String id) => p.join(docDir(id).path, 'audio.wav');
  Directory chunkDir(String id) => Directory(p.join(docDir(id).path, 'chunks'));

  static Future<int> sizeOf(FileSystemEntity entity) async {
    if (entity is File) return await entity.exists() ? await entity.length() : 0;
    if (entity is! Directory || !await entity.exists()) return 0;
    var total = 0;
    await for (final e in entity.list(recursive: true, followLinks: false)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  Future<int> totalSize() => sizeOf(root);

  Future<int> documentSize(String id) => sizeOf(docDir(id));

  /// Bytes taken by audio (merged file plus any partial chunks).
  Future<int> audioSize(String id) async =>
      await sizeOf(File(audioPath(id))) + await sizeOf(chunkDir(id));

  Future<void> deleteChunks(String id) async {
    final dir = chunkDir(id);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Removes the audio and partial chunks; returns bytes freed.
  Future<int> deleteAudio(String id) async {
    final freed = await audioSize(id);
    final audio = File(audioPath(id));
    if (await audio.exists()) await audio.delete();
    await deleteChunks(id);
    return freed;
  }

  /// Removes everything for a document; returns bytes freed.
  Future<int> deleteDocument(String id) async {
    final dir = docDir(id);
    final freed = await sizeOf(dir);
    if (await dir.exists()) await dir.delete(recursive: true);
    return freed;
  }
}

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 || value >= 100 ? 0 : 1)} ${units[unit]}';
}
