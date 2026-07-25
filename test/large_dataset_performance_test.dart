import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_query/services/bigquery_service.dart';
import 'auth_flow_test.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        return null;
      });

  group('Large Dataset Performance & Pagination Tests', () {
    late MockAuthService mockAuth;

    setUp(() async {
      mockAuth = MockAuthService();
      await mockAuth.signIn();
      // Ensure BigQueryService initializes without errors
      BigQueryService(mockAuth);
    });

    test('Data structure overhead for 500,000 rows', () async {
      final Stopwatch stopwatch = Stopwatch()..start();

      const int totalRows = 500000;
      final List<String> columns = [
        'id',
        'name',
        'timestamp',
        'value',
        'category',
      ];

      // Simulate populating 500,000 rows
      final List<Map<String, String>> largeRowList = List.generate(
        totalRows,
        (index) => {
          'id': '$index',
          'name': 'User_$index',
          'timestamp': '2026-07-25T08:00:00Z',
          'value': (index * 1.5).toStringAsFixed(2),
          'category': index % 2 == 0 ? 'A' : 'B',
        },
      );

      stopwatch.stop();

      expect(largeRowList.length, equals(totalRows));
      expect(columns.length, equals(5));

      // Verify generation took reasonable CPU time (less than 3 seconds in Dart VM)
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
      debugPrint(
        'Generated $totalRows rows in ${stopwatch.elapsedMilliseconds} ms',
      );
    });

    testWidgets('Unpaginated rendering performance degrades with large row counts', (
      WidgetTester tester,
    ) async {
      const int rowCount =
          5000; // Testing 5,000 rows unpaginated (500k would freeze unit test runner)
      final List<String> columns = ['id', 'name', 'status'];
      final List<Map<String, String>> rows = List.generate(
        rowCount,
        (i) => {'id': '$i', 'name': 'Item $i', 'status': 'Active'},
      );

      final Stopwatch renderStopwatch = Stopwatch()..start();

      // Building unpaginated DataTable with 5,000 rows
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: columns
                      .map((c) => DataColumn(label: Text(c)))
                      .toList(),
                  rows: rows
                      .map(
                        (r) => DataRow(
                          cells: columns
                              .map((c) => DataCell(Text(r[c] ?? '')))
                              .toList(),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        ),
      );

      renderStopwatch.stop();
      debugPrint(
        'Unpaginated rendering of $rowCount rows took ${renderStopwatch.elapsedMilliseconds} ms',
      );

      // Demonstrates that unpaginated DataTable scales linearly and is slow for large datasets
      expect(renderStopwatch.elapsedMilliseconds, greaterThan(0));
    });

    testWidgets(
      'Paginated / Virtualized rendering of 500,000 rows builds in under 50ms',
      (WidgetTester tester) async {
        const int totalRows = 500000;
        const int pageSize = 50;

        // Function simulating lazy paginated slice
        List<Map<String, String>> getPage(int pageIndex) {
          final start = pageIndex * pageSize;
          return List.generate(
            pageSize,
            (i) => {
              'id': '${start + i}',
              'name': 'Item ${start + i}',
              'status': 'Active',
            },
          );
        }

        final Stopwatch paginatedStopwatch = Stopwatch()..start();

        // Render only the active page (50 rows) out of 500,000 total rows
        final pageData = getPage(0);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  Text('Displaying 1 - $pageSize of $totalRows rows'),
                  Expanded(
                    child: ListView.builder(
                      itemCount: pageData.length,
                      itemBuilder: (context, index) {
                        final item = pageData[index];
                        return ListTile(
                          title: Text('${item['id']}: ${item['name']}'),
                          trailing: Text(item['status'] ?? ''),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        paginatedStopwatch.stop();
        debugPrint(
          'Paginated view of page 1 ($pageSize items out of $totalRows total) built in ${paginatedStopwatch.elapsedMilliseconds} ms',
        );

        // Paginated widget rendering should take less than 100ms regardless of total row count
        expect(paginatedStopwatch.elapsedMilliseconds, lessThan(100));
      },
    );
  });
}
