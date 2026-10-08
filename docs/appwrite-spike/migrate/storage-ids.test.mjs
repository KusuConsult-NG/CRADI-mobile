/**
 * Pins the file-id port against the Dart original.
 *
 * `storage-ids.mjs` is a port of `AppwriteDataBackend.fileIdFor` in
 * `lib/core/services/appwrite/appwrite_data_backend.dart`. If the two disagree,
 * the migration stores files under ids the app never asks for, every image
 * 404s, and nothing reports a problem — the client derives the id from the path
 * and nothing persists it, so there is no mapping to notice is wrong.
 *
 * The cases below are the ones `test/unit/appwrite_documents_test.dart` asserts
 * on the Dart side, with the same reasoning. A change to either implementation
 * without the other fails here.
 *
 *   node --test storage-ids.test.mjs
 */
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  MAX_ID_LENGTH,
  MAX_OWN_ID_LENGTH,
  fileIdFor,
  idsFor,
  thumbFileIdFor,
} from './storage-ids.mjs';

describe('storage paths become file ids', () => {
  test('the slashes of a path are replaced', () => {
    assert.equal(fileIdFor('u1/report_123.jpg'), 'u1-report_123.jpg');
  });

  test('a long path leaves room for the thumbnail suffix', () => {
    // 36 is Appwrite's limit, and a thumbnail's id is this one plus a suffix —
    // so an id that used all 36 would have no reachable thumbnail.
    const id = fileIdFor('0199c0de-dead-beef-cafe-000000000001/report_1772539200000.jpg');
    assert.ok(id.length <= MAX_OWN_ID_LENGTH, `${id} is ${id.length}`);
    assert.match(id, /^[A-Za-z0-9][A-Za-z0-9._-]*$/);
    assert.ok(thumbFileIdFor(id).length <= MAX_ID_LENGTH);
  });

  test('the same path always gives the same id', () => {
    // Re-uploading after a retry must replace the file, not add a second copy —
    // the offline queue retries by path, and so does a re-run of the migration.
    const path = '0199c0de-dead-beef-cafe-000000000001/report_17725392.jpg';
    assert.equal(fileIdFor(path), fileIdFor(path));
  });

  test('an id may not begin with a punctuation character', () => {
    assert.ok(fileIdFor('_leading').startsWith('f'));
    assert.doesNotMatch(fileIdFor('/leading'), /^[._-]/);
  });

  test('long paths that differ only near the front still differ', () => {
    // The case truncation got wrong: the filename is most of the 36 characters,
    // so only a tail of the user id would have survived and one agent's photo
    // could overwrite another's.
    assert.notEqual(
      fileIdFor('aaaaaaaa-dead-beef-cafe-000000000001/report_1772539200000.jpg'),
      fileIdFor('bbbbbbbb-dead-beef-cafe-000000000001/report_1772539200000.jpg'),
    );
  });

  test('ids stay distinct across a realistic batch', () => {
    const ids = new Set();
    for (let user = 0; user < 60; user++) {
      for (let n = 0; n < 60; n++) {
        ids.add(
          fileIdFor(
            `${String(user).padStart(8, '0')}-dead-beef-cafe-000000000001/report_17725392000${n}.jpg`,
          ),
        );
      }
    }
    assert.equal(ids.size, 3600);
  });

  test('every id Appwrite would reject is rejected here', () => {
    for (const path of [
      'u1/report_123.jpg',
      '_leading',
      'a'.repeat(200),
      'spaces and (parens)/file name.jpg',
      'ünïcødé/ñame.jpg',
      '0199c0de-dead-beef-cafe-000000000001/report_1772539200000.jpg',
    ]) {
      const id = fileIdFor(path);
      assert.match(id, /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,35}$/, `${path} -> ${id}`);
      assert.ok(id.length <= MAX_OWN_ID_LENGTH, `${path} -> ${id} (${id.length})`);
    }
  });
});

describe('idsFor', () => {
  test('maps each name to its id', () => {
    const map = idsFor(['u1/a.jpg', 'u2/b.jpg']);
    assert.equal(map.get('u1/a.jpg'), 'u1-a.jpg');
    assert.equal(map.get('u2/b.jpg'), 'u2-b.jpg');
  });

  test('a repeated name is not a collision', () => {
    assert.equal(idsFor(['u1/a.jpg', 'u1/a.jpg']).size, 1);
  });

  test('refuses two names that would overwrite each other', () => {
    // Short paths skip the digest, so `_x` and `-x` both become `fx`. The app
    // never generates such a name, and a migration reads whatever is actually
    // in the bucket.
    assert.throws(() => idsFor(['_x.jpg', '-x.jpg']), /overwrite each other/);
  });
});
