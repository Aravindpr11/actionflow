import 'package:flutter/material.dart';

/// Custom Drawer widget for the application
class DrawerWidget extends StatelessWidget {
  final String userName;
  final String userEmail;
  final String userRole;
  final List<DrawerItem> items;
  final VoidCallback? onLogout;

  const DrawerWidget({
    Key? key,
    required this.userName,
    required this.userEmail,
    required this.userRole,
    required this.items,
    this.onLogout,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(userName),
            accountEmail: Text(userEmail),
            currentAccountPicture: const CircleAvatar(
              child: Icon(Icons.person),
            ),
          ),
          ...items.map(
            (item) => ListTile(
              leading: Icon(item.icon),
              title: Text(item.label),
              onTap: item.onTap,
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: onLogout,
          ),
        ],
      ),
    );
  }
}

/// Model for drawer items
class DrawerItem {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  DrawerItem({required this.label, required this.icon, required this.onTap});
}
