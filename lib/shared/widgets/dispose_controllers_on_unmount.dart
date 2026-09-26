import 'package:flutter/widgets.dart';

/// Disposes [controllers] when the wrapped widget (typically a dialog's
/// content) is removed from the tree — i.e. after a dialog's exit animation —
/// so they are never used after disposal.
///
/// Create the controllers *outside* the dialog builder (the builder can run
/// again on rebuilds) and hand them to this widget.
class DisposeControllersOnUnmount extends StatefulWidget {
  const DisposeControllersOnUnmount({
    super.key,
    required this.controllers,
    required this.child,
  });

  final List<ChangeNotifier> controllers;
  final Widget child;

  @override
  State<DisposeControllersOnUnmount> createState() =>
      _DisposeControllersOnUnmountState();
}

class _DisposeControllersOnUnmountState
    extends State<DisposeControllersOnUnmount> {
  @override
  void dispose() {
    for (final c in widget.controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
