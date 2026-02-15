# Escalation Timer Fix - Manual Deployment

## ✅ Code Fix Applied Successfully!

The bug has been automatically fixed in:
```
functions/escalation-timer/src/index.js
```

**Change made**:
```diff
- sdk.Query.lessThan('submittedAt', thirtyMinutesAgo)
+ sdk.Query.lessThan('$createdAt', thirtyMinutesAgo)
```

**Backup created**:
```
functions/escalation-timer/src/index.js.backup
```

---

## Deploy to Appwrite

The code is fixed, but you need to deploy it manually.

### Option 1: Appwrite CLI (Recommended)

```bash
cd "/Users/mac/CRADI Mobile"
appwrite deploy function
```

When prompted:
- Select `escalation-timer` from the list
- Confirm deployment

### Option 2: Appwrite Console (Alternative)

1. Go to: https://cloud.appwrite.io/console/project-6941cdb400050e7249d5/functions
2. Click `escalation-timer`
3. Go to "Deployments" tab
4. Click "Create Deployment"
5. Upload the fixed `src/index.js` file
6. Or paste the code directly
7. Click "Deploy"

---

## Verify Deployment

After deploying, run the health check:

```bash
cd "/Users/mac/CRADI Mobile/scripts"
APPWRITE_API_KEY=standard_d729300d2e6a8637d544c72c97716b6aa1a250dd1956e6a63d8e9d5f710fee1689d75777a18afb2891581d6637fca79e220936bac20085cf2121ede97bc2df44daca7cd0465cc938477f1240536ac617653cfbbae7f9b3ea3a76c61be527045cf6c0e6b471cf516ae03137e3e11231a16b1b3dfeae612ba17d74d42a0bc9a52d node check_cloud_functions.js
```

Expected result:
```
✅ escalation-timer: Healthy
```

---

## Summary

- ✅ Code fixed locally
- ✅ Backup created
- ⏳ Deployment pending (manual step required)
- ⏳ Verification pending
