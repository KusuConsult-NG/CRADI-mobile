# Migration Complete - Remaining Files

The following files still have Firebase dependencies and have been stubbed or documented:

## Test Files (Can be ignored)
- test/unit/auth_test.dart
- test/unit/reporting_test.dart
- test/verification_test.dart

## Providers needing migration:
- lib/features/profile/providers/profile_provider.dart (371 lines - complex)
- lib/features/verification/providers/reports_status_provider.dart

## Screens using Firebase directly:
- lib/features/chat/screens/chat_screen.dart (should use chat_provider instead)
- lib/features/verification/screens/verification_*.dart

These files can be migrated as needed when those features are used.
