import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

/// A custom HTTP client that automatically injects authorization headers.
class AuthenticatedClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  final Map<String, String> _headers;

  AuthenticatedClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

class AuthService extends ChangeNotifier {
  GoogleSignInAccount? _currentUser;
  bool _isLoading = false;
  StreamSubscription? _authSubscription;

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  final List<String> _scopes = [
    'https://www.googleapis.com/auth/bigquery',
    'https://www.googleapis.com/auth/cloud-platform',
  ];

  AuthService() {
    // Initialize the plugin first
    final String webClientId = '226169391261-4qqt2be6t0iu2b9q6kblvdf79nkniaq5.apps.googleusercontent.com';
    
    final Future<void> initFuture;
    if (kIsWeb) {
      initFuture = _googleSignIn.initialize(
        clientId: webClientId,
      );
    } else {
      initFuture = _googleSignIn.initialize(
        serverClientId: webClientId,
      );
    }

    initFuture.then((_) {
      // Listen to authentication events
      _authSubscription = _googleSignIn.authenticationEvents.listen(_handleAuthenticationEvent);
      // Attempt to silently sign in
      attemptLightweightAuthentication();
    }).catchError((e) {
      debugPrint("Failed to initialize GoogleSignIn: $e");
    });
  }

  void _handleAuthenticationEvent(GoogleSignInAuthenticationEvent event) {
    final GoogleSignInAccount? user = switch (event) {
      GoogleSignInAuthenticationEventSignIn(:final user) => user,
      GoogleSignInAuthenticationEventSignOut() => null,
    };
    _currentUser = user;
    _isLoading = false;
    notifyListeners();
  }

  GoogleSignInAccount? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;

  /// Attempts to sign in the user silently on startup.
  Future<void> attemptLightweightAuthentication() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _googleSignIn.attemptLightweightAuthentication();
    } catch (e) {
      debugPrint("Lightweight authentication failed: $e");
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Triggers the interactive sign-in flow.
  Future<bool> signIn() async {
    _isLoading = true;
    notifyListeners();
    try {
      final account = await _googleSignIn.authenticate();
      if (account != null) {
        // Request the necessary BigQuery scopes
        await account.authorizationClient.authorizeScopes(_scopes);
      }
      return account != null;
    } catch (e) {
      debugPrint("Sign-in failed: $e");
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Signs out the active user.
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint("Sign-out failed: $e");
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Returns an authenticated [http.Client] that injects the active OAuth token.
  Future<http.Client?> getAuthenticatedClient() async {
    if (_currentUser == null) return null;
    try {
      final authorization = await _currentUser!.authorizationClient.authorizationForScopes(_scopes)
          ?? await _currentUser!.authorizationClient.authorizeScopes(_scopes);
      return AuthenticatedClient({
        'Authorization': 'Bearer ${authorization.accessToken}',
      });
    } catch (e) {
      debugPrint("Failed to authorize scopes: $e");
      return null;
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
