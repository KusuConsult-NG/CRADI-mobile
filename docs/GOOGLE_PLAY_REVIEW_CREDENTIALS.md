# Google Play review test account

Google Play reviewers need a working account, because the app is unusable
without signing in. This page explains how to set one up and what to paste into
the Play Console.

> **The credentials themselves are not in this file, and must not be.**
> This repository is public. An earlier version of this page contained the
> reviewer account's real email, password and registration code in plain text,
> so **those accounts are compromised and must be rotated** — see
> "Rotating the old ones" below. Keep the current values in your team's
> password manager and paste them straight into the Play Console.

## What the reviewer needs

Sign-in takes three things, which is unusual enough that reviewers will reject
the build if you don't explain it:

1. Email address
2. Registration code (format `CRD######`)
3. Password

## Creating the account

1. **Supabase dashboard → Authentication → Users → Add user.** Use an address
   on a domain you control. Tick **Auto Confirm User** — an unconfirmed account
   cannot be approved, and the reviewer will be locked out.
2. **Approve the profile**, so the account is past the pending-approval screen:

   ```sql
   update public.profiles
      set is_approved = true, is_disabled = false
    where email = 'REVIEWER_EMAIL_HERE'
   returning id, email, role, is_approved;
   ```

   Leave `role` as `user` unless the reviewer needs to see staff screens. A
   reviewer account with admin rights can change other people's roles, so give
   it the lowest role that still shows the features under review.
3. **Set the registration code** to whatever you will give the reviewer, and
   record it in the password manager alongside the password.
4. **Sign in with it yourself** on a real build before submitting. Most review
   rejections for this app will be a test account that was never tried.

## What to paste into the Play Console

Under *App content → App access → All or some functionality is restricted*, add
the username, password and this note:

```
Sign-in requires three fields:
  1. Email address
  2. Registration code (format CRD######)
  3. Password

The registration code is provided with these credentials. The account has
full access to hazard reporting, peer verification, alerts, the knowledge
base and emergency contacts.
```

Put the registration code in the password field alongside the password, or in
the instructions box — the Play Console has no third field for it.

## Keeping it working

The account can stop working between submissions:

- **Rate limiting** locks an account after repeated failed sign-ins. If a
  reviewer reports being locked out, clear the lock rather than making a new
  account.
- **`app_min_version`** blocks every build below the configured minimum. If you
  raise it (see `docs/DEPLOYMENT.md`), the reviewer's build must be at or above
  it, or they will see only the update screen.
- **A disabled or unapproved profile** shows the pending-approval screen. Check
  `is_approved` and `is_disabled` before each submission.

## Rotating the old ones

Two accounts were published in this file's git history, with their passwords
and registration codes. Git history is public and cannot be unpublished, so:

1. Change both passwords in Supabase (Authentication → Users → the user →
   Reset password), or delete the accounts and create fresh ones.
2. Change their registration codes.
3. Store the new values in the password manager, not here.

The accounts are ordinary user accounts with no admin rights, so the exposure
is limited to those two accounts — but anyone can still sign in as them and
submit reports that look like they came from your test users.
