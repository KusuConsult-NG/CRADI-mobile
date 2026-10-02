import 'package:flutter_test/flutter_test.dart';

import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/services/supabase_mapping.dart';
import 'package:climate_app/core/services/supabase_service.dart';

/// The data seam. Two things here are strings the server parses and the
/// client never validates, so a typo in either degrades silently rather
/// than failing: the PostgREST projection for an embedded relation, and
/// the query plan behind a list.
void main() {
  group('the embed projection', () {
    test('names the related table, the foreign key and the fields', () {
      // Byte-for-byte what `getVerifications` sent before it went through
      // the interface. If this drifts, the embed throws, the adapter falls
      // back to plain documents by contract, and every verifier name
      // quietly disappears from the UI with nothing logged as an error.
      expect(
        SupabaseService.selectionFor(
          const RelatedFields(
            alias: 'verifier',
            collectionId: AppConfig.usersCollection,
            foreignKey: 'verifierId',
            fields: ['name'],
          ),
        ),
        '*, verifier:profiles!verifier_id(name)',
      );
    });

    test('field and key names are converted, not passed through', () {
      expect(
        SupabaseService.selectionFor(
          const RelatedFields(
            alias: 'reporter',
            collectionId: AppConfig.usersCollection,
            foreignKey: 'userId',
            fields: ['name', 'phoneNumber'],
          ),
        ),
        '*, reporter:profiles!user_id(name, phone_number)',
      );
    });

    test('no relation selects everything', () {
      expect(SupabaseService.selectionFor(null), '*');
    });
  });

  group('the verifications query', () {
    test('filters, orders and limits as the raw call did', () {
      final plan = QueryPlan.build(AppConfig.verificationsCollection, [
        FQuery.equal('reportId', 'r1'),
        FQuery.orderDesc('submittedAt'),
        FQuery.limit(200),
      ]);

      expect(plan.table, 'verifications');
      expect(plan.filters.map((f) => f.column), ['report_id']);
      expect(plan.orders.single.column, 'submitted_at');
      expect(plan.orders.single.ascending, isFalse);
      expect(plan.limit, 200);
    });
  });

  test('app settings survive the document mapping', () {
    // `_fetch` reads `row['key']` and `row['value']` off each document.
    // The mapper adds `$id`/`id` for the primary key, which is `key` here —
    // harmless, because the loop reads named fields rather than iterating
    // the map.
    final doc = fromRow('app_settings', {'key': 'minPeers', 'value': 3});
    expect(doc['key'], 'minPeers');
    expect(doc['value'], 3);
  });
}
