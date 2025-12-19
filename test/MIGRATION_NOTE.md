# Test Files - Temporarily Disabled

This directory contains test files that need to be updated for Appwrite.

## Status

All tests are currently commented out because they reference Firebase constructors 
that no longer exist after the migration to Appwrite.

## To Re-enable Tests

Update the following files to use Appwrite instead of Firebase:

1. `unit/reporting_test.dart` - Remove Firebase constructor parameters
2. `unit/auth_test.dart` - Update to use Appwrite auth mocks
3. `verification_test.dart` - Update provider constructors

## Migration Notes

The test failures are:
- Missing `auth`, `firestore`, `storage`, `offlineQueue` constructor parameters
- These were removed when providers were migrated to use AppwriteService

## Next Steps

1. Create Appwrite test mocks
2. Rewrite tests to use new provider structure
3. Re-enable tests one by one
