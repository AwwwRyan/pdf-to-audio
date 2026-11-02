import 'package:flutter/material.dart';

/// Asks for a new document title. Returns null on cancel or an unchanged
/// / empty name.
Future<String?> showRenameDialog(BuildContext context, String current) =>
    showDialog<String>(context: context, builder: (_) => _RenameDialog(current));

class _RenameDialog extends StatefulWidget {
  const _RenameDialog(this.current);

  final String current;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.current)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.current.length);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    Navigator.pop(context, name.isEmpty || name == widget.current ? null : name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _submit, child: const Text('Save')),
        ],
      );
}
