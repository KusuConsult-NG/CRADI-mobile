import 'package:flutter_test/flutter_test.dart';
import 'package:climate_app/core/services/notification_service.dart';

/// Tests for NotificationService pure logic: push-payload routing.
/// (OneSignal tag sanitisation is covered in supabase_mapping_test.dart.)
void main() {
  String route(Map<String, dynamic> data) =>
      NotificationService.routeForData(data);

  group('Backend notification types', () {
    test('verification_request routes to the report', () {
      expect(
        route({'type': 'verification_request', 'report_id': 'r1'}),
        '/report/r1',
      );
    });

    test('report_status routes to the report', () {
      expect(route({'type': 'report_status', 'report_id': 'r2'}), '/report/r2');
    });

    test('escalation_auto routes to the report', () {
      expect(
        route({'type': 'escalation_auto', 'report_id': 'r3'}),
        '/report/r3',
      );
    });

    test('validated_alert / admin_alert route to the alert', () {
      expect(route({'type': 'validated_alert', 'alert_id': 'a1'}), '/alert/a1');
      expect(route({'type': 'admin_alert', 'alert_id': 'a2'}), '/alert/a2');
    });

    test('alert types without id route to the alerts list', () {
      expect(route({'type': 'admin_alert'}), '/alerts');
    });

    test('report types without id route to the reports list', () {
      expect(route({'type': 'report_status'}), '/reports-status');
    });
  });

  group('Legacy payloads', () {
    test('alert with id routes to alert detail', () {
      expect(route({'type': 'alert', 'id': 'abc123'}), '/alert/abc123');
    });

    test('report with reportId routes to report detail', () {
      expect(route({'type': 'report', 'reportId': 'r2'}), '/report/r2');
    });

    test('verification type routes like report', () {
      expect(route({'type': 'verification', 'id': 'v1'}), '/report/v1');
    });

    test('chat type routes to chat', () {
      expect(route({'type': 'chat'}), '/chat');
    });

    test('unknown type routes to notifications', () {
      expect(route({'type': 'system'}), '/notifications');
    });

    test('missing type defaults to alert', () {
      expect(route({}), '/alerts');
    });

    test('empty id treated as no id', () {
      expect(route({'type': 'report', 'id': ''}), '/reports-status');
    });
  });
}
