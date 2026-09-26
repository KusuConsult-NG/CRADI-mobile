import 'package:climate_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:climate_app/core/l10n/l10n.dart';

/// Full-screen message with a way out, used for unknown routes and for deep
/// links whose target could not be loaded.
class RouteStatusScreen extends StatelessWidget {
  const RouteStatusScreen({
    super.key,
    required String this.title,
    required String this.message,
    this.icon = Icons.explore_off_outlined,
    this.homeLocation = '/dashboard',
    this.homeLabel,
    this.onRetry,
  });

  /// Screen shown by the router's errorBuilder.
  const RouteStatusScreen.notFound({super.key})
    : title = null,
      message = null,
      icon = Icons.explore_off_outlined,
      homeLocation = '/dashboard',
      homeLabel = null,
      onRetry = null;

  /// Null only for [RouteStatusScreen.notFound] (localised defaults).
  final String? title;
  final String? message;
  final IconData icon;
  final String homeLocation;

  /// Label of the home button; defaults to "Go home".
  final String? homeLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          tooltip: context.l10n.back,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(homeLocation),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 72, color: Colors.grey.shade400),
              const SizedBox(height: 24),
              Text(
                title ?? context.l10n.routeNotFoundTitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.lexend(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message ?? context.l10n.routeNotFoundBody,
                textAlign: TextAlign.center,
                style: GoogleFonts.lexend(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 32),
              if (onRetry != null) ...[
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(context.l10n.routeTryAgain),
                ),
                const SizedBox(height: 12),
              ],
              ElevatedButton.icon(
                onPressed: () => context.go(homeLocation),
                icon: const Icon(Icons.home_outlined),
                label: Text(homeLabel ?? context.l10n.routeGoHome),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryRed,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loads a record by id, then builds [builder] with it. Shows a spinner
/// while loading and a [RouteStatusScreen] when it is missing or failed.
class DeepLinkLoader<T> extends StatefulWidget {
  const DeepLinkLoader({
    super.key,
    required this.load,
    required this.builder,
    required this.notFoundTitle,
    required this.fallbackLocation,
    required this.fallbackLabel,
  });

  final Future<T?> Function() load;
  final Widget Function(BuildContext context, T value) builder;
  final String notFoundTitle;
  final String fallbackLocation;
  final String fallbackLabel;

  @override
  State<DeepLinkLoader<T>> createState() => _DeepLinkLoaderState<T>();
}

class _DeepLinkLoaderState<T> extends State<DeepLinkLoader<T>> {
  late Future<T?> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final value = snap.data;
        if (value != null) return widget.builder(context, value);
        final failed = snap.hasError;
        return RouteStatusScreen(
          title: failed
              ? context.l10n.routeLoadFailedTitle
              : widget.notFoundTitle,
          message: failed
              ? context.l10n.routeLoadFailedBody
              : context.l10n.routeMissingBody,
          icon: failed ? Icons.cloud_off : Icons.search_off,
          homeLocation: widget.fallbackLocation,
          homeLabel: widget.fallbackLabel,
          onRetry: failed
              ? () => setState(() => _future = widget.load())
              : null,
        );
      },
    );
  }
}
