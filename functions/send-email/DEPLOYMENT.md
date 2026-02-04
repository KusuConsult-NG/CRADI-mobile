# Resend Email Integration - Deployment Guide

## Overview

CRADI Mobile now has email notification capabilities via Resend. This enables:
- 📧 **Alert Notifications** to authorities when hazards are validated
- ✉️ **Email Verification** codes for login/registration
- 📬 **Status Updates** when report statuses change
- 👋 **Welcome Emails** for new users

---

## Files Created

1. **`functions/send-email/src/index.js`** - Main Cloud Function handler
2. **`functions/send-email/src/email_templates.js`** - HTML email templates
3. **`functions/send-email/package.json`** - Dependencies (Resend SDK)
4. **`functions/alert-distribution/src/index.js`** - Updated to send emails

---

## Deployment Steps

### 1. Install Dependencies

Already completed locally. When deploying to Appwrite:

```bash
cd functions/send-email
npm install
```

### 2. Deploy to Appwrite Console

#### Option A: Via Appwrite Console (Recommended)

1. Log in to [Appwrite Console](https://cloud.appwrite.io)
2. Navigate to **Functions** → **Create Function**
3. Configure function:
   - **Name**: `send-email`
   - **Runtime**: `Node.js 18.0` or higher
   - **Entrypoint**: `src/index.js`
   - **Events**: (None - will be called manually)
   - **Timeout**: `15` seconds
   - **Execute Access**: `Server` (Functions can execute)

4. Upload code:
   - Zip the `functions/send-email` directory
   - Upload via Console or use Appwrite CLI

#### Option B: Via Appwrite CLI

```bash
# Install Appwrite CLI
npm install -g appwrite

# Login
appwrite login

# Deploy function
appwrite functions createDeployment \
  --functionId send-email \
  --activate=true \
  --entrypoint="src/index.js" \
  --code="./functions/send-email"
```

### 3. Configure Environment Variables

In Appwrite Console → Functions → send-email → Settings → Environment Variables:

| Variable | Value | Description |
|----------|-------|-------------|
| `RESEND_API_KEY` | `re_NGbnm7d7_DErnsvKK1nf7kVscLE4VqiFP` | Your Resend API key |
| `FROM_EMAIL` | `noreply@cradi.ng` (or your verified domain) | Sender email address |
| `FROM_NAME` | `CRADI Mobile` | Sender display name |

> [!WARNING]
> **Important**: You must verify the sender domain in your Resend dashboard before sending emails. Visit [Resend Dashboard](https://resend.com/domains) to add and verify your domain.

### 4. Update alert-distribution Function

The `alert-distribution` function has been updated to call `send-email`. Deploy the updated version:

```bash
cd functions/alert-distribution
# Re-deploy via Console or CLI
```

Ensure these environment variables are set for `alert-distribution`:

| Variable | Description |
|----------|-------------|
| `APPWRITE_FUNCTION_ENDPOINT` | Appwrite API endpoint |
| `APPWRITE_FUNCTION_PROJECT_ID` | Your project ID |
| `APPWRITE_API_KEY` | API key with function execution permission |

### 5. Update Authority Contacts Database

Ensure authority contacts have email addresses populated:

```javascript
// Example authority document structure
{
  "name": "SEMA Benue",
  "phone": "+2348012345678",
  "email": "sema@benuestate.gov.ng",  // ← Ensure this field exists
  "state": "Benue",
  "lga": "Makurdi"
}
```

---

## Testing

### Test 1: Manual Function Execution

Test the `send-email` function directly:

```bash
# Via Appwrite Console
# Navigate to Functions → send-email → Executions → Create Execution

# Payload for Alert Email:
{
  "to": "your-test-email@example.com",
  "template": "alert",
  "data": {
    "hazardType": "Flood",
    "severity": "Critical",
    "ward": "Test Ward",
    "lga": "Makurdi",
    "state": "Benue",
    "description": "Test flood alert",
    "timestamp": "Feb 4, 2026, 1:45 PM"
  }
}
```

### Test 2: End-to-End Alert Flow

1. Create a test hazard report in the app
2. As a coordinator, validate the report
3. Check that:
   - SMS sent to authority phones
   - **Email sent to authority emails** ✉️
   - Push notification sent

### Test 3: Verification Email

```json
{
  "to": "user@example.com",
  "template": "verification",
  "data": {
    "name": "John Doe",
    "code": "123456"
  }
}
```

### Test 4: Welcome Email

```json
{
  "to": "newuser@example.com",
  "template": "welcome",
  "data": {
    "name": "Jane Smith",
    "email": "newuser@example.com",
    "role": "Early Warning Monitor"
  }
}
```

---

## Monitoring & Debugging

### Check Resend Dashboard

Visit [Resend Dashboard](https://resend.com/emails) to:
- View sent emails
- Check delivery status
- Monitor bounces/complaints
- View email analytics

### Appwrite Function Logs

In Appwrite Console → Functions → send-email → Executions:
- View execution history
- Check for errors
- Monitor performance

### Common Issues

| Issue | Solution |
|-------|----------|
| "Domain not verified" | Verify your sender domain in Resend dashboard |
| "RESEND_API_KEY not set" | Add environment variable in Appwrite Console |
| "Email not delivered" | Check Resend dashboard for bounce/spam reports |
| "Function timeout" | Increase timeout in function settings (max 900s) |

---

## Email Templates

### 1. Alert Template (`alert`)
Sends emergency hazard notifications to authorities with:
- Hazard type and severity badge
- Location details
- Description
- Timestamp
- Safety recommendations (optional)

### 2. Verification Template (`verification`)
Sends OTP codes for email verification with:
- Large, readable code
- 10-minute expiration notice
- Security warning

### 3. Status Update Template (`statusUpdate`)
Notifies users when report statuses change with:
- Report ID
- New status badge
- Coordinator comments (optional)

### 4. Welcome Template (`welcome`)
Onboarding email for new users with:
- Welcome message
- User role and email
- Feature overview

---

## Next Steps

1. **Verify domain in Resend** - Critical for production
2. **Deploy both functions** to Appwrite
3. **Test with real scenarios** - Create test reports
4. **Monitor delivery rates** - Check Resend analytics
5. **Add more templates** as needed (password reset, etc.)

---

## API Reference

### Send Email Function

**Endpoint**: `https://[your-region].cloud.appwrite.io/v1/functions/send-email/executions`

**Method**: POST

**Headers**:
```json
{
  "X-Appwrite-Project": "your-project-id",
  "X-Appwrite-Key": "your-api-key",
  "Content-Type": "application/json"
}
```

**Payload**:
```json
{
  "to": "recipient@example.com" | ["email1@example.com", "email2@example.com"],
  "template": "verification" | "alert" | "statusUpdate" | "welcome",
  "data": {
    // Template-specific data
  }
}
```

**Response**:
```json
{
  "success": true,
  "messageId": "550e8400-e29b-41d4-a716-446655440000",
  "template": "alert",
  "recipients": 3
}
```

---

## Security Considerations

✅ **API Key Protection**: Resend API key stored as environment variable  
✅ **Function Authentication**: Only authenticated functions can call send-email  
✅ **Rate Limiting**: Handled by Resend (100 emails/day on free tier)  
✅ **Data Privacy**: No sensitive data logged or exposed  
✅ **Domain Verification**: Prevents email spoofing

---

## Cost Estimate

**Resend Pricing**:
- Free tier: 100 emails/day, 3,000/month
- Paid: $20/month for 50,000 emails

**Appwrite Functions**:
- Free tier: 750,000 function executions/month
- Paid: Varies by region

For typical CRADI usage (assuming 50 validated alerts/day):
- Emails sent: ~150/day (3 authorities per alert × 50)
- Monthly cost: **$0** (within free tier)

---

## Support

For issues or questions:
- Resend Docs: https://resend.com/docs
- Appwrite Docs: https://appwrite.io/docs/products/functions
- CRADI Team: Contact your coordinator
