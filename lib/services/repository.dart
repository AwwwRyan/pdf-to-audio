import 'package:hive_ce/hive_ce.dart';

import '../models/app_settings.dart';
import '../models/chunk.dart';
import '../models/document.dart';

/// Hive-backed library metadata. Chunks live in their own box keyed by
/// document id, so frequent progress/position writes stay small.
class DocumentRepository {
  DocumentRepository._(this._docs, this._chunks, this._settings);

  final Box<Document> _docs;
  final Box<List> _chunks;
  final Box<dynamic> _settings;

  static void registerAdapters() {
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(DocumentAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ChunkAdapter());
  }

  /// Call after Hive.init / Hive.initFlutter.
  static Future<DocumentRepository> open() async {
    registerAdapters();
    return DocumentRepository._(
      await Hive.openBox<Document>('documents'),
      await Hive.openBox<List>('chunks'),
      await Hive.openBox<dynamic>('settings'),
    );
  }

  List<Document> all() =>
      _docs.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Stream<List<Document>> watchAll() async* {
    yield all();
    await for (final _ in _docs.watch()) {
      yield all();
    }
  }

  Document? get(String id) => _docs.get(id);

  Future<void> put(Document doc) => _docs.put(doc.id, doc);

  /// Applies [change] to the stored document, if it still exists.
  Future<Document?> update(String id, Document Function(Document) change) async {
    final doc = _docs.get(id);
    if (doc == null) return null;
    final next = change(doc);
    await _docs.put(id, next);
    return next;
  }

  Future<void> savePosition(String id, Duration position) =>
      update(id, (d) => d.copyWith(lastPosition: position));

  List<Chunk> chunks(String id) => (_chunks.get(id) ?? const []).cast<Chunk>();

  Future<void> putChunks(String id, List<Chunk> chunks) => _chunks.put(id, chunks);

  Future<void> deleteChunks(String id) => _chunks.delete(id);

  Future<void> delete(String id) async {
    await _docs.delete(id);
    await _chunks.delete(id);
  }

  AppSettings get settings =>
      AppSettings.fromMap(_settings.get('app') as Map<dynamic, dynamic>?);

  Future<void> saveSettings(AppSettings s) => _settings.put('app', s.toMap());

  /// The document most recently opened in the player, so the widget and
  /// media buttons can resume it after the app was killed.
  String? get lastDocumentId => _settings.get('lastDocumentId') as String?;

  Future<void> setLastDocumentId(String? id) => id == null
      ? _settings.delete('lastDocumentId')
      : _settings.put('lastDocumentId', id);
}
