import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Maximum length of a dispute comment.
const int kDisputeCommentMaxLength = 500;

/// Asks for the (required) comment explaining a dispute. Returns the
/// trimmed comment, or null when cancelled. Every dispute entry point uses
/// it so staff always see why a report was disputed.
Future<String?> showDisputeCommentDialog(
  BuildContext context, {
  String initialText = '',
}) => showDialog<String>(
  context: context,
  builder: (_) => DisputeCommentDialog(initialText: initialText),
);

/// Dialog of [showDisputeCommentDialog]. Owns its text controller so it is
/// disposed only once the dialog route is gone.
class DisputeCommentDialog extends StatefulWidget {
  const DisputeCommentDialog({super.key, this.initialText = ''});

  final String initialText;

  @override
  State<DisputeCommentDialog> createState() => _DisputeCommentDialogState();
}

class _DisputeCommentDialogState extends State<DisputeCommentDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  bool _showError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _showError = true);
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Dispute report?',
        style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        maxLength: kDisputeCommentMaxLength,
        onChanged: (_) {
          if (_showError) setState(() => _showError = false);
        },
        decoration: InputDecoration(
          labelText: 'What is wrong with this report? (required)',
          border: const OutlineInputBorder(),
          errorText: _showError
              ? 'Please explain why you dispute this report.'
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Dispute', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }
}
