# Google Play Store Review Test Credentials

## Purpose
This document contains test account credentials for Google Play Store reviewers to access all features of CRADI Mobile app.

## Test Account Details

### Primary Test Account

**Instruction Name for Play Console:**
```
Test Account for CRADI Mobile App Review
```

**Email Address:**
```
reviewer@craditest.com
```

**Password:**
```
ReviewTest2026!
```

**Registration Code:**
```
CRD123456
```

### Login Instructions for Reviewers

1. Open CRADI Mobile app
2. On the login screen, enter:
   - **Email**: reviewer@craditest.com
   - **Registration Code**: CRD123456
   - **Password**: ReviewTest2026!
3. Tap "Login" button
4. You will be directed to the dashboard with full access

### Additional Notes for Play Console Submission

Add this in the "Other instructions" field:

```
This app uses a three-factor authentication system for enhanced security:
1. Email address
2. Registration code (format: CRD######) 
3. Password

The test account provides full access to all app features including:
- Climate hazard reporting and verification
- Interactive maps with location-based data
- Knowledge base with safety guides
- Community chat and messaging
- User profile management
- Biometric authentication (optional, can be tested on supported devices)

IMPORTANT PERMISSIONS:
- Location: Required for hazard reporting with geographic coordinates
- Camera: Optional for attaching photos to hazard reports
- Microphone: Optional for voice-to-text in report descriptions
- Biometric: Optional for biometric login feature

Language Support: English and Hausa
```

## Creating the Test Account

> **ACTION REQUIRED**: You must create this test account in the Supabase project before uploading to Play Store.

### Steps to Create Test Account:

1. **Open the Supabase dashboard → Authentication → Users → Add user**
2. **Create the user with "Auto Confirm User" ticked:**
   - Email: `reviewer@craditest.com`
   - Password: `ReviewTest2026!`
   - User metadata: `{"name": "Play Store Reviewer"}`
3. **In Table Editor → `profiles`**, set on that row: `is_approved = true`,
   `is_verified = true`, `registration_code = 'CRD123456'`, and the role to
   grant (e.g. `ewm`) plus `state` / `lga` / `ward`.

4. **Verify the account works:**
   - Test login with these credentials on your device
   - Ensure all features are accessible
   - Test location permissions and camera access

## Security Best Practices

- ✅ Use a dedicated test account (not a real user account)
- ✅ Set a strong password
- ✅ Monitor this account for unusual activity after app goes live
- ✅ Consider disabling/resetting this account after successful review if desired
- ⚠️ Keep these credentials secure and only share via Play Console

## Troubleshooting

If Google reviewers report issues accessing the app:

1. **Verify the account exists in Supabase (Auth → Users) and its `profiles` row is approved**
2. **Check account is not locked** (rate limiting may block after failed attempts)
3. **Ensure registration code matches** exactly in your database
4. **Test credentials yourself** before each submission

## Alternative Test Accounts (Optional)

If you want to provide multiple test accounts or region-specific accounts:

**Account 2:**
- Email: `testuser2@craditest.com`
- Password: `TestUser2026!`
- Code: `CRD789012`

---

**Last Updated:** January 15, 2026
**App Version:** 1.0.0+2
