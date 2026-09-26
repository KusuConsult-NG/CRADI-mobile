import 'dart:io';

import 'package:climate_app/core/services/hive_encryption_service.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// The Hive boxes hold bare `Map`s with no schema or version stamp, so a
/// record written by an older build survives an app upgrade unchanged.
/// These tests put such records straight into the boxes and check that
/// reading them degrades gracefully instead of crashing on first launch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDir;
  final service = OfflineStorageService();

  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    hiveDir = Directory.systemTemp.createTempSync('offline_upgrade');
    Hive.init(hiveDir.path);
    await service.initialize();
  });

  tearDownAll(() async {
    await Hive.close();
    hiveDir.deleteSync(recursive: true);
  });

  Box<Map> drafts() => Hive.box<Map>('draft_reports');
  Box<Map> queue() => Hive.box<Map>('sync_queue');
  Box<Map> cache() => Hive.box<Map>('content_cache');

  setUp(() async {
    await drafts().clear();
    await queue().clear();
    await cache().clear();
  });

  group('drafts written by an older build', () {
    test('a draft missing most fields still lists and reads back', () async {
      await drafts().put('legacy', {'id': 'legacy', 'hazardType': 'flood'});
      final all = service.getAllDrafts();
      expect(all, hasLength(1));
      expect(all.single['hazardType'], 'flood');
      expect(service.getDraft('legacy'), isNotNull);
    });

    test('a draft with no createdAt sorts without throwing', () async {
      await drafts().put('a', {'id': 'a'});
      await drafts().put('b', {
        'id': 'b',
        'createdAt': DateTime.now().toIso8601String(),
      });
      expect(service.getAllDrafts(), hasLength(2));
    });

    test('an ownerless draft is offered to whoever is signed in', () async {
      await drafts().put('legacy', {'id': 'legacy'});
      expect(service.getDraftsFor('alice'), hasLength(1));
      expect(service.getDraftsFor(null), hasLength(1));
      // ...but is never uploaded automatically as theirs.
      expect(
        OfflineStorageService.isAutoSyncableDraft(
          drafts().get('legacy')!,
          'alice',
        ),
        isFalse,
      );
    });

    test(
      'a draft whose userId is not a string is treated as ownerless',
      () async {
        await drafts().put('weird', {'id': 'weird', 'userId': 42});
        expect(
          OfflineStorageService.draftOwner(drafts().get('weird')!),
          isNull,
        );
        expect(service.getDraftsFor('alice'), hasLength(1));
      },
    );

    test(
      'deleting a draft whose imagePaths is not a list does not throw',
      () async {
        // An older build stored a single path as a bare String.
        await drafts().put('old', {
          'id': 'old',
          'imagePaths': '/tmp/offline_images/one.jpg',
        });
        await expectLater(service.deleteDraft('old'), completes);
        expect(service.getDraft('old'), isNull);
      },
    );

    test(
      'deleting a draft with mixed-type imagePaths skips the junk',
      () async {
        await drafts().put('mixed', {
          'id': 'mixed',
          'imagePaths': ['/tmp/offline_images/gone.jpg', 7, null],
        });
        await expectLater(service.deleteDraft('mixed'), completes);
        expect(service.getDraft('mixed'), isNull);
      },
    );

    test('deleting a draft that is not there is a no-op', () async {
      await expectLater(service.deleteDraft('nope'), completes);
    });
  });

  group('sync-queue items written by an older build', () {
    test('a retryCount stored as a double is read as a count', () {
      expect(OfflineStorageService.retryCountOf({'retryCount': 3.0}), 3);
      expect(OfflineStorageService.retryCountOf({'retryCount': '4'}), 4);
      expect(OfflineStorageService.retryCountOf({}), 0);
      expect(OfflineStorageService.retryCountOf({'retryCount': null}), 0);
      expect(OfflineStorageService.retryCountOf({'retryCount': 'many'}), 0);
    });

    test('a failed item with a non-int retryCount is still terminal', () {
      expect(
        OfflineStorageService.isTerminalFailure({
          'status': 'failed',
          'retryCount': OfflineStorageService.maxSyncAttempts.toDouble(),
        }),
        isTrue,
      );
    });

    test(
      'markAsFailed on an item with a legacy retryCount increments it',
      () async {
        await queue().put('q1', {
          'queueId': 'q1',
          'status': 'pending',
          'retryCount': 2.0,
          'addedToQueueAt': DateTime.now().toIso8601String(),
        });
        await service.markAsFailed('q1', 'boom');
        expect(queue().get('q1')!['retryCount'], 3);
        expect(queue().get('q1')!['status'], 'failed');
      },
    );

    test('a flat (pre-wrapping) queue item still lists and filters', () async {
      await queue().put('flat', {
        'queueId': 'flat',
        'status': 'pending',
        'hazardType': 'flood',
        'userId': 'alice',
        'addedToQueueAt': DateTime.now().toIso8601String(),
      });
      expect(service.getSyncQueue(), hasLength(1));
      expect(service.getUnsyncedItems(userId: 'alice'), hasLength(1));
      expect(service.getUnsyncedItems(userId: 'bob'), isEmpty);
    });

    test('an item with no addedToQueueAt sorts without throwing', () async {
      await queue().put('a', {'queueId': 'a', 'status': 'pending'});
      await queue().put('b', {
        'queueId': 'b',
        'status': 'pending',
        'addedToQueueAt': DateTime.now().toIso8601String(),
      });
      expect(service.getSyncQueue(), hasLength(2));
      expect(service.getPendingSyncCount(), 2);
    });

    test(
      'markAsSynced / retryQueueItem on a missing item are no-ops',
      () async {
        await expectLater(service.markAsSynced('ghost'), completes);
        await expectLater(service.retryQueueItem('ghost'), completes);
        await expectLater(service.markAsRejected('ghost', 'x'), completes);
      },
    );

    test('retrying a rejected item puts it back in the queue', () async {
      await queue().put('q2', {
        'queueId': 'q2',
        'status': OfflineStorageService.statusRejected,
        'retryCount': 9,
        'addedToQueueAt': DateTime.now().toIso8601String(),
      });
      expect(service.getFailedSyncItems(), hasLength(1));
      await service.retryQueueItem('q2');
      expect(service.getFailedSyncItems(), isEmpty);
      expect(service.getPendingSyncCount(), 1);
    });
  });

  group('content cache written by an older build', () {
    test('a profile entry whose data is not a map reads as no cache', () async {
      await cache().put('user_profile', {
        'data': ['not', 'a', 'map'],
        'timestamp': DateTime.now().toIso8601String(),
      });
      expect(service.getCachedUserProfile(), isNull);
    });

    test('a profile entry with no timestamp is treated as stale', () async {
      await cache().put('user_profile', {
        'data': {'fullName': 'Ada'},
      });
      expect(service.getCachedUserProfile(), isNull);
    });

    test('a timestamp stored as a DateTime is understood', () async {
      await cache().put('user_profile', {
        'data': {'fullName': 'Ada'},
        'timestamp': DateTime.now(),
      });
      expect(service.getCachedUserProfile()?['fullName'], 'Ada');
    });

    test('an unparsable timestamp is treated as stale, not fatal', () async {
      await cache().put('alerts', {
        'data': [
          {'id': 'a1'},
        ],
        'timestamp': 'last tuesday',
      });
      expect(service.getCachedAlerts(), isEmpty);
    });

    test('a cache entry whose data is not a list reads as empty', () async {
      await cache().put('alerts', {
        'data': {'id': 'a1'},
        'timestamp': DateTime.now().toIso8601String(),
      });
      expect(service.getCachedAlerts(), isEmpty);
      await cache().put('verifications', {'data': 5});
      expect(service.getCachedVerifications(), isEmpty);
      await cache().put('guides', {'data': 'none'});
      expect(service.getCachedGuides(), isNull);
    });

    test(
      'a device clock in the future does not discard fresh alerts',
      () async {
        // The entry was written "tomorrow" (clock was wrong then, or is wrong
        // now): the age is negative, which must not read as stale.
        await cache().put('alerts', {
          'data': [
            {'id': 'a1'},
          ],
          'timestamp': DateTime.now()
              .add(const Duration(days: 2))
              .toIso8601String(),
        });
        expect(service.getCachedAlerts(), hasLength(1));
      },
    );

    test('an entry older than a day is dropped on read', () async {
      await cache().put('alerts', {
        'data': [
          {'id': 'a1'},
        ],
        'timestamp': DateTime.now()
            .subtract(const Duration(days: 2))
            .toIso8601String(),
      });
      expect(service.getCachedAlerts(), isEmpty);
      expect(cache().get('alerts'), isNull);
    });

    test('guides are served however old they are', () async {
      await cache().put('guides', {
        'data': [
          {'id': 'g1'},
        ],
        'timestamp': DateTime.now()
            .subtract(const Duration(days: 400))
            .toIso8601String(),
      });
      expect(service.getCachedGuides(), hasLength(1));
      // ...and are not deleted on read: they are the offline fallback.
      expect(cache().get('guides'), isNotNull);
    });
  });

  group('Hive encryption key', () {
    test('the key is generated once and reused', () async {
      // initialize() above already created it.
      final svc = HiveEncryptionService();
      final key = await svc.getEncryptionKey();
      expect(key, hasLength(32));
      expect(await svc.getEncryptionKey(), key);
      expect(await svc.hasEncryptionKey(), isTrue);
    });
  });
}
