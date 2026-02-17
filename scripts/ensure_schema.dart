// ignore_for_file: avoid_print, deprecated_member_use
import 'package:dart_appwrite/dart_appwrite.dart';
import 'dart:io';

// Configuration
const String endpoint = 'https://fra.cloud.appwrite.io/v1';
const String projectId = '6941cdb400050e7249d5'; // Updated from AppConfig
const String databaseId = '6941e2c2003705bb5a25'; // Updated from AppConfig

// Collection IDs
const String usersCollectionId = 'users'; // Updated from AppConfig
const String reportsCollectionId = 'reports'; // Updated from AppConfig

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart ensure_schema.dart <YOUR_API_KEY>');
    print(
      'API Key must have "collections.write" and "attributes.write" scopes.',
    );
    exit(1);
  }

  final apiKey = args[0];
  final client = Client()
      .setEndpoint(endpoint)
      .setProject(projectId)
      .setKey(apiKey);

  final databases = Databases(client);

  print('🚀 Starting Schema Audit...');

  // Reordered to check Trusted Devices first (to debug truncation)
  await _ensureDevicesAttributes(databases);
  await _ensureLoginHistoryAttributes(databases);

  // Standard checks
  await _ensureReportsAttributes(databases);
  await _ensureUsersAttributes(databases);
  await _ensureMessagesAttributes(databases);
  await _ensureContactsAttributes(databases);

  // Alerts check (might fail if collection missing)
  await _ensureAlertsAttributes(databases);

  print('✅ Schema Audit Complete!');
}

Future<void> _ensureReportsAttributes(Databases databases) async {
  print('\nChecking Reports Collection ($reportsCollectionId)...');

  final attributes = [
    _Attribute('location', 'string', 255, false),
    _Attribute('address', 'string', 255, false),
    _Attribute('ward', 'string', 128, false),
    _Attribute('lga', 'string', 128, false),
    _Attribute('state', 'string', 64, false),
    _Attribute('hazardType', 'string', 64, true),
    _Attribute('severity', 'string', 32, true),
    _Attribute('status', 'string', 32, true),
    _Attribute('isAlert', 'boolean', 0, false),
    _Attribute('submittedAt', 'string', 64, true),
    _Attribute('imageIds', 'string', 64, false, array: true),
    _Attribute('createdAt', 'string', 64, false), // Added for safety
  ];

  await _checkAndCreateAttributes(databases, reportsCollectionId, attributes);
  await _ensureIntegerAttribute(
    databases,
    reportsCollectionId,
    'verificationCount',
    false,
  );
}

Future<void> _ensureUsersAttributes(Databases databases) async {
  print('\nChecking Users Collection ($usersCollectionId)...');

  final attributes = [
    _Attribute('address', 'string', 255, false),
    _Attribute('phone', 'string', 20, false),
    _Attribute('lastLoginAt', 'string', 80, false), // Increased size
    _Attribute('profileImageId', 'string', 64, false),
    _Attribute('createdAt', 'string', 64, false),
    _Attribute('bio', 'string', 500, false),
    _Attribute('fcmToken', 'string', 255, false),
    _Attribute('role', 'string', 64, false),
    _Attribute('accessCode', 'string', 64, false),
    _Attribute('isVerified', 'boolean', 0, false),
    _Attribute('biometricsEnabled', 'boolean', 0, false),
    _Attribute('monitoringZone', 'string', 128, false),
  ];

  await _checkAndCreateAttributes(databases, usersCollectionId, attributes);
}

Future<void> _ensureMessagesAttributes(Databases databases) async {
  print('\nChecking Messages Collection (messages)...');
  final attributes = [
    _Attribute('chatId', 'string', 64, true),
    _Attribute('senderId', 'string', 64, true),
    _Attribute('senderName', 'string', 128, true),
    _Attribute('message', 'string', 5000, true),
    _Attribute('type', 'string', 32, true),
    _Attribute('sentAt', 'string', 64, true),
    _Attribute('read', 'boolean', 0, false),
    _Attribute('createdAt', 'string', 64, false), // Added for safety
  ];
  await _checkAndCreateAttributes(databases, 'messages', attributes);
}

Future<void> _ensureContactsAttributes(Databases databases) async {
  print('\nChecking Contacts Collection (emergency_contacts)...');
  final attributes = [
    _Attribute('userId', 'string', 64, true),
    _Attribute('name', 'string', 128, true),
    _Attribute('phone', 'string', 20, true),
    _Attribute('relationship', 'string', 64, true),
    _Attribute('createdAt', 'string', 64, false),
  ];
  await _checkAndCreateAttributes(databases, 'emergency_contacts', attributes);
}

Future<void> _ensureDevicesAttributes(Databases databases) async {
  print('\nChecking Trusted Devices Collection (trusted_devices)...');
  final attributes = [
    _Attribute('userId', 'string', 64, true),
    _Attribute('deviceFingerprint', 'string', 128, true),
    _Attribute('deviceName', 'string', 128, true),
    _Attribute('trusted', 'boolean', 0, false),
    _Attribute('lastUsed', 'string', 64, false),
    _Attribute('createdAt', 'string', 64, false),
  ];
  await _checkAndCreateAttributes(databases, 'trusted_devices', attributes);
}

Future<void> _ensureLoginHistoryAttributes(Databases databases) async {
  print('\nChecking Login History Collection (login_history)...');
  final attributes = [
    _Attribute('userId', 'string', 64, true),
    _Attribute('success', 'boolean', 0, true),
    _Attribute('deviceFingerprint', 'string', 128, false),
    _Attribute('deviceName', 'string', 128, false),
    _Attribute('timestamp', 'string', 64, true),
  ];
  await _checkAndCreateAttributes(databases, 'login_history', attributes);
  await _ensureIntegerAttribute(databases, 'login_history', 'riskScore', false);
}

Future<void> _ensureAlertsAttributes(Databases databases) async {
  print('\nChecking Alerts Collection (alerts)...');
  final attributes = [
    _Attribute('title', 'string', 255, true),
    _Attribute('body', 'string', 5000, true),
    _Attribute('type', 'string', 64, false),
    _Attribute('severity', 'string', 32, false),
    _Attribute('location', 'string', 255, false),
  ];
  await _checkAndCreateAttributes(databases, 'alerts', attributes);
}

class _Attribute {
  final String key;
  final String type;
  final int size;
  final bool required;
  final bool array;

  _Attribute(
    this.key,
    this.type,
    this.size,
    this.required, {
    this.array = false,
  });
}

Future<void> _checkAndCreateAttributes(
  Databases db,
  String collId,
  List<_Attribute> requiredAttrs,
) async {
  try {
    final existingList = await db.listAttributes(
      databaseId: databaseId,
      collectionId: collId,
    );
    final existingKeys = existingList.attributes
        .map((a) => a is Map ? a['key'] : (a as dynamic).key)
        .toSet();

    for (final attr in requiredAttrs) {
      if (existingKeys.contains(attr.key)) {
        // Find the existing attribute to check details
        final existing = existingList.attributes.firstWhere(
          (a) => (a is Map ? a['key'] : (a as dynamic).key) == attr.key,
        );

        final isRequired = existing is Map
            ? existing['required']
            : (existing as dynamic).required;
        final type = existing is Map
            ? existing['type']
            : (existing as dynamic).type;

        print('  - [OK] ${attr.key} (Type: $type, Required: $isRequired)');
        continue;
      }

      print('  - [MISSING] ${attr.key} (Creating...)');
      try {
        if (attr.type == 'string') {
          await db.createStringAttribute(
            databaseId: databaseId,
            collectionId: collId,
            key: attr.key,
            size: attr.size,
            xrequired: attr.required,
            array: attr.array,
          );
        } else if (attr.type == 'boolean') {
          await db.createBooleanAttribute(
            databaseId: databaseId,
            collectionId: collId,
            key: attr.key,
            xrequired: attr.required,
            array: attr.array,
          );
        }
        print('    -> Created!');
        // Small delay to prevent rate limits
        await Future.delayed(const Duration(milliseconds: 500));
      } on Exception catch (e) {
        print('    -> Failed to create ${attr.key}: $e');
      }
    }
  } on Exception catch (e) {
    print('Error listing attributes for $collId: $e');
  }
}

Future<void> _ensureIntegerAttribute(
  Databases db,
  String collId,
  String key,
  bool required,
) async {
  try {
    final existingList = await db.listAttributes(
      databaseId: databaseId,
      collectionId: collId,
    );
    final existingKeys = existingList.attributes
        .map((a) => a is Map ? a['key'] : (a as dynamic).key)
        .toSet();

    if (existingKeys.contains(key)) {
      print('  - [OK] $key');
      return;
    }

    print('  - [MISSING] $key (Creating Integer...)');
    await db.createIntegerAttribute(
      databaseId: databaseId,
      collectionId: collId,
      key: key,
      xrequired: required,
      min: 0,
      max: 9999999,
    );
    print('    -> Created!');
  } on Exception catch (e) {
    print('    -> Failed to create Integer $key: $e');
  }
}
