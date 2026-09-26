import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/utils/image_url_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// Delivery-side URL rewriting: ImageKit is optional and off unless
/// IMAGEKIT_URL_ENDPOINT is defined at build time, and thumbnails are found
/// by name convention next to the full-size object.
void main() {
  const supabaseImage =
      'https://abcdefgh.supabase.co/storage/v1/object/public/report-images/'
      'user-1/report-9_0_photo.jpg';
  const endpoint = 'https://ik.imagekit.io/cradi';

  group('resolve — endpoint not configured', () {
    test('the app default is no endpoint, so nothing is rewritten', () {
      expect(AppConfig.imageKitUrlEndpoint, isEmpty);
      expect(ImageUrlResolver.resolve(supabaseImage), supabaseImage);
      expect(
        ImageUrlResolver.resolve(supabaseImage, width: 320, quality: 70),
        supabaseImage,
      );
    });

    test('an endpoint of only whitespace counts as unset', () {
      expect(
        ImageUrlResolver.resolve(supabaseImage, endpoint: '   ', width: 320),
        supabaseImage,
      );
    });
  });

  group('resolve — endpoint configured', () {
    test('a Supabase public URL becomes <endpoint>/<bucket>/<path>', () {
      expect(
        ImageUrlResolver.resolve(supabaseImage, endpoint: endpoint),
        '$endpoint/report-images/user-1/report-9_0_photo.jpg',
      );
    });

    test('width and quality become a tr query parameter', () {
      expect(
        ImageUrlResolver.resolve(
          supabaseImage,
          endpoint: endpoint,
          width: 320,
          quality: 70,
        ),
        '$endpoint/report-images/user-1/report-9_0_photo.jpg?tr=w-320,q-70',
      );
      expect(
        ImageUrlResolver.resolve(supabaseImage, endpoint: endpoint, width: 320),
        '$endpoint/report-images/user-1/report-9_0_photo.jpg?tr=w-320',
      );
    });

    test('non-positive width / quality are dropped rather than sent', () {
      expect(
        ImageUrlResolver.resolve(
          supabaseImage,
          endpoint: endpoint,
          width: 0,
          quality: -1,
        ),
        '$endpoint/report-images/user-1/report-9_0_photo.jpg',
      );
    });

    test('a trailing slash on the endpoint does not double up', () {
      expect(
        ImageUrlResolver.resolve(supabaseImage, endpoint: '$endpoint/'),
        '$endpoint/report-images/user-1/report-9_0_photo.jpg',
      );
    });

    test('a query string on the original (cache buster) is dropped', () {
      expect(
        ImageUrlResolver.resolve(
          '$supabaseImage?t=12345',
          endpoint: endpoint,
          width: 320,
        ),
        '$endpoint/report-images/user-1/report-9_0_photo.jpg?tr=w-320',
      );
    });

    test('profile images rewrite the same way', () {
      const avatar =
          'https://abcdefgh.supabase.co/storage/v1/object/public/'
          'profile-images/user-1/avatar.png';
      expect(
        ImageUrlResolver.resolve(avatar, endpoint: endpoint, width: 240),
        '$endpoint/profile-images/user-1/avatar.png?tr=w-240',
      );
    });
  });

  group('resolve — URLs that are deliberately left alone', () {
    // The ImageKit endpoint's origin is this project's Supabase bucket, so
    // any other host can't be served through it. Admin-set knowledge-base
    // images live off-site and are fetched (and disk-cached) directly.
    test('an off-site https guide image is untouched', () {
      const guide = 'https://cdn.example.org/guides/flood-cover.jpg';
      expect(
        ImageUrlResolver.resolve(guide, endpoint: endpoint, width: 480),
        guide,
      );
    });

    test('a signed (non-public) Supabase URL is untouched', () {
      const signed =
          'https://abcdefgh.supabase.co/storage/v1/object/sign/'
          'report-images/user-1/x.jpg?token=abc';
      expect(ImageUrlResolver.resolve(signed, endpoint: endpoint), signed);
    });

    test('malformed and unusual values do not throw', () {
      for (final value in <String>[
        '',
        'not a url',
        '/storage/v1/object/public/',
        'https://abcdefgh.supabase.co/storage/v1/object/public/',
        'data:image/png;base64,AAAA',
        '/data/user/0/app/cache/photo.jpg',
        '://',
      ]) {
        expect(
          () => ImageUrlResolver.resolve(value, endpoint: endpoint, width: 320),
          returnsNormally,
          reason: value,
        );
        expect(
          ImageUrlResolver.resolve(value, endpoint: endpoint, width: 320),
          value,
          reason: value,
        );
      }
    });
  });

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

    test('a thumbnail URL resolves through ImageKit like any other', () {
      expect(
        ImageUrlResolver.resolve(
          ImageUrlResolver.thumbUrlFor(supabaseImage)!,
          endpoint: endpoint,
          width: 320,
          quality: 70,
        ),
        '$endpoint/report-images/user-1/report-9_0_photo_thumb.jpg'
        '?tr=w-320,q-70',
      );
    });
  });
}
