import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chunk.dart';
import '../providers/providers.dart';
import '../services/android_system.dart';
import '../services/audio_handler.dart';
import '../services/chunk_lookup.dart';
import '../widgets/current_text_panel.dart';
import '../widgets/format.dart';
import '../widgets/study_prompt_row.dart';

const _speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
const _skips = [-30, -10, -5, 5, 10, 30];

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.documentId});

  final String documentId;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final PlayerAudioHandler _handler = ref.read(audioHandlerProvider);
  late Future<void> _loading;
  List<Chunk> _chunks = const [];
  List<Duration> _starts = const [];
  double? _dragValue;

  @override
  void initState() {
    super.initState();
    final doc = ref.read(documentProvider(widget.documentId))!;
    _loading = _handler.openDocument(doc, speed: ref.read(settingsProvider).playbackSpeed);
    // The lock-screen / notification controls need this on Android 13+.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => AndroidSystem.requestNotificationPermission());
  }

  @override
  void dispose() {
    _handler.savePosition();
    super.dispose();
  }

  void _setChunks(List<Chunk> chunks) {
    if (identical(chunks, _chunks)) return;
    _chunks = chunks;
    _starts = [for (final c in chunks) c.startOffset];
  }

  Future<void> _setSpeed(double speed) async {
    await _handler.setSpeed(speed);
    await ref.read(settingsProvider.notifier).change((s) => s.copyWith(playbackSpeed: speed));
  }

  @override
  Widget build(BuildContext context) {
    final doc = ref.watch(documentProvider(widget.documentId));
    if (doc == null) {
      return const Scaffold(body: Center(child: Text('This document was deleted.')));
    }
    _setChunks(ref.watch(chunksProvider(widget.documentId)));
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(),
      body: FutureBuilder<void>(
        future: _loading,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text("Couldn't load the audio: ${snap.error}"));
          }
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return StreamBuilder<Duration>(
            stream: _handler.positionStream,
            initialData: _handler.position,
            builder: (context, posSnap) {
              final position = posSnap.data ?? Duration.zero;
              final total = _handler.duration;
              final index = chunkIndexAt(_starts, position);
              final page = index >= 0 ? _chunks[index].pageNumber : doc.startPage;

              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(doc.title,
                        style: text.headlineSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text('Page $page of ${doc.pageCount}',
                        style: text.titleSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ]),
                ),
                const SizedBox(height: 8),
                _seekBar(position, total),
                _controls(),
                _speedSelector(),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: StudyPromptRow(),
                ),
                Expanded(
                  child: CurrentTextPanel(
                    chunks: _chunks,
                    currentIndex: index,
                    onSeek: (start) async {
                      await _handler.seek(start);
                      if (!_handler.playing) await _handler.play();
                    },
                  ),
                ),
              ]);
            },
          );
        },
      ),
    );
  }

  Widget _seekBar(Duration position, Duration total) {
    final maxMs = total.inMilliseconds.toDouble();
    final valueMs = (_dragValue ?? position.inMilliseconds.toDouble()).clamp(0.0, maxMs);
    final shown = Duration(milliseconds: valueMs.round());
    final style = Theme.of(context).textTheme.labelMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(children: [
        Slider(
          value: maxMs <= 0 ? 0 : valueMs,
          max: maxMs <= 0 ? 1 : maxMs,
          onChanged: maxMs <= 0 ? null : (v) => setState(() => _dragValue = v),
          onChangeEnd: (v) async {
            await _handler.seek(Duration(milliseconds: v.round()));
            setState(() => _dragValue = null);
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(formatClock(shown), style: style),
            Text('-${formatClock(total - shown)}', style: style),
          ]),
        ),
      ]),
    );
  }

  Widget _controls() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(children: [
        StreamBuilder<bool>(
          stream: _handler.playingStream,
          initialData: _handler.playing,
          builder: (context, snap) {
            final playing = snap.data ?? false;
            return SizedBox(
              width: 88,
              height: 88,
              child: IconButton.filled(
                tooltip: playing ? 'Pause' : 'Play',
                iconSize: 48,
                onPressed: playing ? _handler.pause : _handler.play,
                icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Row(children: [
          for (final s in _skips) ...[
            Expanded(
              child: SizedBox(
                height: 56,
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor: s < 0
                        ? scheme.surfaceContainerHigh
                        : scheme.secondaryContainer,
                  ),
                  onPressed: () => _handler.seekBy(Duration(seconds: s)),
                  child: Text(s < 0 ? '−${-s}' : '+$s',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
            if (s != _skips.last) SizedBox(width: s == -5 ? 12 : 6),
          ],
        ]),
      ]),
    );
  }

  Widget _speedSelector() => StreamBuilder<double>(
        stream: _handler.speedStream,
        initialData: _handler.speed,
        builder: (context, snap) {
          final current = snap.data ?? 1.0;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in _speeds)
                  ChoiceChip(
                    label: Text('${s}x'.replaceFirst('.0x', 'x')),
                    selected: (current - s).abs() < 0.01,
                    showCheckmark: false,
                    onSelected: (_) => _setSpeed(s),
                  ),
              ],
            ),
          );
        },
      );
}
