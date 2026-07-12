import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis/bigquery/v2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pocket_query/services/auth_service.dart';

class BigQueryService extends ChangeNotifier {
  final AuthService _authService;
  final _storage = const FlutterSecureStorage();
  BigqueryApi? _api;
  
  List<String> _personalQueries = [];
  
  String? _selectedProjectId;
  List<String> _projects = [];
  bool _isLoadingProjects = false;
  
  // Schema states
  List<String> _datasets = [];
  Map<String, List<String>> _datasetTables = {}; // datasetId -> list of tableIds
  Map<String, List<Map<String, String>>> _tableFields = {}; // "datasetId.tableId" -> fields
  bool _isLoadingSchema = false;
  
  // Execution states
  bool _isExecuting = false;
  List<String> _resultColumns = [];
  List<Map<String, String>> _resultRows = [];
  String? _queryError;
  
  // Cost estimation (dry run)
  int? _estimatedBytesScanned;
  String? _estimationError;
  
  // Quick count metadata-only result
  String? _quickCountResult;

  BigQueryService(this._authService) {
    _initializeService();
    _loadPersonalQueries();
  }

  /// Reacts to changes in AuthService (login, logout)
  void updateAuth(AuthService authService) {
    _initializeService();
  }

  Future<void> _initializeService() async {
    if (!_authService.isAuthenticated) {
      _resetState();
      return;
    }
    
    // In mock testing, auth servicecurrentUser displayName is 'Test User'
    if (_authService.currentUser?.displayName == 'Test User') {
      _loadMockData();
      return;
    }

    _isLoadingProjects = true;
    notifyListeners();

    try {
      final client = await _authService.getAuthenticatedClient();
      if (client != null) {
        _api = BigqueryApi(client);
        await fetchProjects();
      }
    } catch (e) {
      debugPrint("Failed to initialize BigQuery client: $e");
    } finally {
      _isLoadingProjects = false;
      notifyListeners();
    }
  }

  void _resetState() {
    _api = null;
    _selectedProjectId = null;
    _projects = [];
    _datasets = [];
    _datasetTables = {};
    _tableFields = {};
    _resultColumns = [];
    _resultRows = [];
    _queryError = null;
    _estimatedBytesScanned = null;
    _estimationError = null;
    _quickCountResult = null;
    notifyListeners();
  }

  void _loadMockData() {
    _projects = ['mock-gcp-project-1', 'mock-gcp-project-2'];
    _selectedProjectId = _selectedProjectId ?? _projects.first;
    _datasets = ['analytics_dataset', 'ecommerce_dataset'];
    _datasetTables = {
      'analytics_dataset': ['user_events', 'daily_active_users'],
      'ecommerce_dataset': ['transactions', 'products', 'customers'],
    };
    _tableFields = {
      'analytics_dataset.user_events': [
        {'name': 'event_id', 'type': 'STRING'},
        {'name': 'event_timestamp', 'type': 'TIMESTAMP'},
        {'name': 'user_id', 'type': 'STRING'},
        {'name': 'event_name', 'type': 'STRING'},
      ],
      'ecommerce_dataset.transactions': [
        {'name': 'transaction_id', 'type': 'STRING'},
        {'name': 'user_id', 'type': 'STRING'},
        {'name': 'amount', 'type': 'FLOAT64'},
        {'name': 'date_str', 'type': 'STRING'},
        {'name': 'status', 'type': 'STRING'},
      ]
    };
    notifyListeners();
  }

  // Getters
  String? get selectedProjectId => _selectedProjectId;
  List<String> get projects => _projects;
  bool get isLoadingProjects => _isLoadingProjects;
  List<String> get personalQueries => _personalQueries;
  
  List<String> get datasets => _datasets;
  Map<String, List<String>> get datasetTables => _datasetTables;
  Map<String, List<Map<String, String>>> get tableFields => _tableFields;
  bool get isLoadingSchema => _isLoadingSchema;
  
  bool get isExecuting => _isExecuting;
  List<String> get resultColumns => _resultColumns;
  List<Map<String, String>> get resultRows => _resultRows;
  String? get queryError => _queryError;
  
  int? get estimatedBytesScanned => _estimatedBytesScanned;
  String? get estimationError => _estimationError;
  String? get quickCountResult => _quickCountResult;

  /// Fetches GCP project list
  Future<void> fetchProjects() async {
    if (_api == null) return;
    try {
      final response = await _api!.projects.list();
      _projects = response.projects?.map((p) => p.id!).toList() ?? [];
      if (_projects.isNotEmpty && _selectedProjectId == null) {
        await selectProject(_projects.first);
      }
    } catch (e) {
      debugPrint("Failed to fetch projects: $e");
    } finally {
      notifyListeners();
    }
  }

  /// Sets selected project and fetches its dataset schemas
  Future<void> selectProject(String projectId) async {
    _selectedProjectId = projectId;
    _datasets = [];
    _datasetTables = {};
    _tableFields = {};
    notifyListeners();
    await fetchDatasetsAndTables();
  }

  /// Fetches datasets and their underlying tables
  Future<void> fetchDatasetsAndTables() async {
    if (_authService.currentUser?.displayName == 'Test User') {
      _loadMockData();
      return;
    }
    if (_api == null || _selectedProjectId == null) return;
    
    _isLoadingSchema = true;
    notifyListeners();

    try {
      final datasetList = await _api!.datasets.list(_selectedProjectId!);
      _datasets = datasetList.datasets?.map((d) => d.datasetReference!.datasetId!).toList() ?? [];

      for (final datasetId in _datasets) {
        final tableList = await _api!.tables.list(_selectedProjectId!, datasetId);
        _datasetTables[datasetId] = tableList.tables?.map((t) => t.tableReference!.tableId!).toList() ?? [];
      }
    } catch (e) {
      debugPrint("Failed to fetch schema: $e");
    } finally {
      _isLoadingSchema = false;
      notifyListeners();
    }
  }

  /// Lazily fetches and caches fields for a selected table
  Future<void> fetchTableSchema(String datasetId, String tableId) async {
    final cacheKey = "$datasetId.$tableId";
    if (_tableFields.containsKey(cacheKey) || _api == null || _selectedProjectId == null) return;

    try {
      final table = await _api!.tables.get(_selectedProjectId!, datasetId, tableId);
      final fields = table.schema?.fields?.map((f) => {
        'name': f.name ?? '',
        'type': f.type ?? '',
      }).toList() ?? [];
      
      _tableFields[cacheKey] = fields;
      notifyListeners();
    } catch (e) {
      debugPrint("Failed to fetch table fields for $cacheKey: $e");
    }
  }

  /// Estimates query bytes scanned using dryRun job insertion
  Future<void> estimateQueryCost(String query) async {
    if (query.trim().isEmpty) {
      _estimatedBytesScanned = null;
      _estimationError = null;
      notifyListeners();
      return;
    }

    if (_authService.currentUser?.displayName == 'Test User') {
      // Mock Cost Estimation: parse query length to return size
      _estimatedBytesScanned = query.length * 1024 * 1024;
      _estimationError = null;
      notifyListeners();
      return;
    }

    if (_api == null || _selectedProjectId == null) return;

    try {
      final job = Job(
        configuration: JobConfiguration(
          dryRun: true,
          query: JobConfigurationQuery(
            query: query,
            useLegacySql: false,
          ),
        ),
      );

      final result = await _api!.jobs.insert(job, _selectedProjectId!);
      final bytesStr = result.statistics?.query?.totalBytesProcessed;
      _estimatedBytesScanned = bytesStr != null ? int.tryParse(bytesStr) : null;
      _estimationError = null;
    } catch (e) {
      _estimatedBytesScanned = null;
      _estimationError = e.toString();
      debugPrint("Dry run cost estimation failed: $e");
    } finally {
      notifyListeners();
    }
  }

  /// Runs query job to fetch real rows and columns
  Future<void> runQuery(String query) async {
    if (query.trim().isEmpty || _selectedProjectId == null) return;

    _isExecuting = true;
    _queryError = null;
    _quickCountResult = null;
    notifyListeners();

    if (_authService.currentUser?.displayName == 'Test User') {
      await Future.delayed(const Duration(milliseconds: 400));
      _resultColumns = ['Row', 'Name', 'Employees', 'Earnings'];
      _resultRows = [
        {'Row': '1', 'Name': 'Apple, Inc.', 'Employees': '150,000', 'Earnings': '120.5B'},
        {'Row': '2', 'Name': 'Microsoft', 'Employees': '220,000', 'Earnings': '142.1B'},
        {'Row': '3', 'Name': 'Toshiba, Inc.', 'Employees': '100,000', 'Earnings': '21.3B'},
      ];
      _isExecuting = false;
      notifyListeners();
      await addPersonalQuery(query);
      return;
    }

    if (_api == null) return;

    try {
      final request = QueryRequest(
        query: query,
        useLegacySql: false,
      );

      final response = await _api!.jobs.query(request, _selectedProjectId!);
      
      _resultColumns = response.schema?.fields?.map((f) => f.name!).toList() ?? [];
      
      _resultRows = response.rows?.map((row) {
        final Map<String, String> rowMap = {};
        for (int i = 0; i < _resultColumns.length; i++) {
          final cellValue = row.f?[i].v;
          rowMap[_resultColumns[i]] = cellValue?.toString() ?? '';
        }
        return rowMap;
      }).toList() ?? [];

      _queryError = null;
      await addPersonalQuery(query);
    } catch (e) {
      _resultColumns = [];
      _resultRows = [];
      _queryError = e.toString().replaceFirst(RegExp(r'^DetailedApiRequestError\(.*?\): '), '');
      debugPrint("Query job failed: $e");
    } finally {
      _isExecuting = false;
      notifyListeners();
    }
  }

  /// Runs Quick Count: pulls metadata row count with 0 bytes scanned cost
  Future<void> runQuickCount(String datasetId, String tableId) async {
    _isExecuting = true;
    _quickCountResult = null;
    _queryError = null;
    notifyListeners();

    if (_authService.currentUser?.displayName == 'Test User') {
      await Future.delayed(const Duration(milliseconds: 300));
      _quickCountResult = "10,413";
      _isExecuting = false;
      notifyListeners();
      return;
    }

    if (_api == null || _selectedProjectId == null) return;

    try {
      final table = await _api!.tables.get(_selectedProjectId!, datasetId, tableId);
      final numRows = table.numRows; // total rows count string from BQ metadata
      if (numRows != null) {
        // Format with commas (e.g. 10413 -> 10,413)
        final parsed = int.tryParse(numRows);
        if (parsed != null) {
          _quickCountResult = parsed.toString().replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
            (Match m) => "${m[1]},",
          );
        } else {
          _quickCountResult = numRows;
        }
      } else {
        _quickCountResult = "0";
      }
      _queryError = null;
    } catch (e) {
      _quickCountResult = null;
      _queryError = e.toString();
      debugPrint("Quick count metadata fetch failed: $e");
    } finally {
      _isExecuting = false;
      notifyListeners();
    }
  }

  Future<void> _loadPersonalQueries() async {
    try {
      final raw = await _storage.read(key: 'personal_queries');
      if (raw != null) {
        _personalQueries = List<String>.from(json.decode(raw));
      } else {
        _personalQueries = [
          'large_accounts_queryname',
          'transactions_per_channel',
        ];
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Failed to load queries: $e");
    }
  }

  Future<void> _savePersonalQueries() async {
    try {
      await _storage.write(key: 'personal_queries', value: json.encode(_personalQueries));
    } catch (e) {
      debugPrint("Failed to save queries: $e");
    }
  }

  Future<void> addPersonalQuery(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    if (_personalQueries.contains(trimmed)) return;
    
    _personalQueries.insert(0, trimmed);
    if (_personalQueries.length > 10) {
      _personalQueries = _personalQueries.sublist(0, 10);
    }
    notifyListeners();
    await _savePersonalQueries();
  }
}
