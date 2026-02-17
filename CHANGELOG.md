# Changelog

All notable changes to this project will be documented in this file.

## [1.0.4+7] - 2026-02-15

### Added
- **Global Emergency Contacts**: Users can now see emergency contacts (Police, Fire, NEMA) added by Admins, regardless of who created them.
- **Dynamic Knowledge Base**: "Hazard Guides" now fetch real-time data from the Admin Portal instead of using hardcoded placeholders.
- **Admin Approval Gate**: New users are now redirected to a "Pending Approval" screen until verified by an Admin.
- **Role Sync**: User roles (Coordinator, Media, etc.) are now synced from the Admin Portal to the App.

### Changed
- **Configuration**: Extracted hardcoded Appwrite credentials to `lib/core/config/app_config.dart` for better security and maintainability.
- **Offline Mode**: Improved offline detection and manual toggle in Settings.
- **Versioning**: Bumped version code to 7 to support the new release.

### Fixed
- **Critical Bug**: Fixed an issue where "Emergency Contacts" were filtered by the current user ID, hiding global admin contacts.
- **Crash**: Fixed potential crash in Text-to-Speech when navigating away rapidly.
