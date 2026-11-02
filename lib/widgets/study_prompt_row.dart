import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/prompts.dart';

/// One-line, tap-to-copy study prompt shown on the player.
class StudyPromptRow extends StatelessWidget {
  const StudyPromptRow({super.key});

  static const _radius = BorderRadius.all(Radius.circular(12));

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: kStudyReferencesPrompt));
    await HapticFeedback.lightImpact();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Prompt copied'),
        duration: Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    return Semantics(
      label: 'Copy study references prompt',
      button: true,
      excludeSemantics: true,
      onTap: () => _copy(context),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: _radius,
        child: InkWell(
          borderRadius: _radius,
          onTap: () => _copy(context),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      kStudyReferencesPrompt,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: muted),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.copy_rounded, size: 20, color: muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
