import 'package:appwrite/appwrite.dart' as aw;
import 'package:flutter_test/flutter_test.dart';

import 'package:climate_app/core/services/appwrite/appwrite_auth_backend.dart';
import 'package:climate_app/core/services/appwrite/appwrite_data_backend.dart';
import 'package:climate_app/core/services/auth_backend.dart';

import 'live_appwrite.dart';

/// `signInWithPassword` against a real Appwrite.
///
/// This is the oldest open gap in the migration. Appwrite answers
/// `createEmailPasswordSession` with the session in three `Set-Cookie`
/// headers, and the SDK's IO client is supposed to keep them — against
/// this stack it did not, so the session was created and the very next
/// call was a guest. Not a timing race, and the fallback header
/// Appwrite exposes for exactly that case is browser-only in the SDK.
///
/// Every other live test therefore authenticated with `setSession` and
/// a server-minted secret, which is the path sign-up and recovery take
/// and is not the path a returning user takes. So the one call every
/// returning user makes was the one call nothing exercised.
///
/// The adapter now reads the secret out of the session it was handed
/// and sets it explicitly, the same way `_establish` does. These tests
/// are what says so.
void main() {
  if (!liveConfigured) {
    test('sign-in integration tests', () {}, skip: skipUnlessLive);
    return;
  }

  useLiveAppwrite();

  late AppwriteDataBackend backend;
  late AppwriteAuthBackend auth;

  setUp(() {
    AppwriteDataBackend.installErrorVocabulary();
    backend = AppwriteDataBackend(
      client: aw.Client().setEndpoint(liveEndpoint).setProject(liveProject),
    );
    auth = AppwriteAuthBackend(data: backend);
  });

  tearDown(() async {
    await auth.signOut();
    auth.dispose();
  });

  test(
    'signs in with a password and the next call is still that user',
    () async {
      final outcome = await auth.signInWithPassword(
        email: liveEmail,
        password: livePassword,
      );
      expect(outcome.hasSession, isTrue);
      expect(outcome.user?.id, liveUserId);

      // The assertion the gap was about. `signInWithPassword` already
      // calls `account.get()` once; this is a *second* request on the same
      // client, after the sign-in returned, which is where the session
      // used to have evaporated.
      final again = await aw.Account(backend.client).get();
      expect(again.$id, liveUserId, reason: 'the session did not survive');
    },
  );

  test('a read that needs the session works after signing in', () async {
    await auth.signInWithPassword(email: liveEmail, password: livePassword);

    // `profiles` is readable by its owner and by staff labels, so this
    // returns a row only for an authenticated caller. A guest gets an
    // empty page with a 200, which is the shape the whole gap hid in.
    final profile = await backend.getDocument(
      collectionId: 'profiles',
      documentId: liveUserId,
    );
    expect(profile['id'] ?? profile['\$id'], liveUserId);
  });

  test('the session is gone after signing out', () async {
    await auth.signInWithPassword(email: liveEmail, password: livePassword);
    await auth.signOut();

    expect(auth.currentUser, isNull);
    await expectLater(
      aw.Account(backend.client).get(),
      throwsA(isA<aw.AppwriteException>()),
    );
  });

  test('a wrong password is refused, and leaves no session behind', () async {
    await expectLater(
      auth.signInWithPassword(email: liveEmail, password: 'not-the-password'),
      throwsA(
        isA<AuthBackendException>().having(
          (e) => e.failure,
          'failure',
          AuthFailure.invalidCredentials,
        ),
      ),
    );
    expect(auth.currentUser, isNull);
  });
}
