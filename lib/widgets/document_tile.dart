import 'package:flutter/material.dart';

import '../models/document.dart';
import 'format.dart';

enum DocAction { rename, reconvert, cancel, deleteAudio, deleteDocument }

extension DocActionLabel on DocAction {
  String get label => switch (this) {
        DocAction.rename => 'Rename…',
        DocAction.reconvert => 'Reconvert…',
        DocAction.cancel => 'Cancel conversion',
        DocAction.deleteAudio => 'Delete audio',
        DocAction.deleteDocument => 'Delete document',
      };

  IconData get icon => switch (this) {
        DocAction.rename => Icons.edit_outlined,
        DocAction.reconvert => Icons.refresh,
        DocAction.cancel => Icons.stop_circle_outlined,
        DocAction.deleteAudio => Icons.music_off_outlined,
        DocAction.deleteDocument => Icons.delete_outline,
      };
}

List<DocAction> actionsFor(Document d) => [
      DocAction.rename,
      if (!d.isBusy) DocAction.reconvert,
      if (d.isBusy) DocAction.cancel,
      if (d.audioPath != null || d.status == DocStatus.failed) DocAction.deleteAudio,
      DocAction.deleteDocument,
    ];

class DocumentTile extends StatelessWidget {
  const DocumentTile({
    super.key,
    required this.doc,
    required this.onTap,
    required this.onAction,
  });

  final Document doc;
  final VoidCallback onTap;
  final ValueChanged<DocAction> onAction;

  Future<void> _showSheet(BuildContext context) async {
    final action = await showModalBottomSheet<DocAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final a in actionsFor(doc))
            ListTile(
              leading: Icon(a.icon),
              title: Text(a.label),
              onTap: () => Navigator.pop(ctx, a),
            ),
        ]),
      ),
    );
    if (action != null) onAction(action);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final (String status, Color? color) = switch (doc.status) {
      _ when doc.needsReconversion => ('Made with an older version — tap to reconvert', scheme.tertiary),
      DocStatus.queued => ('Waiting to convert…', null),
      DocStatus.extracting => ('Reading text…', null),
      DocStatus.converting => ('Converting ${(doc.progress * 100).floor()}%', null),
      DocStatus.ready => (
          '${formatDurationShort(doc.totalDuration ?? Duration.zero)}'
              ' · ${(doc.listenedFraction * 100).round()}% listened',
          null
        ),
      DocStatus.failed => ('Failed — tap for details', scheme.error),
      DocStatus.idle => ('No audio — tap to convert', null),
    };
    final pages = doc.startPage == 1 && doc.endPage == doc.pageCount
        ? '${doc.pageCount} pages'
        : 'Pages ${doc.startPage}–${doc.endPage} of ${doc.pageCount}';

    return InkWell(
      onTap: onTap,
      onLongPress: () => _showSheet(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
        child: Row(children: [
          Icon(
            doc.isPlayable ? Icons.headphones : Icons.picture_as_pdf_outlined,
            color: scheme.primary,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(doc.title,
                  style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('$status · $pages',
                  style: text.bodySmall?.copyWith(color: color ?? scheme.onSurfaceVariant)),
              if (doc.isBusy) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: doc.status == DocStatus.converting ? doc.progress : null,
                  borderRadius: BorderRadius.circular(4),
                ),
              ] else if (doc.isPlayable && doc.listenedFraction > 0) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: doc.listenedFraction,
                  minHeight: 2,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ],
            ]),
          ),
          PopupMenuButton<DocAction>(
            tooltip: 'More',
            onSelected: onAction,
            itemBuilder: (_) => [
              for (final a in actionsFor(doc))
                PopupMenuItem(value: a, child: Text(a.label)),
            ],
          ),
        ]),
      ),
    );
  }
}
