import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pocket_query/services/bigquery_service.dart';

class SchemaBrowser extends StatefulWidget {
  final Function(String) onFieldSelected;

  const SchemaBrowser({super.key, required this.onFieldSelected});

  @override
  State<SchemaBrowser> createState() => _SchemaBrowserState();
}

class _SchemaBrowserState extends State<SchemaBrowser> {
  String? _selectedDataset;
  String? _selectedTable;

  @override
  Widget build(BuildContext context) {
    final bigQueryService = context.watch<BigQueryService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Build the dynamic path string
    String path = bigQueryService.selectedProjectId ?? 'No project selected';
    if (_selectedDataset != null) {
      path += ' . $_selectedDataset';
      if (_selectedTable != null) {
        path += ' . $_selectedTable';
      }
    }

    // Determine the header title
    String title = 'Datasets';
    if (_selectedDataset != null) {
      title = _selectedTable == null ? 'Tables' : 'Fields';
    }

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with back navigation
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  if (_selectedDataset != null)
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () {
                        setState(() {
                          if (_selectedTable != null) {
                            _selectedTable = null;
                          } else {
                            _selectedDataset = null;
                          }
                        });
                      },
                    ),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            // Path Indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Text(
                path,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.grey[400] : Colors.grey[700],
                ),
              ),
            ),
            const Divider(),
            
            // Loading State & Body list
            Expanded(
              child: bigQueryService.isLoadingSchema
                  ? const Center(child: CircularProgressIndicator())
                  : _buildBody(bigQueryService),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BigQueryService bq) {
    if (bq.selectedProjectId == null) {
      return const Center(child: Text('Select a project in the side menu'));
    }

    if (_selectedDataset == null) {
      return _buildDatasetsList(bq);
    } else if (_selectedTable == null) {
      return _buildTablesList(bq, _selectedDataset!);
    } else {
      return _buildFieldsList(bq, _selectedDataset!, _selectedTable!);
    }
  }

  Widget _buildDatasetsList(BigQueryService bq) {
    final datasets = bq.datasets;
    if (datasets.isEmpty) {
      return const Center(child: Text('No datasets found in this project'));
    }

    return ListView.builder(
      itemCount: datasets.length,
      itemBuilder: (context, index) {
        final datasetName = datasets[index];
        return ListTile(
          leading: const Icon(Icons.folder_open, color: Color(0xFF536DFE)),
          title: Text(datasetName),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            setState(() {
              _selectedDataset = datasetName;
            });
          },
        );
      },
    );
  }

  Widget _buildTablesList(BigQueryService bq, String datasetName) {
    final tables = bq.datasetTables[datasetName] ?? [];
    if (tables.isEmpty) {
      return const Center(child: Text('No tables found in this dataset'));
    }

    return ListView.builder(
      itemCount: tables.length,
      itemBuilder: (context, index) {
        final tableName = tables[index];
        return ListTile(
          leading: const Icon(Icons.table_chart_outlined, color: Color(0xFF536DFE)),
          title: Text(tableName),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            bq.fetchTableSchema(datasetName, tableName);
            setState(() {
              _selectedTable = tableName;
            });
          },
        );
      },
    );
  }

  Widget _buildFieldsList(BigQueryService bq, String datasetName, String tableName) {
    final cacheKey = "$datasetName.$tableName";
    final fieldsList = bq.tableFields[cacheKey] ?? [];

    if (fieldsList.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      itemCount: fieldsList.length,
      itemBuilder: (context, index) {
        final field = fieldsList[index];
        final fieldName = field['name'] ?? '';
        final fieldType = field['type'] ?? '';

        return ListTile(
          leading: const Icon(Icons.tag_outlined, size: 20),
          title: Text(fieldName),
          subtitle: Text(
            fieldType,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.add_box_outlined, color: Color(0xFF536DFE)),
            tooltip: 'Add to Query',
            onPressed: () {
              widget.onFieldSelected(fieldName);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Added "$fieldName" to query'),
                  duration: const Duration(milliseconds: 500),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
