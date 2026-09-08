# Manual Function Deployment Instructions

## Statistics Aggregation Function
✅ **No code changes needed** - Collection is now fixed with all attributes

## Escalation Timer Function  
❌ **Requires code update**

### The Fix

**File**: `functions/escalation-timer/src/index.js`  
**Line 35**: Change from `submittedAt` to `$createdAt`

**Before**:
```javascript
sdk.Query.lessThan('submittedAt', thirtyMinutesAgo),
```

**After**:
```javascript
sdk.Query.lessThan('$createdAt', thirtyMinutesAgo),
```

### Deployment Options

#### Option 1: Appwrite Console (Easiest)

1. Go to: https://cloud.appwrite.io/console/project-6941cdb400050e7249d5/functions

2. Click on `escalation-timer` function

3. Go to "Settings" tab

4. Scroll to "Code" or look for inline code editor

5. Find line 35 and change:
   ```javascript
   sdk.Query.lessThan('submittedAt', thirtyMinutesAgo),
   ```
   to:
   ```javascript
   sdk.Query.lessThan('$createdAt', thirtyMinutesAgo),
   ```

6. Click "Save" or "Deploy"

7. Wait for deployment to complete

#### Option 2: Copy Fixed File

I've created a fixed version at:
```
functions/escalation-timer/src/index.FIXED.js
```

Steps:
1. Copy the FIXED file content
2. Replace `functions/escalation-timer/src/index.js` with it
3. Deploy via CLI:
   ```bash
   appwrite deploy function --functionId escalation-timer
   ```

#### Option 3: Manual Edit

Simply open `functions/escalation-timer/src/index.js` in your editor and change line 35, then redeploy.

### Verify Deployment

After deploying, run the health check:
```bash
cd "/Users/mac/CRADI Mobile/scripts"
APPWRITE_API_KEY=your_key node check_cloud_functions.js
```

Expected output:
```
✅ escalation-timer: Healthy
✅ statistics-aggregation: Healthy  
✅ verification-request: Healthy
```

---

## Why This Fix Works

**Problem**: The reports collection doesn't have a custom `submittedAt` field

**Solution**: Use Appwrite's built-in `$createdAt` timestamp instead

**Impact**: Function will now successfully query and escalate pending reports
