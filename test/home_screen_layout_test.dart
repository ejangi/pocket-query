import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pocket_query/screens/home_screen.dart';
import 'package:pocket_query/services/auth_service.dart';
import 'package:pocket_query/services/bigquery_service.dart';

void main() {
  late AuthService authService;
  late BigQueryService bigQueryService;

  setUp(() {
    authService = AuthService();
    bigQueryService = BigQueryService(authService);
  });

  Widget createHomeScreenWidget() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: authService),
        ChangeNotifierProvider<BigQueryService>.value(value: bigQueryService),
      ],
      child: const MaterialApp(
        home: HomeScreen(),
      ),
    );
  }

  testWidgets('HomeScreen layout displays Results at top, Status bar above Editor, and proper controls', (WidgetTester tester) async {
    await tester.pumpWidget(createHomeScreenWidget());
    await tester.pumpAndSettle();

    // Verify status bar text shows UNTITLED QUERY by default
    expect(find.text('UNTITLED QUERY'), findsOneWidget);

    // Verify swap_vert is NOT present
    expect(find.byIcon(Icons.swap_vert), findsNothing);

    // Verify arrow upward (Maximise) and arrow downward (Minimise) icons exist in status bar
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);

    // Verify Action Bar buttons exist
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Limit 100'), findsOneWidget);
    expect(find.text('Run'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_up), findsOneWidget);

    // Test Limit 100 toggle
    final limitChip = find.text('Limit 100');
    expect(limitChip, findsOneWidget);
    await tester.tap(limitChip);
    await tester.pumpAndSettle();

    // Test Run drop-up button opens popup menu with 'Run Query' and 'Run Quick Count'
    final runButton = find.text('Run');
    await tester.tap(runButton);
    await tester.pumpAndSettle();

    expect(find.text('Run Query'), findsOneWidget);
    expect(find.text('Run Quick Count'), findsOneWidget);
  });
}
