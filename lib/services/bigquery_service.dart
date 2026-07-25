import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:googleapis/bigquery/v2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pocket_query/services/auth_service.dart';
import 'package:pocket_query/services/logger_service.dart';

/// Represents a saved query either stored locally or synced with GCP BigQuery
class SavedQuery {
  final String name;
  final String sql;
  final String? datasetId;
  final bool isCloudView;

  SavedQuery({
    required this.name,
    required this.sql,
    this.datasetId,
    this.isCloudView = false,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'sql': sql,
    'datasetId': datasetId,
    'isCloudView': isCloudView,
  };

  factory SavedQuery.fromJson(Map<String, dynamic> json) => SavedQuery(
    name: json['name'] as String? ?? 'Untitled Query',
    sql: json['sql'] as String? ?? '',
    datasetId: json['datasetId'] as String?,
    isCloudView: json['isCloudView'] as bool? ?? false,
  );
}

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
  Map<String, List<String>> _datasetTables =
      {}; // datasetId -> list of tableIds
  Map<String, List<Map<String, String>>> _tableFields =
      {}; // "datasetId.tableId" -> fields
  bool _isLoadingSchema = false;

  // Project Queries & Jobs state
  List<SavedQuery> _projectQueries = [];

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
      ],
    };
    _projectQueries = [
      SavedQuery(
        name: 'online_transactions_this_month',
        sql:
            'SELECT * FROM `ecommerce_dataset.transactions` WHERE amount > 100',
        isCloudView: true,
      ),
      SavedQuery(
        name: 'accounts_with_no_primary_contact',
        sql: 'SELECT user_id, event_name FROM `analytics_dataset.user_events`',
        isCloudView: false,
      ),
    ];
    notifyListeners();
  }

  // Getters
  String? get selectedProjectId => _selectedProjectId;
  List<String> get projects => _projects;
  bool get isLoadingProjects => _isLoadingProjects;
  String? get projectsError => _projectsError;
  List<String> get personalQueries => _personalQueries;

  List<SavedQuery> get projectQueries => _projectQueries;

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
    await LoggerService.log(
      "User triggered full refresh (Projects, Schemas, Saved Queries, and Recent Query History)",
    );
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
    await LoggerService.log(
      "Executing fetchProjects() via BigQuery REST API (GET /bigquery/v2/projects)",
    );
    try {
      if (_api != null) {
        final response = await _api!.projects.list();
        final List<String> projectList =
            response.projects
                ?.map((p) => p.projectReference?.projectId ?? p.id!)
                .toList() ??
            <String>[];
        _projects = projectList;
        await LoggerService.log(
          "GCP API returned ${projectList.length} projects: $projectList",
        );
        if (_projects.isNotEmpty) {
          if (_selectedProjectId == null ||
              !_projects.contains(_selectedProjectId)) {
            await selectProject(_projects.first);
          }
        } else {
          _selectedProjectId = null;
          _projectsError = "No Google Cloud projects found for this account.";
          await LoggerService.log(
            "GCP API returned 0 projects for account.",
            level: "WARNING",
          );
        }
      } else {
        _projects = [];
        _selectedProjectId = null;
        if (_authService.lastAuthError != null) {
          _projectsError =
              "OAuth token unavailable because Google Sign-In failed:\n${_authService.lastAuthError}\n\nRegister SHA-1 fingerprint in GCP Console to obtain a real OAuth access token.";
        } else {
          _projectsError =
              "Google Cloud API client is not initialized (no active OAuth access token).";
        }
        await LoggerService.log(
          "Cannot call GCP projects.list(): BigQuery API client is null (no valid OAuth token). Last Auth Error: ${_authService.lastAuthError}",
          level: "WARNING",
        );
      }
    } catch (e, stack) {
      _projects = [];
      _selectedProjectId = null;
      _projectsError = e.toString().replaceFirst(
        RegExp(r'^DetailedApiRequestError\(.*?\): '),
        '',
      );
      await LoggerService.log(
        "GCP projects.list() API call failed with exception",
        level: "ERROR",
        error: e,
        stackTrace: stack,
      );
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

    await LoggerService.log(
      "Selected GCP Project: $projectId. Fetching datasets, saved queries, and recent query history...",
    );
    await Future.wait([
      fetchDatasetsAndTables().then((_) => fetchCloudSavedQueries()),
      loadProjectSavedQueries(),
      fetchRecentQueries(),
    ]);
  }

  /// Scans GCP BigQuery for cloud-saved queries (Saved Views, Routines, and Dataform Repository assets)
  Future<void> fetchCloudSavedQueries() async {
    if (_api == null || _selectedProjectId == null) return;

    await LoggerService.log(
      "Scanning GCP for Cloud Saved Queries (Views, Routines, Dataform) in project: $_selectedProjectId",
    );

    final List<SavedQuery> discoveredCloudQueries = [];

    // 1. Scan BigQuery Datasets for Saved Views (View SQL definitions)
    try {
      for (final datasetId in _datasets) {
        final tablesList = await _api!.tables.list(
          _selectedProjectId!,
          datasetId,
        );
        if (tablesList.tables != null) {
          for (final t in tablesList.tables!) {
            if (t.type == 'VIEW') {
              try {
                final fullTable = await _api!.tables.get(
                  _selectedProjectId!,
                  datasetId,
                  t.tableReference!.tableId!,
                );
                final viewQuery = fullTable.view?.query;
                final viewName = t.tableReference!.tableId!;
                if (viewQuery != null && viewQuery.isNotEmpty) {
                  discoveredCloudQueries.add(
                    SavedQuery(
                      name: viewName,
                      sql: viewQuery,
                      datasetId: datasetId,
                      isCloudView: true,
                    ),
                  );
                  await LoggerService.log(
                    "Discovered BigQuery Saved View query: $viewName",
                  );
                }
              } catch (ve) {
                debugPrint(
                  "Failed to fetch view details for ${t.tableReference?.tableId}: $ve",
                );
              }
            }
          }
        }

        // 2. Scan BigQuery Routines / Procedures
        try {
          final routinesList = await _api!.routines.list(
            _selectedProjectId!,
            datasetId,
          );
          if (routinesList.routines != null) {
            for (final r in routinesList.routines!) {
              final routineId = r.routineReference?.routineId ?? 'routine';
              final body = r.definitionBody;
              if (body != null && body.isNotEmpty) {
                discoveredCloudQueries.add(
                  SavedQuery(
                    name: routineId,
                    sql: body,
                    datasetId: datasetId,
                    isCloudView: true,
                  ),
                );
                await LoggerService.log(
                  "Discovered BigQuery Routine: $routineId",
                );
              }
            }
          }
        } catch (re) {
          debugPrint("No routines found in dataset $datasetId: $re");
        }
      }
    } catch (e, stack) {
      await LoggerService.log(
        "Error scanning BigQuery datasets for saved views/routines",
        level: "WARNING",
        error: e,
        stackTrace: stack,
      );
    }

    // 3. Scan Dataform API (Modern BigQuery Studio Saved Queries)
    try {
      final client = await _authService.getAuthenticatedClient();
      if (client != null) {
        final url = Uri.parse(
          "https://dataform.googleapis.com/v1beta1/projects/$_selectedProjectId/locations/-/repositories",
        );
        final resp = await client.get(url);
        await LoggerService.log(
          "Dataform Repositories API response (${resp.statusCode}): ${resp.body}",
        );
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body);
          final repos = data['repositories'] as List<dynamic>?;
          if (repos != null) {
            for (final repo in repos) {
              final displayName = repo['displayName'] as String?;
              final repoName = repo['name'] as String?;
              if (displayName != null && displayName.isNotEmpty) {
                if (repoName != null) {
                  _dataformRepoPaths[displayName] = repoName;
                }
                final sqlContent = await fetchDataformQueryContent(displayName);
                final String fetchedSql =
                    (sqlContent != null && sqlContent.trim().isNotEmpty)
                    ? sqlContent
                    : 'SELECT * FROM `$_selectedProjectId.sample` LIMIT 10;';

                discoveredCloudQueries.add(
                  SavedQuery(
                    name: displayName,
                    sql: fetchedSql,
                    isCloudView: true,
                  ),
                );
                await LoggerService.log(
                  "Discovered BigQuery Studio Saved Query from GCP: $displayName (Repo: $repoName, SQL: $fetchedSql)",
                );
              }
            }
          }
        }
      }
    } catch (dfe, dfstack) {
      await LoggerService.log(
        "Dataform API check exception",
        level: "WARNING",
        error: dfe,
        stackTrace: dfstack,
      );
    }

    if (discoveredCloudQueries.isNotEmpty) {
      for (final cq in discoveredCloudQueries) {
        final existingIdx = _projectQueries.indexWhere(
          (pq) =>
              pq.name == cq.name ||
              pq.sql == cq.name ||
              pq.sql == cq.sql ||
              pq.name == 'Saved Query',
        );
        if (existingIdx >= 0) {
          _projectQueries[existingIdx] = cq;
        } else {
          _projectQueries.add(cq);
        }
      }
      notifyListeners();
    }
  }

  /// Loads locally saved queries for the selected project
  Future<void> loadProjectSavedQueries() async {
    if (_selectedProjectId == null) return;
    try {
      final raw = await _storage.read(
        key: 'project_saved_queries_$_selectedProjectId',
      );
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        _projectQueries = decoded.map((e) {
          if (e is Map<String, dynamic>) {
            return SavedQuery.fromJson(e);
          } else if (e is String) {
            final firstLine = e.split('\n').first.trim();
            final title = firstLine.isNotEmpty ? firstLine : 'Saved Query';
            return SavedQuery(name: title, sql: e);
          }
          return SavedQuery(name: 'Saved Query', sql: e.toString());
        }).toList();
      } else {
        _projectQueries = [];
      }

      notifyListeners();
    } catch (e) {
      debugPrint("Failed to load project saved queries: $e");
    }
  }

  /// Saves a query with a name to the selected project (and optionally creates a BigQuery View in GCP)
  /// Creates an official BigQuery Studio Saved Query via Dataform API
  Future<bool> saveDataformQuery(String name, String sql) async {
    if (_selectedProjectId == null) return false;
    try {
      final client = await _authService.getAuthenticatedClient();
      if (client == null) return false;

      final repoId = "pq-${DateTime.now().millisecondsSinceEpoch}";
      final locations = ['australia-southeast1', 'us-central1', 'us'];

      String? createdRepoName;
      for (final loc in locations) {
        final createRepoUrl = Uri.parse(
          "https://dataform.googleapis.com/v1beta1/projects/$_selectedProjectId/locations/$loc/repositories?repositoryId=$repoId",
        );
        final resp = await client.post(
          createRepoUrl,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'displayName': name,
            'labels': {'single-file-asset-type': 'sql'},
          }),
        );
        await LoggerService.log(
          "Dataform createRepository ($loc) status ${resp.statusCode}: ${resp.body}",
        );
        if (resp.statusCode == 200 || resp.statusCode == 201) {
          final data = json.decode(resp.body);
          createdRepoName = data['name'];
          break;
        }
      }

      if (createdRepoName == null) return false;

      // Create Workspace
      final wsId = "ws-${DateTime.now().millisecondsSinceEpoch}";
      final createWsUrl = Uri.parse(
        "https://dataform.googleapis.com/v1beta1/$createdRepoName/workspaces?workspaceId=$wsId",
      );
      final wsResp = await client.post(
        createWsUrl,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({}),
      );
      await LoggerService.log(
        "Dataform createWorkspace status ${wsResp.statusCode}: ${wsResp.body}",
      );

      final wsName = "$createdRepoName/workspaces/$wsId";

      // Write File (index.sql)
      final writeFileUrl = Uri.parse(
        "https://dataform.googleapis.com/v1beta1/$wsName:writeFile",
      );
      final base64Content = base64.encode(utf8.encode(sql));
      await client.post(
        writeFileUrl,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'path': 'index.sql', 'contents': base64Content}),
      );

      // Commit Workspace
      final commitUrl = Uri.parse(
        "https://dataform.googleapis.com/v1beta1/$wsName:commit",
      );
      await client.post(
        commitUrl,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'author': {
            'name': 'Pocket Query',
            'emailAddress':
                _authService.currentUser?.email ?? 'pocketquery@app',
          },
          'commitMessage': 'Saved from Pocket Query',
        }),
      );

      _dataformRepoPaths[name] = createdRepoName;
      await LoggerService.log(
        "Successfully created BigQuery Studio Saved Query in GCP via Dataform API: '$name' ($createdRepoName)",
      );
      return true;
    } catch (e, stack) {
      await LoggerService.log(
        "Dataform API query creation exception",
        level: "WARNING",
        error: e,
        stackTrace: stack,
      );
      return false;
    }
  }

  /// Saves a query with a name to the selected project (using Dataform API or BigQuery View in GCP, with local fallback)
  Future<void> saveProjectQuery(
    String query, {
    required String name,
    String? datasetId,
  }) async {
    final trimmedSql = query.trim();
    final trimmedName = name.trim();
    if (trimmedSql.isEmpty ||
        trimmedName.isEmpty ||
        _selectedProjectId == null) {
      return;
    }

    final targetDataset =
        datasetId ?? (_datasets.isNotEmpty ? _datasets.first : null);
    bool isCloudSaved = false;

    // 1. First attempt to create an official BigQuery Studio Saved Query via Dataform API
    final dataformSuccess = await saveDataformQuery(trimmedName, trimmedSql);
    if (dataformSuccess) {
      isCloudSaved = true;
    } else if (_api != null && targetDataset != null) {
      // 2. Fallback: attempt to create a BigQuery View in GCP
      final String cleanId = trimmedName.replaceAll(
        RegExp(r'[^a-zA-Z0-9_]'),
        '_',
      );
      final String viewId = cleanId.isEmpty
          ? 'view_${DateTime.now().millisecondsSinceEpoch}'
          : (RegExp(r'^[0-9]').hasMatch(cleanId) ? 'v_$cleanId' : cleanId);

      try {
        final newView = Table(
          tableReference: TableReference(
            projectId: _selectedProjectId,
            datasetId: targetDataset,
            tableId: viewId,
          ),
          view: ViewDefinition(query: trimmedSql, useLegacySql: false),
          description: "Saved Query from Pocket Query: $trimmedName",
        );

        await _api!.tables.insert(newView, _selectedProjectId!, targetDataset);
        isCloudSaved = true;
        await LoggerService.log(
          "Successfully created BigQuery View '$viewId' in dataset '$targetDataset' for GCP project '$_selectedProjectId'",
        );
      } catch (e, stack) {
        await LoggerService.log(
          "Could not create BigQuery View in GCP (saving locally): $e",
          level: "WARNING",
          error: e,
          stackTrace: stack,
        );
      }
    }

    final newSavedQuery = SavedQuery(
      name: trimmedName,
      sql: trimmedSql,
      datasetId: targetDataset,
      isCloudView: isCloudSaved,
    );

    // Remove any existing query with the same name or SQL
    _projectQueries.removeWhere(
      (sq) => sq.name == trimmedName || sq.sql == trimmedSql,
    );
    _projectQueries.insert(0, newSavedQuery);

    if (_projectQueries.length > 30) {
      _projectQueries = _projectQueries.sublist(0, 30);
    }
    notifyListeners();

    try {
      final jsonList = _projectQueries.map((q) => q.toJson()).toList();
      await _storage.write(
        key: 'project_saved_queries_$_selectedProjectId',
        value: json.encode(jsonList),
      );
    } catch (e) {
      debugPrint("Failed to save project query: $e");
    }
  }

  /// Updates an existing Dataform saved query in GCP
  Future<bool> updateDataformQuery(String name, String sql) async {
    final repoPath = _dataformRepoPaths[name];
    if (repoPath == null) return false;

    try {
      final client = await _authService.getAuthenticatedClient();
      if (client == null) return false;

      // 1. Fetch workspace or create workspace
      final wsUrl = Uri.parse(
        "https://dataform.googleapis.com/v1beta1/$repoPath/workspaces",
      );
      final wsResp = await client.get(wsUrl);
      String? wsName;
      if (wsResp.statusCode == 200) {
        final wsData = json.decode(wsResp.body);
        final workspaces = wsData['workspaces'] as List<dynamic>?;
        if (workspaces != null && workspaces.isNotEmpty) {
          wsName = workspaces.first['name'];
        }
      }

      if (wsName == null) {
        final wsId = "ws-${DateTime.now().millisecondsSinceEpoch}";
        final createWsUrl = Uri.parse(
          "https://dataform.googleapis.com/v1beta1/$repoPath/workspaces?workspaceId=$wsId",
        );
        final createResp = await client.post(
          createWsUrl,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({}),
        );
        if (createResp.statusCode == 200 || createResp.statusCode == 201) {
          final createData = json.decode(createResp.body);
          wsName = createData['name'];
        }
      }

      if (wsName == null) return false;

      // 2. Overwrite file (index.sql)
      final base64Content = base64.encode(utf8.encode(sql));
      final postWriteUrl = Uri.parse(
        "https://dataform.googleapis.com/v1beta1/$wsName:writeFile",
      );
      final writeResp = await client.post(
        postWriteUrl,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'path': 'index.sql', 'contents': base64Content}),
      );
      await LoggerService.log(
        "Dataform update writeFile status (${writeResp.statusCode}): ${writeResp.body}",
      );

      // 3. Commit
      final commitUrl = Uri.parse(
        "https://dataform.googleapis.com/v1beta1/$wsName:commit",
      );
      await client.post(
        commitUrl,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'author': {
            'name': 'Pocket Query',
            'emailAddress':
                _authService.currentUser?.email ?? 'pocketquery@app',
          },
          'commitMessage': 'Updated from Pocket Query',
        }),
      );

      await LoggerService.log(
        "Successfully updated Dataform saved query '$name' in GCP",
      );
      return true;
    } catch (e, stack) {
      await LoggerService.log(
        "Dataform API query update exception",
        level: "WARNING",
        error: e,
        stackTrace: stack,
      );
      return false;
    }
  }

  /// Updates an existing saved query or creates a new entry if not found
  Future<void> updateProjectQuery(String query, {required String name}) async {
    final trimmedSql = query.trim();
    final trimmedName = name.trim();
    if (trimmedSql.isEmpty ||
        trimmedName.isEmpty ||
        _selectedProjectId == null) {
      return;
    }

    bool isCloudUpdated = await updateDataformQuery(trimmedName, trimmedSql);

    final idx = _projectQueries.indexWhere((q) => q.name == trimmedName);
    final updatedSavedQuery = SavedQuery(
      name: trimmedName,
      sql: trimmedSql,
      isCloudView:
          isCloudUpdated ||
          (idx >= 0 ? _projectQueries[idx].isCloudView : false),
    );

    if (idx >= 0) {
      _projectQueries[idx] = updatedSavedQuery;
    } else {
      _projectQueries.insert(0, updatedSavedQuery);
    }
    notifyListeners();

    try {
      final jsonList = _projectQueries.map((q) => q.toJson()).toList();
      await _storage.write(
        key: 'project_saved_queries_$_selectedProjectId',
        value: json.encode(jsonList),
      );
    } catch (e) {
      debugPrint("Failed to save project query: $e");
    }
  }

  /// Deletes a Dataform saved query repository in GCP (with ?force=true)
  Future<bool> deleteDataformQuery(String name) async {
    String? repoPath = _dataformRepoPaths[name];
    await LoggerService.log(
      "[DATAFORM_DELETE] Initiated deleteDataformQuery for '$name' (Initial repoPath: '$repoPath')",
    );

    try {
      final client = await _authService.getAuthenticatedClient();
      if (client == null) {
        await LoggerService.log(
          "[DATAFORM_DELETE_ERROR] Authenticated client is null when trying to delete '$name'",
          level: "WARNING",
        );
        return false;
      }

      // 1. If repoPath is missing from cache, scan repositories to locate it
      if (repoPath == null && _selectedProjectId != null) {
        final url = Uri.parse(
          "https://dataform.googleapis.com/v1beta1/projects/$_selectedProjectId/locations/-/repositories",
        );
        await LoggerService.log(
          "[DATAFORM_DELETE] Cache miss for '$name'. Fetching repositories from $url...",
        );
        final resp = await client.get(url);
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body);
          final repos = data['repositories'] as List<dynamic>?;
          if (repos != null) {
            for (final repo in repos) {
              final dName = repo['displayName'] as String?;
              final rName = repo['name'] as String?;
              if (dName != null && rName != null) {
                _dataformRepoPaths[dName] = rName;
                if (dName == name) {
                  repoPath = rName;
                }
              }
            }
          }
        }
      }

      if (repoPath == null) {
        await LoggerService.log(
          "[DATAFORM_DELETE_WARNING] Could not find GCP Dataform repository path for '$name' to delete",
          level: "WARNING",
        );
        return false;
      }

      // 2. Fetch and delete all child workspaces inside this repository first
      final wsUrl = Uri.parse(
        "https://dataform.googleapis.com/v1beta1/$repoPath/workspaces",
      );
      final wsResp = await client.get(wsUrl);
      if (wsResp.statusCode == 200) {
        final wsData = json.decode(wsResp.body);
        final workspaces = wsData['workspaces'] as List<dynamic>?;
        if (workspaces != null && workspaces.isNotEmpty) {
          for (final ws in workspaces) {
            final wsName = ws['name'] as String?;
            if (wsName != null) {
              final delWsUrl = Uri.parse(
                "https://dataform.googleapis.com/v1beta1/$wsName",
              );
              final delWsResp = await client.delete(delWsUrl);
              await LoggerService.log(
                "[DATAFORM_DELETE] Workspace delete ($wsName) response (${delWsResp.statusCode}): ${delWsResp.body}",
              );
            }
          }
        }
      }

      // 3. Delete the repository itself
      final deleteUrl = Uri.parse(
        "https://dataform.googleapis.com/v1beta1/$repoPath",
      );
      await LoggerService.log(
        "[DATAFORM_DELETE] Executing HTTP DELETE $deleteUrl...",
      );
      final resp = await client.delete(deleteUrl);
      await LoggerService.log(
        "[DATAFORM_DELETE] Repository delete response (${resp.statusCode}): ${resp.body}",
      );
      _dataformRepoPaths.remove(name);
      return resp.statusCode == 200 || resp.statusCode == 204;
    } catch (e, stack) {
      await LoggerService.log(
        "[DATAFORM_DELETE_EXCEPTION] Failed to delete Dataform query '$name'",
        level: "WARNING",
        error: e,
        stackTrace: stack,
      );
      return false;
    }
  }

  /// Deletes a project query from Dataform/GCP and local storage
  Future<void> deleteProjectQuery(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty || _selectedProjectId == null) return;

    await deleteDataformQuery(trimmedName);

    final targetQuery = _projectQueries.firstWhere(
      (q) => q.name == trimmedName,
      orElse: () => SavedQuery(name: trimmedName, sql: ''),
    );
    if (_api != null && targetQuery.datasetId != null) {
      try {
        final viewId = trimmedName.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
        await _api!.tables.delete(
          _selectedProjectId!,
          targetQuery.datasetId!,
          viewId,
        );
        await LoggerService.log(
          "Deleted BigQuery View '$viewId' from GCP dataset",
        );
      } catch (e) {
        debugPrint("Could not delete view from BigQuery dataset: $e");
      }
    }

    _projectQueries.removeWhere((q) => q.name == trimmedName);
    notifyListeners();

    try {
      final jsonList = _projectQueries.map((q) => q.toJson()).toList();
      await _storage.write(
        key: 'project_saved_queries_$_selectedProjectId',
        value: json.encode(jsonList),
      );
    } catch (e) {
      debugPrint("Failed to update saved queries after deletion: $e");
    }
  }

  /// Renames a Dataform repository saved query in GCP
  Future<bool> renameDataformQuery(String oldName, String newName) async {
    final repoPath = _dataformRepoPaths[oldName];
    if (repoPath == null) return false;

    try {
      final client = await _authService.getAuthenticatedClient();
      if (client == null) return false;

      final patchUrl = Uri.parse(
        "https://dataform.googleapis.com/v1beta1/$repoPath?updateMask=displayName",
      );
      final resp = await client.patch(
        patchUrl,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'displayName': newName}),
      );
      await LoggerService.log(
        "Dataform rename repository status (${resp.statusCode}): ${resp.body}",
      );
      if (resp.statusCode == 200) {
        _dataformRepoPaths.remove(oldName);
        _dataformRepoPaths[newName] = repoPath;
        return true;
      }
      return false;
    } catch (e, stack) {
      await LoggerService.log(
        "Dataform API rename exception",
        level: "WARNING",
        error: e,
        stackTrace: stack,
      );
      return false;
    }
  }

  /// Renames a project saved query in Dataform/GCP and local storage
  Future<void> renameProjectQuery(String oldName, String newName) async {
    final trimmedOld = oldName.trim();
    final trimmedNew = newName.trim();
    if (trimmedOld.isEmpty ||
        trimmedNew.isEmpty ||
        _selectedProjectId == null) {
      return;
    }

    await renameDataformQuery(trimmedOld, trimmedNew);

    final idx = _projectQueries.indexWhere((q) => q.name == trimmedOld);
    if (idx >= 0) {
      final existing = _projectQueries[idx];
      _projectQueries[idx] = SavedQuery(
        name: trimmedNew,
        sql: existing.sql,
        datasetId: existing.datasetId,
        isCloudView: existing.isCloudView,
      );
      notifyListeners();

      try {
        final jsonList = _projectQueries.map((q) => q.toJson()).toList();
        await _storage.write(
          key: 'project_saved_queries_$_selectedProjectId',
          value: json.encode(jsonList),
        );
      } catch (e) {
        debugPrint("Failed to update saved queries after rename: $e");
      }
    }
  }

  /// Fetches SQL content for a Dataform repository saved query
  Future<String?> fetchDataformQueryContent(String displayName) async {
    String? repoPath = _dataformRepoPaths[displayName];

    try {
      final client = await _authService.getAuthenticatedClient();
      if (client == null) return null;

      // 1. If repoPath is missing from cache, scan repositories to locate it
      if (repoPath == null && _selectedProjectId != null) {
        final url = Uri.parse(
          "https://dataform.googleapis.com/v1beta1/projects/$_selectedProjectId/locations/-/repositories",
        );
        final resp = await client.get(url);
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body);
          final repos = data['repositories'] as List<dynamic>?;
          if (repos != null) {
            for (final repo in repos) {
              final dName = repo['displayName'] as String?;
              final rName = repo['name'] as String?;
              if (dName != null && rName != null) {
                _dataformRepoPaths[dName] = rName;
                if (dName == displayName) {
                  repoPath = rName;
                }
              }
            }
          }
        }
      }

      if (repoPath == null) return null;

      // 2. Fetch workspaces for repository
      final wsUrl = Uri.parse(
        "https://dataform.googleapis.com/v1beta1/$repoPath/workspaces",
      );
      final wsResp = await client.get(wsUrl);
      if (wsResp.statusCode == 200) {
        final wsData = json.decode(wsResp.body);
        final workspaces = wsData['workspaces'] as List<dynamic>?;
        if (workspaces != null && workspaces.isNotEmpty) {
          final wsName = workspaces.first['name'];

          // Try candidate file paths directly
          final candidatePaths = ['index.sql', 'query.sql', 'main.sql'];
          for (final path in candidatePaths) {
            final readFileUrl = Uri.parse(
              "https://dataform.googleapis.com/v1beta1/$wsName:readFile?path=$path",
            );
            final contentResp = await client.get(readFileUrl);
            if (contentResp.statusCode == 200) {
              final contentJson = json.decode(contentResp.body);
              final raw =
                  contentJson['fileContents'] ?? contentJson['contents'];
              if (raw != null) {
                final decoded = utf8.decode(base64.decode(raw));
                if (decoded.trim().isNotEmpty) {
                  await LoggerService.log(
                    "Successfully retrieved Dataform SQL via $path: $decoded",
                  );
                  return decoded;
                }
              }
            }
          }

          // Search directory files inside workspace
          final filesUrl = Uri.parse(
            "https://dataform.googleapis.com/v1beta1/$wsName/files",
          );
          final filesResp = await client.get(filesUrl);
          if (filesResp.statusCode == 200) {
            final filesData = json.decode(filesResp.body);
            final filesList = filesData['files'] as List<dynamic>? ?? [];
            for (final f in filesList) {
              final filePath = f['path'] as String?;
              if (filePath != null && filePath.endsWith('.sql')) {
                final readFileUrl = Uri.parse(
                  "https://dataform.googleapis.com/v1beta1/$wsName:readFile?path=$filePath",
                );
                final contentResp = await client.get(readFileUrl);
                if (contentResp.statusCode == 200) {
                  final contentJson = json.decode(contentResp.body);
                  final raw =
                      contentJson['fileContents'] ?? contentJson['contents'];
                  if (raw != null) {
                    final decoded = utf8.decode(base64.decode(raw));
                    return decoded;
                  }
                }
              }
            }
          }
        }
      }
    } catch (e, stack) {
      await LoggerService.log(
        "Failed to fetch Dataform SQL content for '$displayName'",
        level: "WARNING",
        error: e,
        stackTrace: stack,
      );
    }
    return null;
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

    await LoggerService.log(
      "Fetching recent query history for GCP project: $_selectedProjectId",
    );

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
      await LoggerService.log(
        "Fetched ${_recentQueries.length} recent query jobs for GCP project $_selectedProjectId",
      );
    } catch (e, stack) {
      debugPrint("Failed to fetch recent queries for $_selectedProjectId: $e");
      await LoggerService.log(
        "Failed to fetch recent queries for $_selectedProjectId",
        level: "WARNING",
        error: e,
        stackTrace: stack,
      );
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
      _datasets =
          datasetList.datasets
              ?.map((d) => d.datasetReference!.datasetId!)
              .toList() ??
          [];

      for (final datasetId in _datasets) {
        final tableList = await _api!.tables.list(
          _selectedProjectId!,
          datasetId,
        );
        _datasetTables[datasetId] =
            tableList.tables?.map((t) => t.tableReference!.tableId!).toList() ??
            [];
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
    if (_tableFields.containsKey(cacheKey) ||
        _api == null ||
        _selectedProjectId == null)
      return;

    try {
      final table = await _api!.tables.get(
        _selectedProjectId!,
        datasetId,
        tableId,
      );
      final fields =
          table.schema?.fields
              ?.map((f) => {'name': f.name ?? '', 'type': f.type ?? ''})
              .toList() ??
          [];

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
          query: JobConfigurationQuery(query: query, useLegacySql: false),
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
        {
          'Row': '1',
          'Name': 'Apple, Inc.',
          'Employees': '150,000',
          'Earnings': '120.5B',
        },
        {
          'Row': '2',
          'Name': 'Microsoft',
          'Employees': '220,000',
          'Earnings': '142.1B',
        },
        {
          'Row': '3',
          'Name': 'Toshiba, Inc.',
          'Employees': '100,000',
          'Earnings': '21.3B',
        },
      ];
      _isExecuting = false;
      notifyListeners();
      await addPersonalQuery(query);
      return;
    }

    if (_api == null) return;

    try {
      final request = QueryRequest(query: query, useLegacySql: false);

      final response = await _api!.jobs.query(request, _selectedProjectId!);

      _resultColumns =
          response.schema?.fields?.map((f) => f.name!).toList() ?? [];

      _resultRows =
          response.rows?.map((row) {
            final Map<String, String> rowMap = {};
            for (int i = 0; i < _resultColumns.length; i++) {
              final cellValue = row.f?[i].v;
              rowMap[_resultColumns[i]] = cellValue?.toString() ?? '';
            }
            return rowMap;
          }).toList() ??
          [];

      _queryError = null;
      await addPersonalQuery(query);
    } catch (e) {
      _resultColumns = [];
      _resultRows = [];
      _queryError = e.toString().replaceFirst(
        RegExp(r'^DetailedApiRequestError\(.*?\): '),
        '',
      );
      debugPrint("Query job failed: $e");
    } finally {
      _isExecuting = false;
      notifyListeners();
    }
  }

  /// Runs Quick Count: wraps active user query in `SELECT COUNT(*) FROM (...)`
  Future<void> runQuickCount(
    String userQuery, {
    String? datasetId,
    String? tableId,
  }) async {
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

      final request = QueryRequest(query: countSql, useLegacySql: false);
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
      await LoggerService.log(
        "Quick count query error, attempting metadata fallback",
        level: "WARNING",
        error: e,
        stackTrace: stack,
      );
      if (datasetId != null && tableId != null) {
        try {
          final table = await _api!.tables.get(
            _selectedProjectId!,
            datasetId,
            tableId,
          );
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
      await _storage.write(
        key: 'personal_queries',
        value: json.encode(_personalQueries),
      );
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
