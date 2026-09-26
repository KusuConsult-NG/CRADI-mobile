import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Shows the reason for a sign-out the user did not ask for (account
/// disabled or deleted by an administrator) as a snack bar.
///
/// Sits in `MaterialApp.builder`, below the app's [ScaffoldMessenger] and
/// [Localizations], so the message is shown on whatever screen the router
/// lands on after the sign-out.
class SignOutNoticeListener extends StatefulWidget {
  const SignOutNoticeListener({super.key, required this.child});

  final Widget child;

  @override
  State<SignOutNoticeListener> createState() => _SignOutNoticeListenerState();
}

class _SignOutNoticeListenerState extends State<SignOutNoticeListener> {
  AuthProvider? _auth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    if (!identical(auth, _auth)) {
      _auth?.removeListener(_onAuthChanged);
      _auth = auth..addListener(_onAuthChanged);
      _onAuthChanged();
    }
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    final auth = _auth;
    // Wait until the sign-out has completed.
    if (auth == null || auth.isAuthenticated) return;
    final notice = auth.takeSignOutNotice();
    if (notice == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(notice(context.l10n)),
          duration: const Duration(seconds: 8),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
