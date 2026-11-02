import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'constants/app_info.dart';
import 'providers/providers.dart';
import 'screens/library_screen.dart';
import 'services/audio_handler.dart';
import 'services/conversion_service.dart';
import 'services/repository.dart';
import 'services/storage.dart';
import 'services/tts_synth.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The app icon is derived from Lucide's "book-headphones" glyph.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
        ['Lucide icons'], await rootBundle.loadString('assets/licenses/lucide.txt'));
  });
  await Hive.initFlutter();
  final repo = await DocumentRepository.open();
  final storage = await AppStorage.open();
  final tts = TtsSynth();
  final handler = await AudioService.init(
    builder: () => PlayerAudioHandler(repo),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.awwwryan.acchasunno.playback',
      androidNotificationChannelName: 'Playback',
      fastForwardInterval: skipInterval,
      rewindInterval: skipInterval,
      androidNotificationIcon: 'drawable/ic_stat_accha_sunno',
    ),
  );
  final conversion = ConversionService(repo, storage, tts);

  runApp(ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      storageProvider.overrideWithValue(storage),
      ttsProvider.overrideWithValue(tts),
      audioHandlerProvider.overrideWithValue(handler),
      conversionServiceProvider.overrideWithValue(conversion),
    ],
    child: const AcchaSunnoApp(),
  ));
  unawaited(conversion.resumeInterrupted());
}

class AcchaSunnoApp extends StatelessWidget {
  const AcchaSunnoApp({super.key});

  static const _seed = Color(0xFF3F6E8C);

  ThemeData _theme(Brightness brightness) => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: brightness),
        useMaterial3: true,
      );

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: kAppName,
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: const LibraryScreen(),
      );
}
