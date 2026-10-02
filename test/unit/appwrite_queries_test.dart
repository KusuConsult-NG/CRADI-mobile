import 'package:flutter_test/flutter_test.dart';

import 'package:climate_app/core/services/appwrite/appwrite_queries.dart';
import 'package:climate_app/core/services/data_backend.dart';

/// Null handling is the whole difficulty in translating these filters, and
/// it is not a detail: `distinctFrom` exists as a separate operator purely
/// so the verification list keeps reports whose reporter was deleted. Get
/// it backwards and those reports vanish, silently, for everybody.
void main() {
  String one(QueryFilter f) => buildAppwriteQueries([f]).single;

  group('equality', () {
    test('equal is equal', () {
      expect(one(FQuery.equal('status', 'pending')), contains('"equal"'));
      expect(one(FQuery.equal('status', 'pending')), contains('pending'));
    });

    test('equal to null asks for null, not for the string "null"', () {
      expect(one(FQuery.equal('ward', null)), contains('"isNull"'));
    });
  });

  group('the two not-equals are different queries, deliberately', () {
    final neq = one(FQuery.notEqual('ward', 'A'));
    final distinct = one(FQuery.distinctFrom('userId', 'u1'));

    test('notEqual excludes nulls, as SQL does', () {
      // `NULL <> x` is not true, and the app's own evaluator agrees, so
      // the translation says so explicitly rather than trusting Appwrite's
      // bare notEqual to behave the same way.
      expect(neq, contains('"and"'));
      expect(neq, contains('isNotNull'));
      expect(neq, contains('notEqual'));
      expect(neq, isNot(contains('"isNull"')));
    });

    test('distinctFrom keeps them', () {
      expect(distinct, contains('"or"'));
      expect(distinct, contains('isNull'));
      expect(distinct, contains('notEqual'));
    });

    test('and they are not the same string', () {
      expect(neq, isNot(equals(distinct)));
    });
  });

  group('IN', () {
    test('a list becomes one equal, which is how Appwrite spells IN', () {
      final q = one(FQuery.isIn('status', ['pending', 'approved']));
      expect(q, contains('"equal"'));
      expect(q, contains('pending'));
      expect(q, contains('approved'));
    });

    test('an empty list matches nothing, not everything', () {
      // The dangerous direction: `IN ()` is false in SQL, but an empty
      // Appwrite `equal` would read as no constraint at all and return the
      // whole collection. There is no literal false, so say it as a
      // contradiction the server can evaluate.
      final q = one(FQuery.isIn('status', []));
      expect(q, contains('isNull'));
      expect(q, contains('isNotNull'));
    });
  });

  group('contains', () {
    test('a single value uses contains', () {
      expect(one(FQuery.contains('tags', 'flood')), contains('"contains"'));
    });

    test('several values must all be present, as the app evaluator says', () {
      final q = one(FQuery.contains('tags', ['flood', 'urgent']));
      expect(q, contains('containsAll'));
    });
  });

  group('ordering, limit and offset', () {
    test('order and limit come through', () {
      final qs = buildAppwriteQueries([
        FQuery.orderDesc('submittedAt'),
        FQuery.limit(50),
      ]);
      expect(qs.any((q) => q.contains('orderDesc')), isTrue);
      expect(qs.any((q) => q.contains('"limit"')), isTrue);
    });

    test('an explicit limitCount wins over a LimitFilter', () {
      final qs = buildAppwriteQueries([FQuery.limit(50)], limitCount: 10);
      final limits = qs.where((q) => q.contains('"limit"')).toList();
      expect(limits, hasLength(1));
      expect(limits.single, contains('10'));
    });

    test('offset is only sent when it is not zero', () {
      expect(
        buildAppwriteQueries(null).any((q) => q.contains('offset')),
        isFalse,
      );
      expect(
        buildAppwriteQueries(null, offset: 20).any((q) => q.contains('offset')),
        isTrue,
      );
    });

    test('no filters is no queries', () {
      expect(buildAppwriteQueries(null), isEmpty);
      expect(buildAppwriteQueries([]), isEmpty);
    });
  });

  test('a DateTime is sent as UTC ISO-8601, not as a Dart toString', () {
    final q = one(FQuery.greaterThan('createdAt', DateTime.utc(2026, 3, 1, 9)));
    expect(q, contains('2026-03-01T09:00:00.000Z'));
  });

  group('DocumentPlan — the client-side half of a realtime stream', () {
    final docs = [
      {r'$id': 'a', 'status': 'pending', 'n': 2, 'userId': 'u1'},
      {r'$id': 'b', 'status': 'approved', 'n': 1, 'userId': null},
      {r'$id': 'c', 'status': 'pending', 'n': 3, 'userId': 'u2'},
    ];

    test('filters on the document field, with no schema in between', () {
      final plan = DocumentPlan.build([FQuery.equal('status', 'pending')]);
      expect(plan.apply(docs).map((d) => d[r'$id']), ['a', 'c']);
    });

    test('distinctFrom keeps the null reporter', () {
      final plan = DocumentPlan.build([FQuery.distinctFrom('userId', 'u1')]);
      expect(plan.apply(docs).map((d) => d[r'$id']), ['b', 'c']);
    });

    test('notEqual drops it', () {
      final plan = DocumentPlan.build([FQuery.notEqual('userId', 'u1')]);
      expect(plan.apply(docs).map((d) => d[r'$id']), ['c']);
    });

    test('orders and then truncates, in that order', () {
      final plan = DocumentPlan.build([FQuery.orderDesc('n'), FQuery.limit(2)]);
      expect(plan.apply(docs).map((d) => d[r'$id']), ['c', 'a']);
    });
  });
}
