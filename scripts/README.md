# Database Migration Scripts

## Setup

1. **Install dependencies:**
   ```bash
   cd scripts
   npm install
   ```

2. **Get Appwrite API Key:**
   - Go to: https://cloud.appwrite.io/console/project-fra-6941cdb400050e7249d5/settings
   - Click "API Keys" → "Create API key"
   - Name: "Database Migration"
   - Scopes: Select all "Database" scopes
   - Copy the generated API key

3. **Run migration:**
   ```bash
   # Set API key and run
   APPWRITE_API_KEY="your-api-key-here" npm run migrate
   ```

## What This Script Does

Automatically adds all missing database attributes to your Appwrite collections:

### Users Collection
- email, name, role, address
- biometricsEnabled, phoneNumber, profileImageId
- createdAt, lastLoginAt

### Reports Collection  
- userId, hazardType, severity, description
- location, latitude, longitude, state, lga
- imageIds (array), status
- createdAt, updatedAt

### Emergency Contacts Collection
- userId, name, phone, relationship
- organization, lga, category, isAvailable

### Chats Collection
- participants (array), lastMessage, lastMessageAt, createdAt

### Messages Collection
- chatId, senderId, text, createdAt, readBy (array)

### Other Collections
- Trusted Devices, Login History, Knowledge Base

## Safety Features

- ✅ Checks for existing attributes (won't duplicate)
- ✅ Validates collection exists before adding attributes
- ✅ Rate limiting to avoid API overload
- ✅ Detailed progress logs
- ✅ Summary report at end

## Example Output

```
🚀 Starting database schema migration...

📁 Processing collection: users
──────────────────────────────────────────────────────
   Found 3 existing attributes
   ⏭️  email (string) - already exists
   ⏭️  name (string) - already exists
   ✅ Added: address (string)
   ✅ Added: phoneNumber (string)
   ✅ Added: createdAt (datetime)
...

📊 MIGRATION SUMMARY
═══════════════════════════════════════════════════
✅ Attributes added:   15
⏭️  Attributes skipped: 8
❌ Errors:             0
═══════════════════════════════════════════════════
```
