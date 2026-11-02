import 'package:flutter/material.dart';

import '../models/chunk.dart';

/// The chunk being spoken, with its neighbours dimmed for context. Tapping
/// a chunk seeks to its start.
class CurrentTextPanel extends StatefulWidget {
  const CurrentTextPanel({
    super.key,
    required this.chunks,
    required this.currentIndex,
    required this.onSeek,
  });

  final List<Chunk> chunks;
  final int currentIndex;
  final ValueChanged<Duration> onSeek;

  @override
  State<CurrentTextPanel> createState() => _CurrentTextPanelState();
}

class _CurrentTextPanelState extends State<CurrentTextPanel> {
  final _scroll = ScrollController();
  final _currentKey = GlobalKey();

  @override
  void didUpdateWidget(CurrentTextPanel old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _currentKey.currentContext;
        if (ctx != null && ctx.mounted) {
          Scrollable.ensureVisible(ctx,
              alignment: 0.05, duration: const Duration(milliseconds: 250));
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _item(BuildContext context, int i) {
    final chunk = widget.chunks[i];
    final scheme = Theme.of(context).colorScheme;
    final isCurrent = i == widget.currentIndex;
    final base = Theme.of(context).textTheme.bodyLarge!;
    final style = base.copyWith(
      height: 1.45,
      fontWeight: chunk.isHeading ? FontWeight.w700 : null,
      color: isCurrent ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.4),
    );
    return Padding(
      key: isCurrent ? _currentKey : null,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: isCurrent ? scheme.secondaryContainer.withValues(alpha: 0.6) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => widget.onSeek(chunk.startOffset),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(chunk.text, style: style),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.chunks.length;
    if (n == 0) return const SizedBox.shrink();
    final i = widget.currentIndex.clamp(0, n - 1);
    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (i > 0) _item(context, i - 1),
          _item(context, i),
          if (i + 1 < n) _item(context, i + 1),
        ],
      ),
    );
  }
}
