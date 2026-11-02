import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Asks for a 1-based inclusive page range. Returns null on cancel.
Future<(int, int)?> showPageRangeDialog(
  BuildContext context, {
  required String title,
  required int pageCount,
  int? start,
  int? end,
  String confirmLabel = 'Convert',
}) =>
    showDialog<(int, int)>(
      context: context,
      builder: (_) => _PageRangeDialog(
        title: title,
        pageCount: pageCount,
        start: start ?? 1,
        end: end ?? pageCount,
        confirmLabel: confirmLabel,
      ),
    );

class _PageRangeDialog extends StatefulWidget {
  const _PageRangeDialog({
    required this.title,
    required this.pageCount,
    required this.start,
    required this.end,
    required this.confirmLabel,
  });

  final String title;
  final int pageCount;
  final int start;
  final int end;
  final String confirmLabel;

  @override
  State<_PageRangeDialog> createState() => _PageRangeDialogState();
}

class _PageRangeDialogState extends State<_PageRangeDialog> {
  late final _start = TextEditingController(text: '${widget.start}');
  late final _end = TextEditingController(text: '${widget.end}');
  String? _error;

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  void _submit() {
    final s = int.tryParse(_start.text);
    final e = int.tryParse(_end.text);
    final n = widget.pageCount;
    if (s == null || e == null || s < 1 || e > n || s > e) {
      setState(() => _error = 'Enter pages between 1 and $n, start ≤ end');
      return;
    }
    Navigator.pop(context, (s, e));
  }

  Widget _field(TextEditingController c, String label) => Expanded(
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          onSubmitted: (_) => _submit(),
        ),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.pageCount} pages'),
            const SizedBox(height: 16),
            Row(children: [
              _field(_start, 'From page'),
              const SizedBox(width: 12),
              _field(_end, 'To page'),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
        ],
      );
}
