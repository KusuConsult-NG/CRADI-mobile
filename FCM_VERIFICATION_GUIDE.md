# FCM Verification Guide

## Running the FCM Verification Script

The FCM verification script tests your Firebase Cloud Messaging setup to ensure push notifications work correctly.

### Prerequisites

- Flutter installed and configured
- Physical Android/iOS device OR emulator running
- `google-services.json` configured in `android/app/`

### Steps to Run

1. **Connect a device or start an emulator**
   ```bash
   # For Android emulator
   flutter emulators --launch <emulator_id>
   
   # Or connect a physical device via USB and enable USB debugging
   ```

2. **Verify device is connected**
   ```bash
   flutter devices
   ```
   
   You should see output like:
   ```
   Android SDK built for x86 (mobile) • emulator-5554 • ...
   # or
   Pixel 6 (mobile) • ABCD1234 • android-arm64 • ...
   ```

3. **Run the FCM verification script**
   ```bash
   cd "/Users/mac/CRADI Mobile"
   flutter run lib/scripts/verify_fcm.dart
   ```

4. **Select your device**
   - When prompted, choose your Android/iOS device (not macOS or Chrome)
   - The app will launch and run the FCM tests

### What to Expect

The script will display a UI showing test results:

#### Successful Tests (✅):
- Firebase initialized
- FCM token generated
- Permissions granted
- Token refresh listener active
- Foreground message handler working
- Background handler registered

#### Common Issues:

**Problem**: "Firebase not configured"
- **Fix**: Ensure `google-services.json` exists in `android/app/`
- Check Firebase project is set up correctly

**Problem**: "Permission denied"
- **Fix**: Grant notification permissions when prompted on device

**Problem**: "No token generated"
- **Fix**: Check internet connection
- Verify Firebase project configuration

### Manual Testing (Alternative)

If you don't have a device available right now, you can manually test FCM:

1. **Build a release APK**
   ```bash
   flutter build apk --release
   ```

2. **Install on physical device**
   ```bash
   adb install build/app/outputs/flutter-apk/app-release.apk
   ```

3. **Check logs for FCM token**
   ```bash
   adb logcat | grep "FCM Token"
   ```

4. **Send test notification**
   - Go to Firebase Console → Cloud Messaging
   - Click "Send test message"
   - Paste your FCM token
   - Send notification and verify it appears on device

### Test Results to Look For

When the verification app runs, look for these in the console:

```
✅ Firebase initialized: your-project-id
✅ FCM Token: eyJhbGciOi... (long token string)
✅ Notification permissions granted
✅ FCM background handler registered
```

### Next Steps After Verification

Once FCM is verified:
1. Note the FCM token (copy from logs)
2. Test sending a notification from Appwrite Console
3. Verify notification appears on device
4. Proceed with production build

---

## For Web/Chrome Testing (Limited)

> [!WARNING]
> FCM verification requires a mobile device. Chrome/macOS won't work for full FCM testing.

If you only have web available:
- Some tests will pass (Firebase init)
- Token generation may fail (web FCM requires different setup)
- Use a physical device or emulator for accurate results

---

## Current Status

**Available Devices**:
- macOS (desktop) ❌ - Cannot test FCM
- Chrome (web) ❌ - Limited FCM support

**Recommended**: Connect Android/iOS device or start emulator to run full FCM verification.

**Quick Setup**:
```bash
# Start Android emulator (if configured)
flutter emulators
flutter emulators --launch <emulator-name>

# Then run verification
flutter run lib/scripts/verify_fcm.dart
```
