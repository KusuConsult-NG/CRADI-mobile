/**
 * A Supabase storage object's name -> the Appwrite file id the app will look
 * for.
 *
 * This is not a mapping the migration gets to choose. The Flutter client
 * derives it at render time: `reports.imageUrls` holds a URL built from
 * `fileIdFor(storagePath)`, and `AppwriteDataBackend` comments that the id is
 * "a digest of the path, and a digest cannot be inverted" — so nothing
 * persists the mapping and nothing can look it up. A migrated file stored
 * under any other id is unreachable by the app, with no error anywhere: the
 * request 404s and an image fails to load.
 *
 * So this is a port of `AppwriteDataBackend.fileIdFor` in
 * `lib/core/services/appwrite/appwrite_data_backend.dart`, and the two must
 * agree exactly. `storage-ids.test.mjs` pins it against the cases
 * `test/unit/appwrite_documents_test.dart` asserts on the Dart side; a change
 * to either without the other shows up there.
 *
 * `fnv1a64` is imported from the Functions rather than written a third time —
 * same constants, same UTF-8 bytes, same 16 hex characters as the Dart one.
 */
import { fnv1a64 } from '../../../functions/cradi/src/lib/appwrite.js';

/** Appwrite's limit on a file id. */
export const MAX_ID_LENGTH = 36;

/**
 * Marks a thumbnail's id as belonging to the photo it was cut from.
 *
 * Only one direction is ever needed: photo id -> thumbnail id. The display
 * code has the photo's URL and nothing else.
 */
export const THUMB_SUFFIX = '-t';

/** What an id of our own may use, leaving the thumbnail suffix room to fit. */
export const MAX_OWN_ID_LENGTH = MAX_ID_LENGTH - THUMB_SUFFIX.length;

/** An id may not begin with a punctuation character. */
const fixHead = (s) => (/^[._-]/.test(s) ? `f${s.slice(1)}` : s);

export function fileIdFor(storagePath) {
  const cleaned = String(storagePath).replace(/[^A-Za-z0-9._-]/g, '-');
  if (cleaned.length <= MAX_OWN_ID_LENGTH) return fixHead(cleaned);
  // 17 characters of prefix + '-' + 16 hex = 34.
  const head = fixHead(cleaned.slice(0, MAX_OWN_ID_LENGTH - 17));
  return `${head}-${fnv1a64(storagePath)}`;
}

/** The id of the thumbnail cut from the file at [fileId]. */
export const thumbFileIdFor = (fileId) => `${fileId}${THUMB_SUFFIX}`;

/**
 * The view URL the app stores on a row and later renders.
 *
 * `/view` rather than `/preview`: preview transformations are a paid feature on
 * Cloud, and the app already compresses before upload. The `project` query
 * parameter is part of it — the client reads these with no session.
 */
export const fileViewUrl = ({ endpoint, project, bucketId, fileId }) =>
  `${endpoint}/storage/buckets/${bucketId}/files/${fileId}/view` +
  `?project=${project}`;

/**
 * Maps every object name in [names] to its file id, or throws on a collision.
 *
 * Two different paths landing on one id would mean the second upload replaces
 * the first user's evidence, with no error anywhere — the exact failure the
 * digest exists to prevent. Short paths skip the digest, so a collision is
 * possible for names the app did not generate (`_x` and `-x` both become
 * `fx`), and a migration reads whatever is actually in the bucket.
 */
export function idsFor(names) {
  const byId = new Map();
  const collisions = [];
  for (const name of names) {
    const id = fileIdFor(name);
    if (byId.has(id) && byId.get(id) !== name) {
      collisions.push({ id, names: [byId.get(id), name] });
      continue;
    }
    byId.set(id, name);
  }
  if (collisions.length) {
    const lines = collisions
      .map((c) => `  ${c.id} <- ${c.names.join(' AND ')}`)
      .join('\n');
    throw new Error(
      `${collisions.length} storage object(s) map to an id another object` +
        ` already has. Uploading them would overwrite each other:\n${lines}`,
    );
  }
  return new Map([...byId].map(([id, name]) => [name, id]));
}
