# Security Collections Setup

## Quick Setup

### Option 1: Automated Script (Recommended)

1. **Get your API Key:**
   - Go to Appwrite Console
   - Click "Settings" → "API Keys"
   - Create a new API key with these scopes:
     - `databases.read`
     - `databases.write`
     - `collections.read`
     - `collections.write`
     - `attributes.read`
     - `attributes.write`
     - `indexes.read`
     - `indexes.write`

2. **Install Appwrite SDK:**
   ```bash
   npm install node-appwrite
   ```

3. **Edit the script:**
   Open `setup_security_collections.js` and replace `YOUR_API_KEY_HERE` with your actual API key

4. **Run the script:**
   ```bash
   node setup_security_collections.js
   ```

### Option 2: Manual Setup in Appwrite Console

#### Collection 1: login_history

1. Create collection:
   - Name: `login_history`
   - ID: `login_history`

2. Add attributes:
   - `userId` - String (255) - Required
   - `success` - Boolean - Required
   - `timestamp` - DateTime - Required
   - `deviceFingerprint` - String (255) - Required
   - `deviceName` - String (255) - Optional
   - `ipAddress` - String (45) - Optional
   - `riskScore` - Integer - Optional
   - `riskLevel` - String (50) - Optional

3. Create indexes:
   - `userId_idx` on userId
   - `timestamp_idx` on timestamp
   - `success_idx` on success

4. Set permissions:
   - Create: `users` (any authenticated)
   - Read: `users` (self) + `role:admin`
   - Update: None
   - Delete: `role:admin`

#### Collection 2: trusted_devices

1. Create collection:
   - Name: `trusted_devices`
   - ID: `trusted_devices`

2. Add attributes:
   - `userId` - String (255) - Required
   - `deviceFingerprint` - String (255) - Required
   - `deviceName` - String (255) - Optional
   - `trusted` - Boolean - Required
   - `lastUsed` - DateTime - Required
   - `createdAt` - DateTime - Required

3. Create indexes:
   - `userId_idx` on userId
   - `deviceFingerprint_idx` on deviceFingerprint
   - `userId_deviceFingerprint_idx` on userId + deviceFingerprint

4. Set permissions:
   - Create: `users` (any authenticated)
   - Read: `users` (self)
   - Update: `users` (self)
   - Delete: `users` (self)

#### Collection 3: security_alerts

1. Create collection:
   - Name: `security_alerts`
   - ID: `security_alerts`

2. Add attributes:
   - `userId` - String (255) - Required
   - `type` - String (100) - Required
   - `severity` - String (50) - Required
   - `message` - String (500) - Required
   - `acknowledged` - Boolean - Required
   - `timestamp` - DateTime - Required

3. Create indexes:
   - `userId_idx` on userId
   - `acknowledged_idx` on acknowledged
   - `timestamp_idx` on timestamp

4. Set permissions:
   - Create: `users` (any authenticated)
   - Read: `users` (self)
   - Update: `users` (self)
   - Delete: `users` (self) + `role:admin`

## Verification

After setup, verify in Appwrite Console:
- [ ] 3 new collections visible
- [ ] All attributes created correctly
- [ ] All indexes created
- [ ] Permissions set properly

## Usage

Once set up, the app will automatically:
- Track login attempts in `login_history`
- Manage trusted devices in `trusted_devices`
- Create security alerts in `security_alerts`

No additional code changes needed!
