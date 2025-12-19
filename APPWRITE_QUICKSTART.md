# 🚀 Appwrite Setup - Quick Start

## What's Been Done ✅

- ✅ Appwrite service implementation (`lib/core/services/appwrite_service.dart`)
- ✅ Registration code service with CRD prefix (`lib/core/services/registration_code_service.dart`)
- ✅ Auth provider integrated with Appwrite
- ✅ Database schema with registrationCode field
- ✅ Setup scripts created (`setup_appwrite.js`, `verify_appwrite_setup.js`)
- ✅ Node dependencies installed (`node-appwrite`)

---

## Next Steps (You Need to Do This) 👇

### Step 1: Get Your Appwrite API Key

1. **Visit:** https://cloud.appwrite.io/console/project-6941cdb400050e7249d5/auth/apikeys

2. **Click:** "Create API Key"

3. **Name it:** "CRADI Setup Key"

4. **Enable these scopes:**
   - ✓ `databases.*` (all database permissions)
   - ✓ `collections.*` (all collection permissions)
   - ✓ `attributes.*` (all attribute permissions)
   - ✓ `indexes.*` (all index permissions)
   - ✓ `buckets.*` (all storage permissions)

   Or manually grant:
   - databases.read, databases.write
   - collections.read, collections.write
   - attributes.read, attributes.write
   - indexes.read, indexes.write
   - buckets.read, buckets.write

5. **Copy the API key** - You won't see it again!

---

### Step 2: Run Setup Script

```bash
cd "/Users/mac/CRADI Mobile"
APPWRITE_API_KEY=your_copied_api_key_here npm run setup:appwrite
```

**This will create:**
- 📦 Database: `cradi_database`
- 👥 Users collection (with registrationCode field)
- 📋 Reports collection
- 💬 Messages collection
- 🚨 Emergency Contacts collection
- 🖼️ Profile Images bucket (5MB max)
- 📸 Report Images bucket (10MB max)

---

### Step 3: Verify Setup

```bash
APPWRITE_API_KEY=your_api_key_here npm run verify:appwrite
```

This checks that everything was created correctly.

---

### Step 4: Test the App

```bash
flutter run
```

**Test these features:**
1. ✅ Sign up with email/password (check registration code pre-fill)
2. ✅ Login with email/password
3. ✅ Upload profile image
4. ⚙️ Phone OTP (requires SMS provider - see below)

---

## Optional: Enable Phone OTP

**To enable SMS OTP:**

1. Go to: https://cloud.appwrite.io/console/project-6941cdb400050e7249d5/auth/providers
2. Click "Messaging" → "Add Provider"
3. Choose provider (Twilio recommended)
4. Enter credentials
5. Test phone login in app

**Without this, only email/password login will work.**

---

## Troubleshooting

### "401 Unauthorized"
→ Check API key has correct permissions

### Phone OTP not working
→ Configure SMS provider in Console

### Image upload fails
→ Check file size (<5MB) and type (jpg/png/webp)

---

## Full Documentation

For complete details, see: [`docs/APPWRITE_SETUP_GUIDE.md`](file:///Users/mac/CRADI%20Mobile/docs/APPWRITE_SETUP_GUIDE.md)

---

**Ready?** Get your API key and run the setup script! 🎯
