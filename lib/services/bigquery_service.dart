import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis/bigquery/v2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pocket_query/services/auth_service.dart';
import 'package:pocket_query/services/logger_service.dart';

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
  
  // Project Queries & Jobs state
  List<String> _projectQueries = [];
  List<String> _recentQueries = [];
  final Map<String, String> _dataformRepoPaths = {};
  bool _isLoadingProjectQueries = false;
  
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

  // GCP Projects error guidance state
  String? _projectsError;

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

    // In unit testing and desktop mock mode, currentUser displayName is 'Test User'
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
      } else {
        _loadMockData();
      }
    } catch (e) {
      debugPrint("Failed to initialize BigQuery client: $e");
      if (_projects.isEmpty) {
        _loadMockData();
      }
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
    _projectsError = null;
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
  String? get projectsError => _projectsError;
  List<String> get personalQueries => _personalQueries;
  
  List<String> get projectQueries => _projectQueries;
  List<String> get recentQueries => _recentQueries;
  bool get isLoadingProjectQueries => _isLoadingProjectQueries;
  
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

  /// Performs a full refresh of GCP projects, datasets, tables, saved queries, and recent query history
  Future<void> refreshAll() async {
    await LoggerService.log("User triggered full refresh (Projects, Schemas, Saved Queries, and Recent Query History)");
    await fetchProjects();
    if (_selectedProjectId != null) {
      await Future.wait([
        fetchDatasetsAndTables().then((_) => fetchCloudSavedQueries()),
        loadProjectSavedQueries(),
        fetchRecentQueries(),
        _loadPersonalQueries(),
      ]);
    }
  }

  /// Fetches GCP project list via BigQuery REST API (GET /bigquery/v2/projects)
  Future<void> fetchProjects() async {
    _isLoadingProjects = true;
    _projectsError = null;
    notifyListeners();
    await LoggerService.log("Executing fetchProjects() via BigQuery REST API (GET /bigquery/v2/projects)");
    try {
      if (_api != null) {
        final response = await _api!.projects.list();
        final List<String> projectList = response.projects?.map((p) => p.projectReference?.projectId ?? p.id!).toList() ?? <String>[];
        _projects = projectList;
        await LoggerService.log("GCP API returned ${projectList.length} projects: $projectList");
        if (_projects.isNotEmpty) {
          if (_selectedProjectId == null || !_projects.contains(_selectedProjectId)) {
            await selectProject(_projects.first);
          }
        } else {
          _selectedProjectId = null;
          _projectsError = "No Google Cloud projects found for this account.";
          await LoggerService.log("GCP API returned 0 projects for account.", level: "WARNING");
        }
      } else {
        _projects = [];
        _selectedProjectId = null;
        if (_authService.lastAuthError != null) {
          _projectsError = "OAuth token unavailable because Google Sign-In failed:\n${_authService.lastAuthError}\n\nRegister SHA-1 fingerprint in GCP Console to obtain a real OAuth access token.";
        } else {
          _projectsError = "Google Cloud API client is not initialized (no active OAuth access token).";
        }
        await LoggerService.log("Cannot call GCP projects.list(): BigQuery API client is null (no valid OAuth token). Last Auth Error: ${_authService.lastAuthError}", level: "WARNING");
      }
    } catch (e, stack) {
      _projects = [];
      _selectedProjectId = null;
      _projectsError = e.toString().replaceFirst(RegExp(r'^DetailedApiRequestError\(.*?\): '), '');
      await LoggerService.log("GCP projects.list() API call failed with exception", level: "ERROR", error: e, stackTrace: stack);
    } finally {
      _isLoadingProjects = false;
      notifyListeners();
    }
  }

  /// Adds a custom project ID entered manually by the user
  Future<void> addCustomProject(String projectId) async {
    final trimmed = projectId.trim();
    if (trimmed.isEmpty) return;
    
    // Clear demo mock projects if present
    _projects.removeWhere((p) => p.startsWith('mock-gcp-project-'));
    
    if (!_projects.contains(trimmed)) {
      _projects.add(trimmed);
    }
    await selectProject(trimmed);
  }

  /// Sets selected project and fetches its dataset schemas, saved queries, and recent query history
  Future<void> selectProject(String projectId) async {
    _selectedProjectId = projectId;
    _datasets = [];
    _datasetTables = {};
    _tableFields = {};
    _projectQueries = [];
    _recentQueries = [];
    notifyListeners();

    await LoggerService.log("Selected GCP Project: $projectId. Fetching datasets, saved queries, and recent query history...");
    await Future.wait([
      fetchDatasetsAndTables().then((_) => fetchCloudSavedQueries()),
      loadProjectSavedQueries(),
      fetchRecentQueries(),
    ]);
  }

  /// Scans GCP BigQuery for cloud-saved queries (Saved Views, Routines, and Dataform Repository assets)
  Future<void> fetchCloudSavedQueries() async {
    if (_api == null || _selectedProjectId == null) return;

    await LoggerService.log("Scanning GCP for Cloud Saved Queries (Views, Routines, Dataform) in project: $_selectedProjectId");

    final List<String> discoveredCloudQueries = [];

    // 1. Scan BigQuery Datasets for Saved Views (View SQL definitions)
    try {
      for (final datasetId in _datasets) {
        final tablesList = await _api!.tables.list(_selectedProjectId!, datasetId);
        if (tablesList.tables != null) {
          for (final t in tablesList.tables!) {
            if (t.type == 'VIEW') {
              try {
                final fullTable = await _api!.tables.get(_selectedProjectId!, datasetId, t.tableReference!.tableId!);
                final viewQuery = fullTable.view?.query;
                final viewName = t.tableReference!.tableId!;
                if (viewQuery != null && viewQuery.isNotEmpty) {
                  discoveredCloudQueries.add(viewQuery);
                  await LoggerService.log("Discovered BigQuery Saved View query: $viewName");
                }
              } catch (ve) {
                debugPrint("Failed to fetch view details for ${t.tableReference?.tableId}: $ve");
              }
            }
          }
        }

        // 2. Scan BigQuery Routines / Procedures
        try {
          final routinesList = await _api!.routines.list(_selectedProjectId!, datasetId);
          if (routinesList.routines != null) {
            for (final r in routinesList.routines!) {
              final routineId = r.routineReference?.routineId ?? 'routine';
              final body = r.definitionBody;
              if (body != null && body.isNotEmpty) {
                discoveredCloudQueries.add(body);
                await LoggerService.log("Discovered BigQuery Routine: $routineId");
              }
            }
          }
        } catch (re) {
          debugPrint("No routines found in dataset $datasetId: $re");
        }
      }
    } catch (e, stack) {
      await LoggerService.log("Error scanning BigQuery datasets for saved views/routines", level: "WARNING", error: e, stackTrace: stack);
    }

    // 3. Scan Dataform API (Modern BigQuery Studio Saved Queries)
    try {
      final client = await _authService.getAuthenticatedClient();
      if (client != null) {
        final url = Uri.parse("https://dataform.googleapis.com/v1beta1/projects/$_selectedProjectId/locations/-/repositories");
        final resp = await client.get(url);
        await LoggerService.log("Dataform Repositories API response (${resp.statusCode}): ${resp.body}");
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body);
          final repos = data['repositories'] as List<dynamic>?;
          if (repos != null) {
            for (final repo in repos) {
              final displayName = repo['displayName'] as String?;
              final repoName = repo['name'] as String?;
              if (displayName != null && displayName.isNotEmpty) {
                String fetchedSql = displayName;
                if (repoName != null) {
                  _dataformRepoPaths[displayName] = repoName;
                  
                  try {
                    // 1. Check GET /workspaces
                    final wsUrl = Uri.parse("https://dataform.googleapis.com/v1beta1/$repoName/workspaces");
                    final wsResp = await client.get(wsUrl);
                    await LoggerService.log("Dataform GET workspaces (${wsResp.statusCode}): ${wsResp.body}");

                    // 2. Send CreateCompilationResultRequest with empty body {}
                    final postCompUrl = Uri.parse("https://dataform.googleapis.com/v1beta1/$repoName/compilationResults");
                    final postCompResp = await client.post(
                      postCompUrl,
                      headers: {'Content-Type': 'application/json'},
                      body: json.encode({}),
                    );
                    await LoggerService.log("Dataform POST compilationResults ({}) (${postCompResp.statusCode}): ${postCompResp.body}");
                    if (postCompResp.statusCode == 200 || postCompResp.statusCode == 201) {
                      final compData = json.decode(postCompResp.body);
                      final compName = compData['name'];
                      if (compName != null) {
                        final actionsUrl = Uri.parse("https://dataform.googleapis.com/v1beta1/$compName/compilationResultActions");
                        final actionsResp = await client.get(actionsUrl);
                        await LoggerService.log("Dataform compilationResultActions (${actionsResp.statusCode}): ${actionsResp.body}");
                      }
                    }
                  } catch (e) {
                    await LoggerService.log("Dataform compilation error: $e", level: "WARNING");
                  }
                }
                discoveredCloudQueries.add(fetchedSql);
                await LoggerService.log("Discovered BigQuery Studio Saved Query from GCP: $displayName (Repo: $repoName)");
              }
            }
          }
        }
      }
    } catch (dfe, dfstack) {
      await LoggerService.log("Dataform API check exception", level: "WARNING", error: dfe, stackTrace: dfstack);
    }

    if (discoveredCloudQueries.isNotEmpty) {
      for (final q in discoveredCloudQueries) {
        if (!_projectQueries.contains(q)) {
          _projectQueries.add(q);
        }
      }
      notifyListeners();
    }
  }

  /// Fetches SQL content for a Dataform repository saved query
  Future<String?> fetchDataformQueryContent(String displayName) async {
    final repoPath = _dataformRepoPaths[displayName];
    await LoggerService.log("fetchDataformQueryContent triggered for '$displayName' (repoPath: $repoPath)");
    if (repoPath == null) return null;

    try {
      final client = await _authService.getAuthenticatedClient();
      if (client == null) return null;

      // 1. Fetch workspaces for repository
      final wsUrl = Uri.parse("https://dataform.googleapis.com/v1beta1/$repoPath/workspaces");
      final wsResp = await client.get(wsUrl);
      if (wsResp.statusCode == 200) {
        final wsData = json.decode(wsResp.body);
        final workspaces = wsData['workspaces'] as List<dynamic>?;
        if (workspaces != null && workspaces.isNotEmpty) {
          final wsName = workspaces.first['name'];

          // 2. Search directory files inside workspace
          final searchUrl = Uri.parse("https://dataform.googleapis.com/v1beta1/$wsName:searchFiles");
          final searchResp = await client.get(searchUrl);
          await LoggerService.log("Dataform searchFiles API ($searchUrl): ${searchResp.statusCode} -> ${searchResp.body}");

          final filesUrl = Uri.parse("https://dataform.googleapis.com/v1beta1/$wsName/files");
          final filesResp = await client.get(filesUrl);
          await LoggerService.log("Dataform Files API ($filesUrl): ${filesResp.statusCode} -> ${filesResp.body}");

          List<dynamic> filesList = [];
          if (filesResp.statusCode == 200) {
            final filesData = json.decode(filesResp.body);
            filesList = filesData['files'] as List<dynamic>? ?? [];
          } else if (searchResp.statusCode == 200) {
            final searchData = json.decode(searchResp.body);
            filesList = searchData['searchResults'] as List<dynamic>? ?? [];
          }

          if (filesList.isNotEmpty) {
            final filePath = filesList.first['path'] ?? filesList.first['file']?['path'] ?? 'index.sql';
            final readFileUrl = Uri.parse("https://dataform.googleapis.com/v1beta1/$wsName:readFile?path=$filePath");
            final contentResp = await client.get(readFileUrl);
            await LoggerService.log("Dataform readFile API ($readFileUrl): ${contentResp.statusCode} -> ${contentResp.body}");
            if (contentResp.statusCode == 200) {
              final contentJson = json.decode(contentResp.body);
              final raw = contentJson['fileContents'] ?? contentJson['contents'];
              if (raw != null) {
                final decoded = utf8.decode(base64.decode(raw));
                await LoggerService.log("Successfully retrieved Dataform SQL: $decoded");
                return decoded;
              }
            }
          }
        }
      }
    } catch (e, stack) {
      await LoggerService.log("Failed to fetch Dataform SQL content", level: "WARNING", error: e, stackTrace: stack);
    }
    return null;
  }

  /// Loads locally saved queries for the selected project
  Future<void> loadProjectSavedQueries() async {
    if (_selectedProjectId == null) return;
    try {
      final raw = await _storage.read(key: 'project_saved_queries_$_selectedProjectId');
      if (raw != null) {
        _projectQueries = List<String>.from(json.decode(raw));
      } else {
        _projectQueries = [];
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Failed to load project saved queries: $e");
    }
  }

  /// Saves a query to the selected project's saved queries list
  Future<void> saveProjectQuery(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || _selectedProjectId == null) return;
    if (_projectQueries.contains(trimmed)) return;

    _projectQueries.insert(0, trimmed);
    if (_projectQueries.length > 20) {
      _projectQueries = _projectQueries.sublist(0, 20);
    }
    notifyListeners();
    try {
      await _storage.write(
        key: 'project_saved_queries_$_selectedProjectId',
        value: json.encode(_projectQueries),
      );
    } catch (e) {
      debugPrint("Failed to save project query: $e");
    }
  }

  /// Fetches recent query execution history for the active GCP project via BigQuery API (GET /bigquery/v2/projects/{projectId}/jobs)
  Future<void> fetchRecentQueries() async {
    if (_authService.currentUser?.displayName == 'Test User' && _api == null) {
      _recentQueries = [
        'SELECT * FROM `transactions` LIMIT 100',
        'SELECT COUNT(*) FROM `users`',
      ];
      notifyListeners();
      return;
    }

    if (_api == null || _selectedProjectId == null) return;
    _isLoadingProjectQueries = true;
    notifyListeners();

    await LoggerService.log("Fetching recent query history for GCP project: $_selectedProjectId");

    try {
      final response = await _api!.jobs.list(
        _selectedProjectId!,
        projection: 'full',
        maxResults: 20,
      );

      final List<String> fetchedQueries = [];
      if (response.jobs != null) {
        for (final job in response.jobs!) {
          final q = job.configuration?.query?.query?.trim();
          if (q != null && q.isNotEmpty && !fetchedQueries.contains(q)) {
            fetchedQueries.add(q);
          }
        }
      }

      _recentQueries = fetchedQueries;
      await LoggerService.log("Fetched ${_recentQueries.length} recent query jobs for GCP project $_selectedProjectId");
    } catch (e, stack) {
      debugPrint("Failed to fetch recent queries for $_selectedProjectId: $e");
      await LoggerService.log("Failed to fetch recent queries for $_selectedProjectId", level: "WARNING", error: e, stackTrace: stack);
    } finally {
      _isLoadingProjectQueries = false;
      notifyListeners();
    }
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

  /// Runs Quick Count: wraps active user query in `SELECT COUNT(*) FROM (...)`
  Future<void> runQuickCount(String userQuery, {String? datasetId, String? tableId}) async {
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

    final trimmed = userQuery.trim();
    if (trimmed.isEmpty && (datasetId == null || tableId == null)) {
      _queryError = "Please enter a SQL query first.";
      _isExecuting = false;
      notifyListeners();
      return;
    }

    if (_api == null || _selectedProjectId == null) return;

    try {
      String countSql;
      if (trimmed.isNotEmpty) {
        String cleaned = trimmed;
        if (cleaned.endsWith(';')) {
          cleaned = cleaned.substring(0, cleaned.length - 1).trim();
        }
        countSql = "SELECT COUNT(*) AS total_count FROM ($cleaned)";
      } else {
        countSql = "SELECT COUNT(*) AS total_count FROM `$datasetId.$tableId`";
      }

      await LoggerService.log("Running Quick Count query: $countSql");

      final request = QueryRequest(
        query: countSql,
        useLegacySql: false,
      );
      final response = await _api!.jobs.query(request, _selectedProjectId!);

      if (response.rows != null && response.rows!.isNotEmpty) {
        final val = response.rows!.first.f?.first.v?.toString();
        if (val != null) {
          final parsed = int.tryParse(val);
          if (parsed != null) {
            _quickCountResult = parsed.toString().replaceAllMapped(
              RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
              (Match m) => "${m[1]},",
            );
          } else {
            _quickCountResult = val;
          }
        } else {
          _quickCountResult = "0";
        }
      } else {
        _quickCountResult = "0";
      }
      _queryError = null;
    } catch (e, stack) {
      await LoggerService.log("Quick count query error, attempting metadata fallback", level: "WARNING", error: e, stackTrace: stack);
      if (datasetId != null && tableId != null) {
        try {
          final table = await _api!.tables.get(_selectedProjectId!, datasetId, tableId);
          if (table.numRows != null) {
            final parsed = int.tryParse(table.numRows!);
            _quickCountResult = parsed != null
                ? parsed.toString().replaceAllMapped(
                    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                    (Match m) => "${m[1]},",
                  )
                : table.numRows;
            _queryError = null;
            return;
          }
        } catch (metaErr) {
          debugPrint("Metadata fallback failed: $metaErr");
        }
      }
      _quickCountResult = null;
      _queryError = e.toString();
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
        _personalQueries = [];
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
