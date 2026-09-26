import 'package:climate_app/core/services/remote_config_service.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Replaces the whole app with an "update required" screen while this
/// build is older than the server's `app_min_version` (app_settings).
///
/// Used as MaterialApp.builder's wrapper rather than a dialog, so router
/// redirects cannot dismiss it.
class ForceUpdateGate extends StatelessWidget {
  const ForceUpdateGate({super.key, required this.child, this.config});

  final Widget child;

  /// Defaults to the app-wide [RemoteConfigService].
  final RemoteConfigService? config;

  @override
  Widget build(BuildContext context) {
    final cfg = config ?? RemoteConfigService();
    return ValueListenableBuilder<bool>(
      valueListenable: cfg.updateRequired,
      builder: (context, required, _) {
        if (!required) return child;
        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.system_update,
                      size: 72,
                      color: AppColors.primaryRed,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Update required',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(cfg.appMinVersionMessage, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(
                      'Minimum version: ${cfg.appMinVersion}',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton(
                      onPressed: () => cfg.refresh(force: true),
                      child: const Text('Check again'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
