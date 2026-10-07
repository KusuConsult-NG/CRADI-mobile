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

**Register through the app**, on a build pointed at the project you are
submitting against. Not by hand in the console: sign-in needs a `profiles`
row carrying the registration code, and only registration creates one — a
user added in the console has an account and no profile, which signs in to
the pending-approval screen at best.

1. **Sign up in the app** with an address on a domain you control, and keep
   the registration code and password it was given. Record both in the
   password manager; they are not in this file and must not be.
2. **Confirm the address.** The app's own typed code does it. If the mail did
   not arrive, the Appwrite console (**Auth → Users →** the user) can mark
   the email verified — on the Supabase stack, **Authentication → Users →**
   the user → *Confirm email*.

   This is not optional: **the panel refuses to approve an account whose
   email and phone are both unconfirmed**, on either stack, and an
   unapproved reviewer is a locked-out reviewer.
3. **Approve it** in the admin panel: **Admin → Users →** find the account →
   **Approve**. Leave `role` as `user` unless the reviewer needs to see staff
   screens — a reviewer account with admin rights can change other people's
   roles, so give it the lowest role that still shows the features under
   review.
4. **Sign in with it yourself** on a real build before submitting. Most
   review rejections for this app will be a test account that was never
   tried.

> On the Appwrite stack, an account that signs in and then shows nothing is
> usually a labels problem rather than an approval one — Appwrite answers an
> unpermitted read with `200 {"total": 0}`. A plain `user` account needs no
> label, so this bites staff roles rather than reviewer accounts; see the
> README.

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
- **A disabled or unapproved profile** shows the pending-approval screen.
  Check it in the panel (Admin → Users) before each submission — the fields
  are `isApproved` / `isDisabled` on Appwrite and `is_approved` /
  `is_disabled` in Postgres.
- **The account belongs to one project.** A reviewer account made against
  Supabase does not exist on Appwrite, and which backend a build talks to is
  decided by its defines — so a release built with the `APPWRITE_*` secrets
  needs a reviewer account on the Appwrite project, created the same way
  above. Check this before the first submission after the cutover; the
  symptom is a reviewer reporting that correct credentials are rejected.

## Rotating the old ones

Two accounts were published in this file's git history, with their passwords
and registration codes. Git history is public and cannot be unpublished, so:

1. Change both passwords where those accounts live — the Supabase dashboard
   (Authentication → Users → the user → Reset password) for accounts created
   before the migration, the Appwrite console (Auth → Users → the user) for
   ones created after — or delete the accounts and create fresh ones.
2. Change their registration codes.
3. Store the new values in the password manager, not here.

The accounts are ordinary user accounts with no admin rights, so the exposure
is limited to those two accounts — but anyone can still sign in as them and
submit reports that look like they came from your test users.
