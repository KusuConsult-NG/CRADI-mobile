import 'dart:io';

import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/providers/connectivity_provider.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/services/backend.dart';
import 'package:climate_app/core/utils/image_url_resolver.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

/// Records uploads / writes; the upload number [failUploadAt] (0-based)
/// fails with [uploadError].
class _FakeDb implements DataBackend {
  _FakeDb({this.failUploadAt, this.uploadError});

  final int? failUploadAt;
  final Exception? uploadError;
  final List<String> uploadedPaths = [];
  final List<String> attemptedPaths = [];

  /// Thumbnail uploads, kept apart from the full-size ones: they are a
  /// best-effort extra and must not shift the [failUploadAt] numbering.
  final List<String> uploadedThumbPaths = [];
  final List<String?> createdIds = [];
  final List<String?> upsertedIds = [];
  final List<Map<String, dynamic>> upsertedData = [];

  @override
  String? get currentUserId => 'u1';

  @override
  Future<String> uploadFileFromPath({
    required String bucketId,
    required String storagePath,
    required File file,
    String? contentType,
    bool upsert = false,
    int maxDimension = 1920,
    int quality = 85,
  }) async {
    final n = attemptedPaths.length;
    attemptedPaths.add(storagePath);
    if (n == failUploadAt) throw uploadError!;
    uploadedPaths.add(storagePath);
    return 'https://storage.example/$storagePath';
  }

  /// Models the Supabase convention: the thumbnail lands beside the
  /// photo under `thumbStoragePath`. The provider now passes the
  /// **photo's** path and lets the backend name the thumbnail, which is
  /// what lets Appwrite key its id off the photo's instead.
  @override
  Future<String> uploadThumbnailFromPath({
    required String bucketId,
    required String storagePath,
    required File file,
    int maxDimension = 320,
    int quality = 60,
  }) async {
    final thumb = ImageUrlResolver.thumbStoragePath(storagePath);
    uploadedThumbPaths.add(thumb);
    return 'https://storage.example/$thumb';
  }

  @override
  Future<Map<String, dynamic>> createDocument({
    required String collectionId,
    required Map<String, dynamic> data,
    String? documentId,
  }) async {
    createdIds.add(documentId);
    return {r'$id': documentId, ...data};
  }

  @override
  Future<Map<String, dynamic>?> upsertDocument({
    required String collectionId,
    required Map<String, dynamic> data,
    String? documentId,
    bool ignoreDuplicates = false,
  }) async {
    upsertedIds.add(documentId);
    upsertedData.add(data);
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// In-memory drafts / queue.
class _FakeOffline implements OfflineStorageService {
  final Map<String, Map<String, dynamic>> drafts = {};
  final List<Map<String, dynamic>> queued = [];

  @override
  Future<String> saveDraft({
    String? userId,
    String? reportId,
    List<String>? imageStoragePaths,
    required String hazardType,
    required String severity,
    required String locationDetails,
    String? ward,
    String? lga,
    String? state,
    double? latitude,
    double? longitude,
    String? description,
    DateTime? reportDateTime,
    List<String>? imagePaths,
  }) async {
    final id = 'd${drafts.length + 1}';
    drafts[id] = {
      'id': id,
      'userId': userId,
      'reportId': ?reportId,
      'imageStoragePaths': ?imageStoragePaths,
      'hazardType': hazardType,
      'severity': severity,
      'locationDetails': locationDetails,
      'ward': ward,
      'lga': lga,
      'state': state,
      'latitude': latitude,
      'longitude': longitude,
      'description': description ?? '',
      'reportDateTime': (reportDateTime ?? DateTime.now())
          .toUtc()
          .toIso8601String(),
      'imagePaths': imagePaths ?? const <String>[],
      'status': 'draft',
    };
    return id;
  }

  @override
  List<Map<String, dynamic>> getAllDrafts() =>
      drafts.values.map(Map<String, dynamic>.of).toList();

  @override
  Future<void> deleteDraft(String draftId) async => drafts.remove(draftId);

  @override
  Future<void> addToSyncQueue(Map<String, dynamic> report) async =>
      queued.add(report);

  @override
  Future<Map<String, int>> syncPendingReports() async => {
    'synced': 0,
    'failed': 0,
    'rejected': 0,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  late Directory tmp;
  late List<XFile> photos;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('report_photos');
    photos = [
      for (final name in ['a.jpg', 'b.jpg'])
        XFile(
          (File('${tmp.path}/$name')..writeAsBytesSync([1, 2, 3])).path,
          name: name,
        ),
    ];
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  ReportingProvider filledProvider(_FakeDb db, _FakeOffline offline) {
    final p = ReportingProvider(db: db, offlineStorage: offline)
      ..setHazardType('flood')
      ..setSeverity('high')
      ..setLocationDetails('Near the market')
      ..setReportState('Lagos')
      ..setLGA('Ikeja')
      ..setWard('Ward 1');
    p.photos.addAll(photos);
    return p;
  }

  Future<BuildContext> pumpContext(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      ChangeNotifierProvider<ConnectivityProvider>.value(
        value: ConnectivityProvider.forTesting(online: true),
        child: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return ctx;
  }

  testWidgets(
    'a network failure while uploading photos keeps the report for sync '
    'with its local photos, and the sync reuses its id and storage paths',
    (tester) async {
      final db = _FakeDb(
        failUploadAt: 1,
        uploadError: const SocketException('connection reset'),
      );
      final offline = _FakeOffline();
      final provider = filledProvider(db, offline);
      final ctx = await pumpContext(tester);

      final result = await tester.runAsync(() => provider.submitReport(ctx));
      expect(result!['queued'], isTrue);
      expect(
        (result['message'] as LocalizedText)(englishL10n),
        englishL10n.reportQueuedServerUnreachable,
      );
      // No report row was written; the wizard was reset.
      expect(db.createdIds, isEmpty);
      expect(offline.queued, isEmpty);
      expect(provider.hazardType, isNull);

      final draft = offline.drafts.values.single;
      expect(draft['userId'], 'u1');
      expect(draft['imagePaths'], photos.map((p) => p.path).toList());
      final reportId = draft['reportId'] as String;
      expect(draft['imageStoragePaths'], [
        ReportingProvider.reportPhotoStoragePath('u1', reportId, 0, 'a.jpg'),
        ReportingProvider.reportPhotoStoragePath('u1', reportId, 1, 'b.jpg'),
      ]);
      expect(db.uploadedPaths, [
        ReportingProvider.reportPhotoStoragePath('u1', reportId, 0, 'a.jpg'),
      ]);
      // A thumbnail was stored next to the photo that did upload, and only
      // that one.
      expect(db.uploadedThumbPaths, [
        ImageUrlResolver.thumbStoragePath(
          ReportingProvider.reportPhotoStoragePath('u1', reportId, 0, 'a.jpg'),
        ),
      ]);

      // Back online: the draft sync uploads to the same objects (the first
      // one is reused, not orphaned) and inserts the report under the same
      // id, idempotently.
      final syncDb = _FakeDb();
      final syncProvider = ReportingProvider(
        db: syncDb,
        offlineStorage: offline,
      );
      final sync = await tester.runAsync(
        () => syncProvider.syncPendingReports(ctx),
      );
      expect(sync!['synced'], 1);
      expect(syncDb.attemptedPaths, draft['imageStoragePaths']);
      // The sync uploads both sizes, at the same deterministic paths.
      expect(
        syncDb.uploadedThumbPaths,
        (draft['imageStoragePaths'] as List)
            .map((p) => ImageUrlResolver.thumbStoragePath(p as String))
            .toList(),
      );
      expect(syncDb.upsertedIds, [reportId]);
      expect(
        syncDb.upsertedData.single['imageUrls'],
        (draft['imageStoragePaths'] as List).map(
          (p) => 'https://storage.example/$p',
        ),
      );
      expect(offline.drafts, isEmpty);
    },
  );

  testWidgets('a server refusal during photo upload is not queued', (
    tester,
  ) async {
    final db = _FakeDb(failUploadAt: 0, uploadError: ImageEncodingException());
    final offline = _FakeOffline();
    final provider = filledProvider(db, offline);
    final ctx = await pumpContext(tester);

    final result = await tester.runAsync(() => provider.submitReport(ctx));
    expect(result!['success'], isFalse);
    expect(result['queued'], isNull);
    expect(offline.drafts, isEmpty);
    // The wizard keeps the user's input so they can fix / retry.
    expect(provider.hazardType, 'flood');
  });

  testWidgets('successful uploads insert the report with the photo URLs', (
    tester,
  ) async {
    final db = _FakeDb();
    final offline = _FakeOffline();
    final provider = filledProvider(db, offline);
    final ctx = await pumpContext(tester);

    final result = await tester.runAsync(() => provider.submitReport(ctx));
    expect(result!['success'], isTrue);
    expect(db.uploadedPaths, hasLength(2));
    expect(db.createdIds.single, result['reportId']);
    expect(offline.drafts, isEmpty);
  });

  test('draft photo paths: recorded paths are used only in the user\'s '
      'own folder', () {
    final draft = {
      'imageStoragePaths': ['u1/r_0_a.jpg', 'u2/r_1_b.jpg'],
    };
    String path(int i) => ReportingProvider.draftPhotoStoragePath(
      draft,
      uid: 'u1',
      reportId: 'r',
      index: i,
      fileName: 'draft_img.jpg',
    );
    expect(path(0), 'u1/r_0_a.jpg');
    expect(path(1), 'u1/r_1_draft_img.jpg');
    expect(path(2), 'u1/r_2_draft_img.jpg');
    expect(
      ReportingProvider.draftPhotoStoragePath(
        const {},
        uid: 'u1',
        reportId: 'r',
        index: 0,
        fileName: 'x.jpg',
      ),
      'u1/r_0_x.jpg',
    );
  });

  group('OfflineStorageService.saveDraft', () {
    late Directory hiveDir;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      FlutterSecureStorage.setMockInitialValues({});
      hiveDir = Directory.systemTemp.createTempSync('offline_drafts');
      Hive.init(hiveDir.path);
      await OfflineStorageService().initialize();
    });

    tearDownAll(() async {
      await Hive.close();
      hiveDir.deleteSync(recursive: true);
    });

    test('keeps the report id and aligned storage paths', () async {
      final service = OfflineStorageService();
      final id = await service.saveDraft(
        userId: 'u1',
        reportId: 'rid',
        hazardType: 'flood',
        severity: 'high',
        locationDetails: 'x',
        imagePaths: photos.map((p) => p.path).toList(),
        imageStoragePaths: ['u1/rid_0_a.jpg', 'u1/rid_1_b.jpg'],
      );
      final draft = service.getDraft(id)!;
      expect(draft['reportId'], 'rid');
      expect(draft['imageStoragePaths'], ['u1/rid_0_a.jpg', 'u1/rid_1_b.jpg']);
      expect(draft['imagePaths'], hasLength(2));
      await service.clearAllDrafts();
    });

    test('ordinary drafts carry neither', () async {
      final service = OfflineStorageService();
      final id = await service.saveDraft(
        userId: 'u1',
        hazardType: 'flood',
        severity: 'high',
        locationDetails: 'x',
      );
      final draft = service.getDraft(id)!;
      expect(draft.containsKey('reportId'), isFalse);
      expect(draft.containsKey('imageStoragePaths'), isFalse);
      await service.clearAllDrafts();
    });
  });
}
