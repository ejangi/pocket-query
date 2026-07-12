import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:pocket_query/main.dart';
import 'package:pocket_query/services/auth_service.dart';
import 'package:pocket_query/screens/splash_screen.dart';
import 'package:pocket_query/screens/home_screen.dart';

// Reuse mock classes locally to isolate integration testing from OS OAuth popups
import 'package:pocket_query/services/bigquery_service.dart';
import '../test/auth_flow_test.dart';

void main() {
  // Initialize integration test engine bindings
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('E2E App Integration Flow', () {
    testWidgets('App launches to Splash Screen, performs mock Google Sign-in, and loads Home Workspace', (WidgetTester tester) async {
      final mockAuth = MockAuthService();
      final mockBQ = BigQueryService(mockAuth);

      // Launch the application using the mocked auth and BQ providers
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: mockAuth),
            ChangeNotifierProvider<BigQueryService>.value(value: mockBQ),
          ],
          child: const PocketQueryApp(),
        ),
      );

      // 1. Verify app starts at the Splash Screen and displays login action
      await tester.pumpAndSettle();
      expect(find.byType(SplashScreen), findsOneWidget);
      final loginButtonText = (!kIsWeb && Platform.isLinux) ? 'Get Started' : 'Sign in with Google';
      expect(find.text(loginButtonText), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);

      // 2. Perform tap gesture on the login button
      await tester.tap(find.text(loginButtonText));

      // Wait for all async actions and routing animations to settle
      await tester.pumpAndSettle();

      // 3. Verify successful transition to Home Screen query editor workspace
      expect(find.byType(SplashScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      
      // Verify that workspace action widgets like the 'Run' button are present
      expect(find.text('Run'), findsOneWidget);
      expect(find.text('Quick Count'), findsOneWidget);
    });
  });
}
