/// Pure (no I/O) helpers that translate between the app's document-style
/// maps (camelCase keys, `$id`, legacy collection names) and Supabase rows
/// (snake_case columns, `id`, Postgres table names).
///
/// Kept free of any Supabase client dependency so it can be unit tested.
library;

import 'dart:developer' as developer;

// ───────────────────────────── Key conversion ────────────────────────────────

final RegExp _acronymBoundary = RegExp(r'([A-Z]+)([A-Z][a-z])');
final RegExp _wordBoundary = RegExp(r'([a-z0-9])([A-Z])');

/// `imageUrls` → `image_urls`, `coverageLGA` → `coverage_lga`.
String camelToSnake(String key) {
  if (key.isEmpty || !key.contains(RegExp(r'[A-Z]'))) return key;
  return key
      .replaceAllMapped(_acronymBoundary, (m) => '${m[1]}_${m[2]}')
      .replaceAllMapped(_wordBoundary, (m) => '${m[1]}_${m[2]}')
      .toLowerCase();
}

/// `image_urls` → `imageUrls`.
String snakeToCamel(String key) {
  if (!key.contains('_')) return key;
  final parts = key.split('_').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return key;
  final buffer = StringBuffer(parts.first);
  for (final part in parts.skip(1)) {
    buffer
      ..write(part[0].toUpperCase())
      ..write(part.substring(1));
  }
  return buffer.toString();
}

// ───────────────────────────── Schema description ────────────────────────────

/// Mirrors `supabase/migrations/*_init.sql`. Used to drop fields that have no
/// column (PostgREST rejects unknown columns) and to translate names.
class SupabaseSchema {
  SupabaseSchema._();

  /// Legacy collection names → table names.
  static const Map<String, String> collectionAliases = {'users': 'profiles'};

  /// Columns written only by the database (defaults / triggers).
  static const Set<String> serverManagedColumns = {'created_at', 'updated_at'};

  /// Per-table field renames (app field → column) beyond camel→snake.
  static const Map<String, Map<String, String>> fieldAliases = {
    'login_history': {'timestamp': 'occurred_at'},
    'ndpa_consents': {'uid': 'user_id'},
    'authorities': {'coverageLGA': 'coverage_lga'},
  };

  static const Map<String, Set<String>> columns = {
    'profiles': {
      'id', 'email', 'name', 'role', 'address', 'state', 'lga', 'ward', //
      'phone', 'is_verified', 'is_approved', 'is_disabled',
      'biometrics_enabled', 'profile_image_url', 'monitoring_zone',
      'registration_code', 'last_login_at', 'legacy_firebase_uid',
      'created_at', 'updated_at',
    },
    'reports': {
      'id', 'user_id', 'reporter_name', 'hazard_type', 'severity', //
      'latitude', 'longitude', 'location_details', 'location', 'address',
      'ward', 'lga', 'state', 'description', 'submitted_at', 'image_urls',
      'status', 'type', 'is_alert', 'verification_count', 'verified_at',
      'auto_validated', 'approved_at', 'rejected_at', 'rejection_reason',
      'escalated', 'escalated_at', 'escalation_reason',
      'escalation_scheduled_at', 'escalation_status', 'updated_by',
      'synced_at', 'legacy_firebase_id', 'created_at', 'updated_at',
    },
    'scheduled_escalations': {
      'id', 'report_id', 'escalate_at', 'status', 'reason', //
      'processed_at', 'created_at', 'updated_at',
    },
    'verifications': {
      'id', 'report_id', 'verifier_id', 'is_confirmed', 'comment', //
      'submitted_at', 'created_at', 'updated_at',
    },
    'verification_overrides': {
      'id', 'report_id', 'validator_id', 'action', 'reason', 'created_at', //
    },
    'alerts': {
      'id', 'title', 'message', 'severity', 'target_lga', 'report_id', //
      'created_by', 'is_active', 'created_at', 'updated_at',
    },
    'messages': {
      'id', 'chat_id', 'sender_id', 'sender_name', 'message', 'type', //
      'sent_at', 'read', 'created_at', 'updated_at',
    },
    'contacts': {
      'id', 'user_id', 'name', 'role', 'phone', 'organization', 'lga', //
      'category', 'is_available', 'created_at', 'updated_at',
    },
    'knowledge_base': {
      'id', 'title', 'content', 'source', 'category', 'hazard_type', //
      'image_url', 'legacy_firebase_id', 'created_at', 'updated_at',
    },
    'authorities': {
      'id', 'name', 'organization', 'phone', 'coverage_lga', //
      'created_at', 'updated_at',
    },
    'trusted_devices': {
      'id', 'user_id', 'device_fingerprint', 'device_name', 'trusted', //
      'last_used', 'created_at',
    },
    'login_history': {
      'id', 'user_id', 'success', 'device_fingerprint', 'device_name', //
      'risk_score', 'occurred_at', 'created_at',
    },
    'ndpa_consents': {
      'user_id', 'consented_at', 'policy_version', 'data_residency', //
      'platform', 'method',
    },
    'app_settings': {'key', 'value', 'updated_at'},
  };

  /// Primary key column per table (default `id`).
  static const Map<String, String> primaryKeys = {
    'ndpa_consents': 'user_id',
    'app_settings': 'key',
  };

  static String table(String collectionId) =>
      collectionAliases[collectionId] ?? collectionId;

  static String primaryKey(String table) => primaryKeys[table] ?? 'id';

  /// App field name → column name for [table].
  static String column(String table, String field) {
    if (field == r'$id') return primaryKey(table);
    final alias = fieldAliases[table]?[field];
    if (alias != null) return alias;
    return camelToSnake(field);
  }

  /// Column name → app field name for [table].
  static String field(String table, String column) {
    final aliases = fieldAliases[table];
    if (aliases != null) {
      for (final entry in aliases.entries) {
        // Only reverse aliases that are not a plain camel/snake pair.
        if (entry.value == column && camelToSnake(entry.key) != column) {
          return entry.key;
        }
      }
    }
    return snakeToCamel(column);
  }
}

// ───────────────────────────── Value encoding ────────────────────────────────

/// Encodes a Dart value for PostgREST: DateTimes become UTC ISO-8601 strings.
Object? encodeValue(Object? value) {
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (value is List) return value.map(encodeValue).toList();
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), encodeValue(v)));
  }
  return value;
}

/// Converts an app document into a row for [table].
///
/// * keys are converted camelCase → snake_case (plus per-table aliases);
/// * `$id` becomes the primary key;
/// * server-managed timestamps (`created_at`, `updated_at`) are dropped —
///   database defaults and triggers own them;
/// * fields that have no column on [table] are dropped (and logged) so a
///   stray legacy field never fails the whole write.
Map<String, dynamic> toRow(String table, Map<String, dynamic> data) {
  final known = SupabaseSchema.columns[table];
  final row = <String, dynamic>{};
  final dropped = <String>[];
  data.forEach((key, value) {
    if (key == r'$snapshot') return;
    final col = SupabaseSchema.column(table, key);
    if (SupabaseSchema.serverManagedColumns.contains(col)) return;
    if (known != null && !known.contains(col)) {
      dropped.add(key);
      return;
    }
    row[col] = encodeValue(value);
  });
  if (dropped.isNotEmpty) {
    developer.log(
      'toRow($table): dropped fields without a column: $dropped',
      name: 'SupabaseMapping',
    );
  }
  return row;
}

/// Converts a row from [table] into an app document: snake_case → camelCase
/// keys, with the primary key also exposed as `$id` (and `id`).
Map<String, dynamic> fromRow(String table, Map<String, dynamic> row) {
  final doc = <String, dynamic>{};
  row.forEach((col, value) {
    doc[SupabaseSchema.field(table, col)] = value;
  });
  final pk = SupabaseSchema.primaryKey(table);
  final id = row[pk];
  if (id != null) {
    doc[r'$id'] = id.toString();
    doc['id'] ??= id.toString();
  }
  return doc;
}

/// Parses a timestamp coming from Supabase (ISO string), a cached value or a
/// DateTime. Returns local time, or null when unparseable.
DateTime? parseTimestamp(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  return null;
}

// ───────────────────────────── Query DSL ─────────────────────────────────────

/// [neq] follows SQL (`NULL <> x` is not true, so NULL rows are excluded);
/// [distinctFrom] is `IS DISTINCT FROM` (NULL rows are included).
enum FilterOp { eq, neq, distinctFrom, gt, lt, contains }

/// A single column predicate, already resolved to a column name.
class ColumnFilter {
  const ColumnFilter(this.column, this.op, this.value);
  final String column;
  final FilterOp op;
  final Object? value;

  /// Evaluates the predicate against a raw row (snake_case), used for
  /// realtime streams where only one filter can be applied server-side.
  bool matches(Map<String, dynamic> row) {
    final actual = row[column];
    switch (op) {
      case FilterOp.eq:
        return _compare(actual, value) == 0;
      case FilterOp.neq:
        // SQL semantics: NULL <> x is not true.
        return actual != null && _compare(actual, value) != 0;
      case FilterOp.distinctFrom:
        return _compare(actual, value) != 0;
      case FilterOp.gt:
        return actual != null && _compare(actual, value) > 0;
      case FilterOp.lt:
        return actual != null && _compare(actual, value) < 0;
      case FilterOp.contains:
        if (actual is List) {
          final v = value;
          final List<Object?> wanted = v is List ? v : [v];
          return wanted.every(actual.contains);
        }
        return false;
    }
  }

  static int _compare(Object? a, Object? b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    if (a is num && b is num) return a.compareTo(b);
    if (a is bool && b is bool) return a == b ? 0 : (a ? 1 : -1);
    final da = a is String ? DateTime.tryParse(a) : null;
    final db = b is String ? DateTime.tryParse(b) : null;
    if (da != null && db != null) return da.compareTo(db);
    return a.toString().compareTo(b.toString());
  }

  @override
  String toString() => '$column.${op.name}.$value';
}

class ColumnOrder {
  const ColumnOrder(this.column, {required this.ascending});
  final String column;
  final bool ascending;

  @override
  String toString() => '$column.${ascending ? 'asc' : 'desc'}';
}

/// The resolved form of a list of [QueryFilter]s for one table.
class QueryPlan {
  QueryPlan(this.table, this.filters, this.orders, this.limit);

  factory QueryPlan.build(String collectionId, List<QueryFilter>? queries) {
    final table = SupabaseSchema.table(collectionId);
    final filters = <ColumnFilter>[];
    final orders = <ColumnOrder>[];
    int? limit;
    for (final q in queries ?? const <QueryFilter>[]) {
      if (q is WhereFilter) {
        filters.add(
          ColumnFilter(
            SupabaseSchema.column(table, q.field),
            q.op,
            encodeValue(q.value),
          ),
        );
      } else if (q is OrderByFilter) {
        orders.add(
          ColumnOrder(
            SupabaseSchema.column(table, q.field),
            ascending: !q.descending,
          ),
        );
      } else if (q is LimitFilter) {
        limit = q.limit;
      }
    }
    return QueryPlan(table, filters, orders, limit);
  }

  final String table;
  final List<ColumnFilter> filters;
  final List<ColumnOrder> orders;
  final int? limit;

  bool matches(Map<String, dynamic> row) =>
      filters.every((f) => f.matches(row));

  /// Columns that never change once a row exists. Only these may be used as
  /// the (single) server-side filter of a realtime stream: when a row stops
  /// matching a filter on a mutable column (e.g. `status`, `is_active`),
  /// Realtime no longer delivers its updates and the client would keep the
  /// stale row. Mutable columns are filtered on the client instead.
  static const Set<String> immutableStreamColumns = {
    'id',
    'user_id',
    'chat_id',
    'report_id',
    'verifier_id',
    'sender_id',
  };

  /// The filter a realtime stream can apply on the server, if any: an
  /// equality on an immutable column (or the primary key).
  ColumnFilter? get streamServerFilter {
    final pk = SupabaseSchema.primaryKey(table);
    for (final f in filters) {
      if (f.op == FilterOp.eq &&
          f.value != null &&
          (f.column == pk || immutableStreamColumns.contains(f.column))) {
        return f;
      }
    }
    return null;
  }

  /// The ordering a realtime stream can apply on the server (streams take a
  /// single order column; further orders are applied on the client).
  ColumnOrder? get streamServerOrder => orders.isEmpty ? null : orders.first;

  /// The limit a realtime stream can apply on the server: only when every
  /// filter runs on the server and the order is fully server-side —
  /// otherwise client-side filtering after a server limit would drop rows.
  int? get streamServerLimit {
    if (limit == null || orders.length > 1) return null;
    final server = streamServerFilter;
    final allServerSide =
        filters.isEmpty || (filters.length == 1 && filters.first == server);
    return allServerSide ? limit : null;
  }

  /// Sorts raw rows in place according to [orders].
  void sort(List<Map<String, dynamic>> rows) {
    if (orders.isEmpty) return;
    rows.sort((a, b) {
      for (final o in orders) {
        final c = ColumnFilter._compare(a[o.column], b[o.column]);
        if (c != 0) return o.ascending ? c : -c;
      }
      return 0;
    });
  }
}

/// Document-style query DSL used across the app; resolved to
/// PostgREST filters by [QueryPlan].
abstract class QueryFilter {
  const QueryFilter();
}

class WhereFilter extends QueryFilter {
  const WhereFilter(this.field, this.op, this.value);
  final String field;
  final FilterOp op;
  final Object? value;
}

class OrderByFilter extends QueryFilter {
  const OrderByFilter(this.field, {this.descending = false});
  final String field;
  final bool descending;
}

class LimitFilter extends QueryFilter {
  const LimitFilter(this.limit);
  final int limit;
}

class FQuery {
  FQuery._();
  static WhereFilter equal(String field, Object? value) =>
      WhereFilter(field, FilterOp.eq, value);
  static WhereFilter notEqual(String field, Object? value) =>
      WhereFilter(field, FilterOp.neq, value);

  /// `field IS DISTINCT FROM value`: unlike [notEqual], rows where the
  /// field is NULL match too (e.g. reports whose reporter was deleted).
  static WhereFilter distinctFrom(String field, Object? value) =>
      WhereFilter(field, FilterOp.distinctFrom, value);
  static WhereFilter greaterThan(String field, Object? value) =>
      WhereFilter(field, FilterOp.gt, value);
  static WhereFilter lessThan(String field, Object? value) =>
      WhereFilter(field, FilterOp.lt, value);
  static WhereFilter contains(String field, Object? value) =>
      WhereFilter(field, FilterOp.contains, value);
  static OrderByFilter orderDesc(String field) =>
      OrderByFilter(field, descending: true);
  static OrderByFilter orderAsc(String field) => OrderByFilter(field);
  static LimitFilter limit(int n) => LimitFilter(n);
}
