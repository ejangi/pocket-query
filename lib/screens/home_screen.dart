import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:pocket_query/screens/side_menu.dart';
import 'package:pocket_query/screens/schema_browser.dart';
import 'package:pocket_query/widgets/sql_editor_controller.dart';
import 'package:pocket_query/widgets/autocomplete_overlay.dart';
import 'package:pocket_query/services/bigquery_service.dart';

enum EditorLayoutState {
  minimised,
  split,
  maximised,
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final SqlEditorController _queryController;
  final FocusNode _editorFocusNode = FocusNode();
  
  EditorLayoutState _layoutState = EditorLayoutState.split;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _queryController = SqlEditorController()
      ..text = "SELECT Name, Employees FROM Accounts WHERE Size = 'Large' LIMIT 1000";
    _queryController.addListener(_onQueryChanged);
  }

  void _onQueryChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        context.read<BigQueryService>().estimateQueryCost(_queryController.text);
      }
    });
  }

  @override
  void dispose() {
    _queryController.removeListener(_onQueryChanged);
    _queryController.dispose();
    _editorFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _insertField(String fieldName) {
    final text = _queryController.text;
    final selection = _queryController.selection;
    
    if (selection.start >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, fieldName);
      _queryController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + fieldName.length),
      );
    } else {
      _queryController.text = "$text $fieldName";
    }
  }

  void _runQuery() {
    context.read<BigQueryService>().runQuery(_queryController.text);
  }

  void _runQuickCount() {
    final query = _queryController.text;
    final parsedRef = SqlEditorController.parseTableReference(query);
    
    if (parsedRef != null) {
      final datasetId = parsedRef['datasetId']!;
      final tableId = parsedRef['tableId']!;
      context.read<BigQueryService>().runQuickCount(datasetId, tableId);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not parse table name. Format: FROM dataset.table"),
        ),
      );
    }
  }

  String _formatCost(int? bytes) {
    if (bytes == null) return "Dry Run: --";
    
    double val = bytes.toDouble();
    List<String> units = ['B', 'KB', 'MB', 'GB', 'TB'];
    int unitIndex = 0;
    while (val >= 1024 && unitIndex < units.length - 1) {
      val /= 1024;
      unitIndex++;
    }
    
    double tb = bytes / (1024.0 * 1024.0 * 1024.0 * 1024.0);
    double cost = tb * 5.0; // BigQuery pricing: $5.00 per TB
    
    return "Dry Run: ${val.toStringAsFixed(1)} ${units[unitIndex]} (\$${cost.toStringAsFixed(4)})";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bigQueryService = context.watch<BigQueryService>();

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Pocket Query'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_tree_outlined),
            tooltip: 'Browse Schema',
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
      ),
      drawer: SideMenu(
        onQuerySelected: (q) {
          _queryController.text = q;
        },
      ),
      endDrawer: SchemaBrowser(onFieldSelected: _insertField),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final totalHeight = constraints.maxHeight;
          double editorHeight;
          double resultsHeight;

          switch (_layoutState) {
            case EditorLayoutState.minimised:
              editorHeight = totalHeight * 0.15;
              resultsHeight = totalHeight * 0.85;
              break;
            case EditorLayoutState.split:
              editorHeight = totalHeight * 0.45;
              resultsHeight = totalHeight * 0.55;
              break;
            case EditorLayoutState.maximised:
              editorHeight = totalHeight * 0.80;
              resultsHeight = totalHeight * 0.20;
              break;
          }

          return Column(
            children: [
              // Editor Panel
              SizedBox(
                height: editorHeight,
                child: _buildEditorPanel(isDark, bigQueryService),
              ),
              // Layout Divider / Controller Bar
              _buildDividerBar(),
              // Results Panel
              Expanded(
                child: SizedBox(
                  height: resultsHeight,
                  child: _buildResultsPanel(isDark, bigQueryService),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEditorPanel(bool isDark, BigQueryService bq) {
    final bytes = bq.estimatedBytesScanned;
    final hasError = bq.estimationError != null;
    final isExecuting = bq.isExecuting;

    Widget badgeContent;
    if (hasError) {
      badgeContent = const Text(
        'SQL Error',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.redAccent,
        ),
      );
    } else {
      badgeContent = Text(
        _formatCost(bytes),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.blue[300] : const Color(0xFF536DFE),
        ),
      );
    }

    return Container(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[100],
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Toolbar with Actions
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: isExecuting ? null : _runQuery,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Run'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF536DFE),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: isExecuting ? null : _runQuickCount,
                child: const Text('Quick Count'),
              ),
              const Spacer(),
              // Dry-run cost estimator badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (hasError ? Colors.redAccent : const Color(0xFF536DFE)).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: badgeContent,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Code Box
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F0F0F) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[isDark ? 800 : 300]!),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
                    final text = _queryController.text;
                    final selection = _queryController.selection;
                    const tabStr = "    "; // 4 spaces for SQL formatting
                    
                    if (selection.start >= 0) {
                      final newText = text.replaceRange(selection.start, selection.end, tabStr);
                      _queryController.value = TextEditingValue(
                        text: newText,
                        selection: TextSelection.collapsed(offset: selection.start + tabStr.length),
                      );
                    }
                    return KeyEventResult.handled; // Handled, stops focus traversal
                  }
                  return KeyEventResult.ignored;
                },
                child: SqlAutocompleteEditor(
                  controller: _queryController,
                  focusNode: _editorFocusNode,
                  maxLines: null,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Enter your SQL query here...',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDividerBar() {
    return Container(
      height: 36,
      color: const Color(0xFF536DFE),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'QUERY EDITOR STATUS',
            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
          ),
          Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.arrow_upward, color: Colors.white, size: 16),
                onPressed: () {
                  setState(() {
                    _layoutState = EditorLayoutState.maximised;
                  });
                },
              ),
              const SizedBox(width: 12),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.swap_vert, color: Colors.white, size: 16),
                onPressed: () {
                  setState(() {
                    _layoutState = EditorLayoutState.split;
                  });
                },
              ),
              const SizedBox(width: 12),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.arrow_downward, color: Colors.white, size: 16),
                onPressed: () {
                  setState(() {
                    _layoutState = EditorLayoutState.minimised;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultsPanel(bool isDark, BigQueryService bq) {
    if (bq.isExecuting) {
      return const Center(child: CircularProgressIndicator());
    }

    if (bq.queryError != null) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
              const SizedBox(height: 12),
              const Text("Query Execution Failed", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                bq.queryError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, fontFamily: 'monospace', fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (bq.quickCountResult != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Quick Count Result (0 Bytes Scanned)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green),
            ),
            const SizedBox(height: 8),
            Text(
              bq.quickCountResult!,
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: Color(0xFF536DFE),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'rows matching query',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final columns = bq.resultColumns;
    final rows = bq.resultRows;

    if (columns.isEmpty) {
      return const Center(
        child: Text(
          'Enter a query and tap Run to see results.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    if (rows.isEmpty) {
      return const Center(
        child: Text(
          'Query executed successfully but returned 0 rows.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: columns.map((c) => DataColumn(
            label: Text(
              c,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          )).toList(),
          rows: rows.map((row) => DataRow(
            cells: columns.map((col) => DataCell(
              Text(row[col] ?? ''),
            )).toList(),
          )).toList(),
        ),
      ),
    );
  }
}
