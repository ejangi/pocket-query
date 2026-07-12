import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pocket_query/services/auth_service.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final isLinux = !kIsWeb && Platform.isLinux;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                SvgPicture.asset(
                  'assets/images/logo.svg',
                  width: 80,
                  height: 110,
                ),
                const SizedBox(height: 18),
                // App Title SVG
                SvgPicture.asset(
                  'assets/images/title.svg',
                  width: 244,
                ),
                const SizedBox(height: 8),
                Text(
                  'BigQuery on the Go',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
                const Spacer(flex: 2),
                // Adaptive Get Started / Google Login Button
                isLinux
                    ? ElevatedButton.icon(
                        onPressed: authService.isLoading
                            ? null
                            : () async {
                                await authService.signIn();
                              },
                        icon: const Icon(Icons.rocket_launch_outlined, size: 20),
                        label: const Text(
                          'Get Started',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF536DFE),
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shadowColor: Colors.black26,
                          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 32.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      )
                    : ElevatedButton(
                        onPressed: authService.isLoading
                            ? null
                            : () async {
                                final success = await authService.signIn();
                                if (!success && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Google Sign-in failed. Please try again.'),
                                    ),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          elevation: 2,
                          shadowColor: Colors.black26,
                          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey[300]!),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Google Logo asset helper
                            Image.network(
                              'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/1024px-Google_%22G%22_logo.svg.png',
                              height: 24,
                              width: 24,
                              errorBuilder: (_, __, ___) => const Icon(Icons.login, size: 24),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Sign in with Google',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                const Spacer(flex: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }


}
