// ignore_for_file: subtype_of_sealed_class, must_be_immutable
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:climate_app/core/theme/app_theme.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/auth/screens/registration_screen.dart';
import 'package:climate_app/features/profile/providers/profile_provider.dart';
import 'package:climate_app/core/providers/connectivity_provider.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:climate_app/features/reporting/screens/hazard_selection_screen.dart';
import 'package:climate_app/features/verification/screens/verification_request_screen.dart';
import 'package:climate_app/features/contacts/providers/emergency_contacts_provider.dart';
import 'package:climate_app/features/contacts/models/emergency_contact_model.dart';
import 'package:climate_app/core/providers/language_provider.dart';

class MockEmergencyContactsProvider extends ChangeNotifier
    implements EmergencyContactsProvider {
  @override
  Stream<List<EmergencyContact>> getContactsStream() => Stream.value([]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockLanguageProvider extends ChangeNotifier implements LanguageProvider {
  @override
  String get back => 'Back';
  @override
  String get attentionText => 'Please verify your safety';
  @override
  String get settingsTitle => 'Settings';
  @override
  String get language => 'Language';
  @override
  String get selectedLanguage => 'English';
  @override
  String get notifications => 'Notifications';
  @override
  String get pushNotifications => 'Push Notifications';
  @override
  String get criticalAlerts => 'Critical Alerts';
  @override
  String get dnd => 'Do Not Disturb';
  @override
  String get dataStorage => 'Data & Storage';
  @override
  String get wifiOnly => 'WiFi Only';
  @override
  String get lowData => 'Low Data Mode';
  @override
  String get general => 'General';
  @override
  String get helpFaq => 'Help & FAQ';
  @override
  String get ok => 'OK';
  @override
  String get aboutApp => 'About App';
  @override
  String get logout => 'Logout';
  @override
  String get greeting => 'Good Morning';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget makeTestableWidget({required Widget child}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => ReportingProvider()),
      ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
      ChangeNotifierProvider(create: (_) => ProfileProvider()),
      ChangeNotifierProvider<LanguageProvider>(
        create: (_) => MockLanguageProvider(),
      ),
      ChangeNotifierProvider<EmergencyContactsProvider>(
        create: (_) => MockEmergencyContactsProvider(),
      ),
    ],
    child: MaterialApp(theme: AppTheme.lightTheme, home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    HttpOverrides.global = TestHttpOverrides();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('Render RegistrationScreen', (WidgetTester tester) async {
    await tester.pumpWidget(
      makeTestableWidget(child: const RegistrationScreen()),
    );
    expect(find.byType(RegistrationScreen), findsOneWidget);
  });

  testWidgets('Render HazardSelectionScreen', (WidgetTester tester) async {
    await tester.pumpWidget(
      makeTestableWidget(child: const HazardSelectionScreen()),
    );
    expect(find.byType(HazardSelectionScreen), findsOneWidget);
  });

  testWidgets('Render VerificationRequestScreen', (WidgetTester tester) async {
    await tester.pumpWidget(
      makeTestableWidget(child: const VerificationRequestScreen()),
    );
    expect(find.byType(VerificationRequestScreen), findsOneWidget);
  });
}

class TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _MockHttpClient();
}

class _MockHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();
  @override
  set autoUncompress(bool b) {}
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _MockHttpClientRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();
  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _MockHttpClientResponse implements HttpClientResponse {
  @override
  int get statusCode => 200;
  @override
  int get contentLength => kTransparentImage.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream.value(kTransparentImage).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _MockHttpHeaders implements HttpHeaders {
  @override
  void add(String n, Object v, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

final List<int> kTransparentImage = [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];
