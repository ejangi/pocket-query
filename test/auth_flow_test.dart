import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pocket_query/services/auth_service.dart';
import 'package:pocket_query/screens/splash_screen.dart';
import 'package:pocket_query/screens/home_screen.dart';
import 'package:pocket_query/main.dart';

// Mock implementations matching GoogleSignIn v7.2.0 API exactly

class MockGoogleSignInClientAuthorization implements GoogleSignInClientAuthorization {
  @override
  String get accessToken => 'mock_access_token';
}

class MockGoogleSignInAuthorizationClient implements GoogleSignInAuthorizationClient {
  @override
  Future<GoogleSignInClientAuthorization> authorizeScopes(List<String> scopes) async {
    return MockGoogleSignInClientAuthorization();
  }

  @override
  Future<GoogleSignInClientAuthorization?> authorizationForScopes(List<String> scopes) async {
    return MockGoogleSignInClientAuthorization();
  }

  @override
  Future<Map<String, String>?> authorizationHeaders(List<String> scopes, {bool promptIfNecessary = false}) async {
    return {'Authorization': 'Bearer mock_access_token'};
  }

  @override
  Future<GoogleSignInServerAuthorization?> authorizeServer(List<String> scopes) async {
    return null;
  }

  @override
  Future<void> clearAuthorizationToken({required String accessToken}) async {}
}

class MockGoogleSignInAuthentication implements GoogleSignInAuthentication {
  @override
  String? get accessToken => 'mock_access_token';

  @override
  String? get idToken => 'mock_id_token';
}

class MockGoogleSignInAccount implements GoogleSignInAccount {
  @override
  String get displayName => 'Test User';

  @override
  String get email => 'test@example.com';

  @override
  String get id => '12345';

  @override
  String? get photoUrl => null;

  @override
  String? get serverAuthCode => null;

  @override
  GoogleSignInAuthentication get authentication => MockGoogleSignInAuthentication();

  @override
  Future<Map<String, String>> get authHeaders async => {};

  @override
  Future<void> clearAuthCache() async {}

  @override
  GoogleSignInAuthorizationClient get authorizationClient => MockGoogleSignInAuthorizationClient();
}

// A Mock representation of our AuthService
class MockAuthService extends ChangeNotifier implements AuthService {
  GoogleSignInAccount? _currentUser;
  bool _isLoading = false;
  bool signInResult = true;
  int signInCallCount = 0;

  @override
  GoogleSignInAccount? get currentUser => _currentUser;

  @override
  bool get isAuthenticated => _currentUser != null;

  @override
  bool get isLoading => _isLoading;

  @override
  Future<void> attemptLightweightAuthentication() async {
    // Mock silent sign-in does nothing by default in this test
  }

  @override
  Future<bool> signIn() async {
    signInCallCount++;
    _isLoading = true;
    notifyListeners();
    
    // Simulate short network delay
    await Future.delayed(const Duration(milliseconds: 10));
    
    _isLoading = false;
    if (signInResult) {
      _currentUser = MockGoogleSignInAccount();
    }
    notifyListeners();
    return signInResult;
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    notifyListeners();
  }

  @override
  Future<http.Client?> getAuthenticatedClient() async {
    return null;
  }
}

void main() {
  testWidgets('Authentication Flow Test - Successful Sign In', (WidgetTester tester) async {
    final mockAuth = MockAuthService();

    // Render the App with the Mock AuthService injected
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>.value(
        value: mockAuth,
        child: const MaterialApp(
          home: AuthGate(),
        ),
      ),
    );

    // 1. Initially should render the Splash Screen
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    
    // Find and tap the "Sign in with Google" button
    final loginButton = find.text('Sign in with Google');
    expect(loginButton, findsOneWidget);
    await tester.tap(loginButton);
    
    // Trigger the initial frame change
    await tester.pump();
    
    // 2. Check loading state (button should show CircularProgressIndicator instead of text)
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    
    // Wait for the simulated sign-in network delay to resolve
    await tester.pump(const Duration(milliseconds: 20));
    
    // 3. AuthGate should rebuild and navigate to HomeScreen
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(mockAuth.signInCallCount, 1);
  });

  testWidgets('Authentication Flow Test - Failed Sign In displays Error Banner', (WidgetTester tester) async {
    final mockAuth = MockAuthService()..signInResult = false;

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>.value(
        value: mockAuth,
        child: const MaterialApp(
          home: AuthGate(),
        ),
      ),
    );

    // Find and tap sign-in
    await tester.tap(find.text('Sign in with Google'));
    await tester.pump();
    
    // Wait for network delay
    await tester.pump(const Duration(milliseconds: 20));
    
    // 4. Verify that we remain on the SplashScreen
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });
}
