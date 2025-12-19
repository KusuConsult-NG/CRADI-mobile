# Appwrite Database Schema - Security Collections

This document defines additional collections needed for the enhanced security features.

## New Collections for Security

### 1. login_history
**Collection ID:** `login_history`  
**Purpose:** Track all login attempts for fraud detection and audit trails

#### Attributes
| Attribute | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| userId | String(255) | Yes | - | ID of user attempting login |
| success | Boolean | Yes | - | Whether login was successful |
| timestamp | DateTime | Yes | - | When login attempt occurred |
| deviceFingerprint | String(255) | Yes | - | Unique device identifier |
| deviceName | String(255) | No | - | Human-readable device name |
| ipAddress | String(45) | No | - | IP address of login attempt |
| riskScore | Integer | No | 0 | Fraud risk score (0-100) |
| riskLevel | String(20) | No | 'low' | Risk level: low/medium/high/critical |

#### Indexes
- `userId_idx` (key) - For querying user's login history
- `timestamp_idx` (key, DESC) - For recent logins
- `success_idx` (key) - For filtering failed attempts

---

### 2. trusted_devices
**Collection ID:** `trusted_devices`  
**Purpose:** Store recognized/trusted devices for each user

#### Attributes
| Attribute | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| userId | String(255) | Yes | - | Owner user ID |
| deviceFingerprint | String(255) | Yes | - | Unique device identifier |
| deviceName | String(255) | Yes | - | Human-readable device name |
| trusted | Boolean | Yes | true | Whether device is trusted |
| lastUsed | DateTime | Yes | - | Last login from this device |
| createdAt | DateTime | Yes | - | When device was first registered |

#### Indexes
- `userId_idx` (key) - For querying user's devices
- `fingerprint_idx` (unique) - Prevent duplicate device registrations
- `userId_fingerprint_idx` (unique, composite: userId + deviceFingerprint)

---

### 3. security_alerts
**Collection ID:** `security_alerts`  
**Purpose:** Store security alerts for users (new device, suspicious activity, etc.)

#### Attributes
| Attribute | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| userId | String(255) | Yes | - | User to alert |
| type | String(50) | Yes | - | Alert type (new_device, failed_attempts, etc.) |
| severity | String(20) | Yes | 'medium' | Severity: low/medium/high/critical |
| message | String(500) | Yes | - | Alert message |
| acknowledged | Boolean | Yes | false | Whether user has seen the alert |
| timestamp | DateTime | Yes | - | When alert was created |
| metadata | String(1000) | No | - | Additional JSON data |

#### Indexes
- `userId_idx` (key) - For querying user's alerts
- `acknowledged_idx` (key) - For unread alerts
- `timestamp_idx` (key, DESC) - For recent alerts

---

## Setup Instructions

### Automated Setup (Recommended)

Create a new script `setup_security_collections.js`:

```javascript
const sdk = require('node-appwrite');

const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '6941cdb400050e7249d5';
const DATABASE_ID = '6941e2c2003705bb5a25';
const API_KEY = process.env.APPWRITE_API_KEY;

const client = new sdk.Client()
  .setEndpoint(ENDPOINT)
  .setProject(PROJECT_ID)
  .setKey(API_KEY);

const databases = new sdk.Databases(client);

async function createSecurityCollections() {
  // Create login_history collection
  await databases.createCollection(DATABASE_ID, 'login_history', 'Login History');
  await databases.createStringAttribute(DATABASE_ID, 'login_history', 'userId', 255, true);
  await databases.createBooleanAttribute(DATABASE_ID, 'login_history', 'success', true);
  // ... (add remaining attributes)
  
  // Create trusted_devices collection
  // ... (similar pattern)
  
  // Create security_alerts collection
  // ... (similar pattern)
}

createSecurityCollections().catch(console.error);
```

Run with:
```bash
APPWRITE_API_KEY=your_key node setup_security_collections.js
```

### Manual Setup

1. Go to Appwrite Console: https://cloud.appwrite.io
2. Select project: `6941cdb400050e7249d5`
3. Go to Databases → `cradi_database`
4. Create each collection with the attributes and indexes listed above

---

## Permissions

### login_history
- **Read:** Only user can read their own history
  - `read("user:{userId}")`
- **Create:** Authenticated users can create
  - `create("users")`
- **Update:** None (immutable records)
- **Delete:** Admins only

### trusted_devices  
- **Read:** Only device owner
  - `read("user:{userId}")`
- **Create:** Authenticated users
  - `create("users")`
- **Update:** Only device owner
  - `update("user:{userId}")`
- **Delete:** Only device owner
  - `delete("user:{userId}")`

### security_alerts
- **Read:** Only alert recipient
  - `read("user:{userId}")`
- **Create:** System/admins
  - `create("users")`
- **Update:** Only recipient (to acknowledge)
  - `update("user:{userId}")`
- **Delete:** Admins only

---

## Usage Examples

### Record Login Attempt
```dart
await appwrite.createDocument(
  collectionId: 'login_history',
  data: {
    'userId': user.$id,
    'success': true,
    'timestamp': DateTime.now().toIso8601String(),
    'deviceFingerprint': fingerprint,
    'deviceName': await deviceService.getDeviceName(),
    'riskScore': 10,
    'riskLevel': 'low',
  },
);
```

### Check Trusted Device
```dart
final devices = await appwrite.listDocuments(
  collectionId: 'trusted_devices',
  queries: [
    'userId=${user.$id}',
    'deviceFingerprint=$fingerprint',
  ],
);

final isTrusted = devices.total > 0;
```

### Create Security Alert
```dart
await appwrite.createDocument(
  collectionId: 'security_alerts',
  data: {
    'userId': user.$id,
    'type': 'new_device',
    'severity': 'medium',
    'message': 'New device login detected from ${deviceName}',
    'acknowledged': false,
    'timestamp': DateTime.now().toIso8601String(),
  },
);
```
