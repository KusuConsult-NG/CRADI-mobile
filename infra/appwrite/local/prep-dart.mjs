/**
 * Prepares a verified account for the Dart integration tests and prints
 * `--dart-define` flags for it.
 *
 *   source infra/appwrite/local/.env.local
 *   eval "$(node infra/appwrite/local/prep-dart.mjs)"
 *
 * The Flutter SDK deliberately has no `setKey` — an API key must never
 * ship in an app — so the Dart tests authenticate as a user, which is
 * how the app works and therefore what is worth testing.
 */
const EP = process.env.APPWRITE_ENDPOINT;

/*
 * Local only, and now enforced.
 *
 * This script creates verified accounts whose password is the literal below, in
 * a repository, gives them `label:ewr` and `label:approved`, writes a profile
 * and a report, and cleans up nothing. All of that is fine against a throwaway
 * stack and is a published staff credential anywhere else — and it reached the
 * production Cloud project, eleven times, because nothing stopped it from
 * following whatever `APPWRITE_ENDPOINT` happened to be exported. The accounts
 * it left there had to be found by a password audit weeks later.
 *
 * `ALLOW_REMOTE=1` is deliberately awkward: there is no good reason to want it.
 */
const LOCAL = /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\]|appwrite\.local)(:|\/|$)/;
if (!LOCAL.test(String(EP ?? '')) && process.env.ALLOW_REMOTE !== '1') {
  console.error(
    `Refusing to run against ${EP || '(APPWRITE_ENDPOINT unset)'}.\n` +
      'This creates accounts with a password that is a literal in this' +
      " repository, grants them staff labels, and deletes nothing. It is for a\n" +
      'local stack only — see infra/appwrite/local/.env.local. Set ALLOW_REMOTE=1' +
      ' only if you are certain, and clean up after yourself.',
  );
  process.exit(2);
}
const H = {
  'content-type': 'application/json',
  'x-appwrite-project': process.env.APPWRITE_PROJECT_ID,
  'x-appwrite-key': process.env.APPWRITE_API_KEY,
};
const DB = process.env.APPWRITE_DATABASE_ID ?? 'cradi';

const call = async (p, o = {}) => {
  const r = await fetch(`${EP}${p}`, { ...o, headers: H });
  const t = await r.text();
  let b = null;
  if (t) { try { b = JSON.parse(t); } catch { b = { message: t }; } }
  if (!r.ok) throw new Error(`${p} -> ${r.status} ${JSON.stringify(b).slice(0, 200)}`);
  return b;
};

const stamp = Date.now();
const id = `dart-${stamp}`.slice(0, 36);
const email = `${id}@example.test`;
const password = 'DartTestPassword123!';

await call('/users', {
  method: 'POST',
  body: JSON.stringify({ userId: id, email, password, name: 'Dart Test' }),
});
// Verified, so a sign-in is not refused for being unconfirmed — the
// adapter signs an unverified account straight back out.
await call(`/users/${id}/verification`, {
  method: 'PATCH',
  body: JSON.stringify({ emailVerification: true }),
});
await call(`/tablesdb/${DB}/tables/profiles/rows`, {
  method: 'POST',
  body: JSON.stringify({
    rowId: id,
    data: {
      // `ewr`, not `ewm`: a ward monitor may vote but may not reopen a
      // report, and the suite exercises `callOperation` through
      // `reopen_report`. A reviewer can do everything a monitor can
      // here and that one thing more. Who may reopen is a policy
      // question, covered by the Function's unit tests and by
      // `e2e-operation.mjs`; this account exists to exercise the
      // adapters.
      name: 'Dart Test', role: 'ewr', email,
      state: 'Benue', lga: 'Makurdi', ward: 'North Bank I',
      isApproved: true, isDisabled: false, isVerified: true,
    },
    permissions: [`read("user:${id}")`],
  }),
});

/**
 * A session secret, minted server-side.
 *
 * Most of the Dart tests set it with `Client.setSession` rather than
 * signing in, because it is one fewer thing for a data-adapter test to
 * depend on. `appwrite_sign_in_live_test.dart` signs in properly with
 * the email and password below, which is the path a returning user
 * takes and which went unexercised for a long time.
 */
const session = await call(`/users/${id}/sessions`, { method: 'POST' });

/**
 * A pending report filed by **somebody else**, in the same ward.
 *
 * `callOperation` is exercised through `reopen_report`, and a reviewer
 * may not decide their own report — `You cannot approve or reject your
 * own report`, which is the rule working. A test that files its own
 * report can therefore never reach the operation, so the report it
 * decides has to come from elsewhere, and only a key can make one on
 * another account's behalf.
 */
const reporterId = `dart-reporter-${stamp}`.slice(0, 36);
await call('/users', {
  method: 'POST',
  body: JSON.stringify({
    userId: reporterId,
    email: `${reporterId}@example.test`,
    password,
    name: 'Dart Reporter',
  }),
});
await call(`/tablesdb/${DB}/tables/profiles/rows`, {
  method: 'POST',
  body: JSON.stringify({
    rowId: reporterId,
    data: {
      name: 'Dart Reporter', role: 'user', email: `${reporterId}@example.test`,
      state: 'Benue', lga: 'Makurdi', ward: 'North Bank I',
      isApproved: true, isDisabled: false, isVerified: true,
    },
    permissions: [`read("user:${reporterId}")`],
  }),
});
const foreignReportId = `dart-foreign-${stamp}`.slice(0, 36);
await call(`/tablesdb/${DB}/tables/reports/rows`, {
  method: 'POST',
  body: JSON.stringify({
    rowId: foreignReportId,
    data: {
      userId: reporterId,
      reporterName: 'Dart Reporter',
      hazardType: 'Flooding',
      severity: 'high',
      description: `Filed by someone else, for the reopen test (${stamp})`,
      state: 'Benue', lga: 'Makurdi', ward: 'North Bank I',
      status: 'pending',
      verificationCount: 0,
      isAlert: false, escalated: false, autoValidated: false,
      submittedAt: new Date().toISOString(),
      imageUrls: [],
    },
    // Readable by the ward team the reviewer belongs to, and by staff.
    permissions: ['read("label:ewr")', 'read("label:admin")', 'read("label:ewv")'],
  }),
});

// The labels every `read("label:…")` ACL is matched against. Without
// them the reviewer reads nothing, with a 200 and an empty page.
await call(`/users/${id}/labels`, {
  method: 'PUT',
  body: JSON.stringify({ labels: ['ewr', 'approved'] }),
});

process.stdout.write(
  `export DART_TEST_SESSION='${session.secret}'\n` +
    `export DART_TEST_EMAIL='${email}'\n` +
    `export DART_TEST_PASSWORD='${password}'\n` +
    `export DART_TEST_USER_ID='${id}'\n` +
    `export DART_TEST_FOREIGN_REPORT='${foreignReportId}'\n`,
);
