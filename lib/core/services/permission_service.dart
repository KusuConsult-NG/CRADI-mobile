import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
import 'package:climate_app/core/l10n/l10n.dart';

class PermissionService {
  static final PermissionService _instance = PermissionService._internal();

  factory PermissionService() {
    return _instance;
  }

  PermissionService._internal();

  /// Check if a specific permission is granted
  Future<bool> isGranted(Permission permission) async {
    return await permission.isGranted;
  }

  /// Request a permission with a rational dialog if needed
  Future<bool> requestPermission({
    required BuildContext context,
    required Permission permission,
    required String title,
    required String rationale,
    required IconData icon,
  }) async {
    // 1. Check current status
    final status = await permission.status;

    if (status.isGranted) {
      return true;
    }

    if (status.isPermanentlyDenied) {
      if (context.mounted) {
        _showSettingsDialog(context, title, rationale);
      }
      return false;
    }

    // 2. Show Rationale Dialog BEFORE system prompt
    // This increases acceptance rate by explaining "Why"
    if (context.mounted) {
      final shouldProceed = await _showRationaleDialog(
        context,
        title,
        rationale,
        icon,
      );

      if (!shouldProceed) {
        return false;
      }
    }

    // 3. Request Permission
    final newStatus = await permission.request();
    return newStatus.isGranted;
  }

  /// Request Location Permission (Coarse + Fine)
  Future<bool> requestLocation(BuildContext context) async {
    // On Android, we might need to request locationWhenInUse first
    return await requestPermission(
      context: context,
      permission: Permission.location,
      title: context.l10n.permissionLocationTitle,
      rationale: context.l10n.permissionLocationRationale,
      icon: Icons.location_on_outlined,
    );
  }

  /// Request Notification Permission
  Future<bool> requestNotifications(BuildContext context) async {
    return await requestPermission(
      context: context,
      permission: Permission.notification,
      title: context.l10n.permissionNotificationsTitle,
      rationale: context.l10n.permissionNotificationsRationale,
      icon: Icons.notifications_active_outlined,
    );
  }

  /// Request Storage/Photos Permission
  Future<bool> requestPhotos(BuildContext context) async {
    final permission = Platform.isAndroid
        ? Permission.mediaLibrary
        : Permission.photos;
    // For Android 13+ (SDK 33), we might need Permission.photos instead of storage
    // But permission_handler handles mostly. Let's use specific logic if needed.

    return await requestPermission(
      context: context,
      permission: permission,
      title: context.l10n.permissionPhotosTitle,
      rationale: context.l10n.permissionPhotosRationale,
      icon: Icons.photo_library_outlined,
    );
  }

  Future<bool> _showRationaleDialog(
    BuildContext context,
    String title,
    String message,
    IconData icon,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            icon: Icon(icon, size: 48, color: AppColors.primaryRed),
            title: Text(
              title,
              style: GoogleFonts.lexend(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
              textAlign: TextAlign.center,
            ),
            content: Text(
              message,
              style: GoogleFonts.lexend(
                fontSize: 15,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            actions: [
              TextButton(
                onPressed: () => context.pop(false),
                child: Text(
                  context.l10n.permissionNotNow,
                  style: GoogleFonts.lexend(color: Colors.grey),
                ),
              ),
              FilledButton(
                onPressed: () => context.pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryRed,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  context.l10n.continueButton,
                  style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
                ),
              ),
            ],
            actionsAlignment: MainAxisAlignment.center,
          ),
        ) ??
        false;
  }

  void _showSettingsDialog(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(context.l10n.permissionSettingsBody(message)),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              context.pop();
              openAppSettings();
            },
            child: Text(context.l10n.offlineOpenSettings),
          ),
        ],
      ),
    );
  }
}
