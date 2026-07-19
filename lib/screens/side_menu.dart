import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pocket_query/services/auth_service.dart';
import 'package:pocket_query/services/bigquery_service.dart';

class SideMenu extends StatefulWidget {
  final Function(String sql, {String? name}) onQuerySelected;

  const SideMenu({super.key, required this.onQuerySelected});

  @override
  State<SideMenu> createState() => _SideMenuState();
}

class _SideMenuState extends State<SideMenu> {
  // Mock Queries matching Figma specs
  final List<String> _projectQueries = [
    'online_transactions_this_month',
    'accounts_with_no_primary_contact',
  ];

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final bigQueryService = context.watch<BigQueryService>();
    
    final user = authService.currentUser;
    final projects = bigQueryService.projects;
    final selectedProject = bigQueryService.selectedProjectId;
    
    final displayName = user?.displayName ?? "James Angus";
    final displayEmail = user?.email ?? "mygmailadddress@gmail.com";
    final displayInitial = displayName.isNotEmpty ? displayName[0].toUpperCase() : "U";

    return Drawer(
      child: Column(
        children: [
          // Compact User Profile Header
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFF536DFE),
                    child: Text(
                      displayInitial,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (displayEmail.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            displayEmail,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          // Project Selector Dropdown
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'ACTIVE GCP PROJECT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (bigQueryService.isLoadingProjects || bigQueryService.isLoadingProjectQueries)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      InkWell(
                        onTap: () => bigQueryService.refreshAll(),
                        child: Row(
                          children: [
                            Icon(Icons.refresh, size: 14, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text(
                              'Refresh',
                              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedProject != null && projects.contains(selectedProject) ? selectedProject : null,
                      isExpanded: true,
                      hint: const Text("Select project..."),
                      items: [
                        ...projects.map((val) => DropdownMenuItem(
                              value: val,
                              child: Text(val, overflow: TextOverflow.ellipsis),
                            )),
                        const DropdownMenuItem(
                          value: '__add_custom__',
                          child: Row(
                            children: [
                              Icon(Icons.add, size: 18, color: Color(0xFF536DFE)),
                              SizedBox(width: 8),
                              Text("Enter Project ID...", style: TextStyle(color: Color(0xFF536DFE), fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val == '__add_custom__') {
                          _showAddProjectDialog(context, bigQueryService);
                        } else if (val != null) {
                          bigQueryService.selectProject(val);
                        }
                      },
                    ),
                  ),
                ),
                if (projects.isEmpty || bigQueryService.projectsError != null)
                  _buildGcpPermissionGuidance(context, bigQueryService),
              ],
            ),
          ),
          const Divider(),
          // Saved Queries list
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildSectionHeader('PROJECT QUERIES'),
                if (bigQueryService.projectQueries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                    child: Text(
                      'No saved queries for this project.',
                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey[500]),
                    ),
                  )
                else
                  ...bigQueryService.projectQueries.map((q) => _buildQueryItem(q, Icons.star_outline)),
                const Divider(),
                _buildSectionHeader('RECENT QUERY HISTORY'),
                if (bigQueryService.isLoadingProjectQueries)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                  )
                else if (bigQueryService.recentQueries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                    child: Text(
                      'No recent query history found.',
                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey[500]),
                    ),
                  )
                else
                  ...bigQueryService.recentQueries.map(
                    (q) => _buildQueryItem(
                      q,
                      Icons.history,
                      onBookmark: () async {
                        await bigQueryService.saveProjectQuery(q);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Query saved to Project Queries!")),
                          );
                        }
                      },
                    ),
                  ),
                const Divider(),
                _buildSectionHeader('PERSONAL QUERIES'),
                if (bigQueryService.personalQueries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                    child: Text(
                      'No personal saved queries.',
                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey[500]),
                    ),
                  )
                else
                  ...bigQueryService.personalQueries.map((q) => _buildQueryItem(q, Icons.lock_outline)),
              ],
            ),
          ),
          const Divider(),
          // Action Buttons: Settings, Sign out, and New Query
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
            onTap: () async {
              await authService.signOut();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildQueryItem(String queryText, IconData icon, {VoidCallback? onBookmark}) {
    final displayName = queryText.split('\n').first.trim();
    return ListTile(
      leading: Icon(icon, size: 20),
      title: Text(
        displayName,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      trailing: onBookmark != null
          ? IconButton(
              icon: const Icon(Icons.star_border, size: 18, color: Color(0xFF536DFE)),
              tooltip: 'Save to Project Queries',
              onPressed: onBookmark,
            )
          : null,
      onTap: () async {
        final bq = context.read<BigQueryService>();
        final sql = await bq.fetchDataformQueryContent(queryText) ?? queryText;
        widget.onQuerySelected(sql, name: displayName);
        if (context.mounted) {
          Navigator.pop(context);
        }
      },
    );
  }

  void _showAddProjectDialog(BuildContext context, BigQueryService bq) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add GCP Project ID'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. my-gcp-project-id',
            labelText: 'Project ID',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                bq.addCustomProject(text);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildGcpPermissionGuidance(BuildContext context, BigQueryService bq) {
    final authService = context.watch<AuthService>();
    final authError = authService.lastAuthError;
    final bqError = bq.projectsError;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bug_report_outlined, color: Colors.amber.shade900, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Diagnostic & Setup Debug Log',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (authError != null) ...[
            const Text(
              'OAuth Sign-In Exception:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.redAccent),
            ),
            const SizedBox(height: 2),
            SelectableText(
              authError,
              style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.redAccent),
            ),
            const SizedBox(height: 8),
          ],
          if (bqError != null) ...[
            const Text(
              'BigQuery API Diagnostics:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepOrange),
            ),
            const SizedBox(height: 2),
            SelectableText(
              bqError,
              style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.deepOrange),
            ),
            const SizedBox(height: 8),
          ],
          const Text(
            'To enable real Google Sign-In on Android Emulator:',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 4),
          const Text(
            'Add this SHA-1 key to GCP Console ➔ APIs & Services ➔ Credentials ➔ OAuth 2.0 Client ID (Android):',
            style: TextStyle(fontSize: 11, color: Colors.black87),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SelectableText(
                  'Package Name: com.pocketquery.pocket_query',
                  style: TextStyle(fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 2),
                SelectableText(
                  'SHA-1: 90:1B:C6:35:16:5E:54:37:97:3E:14:7D:96:83:F7:37:2A:C7:BA:0D',
                  style: TextStyle(fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showAddProjectDialog(context, bq),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Enter Project ID Manually', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF536DFE),
                side: const BorderSide(color: Color(0xFF536DFE)),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
