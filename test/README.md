# Testing Guide for CRADI Mobile

## Overview

This directory contains tests for the CRADI Mobile application organized by test type.

## Directory Structure

```
test/
├── unit/              # Unit tests for providers, services, and utilities
├── widget/            # Widget tests for screens and components
├── integration/       # Integration tests for end-to-end flows
└── README.md         # This file
```

## Test Types

### Unit Tests (`test/unit/`)
Test individual classes and functions in isolation.

**Examples:**
- `auth_provider_test.dart` - Tests authentication logic
- `reporting_provider_test.dart` - Tests report state management
- `profile_provider_test.dart` - Tests profile operations

**When to write unit tests:**
- Provider business logic
- Utility functions and helpers
- Service classes
- Data models and transformations

**Best Practices:**
- Test one class/function per file
- Use descriptive test names
- Group related tests with `group()`
- Mock external dependencies (Firebase, storage, etc.)
- Aim for >80% code coverage for business logic

### Widget Tests (`test/widget/`)
Test UI components and screens in isolation.

**Examples:**
- `otp_screen_test.dart` - Tests OTP input screen
- `hazard_selection_screen_test.dart` - Tests hazard selection UI

**When to write widget tests:**
- Screen layouts and UI elements
- User interactions (taps, input, gestures)
- Navigation flows
- Form validation
- UI state changes

**Best Practices:**
- Test critical user paths
- Verify widgets render correctly
- Test user interactions
- Check accessibility
- Test different screen sizes when relevant

### Integration Tests (`test/integration/`)
Test complete user flows across multiple screens.

**Best Practices:**
- Test critical workflows (report submission, verification)
- Test offline/online scenarios
- Minimize number of integration tests (they're slow)
- Test on real devices when possible

## Running Tests

### Run All Tests
```bash
flutter test
```

### Run Specific Test File
```bash
flutter test test/unit/profile_provider_test.dart
```

### Run Tests by Type
```bash
# Unit tests only
flutter test test/unit/

# Widget tests only
flutter test test/widget/

# Integration tests only
flutter test test/integration/
```

### Run Tests with Coverage
```bash
# Generate coverage report
flutter test --coverage

# View HTML coverage report (requires lcov)
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

### Watch Mode (Re-run on changes)
```bash
flutter test --watch
```

## Writing Tests

### Naming Conventions

**Test Files:** `<file_name>_test.dart`
- `profile_provider_test.dart` for `profile_provider.dart`

**Test Cases:** Use descriptive names starting with `should`
```dart
test('should update name successfully', () {
  // Test implementation
});
```

**Widget Tests:** Use `testWidgets`
```dart
testWidgets('should display 4 OTP input fields', (tester) async {
  // Widget test implementation
});
```

### Test Structure

Follow the **Arrange-Act-Assert** pattern:

```dart
test('should calculate total correctly', () {
  // Arrange - Set up test data
  final calculator = Calculator();
  final a = 5;
  final b = 3;
  
  // Act - Perform the action
  final result = calculator.add(a, b);
  
  // Assert - Verify the result
  expect(result, equals(8));
});
```

### Mocking Dependencies

Use `mockito` for mocking:

```dart
// 1. Add @GenerateMocks annotation
@GenerateMocks([SecureStorageService, FirebaseFirestore])
void main() {
  // 2. Create mock instances
  late MockSecureStorageService mockStorage;
  
  setUp(() {
    mockStorage = MockSecureStorageService();
  });
  
  // 3. Set up mock behavior
  test('should read from storage', () {
    when(mockStorage.read('key')).thenAnswer((_) async => 'value');
    
    // Test with mock
  });
}
```

## Code Coverage Goals

- **Business Logic (Providers/Services):** 80%+
- **Utilities/Helpers:** 90%+
- **Widgets:** 60%+
- **Overall:** 70%+

## Continuous Integration

Tests are run automatically on:
- Every pull request
- Every commit to main branch
- Pre-deployment checks

## Additional Resources

- [Flutter Testing Documentation](https://docs.flutter.dev/testing)
- [Effective Dart: Testing](https://dart.dev/guides/language/effective-dart/testing)
- [Widget Testing Guide](https://docs.flutter.dev/cookbook/testing/widget/introduction)
- [Mockito Package](https://pub.dev/packages/mockito)

## Common Issues

### Test Failing Due to Async Operations
Use `await tester.pumpAndSettle()` to wait for animations and async operations:
```dart
await tester.tap(find.byType(Button));
await tester.pumpAndSettle(); // Wait for animations
```

### Firebase Not Initialized in Tests
Mock Firebase services or use `setupFirebaseAuthMocks()` from `firebase_auth_mocks`:
```dart
setUp(() {
  setupFirebaseAuthMocks();
});
```

### Widget Not Found
Use `await tester.pump()` after actions:
```dart
await tester.enterText(find.byType(TextField), 'text');
await tester.pump(); // Rebuild widget tree
```

## TODO

- [ ] Add integration test examples
- [ ] Set up automated coverage reporting
- [ ] Add performance testing guidelines
- [ ] Create test data fixtures
- [ ] Add screenshot testing
