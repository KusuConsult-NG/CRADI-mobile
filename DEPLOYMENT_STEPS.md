# Step-by-Step Deployment Guide

## Step 1: Fix Escalation Timer in Appwrite Console

### 1.1 Login to Appwrite
1. Open browser and go to: https://cloud.appwrite.io/console
2. Login with your credentials
3. Select the CRADI Mobile project (ID: 6941cdb400050e7249d5)

### 1.2 Navigate to Functions
1. Click on "Functions" in the left sidebar
2. You should see 3 functions:
   - escalation-timer
   - verification-request  
   - statistics-aggregation
   - alert-distribution

### 1.3 Edit Escalation Timer
1. Click on `escalation-timer` function
2. Look for tabs: Overview, Settings, Deployments, Executions, Logs
3. Go to **Settings** tab
4. Scroll down to find the code editor or deployment section
5. Look for **line 35** in the code (or search for `submittedAt`)

### 1.4 Make the Fix
Find this line (around line 35):
```javascript
sdk.Query.lessThan('submittedAt', thirtyMinutesAgo),
```

Change it to:
```javascript
sdk.Query.lessThan('$createdAt', thirtyMinutesAgo),
```

### 1.5 Save and Deploy
1. Click "Save" or "Update" button
2. Click "Deploy" or "Redeploy" if prompted
3. Wait for deployment to complete (usually 30-60 seconds)
4. You should see a green "Deployed" or "Active" status

**✅ Checkpoint**: Escalation timer should now show "Active" status

---

## Step 2: Deploy Admin Panel to Vercel

### 2.1 Run Vercel Deploy Command
```bash
cd /Users/mac/cradi-admin
vercel --prod
```

### 2.2 Answer Prompts
When Vercel asks:
- "Set up and deploy ~/cradi-admin?" → **Y** (Yes)
- "Which scope?" → Choose your account
- "Link to existing project?" → **N** (No, create new)
- "What's your project's name?" → **cradi-admin** (or keep default)
- "In which directory is your code located?" → **./** (press Enter)
- "Want to modify settings?" → **N** (No)

### 2.3 Wait for Deployment
- Vercel will build and deploy (2-5 minutes)
- You'll see progress bars for:
  - Build
  - Upload
  - Deploy

### 2.4 Get Production URL
After successful deployment, you'll see:
```
✅ Production: https://cradi-admin-xxxxx.vercel.app
```

**Copy this URL** - you'll need it!

### 2.5 Configure Environment Variables
1. Go to https://vercel.com/dashboard
2. Find your cradi-admin project
3. Click on it
4. Go to "Settings" tab
5. Click "Environment Variables"
6. Add these variables (click "Add" for each):

```
NEXT_PUBLIC_APPWRITE_ENDPOINT=https://fra.cloud.appwrite.io/v1
NEXT_PUBLIC_APPWRITE_PROJECT=6941cdb400050e7249d5
NEXT_PUBLIC_DATABASE_ID=6941e2c2003705bb5a25
```

7. Click "Save"
8. Redeploy to apply changes (Deployments tab → Click "..." → Redeploy)

**✅ Checkpoint**: You should be able to visit your production URL and see the login page

---

## Step 3: Verify Cloud Functions

### 3.1 Run Health Check
```bash
cd "/Users/mac/CRADI Mobile/scripts"
APPWRITE_API_KEY=standard_d729300d2e6a8637d544c72c97716b6aa1a250dd1956e6a63d8e9d5f710fee1689d75777a18afb2891581d6637fca79e220936bac20085cf2121ede97bc2df44daca7cd0465cc938477f1240536ac617653cfbbae7f9b3ea3a76c61be527045cf6c0e6b471cf516ae03137e3e11231a16b1b3dfeae612ba17d74d42a0bc9a52d node check_cloud_functions.js
```

### 3.2 Expected Results
```
✅ escalation-timer: Healthy (0% error rate)
✅ statistics-aggregation: Healthy  
✅ verification-request: Healthy
```

If you still see errors:
- Check the function logs in Appwrite Console
- Verify the code change was saved correctly
- Try manually triggering the function

---

## Step 4: Test Admin Panel

### 4.1 Login
1. Go to your production URL from Step 2
2. Login with:
   - Email: `admin@cradi.org`
   - Password: `CradiAdmin2026!`

### 4.2 Verify Dashboard
You should see:
- Total users count
- Total reports count
- Verification requests count
- System statistics

### 4.3 Test Features
- Click on "Users" - should load user list
- Click on "Reports" - should load reports list
- Try filtering or searching

**✅ Checkpoint**: Admin panel fully functional

---

## Quick Reference

### Appwrite Console
```
https://cloud.appwrite.io/console/project-6941cdb400050e7249d5
```

### Admin Login Credentials
```
Email: admin@cradi.org
Password: CradiAdmin2026!
```

### Function to Fix
```
Function: escalation-timer
Line: 35
Change: submittedAt → $createdAt
```

---

## Troubleshooting

### Issue: Can't find code editor in Appwrite
**Solution**: Look for "Deployments" tab, click latest deployment, then "View Code" or edit inline

### Issue: Vercel deployment failing
**Solution**: Check that:
- You're in the correct directory (`/Users/mac/cradi-admin`)
- `npm install` has been run
- `package.json` exists

### Issue: Admin panel login fails
**Solution**: Verify:
- Environment variables are set in Vercel
- You redeployed after adding env vars
- Using correct credentials

### Issue: Cloud functions still failing
**Solution**:
- Check function logs in Appwrite Console (Functions → escalation-timer → Logs)
- Verify environment variables set (DATABASE_ID, REPORTS_COLLECTION_ID)
- Try manual execution to see real-time error

---

## Success Criteria

After completing all steps, you should have:

- ✅ Escalation timer deployed and healthy (0% errors)
- ✅ Statistics aggregation working (0% errors)  
- ✅ Admin panel deployed to Vercel
- ✅ Admin panel accessible via production URL
- ✅ Admin login working
- ✅ Dashboard loading data from Appwrite

**Next**: Phase 2 - Testing & Validation
