class AppSettings {
  const AppSettings({
    this.voiceName,
    this.voiceLocale,
    this.speechRate = 0.5,
    this.pitch = 1.0,
    this.readCodeBlocks = false,
    this.playbackSpeed = 1.0,
    this.showAllVoices = false,
  });

  /// Null means the engine's default voice.
  final String? voiceName;
  final String? voiceLocale;

  /// flutter_tts scale: 0.5 is normal speed on Android (it is doubled
  /// before reaching the engine).
  final double speechRate;
  final double pitch;
  final bool readCodeBlocks;
  final double playbackSpeed;
  final bool showAllVoices;

  AppSettings copyWith({
    String? voiceName,
    String? voiceLocale,
    bool clearVoice = false,
    double? speechRate,
    double? pitch,
    bool? readCodeBlocks,
    double? playbackSpeed,
    bool? showAllVoices,
  }) =>
      AppSettings(
        voiceName: clearVoice ? null : (voiceName ?? this.voiceName),
        voiceLocale: clearVoice ? null : (voiceLocale ?? this.voiceLocale),
        speechRate: speechRate ?? this.speechRate,
        pitch: pitch ?? this.pitch,
        readCodeBlocks: readCodeBlocks ?? this.readCodeBlocks,
        playbackSpeed: playbackSpeed ?? this.playbackSpeed,
        showAllVoices: showAllVoices ?? this.showAllVoices,
      );

  Map<String, dynamic> toMap() => {
        'voiceName': voiceName,
        'voiceLocale': voiceLocale,
        'speechRate': speechRate,
        'pitch': pitch,
        'readCodeBlocks': readCodeBlocks,
        'playbackSpeed': playbackSpeed,
        'showAllVoices': showAllVoices,
      };

  factory AppSettings.fromMap(Map<dynamic, dynamic>? m) {
    if (m == null) return const AppSettings();
    double d(String k, double fallback) => (m[k] as num?)?.toDouble() ?? fallback;
    return AppSettings(
      voiceName: m['voiceName'] as String?,
      voiceLocale: m['voiceLocale'] as String?,
      speechRate: d('speechRate', 0.5),
      pitch: d('pitch', 1.0),
      readCodeBlocks: (m['readCodeBlocks'] as bool?) ?? false,
      playbackSpeed: d('playbackSpeed', 1.0),
      showAllVoices: (m['showAllVoices'] as bool?) ?? false,
    );
  }
}
