import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/app_settings.dart';

class TtsException implements Exception {
  TtsException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TtsVoice {
  const TtsVoice({
    required this.name,
    required this.locale,
    required this.quality,
    required this.networkRequired,
  });

  final String name;

  /// BCP-47 tag, e.g. "en-US".
  final String locale;
  final String quality;
  final bool networkRequired;
}

/// Wraps the Android system TTS engine via flutter_tts.
///
/// flutter_tts's `awaitSynthCompletion(true)` never completes the pending
/// call when the engine reports an error (4.2.5, Android), so this class
/// waits on the completion/error handlers itself, with a timeout.
/// All flutter_tts instances share one method channel, so this must be the
/// only instance in the app.
class TtsSynth {
  final FlutterTts _tts = FlutterTts();
  static const _system = MethodChannel('pdf_listener/system');
  Completer<void>? _pending;
  bool _initialised = false;

  Future<void> _init() async {
    if (_initialised) return;
    _initialised = true;
    await _tts.awaitSynthCompletion(false);
    await _tts.awaitSpeakCompletion(false);
    _tts.setCompletionHandler(() {
      final p = _pending;
      if (p != null && !p.isCompleted) p.complete();
    });
    _tts.setErrorHandler((message) {
      final p = _pending;
      if (p != null && !p.isCompleted) p.completeError(TtsException('$message'));
    });
  }

  Future<List<TtsVoice>> voices() async {
    await _init();
    final raw = await _tts.getVoices as List<dynamic>? ?? const [];
    final voices = [
      for (final v in raw.cast<Map<dynamic, dynamic>>())
        TtsVoice(
          name: '${v['name']}',
          locale: '${v['locale']}',
          quality: '${v['quality'] ?? ''}',
          networkRequired: '${v['network_required']}' == '1',
        ),
    ]..sort((a, b) => a.locale == b.locale
        ? a.name.compareTo(b.name)
        : a.locale.compareTo(b.locale));
    return voices;
  }

  Future<void> configure(AppSettings s) async {
    await _init();
    if (s.voiceName != null && s.voiceLocale != null) {
      await _tts.setVoice({'name': s.voiceName!, 'locale': s.voiceLocale!});
    }
    await _tts.setSpeechRate(s.speechRate);
    await _tts.setPitch(s.pitch);
    await _tts.setVolume(1.0);
  }

  /// Synthesises [text] into a WAV at the absolute [path] and waits until
  /// the engine has finished writing it.
  Future<void> synthesizeToFile(String text, String path) async {
    await _init();
    final completer = Completer<void>();
    _pending = completer;
    try {
      await _tts.synthesizeToFile(text, path, true);
      final timeout = Duration(seconds: 30 + text.length ~/ 10);
      await completer.future.timeout(timeout, onTimeout: () async {
        await _tts.stop();
        throw TtsException('Text-to-speech timed out');
      });
    } finally {
      if (identical(_pending, completer)) _pending = null;
    }
  }

  /// Speaks a short sample with the given settings (settings screen preview).
  Future<void> preview(String text, AppSettings s) async {
    await configure(s);
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
    final p = _pending;
    if (p != null && !p.isCompleted) p.completeError(TtsException('Stopped'));
  }

  /// Opens Android's text-to-speech settings (voice data downloads).
  static Future<void> openSystemTtsSettings() =>
      _system.invokeMethod<void>('openTtsSettings');
}
