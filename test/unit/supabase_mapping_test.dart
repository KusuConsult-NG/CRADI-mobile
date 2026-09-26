import 'package:flutter_test/flutter_test.dart';
import 'package:climate_app/core/services/supabase_mapping.dart';
import 'package:climate_app/core/services/notification_service.dart';

void main() {
  group('key conversion', () {
    test('camelCase → snake_case', () {
      expect(camelToSnake('userId'), 'user_id');
      expect(camelToSnake('imageUrls'), 'image_urls');
      expect(camelToSnake('escalationScheduledAt'), 'escalation_scheduled_at');
      expect(camelToSnake('coverageLGA'), 'coverage_lga');
      expect(camelToSnake('lga'), 'lga');
      expect(camelToSnake('already_snake'), 'already_snake');
    });

    test('snake_case → camelCase', () {
      expect(snakeToCamel('user_id'), 'userId');
      expect(snakeToCamel('image_urls'), 'imageUrls');
      expect(snakeToCamel('escalation_scheduled_at'), 'escalationScheduledAt');
      expect(snakeToCamel('lga'), 'lga');
    });

    test('round trip for every schema column', () {
      for (final entry in SupabaseSchema.columns.entries) {
        for (final col in entry.value) {
          expect(
            camelToSnake(snakeToCamel(col)),
            col,
            reason: '${entry.key}.$col',
          );
        }
      }
    });
  });

  group('toRow', () {
    test('maps keys, \$id, collection alias and drops unknown fields', () {
      final table = SupabaseSchema.table('users');
      expect(table, 'profiles');

      final row = toRow(table, {
        r'$id': 'abc',
        'isApproved': true,
        'profileImageUrl': 'https://x/y.jpg',
        'pushToken': 'legacy', // no such column
        'createdAt': '2020-01-01', // server managed
        'updatedAt': '2020-01-01', // server managed
      });

      expect(row, {
        'id': 'abc',
        'is_approved': true,
        'profile_image_url': 'https://x/y.jpg',
      });
    });

    test('per-table aliases', () {
      expect(toRow('login_history', {'timestamp': 'x'}), {'occurred_at': 'x'});
      expect(toRow('ndpa_consents', {'uid': 'u1'}), {'user_id': 'u1'});
      expect(toRow('authorities', {'coverageLGA': 'Makurdi'}), {
        'coverage_lga': 'Makurdi',
      });
    });

    test('DateTimes are encoded as UTC ISO strings', () {
      final dt = DateTime.utc(2026, 9, 25, 10, 30);
      final row = toRow('reports', {'submittedAt': dt});
      expect(row['submitted_at'], '2026-09-25T10:30:00.000Z');
    });
  });

  group('fromRow', () {
    test('snake → camel and exposes the primary key as \$id', () {
      final doc = fromRow('reports', {
        'id': 'r1',
        'user_id': 'u1',
        'image_urls': ['a'],
        'submitted_at': '2026-09-25T10:30:00+00:00',
      });
      expect(doc[r'$id'], 'r1');
      expect(doc['id'], 'r1');
      expect(doc['userId'], 'u1');
      expect(doc['imageUrls'], ['a']);
      expect(doc['submittedAt'], '2026-09-25T10:30:00+00:00');
    });

    test('non-id primary keys and reverse aliases', () {
      final consent = fromRow('ndpa_consents', {'user_id': 'u1'});
      expect(consent[r'$id'], 'u1');
      expect(consent['uid'], 'u1');

      final login = fromRow('login_history', {'id': 'l1', 'occurred_at': 't'});
      expect(login['timestamp'], 't');
    });
  });

  group('QueryPlan', () {
    test('maps FQuery filters, ordering and limit to columns', () {
      final plan = QueryPlan.build('reports', [
        FQuery.equal('status', 'pending'),
        FQuery.notEqual('userId', 'me'),
        FQuery.greaterThan('submittedAt', DateTime.utc(2026)),
        FQuery.lessThan('verificationCount', 3),
        FQuery.orderDesc('submittedAt'),
        FQuery.orderAsc('hazardType'),
        FQuery.limit(20),
      ]);

      expect(plan.table, 'reports');
      expect(plan.filters.map((f) => f.toString()).toList(), [
        'status.eq.pending',
        'user_id.neq.me',
        'submitted_at.gt.2026-01-01T00:00:00.000Z',
        'verification_count.lt.3',
      ]);
      expect(plan.orders.map((o) => o.toString()).toList(), [
        'submitted_at.desc',
        'hazard_type.asc',
      ]);
      expect(plan.limit, 20);
    });

    test('collection aliases apply to queries', () {
      final plan = QueryPlan.build('users', [FQuery.equal('role', 'ewm')]);
      expect(plan.table, 'profiles');
      expect(plan.filters.single.column, 'role');
    });

    test('client-side evaluation matches SQL semantics', () {
      final plan = QueryPlan.build('reports', [
        FQuery.equal('status', 'pending'),
        FQuery.notEqual('userId', 'me'),
        FQuery.greaterThan('submittedAt', DateTime.utc(2026, 1, 1)),
      ]);
      Map<String, dynamic> row(String? user, String status, String at) => {
        'status': status,
        'user_id': user,
        'submitted_at': at,
      };

      expect(
        plan.matches(row('other', 'pending', '2026-02-01T00:00:00Z')),
        isTrue,
      );
      expect(
        plan.matches(row('me', 'pending', '2026-02-01T00:00:00Z')),
        isFalse,
      );
      // NULL <> 'me' is not true in SQL.
      expect(
        plan.matches(row(null, 'pending', '2026-02-01T00:00:00Z')),
        isFalse,
      );
      expect(
        plan.matches(row('other', 'verified', '2026-02-01T00:00:00Z')),
        isFalse,
      );
      // Timestamps compare chronologically, not lexically across offsets.
      expect(
        plan.matches(row('other', 'pending', '2025-12-31T23:00:00-02:00')),
        isTrue,
      );
      expect(
        plan.matches(row('other', 'pending', '2025-12-31T23:00:00Z')),
        isFalse,
      );
    });

    test('sort orders rows like ORDER BY', () {
      final plan = QueryPlan.build('messages', [FQuery.orderDesc('sentAt')]);
      final rows = [
        {'sent_at': '2026-01-01T00:00:00Z'},
        {'sent_at': '2026-03-01T00:00:00Z'},
        {'sent_at': '2026-02-01T00:00:00Z'},
      ];
      plan.sort(rows);
      expect(rows.map((r) => r['sent_at']).toList(), [
        '2026-03-01T00:00:00Z',
        '2026-02-01T00:00:00Z',
        '2026-01-01T00:00:00Z',
      ]);
    });
  });

  group('parseTimestamp', () {
    test('parses ISO strings to local time and tolerates junk', () {
      final t = parseTimestamp('2026-09-25T10:30:00+00:00');
      expect(t, isNotNull);
      expect(t!.isUtc, isFalse);
      expect(t.toUtc(), DateTime.utc(2026, 9, 25, 10, 30));
      expect(parseTimestamp('nope'), isNull);
      expect(parseTimestamp(null), isNull);
    });
  });

  group('OneSignal tags', () {
    test('sanitised exactly like the backend', () {
      expect(
        NotificationService.sanitizeTag('Makurdi, Benue'),
        'makurdi__benue',
      );
      expect(NotificationService.sanitizeTag('Katsina-Ala'), 'katsina_ala');
      expect(NotificationService.sanitizeTag(' Ward 1'), '_ward_1');
      expect(NotificationService.sanitizeTag('techSupport'), 'techsupport');
    });

    test('tagsFor omits empty values', () {
      expect(
        NotificationService.tagsFor(
          role: 'ewm',
          lga: 'Makurdi',
          state: '',
          ward: null,
          monitoringZone: 'Benue State',
        ),
        {'role': 'ewm', 'lga': 'makurdi', 'monitoring_zone': 'benue_state'},
      );
    });
  });
}
