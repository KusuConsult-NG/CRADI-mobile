# 🚀 CRADI Mobile - Play Store Release Checklist

## ✅ Completed

- [x] All IDE errors fixed
- [x] Flutter analyze passes (0 issues)
- [x] Code quality audit passed
- [x] Security audit passed
- [x] Production signing configuration added
- [x] Keystore setup guide created
- [x] Authority contacts documented

---

## 🔐 Signing Configuration (CRITICAL)

### Required Before Build:

1. [ ] Generate production keystore (.jks file)
   ```bash
   keytool -genkey -v -keystore ~/cradi-release-key.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias cradi
   ```

2. [ ] Create `android/key.properties` from template
   - Copy: `cp android/key.properties.template android/key.properties`
   - Fill in: keystore passwords and file path

3. [ ] Backup keystore securely
   - [ ] Upload to secure cloud storage (encrypted)
   - [ ] Store passwords in password manager
   - [ ] Create offline backup

4. [ ] Verify signing works
   ```bash
   flutter build apk --release
   ```

**📖 See:** `KEYSTORE_SETUP.md` for detailed instructions

---

## 📞 Authority Contacts (HIGH PRIORITY)

### State-Level Contacts to Update:

**Benue:**
- [ ] SEMA Director: `+2348000000000` → Update
- [ ] Police Commissioner: `+2348000000001` → Update

**Nasarawa:**
- [ ] SEMA Director: `+2348000000002` → Update
- [ ] Police Commissioner: `+2348000000003` → Update

**Plateau:**
- [ ] SEMA Director: `+2348000000004` → Update
- [ ] Police Commissioner: `+2348000000005` → Update

**📖 See:** `AUTHORITY_CONTACTS_GUIDE.md` for collection process

**Options:**
- Update before launch (recommended)
- Launch and update via OTA
- Use hybrid approach with national emergency numbers

---

## 🏗️ Build & Test

### Release Build:

1. [ ] Clean previous builds
   ```bash
   flutter clean
   flutter pub get
   ```

2. [ ] Build release APK
   ```bash
   flutter build apk --release
   ```

3. [ ] Verify APK size (should be ~30-50MB)

4. [ ] Check APK location
   ```
   build/app/outputs/flutter-apk/app-release.apk
   ```

### Testing:

1. [ ] Install on physical Android device
   ```bash
   adb install build/app/outputs/flutter-apk/app-release.apk
   ```

2. [ ] Test critical flows:
   - [ ] Registration + OTP verification
   - [ ] Login with biometrics
   - [ ] Create hazard report
   - [ ] Upload image to report
   - [ ] GPS location capture
   - [ ] Offline mode + sync
   - [ ] Emergency contacts
   - [ ] Push notifications

3. [ ] Performance check:
   - [ ] App launches in <3 seconds
   - [ ] No crashes during normal use
   - [ ] Smooth navigation
   - [ ] Camera/gallery work properly

---

## 📱 Play Store Listing

### Required Assets:

1. [ ] **App Icon** (512x512 PNG)
   - High-quality, no transparency
   - Current icon acceptable, but consider professional design

2. [ ] **Feature Graphic** (1024x500 PNG)
   - Showcase app purpose
   - Include app name: "CRADI Mobile"

3. [ ] **Screenshots** (Minimum 2, recommended 8)
   - Phone: 1080x1920 or higher
   - Show key features:
     - [ ] Home/Dashboard
     - [ ] Hazard reporting flow
     - [ ] Emergency contacts
     - [ ] Alert notifications
     - [ ] Knowledge base
     - [ ] Offline mode

4. [ ] **App Description**
   ```
   Title: CRADI Mobile - Disaster Early Warning
   
   Short description (80 chars):
   Report climate hazards, receive alerts, connect with emergency services
   
   Full description (prepare 4000 chars):
   - What the app does
   - Key features
   - Who it's for (farmers, communities)
   - Coverage areas (Benue, Nasarawa, Plateau)
   ```

5. [ ] **Privacy Policy URL**
   - Must be publicly accessible
   - Cover data collection, storage, usage
   - Include contact information

---

## 🔧 App Configuration

### Version & Metadata:

1. [ ] Review `pubspec.yaml`
   - Current version: `1.0.0+1`
   - App name: `"CRADI Mobile"`
   - ✅ Good for initial release

2. [ ] Review `AndroidManifest.xml`
   - [x] All permissions justified
   - [x] App name correct
   - [x] Network security configured

---

## 📋 Play Console Setup

### Google Play Console Steps:

1. [ ] Create Google Play Developer account ($25 one-time fee)

2. [ ] Create new app in Play Console
   - App name: CRADI Mobile
   - Default language: English (US)
   - Type: App
   - Free or paid: Free

3. [ ] Complete Store Listing
   - [ ] Upload all assets (icon, screenshots, graphics)
   - [ ] Write descriptions
   - [ ] Add privacy policy URL
   - [ ] Select category: Weather, Productivity, or Tools
   - [ ] Add contact email

4. [ ] App Content:
   - [ ] Content rating questionnaire
   - [ ] Target audience: All ages (community safety)
   - [ ] Data safety form
   - [ ] Ads declaration: No ads

5. [ ] Upload APK/AAB
   ```bash
   # For better optimization, build App Bundle:
   flutter build appbundle --release
   # Upload: build/app/outputs/bundle/release/app-release.aab
   ```

6. [ ] Set up internal testing (optional)
   - Test with small group before production

7. [ ] Submit for review

---

## 🔒 Security Pre-Launch

- [x] No hardcoded secrets
- [x] ProGuard enabled
- [x] Network security configured
- [x] Secure storage implemented
- [ ] Privacy policy created
- [ ] Data retention policy documented

---

## 📊 Pre-Submission Verification

Run these final checks:

```bash
# 1. Analyze code
flutter analyze

# 2. Check dependency health
flutter pub outdated

# 3. Build release
flutter build apk --release

# 4. Check APK details
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell dumpsys package com.cradi.mobile | grep version
```

**All clear?** Proceed to submission! ✅

---

## 🎯 Launch Day Checklist

- [ ] Release APK uploaded to Play Console
- [ ] All store assets uploaded
- [ ] Privacy policy live
- [ ] Contact email monitored
- [ ] Internal team has test version
- [ ] Ready to monitor reviews and crashes
- [ ] Support plan in place

---

## 📈 Post-Launch

After approval (typically 1-3 days):

1. [ ] Monitor crash reports in Play Console
2. [ ] Track user reviews and respond
3. [ ] Plan first update (authority contacts if needed)
4. [ ] Set up Firebase Crashlytics for better error tracking
5. [ ] Consider Firebase Analytics for usage insights

---

## 🆘 Support & Resources

- **Keystore Guide:** `KEYSTORE_SETUP.md`
- **Contacts Guide:** `AUTHORITY_CONTACTS_GUIDE.md`
- **Audit Report:** See artifacts directory
- **Play Console Help:** https://support.google.com/googleplay/android-developer

---

**Estimated time to submission:** 1-3 days (if keystore and contacts ready)  
**Play Store review time:** 1-3 days typically

Good luck with your launch! 🚀
