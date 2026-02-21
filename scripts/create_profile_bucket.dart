// ignore_for_file: avoid_print

import 'package:dart_appwrite/dart_appwrite.dart';
import 'dart:io';

// Configuration
const String endpoint = 'https://fra.cloud.appwrite.io/v1';
const String projectId = '6941cdb400050e7249d5';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart create_profile_bucket.dart <YOUR_API_KEY>');
    exit(1);
  }

  final apiKey = args[0];
  final client = Client()
      .setEndpoint(endpoint)
      .setProject(projectId)
      .setKey(apiKey);

  final storage = Storage(client);

  print('🚀 Starting Bucket Creation...');

  try {
    final bucket = await storage.createBucket(
      bucketId: 'profile-images-bucket',
      name: 'Profile Images',
      permissions: [
        Permission.read(Role.any()),
        Permission.create(Role.users()),
        Permission.update(Role.users()),
        Permission.delete(Role.users()),
      ],
      fileSecurity: false,
      enabled: true,
      maximumFileSize: 5000000, // 5MB limit for profile pictures
      allowedFileExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    print('✅ Successfully created Profile Images bucket.');
    print('Bucket ID: ${bucket.$id}');
  } on AppwriteException catch (e) {
    if (e.code == 409) {
      print('✅ Bucket "profile-images-bucket" already exists.');
    } else {
      print('❌ Failed to create bucket: ${e.message}');
    }
  }

  print('✅ Script completed!');
}
