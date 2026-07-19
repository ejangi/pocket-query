import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_query/services/bigquery_service.dart';
import '../test/auth_flow_test.dart';

import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    channel,
    (MethodCall methodCall) async {
      return null; // Return null to simulate empty cache
    },
  );

  group('BigQueryService Unit Tests', () {
    late MockAuthService mockAuth;
    late BigQueryService service;

    setUp(() async {
      mockAuth = MockAuthService();
      await mockAuth.signIn(); // Sign in the test user first
      service = BigQueryService(mockAuth);
    });

    test('Initial state loads mock data correctly when Test User is active', () {
      // Mock data should load automatically when displayName is 'Test User'
      expect(service.projects, isNotEmpty);
      expect(service.selectedProjectId, equals('mock-gcp-project-1'));
      expect(service.datasets, contains('analytics_dataset'));
      expect(service.datasetTables['analytics_dataset'], contains('user_events'));
    });

    test('Selecting a new project resets schemas and updates active selection', () async {
      await service.selectProject('mock-gcp-project-2');
      expect(service.selectedProjectId, equals('mock-gcp-project-2'));
      // In mock mode, fetchDatasetsAndTables triggers, retaining test namespaces
      expect(service.datasets, contains('analytics_dataset'));
    });

    test('estimateQueryCost mock outputs expected byte scanning size', () async {
      final query = "SELECT * FROM dataset.table";
      await service.estimateQueryCost(query);
      
      expect(service.estimatedBytesScanned, isNotNull);
      expect(service.estimatedBytesScanned, greaterThan(0));
      expect(service.estimationError, isNull);
    });

    test('runQuery mock maps columns and rows correctly', () async {
      await service.runQuery("SELECT * FROM Accounts");
      
      expect(service.isExecuting, isFalse);
      expect(service.resultColumns, containsAll(['Name', 'Employees', 'Earnings']));
      expect(service.resultRows.length, equals(3));
      expect(service.resultRows.first['Name'], equals('Apple, Inc.'));
      expect(service.queryError, isNull);
    });

    test('runQuickCount mock retrieves row count values', () async {
      await service.runQuickCount('SELECT * FROM ecommerce_dataset.transactions', datasetId: 'ecommerce_dataset', tableId: 'transactions');
      
      expect(service.isExecuting, isFalse);
      expect(service.quickCountResult, equals('10,413')); // Figma count format
      expect(service.queryError, isNull);
    });
  });
}
