import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_info.dart';
import '../providers/providers.dart';
import '../services/android_system.dart';
import '../services/tts_synth.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  /// "en_US" / "en-US" → "en-us".
  static String _norm(String tag) => tag.replaceAll('_', '-').toLowerCase();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final voices = ref.watch(voicesProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final deviceLocale = _norm(Platform.localeName.split('.').first);

    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(title, style: text.titleSmall?.copyWith(color: scheme.primary)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          section('Speech (applied when converting)'),
          ListTile(
            title: const Text('Speech rate'),
            subtitle: Slider(
              value: settings.speechRate,
              min: 0.25,
              max: 1.0,
              divisions: 15,
              label: '${(settings.speechRate * 2).toStringAsFixed(1)}x',
              onChanged: (v) => notifier.change((s) => s.copyWith(speechRate: v)),
            ),
            trailing: Text('${(settings.speechRate * 2).toStringAsFixed(1)}x'),
          ),
          ListTile(
            title: const Text('Pitch'),
            subtitle: Slider(
              value: settings.pitch,
              min: 0.5,
              max: 2.0,
              divisions: 15,
              label: settings.pitch.toStringAsFixed(1),
              onChanged: (v) => notifier.change((s) => s.copyWith(pitch: v)),
            ),
            trailing: Text(settings.pitch.toStringAsFixed(1)),
          ),
          SwitchListTile(
            title: const Text('Read code blocks'),
            subtitle: const Text('Off: code is replaced with "Code example skipped."'),
            value: settings.readCodeBlocks,
            onChanged: (v) => notifier.change((s) => s.copyWith(readCodeBlocks: v)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.record_voice_over_outlined),
                label: const Text('Preview voice'),
                onPressed: () => ref.read(ttsProvider).preview(
                    'This is how your documents will sound.', settings),
              ),
            ),
          ),
          section('Voice'),
          SwitchListTile(
            title: const Text('Show all voices'),
            subtitle: Text('Otherwise only $deviceLocale voices that work offline'),
            value: settings.showAllVoices,
            onChanged: (v) => notifier.change((s) => s.copyWith(showAllVoices: v)),
          ),
          ...voices.when(
            loading: () => const [
              Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            ],
            error: (e, _) => [ListTile(title: Text("Couldn't list voices: $e"))],
            data: (all) {
              final language = deviceLocale.split('-').first;
              final shown = settings.showAllVoices
                  ? all
                  : all.where((v) {
                      final l = _norm(v.locale);
                      return !v.networkRequired &&
                          (l == deviceLocale || l.split('-').first == language);
                    }).toList();
              final selected = settings.voiceName;
              return [
                RadioGroup<String?>(
                  groupValue: selected,
                  onChanged: (name) {
                    final v = shown.where((v) => v.name == name).firstOrNull;
                    notifier.change((s) => v == null
                        ? s.copyWith(clearVoice: true)
                        : s.copyWith(voiceName: v.name, voiceLocale: v.locale));
                  },
                  child: Column(children: [
                    const RadioListTile<String?>(
                      value: null,
                      title: Text('System default'),
                    ),
                    for (final v in shown) _voiceTile(v),
                  ]),
                ),
                if (shown.isEmpty)
                  const ListTile(
                    title: Text('No offline voices for your language'),
                    subtitle: Text('Install voice data below, or turn on "Show all voices".'),
                  ),
              ];
            },
          ),
          section('Offline voices'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '$kAppName uses your phone\'s built-in text-to-speech engine and works '
              'fully offline once voice data is installed. To add or update voices: open '
              'Text-to-speech settings, tap the gear next to your engine (e.g. Speech '
              'Recognition & Synthesis from Google), choose "Install voice data", and '
              'download your language. Then come back here and pick a voice.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open text-to-speech settings'),
                onPressed: () async {
                  try {
                    await AndroidSystem.openTtsSettings();
                  } on Object {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text("Couldn't open system settings")));
                    }
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextButton(
              onPressed: () => ref.invalidate(voicesProvider),
              child: const Text('Refresh voice list'),
            ),
          ),
          section('About'),
          AboutListTile(
            icon: const Icon(Icons.info_outline),
            applicationName: kAppName,
            applicationVersion: switch (ref.watch(packageInfoProvider).value) {
              final info? => 'Version ${info.version} (${info.buildNumber})',
              null => null,
            },
            applicationIcon: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset('assets/icon/icon_192.png', width: 56, height: 56),
            ),
            applicationLegalese: '$kAppTagline\n\nAll conversion and playback happen on '
                'this device. No data leaves your phone.\n\n'
                'App icon based on Lucide "book-headphones" (ISC licence).',
            aboutBoxChildren: const [
              SizedBox(height: 12),
              SelectableText('github.com/AwwwRyan/pdf-to-audio'),
            ],
            child: const Text('About $kAppName'),
          ),
        ],
      ),
    );
  }

  Widget _voiceTile(TtsVoice v) => RadioListTile<String?>(
        value: v.name,
        title: Text(v.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text([
          v.locale,
          if (v.quality.isNotEmpty) '${v.quality} quality',
          if (v.networkRequired) 'needs internet',
        ].join(' · ')),
      );
}
