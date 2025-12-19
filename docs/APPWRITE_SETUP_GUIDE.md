# Appwrite Setup Guide for CRADI Mobile

This guide will walk you through setting up Appwrite backend for the CRADI Mobile application.

## Prerequisites

- Appwrite account at [cloud.appwrite.io](https://cloud.appwrite.io)
- Node.js installed (for running setup scripts)
- Appwrite project ID: `6941cdb400050e7249d5`

---

## Step 1: Install Node Dependencies

First, install the Appwrite Node SDK:

```bash
cd "/Users/mac/CRADI Mobile"
npm install node-appwrite
```

---

## Step 2: Get Appwrite API Key

1. Login to [Appwrite Console](https://cloud.appwrite.io)
2. Select your project: **CRADI app** (ID: `6941cdb400050e7249d5`)
3. Navigate to **Settings → API Keys** or visit directly:
   https://cloud.appwrite.io/console/project-6941cdb400050e7249d5/auth/apikeys
4. Click **Create API Key**
5. Name it: `CRADI Setup Key`
6. Under **Scopes**, grant the following permissions:
   - `databases.read`
   - `databases.write`
   - `collections.read`
   - `collections.write`
   - `attributes.read`
   - `attributes.write`
   - `indexes.read`
   - `indexes.write`
   - `buckets.read`
   - `buckets.write`
7. Click **Create**
8. **Copy the API key** (you won't see it again!)

---

## Step 3: Run Automated Setup Script

Run the setup script with your API key:

```bash
cd "/Users/mac/CRADI Mobile"
APPWRITE_API_KEY=your_api_key_here node setup_appwrite.js
```

This script will automatically create:
- ✅ Database: `cradi_database`
- ✅ Users collection with all attributes and indexes (including registrationCode)
- ✅ Reports collection with all attributes and indexes
- ✅ Messages collection with all attributes and indexes
- ✅ Emergency Contacts collection with all attributes and indexes
- ✅ Profile Images storage bucket (5MB max, jpg/jpeg/png/webp)
- ✅ Report Images storage bucket (10MB max, jpg/jpeg/png/webp)

**Note:** If resources already exist, the script will skip them gracefully.

---

## Step 4: Verify Setup

Run the verification script to ensure everything was created correctly:

```bash
APPWRITE_API_KEY=your_api_key_here node verify_appwrite_setup.js
```

This will check:
- Database exists
- All 4 collections exist with correct attributes
- All indexes are created
- Both storage buckets are configured

---

## Step 5: Configure SMS Provider (Optional - for Phone OTP)

To enable phone number authentication with OTP:

1. Login to [Appwrite Console](https://cloud.appwrite.io)
2. Navigate to **Auth → Messaging**
3. Click **Add Provider**
4. Choose one of the supported providers:
   - **Twilio** (Recommended)
   - Vonage
   - MSG91
   - Textlocal
   - Telesign
5. Enter your provider credentials
6. Save the configuration

**Without this setup, phone login will not work.** Email/password login will work immediately.

---

## Step 6: Test Authentication Flows

### Test Email/Password Signup

1. Run the app: `cd "/Users/mac/CRADI Mobile" && flutter run`
2. Navigate to **Registration** screen
3. Verify the **Registration Code** field is pre-filled with a code like `CRD123456`
4. Fill in email, password, and name
5. Click **Register**
6. Verify account creation and automatic login

### Test Email/Password Login

1. Logout from the app
2. Navigate to **Login** screen  
3. Enter email and password
4. Click **Login**
5. Verify successful login

### Test Profile Image Upload

1. Login to the app
2. Navigate to **Profile** screen
3. Tap on profile image placeholder
4. Select an image from gallery
5. Verify image uploads successfully
6. Check in Appwrite Console → Storage → profile_images to see the uploaded file

### Test Phone OTP (If SMS Provider Configured)

1. Navigate to **Login with Phone** screen
2. Enter phone number with country code (e.g., +1234567890)
3. Click **Send OTP**
4. Verify SMS received
5. Enter OTP code
6. Verify successful login

---

## Troubleshooting

### Issue: "Database already exists" error
**Solution:** This is normal if you've run the setup before. The script skips existing resources.

### Issue: "401 Unauthorized" error
**Solution:** Check that your API key is correct and has the necessary permissions.

### Issue: Phone OTP not working
**Solution:** Ensure you've configured an SMS provider in Appwrite Console → Auth → Messaging.

### Issue: Profile image upload fails
**Solution:** 
- Check bucket permissions in Appwrite Console
- Ensure image is under 5MB
- Verify file type is jpg/jpeg/png/webp

### Issue: Registration code not appearing
**Solution:**
- Check `registration_code_service.dart` is properly initialized
- Verify `RegistrationCodeService().getRegistrationCode()` is called on registration screen

---

## Database Schema Reference

### Users Collection

| Field | Type | Required | Unique | Default |
|-------|------|----------|--------|---------|
| email | string | Yes | Yes | - |
| name | string | Yes | No | - |
| role | string | Yes | No | ewm |
| phoneNumber | string | No | No | - |
| profileImageId | string | No | No | - |
| **registrationCode** | string | No | **Yes** | - |
| biometricsEnabled | boolean | No | No | false |
| createdAt | datetime | Yes | No | - |
| lastLoginAt | datetime | No | No | - |

### Reports Collection

Full schema in: [`/docs/appwrite_schema.md`](file:///Users/mac/CRADI%20Mobile/docs/appwrite_schema.md)

---

## Next Steps

After setup is complete:

1. ✅ Run verification script
2. ✅ Test email/password authentication
3. ✅ Test profile image upload
4. ⚙️ Configure SMS provider (optional)
5. 📱 Test phone OTP (if SMS configured)
6. 🚀 Deploy and test in production

---

## Important Notes

- **Registration codes** are generated client-side with format `CRD######`
- **API Key** should be kept secure and not committed to version control
- **Backups**: Appwrite Cloud automatically backs up your data
- **Rate Limits**: Be aware of Appwrite Cloud free tier limits

---

## Support

For issues with:
- **Appwrite**: Visit [Appwrite Discord](https://appwrite.io/discord) or [Documentation](https://appwrite.io/docs)
- **CRADI Mobile**: Check the project README or contact the development team

---

**Setup Guide Version:** 1.0  
**Last Updated:** December 2025
