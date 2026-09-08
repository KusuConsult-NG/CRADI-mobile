import 'package:flutter_test/flutter_test.dart';

/// Tests for NotificationService topic subscription logic.
///
/// We test the pure functions that sanitize topic names and determine
/// which topics to subscribe to based on the monitoring zone string.
void main() {
  // Reproduce the sanitize + topic logic from NotificationService
  String sanitize(String s) =>
      s.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_').toLowerCase();

  List<String> topicsForZone(String? zone) {
    if (zone == null || zone.isEmpty) return [];

    final topics = <String>['all_alerts'];

    if (zone.contains(', ')) {
      final parts = zone.split(', ');
      final lga = sanitize(parts[0]);
      final state = sanitize(parts[1]);
      topics.add('state_$state');
      topics.add('lga_$lga');
    } else if (zone.endsWith(' State')) {
      final state = sanitize(zone.replaceAll(' State', ''));
      topics.add('state_$state');
    }

    return topics;
  }

  group('Topic Name Sanitization', () {
    test('lowercase conversion', () {
      expect(sanitize('Benue'), equals('benue'));
    });

    test('replaces spaces with underscore', () {
      expect(
        sanitize('Federal Capital Territory'),
        equals('federal_capital_territory'),
      );
    });

    test('strips special characters', () {
      expect(sanitize("Ogun-State's"), equals('ogun_state_s'));
    });

    test('preserves digits', () {
      expect(sanitize('Zone1'), equals('zone1'));
    });

    test('empty string stays empty', () {
      expect(sanitize(''), equals(''));
    });
  });

  group('FCM Topic Resolution', () {
    test('null zone returns no topics', () {
      expect(topicsForZone(null), isEmpty);
    });

    test('empty zone returns no topics', () {
      expect(topicsForZone(''), isEmpty);
    });

    test('LGA format subscribes to all_alerts, state, and lga', () {
      final topics = topicsForZone('Makurdi, Benue');
      expect(topics, contains('all_alerts'));
      expect(topics, contains('state_benue'));
      expect(topics, contains('lga_makurdi'));
      expect(topics.length, equals(3));
    });

    test('State format subscribes to all_alerts and state', () {
      final topics = topicsForZone('Benue State');
      expect(topics, contains('all_alerts'));
      expect(topics, contains('state_benue'));
      expect(topics.length, equals(2));
    });

    test('FCT edge case', () {
      final topics = topicsForZone('Abuja, Federal Capital Territory');
      expect(topics, contains('state_federal_capital_territory'));
      expect(topics, contains('lga_abuja'));
    });

    test('unknown format only subscribes to all_alerts', () {
      final topics = topicsForZone('Unknown Zone X');
      expect(topics, equals(['all_alerts']));
    });

    test('multi-word LGA handles correctly', () {
      final topics = topicsForZone('Ijebu North, Ogun');
      expect(topics, contains('lga_ijebu_north'));
      expect(topics, contains('state_ogun'));
    });
  });

  group('Notification Navigation Routing', () {
    // Mirrors _handleNotificationNavigation switch logic
    String routeForData(Map<String, dynamic> data) {
      final type = data['type'] ?? 'alert';
      final id = data['id'] as String? ?? data['reportId'] as String? ?? '';

      switch (type) {
        case 'report':
        case 'verification':
          return id.isNotEmpty ? '/report/$id' : '/reports-status';
        case 'alert':
          return id.isNotEmpty ? '/alert/$id' : '/alerts';
        case 'chat':
          return '/chat';
        default:
          return '/notifications';
      }
    }

    test('alert with id routes to alert detail', () {
      expect(routeForData({'type': 'alert', 'id': 'abc123'}), '/alert/abc123');
    });

    test('alert without id routes to alerts list', () {
      expect(routeForData({'type': 'alert'}), '/alerts');
    });

    test('report with id routes to report detail', () {
      expect(routeForData({'type': 'report', 'id': 'r1'}), '/report/r1');
    });

    test('report with reportId routes to report detail', () {
      expect(routeForData({'type': 'report', 'reportId': 'r2'}), '/report/r2');
    });

    test('verification type routes like report', () {
      expect(routeForData({'type': 'verification', 'id': 'v1'}), '/report/v1');
    });

    test('chat type routes to chat', () {
      expect(routeForData({'type': 'chat'}), '/chat');
    });

    test('unknown type routes to notifications', () {
      expect(routeForData({'type': 'system'}), '/notifications');
    });

    test('missing type defaults to alert', () {
      expect(routeForData({}), '/alerts');
    });

    test('empty id treated as no id', () {
      expect(routeForData({'type': 'report', 'id': ''}), '/reports-status');
    });
  });
}
