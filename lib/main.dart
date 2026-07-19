import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:pocket_query/services/auth_service.dart';
import 'package:pocket_query/services/bigquery_service.dart';
import 'package:pocket_query/services/logger_service.dart';
import 'package:pocket_query/screens/splash_screen.dart';
import 'package:pocket_query/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LoggerService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProxyProvider<AuthService, BigQueryService>(
          create: (context) => BigQueryService(context.read<AuthService>()),
          update: (context, auth, previous) {
            if (previous == null) {
              return BigQueryService(auth);
            }
            previous.updateAuth(auth);
            return previous;
          },
        ),
      ],
      child: const PocketQueryApp(),
    ),
  );
}

class PocketQueryApp extends StatelessWidget {
  const PocketQueryApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryAccent = Color(0xFF536DFF);
    
    return MaterialApp(
      title: 'Pocket Query',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        textTheme: GoogleFonts.robotoTextTheme(ThemeData.light().textTheme),
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryAccent,
          primary: primaryAccent,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.white,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        textTheme: GoogleFonts.robotoTextTheme(ThemeData.dark().textTheme),
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryAccent,
          primary: primaryAccent,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      themeMode: ThemeMode.system,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();

    if (authService.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (authService.isAuthenticated) {
      return const HomeScreen();
    }

    return const SplashScreen();
  }
}
