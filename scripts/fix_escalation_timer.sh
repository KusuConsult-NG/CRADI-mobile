#!/bin/bash

###############################################################################
# Automated Escalation Timer Fix & Deployment
# 
# This script:
# 1. Backs up the original function
# 2. Fixes the submittedAt -> $createdAt bug
# 3. Deploys the fixed function to Appwrite
###############################################################################

set -e  # Exit on error

echo "🔧 Automated Escalation Timer Fix"
echo "=================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Paths
FUNCTION_FILE="functions/escalation-timer/src/index.js"
BACKUP_FILE="functions/escalation-timer/src/index.js.backup"
PROJECT_DIR="/Users/mac/CRADI Mobile"

cd "$PROJECT_DIR"

# Check if function file exists
if [ ! -f "$FUNCTION_FILE" ]; then
    echo -e "${RED}❌ Error: Function file not found at $FUNCTION_FILE${NC}"
    exit 1
fi

echo "📁 Found function file: $FUNCTION_FILE"

# Check if already fixed
if grep -q "sdk.Query.lessThan('\$createdAt'" "$FUNCTION_FILE"; then
    echo -e "${GREEN}✅ Function is already fixed!${NC}"
    echo ""
    echo "The code already uses \$createdAt instead of submittedAt."
    echo "Do you want to redeploy anyway? (y/n)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Skipping deployment."
        exit 0
    fi
else
    echo "🔍 Detected bug: Function uses 'submittedAt' instead of '\$createdAt'"
    echo ""
    
    # Create backup
    echo "💾 Creating backup..."
    cp "$FUNCTION_FILE" "$BACKUP_FILE"
    echo -e "${GREEN}✅ Backup created: $BACKUP_FILE${NC}"
    echo ""
    
    # Fix the bug using sed (macOS compatible)
    echo "🔨 Applying fix..."
    sed -i '' "s/sdk.Query.lessThan('submittedAt'/sdk.Query.lessThan('\$createdAt'/g" "$FUNCTION_FILE"
    
    # Also fix the comment if it exists
    sed -i '' "s/Get pending reports submitted/Get pending reports created/g" "$FUNCTION_FILE"
    
    # Verify the fix
    if grep -q "sdk.Query.lessThan('\$createdAt'" "$FUNCTION_FILE"; then
        echo -e "${GREEN}✅ Fix applied successfully!${NC}"
        echo ""
        
        # Show the change
        echo "📝 Changes made:"
        echo -e "${RED}- sdk.Query.lessThan('submittedAt', thirtyMinutesAgo)${NC}"
        echo -e "${GREEN}+ sdk.Query.lessThan('\$createdAt', thirtyMinutesAgo)${NC}"
        echo ""
    else
        echo -e "${RED}❌ Fix failed! Restoring backup...${NC}"
        cp "$BACKUP_FILE" "$FUNCTION_FILE"
        exit 1
    fi
fi

# Check if Appwrite CLI is installed
if ! command -v appwrite &> /dev/null; then
    echo -e "${YELLOW}⚠️  Appwrite CLI not found${NC}"
    echo ""
    echo "Option 1: Install Appwrite CLI"
    echo "  npm install -g appwrite-cli"
    echo ""
    echo "Option 2: Deploy manually via Appwrite Console"
    echo "  Go to: https://cloud.appwrite.io/console/project-6941cdb400050e7249d5/functions"
    echo "  Click: escalation-timer → Settings → Update Code"
    echo ""
    echo "The fix has been applied to your local file."
    exit 0
fi

echo "🚀 Deploying to Appwrite..."
echo ""

# Deploy the function
if appwrite deploy function --functionId escalation-timer; then
    echo ""
    echo -e "${GREEN}✅ Deployment successful!${NC}"
    echo ""
    echo "🎉 Escalation Timer has been fixed and deployed!"
    echo ""
    echo "Next steps:"
    echo "1. Run health check: APPWRITE_API_KEY=key node scripts/check_cloud_functions.js"
    echo "2. Check function logs in Appwrite Console"
    echo "3. Verify it runs without errors in 5 minutes"
    echo ""
else
    echo ""
    echo -e "${RED}❌ Deployment failed${NC}"
    echo ""
    echo "The code has been fixed locally, but deployment failed."
    echo "Please deploy manually via Appwrite Console:"
    echo "https://cloud.appwrite.io/console/project-6941cdb400050e7249d5/functions"
    echo ""
    exit 1
fi
