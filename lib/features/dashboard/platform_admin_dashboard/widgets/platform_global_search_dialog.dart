import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/models/platform_setting.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Interactive Command Palette and Global Search dialog for Platform Owners.
class PlatformGlobalSearchDialog extends StatefulWidget {
  final List<Organization> organizations;
  final Map<String, PlatformSetting> platformSettings;
  final void Function(int navIndex, {String? companyFilter}) onNavigate;
  final VoidCallback onAddCompany;
  final VoidCallback onRunDiagnostics;

  const PlatformGlobalSearchDialog({
    super.key,
    required this.organizations,
    required this.platformSettings,
    required this.onNavigate,
    required this.onAddCompany,
    required this.onRunDiagnostics,
  });

  static Future<void> show(
    BuildContext context, {
    required List<Organization> organizations,
    required Map<String, PlatformSetting> platformSettings,
    required void Function(int navIndex, {String? companyFilter}) onNavigate,
    required VoidCallback onAddCompany,
    required VoidCallback onRunDiagnostics,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => PlatformGlobalSearchDialog(
        organizations: organizations,
        platformSettings: platformSettings,
        onNavigate: onNavigate,
        onAddCompany: onAddCompany,
        onRunDiagnostics: onRunDiagnostics,
      ),
    );
  }

  @override
  State<PlatformGlobalSearchDialog> createState() =>
      _PlatformGlobalSearchDialogState();
}

class _PlatformGlobalSearchDialogState
    extends State<PlatformGlobalSearchDialog> {
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _queryController.addListener(() {
      setState(() {
        _query = _queryController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    // 1. Navigation shortcuts
    final navItems = [
      (
        title: 'Platform Overview',
        subtitle: 'System health, identity, and governance summary',
        icon: Icons.dashboard_outlined,
        action: () {
          Navigator.of(context).pop();
          widget.onNavigate(0);
        },
      ),
      (
        title: 'Companies & Tenants',
        subtitle: 'Multi-tenant organizations, admin allocation, and lifecycle',
        icon: Icons.business_outlined,
        action: () {
          Navigator.of(context).pop();
          widget.onNavigate(1);
        },
      ),
      (
        title: 'Platform Security & Governance',
        subtitle: 'Authority verification, RLS diagnostics, and anchor guard',
        icon: Icons.security_outlined,
        action: () {
          Navigator.of(context).pop();
          widget.onNavigate(2);
        },
      ),
      (
        title: 'Global Audit Logs',
        subtitle: 'Immutable audit trail for all platform operations',
        icon: Icons.history_outlined,
        action: () {
          Navigator.of(context).pop();
          widget.onNavigate(3);
        },
      ),
      (
        title: 'Platform Settings',
        subtitle: 'Global parameters, session timeouts, and MFA policies',
        icon: Icons.settings_outlined,
        action: () {
          Navigator.of(context).pop();
          widget.onNavigate(4);
        },
      ),
    ];

    final filteredNav = _query.isEmpty
        ? navItems
        : navItems.where((n) {
            return n.title.toLowerCase().contains(_query) ||
                n.subtitle.toLowerCase().contains(_query);
          }).toList();

    // 2. Action shortcuts
    final actionItems = [
      (
        title: 'Add New Company / Tenant',
        subtitle: 'Provision a new isolated organization',
        icon: Icons.add_business_outlined,
        action: () {
          Navigator.of(context).pop();
          widget.onAddCompany();
        },
      ),
      (
        title: 'Run Security Diagnostics',
        subtitle: 'Execute live database authority and RLS checks',
        icon: Icons.play_arrow_outlined,
        action: () {
          Navigator.of(context).pop();
          widget.onRunDiagnostics();
        },
      ),
    ];

    final filteredActions = _query.isEmpty
        ? actionItems
        : actionItems.where((a) {
            return a.title.toLowerCase().contains(_query) ||
                a.subtitle.toLowerCase().contains(_query);
          }).toList();

    // 3. Filtered Organizations
    final filteredOrgs = _query.isEmpty
        ? widget.organizations.take(5).toList()
        : widget.organizations.where((org) {
            return org.name.toLowerCase().contains(_query) ||
                org.code.toLowerCase().contains(_query) ||
                org.id.toLowerCase().contains(_query);
          }).toList();

    // 4. Filtered Settings
    final filteredSettings = _query.isEmpty
        ? <PlatformSetting>[]
        : widget.platformSettings.values.where((s) {
            return s.key.toLowerCase().contains(_query) ||
                s.category.toLowerCase().contains(_query) ||
                (s.description?.toLowerCase().contains(_query) ?? false);
          }).toList();

    final hasAnyResults =
        filteredNav.isNotEmpty ||
        filteredActions.isNotEmpty ||
        filteredOrgs.isNotEmpty ||
        filteredSettings.isNotEmpty;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Search Input Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      size: 20,
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _queryController,
                        focusNode: _searchFocusNode,
                        autofocus: true,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search companies, settings, navigation, or actions...',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? AppTheme.darkTextHint
                                : AppTheme.lightTextHint,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (_query.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        splashRadius: 16,
                        onPressed: () => _queryController.clear(),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Text(
                        'ESC',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
              ),
              // Results List
              Flexible(
                child: hasAnyResults
                    ? ListView(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shrinkWrap: true,
                        children: [
                          // 1. Companies section
                          if (filteredOrgs.isNotEmpty) ...[
                            _buildSectionHeader(
                              'Companies & Tenants (${filteredOrgs.length})',
                              isDark,
                            ),
                            ...filteredOrgs.map(
                              (org) => ListTile(
                                dense: true,
                                leading: Container(
                                  width: 32,
                                  height: 32,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: org.isSobha
                                        ? Colors.amber.withValues(alpha: 0.15)
                                        : AppTheme.primaryColor.withValues(
                                            alpha: 0.12,
                                          ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    org.isSobha ? Icons.shield : Icons.business,
                                    size: 16,
                                    color: org.isSobha
                                        ? Colors.amber.shade700
                                        : AppTheme.primaryColor,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Text(
                                      org.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF1E293B)
                                            : const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        org.code,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Text(
                                  org.isSobha
                                      ? 'Anchor Tenant • Protected'
                                      : 'Status: ${org.isActive ? 'Active' : 'Inactive'}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? AppTheme.darkTextSecondary
                                        : AppTheme.lightTextSecondary,
                                  ),
                                ),
                                trailing: Icon(
                                  Icons.arrow_forward,
                                  size: 14,
                                  color: isDark
                                      ? AppTheme.darkTextHint
                                      : AppTheme.lightTextHint,
                                ),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  widget.onNavigate(1, companyFilter: org.name);
                                },
                              ),
                            ),
                          ],

                          // 2. Platform Settings section
                          if (filteredSettings.isNotEmpty) ...[
                            _buildSectionHeader(
                              'Platform Settings (${filteredSettings.length})',
                              isDark,
                            ),
                            ...filteredSettings.map(
                              (s) => ListTile(
                                dense: true,
                                leading: Container(
                                  width: 32,
                                  height: 32,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.purple.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(
                                    Icons.tune,
                                    size: 16,
                                    color: Colors.purple,
                                  ),
                                ),
                                title: Text(
                                  s.key,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                subtitle: Text(
                                  s.description ?? 'Category: ${s.category}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? AppTheme.darkTextSecondary
                                        : AppTheme.lightTextSecondary,
                                  ),
                                ),
                                trailing: Icon(
                                  Icons.arrow_forward,
                                  size: 14,
                                  color: isDark
                                      ? AppTheme.darkTextHint
                                      : AppTheme.lightTextHint,
                                ),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  widget.onNavigate(4);
                                },
                              ),
                            ),
                          ],

                          // 3. Navigation section
                          if (filteredNav.isNotEmpty) ...[
                            _buildSectionHeader('Platform Views', isDark),
                            ...filteredNav.map(
                              (n) => ListTile(
                                dense: true,
                                leading: Icon(
                                  n.icon,
                                  size: 18,
                                  color: AppTheme.primaryColor,
                                ),
                                title: Text(
                                  n.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  n.subtitle,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? AppTheme.darkTextSecondary
                                        : AppTheme.lightTextSecondary,
                                  ),
                                ),
                                trailing: Icon(
                                  Icons.subdirectory_arrow_left,
                                  size: 14,
                                  color: isDark
                                      ? AppTheme.darkTextHint
                                      : AppTheme.lightTextHint,
                                ),
                                onTap: n.action,
                              ),
                            ),
                          ],

                          // 4. Actions section
                          if (filteredActions.isNotEmpty) ...[
                            _buildSectionHeader('Platform Actions', isDark),
                            ...filteredActions.map(
                              (a) => ListTile(
                                dense: true,
                                leading: Icon(
                                  a.icon,
                                  size: 18,
                                  color: Colors.green,
                                ),
                                title: Text(
                                  a.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  a.subtitle,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? AppTheme.darkTextSecondary
                                        : AppTheme.lightTextSecondary,
                                  ),
                                ),
                                trailing: Icon(
                                  Icons.arrow_forward,
                                  size: 14,
                                  color: isDark
                                      ? AppTheme.darkTextHint
                                      : AppTheme.lightTextHint,
                                ),
                                onTap: a.action,
                              ),
                            ),
                          ],
                        ],
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(vertical: 36),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 36,
                              color: isDark
                                  ? Colors.grey.shade600
                                  : Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No matching platform records found for "$_query"',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? AppTheme.darkTextSecondary
                                    : AppTheme.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              // Footer
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0B132B)
                      : const Color(0xFFF8FAFC),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(14),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'ActionFlow Platform Command Palette',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? AppTheme.darkTextHint
                              : AppTheme.lightTextHint,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Tier 0 Superadmin Access',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
          color: isDark ? AppTheme.darkTextHint : AppTheme.lightTextSecondary,
        ),
      ),
    );
  }
}
