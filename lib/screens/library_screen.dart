import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/document.dart';
import '../constants/app_info.dart';
import '../providers/providers.dart';
import '../services/pdf_extractor.dart';
import '../services/storage.dart';
import '../widgets/document_tile.dart';
import '../widgets/page_range_dialog.dart';
import 'player_screen.dart';
import 'settings_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _importing = false;

  void _snack(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _import() async {
    final picked =
        await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf']);
    if (picked == null || !mounted) return;
    final storage = ref.read(storageProvider);
    final id = const Uuid().v4();
    final pdfPath = storage.pdfPath(id);
    setState(() => _importing = true);
    int pageCount;
    try {
      await storage.docDir(id).create(recursive: true);
      final sink = File(pdfPath).openWrite();
      await sink.addStream(picked.readAsByteStream());
      await sink.close();
      pageCount = await PdfExtractor.pageCount(pdfPath);
    } on Object {
      await storage.deleteDocument(id);
      if (mounted) {
        setState(() => _importing = false);
        _snack("Couldn't open this PDF. It may be damaged or password-protected.");
      }
      return;
    }
    if (!mounted) return;
    setState(() => _importing = false);

    final title = p.basenameWithoutExtension(picked.name);
    final range = await showPageRangeDialog(context, title: title, pageCount: pageCount);
    if (range == null) {
      await storage.deleteDocument(id);
      return;
    }
    await ref.read(repositoryProvider).put(Document(
          id: id,
          title: title,
          originalFileName: picked.name,
          pdfPath: pdfPath,
          pageCount: pageCount,
          startPage: range.$1,
          endPage: range.$2,
          createdAt: DateTime.now(),
        ));
    await ref.read(conversionServiceProvider).enqueue(id);
  }

  Future<void> _onTap(Document doc) async {
    if (doc.isPlayable) {
      await Navigator.push(
          context, MaterialPageRoute(builder: (_) => PlayerScreen(documentId: doc.id)));
    } else if (doc.needsReconversion) {
      final ok = await _confirm(
        title: 'Reconvert "${doc.title}"?',
        body: 'This audio was made with an older version of the text cleanup. '
            'Reconverting gives better paragraphs, headings and follow-along text.',
        action: 'Reconvert',
      );
      if (ok) await _reconvert(doc, askRange: false);
    } else if (doc.status == DocStatus.failed) {
      final ok = await _confirm(
        title: 'Conversion failed',
        body: doc.error ?? 'Unknown error',
        action: 'Retry',
      );
      if (ok) await ref.read(conversionServiceProvider).enqueue(doc.id);
    } else if (doc.status == DocStatus.idle) {
      await _reconvert(doc, askRange: true);
    }
  }

  Future<void> _reconvert(Document doc, {required bool askRange}) async {
    var (start, end) = (doc.startPage, doc.endPage);
    if (askRange) {
      final range = await showPageRangeDialog(context,
          title: doc.title, pageCount: doc.pageCount, start: start, end: end);
      if (range == null) return;
      (start, end) = range;
    }
    await ref.read(audioHandlerProvider).closeIfCurrent(doc.id);
    final conversion = ref.read(conversionServiceProvider);
    await conversion.reset(doc.id);
    await ref
        .read(repositoryProvider)
        .update(doc.id, (d) => d.copyWith(startPage: start, endPage: end));
    await conversion.enqueue(doc.id);
  }

  Future<void> _onAction(Document doc, DocAction action) async {
    final storage = ref.read(storageProvider);
    final conversion = ref.read(conversionServiceProvider);
    final handler = ref.read(audioHandlerProvider);
    switch (action) {
      case DocAction.reconvert:
        await _reconvert(doc, askRange: true);
      case DocAction.cancel:
        await conversion.reset(doc.id);
        _snack('Conversion cancelled');
      case DocAction.deleteAudio:
        final size = await storage.audioSize(doc.id);
        final ok = await _confirm(
          title: 'Delete audio?',
          body: 'Frees ${formatBytes(size)}. "${doc.title}" stays in your library '
              'and can be converted again.',
          action: 'Delete audio',
          destructive: true,
        );
        if (!ok) return;
        await handler.closeIfCurrent(doc.id);
        final freed = await conversion.reset(doc.id);
        _snack('Freed ${formatBytes(freed)}');
      case DocAction.deleteDocument:
        final size = await storage.documentSize(doc.id);
        final ok = await _confirm(
          title: 'Delete document?',
          body: 'Removes "${doc.title}", its PDF copy and audio. '
              'Frees ${formatBytes(size)}.',
          action: 'Delete',
          destructive: true,
        );
        if (!ok) return;
        await handler.closeIfCurrent(doc.id);
        await conversion.cancel(doc.id);
        await ref.read(repositoryProvider).delete(doc.id);
        final freed = await storage.deleteDocument(doc.id);
        _snack('Freed ${formatBytes(freed)}');
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) async {
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error, foregroundColor: scheme.onError)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final docs = ref.watch(documentsProvider);
    final usage = ref.watch(storageUsageProvider).value;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(kAppName),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: Column(children: [
        if (_importing) const LinearProgressIndicator(),
        Expanded(
          child: docs.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (list) => list.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Import a text-based PDF to turn it into audio.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
                    itemBuilder: (_, i) => DocumentTile(
                      doc: list[i],
                      onTap: () => _onTap(list[i]),
                      onAction: (a) => _onAction(list[i], a),
                    ),
                  ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                usage == null ? ' ' : 'Storage used: ${formatBytes(usage)}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _import,
        icon: const Icon(Icons.add),
        label: const Text('Import PDF'),
      ),
    );
  }
}
