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

---

## Step 5: GitHub Actions release signing

The `build-android-release` job in `.github/workflows/ci.yml` runs only for
tags matching `v*`. It refuses to start unless all four signing secrets are
set (otherwise Gradle would silently fall back to debug signing), so add them
under **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Value |
| --- | --- |
| `RELEASE_KEYSTORE_BASE64` | the keystore file, base64-encoded: `base64 -w0 ~/cradi-release-key.jks` (macOS: `base64 -i ~/cradi-release-key.jks`) |
| `KEY_STORE_PASSWORD` | keystore password from Step 1 |
| `KEY_PASSWORD` | key password from Step 1 |
| `KEY_ALIAS` | key alias from Step 1 (`cradi` if you used the command above) |

The job decodes the keystore into `android/app/` and writes
`android/key.properties` itself — neither file is ever committed, and both
live only in the runner's workspace for the length of the build. It then
re-reads the signed APK with `apksigner` and fails the build if the
certificate is the Android debug one.

The build also needs the runtime configuration secrets, which the job
writes into `env.json` (see `docs/DEPLOYMENT.md` § 6):

| Secret | For |
| --- | --- |
| `APPWRITE_ENDPOINT`, `APPWRITE_PROJECT_ID` | an Appwrite build. **Without these two the tag ships a Supabase build** — which backend the app talks to is decided by its defines |
| `APPWRITE_DATABASE_ID` | only when the database is not `cradi` |
| `APPWRITE_PUSH_PROVIDER_ANDROID`, `APPWRITE_PUSH_PROVIDER_IOS` | push, in a project with both an FCM and an APNs provider |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | a Supabase build |
| `ONESIGNAL_APP_ID` | push on either stack — the device token comes from OneSignal |
| `SENTRY_DSN` | crash reporting |

The job drops empty ones rather than writing them, because a define that
is present but empty beats the Dart default: an unset
`APPWRITE_DATABASE_ID` would otherwise compile in `""` instead of `cradi`
and every call would 404. It prints which backend it built.

`BACKEND_URL` used to be listed here and is not a define the app reads —
nothing in `lib/` has ever looked it up.

> Never add the Appwrite **API key**, the Supabase **service role key**,
> the **Termii** key or the OneSignal **REST API key** here. They are
> server-only, and anything in `env.json` ends up readable inside the
> APK.
