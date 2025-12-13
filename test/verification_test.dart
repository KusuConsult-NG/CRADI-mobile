import 'package:climate_app/core/theme/app_theme.dart';
import 'package:climate_app/features/alerts/screens/alerts_list_screen.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/auth/screens/registration_screen.dart';
import 'package:climate_app/features/contacts/screens/emergency_contacts_screen.dart';
import 'package:climate_app/features/dashboard/screens/home_screen.dart';
import 'package:climate_app/features/knowledge_base/screens/hazard_guides_screen.dart';
import 'package:climate_app/features/knowledge_base/screens/knowledge_base_screen.dart';
import 'package:climate_app/features/profile/screens/user_profile_screen.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:climate_app/features/reporting/screens/hazard_selection_screen.dart';
import 'package:climate_app/features/reporting/screens/location_picker_screen.dart';
import 'package:climate_app/features/reporting/screens/report_details_screen.dart';
import 'package:climate_app/features/reporting/screens/report_review_screen.dart';
import 'package:climate_app/features/settings/screens/settings_screen.dart';
import 'package:climate_app/features/verification/screens/verification_request_screen.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

// ... imports ...

class TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _MockHttpClient();
  }
}

class _MockHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return _MockHttpClientRequest();
  }

  @override
  set autoUncompress(bool autoUncompress) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    // throw UnimplementedError(); // Commented out to be lenient
  }
}

class _MockHttpClientRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  Future<HttpClientResponse> close() async {
    return _MockHttpClientResponse();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {} 
}

class _MockHttpClientResponse implements HttpClientResponse {
  @override
  int get statusCode => 200;
  
  @override
  int get contentLength => kTransparentImage.length;
  
  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData, {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream.value(kTransparentImage).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
  
  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

class _MockHttpHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

final List<int> kTransparentImage = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49,
  0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06,
  0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44,
  0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D,
  0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
  0x60, 0x82,
];


Widget makeTestableWidget({required Widget child}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => ReportingProvider()),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: child,
    ),
  );
}

void main() {
  setUpAll(() {
    HttpOverrides.global = TestHttpOverrides();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('Render RegistrationScreen', (WidgetTester tester) async {
    await tester.pumpWidget(makeTestableWidget(child: const RegistrationScreen()));
    expect(find.byType(RegistrationScreen), findsOneWidget);
  });

  testWidgets('Render HomeScreen', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(makeTestableWidget(child: const HomeScreen()));
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('Render HazardSelectionScreen', (WidgetTester tester) async {
    await tester.pumpWidget(makeTestableWidget(child: const HazardSelectionScreen()));
    expect(find.byType(HazardSelectionScreen), findsOneWidget);
  });

  testWidgets('Render LocationPickerScreen', (WidgetTester tester) async {
    await tester.pumpWidget(makeTestableWidget(child: const LocationPickerScreen()));
    expect(find.byType(LocationPickerScreen), findsOneWidget);
  });

  testWidgets('Render ReportDetailsScreen', (WidgetTester tester) async {
    await tester.pumpWidget(makeTestableWidget(child: const ReportDetailsScreen()));
    expect(find.byType(ReportDetailsScreen), findsOneWidget);
  });

  testWidgets('Render ReportReviewScreen', (WidgetTester tester) async {
    await tester.pumpWidget(makeTestableWidget(child: const ReportReviewScreen()));
    expect(find.byType(ReportReviewScreen), findsOneWidget);
  });

  testWidgets('Render UserProfileScreen', (WidgetTester tester) async {
    await tester.pumpWidget(makeTestableWidget(child: const UserProfileScreen()));
    expect(find.byType(UserProfileScreen), findsOneWidget);
  });

  testWidgets('Render SettingsScreen', (WidgetTester tester) async {
    await tester.pumpWidget(makeTestableWidget(child: const SettingsScreen()));
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('Render EmergencyContactsScreen', (WidgetTester tester) async {
    await tester.pumpWidget(makeTestableWidget(child: const EmergencyContactsScreen()));
    expect(find.byType(EmergencyContactsScreen), findsOneWidget);
  });

  testWidgets('Render KnowledgeBaseScreen', (WidgetTester tester) async {
    await tester.pumpWidget(makeTestableWidget(child: const KnowledgeBaseScreen()));
    expect(find.byType(KnowledgeBaseScreen), findsOneWidget);
  });

  testWidgets('Render HazardGuidesScreen', (WidgetTester tester) async {
    await tester.pumpWidget(makeTestableWidget(child: const HazardGuidesScreen()));
    expect(find.byType(HazardGuidesScreen), findsOneWidget);
  });

  testWidgets('Render AlertsListScreen', (WidgetTester tester) async {
    await tester.pumpWidget(makeTestableWidget(child: const AlertsListScreen()));
    expect(find.byType(AlertsListScreen), findsOneWidget);
  });

  testWidgets('Render VerificationRequestScreen', (WidgetTester tester) async {
    await tester.pumpWidget(makeTestableWidget(child: const VerificationRequestScreen()));
    expect(find.byType(VerificationRequestScreen), findsOneWidget);
  });
}
