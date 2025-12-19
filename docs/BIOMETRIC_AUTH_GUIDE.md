# Biometric Authentication - User Guide

## Overview

Biometric authentication is now enabled in CRADI Mobile, allowing you to login quickly and securely using your fingerprint or Face ID instead of entering your registration code and phone number every time.

## Features

### 🔐 Secure & Fast Login
- **Fingerprint** authentication (Android & iOS)
- **Face ID** authentication (iOS devices with Face ID)
- Fully encrypted and secure
- Works offline

### 🎯 How It Works

1. **First Time Setup**
   - Login with your registration code first time
   - Go to Settings → Security & Privacy
   - Enable "Biometric Login"
   - Authenticate with your fingerprint/Face ID to confirm

2. **Using Biometric Login**
   - Open the app
   - On login screen, tap "Login with Biometrics" button
   - Authenticate with fingerprint or Face ID
   - Instant access to dashboard!

## Setup Instructions

### Step 1: Initial Login
First, login normally using your:
- Phone number (e.g., 08012345678)
- Registration code (provided by coordinator)

### Step 2: Enable Biometric Login
1. Tap the **Settings** icon in the navigation bar
2. Scroll to **SECURITY & PRIVACY** section
3. Toggle **"Biometric Login"** to ON
4. Authenticate with your fingerprint/Face ID when prompted
5. ✅ Biometric login is now enabled!

### Step 3: Use Biometric Login
Next time you open the app:
1. On the login screen, look for the **"OR"** divider
2. Tap the **"Login with Biometrics"** button (fingerprint icon)
3. Place your finger on the sensor or look at the camera
4. 🎉 Instant login!

## Security Features

### ✅ What's Protected
- Your authentication is stored encrypted in secure storage
- **iOS**: Keychain (hardware-backed)
- **Android**: KeyStore (hardware-backed)
- Biometric data NEVER leaves your device
- Works with existing device security

### ⚠️ Important Notes
- You must login with your registration code at least once before enabling biometric auth
- If biometric authentication fails 5 times, you'll need to use your registration code
- You can disable biometric login anytime in Settings
- Changing device biometric settings (adding/removing fingerprints) won't affect the app

## Device Compatibility

### ✅ Supported Devices
- **Android**: Devices with fingerprint sensor (Android 6.0+)
- **iOS**: Devices with Touch ID or Face ID (iOS 11.0+)

### ❌ Not Available
If you see "Not available on this device" in settings, your device doesn't have:
- Fingerprint sensor
- Face ID/Touch ID hardware
- Or biometric authentication is disabled in device settings

## Troubleshooting

### Biometric Button Not Showing
**Problem**: "Login with Biometrics" button doesn't appear on login screen

**Solution**:
1. Go to Settings → Security & Privacy
2. Make sure "Biometric Login" toggle is ON
3. Restart the app

### Authentication Keeps Failing
**Problem**: Fingerprint/Face ID not recognized

**Solutions**:
1. Clean your fingerprint sensor/camera
2. Try a different registered finger
3. Check device Settings → Biometrics and ensure they work there first
4. If still failing, disable and re-enable biometric login in app settings

### "Biometric authentication failed" Error
**Solutions**:
1. Your session may have expired - login with registration code again
2. Too many failed attempts - wait 30 seconds and try again
3. Device biometrics changed - disable and re-enable in settings

### Button Disappeared After Update
**Solution**:
1. Session expired - login with registration code
2. Biometric setting was reset - re-enable in Settings

## Privacy & Security

### 🔒 Your Data is Safe
- ✅ Biometric data stays on YOUR device only
- ✅ App NEVER receives your fingerprint/face data
- ✅ We only receive authentication success/failure
- ✅ All stored data is encrypted
- ✅ Session timeout still applies (30 minutes)

### 🚫 What We DON'T Do
- ❌ Store your fingerprint/face data
- ❌ Send biometric data to servers
- ❌ Share with third parties
- ❌ Use for anything except authentication

## FAQ

**Q: Is biometric login as secure as registration code?**  
A: Yes! Your device's biometric security is hardware-backed and very secure. We use it as a convenience feature without compromising security.

**Q: Can I use both registration code and biometric?**  
A: Yes! Biometric is optional. You can always login with your registration code.

**Q: What happens if I lose my phone?**  
A: Biometric authentication is device-specific. If you lose your phone, your biometrics on the new device won't work until you login with your registration code and enable it again.

**Q: Will enabling biometric login share my fingerprint with the app?**  
A: No! Your biometric data NEVER leaves your device. The app only knows if authentication succeeded or failed.

**Q: Can I disable biometric login?**  
A: Yes, anytime! Go to Settings → Security & Privacy → Toggle OFF "Biometric Login"

**Q: Do I need internet to use biometric login?**  
A: No! Biometric authentication works completely offline.

**Q: How many fingerprints can I use?**  
A: You can use any fingerprint registered on your device. The app uses your device's biometric system.

## Support

If you encounter any issues with biometric authentication:

1. **Check Device Settings**
   - Ensure biometrics are enabled on your device
   - Test your fingerprint/Face ID in device settings

2. **Restart the App**
   - Close the app completely
   - Open again and try

3. **Re-enable Biometric Login**
   - Settings → Security & Privacy
   - Toggle OFF, then ON again

4. **Contact Support**
   - If issues persist, contact your coordinator
   - Provide: Device model, OS version, error message

## Version Information

- **Feature Added**: Version 2.5.0
- **Minimum Requirements**:
  - Android 6.0+ with fingerprint sensor
  - iOS 11.0+ with Touch ID or Face ID
- **Security Level**: Hardware-backed encryption

---

**Remember**: Biometric authentication is a convenience feature. Your registration code is still the primary authentication method and will always work!
