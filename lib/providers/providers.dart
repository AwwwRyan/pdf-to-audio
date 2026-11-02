import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_settings.dart';
import '../models/chunk.dart';
import '../models/document.dart';
import '../services/audio_handler.dart';
import '../services/conversion_service.dart';
import '../services/repository.dart';
import '../services/storage.dart';
import '../services/tts_synth.dart';

// Created in main() before runApp and injected via overrides.
final repositoryProvider =
    Provider<DocumentRepository>((ref) => throw UnimplementedError());
final storageProvider = Provider<AppStorage>((ref) => throw UnimplementedError());
final audioHandlerProvider =
    Provider<PlayerAudioHandler>((ref) => throw UnimplementedError());
final ttsProvider = Provider<TtsSynth>((ref) => throw UnimplementedError());
final conversionServiceProvider =
    Provider<ConversionService>((ref) => throw UnimplementedError());

final documentsProvider = StreamProvider<List<Document>>(
    (ref) => ref.watch(repositoryProvider).watchAll());

final documentProvider = Provider.family<Document?, String>((ref, id) {
  final docs = ref.watch(documentsProvider).value ?? const <Document>[];
  for (final d in docs) {
    if (d.id == id) return d;
  }
  return null;
});

/// Chunks for a ready document; refreshed when the document changes.
final chunksProvider = Provider.family<List<Chunk>, String>((ref, id) {
  ref.watch(documentProvider(id).select((d) => (d?.status, d?.chunkCount)));
  return ref.watch(repositoryProvider).chunks(id);
});

/// Total bytes on disk, recomputed only when files can have changed.
final storageUsageProvider = FutureProvider<int>((ref) {
  ref.watch(documentsProvider.select((docs) => docs.value
      ?.map((d) => '${d.id}:${d.status.name}:${d.audioPath}')
      .join('|')));
  return ref.watch(storageProvider).totalSize();
});

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(repositoryProvider).settings;

  Future<void> change(AppSettings Function(AppSettings) f) async {
    state = f(state);
    await ref.read(repositoryProvider).saveSettings(state);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

final packageInfoProvider =
    FutureProvider<PackageInfo>((ref) => PackageInfo.fromPlatform());

final voicesProvider =
    FutureProvider<List<TtsVoice>>((ref) => ref.watch(ttsProvider).voices());
