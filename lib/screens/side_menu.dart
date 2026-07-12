import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pocket_query/services/auth_service.dart';

class SideMenu extends StatefulWidget {
  const SideMenu({super.key});

  @override
  State<SideMenu> createState() => _SideMenuState();
}

class _SideMenuState extends State<SideMenu> {
  String _selectedProject = "My Data Project";

  // Mock Queries matching Figma specs
  final List<String> _projectQueries = [
    'online_transactions_this_month',
    'accounts_with_no_primary_contact',
  ];

  final List<String> _personalQueries = [
    'large_accounts_queryname',
    'transactions_per_channel',
  ];

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final user = authService.currentUser;
    
    final displayName = user?.displayName ?? "James Angus";
    final displayEmail = user?.email ?? "mygmailadddress@gmail.com";
    final displayInitial = displayName.isNotEmpty ? displayName[0].toUpperCase() : "U";

    return Drawer(
      child: Column(
        children: [
          // Drawer Header matching User Profile
          UserAccountsDrawerHeader(
            currentAccountPicture: CircleAvatar(
              backgroundColor: const Color(0xFF536DFE),
              child: Text(
                displayInitial,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            accountName: Text(
              displayName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            accountEmail: Text(displayEmail),
            decoration: const BoxDecoration(
              color: Colors.transparent,
            ),
          ),
          // Project Selector Dropdown
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ACTIVE GCP PROJECT',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                  ),
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
                      value: _selectedProject,
                      isExpanded: true,
                      items: ["My Data Project", "Prod Billing Project", "Sandbox Lab"]
                          .map((val) => DropdownMenuItem(
                                value: val,
                                child: Text(val),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedProject = val;
                          });
                        }
                      },
                    ),
                  ),
                ),
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
                ..._projectQueries.map((q) => _buildQueryItem(q, Icons.article_outlined)),
                const Divider(),
                _buildSectionHeader('PERSONAL QUERIES'),
                ..._personalQueries.map((q) => _buildQueryItem(q, Icons.lock_outline)),
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

  Widget _buildQueryItem(String name, IconData icon) {
    return ListTile(
      leading: Icon(icon, size: 20),
      title: Text(
        name,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      onTap: () {},
    );
  }
}
