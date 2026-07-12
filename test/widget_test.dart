import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:pocket_query/services/auth_service.dart';
import 'package:pocket_query/screens/splash_screen.dart';

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

void main() {
  testWidgets('App renders splash screen elements initially', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>(
        create: (_) => AuthService(),
        child: const MaterialApp(
          home: SplashScreen(),
        ),
      ),
    );

    // Verify that the SVG assets (Logo and Title) are present.
    expect(find.byType(SvgPicture), findsNWidgets(2));
    
    // Verify that the login button is shown.
    final loginButtonText = (!kIsWeb && Platform.isLinux) ? 'Get Started' : 'Sign in with Google';
    expect(find.text(loginButtonText), findsOneWidget);
  });
}
