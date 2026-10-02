import 'package:climate_app/core/utils/image_url_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// Names the thumbnail stored beside a Supabase Storage object. The
/// Appwrite half of the same job — a thumbnail id derived from its
/// photo's — is covered in `test/unit/appwrite_data_backend_test.dart`.
void main() {
  const supabaseImage =
      'https://abcdefgh.supabase.co/storage/v1/object/public/report-images/'
      'user-1/report-9_0_photo.jpg';

  group('thumbStoragePath', () {
    test('keeps the folder (the user id storage RLS keys on)', () {
      expect(
        ImageUrlResolver.thumbStoragePath('user-1/report-9_0_photo.jpg'),
        'user-1/report-9_0_photo_thumb.jpg',
      );
    });

    test('always ends in .jpg, whatever the original extension', () {
      expect(
        ImageUrlResolver.thumbStoragePath('user-1/shot.HEIC'),
        'user-1/shot_thumb.jpg',
      );
      expect(
        ImageUrlResolver.thumbStoragePath('user-1/no-extension'),
        'user-1/no-extension_thumb.jpg',
      );
      expect(
        ImageUrlResolver.thumbStoragePath('user-1/a.b.c.png'),
        'user-1/a.b.c_thumb.jpg',
      );
    });
  });

  group('thumbUrlFor', () {
    test('points at the sibling object', () {
      expect(
        ImageUrlResolver.thumbUrlFor(supabaseImage),
        'https://abcdefgh.supabase.co/storage/v1/object/public/report-images/'
        'user-1/report-9_0_photo_thumb.jpg',
      );
    });

    test('is idempotent on a thumbnail URL', () {
      final thumb = ImageUrlResolver.thumbUrlFor(supabaseImage)!;
      expect(ImageUrlResolver.thumbUrlFor(thumb), thumb);
    });

    test('is null for anything that is not a Supabase public object', () {
      expect(
        ImageUrlResolver.thumbUrlFor('https://cdn.example.org/a.jpg'),
        isNull,
      );
      expect(ImageUrlResolver.thumbUrlFor(''), isNull);
      // Bucket with no object path.
      expect(
        ImageUrlResolver.thumbUrlFor(
          'https://abcdefgh.supabase.co/storage/v1/object/public/bucket',
        ),
        isNull,
      );
    });
  });
}
