import 'dart:async';

import 'package:climate_app/core/services/auth_backend.dart';

/// An [AuthBackend] for tests that only need "who is signed in".
///
/// Before the data seam existed these tests faked `SupabaseService` and got
/// the account from `getCurrentUser()`, which meant every one of them named
/// the vendor to assert something about a profile screen.
class FakeAuthBackend implements AuthBackend {
  FakeAuthBackend([this.user]);

  AuthUser? user;

  @override
  bool get isConfigured => true;

  @override
  Stream<AuthChange> get changes => const Stream<AuthChange>.empty();

  @override
  AuthUser? get currentUser => user;

  @override
  bool get hasSession => user != null;

  @override
  bool get isSessionExpired => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
