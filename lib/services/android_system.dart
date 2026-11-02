import 'package:flutter/services.dart';

/// Small Android hooks implemented in MainActivity.kt.
class AndroidSystem {
  static const _channel = MethodChannel('pdf_listener/system');

  /// Opens Android's text-to-speech settings (voice data downloads).
  static Future<void> openTtsSettings() => _channel.invokeMethod<void>('openTtsSettings');

  /// Asks for the Android 13+ notification permission that the playback
  /// notification needs. No-op when already granted or on older Android.
  static Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod<void>('requestNotificationPermission');
    } on Object {
      // Not available (tests, or no activity attached); playback still works.
    }
  }
}
