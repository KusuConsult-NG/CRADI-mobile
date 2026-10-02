/// Translates the app's [QueryFilter]s into Appwrite query strings.
///
/// Pure, and tested as such. Every other part of the Appwrite adapter needs
/// a server to exercise; this does not, and it is where the semantics are
/// easiest to get subtly wrong — so it is the part that carries the tests.
library;

import 'package:appwrite/appwrite.dart' show Query;

import 'package:climate_app/core/services/data_backend.dart';
import 'package:climate_app/core/services/supabase_mapping.dart'
    show
        ColumnFilter,
        ColumnOrder,
        FilterOp,
        LimitFilter,
        OrderByFilter,
        WhereFilter,
        compareValues,
        encodeValue;

/// Appwrite's name for a document's key. The app writes `$id` already, so
/// unlike the Postgres adapter — which has to resolve it to each table's
/// primary key — there is nothing to map.
const String kAppwriteIdField = r'$id';

/// Builds the `queries` argument for a `listDocuments` call.
///
/// [offset] and [limitCount] are passed separately because [DataBackend]
/// takes them as arguments rather than as filters.
List<String> buildAppwriteQueries(
  List<QueryFilter>? queries, {
  int? limitCount,
  int offset = 0,
  List<String>? select,
}) {
  final out = <String>[];
  int? limit;

  for (final q in queries ?? const <QueryFilter>[]) {
    switch (q) {
      case WhereFilter(:final field, :final op, :final value):
        out.add(whereToQuery(field, op, value));
      case OrderByFilter(:final field, :final descending):
        out.add(descending ? Query.orderDesc(field) : Query.orderAsc(field));
      case LimitFilter(limit: final n):
        limit = n;
      default:
        throw ArgumentError('Unsupported query filter: ${q.runtimeType}');
    }
  }

  if (select != null && select.isNotEmpty) out.add(Query.select(select));
  final effective = limitCount ?? limit;
  if (effective != null) out.add(Query.limit(effective));
  if (offset > 0) out.add(Query.offset(offset));
  return out;
}

/// One predicate.
///
/// Null handling is the whole difficulty here, and it is deliberate rather
/// than defensive. `ColumnFilter.matches` — the app's own evaluator, used
/// for realtime streams — follows SQL: `NULL <> x` is **not** true, which
/// is why `distinctFrom` exists as a separate operator at all (it is how
/// the verification list keeps reports whose reporter was deleted).
///
/// Appwrite is a document store and its bare `notEqual` may or may not
/// return documents where the attribute is null; that is not written down
/// and this adapter has not been run against a server. So neither case
/// relies on it: `neq` is explicitly *not null and not equal*, and
/// `distinctFrom` is explicitly *null or not equal*. Both are correct
/// whichever way Appwrite resolves the bare form.
String whereToQuery(String field, FilterOp op, Object? rawValue) {
  final name = field == r'$id' ? kAppwriteIdField : field;
  final value = encodeValue(rawValue);

  switch (op) {
    case FilterOp.eq:
      return value == null ? Query.isNull(name) : Query.equal(name, value);

    case FilterOp.neq:
      // SQL semantics: a null never satisfies `<>`.
      return Query.and([Query.isNotNull(name), Query.notEqual(name, value)]);

    case FilterOp.distinctFrom:
      // `IS DISTINCT FROM`: nulls are kept.
      return Query.or([Query.isNull(name), Query.notEqual(name, value)]);

    case FilterOp.gt:
      return Query.and([Query.isNotNull(name), Query.greaterThan(name, value)]);

    case FilterOp.lt:
      return Query.and([Query.isNotNull(name), Query.lessThan(name, value)]);

    case FilterOp.inList:
      final options = value is List ? value : [value];
      // An empty `IN ()` matches nothing. Appwrite has no literal false, so
      // say it as a contradiction the server can evaluate — passing an
      // empty list to `Query.equal` would be read as "no constraint".
      if (options.isEmpty) {
        return Query.and([Query.isNull(name), Query.isNotNull(name)]);
      }
      return Query.equal(name, options);

    case FilterOp.contains:
      // The app's own evaluator requires *every* wanted element to be
      // present, so this is `containsAll`, not `containsAny`.
      final wanted = value is List ? value : [value];
      return wanted.length == 1
          ? Query.contains(name, wanted.first)
          : Query.containsAll(name, wanted);
  }
}

/// The same filters, evaluated on the client.
///
/// Appwrite Realtime delivers one document at a time, not a list, so a live
/// collection is assembled here: the initial page from `listDocuments`, then
/// each event applied to it. Re-filtering, ordering and limiting that list
/// is client work either way — the Postgres adapter does exactly the same
/// over `.stream()`, which also ignores most of a query.
///
/// Unlike [QueryPlan] this resolves nothing: Appwrite attributes carry the
/// app's own field names, so a filter's field *is* the key in the document.
class DocumentPlan {
  DocumentPlan(this.filters, this.orders, this.limit);

  factory DocumentPlan.build(List<QueryFilter>? queries) {
    final filters = <ColumnFilter>[];
    final orders = <ColumnOrder>[];
    int? limit;
    for (final q in queries ?? const <QueryFilter>[]) {
      switch (q) {
        case WhereFilter(:final field, :final op, :final value):
          filters.add(ColumnFilter(field, op, encodeValue(value)));
        case OrderByFilter(:final field, :final descending):
          orders.add(ColumnOrder(field, ascending: !descending));
        case LimitFilter(limit: final n):
          limit = n;
        default:
          throw ArgumentError('Unsupported query filter: ${q.runtimeType}');
      }
    }
    return DocumentPlan(filters, orders, limit);
  }

  final List<ColumnFilter> filters;
  final List<ColumnOrder> orders;
  final int? limit;

  bool matches(Map<String, dynamic> doc) =>
      filters.every((f) => f.matches(doc));

  /// Filters, orders and truncates [docs] — the whole plan, applied to a
  /// list the server did not shape for us.
  List<Map<String, dynamic>> apply(Iterable<Map<String, dynamic>> docs) {
    final out = docs.where(matches).toList();
    if (orders.isNotEmpty) {
      out.sort((a, b) {
        for (final o in orders) {
          final c = compareValues(a[o.column], b[o.column]);
          if (c != 0) return o.ascending ? c : -c;
        }
        return 0;
      });
    }
    final n = limit;
    return (n != null && out.length > n) ? out.sublist(0, n) : out;
  }
}
