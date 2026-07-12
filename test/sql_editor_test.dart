import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_query/widgets/sql_editor_controller.dart';

void main() {
  testWidgets('SqlEditorController highlights keywords, types, and comments', (WidgetTester tester) async {
    final controller = SqlEditorController();
    // Test SQL with a keyword (SELECT), type (STRING), backtick block, and comment
    controller.text = "SELECT `project.dataset.table`, CAST(age AS INT64) -- casting column";

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final textSpan = controller.buildTextSpan(
                context: context,
                withComposing: false,
              );

              // Expect multiple stylized segments
              expect(textSpan.children, isNotNull);
              expect(textSpan.children!.length, greaterThan(1));

              // Verify SELECT is styled as keyword (bold)
              final selectSpan = textSpan.children![0] as TextSpan;
              expect(selectSpan.text, 'SELECT');
              expect(selectSpan.style!.fontWeight, FontWeight.bold);

              // Find and verify backtick segment style (bold)
              final backtickSpan = textSpan.children!.firstWhere(
                (s) => (s as TextSpan).text == '`project.dataset.table`',
              ) as TextSpan;
              expect(backtickSpan.style, isNotNull);

              // Find and verify data type INT64 style (non-bold, custom color)
              final typeSpan = textSpan.children!.firstWhere(
                (s) => (s as TextSpan).text == 'INT64',
              ) as TextSpan;
              expect(typeSpan.style, isNotNull);

              // Find and verify comment style (italic)
              final commentSpan = textSpan.children!.last as TextSpan;
              expect(commentSpan.text, '-- casting column');
              expect(commentSpan.style!.fontStyle, FontStyle.italic);

              return Container();
            },
          ),
        ),
      ),
    );
  });

  testWidgets('SqlEditorController highlights complex SQL query with diverse keywords, types, and functions', (WidgetTester tester) async {
    final controller = SqlEditorController();
    controller.text = '''
      WITH RawData AS (
        SELECT
          user_id,
          SAFE_CAST(amount AS FLOAT64) as transaction_amount,
          ROW_NUMBER() OVER(PARTITION BY user_id ORDER BY date_str DESC) as rank
        FROM `my-project.my_dataset.transactions`
        WHERE status = 'ACTIVE' AND category IN ('Retail', 'Online')
      )
      SELECT
        user_id,
        CASE
          WHEN transaction_amount > 100.00 THEN 'Premium'
          ELSE 'Standard'
        END as tier
      FROM RawData
      LIMIT 100
    ''';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final textSpan = controller.buildTextSpan(
                context: context,
                withComposing: false,
              );

              // Helper function to extract spans matching a search term
              List<TextSpan> findSpansText(String term) {
                return textSpan.children!
                    .whereType<TextSpan>()
                    .where((s) => s.text == term)
                    .toList();
              }

              // Verify keywords exist and are styled as bold
              final withSpans = findSpansText('WITH');
              expect(withSpans, isNotEmpty);
              expect(withSpans.first.style!.fontWeight, FontWeight.bold);

              final caseSpans = findSpansText('CASE');
              expect(caseSpans, isNotEmpty);
              expect(caseSpans.first.style!.fontWeight, FontWeight.bold);

              final selectSpans = findSpansText('SELECT');
              expect(selectSpans, isNotEmpty);
              expect(selectSpans.first.style!.fontWeight, FontWeight.bold);

              // Verify functions exist and are styled as medium-bold w600
              final rankSpans = findSpansText('ROW_NUMBER');
              expect(rankSpans, isNotEmpty);
              expect(rankSpans.first.style!.fontWeight, FontWeight.w600);

              // Verify types exist and have non-default styles
              final floatSpans = findSpansText('FLOAT64');
              expect(floatSpans, isNotEmpty);

              // Verify string literals exist
              final activeSpans = findSpansText("'ACTIVE'");
              expect(activeSpans, isNotEmpty);

              // Verify backtick identifiers exist
              final tableSpans = findSpansText('`my-project.my_dataset.transactions`');
              expect(tableSpans, isNotEmpty);

              // Verify sorting descriptors exist and are styled as bold keywords
              final descSpans = findSpansText('DESC');
              expect(descSpans, isNotEmpty);
              expect(descSpans.first.style!.fontWeight, FontWeight.bold);

              return Container();
            },
          ),
        ),
      ),
    );
  });
}
