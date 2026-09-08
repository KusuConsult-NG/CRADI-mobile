# 🔐 Production Keystore Setup Guide

## Step 1: Generate Your Keystore (One-time setup)

Run this command in your terminal:

```bash
keytool -genkey -v -keystore ~/cradi-release-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias cradi
```

**You'll be prompted for:**
- Keystore password (choose a strong password, you'll need it)
- Key password (can be the same as keystore password)
- Your name and organization details

**IMPORTANT:** 
- Store this keystore file safely - you need it for ALL future app updates
- If you lose it, you cannot update your app on Play Store (you'll need to publish a new app)
- Back it up securely (encrypted cloud storage, password manager, etc.)

---

## Step 2: Create key.properties File

1. Copy the template file:
   ```bash
   cd /Users/mac/CRADI\ Mobile/android
   cp key.properties.template key.properties
   ```

2. Edit `key.properties` with your actual values:
   ```properties
   storePassword=YOUR_KEYSTORE_PASSWORD
   keyPassword=YOUR_KEY_PASSWORD
   keyAlias=cradi
   storeFile=/Users/mac/cradi-release-key.jks
   ```

**CRITICAL:** 
- ✅ `key.properties` is already in `.gitignore` - it will NOT be committed
- ✅ Never share this file or commit it to version control
- ✅ The `storeFile` path should point to where you saved the .jks file

---

## Step 3: Verify Setup

Test that the signing configuration works:

```bash
cd /Users/mac/CRADI\ Mobile
flutter build apk --release
```

**Expected output:**
- Build should complete successfully
- You should see: "Running Gradle task 'assembleRelease'..."
- Final APK will be at: `build/app/outputs/flutter-apk/app-release.apk`

**If you see warnings about "key.properties not found":**
- Double-check the file exists at `/Users/mac/CRADI Mobile/android/key.properties`
- Verify the storeFile path in key.properties points to your actual .jks file

---

## Step 4: Security Checklist

Before proceeding:

- [ ] Keystore file (.jks) is backed up in a secure location
- [ ] Passwords are stored in a password manager
- [ ] key.properties file exists and contains correct values
- [ ] Git status shows key.properties is ignored (not tracked)
- [ ] Release build completes successfully

---

## Troubleshooting

### "Cannot find key.properties"
- Ensure file is at: `/Users/mac/CRADI Mobile/android/key.properties`
- Check file permissions (should be readable)

### "Keystore file not found"
- Verify the `storeFile` path in key.properties
- Use absolute path (e.g., `/Users/mac/cradi-release-key.jks`)

### "Wrong password"
- Re-check your keystore and key passwords
- They were set when you created the keystore

---

## Next Steps

Once signing is configured:

1. Build release APK: `flutter build apk --release`
2. Test on physical device
3. Proceed to Play Store Console setup
