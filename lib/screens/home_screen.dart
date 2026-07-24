import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';
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
  
  final ScrollController _resultsScrollController = ScrollController();
  EditorLayoutState _layoutState = EditorLayoutState.split;
  Timer? _debounceTimer;
  String? _currentQueryName;

  @override
  void initState() {
    super.initState();
    _queryController = SqlEditorController()
      ..text = "SELECT Name, Employees FROM Accounts WHERE Size = 'Large' LIMIT 1000";
    _queryController.addListener(_onQueryChanged);
  }

  void _scrollToTop() {
    if (_resultsScrollController.hasClients) {
      _resultsScrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
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
    _resultsScrollController.dispose();
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
    if (query.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter a SQL query first."),
        ),
      );
      return;
    }

    final parsedRef = SqlEditorController.parseTableReference(query);
    final datasetId = parsedRef?['datasetId'];
    final tableId = parsedRef?['tableId'];

    context.read<BigQueryService>().runQuickCount(
          query,
          datasetId: datasetId,
          tableId: tableId,
        );
  }

  void _toggleLimit100(bool enable) {
    String text = _queryController.text;
    final limitRegex = RegExp(r'\s+LIMIT\s+\d+\b', caseSensitive: false);

    if (enable) {
      if (limitRegex.hasMatch(text)) {
        text = text.replaceAll(limitRegex, ' LIMIT 100');
      } else {
        text = '$text LIMIT 100';
      }
    } else {
      text = text.replaceAll(limitRegex, '');
    }

    setState(() {
      _queryController.text = text;
    });
  }

  void _showSaveQueryDialog(BuildContext context, BigQueryService bq) {
    final nameController = TextEditingController(
      text: (_currentQueryName != null && _currentQueryName != 'Untitled Query')
          ? _currentQueryName
          : 'Saved Query 1',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Query to BigQuery'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter a name for this saved query:'),
            const SizedBox(height: 8),
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'e.g. high_value_accounts',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final queryName = nameController.text.trim();
              if (queryName.isNotEmpty) {
                final sql = _queryController.text;
                await bq.saveProjectQuery(sql);
                setState(() {
                  _currentQueryName = queryName;
                });
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Query '$queryName' saved successfully!")),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDownloadFormatDialog(BuildContext context, BigQueryService bq) {
    final columns = bq.resultColumns;
    final rows = bq.resultRows;

    if (columns.isEmpty || rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No query results available to download."),
        ),
      );
      return;
    }

    String selectedFormat = 'CSV';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.file_download_outlined, color: Color(0xFF536DFE)),
                  SizedBox(width: 8),
                  Text('Download Results'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Exporting ${rows.length} rows (${columns.length} columns):',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 12),
                    RadioListTile<String>(
                      dense: true,
                      title: const Text('CSV (Comma Separated)'),
                      subtitle: const Text('Standard spreadsheet CSV format'),
                      value: 'CSV',
                      groupValue: selectedFormat,
                      onChanged: (val) => setDialogState(() => selectedFormat = val!),
                    ),
                    RadioListTile<String>(
                      dense: true,
                      title: const Text('JSON (Formatted Array)'),
                      subtitle: const Text('Array of JSON objects'),
                      value: 'JSON',
                      groupValue: selectedFormat,
                      onChanged: (val) => setDialogState(() => selectedFormat = val!),
                    ),
                    RadioListTile<String>(
                      dense: true,
                      title: const Text('JSONL (Newline Delimited JSON)'),
                      subtitle: const Text('BigQuery standard JSONL format'),
                      value: 'JSONL',
                      groupValue: selectedFormat,
                      onChanged: (val) => setDialogState(() => selectedFormat = val!),
                    ),
                    RadioListTile<String>(
                      dense: true,
                      title: const Text('TSV (Tab Separated)'),
                      subtitle: const Text('Tab-delimited text data'),
                      value: 'TSV',
                      groupValue: selectedFormat,
                      onChanged: (val) => setDialogState(() => selectedFormat = val!),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save_alt, size: 18),
                  label: const Text('Save File'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF536DFE),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    String exportContent = '';
                    if (selectedFormat == 'CSV') {
                      final header = columns.join(',');
                      final dataRows = rows.map((r) => columns.map((c) => '"${(r[c] ?? '').replaceAll('"', '""')}"').join(','));
                      exportContent = '$header\n${dataRows.join('\n')}';
                    } else if (selectedFormat == 'JSON') {
                      exportContent = const JsonEncoder.withIndent('  ').convert(rows);
                    } else if (selectedFormat == 'JSONL') {
                      exportContent = rows.map((r) => jsonEncode(r)).join('\n');
                    } else if (selectedFormat == 'TSV') {
                      final header = columns.join('\t');
                      final dataRows = rows.map((r) => columns.map((c) => r[c] ?? '').join('\t'));
                      exportContent = '$header\n${dataRows.join('\n')}';
                    }

                    final ext = selectedFormat.toLowerCase();
                    final defaultFileName = 'query_results.$ext';
                    final bytes = Uint8List.fromList(utf8.encode(exportContent));
                    
                    String? outputPath;
                    try {
                      outputPath = await FilePicker.platform.saveFile(
                        dialogTitle: 'Select location to save results',
                        fileName: defaultFileName,
                        type: FileType.custom,
                        allowedExtensions: [ext],
                        bytes: bytes,
                      );
                    } catch (e) {
                      debugPrint("FilePicker saveFile error: $e");
                    }

                    bool savedSuccessfully = false;
                    if (outputPath != null && outputPath.isNotEmpty) {
                      try {
                        final file = File(outputPath);
                        await file.writeAsBytes(bytes, flush: true);
                        if (file.existsSync() && file.lengthSync() > 0) {
                          savedSuccessfully = true;
                        }
                      } catch (e) {
                        debugPrint("Direct File write exception for $outputPath: $e");
                      }
                    }

                    // Fallback to Documents/Downloads directory if direct save path failed or was 0 bytes
                    if (!savedSuccessfully) {
                      Directory? targetDir;
                      try {
                        targetDir = await getDownloadsDirectory();
                      } catch (_) {}
                      targetDir ??= await getApplicationDocumentsDirectory();

                      final fallbackPath = '${targetDir.path}/$defaultFileName';
                      final fallbackFile = File(fallbackPath);
                      await fallbackFile.writeAsBytes(bytes, flush: true);
                      outputPath = fallbackPath;
                      savedSuccessfully = true;
                    }

                    // Also copy to clipboard as instant backup
                    await Clipboard.setData(ClipboardData(text: exportContent));

                    if (context.mounted) {
                      Navigator.pop(ctx);
                      final savedFile = File(outputPath!);
                      final fileSize = savedFile.existsSync() ? savedFile.lengthSync() : bytes.length;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Saved ${rows.length} rows ($fileSize bytes) to:\n$outputPath"),
                          duration: const Duration(seconds: 5),
                        ),
                      );
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
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
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        flexibleSpace: GestureDetector(
          onDoubleTap: _scrollToTop,
          behavior: HitTestBehavior.translucent,
          child: const SizedBox.expand(),
        ),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: GestureDetector(
          onDoubleTap: _scrollToTop,
          behavior: HitTestBehavior.opaque,
          child: const SizedBox(
            width: double.infinity,
            child: Text('Pocket Query'),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.vertical_align_top_rounded),
            tooltip: 'Scroll Results to Top',
            onPressed: _scrollToTop,
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Download Query Results',
            onPressed: () => _showDownloadFormatDialog(context, bigQueryService),
          ),
          IconButton(
            icon: const Icon(Icons.account_tree_outlined),
            tooltip: 'Browse Schema',
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
      ),
      drawer: SideMenu(
        onQuerySelected: (q, {name}) {
          setState(() {
            _queryController.text = q;
            _currentQueryName = name ?? 'Untitled Query';
          });
        },
      ),
      endDrawer: SchemaBrowser(
        onFieldSelected: _insertField,
        activeQuery: _queryController.text,
      ),
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
              // Results Panel at top
              Expanded(
                child: SizedBox(
                  height: resultsHeight,
                  child: _buildResultsPanel(isDark, bigQueryService),
                ),
              ),
              // Layout Divider / Controller Bar just above editor
              _buildStatusBar(bigQueryService),
              // Editor Panel at bottom
              SizedBox(
                height: editorHeight,
                child: _buildEditorPanel(isDark, bigQueryService),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEditorPanel(bool isDark, BigQueryService bq) {
    final isExecuting = bq.isExecuting;

    final isLimit100 = RegExp(r'\bLIMIT\s+100\b', caseSensitive: false)
        .hasMatch(_queryController.text);

    return Container(
      color: const Color(0xFF2F3237),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Code Box (edge-to-edge dark pane with inset padding)
          Expanded(
            child: Container(
              color: const Color(0xFF2F3237),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  style: GoogleFonts.anonymousPro(
                    fontSize: 18,
                    color: Colors.white,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: 'Enter your SQL query here...',
                    hintStyle: GoogleFonts.anonymousPro(
                      fontSize: 18,
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Bottom Accessory / Action Bar (positioned at bottom / above soft keyboard)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF24272C),
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left Aligned Buttons (Save & Navigator Tray)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _showSaveQueryDialog(context, bq),
                      icon: const Icon(Icons.save_outlined, size: 16),
                      label: const Text('Save', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                      icon: const Icon(Icons.account_tree_outlined, size: 20),
                      tooltip: 'Open Datasets & Tables Tray',
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                // Right Aligned Buttons (Limit 100 & Run drop-up)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilterChip(
                      label: const Text('Limit 100', style: TextStyle(fontSize: 12)),
                      selected: isLimit100,
                      onSelected: (selected) {
                        _toggleLimit100(selected);
                      },
                      selectedColor: const Color(0xFF536DFE).withOpacity(0.2),
                      checkmarkColor: const Color(0xFF536DFE),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 8),
                    _buildRunDropUpButton(isExecuting),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(BigQueryService bq) {
    final title = (_currentQueryName != null && _currentQueryName!.isNotEmpty)
        ? _currentQueryName!
        : 'Untitled Query';

    return GestureDetector(
      onDoubleTap: _scrollToTop,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 36,
        color: const Color(0xFF536DFE),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.arrow_upward, color: Colors.white, size: 16),
                tooltip: 'Maximise Editor',
                onPressed: () {
                  setState(() {
                    _layoutState = _layoutState == EditorLayoutState.maximised
                        ? EditorLayoutState.split
                        : EditorLayoutState.maximised;
                  });
                },
              ),
              const SizedBox(width: 16),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.arrow_downward, color: Colors.white, size: 16),
                tooltip: 'Minimise Editor',
                onPressed: () {
                  setState(() {
                    _layoutState = _layoutState == EditorLayoutState.minimised
                        ? EditorLayoutState.split
                        : EditorLayoutState.minimised;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    ),
  );
  }

  Widget _buildRunDropUpButton(bool isExecuting) {
    if (isExecuting) {
      return ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF536DFE),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 6),
            Text('Running...', style: TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      );
    }

    return PopupMenuButton<String>(
      tooltip: 'Run Options',
      offset: const Offset(0, -105),
      onSelected: (value) {
        if (value == 'run') {
          _runQuery();
        } else if (value == 'quick_count') {
          _runQuickCount();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          value: 'run',
          child: Row(
            children: [
              Icon(Icons.play_arrow, color: Color(0xFF536DFE), size: 18),
              SizedBox(width: 8),
              Text('Run Query'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'quick_count',
          child: Row(
            children: [
              Icon(Icons.flash_on, color: Colors.orangeAccent, size: 18),
              SizedBox(width: 8),
              Text('Run Quick Count'),
            ],
          ),
        ),
      ],
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF536DFE),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_arrow, size: 18, color: Colors.white),
            SizedBox(width: 4),
            Text('Run', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            SizedBox(width: 2),
            Icon(Icons.arrow_drop_up, size: 18, color: Colors.white),
          ],
        ),
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
      final countColor = isDark ? Colors.white : const Color(0xFF2F3237);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Results',
              style: GoogleFonts.roboto(
                fontSize: 38,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF536DFF),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              bq.quickCountResult!,
              style: GoogleFonts.anonymousPro(
                fontSize: 56,
                fontWeight: FontWeight.normal,
                color: countColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'rows matching query',
              style: GoogleFonts.roboto(
                fontSize: 14,
                color: const Color(0xFF7F8286),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Quick Count Result (0 Bytes Scanned)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
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

    final tableWidth = columns.length * 160.0 > 360.0 ? columns.length * 160.0 : 360.0;

    return GestureDetector(
      onDoubleTap: _scrollToTop,
      behavior: HitTestBehavior.opaque,
      child: NotificationListener<ScrollNotification>(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                // Sticky Header Row (Double-tap or tap header row to scroll to top)
                GestureDetector(
                  onTap: _scrollToTop,
                  onDoubleTap: _scrollToTop,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    color: isDark ? const Color(0xFF1E2024) : Colors.grey[200],
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                    child: Row(
                      children: columns.map((col) => Expanded(
                        child: Text(
                          col,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      )).toList(),
                    ),
                  ),
                ),
                const Divider(height: 1, thickness: 1),
                // Virtualized List View (Renders only items visible on screen)
                Expanded(
                  child: ListView.builder(
                    controller: _resultsScrollController,
                    itemCount: rows.length,
                    itemExtent: 44.0,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final isEven = index % 2 == 0;
                      return Container(
                        height: 44.0,
                        color: isEven
                            ? (isDark ? Colors.transparent : Colors.white)
                            : (isDark ? Colors.white.withOpacity(0.04) : Colors.grey[100]),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: columns.map((col) => Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                row[col] ?? '',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                            ),
                          )).toList(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
