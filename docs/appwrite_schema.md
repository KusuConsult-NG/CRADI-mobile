# Appwrite Database Schema Setup

## Database Configuration

**Database ID**: `cradi_database`
**Database Name**: CRADI Database

---

## Collections

### 1. Users Collection
**Collection ID**: `users`

| Attribute | Type | Size | Required | Array | Default |
|-----------|------|------|----------|-------|---------|
| email | string | 255 | Yes | No | - |
| name | string | 255 | Yes | No | - |
| role | string | 50 | Yes | No | ewm |
| phoneNumber | string | 20 | No | No | - |
| profileImageId | string | 255 | No | No | - |
| registrationCode | string | 20 | No | No | - |
| biometricsEnabled | boolean | - | No | No | false |
| createdAt | datetime | - | Yes | No | - |
| lastLoginAt | datetime | - | No | No | - |

**Indexes:**
- email (unique)
- registrationCode (unique)
- role

**Permissions:**
- Create: Users
- Read: Users (own documents)
- Update: Users (own documents)
- Delete: Users (own documents)

---

### 2. Reports Collection
**Collection ID**: `reports`

| Attribute | Type | Size | Required | Array | Default |
|-----------|------|------|----------|-------|---------|
| userId | string | 255 | Yes | No | - |
| hazardType | string | 100 | Yes | No | - |
| severity | string | 50 | Yes | No | - |
| latitude | double | - | Yes | No | - |
| longitude | double | - | Yes | No | - |
| locationDetails | string | 500 | Yes | No | - |
| description | string | 2000 | No | No | - |
| imageIds | string | 255 | No | Yes | - |
| status | string | 50 | Yes | No | pending |
| isAlert | boolean | - | No | No | false |
| submittedAt | datetime | - | Yes | No | - |
| verificationCount | integer | - | No | No | 0 |

**Indexes:**
- userId
- status
| isAlert
- submittedAt (DESC)

**Permissions:**
- Create: Users
- Read: Any
- Update: Users (own documents)
- Delete: Users (own documents)

---

### 3. Messages Collection
**Collection ID**: `messages`

| Attribute | Type | Size | Required | Array | Default |
|-----------|------|------|----------|-------|---------|
| chatId | string | 255 | Yes | No | - |
| senderId | string | 255 | Yes | No | - |
| senderName | string | 255 | Yes | No | - |
| message | string | 5000 | Yes | No | - |
| type | string | 50 | Yes | No | text |
| sentAt | datetime | - | Yes | No | - |
| read | boolean | - | No | No | false |

**Indexes:**
- chatId
- sentAt (DESC)

**Permissions:**
- Create: Users
- Read: Users
- Update: Users (own documents)
- Delete: Users (own documents)

---

### 4. Emergency Contacts Collection
**Collection ID**: `emergency_contacts`

| Attribute | Type | Size | Required | Array | Default |
|-----------|------|------|----------|-------|---------|
| userId | string | 255 | Yes | No | - |
| name | string | 255 | Yes | No | - |
| phone | string | 20 | Yes | No | - |
| relationship | string | 100 | No | No | - |
| createdAt | datetime | - | Yes | No | - |

**Indexes:**
- userId

**Permissions:**
- Create: Users
- Read: Users (own documents)
- Update: Users (own documents)
- Delete: Users (own documents)

---

## Storage Buckets

### 1. Profile Images Bucket
**Bucket ID**: `profile_images`
**Bucket Name**: Profile Images

**Settings:**
- Maximum File Size: 5MB
- Allowed File Extensions: jpg, jpeg, png, webp
- Encryption: Enabled
- Antivirus: Enabled

**Permissions:**
- Create: Users
- Read: Any
- Update: Users
- Delete: Users

---

### 2. Report Images Bucket
**Bucket ID**: `report_images`
**Bucket Name**: Report Images

**Settings:**
- Maximum File Size: 10MB
- Allowed File Extensions: jpg, jpeg, png, webp
- Encryption: Enabled
- Antivirus: Enabled

**Permissions:**
- Create: Users
- Read: Any
- Update: Users
- Delete: Users

---

## Setup Instructions

1. Login to [Appwrite Console](https://cloud.appwrite.io)
2. Select project: **CRADI app** (ID: 6941cdb400050e7249d5)
3. Create Database:
   - Navigate to Databases → Create Database
   - Set ID: `cradi_database`
4. Create each collection with attributes as specified above
5. Create indexes for each collection
6. Set appropriate permissions
7. Navigate to Storage
8. Create both storage buckets with specified settings

---

## Notes

- All datetime fields should use ISO 8601 format
- User documents should be created immediately after account creation
- Report images should be uploaded to storage first, then IDs stored in reports collection
- Chat functionality will use messages collection with chatId grouping
