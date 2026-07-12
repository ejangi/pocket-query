import 'package:flutter/material.dart';

class SchemaBrowser extends StatefulWidget {
  final Function(String) onFieldSelected;

  const SchemaBrowser({super.key, required this.onFieldSelected});

  @override
  State<SchemaBrowser> createState() => _SchemaBrowserState();
}

class _SchemaBrowserState extends State<SchemaBrowser> {
  String? _selectedTable;

  // Mock Schema data matching Figma specs
  final String _dataset = "MyDataSet1";
  
  final List<String> _tables = [
    'Accounts',
    'Transactions',
    'Channels',
    'Contacts',
  ];

  // Fields and their types matching Figma specs for Accounts table
  final Map<String, List<Map<String, String>>> _fields = {
    'Accounts': [
      {'name': 'Name', 'type': 'STRING'},
      {'name': 'Employees', 'type': 'INTEGER'},
      {'name': 'Earnings', 'type': 'FLOAT'},
      {'name': 'FirstContact', 'type': 'DATE'},
    ],
    'Transactions': [
      {'name': 'TransactionID', 'type': 'STRING'},
      {'name': 'Amount', 'type': 'FLOAT'},
      {'name': 'Timestamp', 'type': 'TIMESTAMP'},
    ],
    'Channels': [
      {'name': 'ChannelID', 'type': 'STRING'},
      {'name': 'Name', 'type': 'STRING'},
    ],
    'Contacts': [
      {'name': 'ContactID', 'type': 'STRING'},
      {'name': 'Email', 'type': 'STRING'},
    ],
  };

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  if (_selectedTable != null)
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () {
                        setState(() {
                          _selectedTable = null;
                        });
                      },
                    ),
                  Text(
                    _selectedTable == null ? 'Tables' : 'Fields',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const Divider(),
            // Path Indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Text(
                _selectedTable == null
                    ? _dataset
                    : '$_dataset . $_selectedTable',
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
            ),
            const Divider(),
            // Drilldown List View
            Expanded(
              child: _selectedTable == null
                  ? _buildTablesList()
                  : _buildFieldsList(_selectedTable!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTablesList() {
    return ListView.builder(
      itemCount: _tables.length,
      itemBuilder: (context, index) {
        final tableName = _tables[index];
        return ListTile(
          leading: const Icon(Icons.table_chart_outlined, color: Color(0xFF536DFE)),
          title: Text(tableName),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            setState(() {
              _selectedTable = tableName;
            });
          },
        );
      },
    );
  }

  Widget _buildFieldsList(String tableName) {
    final fieldsList = _fields[tableName] ?? [];

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
              fontFamily: 'Courier',
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.add_box_outlined, color: Color(0xFF536DFE)),
            tooltip: 'Add to Query',
            onPressed: () {
              widget.onFieldSelected(fieldName);
              // Provide visual feedback
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
