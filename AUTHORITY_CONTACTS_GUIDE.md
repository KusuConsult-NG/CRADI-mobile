# 📞 Authority Contacts - Data Collection Guide

## Overview

The CRADI Mobile app includes a comprehensive database of emergency contacts and disaster management authorities. However, **placeholder phone numbers** are currently used for state-level authorities that require real contact information.

---

## ⚠️ Placeholders That Need Real Numbers

### Benue State

1. **State Emergency Management Agency (SEMA)**
   - Role: State Emergency Management Director
   - Current: `+2348000000000` ❌ PLACEHOLDER
   - Office: Benue SEMA Headquarters, Makurdi
   - Email: sema@benuestate.gov.ng

2. **Police Commissioner**
   - Role: Commissioner of Police, Benue State
   - Current: `+2348000000001` ❌ PLACEHOLDER
   - Office: Benue State Police Command, Makurdi

---

### Nasarawa State

3. **State Emergency Management Agency (SEMA)**
   - Role: State Emergency Management Director
   - Current: `+2348000000002` ❌ PLACEHOLDER
   - Office: Nasarawa SEMA Headquarters, Lafia
   - Email: sema@nasarawastate.gov.ng

4. **Police Commissioner**
   - Role: Commissioner of Police, Nasarawa State
   - Current: `+2348000000003` ❌ PLACEHOLDER
   - Office: Nasarawa State Police Command, Lafia

---

### Plateau State

5. **State Emergency Management Agency (SEMA)**
   - Role: State Emergency Management Director
   - Current: `+2348000000004` ❌ PLACEHOLDER
   - Office: Plateau SEMA Headquarters, Jos
   - Email: sema@plateaustate.gov.ng

6. **Police Commissioner**
   - Role: Commissioner of Police, Plateau State
   - Current: `+2348000000005` ❌ PLACEHOLDER
   - Office: Plateau State Police Command, Jos

---

## 📋 Data Collection Process

### Recommended Approach:

1. **Official Government Contacts**
   - Contact each state's SEMA office directly
   - Request official emergency hotline numbers
   - Obtain written permission to publish contact information

2. **Police Commands**
   - Visit or call each State Police Command
   - Request the Commissioner's office emergency contact line
   - Verify it's a publicly shareable number for emergency reports

3. **Verification**
   - Test each number before updating the app
   - Confirm the contact person/office answers
   - Document date of verification

---

## 🔧 How to Update Contacts

Once you have the real contact numbers:

1. Open: `/Users/mac/CRADI Mobile/lib/core/data/authority_contacts_data.dart`

2. Find the `_stateAuthorities` section (starts around line 47)

3. Update each placeholder:
   ```dart
   // BEFORE:
   phone: '+2348000000000', // Placeholder: Update with real number
   
   // AFTER:
   phone: '+2348012345678', // Verified 2026-01-10
   ```

4. Add verification notes in comments

5. Remove the TODO comments after updating

---

## ✅ LGA-Level Contacts

**Good news:** LGA-level contacts (Local Government Chairmen, DPOs, Extension Officers) are **auto-generated** for all 53 LGAs using a consistent algorithm.

These placeholder numbers follow a pattern and can be updated later as real contacts are obtained. They are lower priority since the app will still function with state-level contacts for emergency routing.

---

## 📊 Current Status

- **State-level placeholders:** 6 contacts need updating
- **LGA-level contacts:** 159 auto-generated (can be gradually updated)
- **Impact:** High – state contacts are primary emergency routing contacts

---

## 🚀 Deployment Options

### Option 1: Update Before Launch (Recommended)
- Obtain all 6 state contacts
- Update authority_contacts_data.dart
- Rebuild app with real numbers
- ✅ Launch with full functionality

### Option 2: Launch with Placeholders + OTA Update
- Launch app with current placeholders
- Add in-app notification: "Real emergency contacts coming soon"
- Update contacts via app update once obtained
- ⚠️ Users won't receive automated alerts to authorities until updated

### Option 3: Hybrid Approach
- Use national emergency numbers (e.g., 112, 199 for police)
- Update state-specific contacts as they become available
- Release incremental updates

---

## 📝 Template for Government Contact Request

```
Subject: Request for Emergency Contact Information - CRADI Mobile App

Dear [SEMA Director/Police Commissioner],

We are launching CRADI Mobile, a climate and disaster early warning system 
for communities in [State Name]. The app enables citizens to report hazards 
and receive emergency alerts.

We would like to include your office's emergency contact number in our 
authority database to:
1. Enable automated alert notifications for verified hazard reports
2. Provide citizens with direct emergency contact information
3. Facilitate rapid response to climate/disaster incidents

Could you please provide:
- Emergency hotline number (publicly shareable)
- Official office email
- Preferred contact hours (if applicable)

We will ensure proper attribution and only use this information for 
emergency notification purposes.

Best regards,
[Your Name]
CRADI Mobile Team
```

---

## 🎯 Next Steps

1. Send contact requests to all 6 state offices
2. Track responses in a spreadsheet
3. Update contacts as received
4. Test each number before deploying
5. Document verification dates

**Timeline estimate:** 2-7 days (depending on government response times)
