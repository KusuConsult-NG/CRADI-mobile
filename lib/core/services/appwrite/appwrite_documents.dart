/// Appwrite document ↔ app document.
///
/// Much smaller than the Postgres equivalent, and deliberately so: Phase 1
/// gives the Appwrite collections the app's own field names, so there is no
/// camelCase/snake_case translation to do. What is left is Appwrite's four
/// reserved keys.
library;

import 'package:appwrite/models.dart' as aw;

/// Appwrite's system attributes, which are not part of a document's data.
const Set<String> kAppwriteSystemKeys = {
  r'$id',
  r'$collectionId',
  r'$databaseId',
  r'$createdAt',
  r'$updatedAt',
  r'$permissions',
  r'$sequence',
};

/// Flattens an Appwrite row into the shape the app's providers read.
///
/// * `$id` is exposed under both `$id` and `id`, which is what the Postgres
///   adapter's `fromRow` already does — every call site reads one or the
///   other and neither backend should decide which.
/// * `$createdAt` / `$updatedAt` fill `createdAt` / `updatedAt` **only when
///   the collection does not define its own**. Several collections do
///   (`reports.createdAt` is the time of the event, not of the write), and
///   silently overwriting a real field with Appwrite's bookkeeping would be
///   the kind of defect that only shows up as a wrong date on a report.
Map<String, dynamic> fromAppwriteRow(aw.Row row) =>
    _flatten(row.data, row.$id, row.$createdAt, row.$updatedAt);

/// The same for the deprecated document API, kept because Appwrite 1.6 —
/// the version the spike proved — has no `TablesDB`.
Map<String, dynamic> fromAppwriteDocument(aw.Document doc) =>
    _flatten(doc.data, doc.$id, doc.$createdAt, doc.$updatedAt);

Map<String, dynamic> _flatten(
  Map<String, dynamic> data,
  String id,
  String createdAt,
  String updatedAt,
) {
  final out = Map<String, dynamic>.from(data);

  // `data` already contains the system keys on some SDK versions; drop them
  // so the rules below are the only thing that sets them.
  out.removeWhere((k, _) => kAppwriteSystemKeys.contains(k));

  out[r'$id'] = id;
  out['id'] ??= id;
  out[r'$createdAt'] = createdAt;
  out[r'$updatedAt'] = updatedAt;
  out['createdAt'] ??= createdAt;
  out['updatedAt'] ??= updatedAt;
  return out;
}

/// The payload for a write: the app's data without the keys Appwrite owns.
///
/// `$id` is passed to the SDK as `documentId`, not inside `data`, and the
/// timestamps are the server's. Sending any of them back is a 400.
Map<String, dynamic> toAppwriteData(Map<String, dynamic> data) {
  final out = Map<String, dynamic>.from(data)
    ..removeWhere((k, _) => kAppwriteSystemKeys.contains(k))
    ..remove('id');
  return out;
}

/// The same flattening for a realtime payload, which arrives as a raw map
/// rather than a typed [aw.Document].
Map<String, dynamic> fromAppwritePayload(Map<String, dynamic> payload) {
  final out = Map<String, dynamic>.from(payload);
  final id = payload[r'$id']?.toString();
  final createdAt = payload[r'$createdAt']?.toString();
  final updatedAt = payload[r'$updatedAt']?.toString();
  out.removeWhere((k, _) => kAppwriteSystemKeys.contains(k));
  if (id != null) {
    out[r'$id'] = id;
    out['id'] ??= id;
  }
  if (createdAt != null) {
    out[r'$createdAt'] = createdAt;
    out['createdAt'] ??= createdAt;
  }
  if (updatedAt != null) {
    out[r'$updatedAt'] = updatedAt;
    out['updatedAt'] ??= updatedAt;
  }
  return out;
}
