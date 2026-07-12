import 'package:flutter/material.dart';
import 'package:pocket_query/screens/side_menu.dart';
import 'package:pocket_query/screens/schema_browser.dart';

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
  final TextEditingController _queryController = TextEditingController(
    text: "SELECT Name, Employees FROM Accounts WHERE Size = 'Large' LIMIT 1000",
  );
  
  EditorLayoutState _layoutState = EditorLayoutState.split;
  String? _selectedText;
  String? _quickCountResult;
  bool _isRunning = false;

  // Mock Result Data matching Figma specs
  final List<String> _columns = ['Row', 'Name', 'Employees', 'Earnings'];
  final List<Map<String, String>> _rows = [
    {'Row': '1', 'Name': 'Apple, Inc.', 'Employees': '150,000', 'Earnings': '120.5B'},
    {'Row': '2', 'Name': 'Microsoft', 'Employees': '220,000', 'Earnings': '142.1B'},
    {'Row': '3', 'Name': 'Toshiba, Inc.', 'Employees': '100,000', 'Earnings': '21.3B'},
  ];

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
    setState(() {
      _isRunning = true;
      _quickCountResult = null;
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    });
  }

  void _runQuickCount() {
    setState(() {
      _isRunning = true;
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _isRunning = false;
          _quickCountResult = "10,413"; // Mock count from Figma
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
      drawer: const SideMenu(),
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
                child: _buildEditorPanel(isDark),
              ),
              // Layout Divider / Controller Bar
              _buildDividerBar(),
              // Results Panel
              Expanded(
                child: SizedBox(
                  height: resultsHeight,
                  child: _buildResultsPanel(isDark),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEditorPanel(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[100],
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Toolbar with Actions
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _isRunning ? null : _runQuery,
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
                onPressed: _isRunning ? null : _runQuickCount,
                child: const Text('Quick Count'),
              ),
              const Spacer(),
              // Dry-run cost estimator badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF536DFE).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Dry Run: 2.4 MB (\$0.00)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF536DFE),
                  ),
                ),
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
              child: TextField(
                controller: _queryController,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 14,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Enter your SQL query here...',
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

  Widget _buildResultsPanel(bool isDark) {
    if (_isRunning) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_quickCountResult != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Quick Count Result',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _quickCountResult!,
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

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: _columns.map((c) => DataColumn(
            label: Text(
              c,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          )).toList(),
          rows: _rows.map((row) => DataRow(
            cells: _columns.map((col) => DataCell(
              Text(row[col] ?? ''),
            )).toList(),
          )).toList(),
        ),
      ),
    );
  }
}
