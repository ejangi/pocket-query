import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

class SqlEditorController extends TextEditingController {
  // Lists of keywords, functions, and types for regex parsing
  List<String> _keywords = [];
  List<String> _functions = [];
  List<String> _types = [];
  
  RegExp? _masterRegex;
  bool _isInitialized = false;

  // Fallback defaults in case asset loading is delayed
  static const List<String> fallbackKeywords = [
    "SELECT", "FROM", "WHERE", "GROUP BY", "HAVING", "ORDER BY", "LIMIT",
    "ASC", "DESC",
    "AND", "OR", "NOT", "IN", "LIKE", "BETWEEN", "IS", "NULL", "TRUE", "FALSE",
    "AS", "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "CROSS", "ON", "USING",
    "UNION", "ALL", "DISTINCT", "INTERSECT", "EXCEPT", "WITH", "CREATE", "REPLACE",
    "TABLE", "VIEW", "FUNCTION", "INSERT", "UPDATE", "DELETE", "MERGE", "CASE",
    "WHEN", "THEN", "ELSE", "END", "CAST", "SAFE_CAST", "OVER", "PARTITION BY",
    "ROWS", "UNBOUNDED", "PRECEDING", "FOLLOWING", "CURRENT", "ROW", "UNNEST",
    "QUALIFY", "SYSTEM_TIME", "FOR", "VALUES", "SET", "DEFAULT"
  ];

  static const List<String> fallbackTypes = [
    "INT64", "NUMERIC", "BIGNUMERIC", "FLOAT64", "BOOLEAN", "STRING", "BYTES",
    "DATE", "DATETIME", "TIME", "TIMESTAMP", "GEOGRAPHY", "JSON", "STRUCT",
    "ARRAY", "INTERVAL"
  ];

  static const List<String> fallbackFunctions = [
    "CONCAT", "SUBSTR", "LENGTH", "LOWER", "UPPER", "TRIM", "REPLACE",
    "REGEXP_CONTAINS", "REGEXP_EXTRACT", "REGEXP_REPLACE", "SPLIT", "FORMAT",
    "COUNT", "SUM", "AVG", "MIN", "MAX", "COUNTIF", "ROW_NUMBER", "RANK",
    "DENSE_RANK", "LAG", "LEAD", "DATE_ADD", "DATE_SUB", "DATE_DIFF",
    "DATETIME_ADD", "DATETIME_SUB", "DATETIME_DIFF", "GENERATE_ARRAY"
  ];

  SqlEditorController() {
    _initializeDefaultRegex();
    _loadSpecAsset();
  }

  void _initializeDefaultRegex() {
    _keywords = List.from(fallbackKeywords);
    _types = List.from(fallbackTypes);
    _functions = List.from(fallbackFunctions);
    _buildRegex();
  }

  /// Asynchronously load the scraped BigQuery syntax rules from application assets
  Future<void> _loadSpecAsset() async {
    try {
      final jsonContent = await rootBundle.loadString('assets/metadata/bigquery_syntax.json');
      final data = json.decode(jsonContent);
      
      _keywords = List<String>.from(data['keywords'] ?? fallbackKeywords);
      _types = List<String>.from(data['types'] ?? fallbackTypes);
      _functions = List<String>.from(data['functions'] ?? fallbackFunctions);
      
      _buildRegex();
      _isInitialized = true;
      
      // Force trigger rebuild to reflect updated syntax highlighting
      notifyListeners();
    } catch (e) {
      debugPrint("Could not load bigquery_syntax.json asset: $e");
    }
  }

  void _buildRegex() {
    // Sort descending by length to prevent shorter keyword matches from preempting longer compound keywords (e.g. ORDER vs ORDER BY)
    final sortedKeywords = List<String>.from(_keywords)..sort((a, b) => b.length.compareTo(a.length));
    final sortedFunctions = List<String>.from(_functions)..sort((a, b) => b.length.compareTo(a.length));
    final sortedTypes = List<String>.from(_types)..sort((a, b) => b.length.compareTo(a.length));

    final keywordsPattern = sortedKeywords.map(RegExp.escape).join('|');
    final functionsPattern = sortedFunctions.map(RegExp.escape).join('|');
    final typesPattern = sortedTypes.map(RegExp.escape).join('|');

    // Create groups:
    // 1: Multi-line / single-line comments
    // 2: String literals (single & double quotes)
    // 3: Backticks (identifiers)
    // 4: Keywords
    // 5: Functions
    // 6: Data Types
    // 7: Numbers
    _masterRegex = RegExp(
      r'('
      r'(?:\/\*[\s\S]*?\*\/|--.*|#.*)' // Group 1: Comments
      r'|(?:\x27[^\x27\\]*(?:\\.[^\x27\\]*)*\x27|\x22[^\x22\\]*(?:\\.[^\x22\\]*)*\x22)' // Group 2: Strings
      r'|(`[^`\\]*(?:\\.[`\\]*)*`)' // Group 3: Backticks
      r'|\b(?:' + keywordsPattern + r')\b' // Group 4: Keywords
      r'|\b(?:' + functionsPattern + r')\b' // Group 5: Functions
      r'|\b(?:' + typesPattern + r')\b' // Group 6: Types
      r'|\b\d+(?:\.\d+)?\b' // Group 7: Numbers
      r')',
      caseSensitive: false,
      multiLine: true,
    );
  }

  // Define styling theme maps for light and dark modes
  Map<String, TextStyle> _getThemeStyles(bool isDark) {
    if (isDark) {
      return {
        'comment': TextStyle(color: Colors.grey[500], fontStyle: FontStyle.italic),
        'string': const TextStyle(color: Color(0xFF81C784)), // soft green
        'backtick': const TextStyle(color: Color(0xFF4DB6AC), fontWeight: FontWeight.w600), // teal
        'keyword': const TextStyle(color: Color(0xFF64B5F6), fontWeight: FontWeight.bold), // light blue
        'function': const TextStyle(color: Color(0xFFBA68C8), fontWeight: FontWeight.w600), // purple
        'type': const TextStyle(color: Color(0xFFFFB74D)), // orange
        'number': const TextStyle(color: Color(0xFFE0F2F1)), // soft white/cyan
      };
    } else {
      return {
        'comment': TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic),
        'string': const TextStyle(color: Color(0xFF2E7D32)), // forest green
        'backtick': const TextStyle(color: Color(0xFF00796B), fontWeight: FontWeight.w600), // dark teal
        'keyword': const TextStyle(color: Color(0xFF1A237E), fontWeight: FontWeight.bold), // indigo
        'function': const TextStyle(color: Color(0xFF7B1FA2), fontWeight: FontWeight.w600), // deep purple
        'type': const TextStyle(color: Color(0xFFE65100)), // deep orange
        'number': const TextStyle(color: Color(0xFF006064)), // dark cyan
      };
    }
  }

  /// Exposed getter for autocompletion dictionary lookup
  List<String> get autocompleteDictionary => [..._keywords, ..._functions, ..._types];

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (_masterRegex == null) {
      return TextSpan(text: text, style: style);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final styles = _getThemeStyles(isDark);
    final defaultStyle = style ?? const TextStyle(fontFamily: 'monospace');

    final List<TextSpan> spans = [];
    int lastMatchIndex = 0;

    _masterRegex!.allMatches(text).forEach((match) {
      // Add plain text before match
      if (match.start > lastMatchIndex) {
        spans.add(TextSpan(
          text: text.substring(lastMatchIndex, match.start),
          style: defaultStyle,
        ));
      }

      final matchedText = match.group(0)!;
      TextStyle matchStyle = defaultStyle;

      // Classify the match based on contents or characters
      if (matchedText.startsWith('--') || matchedText.startsWith('#') || matchedText.startsWith('/*')) {
        matchStyle = defaultStyle.merge(styles['comment']);
      } else if (matchedText.startsWith('\'') || matchedText.startsWith('"')) {
        matchStyle = defaultStyle.merge(styles['string']);
      } else if (matchedText.startsWith('`')) {
        matchStyle = defaultStyle.merge(styles['backtick']);
      } else {
        final upperText = matchedText.toUpperCase();
        if (_keywords.contains(upperText)) {
          matchStyle = defaultStyle.merge(styles['keyword']);
        } else if (_functions.contains(upperText)) {
          matchStyle = defaultStyle.merge(styles['function']);
        } else if (_types.contains(upperText)) {
          matchStyle = defaultStyle.merge(styles['type']);
        } else if (RegExp(r'^\d').hasMatch(matchedText)) {
          matchStyle = defaultStyle.merge(styles['number']);
        }
      }

      spans.add(TextSpan(
        text: matchedText,
        style: matchStyle,
      ));

      lastMatchIndex = match.end;
    });

    // Add trailing plain text
    if (lastMatchIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchIndex),
        style: defaultStyle,
      ));
    }

    return TextSpan(children: spans, style: defaultStyle);
  }

  /// Robust SQL parser helper to extract dataset ID and table ID from a query string.
  /// Handles backticks, project prefixes, comments, spacing, and multiple lines.
  static Map<String, String>? parseTableReference(String query) {
    // 1. Strip comments (both line -- / # and multi-line /* ... */)
    final cleanQuery = query.replaceAll(RegExp(r'\/\*[\s\S]*?\*\/|--.*|#.*'), ' ');

    // 2. Match FROM or JOIN clauses followed by optional spaces and backticks or letters
    final pathRegex = RegExp(
      r'\b(?:FROM|JOIN)\s+(?:`([^`]+)`|([a-zA-Z0-9_\-\.]+))',
      caseSensitive: false,
    );

    for (final match in pathRegex.allMatches(cleanQuery)) {
      final path = match.group(1) ?? match.group(2);
      if (path == null) continue;
      
      final parts = path.split('.');
      if (parts.length >= 2) {
        final tableId = parts.last.trim();
        final datasetId = parts[parts.length - 2].trim();
        
        return {
          'datasetId': datasetId.replaceAll('`', ''),
          'tableId': tableId.replaceAll('`', ''),
        };
      } else if (parts.isNotEmpty && parts.first.trim().isNotEmpty) {
        final tableId = parts.first.trim();
        return {
          'datasetId': 'default_dataset',
          'tableId': tableId.replaceAll('`', ''),
        };
      }
    }
    return null;
  }
}
