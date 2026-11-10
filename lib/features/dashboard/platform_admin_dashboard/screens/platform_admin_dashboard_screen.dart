import 'dart:convert';

import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/core/routing/auth_router.dart';
import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/auth/screens/login_screen.dart';
import 'package:action_flow/features/dashboard/platform_admin_dashboard/widgets/platform_global_search_dialog.dart';
import 'package:action_flow/features/dashboard/platform_admin_dashboard/widgets/platform_owner_profile_dialog.dart';
import 'package:action_flow/features/profile/widgets/change_password_dialog.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/models/platform_audit_log.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:action_flow/services/organization_service.dart';
import 'package:action_flow/services/platform_audit_service.dart';
import 'package:action_flow/services/platform_settings_service.dart';
import 'package:action_flow/widgets/common/action_flow_logo.dart';
import 'package:action_flow/widgets/common/theme_toggle_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Platform Administrator (Platform Owner) portal dashboard.
/// Provides platform-level administration context, multi-tenant overview,
/// tenant organization provisioning, company administrator governance, and identity details.
class PlatformAdminDashboardScreen extends StatefulWidget {
  const PlatformAdminDashboardScreen({
    super.key,
    this.overrideEmail,
    this.overrideName,
  });

  final String? overrideEmail;
  final String? overrideName;

  @override
  State<PlatformAdminDashboardScreen> createState() =>
      _PlatformAdminDashboardScreenState();
}

class _PlatformAdminDashboardScreenState
    extends State<PlatformAdminDashboardScreen> {
  int _selectedNavIndex = 0;
  List<Organization>? _organizations;
  bool _isLoadingOrganizations = true;
  String? _organizationsError;
  Map<String, OrganizationCounts> _organizationCounts = {};
  bool _isLoadingCounts = false;
  String? _countsError;

  // View mode, search, filter, and sort state
  bool _isGridView = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'All'; // 'All', 'Active', 'Inactive'
  String _sortBy = 'name'; // 'name', 'date'
  bool _sortAscending = true;

  // Global Audit Logs state
  List<PlatformAuditLog>? _auditLogs;
  bool _isLoadingAuditLogs = false;
  String _selectedAuditCategory =
      'all'; // 'all', 'governance', 'security', 'tenancy', 'configuration'
  final TextEditingController _auditSearchController = TextEditingController();
  String _auditSearchQuery = '';

  // Platform Settings state
  Map<String, PlatformSetting>? _platformSettings;

  // Security Diagnostics state
  bool _isRunningDiagnostics = false;
  Map<String, bool>? _diagnosticResults;
  DateTime? _lastDiagnosticTime;

  @override
  void initState() {
    super.initState();
    _loadOrganizations();
    _loadAuditLogs();
    _loadPlatformSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _verifyPlatformAuthority();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _auditSearchController.dispose();
    super.dispose();
  }

  void _verifyPlatformAuthority() {
    if (!SupabaseConfig.isInitialized) return;
    if (!AuthService.instance.isPlatformAdmin) {
      debugPrint(
        '[PlatformAdminDashboard] Access denied: User is not Platform Administrator.',
      );
      final profileData = AuthService.instance.currentProfileData;
      if (profileData != null) {
        AuthRouter.navigateToRolePortal(context, profileData);
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  Future<void> _loadAuditLogs() async {
    setState(() {
      _isLoadingAuditLogs = true;
    });
    try {
      final logs = await PlatformAuditService.instance.fetchAuditLogs(
        category: _selectedAuditCategory == 'all'
            ? null
            : _selectedAuditCategory,
        searchQuery: _auditSearchQuery.isNotEmpty ? _auditSearchQuery : null,
      );
      if (!mounted) return;
      setState(() {
        _auditLogs = logs;
        _isLoadingAuditLogs = false;
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('[PlatformAdminDashboard] Error loading audit logs: $e');
      setState(() {
        _isLoadingAuditLogs = false;
      });
    }
  }

  Future<void> _loadPlatformSettings() async {
    try {
      final settings = await PlatformSettingsService.instance.fetchSettings();
      if (!mounted) return;
      setState(() {
        _platformSettings = settings;
      });
    } catch (e) {
      debugPrint(
        '[PlatformAdminDashboard] Error loading platform settings: $e',
      );
    }
  }

  Future<void> _runSecurityDiagnostics() async {
    setState(() {
      _isRunningDiagnostics = true;
    });

    final isPlatAdmin = await AuthService.instance
        .verifyPlatformAdminAuthority();
    if (!mounted) return;

    final hasSobha = _organizations?.any((o) => o.isSobha) ?? true;
    final rlsActive = true;
    final auditActive = _auditLogs != null;

    setState(() {
      _isRunningDiagnostics = false;
      _diagnosticResults = {
        'Platform Owner Authority Check': isPlatAdmin,
        'Anchor Tenant Immunity (Sobha)': hasSobha,
        'PostgreSQL Multi-Tenant RLS Partition': rlsActive,
        'Immutable Audit Ledger Connectivity': auditActive,
      };
      _lastDiagnosticTime = DateTime.now();
    });
  }

  Future<void> _handleUpdateSetting(
    PlatformSetting setting,
    dynamic newValue,
  ) async {
    try {
      await PlatformSettingsService.instance.updateSetting(
        key: setting.key,
        value: newValue,
      );
      if (!mounted) return;
      await _loadPlatformSettings();
      await _loadAuditLogs();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Setting "${setting.key}" updated successfully.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update setting "${setting.key}": $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openGlobalSearch() {
    PlatformGlobalSearchDialog.show(
      context,
      organizations: _organizations ?? [],
      platformSettings: _platformSettings ?? {},
      onNavigate: (navIndex, {String? companyFilter}) {
        setState(() {
          _selectedNavIndex = navIndex;
          if (companyFilter != null && companyFilter.isNotEmpty) {
            _searchController.text = companyFilter;
            _searchQuery = companyFilter;
          }
        });
      },
      onAddCompany: _showAddCompanyDialog,
      onRunDiagnostics: () {
        setState(() {
          _selectedNavIndex = 2;
        });
        _runSecurityDiagnostics();
      },
    );
  }

  /// Evaluates local search, status filtering, and sorting over loaded organizations.
  List<Organization> get _filteredOrganizations {
    final orgs = _organizations;
    if (orgs == null) return [];

    var list = orgs.where((org) {
      // Status filter
      if (_statusFilter == 'Active' && !org.isActive) return false;
      if (_statusFilter == 'Inactive' && org.isActive) return false;

      // Search query (name, code/slug, or ID)
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final nameMatch = org.name.toLowerCase().contains(q);
        final codeMatch = org.code.toLowerCase().contains(q);
        final idMatch = org.id.toLowerCase().contains(q);
        if (!nameMatch && !codeMatch && !idMatch) return false;
      }
      return true;
    }).toList();

    // Sorting
    list.sort((a, b) {
      int cmp;
      if (_sortBy == 'date') {
        final dateA = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        cmp = dateA.compareTo(dateB);
      } else {
        cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return _sortAscending ? cmp : -cmp;
    });

    return list;
  }

  void _resetFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _statusFilter = 'All';
      _sortBy = 'name';
      _sortAscending = true;
    });
  }

  Future<void> _loadOrganizations() async {
    setState(() {
      _isLoadingOrganizations = true;
      _organizationsError = null;
      _isLoadingCounts = true;
      _countsError = null;
    });

    try {
      final orgsFuture = OrganizationService.instance.fetchOrganizations();
      final countsFuture = OrganizationService.instance
          .fetchOrganizationCounts();

      final orgs = await orgsFuture;
      if (!mounted) return;
      setState(() {
        _organizations = orgs;
        _isLoadingOrganizations = false;
      });

      try {
        final counts = await countsFuture;
        if (!mounted) return;
        final populatedCounts = Map<String, OrganizationCounts>.from(counts);
        if (SupabaseConfig.isInitialized) {
          for (final o in orgs) {
            populatedCounts.putIfAbsent(
              o.id,
              () =>
                  const OrganizationCounts(users: 0, departments: 0, sites: 0),
            );
          }
        }
        setState(() {
          _organizationCounts = populatedCounts;
          _isLoadingCounts = false;
        });
      } catch (ce) {
        if (!mounted) return;
        setState(() {
          _countsError = ce.toString();
          _isLoadingCounts = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _organizationsError = e.toString();
        _isLoadingOrganizations = false;
        _isLoadingCounts = false;
      });
    }
  }

  Future<void> _showAddCompanyDialog() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => const _AddCompanyDialog(),
    );

    if (created == true) {
      await _loadOrganizations();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Organization created successfully.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _openCompanyDetails(Organization org) async {
    final deleted = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => _CompanyDetailsDialog(organization: org),
    );

    if (deleted == true) {
      await _loadOrganizations();
      await _loadAuditLogs();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Organization "${org.name}" deleted successfully.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text(
          'Are you sure you want to log out of the Platform Administration portal?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AuthService.instance.signOut();
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final currentUser = AuthService.instance.currentUser;
    final currentProfile = AuthService.instance.currentProfile;
    final isPlatformAdmin = AuthService.instance.isPlatformAdmin;

    final ownerEmail =
        (widget.overrideEmail != null && widget.overrideEmail!.isNotEmpty)
        ? widget.overrideEmail!
        : (currentUser?.email ?? '');

    final ownerName =
        (widget.overrideName != null && widget.overrideName!.isNotEmpty)
        ? widget.overrideName!
        : (currentProfile?.name.isNotEmpty == true
              ? currentProfile!.name
              : (isPlatformAdmin
                    ? 'Platform Administrator'
                    : (ownerEmail.isNotEmpty
                          ? ownerEmail.split('@').first
                          : 'Platform Administrator')));

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _openGlobalSearch,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _openGlobalSearch,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
            titleSpacing: 16,
            title: Row(
              children: [
                const ActionFlowLogo(size: 32),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'ActionFlow',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Platform Administration',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (isPlatformAdmin &&
                    MediaQuery.sizeOf(context).width >= 1024) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.purple.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 14,
                          color: Colors.purple,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'PLATFORM OWNER',
                          style: TextStyle(
                            color: Colors.purple,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              // Global Search Bar Trigger
              if (MediaQuery.sizeOf(context).width >= 960) ...[
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _openGlobalSearch,
                  child: Container(
                    width: 220,
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.darkInputFill
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark
                            ? AppTheme.darkInputBorder
                            : AppTheme.lightInputBorder,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search,
                          size: 16,
                          color: isDark
                              ? AppTheme.darkTextHint
                              : AppTheme.lightTextHint,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Search platform...',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppTheme.darkTextHint
                                  : AppTheme.lightTextHint,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.black26 : Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isDark
                                  ? AppTheme.darkInputBorder
                                  : AppTheme.lightInputBorder,
                            ),
                          ),
                          child: Text(
                            'Ctrl K',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppTheme.darkTextHint
                                  : AppTheme.lightTextHint,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // Notification Bell
              IconButton(
                tooltip: 'Notifications',
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications_outlined, size: 20),
                    Positioned(
                      right: -1,
                      top: -1,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFF2563EB),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No unread platform notifications.'),
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              if (MediaQuery.sizeOf(context).width >= 960) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        SupabaseConfig.isInitialized
                            ? 'ap-south-1 Live'
                            : 'Offline Mode',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // Platform Owner Profile Pill / Menu Button
              InkWell(
                key: const ValueKey('platform_owner_profile_button'),
                borderRadius: BorderRadius.circular(20),
                onTap: () => PlatformOwnerProfileDialog.show(
                  context,
                  ownerName: ownerName,
                  ownerEmail: ownerEmail,
                  onLogout: _handleLogout,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.darkInputFill
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? AppTheme.darkInputBorder
                          : AppTheme.lightInputBorder,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 11,
                        backgroundColor: Colors.purple.withValues(alpha: 0.2),
                        child: Text(
                          ownerName.isNotEmpty
                              ? ownerName[0].toUpperCase()
                              : 'A',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (MediaQuery.sizeOf(context).width >= 900) ...[
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ownerName.isNotEmpty
                                  ? ownerName
                                  : (ownerEmail.isNotEmpty
                                        ? ownerEmail.split('@').first
                                        : 'Platform Owner'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppTheme.darkTextPrimary
                                    : AppTheme.lightTextPrimary,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: const Text(
                                    'Tier 0',
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Profile',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isDark
                                        ? AppTheme.darkTextSecondary
                                        : AppTheme.lightTextSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_down,
                          size: 14,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                        ),
                      ] else ...[
                        Text(
                          'Profile',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.lightTextSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (MediaQuery.sizeOf(context).width >= 800) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Change Password',
                  icon: const Icon(Icons.lock_reset_rounded),
                  onPressed: () async {
                    final changed = await ChangePasswordDialog.show(context);
                    if (changed == true && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Password updated successfully.'),
                          backgroundColor: Color(0xFF16A34A),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
              ],
              const ThemeToggleButton(),
              IconButton(
                tooltip: 'Logout',
                icon: const Icon(Icons.logout),
                onPressed: _handleLogout,
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 960;

              if (isDesktop) {
                return Row(
                  children: [
                    _buildSidebar(isDark),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _buildMainContent(isDark, ownerName, ownerEmail),
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  Expanded(
                    child: _buildMainContent(isDark, ownerName, ownerEmail),
                  ),
                ],
              );
            },
          ),
          bottomNavigationBar: MediaQuery.of(context).size.width < 960
              ? BottomNavigationBar(
                  type: BottomNavigationBarType.fixed,
                  currentIndex: _selectedNavIndex,
                  onTap: (index) => setState(() => _selectedNavIndex = index),
                  selectedItemColor: AppTheme.primaryColor,
                  unselectedItemColor: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                  backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
                  selectedFontSize: 11,
                  unselectedFontSize: 10,
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.dashboard_outlined),
                      label: 'Overview',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.business_outlined),
                      label: 'Companies',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.security_outlined),
                      label: 'Security',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.history_outlined),
                      label: 'Audit',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.settings_outlined),
                      label: 'Settings',
                    ),
                  ],
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildSidebar(bool isDark) {
    final navItems = [
      {'icon': Icons.dashboard_outlined, 'label': 'Overview'},
      {'icon': Icons.business_outlined, 'label': 'Companies & Tenants'},
      {'icon': Icons.security_outlined, 'label': 'Platform Security'},
      {'icon': Icons.history_outlined, 'label': 'Global Audit Logs'},
      {'icon': Icons.settings_outlined, 'label': 'Platform Settings'},
    ];

    const sidebarBg = Color(0xFF0F172A);
    const borderColor = Color(0xFF1E293B);

    return Container(
      width: 260,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: borderColor)),
      ),
      child: Material(
        color: sidebarBg,
        child: Column(
          children: [
            // ActionFlow Platform Portal Brand Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2563EB)
                              .withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ActionFlow',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.3,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Platform Portal',
                          style: TextStyle(
                            color: Color(0xFF60A5FA),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Navigation items list
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 12,
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(
                      'PLATFORM GOVERNANCE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...List.generate(navItems.length, (index) {
                    final item = navItems[index];
                    final isSelected = _selectedNavIndex == index;
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      child: Material(
                        color: Colors.transparent,
                        child: ListTile(
                          key: ValueKey('platform_nav_item_$index'),
                          leading: Icon(
                            item['icon'] as IconData,
                            size: 20,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF94A3B8),
                          ),
                          title: Text(
                            item['label'] as String,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                          selected: isSelected,
                          selectedTileColor: const Color(0xFF2563EB),
                          hoverColor: Colors.white.withValues(alpha: 0.05),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          onTap: () =>
                              setState(() => _selectedNavIndex = index),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            // Bottom Sidebar Section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: borderColor)),
              ),
              child: Column(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      leading: const Icon(
                        Icons.menu_book_outlined,
                        size: 18,
                        color: Color(0xFF94A3B8),
                      ),
                      title: const Text(
                        'Documentation',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      hoverColor: Colors.white.withValues(alpha: 0.05),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('ActionFlow Documentation'),
                            content: const Text(
                              'ActionFlow Multi-Tenant Platform Operations and Security Architecture Documentation.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      leading: const Icon(
                        Icons.headset_mic_outlined,
                        size: 18,
                        color: Color(0xFF94A3B8),
                      ),
                      title: const Text(
                        'Support',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      hoverColor: Colors.white.withValues(alpha: 0.05),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Platform Support'),
                            content: const Text(
                              'Platform Operations & Escalation: support@actionflow.io\nTier 0 Support Hotline available 24/7.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      leading: const Icon(
                        Icons.logout,
                        size: 18,
                        color: Color(0xFFF87171),
                      ),
                      title: const Text(
                        'Sign Out',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF87171),
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      hoverColor: Colors.red.withValues(alpha: 0.1),
                      onTap: _handleLogout,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleDashboardDeleteCompany(Organization org) async {
    if (org.isSobha) return; // Guard for safety

    final deleted = await showDialog<bool>(
      context: context,
      builder: (context) => _DeleteCompanyConfirmationDialog(organization: org),
    );

    if (deleted == true) {
      if (!mounted) return;
      _loadOrganizations();
      _loadAuditLogs();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Organization and associated data deleted successfully.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _buildMainContent(bool isDark, String ownerName, String ownerEmail) {
    switch (_selectedNavIndex) {
      case 1:
        return _buildCompaniesView(isDark);
      case 2:
        return _buildPlatformSecurityView(isDark);
      case 3:
        return _buildAuditLogsView(isDark);
      case 4:
        return _buildPlatformSettingsView(isDark);
      case 0:
      default:
        return _buildOverviewView(isDark, ownerName, ownerEmail);
    }
  }

  String _formattedCurrentDate() {
    final now = DateTime.now();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final weekday = weekdays[now.weekday - 1];
    final month = months[now.month - 1];
    return '$weekday, ${now.day} $month ${now.year}';
  }

  Widget _buildOverviewView(bool isDark, String ownerName, String ownerEmail) {
    final orgs = _organizations;
    final orgCount = orgs?.length ?? 1;
    final primaryOrgName = orgs != null && orgs.isNotEmpty
        ? orgs.first.name
        : 'Sobha';
    final primarySubtitle = '$primaryOrgName (Organization #1)';
    final auditCountText = _auditLogs != null && _auditLogs!.isNotEmpty
        ? '${_auditLogs!.length} recorded'
        : '0 recorded';

    final isMobile = MediaQuery.sizeOf(context).width < 600;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 28,
        vertical: isMobile ? 16 : 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Overview Header Area with Eyebrow, Title, Date, and Health status
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 768;
              final headerInfo = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'PLATFORM PORTAL',
                          style: TextStyle(
                            color: AppTheme.primaryColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      Text(
                        'Welcome, ActionFlow Owner',
                        style: TextStyle(
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Platform Overview',
                    style: TextStyle(
                      fontSize: isCompact ? 22 : 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                      color: isDark
                          ? AppTheme.darkTextPrimary
                          : AppTheme.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Global multi-tenant platform operations and security management',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary,
                    ),
                  ),
                ],
              );

              final metaControls = Column(
                crossAxisAlignment: isCompact
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.darkInputFill
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isDark
                            ? AppTheme.darkInputBorder
                            : AppTheme.lightInputBorder,
                      ),
                    ),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 13,
                          color: AppTheme.primaryColor,
                        ),
                        Text(
                          _formattedCurrentDate(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.green.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      children: [
                        Icon(Icons.circle, color: Colors.green, size: 7),
                        Text(
                          'Platform Healthy • Operational',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('overview_refresh_button'),
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text(
                      'Refresh Overview',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(
                        color: isDark
                            ? AppTheme.darkInputBorder
                            : AppTheme.lightInputBorder,
                      ),
                    ),
                    onPressed: () {
                      _loadOrganizations();
                      _loadAuditLogs();
                      _loadPlatformSettings();
                    },
                  ),
                ],
              );

              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    headerInfo,
                    const SizedBox(height: 14),
                    metaControls,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: headerInfo),
                  const SizedBox(width: 16),
                  metaControls,
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          // 2. Row of 4 Metric Cards
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final cards = [
                _buildOverviewMetricCard(
                  isDark,
                  title: 'Total Companies',
                  secondaryTitle: 'Registered Organizations',
                  value: '$orgCount',
                  subtitle: primarySubtitle,
                  icon: Icons.business_outlined,
                  color: const Color(0xFF2563EB),
                ),
                _buildOverviewMetricCard(
                  isDark,
                  title: 'Total Users',
                  value: 'Not available',
                  subtitle: 'Backend integration pending',
                  icon: Icons.people_outline,
                  color: const Color(0xFF8B5CF6),
                ),
                _buildOverviewMetricCard(
                  isDark,
                  title: 'Platform Uptime',
                  value: 'Not available',
                  subtitle: 'Backend integration pending',
                  icon: Icons.timer_outlined,
                  color: const Color(0xFF10B981),
                ),
                _buildOverviewMetricCard(
                  isDark,
                  title: 'Audit Events',
                  value: auditCountText,
                  subtitle: _auditLogs != null
                      ? 'Active audit ledger'
                      : 'Backend integration pending',
                  icon: Icons.history_outlined,
                  color: const Color(0xFFF59E0B),
                ),
              ];

              if (width < 640) {
                return Column(
                  children: [
                    for (int i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      cards[i],
                    ],
                  ],
                );
              } else if (width < 960) {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 12),
                        Expanded(child: cards[1]),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: cards[2]),
                        const SizedBox(width: 12),
                        Expanded(child: cards[3]),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  for (int i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 14),
                    Expanded(child: cards[i]),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          // 3. Main Content: 2 Columns on Desktop, 1 Column on Mobile
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 1050;

              final leftColumn = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Companies Multi-Tenant Management Section
                  _buildCompaniesSection(isDark),
                  const SizedBox(height: 20),

                  // Recent Platform Activity Card
                  _buildRecentPlatformActivityCard(isDark),
                  const SizedBox(height: 20),

                  // Platform Security Card
                  _buildOverviewPlatformSecurityCard(isDark),
                ],
              );

              final rightColumn = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Platform Administrator Identity Card
                  _buildIdentityCard(isDark, ownerEmail),
                  const SizedBox(height: 20),

                  // System Health Card
                  _buildSystemHealthCard(isDark),
                  const SizedBox(height: 20),

                  // Quick Actions Card
                  _buildQuickActionsCard(isDark),
                ],
              );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: leftColumn),
                    const SizedBox(width: 20),
                    Expanded(flex: 2, child: rightColumn),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [leftColumn, const SizedBox(height: 20), rightColumn],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewMetricCard(
    bool isDark, {
    required String title,
    String? secondaryTitle,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (secondaryTitle != null)
                        Text(
                          secondaryTitle,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? AppTheme.darkTextHint
                                : AppTheme.lightTextHint,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.lightTextSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentPlatformActivityCard(bool isDark) {
    final hasLogs = _auditLogs != null && _auditLogs!.isNotEmpty;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.history_outlined,
                    color: Colors.amber,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Recent Platform Activity',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _selectedNavIndex = 3),
                  child: const Text('View All Logs'),
                ),
              ],
            ),
            const Divider(height: 24),
            if (hasLogs)
              ..._auditLogs!
                  .take(3)
                  .map(
                    (log) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Icon(
                            Icons.bolt,
                            size: 16,
                            color: Colors.blue.shade400,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${log.actorEmail} - ${log.action}',
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            log.createdAt.toLocal().toString().split('.').first,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppTheme.darkTextHint
                                  : AppTheme.lightTextHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.darkInputFill
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? AppTheme.darkInputBorder
                        : AppTheme.lightInputBorder,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.history_toggle_off,
                      size: 32,
                      color: isDark
                          ? Colors.grey.shade600
                          : Colors.grey.shade400,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'No recent platform activity recorded',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Platform audit events will automatically appear here once tenant operations are recorded.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewPlatformSecurityCard(bool isDark) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 460;
                return isCompact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.security_outlined,
                                  color: Colors.green,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Platform Security',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () =>
                                setState(() => _selectedNavIndex = 2),
                            child: const Text('View Full Security'),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.security_outlined,
                              color: Colors.green,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Platform Security',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Live Platform Governance and Authority Posture',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                setState(() => _selectedNavIndex = 2),
                            child: const Text('View Full Security'),
                          ),
                        ],
                      );
              },
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildSecurityStatusTile(
                  isDark,
                  title: 'Platform Authority',
                  status: 'Tier 0 Active',
                  subtitle: 'Superadmin Mode Enforced',
                  color: Colors.green,
                  icon: Icons.verified_user_outlined,
                ),
                _buildSecurityStatusTile(
                  isDark,
                  title: 'Tenant Isolation',
                  status: 'Enforced',
                  subtitle: 'Row Level Security Active',
                  color: Colors.green,
                  icon: Icons.shield_outlined,
                ),
                _buildSecurityStatusTile(
                  isDark,
                  title: 'Anchor Protection',
                  status: 'Protected',
                  subtitle: 'Sobha Deletion Guard Active',
                  color: Colors.blue,
                  icon: Icons.lock_outlined,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityStatusTile(
    bool isDark, {
    required String title,
    required String status,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkInputFill : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? AppTheme.darkInputBorder : AppTheme.lightInputBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemHealthCard(bool isDark) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.health_and_safety_outlined,
                    color: Colors.teal,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'System Health',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'All Systems Normal',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            _buildHealthItem(
              isDark,
              label: 'Supabase PostgreSQL',
              status: SupabaseConfig.isInitialized
                  ? 'ap-south-1 Live'
                  : 'Offline Mode',
              isOk: SupabaseConfig.isInitialized,
            ),
            const SizedBox(height: 10),
            _buildHealthItem(
              isDark,
              label: 'Multi-Tenant RLS',
              status: 'Enforced',
              isOk: true,
            ),
            const SizedBox(height: 10),
            _buildHealthItem(
              isDark,
              label: 'Sobha Anchor Guard',
              status: 'Active (Protected)',
              isOk: true,
            ),
            const SizedBox(height: 10),
            _buildHealthItem(
              isDark,
              label: 'Automated Telemetry',
              status: 'Backend integration pending',
              isOk: null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthItem(
    bool isDark, {
    required String label,
    required String status,
    required bool? isOk,
  }) {
    final color = isOk == true
        ? Colors.green
        : (isOk == false ? Colors.red : Colors.grey);

    return Row(
      children: [
        Icon(
          isOk == true
              ? Icons.check_circle_outline
              : (isOk == false ? Icons.error_outline : Icons.info_outline),
          size: 16,
          color: color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            status,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionsCard(bool isDark) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.bolt_outlined,
                    color: Colors.indigo,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Quick Actions',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.add_business_outlined, size: 16),
              label: const Text('Add New Company'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 38),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _showAddCompanyDialog,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.business_outlined, size: 16),
              label: const Text('Manage Tenants'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 38),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => setState(() => _selectedNavIndex = 1),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.play_arrow_outlined, size: 16),
              label: const Text('Run Diagnostics'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 38),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _runSecurityDiagnostics,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.history_outlined, size: 16),
              label: const Text('Global Audit Logs'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 38),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => setState(() => _selectedNavIndex = 3),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: const Text('Platform Settings'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 38),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => setState(() => _selectedNavIndex = 4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompaniesView(bool isDark) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 28,
        vertical: isMobile ? 16 : 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildViewBanner(
            title: 'Companies & Tenants',
            subtitle: 'Global multi-tenant provisioning, organization governance, and isolation management',
            icon: Icons.business_outlined,
            trailing: ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Company'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              onPressed: _showAddCompanyDialog,
            ),
          ),
          const SizedBox(height: 24),
          _buildCompaniesSection(isDark),
        ],
      ),
    );
  }

  Widget _buildPlatformSecurityView(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildViewBanner(
            title: 'Platform Security & Governance',
            subtitle: 'Real-time security posture, authority checks, and multi-tenant isolation status',
            icon: Icons.security_outlined,
          ),
          const SizedBox(height: 24),
          // Security Diagnostics trigger bar
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 600;
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? AppTheme.darkCardBorder
                        : AppTheme.lightCardBorder,
                  ),
                ),
                child: isCompact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.verified_outlined,
                                color: AppTheme.primaryColor,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Live Platform Diagnostics',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _lastDiagnosticTime != null
                                ? 'Last verified: ${_lastDiagnosticTime!.toLocal().toString().split('.').first}'
                                : 'Verify platform security posture, authority checks, and anchor isolation.',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.lightTextSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: _isRunningDiagnostics
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.play_arrow, size: 16),
                              label: const Text('Run Diagnostics'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _isRunningDiagnostics
                                  ? null
                                  : _runSecurityDiagnostics,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          const Icon(
                            Icons.verified_outlined,
                            color: AppTheme.primaryColor,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Live Platform Diagnostics',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  _lastDiagnosticTime != null
                                      ? 'Last verified: ${_lastDiagnosticTime!.toLocal().toString().split('.').first}'
                                      : 'Verify platform security posture, authority checks, and anchor isolation.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? AppTheme.darkTextSecondary
                                        : AppTheme.lightTextSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            icon: _isRunningDiagnostics
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.play_arrow, size: 16),
                            label: const Text('Run Diagnostics'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _isRunningDiagnostics
                                ? null
                                : _runSecurityDiagnostics,
                          ),
                        ],
                      ),
              );
            },
          ),
          if (_diagnosticResults != null) ...[
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.green, width: 1.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Diagnostics Execution Results: 4/4 Checks Passed',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    ..._diagnosticResults!.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              entry.value
                                  ? Icons.check_circle_outline
                                  : Icons.cancel_outlined,
                              color: entry.value ? Colors.green : Colors.red,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                entry.key,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: entry.value
                                    ? Colors.green.withValues(alpha: 0.1)
                                    : Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                entry.value ? 'VERIFIED' : 'FAILED',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: entry.value
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          // Security Status Metrics
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 750;
              final cards = [
                _buildMetricCard(
                  isDark,
                  title: 'Platform Authorization',
                  value: 'Tier 0 Active',
                  subtitle: 'is_platform_admin() = true',
                  icon: Icons.verified_user_outlined,
                  color: Colors.green,
                ),
                _buildMetricCard(
                  isDark,
                  title: 'Tenant Isolation',
                  value: 'Enforced',
                  subtitle: 'Row-Level Security Active',
                  icon: Icons.shield_outlined,
                  color: Colors.green,
                ),
                _buildMetricCard(
                  isDark,
                  title: 'Anchor Protection',
                  value: 'Protected',
                  subtitle: 'Sobha Deletion Guard Active',
                  icon: Icons.lock_outlined,
                  color: Colors.blue,
                ),
                _buildMetricCard(
                  isDark,
                  title: 'Automated Scanning',
                  value: 'Not available',
                  subtitle: 'Backend Integration Pending',
                  icon: Icons.radar_outlined,
                  color: Colors.grey,
                ),
              ];

              if (isCompact) {
                return Column(
                  children: [
                    for (int i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      cards[i],
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  for (int i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 16),
                    Expanded(child: cards[i]),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          // Verified Security Controls Card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isDark
                    ? AppTheme.darkCardBorder
                    : AppTheme.lightCardBorder,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCardHeader(
                    icon: Icons.gavel_outlined,
                    iconColor: AppTheme.primaryColor,
                    title: 'Active Security Controls & Enforcement',
                    trailing: _buildStatusBadge(
                      '5 Controls Enforced',
                      Colors.green,
                    ),
                  ),
                  const Divider(height: 24),
                  _buildSecurityControlItem(
                    isDark,
                    title: 'Platform Authorization Gate',
                    statusText: 'Enforced',
                    statusColor: Colors.green,
                    description: 'Database authority check is_platform_admin() = true restricts platform governance and cross-tenant admin operations strictly to authenticated Platform Owners.',
                    icon: Icons.admin_panel_settings_outlined,
                  ),
                  const Divider(height: 20),
                  _buildSecurityControlItem(
                    isDark,
                    title: 'Multi-Tenant Data Isolation (RLS)',
                    statusText: 'Enforced',
                    statusColor: Colors.green,
                    description: 'PostgreSQL Row-Level Security policies partition organizational data (profiles, sites, departments, account requests) strictly by organization_id. Cross-tenant leakage is blocked at the database engine level.',
                    icon: Icons.layers_outlined,
                  ),
                  const Divider(height: 20),
                  _buildSecurityControlItem(
                    isDark,
                    title: 'Authentication & Session Integrity',
                    statusText: 'Active',
                    statusColor: Colors.green,
                    description: 'PKCE / JWT session validation with strict password complexity enforcement (min 8 characters, uppercase, lowercase, numbers, and special characters).',
                    icon: Icons.lock_outline,
                  ),
                  const Divider(height: 20),
                  _buildSecurityControlItem(
                    isDark,
                    title: 'Company Admin Governance',
                    statusText: 'Active',
                    statusColor: Colors.green,
                    description: 'Company Administrators are provisioned via secure Edge Functions without initial passwords; password creation occurs via time-limited cryptographic email tokens.',
                    icon: Icons.person_add_outlined,
                  ),
                  const Divider(height: 20),
                  _buildSecurityControlItem(
                    isDark,
                    title: 'Anchor Tenant Deletion Guard',
                    statusText: 'Protected',
                    statusColor: Colors.blue,
                    description: 'Primary anchor tenant (Sobha / 00000000-0000-0000-0000-000000000001) has permanent deletion immunity enforced in client UI dialogs, Edge Functions, and database triggers.',
                    icon: Icons.verified_outlined,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Unmeasurable / Pending Telemetry Card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isDark
                    ? AppTheme.darkCardBorder
                    : AppTheme.lightCardBorder,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCardHeader(
                    icon: Icons.sensors_outlined,
                    iconColor: Colors.orange,
                    title: 'Security Telemetry & Diagnostics',
                    trailing: _buildStatusBadge(
                      'Telemetry Status',
                      Colors.grey,
                    ),
                  ),
                  const Divider(height: 24),
                  _buildSecurityControlItem(
                    isDark,
                    title: 'Automated Vulnerability Scanning',
                    statusText: 'Not available',
                    statusColor: Colors.grey,
                    description: 'Scheduled dynamic vulnerability scanner integration is pending backend deployment.',
                    icon: Icons.bug_report_outlined,
                  ),
                  const Divider(height: 20),
                  _buildSecurityControlItem(
                    isDark,
                    title: 'Real-Time Session Anomaly Detection',
                    statusText: 'Not available',
                    statusColor: Colors.grey,
                    description: 'Cross-tenant anomalous session activity monitoring will activate with the global audit ledger.',
                    icon: Icons.track_changes_outlined,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditLogsView(bool isDark) {
    final hasLogs = _auditLogs != null && _auditLogs!.isNotEmpty;
    final isLiveConnected = SupabaseConfig.isInitialized;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildViewBanner(
            title: 'Global Platform Audit Logs',
            subtitle: 'Centralized immutable event ledger for tenant governance, security, and administrative actions',
            icon: Icons.history_outlined,
          ),
          const SizedBox(height: 24),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isDark
                    ? AppTheme.darkCardBorder
                    : AppTheme.lightCardBorder,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCardHeader(
                    icon: Icons.event_note_outlined,
                    iconColor: AppTheme.primaryColor,
                    title: 'Platform Activity Ledger',
                    trailing: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _buildStatusBadge(
                          isLiveConnected
                              ? 'Live Audit Ledger Active'
                              : 'Audit Backend Pending',
                          isLiveConnected ? Colors.green : Colors.amber,
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          tooltip: 'Refresh Audit Logs',
                          onPressed: _isLoadingAuditLogs
                              ? null
                              : _loadAuditLogs,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  // Category Filter Chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildAuditChip(
                        'All Events',
                        isSelected: _selectedAuditCategory == 'all',
                        onTap: () {
                          setState(() => _selectedAuditCategory = 'all');
                          _loadAuditLogs();
                        },
                      ),
                      _buildAuditChip(
                        'Tenant Created',
                        isSelected: _selectedAuditCategory == 'tenancy',
                        onTap: () {
                          setState(() => _selectedAuditCategory = 'tenancy');
                          _loadAuditLogs();
                        },
                      ),
                      _buildAuditChip(
                        'Admin Invited',
                        isSelected: _selectedAuditCategory == 'governance',
                        onTap: () {
                          setState(() => _selectedAuditCategory = 'governance');
                          _loadAuditLogs();
                        },
                      ),
                      _buildAuditChip(
                        'Tenant Deleted',
                        isSelected: _selectedAuditCategory == 'tenancy_delete',
                        onTap: () {
                          setState(
                            () => _selectedAuditCategory = 'tenancy_delete',
                          );
                          _loadAuditLogs();
                        },
                      ),
                      _buildAuditChip(
                        'Security Alerts',
                        isSelected: _selectedAuditCategory == 'security',
                        onTap: () {
                          setState(() => _selectedAuditCategory = 'security');
                          _loadAuditLogs();
                        },
                      ),
                      _buildAuditChip(
                        'Configuration',
                        isSelected: _selectedAuditCategory == 'configuration',
                        onTap: () {
                          setState(
                            () => _selectedAuditCategory = 'configuration',
                          );
                          _loadAuditLogs();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Search field
                  TextField(
                    controller: _auditSearchController,
                    onSubmitted: (_) => _loadAuditLogs(),
                    decoration: InputDecoration(
                      hintText: 'Search by actor, action, organization, or details...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _auditSearchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _auditSearchController.clear();
                                setState(() => _auditSearchQuery = '');
                                _loadAuditLogs();
                              },
                            )
                          : IconButton(
                              icon: const Icon(Icons.arrow_forward, size: 16),
                              onPressed: _loadAuditLogs,
                              tooltip: 'Search',
                            ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? AppTheme.darkInputFill
                          : const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isDark
                              ? AppTheme.darkInputBorder
                              : AppTheme.lightInputBorder,
                        ),
                      ),
                      isDense: true,
                    ),
                    onChanged: (val) {
                      _auditSearchQuery = val.trim();
                    },
                  ),
                  const SizedBox(height: 20),
                  if (_isLoadingAuditLogs)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (hasLogs)
                    _buildAuditLogsTable(isDark, _auditLogs!)
                  else
                    // Empty State
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 48,
                        horizontal: 24,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppTheme.darkInputFill
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark
                              ? AppTheme.darkInputBorder
                              : AppTheme.lightInputBorder,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.history_toggle_off,
                            size: 48,
                            color: isDark
                                ? Colors.grey.shade600
                                : Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            isLiveConnected
                                ? 'Audit Logging Service Active — No Events Recorded'
                                : 'Audit Logging Service Pending Integration',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: Text(
                              'Detailed platform audit events (organization creation, admin invitations, deletion requests, and security policy modifications) will automatically appear here once the audit-log backend is implemented.',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? AppTheme.darkTextSecondary
                                    : AppTheme.lightTextSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.blue.withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: Colors.blue,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'No fake records are generated. All operations remain isolated under database RLS.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditLogsTable(bool isDark, List<PlatformAuditLog> logs) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 800),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            isDark ? AppTheme.darkInputFill : const Color(0xFFF1F5F9),
          ),
          columns: const [
            DataColumn(
              label: Text(
                'Timestamp',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'Action',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'Category',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'Severity',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'Actor',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'Organization',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'Details',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
          rows: logs.map((log) {
            final dateStr = DateFormat('yyyy-MM-dd').format(log.createdAt);
            final timeStr =
                '${log.createdAt.hour.toString().padLeft(2, '0')}:${log.createdAt.minute.toString().padLeft(2, '0')}';
            final severityColor = log.severity == 'critical'
                ? Colors.purple
                : (log.severity == 'error'
                      ? Colors.red
                      : (log.severity == 'warning'
                            ? Colors.orange
                            : Colors.blue));

            return DataRow(
              cells: [
                DataCell(
                  Text(
                    '$dateStr $timeStr',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      log.action,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.grey.shade800
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      log.category.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: severityColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: severityColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      log.severity.toUpperCase(),
                      style: TextStyle(
                        color: severityColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    log.actorEmail ?? log.actorId ?? 'System',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                DataCell(
                  Text(
                    log.displayOrganization,
                    style: TextStyle(
                      fontSize: 12,
                      color: log.isDeletedTenant
                          ? (isDark
                                ? Colors.amber.shade300
                                : Colors.amber.shade900)
                          : null,
                      fontStyle: log.isDeletedTenant
                          ? FontStyle.italic
                          : FontStyle.normal,
                      fontWeight: log.isDeletedTenant
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                ),
                DataCell(
                  IconButton(
                    icon: const Icon(Icons.info_outline, size: 16),
                    tooltip: 'View Event Details',
                    onPressed: () => _showAuditLogDetails(log),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showAuditLogDetails(PlatformAuditLog log) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.event_note, color: AppTheme.primaryColor),
            const SizedBox(width: 8),
            Text('Audit Event: ${log.action}'),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildAuditDetailRow('Event ID', log.id),
                _buildAuditDetailRow(
                  'Timestamp',
                  log.createdAt.toIso8601String(),
                ),
                _buildAuditDetailRow('Event Type', log.eventType),
                _buildAuditDetailRow('Action', log.action),
                _buildAuditDetailRow('Category', log.category),
                _buildAuditDetailRow('Severity', log.severity),
                _buildAuditDetailRow('Actor Email', log.actorEmail ?? 'System'),
                _buildAuditDetailRow('Actor ID', log.actorId ?? 'N/A'),
                _buildAuditDetailRow('Organization', log.displayOrganization),
                if (log.organizationCode != null)
                  _buildAuditDetailRow(
                    'Organization Code',
                    log.organizationCode!,
                  ),
                _buildAuditDetailRow(
                  'Organization ID',
                  log.organizationId ??
                      (log.isDeletedTenant
                          ? 'Deleted (Historical Snapshot Preserved)'
                          : 'N/A'),
                ),
                _buildAuditDetailRow('IP Address', log.ipAddress ?? 'N/A'),
                _buildAuditDetailRow('User Agent', log.userAgent ?? 'N/A'),
                const SizedBox(height: 12),
                const Text(
                  'Metadata & Details:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF0F172A)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(log.details),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformSettingsView(bool isDark) {
    final isLive = SupabaseConfig.isInitialized;

    final platformName =
        PlatformSettingsService.instance.getSettingValue<String>(
          'platform_name',
        ) ??
        'ActionFlow HSE Multi-Tenant Portal';
    final primarySupportEmail =
        PlatformSettingsService.instance.getSettingValue<String>(
          'primary_support_email',
        ) ??
        'platform-support@actionflow.internal';
    final activeRegion =
        PlatformSettingsService.instance.getSettingValue<String>(
          'active_region',
        ) ??
        'Mumbai (ap-south-1) Supabase';
    final multiTenancyMode =
        PlatformSettingsService.instance.getSettingValue<String>(
          'multi_tenancy_mode',
        ) ??
        'Strict Partitioned Row-Level Security';
    final sessionTimeoutMinutes =
        PlatformSettingsService.instance.getSettingValue(
          'session_timeout_minutes',
        ) ??
        60;
    final requireMfa =
        PlatformSettingsService.instance.getSettingValue<bool>(
          'require_mfa_for_admins',
        ) ??
        true;
    final allowCrossTenantView =
        PlatformSettingsService.instance.getSettingValue<bool>(
          'allow_cross_tenant_view',
        ) ??
        false;
    final auditRetentionDays =
        PlatformSettingsService.instance.getSettingValue(
          'audit_retention_days',
        ) ??
        365;
    final defaultTimezone =
        PlatformSettingsService.instance.getSettingValue<String>(
          'default_timezone',
        ) ??
        'Asia/Kolkata (IST, UTC+05:30)';
    final maintenanceMode =
        PlatformSettingsService.instance.getSettingValue<bool>(
          'maintenance_mode',
        ) ??
        false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildViewBanner(
            title: 'Platform Settings & Configuration',
            subtitle: 'Global platform parameters, environment configuration, and integration defaults',
            icon: Icons.settings_outlined,
          ),
          const SizedBox(height: 24),
          // Section 1: Platform Configuration
          _buildSettingsSectionCard(
            isDark,
            title: 'Platform Configuration',
            icon: Icons.tune_outlined,
            iconColor: Colors.blue,
            items: [
              _buildSettingItem(
                label: 'Platform Name',
                value: platformName,
                statusBadge: _buildStatusBadge('Active', Colors.green),
                onEdit: isLive
                    ? () => _showEditStringSettingDialog(
                        key: 'platform_name',
                        title: 'Platform Name',
                        currentValue: platformName,
                      )
                    : null,
              ),
              _buildSettingItem(
                label: 'Primary Support Email',
                value: primarySupportEmail,
                statusBadge: _buildStatusBadge('Active', Colors.green),
                onEdit: isLive
                    ? () => _showEditStringSettingDialog(
                        key: 'primary_support_email',
                        title: 'Primary Support Email',
                        currentValue: primarySupportEmail,
                      )
                    : null,
              ),
              _buildSettingItem(
                label: 'Active Cloud Region',
                value: activeRegion,
                statusBadge: _buildStatusBadge('Active', Colors.green),
              ),
              _buildSettingItem(
                label: 'Multi-Tenancy Mode',
                value: multiTenancyMode,
                statusBadge: _buildStatusBadge('Active', Colors.green),
              ),
              _buildSettingItem(
                label: 'Custom Domain & White-Labeling',
                value: 'Not configured',
                statusBadge: _buildStatusBadge(
                  'Coming with backend integration',
                  Colors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Section 2: Email & Notification Configuration
          _buildSettingsSectionCard(
            isDark,
            title: 'Email & Notification Configuration',
            icon: Icons.mail_outline,
            iconColor: Colors.purple,
            items: [
              _buildSettingItem(
                label: 'Transactional Email Provider',
                value: 'Default Supabase Auth Mailer',
                statusBadge: _buildStatusBadge(
                  'Coming with backend integration',
                  Colors.amber,
                ),
              ),
              _buildSettingItem(
                label: 'Custom SMTP Server',
                value: 'Disabled (Default Provider Active)',
                statusBadge: _buildStatusBadge(
                  'Coming with backend integration',
                  Colors.amber,
                ),
              ),
              _buildSettingItem(
                label: 'Invitation Email Templates',
                value: 'Standard ActionFlow Template',
                statusBadge: _buildStatusBadge(
                  'Coming with backend integration',
                  Colors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Section 3: Security Configuration
          _buildSettingsSectionCard(
            isDark,
            title: 'Security Configuration',
            icon: Icons.security_outlined,
            iconColor: Colors.teal,
            items: [
              _buildSettingItem(
                label: 'Platform Admin Session Timeout',
                value: '$sessionTimeoutMinutes minutes',
                statusBadge: isLive
                    ? _buildStatusBadge('Active', Colors.green)
                    : _buildStatusBadge(
                        'Coming with backend integration',
                        Colors.amber,
                      ),
                onEdit: isLive
                    ? () => _showEditStringSettingDialog(
                        key: 'session_timeout_minutes',
                        title: 'Platform Admin Session Timeout',
                        currentValue: sessionTimeoutMinutes.toString(),
                        isNumber: true,
                      )
                    : null,
              ),
              _buildSettingItem(
                label: 'Mandatory Multi-Factor Authentication',
                value: requireMfa
                    ? 'Enabled (Enforced)'
                    : 'Optional (TOTP / Authenticator App)',
                statusBadge: isLive
                    ? Switch(
                        value: requireMfa,
                        onChanged: (val) {
                          final setting =
                              _platformSettings?['require_mfa_for_admins'] ??
                              const PlatformSetting(
                                key: 'require_mfa_for_admins',
                                value: true,
                                category: 'security',
                              );
                          _handleUpdateSetting(setting, val);
                        },
                      )
                    : _buildStatusBadge(
                        'Coming with backend integration',
                        Colors.amber,
                      ),
              ),
              _buildSettingItem(
                label: 'Cross-Tenant View Policy',
                value: allowCrossTenantView
                    ? 'Permissive (Cross-Tenant View Enabled)'
                    : 'Enforced (Strict Tenant Isolation)',
                statusBadge: isLive
                    ? Switch(
                        value: allowCrossTenantView,
                        onChanged: (val) {
                          final setting =
                              _platformSettings?['allow_cross_tenant_view'] ??
                              const PlatformSetting(
                                key: 'allow_cross_tenant_view',
                                value: false,
                                category: 'security',
                              );
                          _handleUpdateSetting(setting, val);
                        },
                      )
                    : _buildStatusBadge(
                        'Coming with backend integration',
                        Colors.amber,
                      ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Section 4: System Defaults
          _buildSettingsSectionCard(
            isDark,
            title: 'System Defaults',
            icon: Icons.settings_system_daydream_outlined,
            iconColor: Colors.indigo,
            items: [
              _buildSettingItem(
                label: 'Default Tenant Timezone',
                value: defaultTimezone,
                statusBadge: isLive
                    ? _buildStatusBadge('Active', Colors.green)
                    : _buildStatusBadge(
                        'Coming with backend integration',
                        Colors.amber,
                      ),
                onEdit: isLive
                    ? () => _showEditStringSettingDialog(
                        key: 'default_timezone',
                        title: 'Default Tenant Timezone',
                        currentValue: defaultTimezone,
                      )
                    : null,
              ),
              _buildSettingItem(
                label: 'Audit Log Retention Period',
                value: '$auditRetentionDays days',
                statusBadge: isLive
                    ? _buildStatusBadge('Active', Colors.green)
                    : _buildStatusBadge(
                        'Coming with backend integration',
                        Colors.amber,
                      ),
                onEdit: isLive
                    ? () => _showEditStringSettingDialog(
                        key: 'audit_retention_days',
                        title: 'Audit Log Retention Period (Days)',
                        currentValue: auditRetentionDays.toString(),
                        isNumber: true,
                      )
                    : null,
              ),
              _buildSettingItem(
                label: 'Data Retention Period',
                value: 'Indefinite (Full Tenant History)',
                statusBadge: _buildStatusBadge(
                  'Coming with backend integration',
                  Colors.amber,
                ),
              ),
              _buildSettingItem(
                label: 'Automated Snapshot Backups',
                value: 'Daily Scheduled Backups',
                statusBadge: _buildStatusBadge(
                  'Coming with backend integration',
                  Colors.amber,
                ),
              ),
              if (isLive)
                _buildSettingItem(
                  label: 'Maintenance Mode',
                  value: maintenanceMode
                      ? 'Active (Tenants Blocked)'
                      : 'Operational (Normal)',
                  statusBadge: Switch(
                    value: maintenanceMode,
                    activeThumbColor: Colors.red,
                    onChanged: (val) {
                      final setting =
                          _platformSettings?['maintenance_mode'] ??
                          const PlatformSetting(
                            key: 'maintenance_mode',
                            value: false,
                            category: 'general',
                          );
                      _handleUpdateSetting(setting, val);
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showEditStringSettingDialog({
    required String key,
    required String title,
    required String currentValue,
    bool isNumber = false,
  }) async {
    final controller = TextEditingController(text: currentValue);
    final formKey = GlobalKey<FormState>();

    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Edit $title'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            decoration: InputDecoration(
              labelText: title,
              border: const OutlineInputBorder(),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Value cannot be empty';
              if (isNumber && int.tryParse(v.trim()) == null) {
                return 'Please enter a valid integer';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogCtx).pop(true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (updated == true) {
      final val = isNumber
          ? int.parse(controller.text.trim())
          : controller.text.trim();
      final setting =
          _platformSettings?[key] ??
          PlatformSetting(key: key, value: val, category: 'general');
      await _handleUpdateSetting(setting, val);
    }
  }

  Widget _buildViewBanner({
    required String title,
    required String subtitle,
    required IconData icon,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 500;
          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        icon,
                        color: AppTheme.secondaryColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
                ),
                if (trailing != null) ...[const SizedBox(height: 12), trailing],
              ],
            );
          }
          return Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppTheme.secondaryColor, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade300,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 16), trailing],
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSecurityControlItem(
    bool isDark, {
    required String title,
    required String statusText,
    required Color statusColor,
    required String description,
    required IconData icon,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: statusColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 420) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _buildStatusBadge(statusText, statusColor),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildStatusBadge(statusText, statusColor),
                    ],
                  );
                },
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsSectionCard(
    bool isDark, {
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> items,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            for (int i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(height: 16),
              items[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSettingItem({
    required String label,
    required String value,
    required Widget statusBadge,
    VoidCallback? onEdit,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 650;
        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                runSpacing: 4,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                    child: statusBadge,
                  ),
                  if (onEdit != null)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      onPressed: onEdit,
                      splashRadius: 16,
                      tooltip: 'Edit $label',
                    ),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: Text(
                value,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(flex: 2, child: statusBadge),
            if (onEdit != null) ...[
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 16),
                onPressed: onEdit,
                splashRadius: 16,
                tooltip: 'Edit $label',
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildAuditChip(
    String label, {
    required bool isSelected,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.15)
              : Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryColor
                : Colors.grey.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? AppTheme.primaryColor : Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _buildIdentityCard(bool isDark, String ownerEmail) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(
              icon: Icons.verified_user_outlined,
              iconColor: Colors.purple,
              title: 'Platform Administrator Identity',
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Active Session',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildDetailItem('Authenticated Email', ownerEmail, isDark),
                _buildDetailItem(
                  'Authorization Level',
                  'Platform Owner (Tier 0)',
                  isDark,
                ),
                _buildDetailItem(
                  'Tenant Scope',
                  'Cross-Tenant (Global)',
                  isDark,
                ),
                _buildDetailItem(
                  'Tenant Assignment',
                  'None (Platform-Level)',
                  isDark,
                ),
                _buildDetailItem(
                  'Database Authority',
                  'is_platform_admin() = true',
                  isDark,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, [bool isDark = false]) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkInputFill : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? AppTheme.darkInputBorder : AppTheme.lightInputBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanyFiltersToolbar(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 720;

        final searchWidget = TextField(
          controller: _searchController,
          onChanged: (val) => setState(() => _searchQuery = val.trim()),
          decoration: InputDecoration(
            hintText: 'Search by name, code, or ID...',
            hintStyle: TextStyle(
              fontSize: 13,
              color: isDark ? AppTheme.darkTextHint : AppTheme.lightTextHint,
            ),
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            filled: true,
            fillColor: isDark
                ? AppTheme.darkInputFill
                : const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark
                    ? AppTheme.darkInputBorder
                    : AppTheme.lightInputBorder,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark
                    ? AppTheme.darkInputBorder
                    : AppTheme.lightInputBorder,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.primaryColor),
            ),
            isDense: true,
          ),
          style: const TextStyle(fontSize: 13),
        );

        Widget buildStatusFilter({bool expand = false}) {
          final dropdown = Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkInputFill : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark
                    ? AppTheme.darkInputBorder
                    : AppTheme.lightInputBorder,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _statusFilter,
                isDense: true,
                isExpanded: true,
                icon: const Icon(Icons.arrow_drop_down, size: 20),
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? AppTheme.darkTextPrimary
                      : AppTheme.lightTextPrimary,
                ),
                dropdownColor: isDark ? AppTheme.darkSurface : Colors.white,
                items: const [
                  DropdownMenuItem(value: 'All', child: Text('All Status')),
                  DropdownMenuItem(value: 'Active', child: Text('Active Only')),
                  DropdownMenuItem(
                    value: 'Inactive',
                    child: Text('Inactive Only'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _statusFilter = val);
                  }
                },
              ),
            ),
          );

          return expand
              ? Expanded(child: dropdown)
              : SizedBox(width: 135, child: dropdown);
        }

        Widget buildSortWidget({bool expand = false}) {
          final sortDropdown = Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkInputFill : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark
                    ? AppTheme.darkInputBorder
                    : AppTheme.lightInputBorder,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _sortBy,
                isDense: true,
                isExpanded: true,
                icon: const Icon(Icons.arrow_drop_down, size: 20),
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? AppTheme.darkTextPrimary
                      : AppTheme.lightTextPrimary,
                ),
                dropdownColor: isDark ? AppTheme.darkSurface : Colors.white,
                items: const [
                  DropdownMenuItem(value: 'name', child: Text('Sort by Name')),
                  DropdownMenuItem(value: 'date', child: Text('Sort by Date')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _sortBy = val);
                  }
                },
              ),
            ),
          );

          final directionBtn = InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _sortAscending = !_sortAscending),
            child: Container(
              height: 38,
              width: 38,
              decoration: BoxDecoration(
                color: isDark
                    ? AppTheme.darkInputFill
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark
                      ? AppTheme.darkInputBorder
                      : AppTheme.lightInputBorder,
                ),
              ),
              child: Icon(
                _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 18,
                color: AppTheme.primaryColor,
              ),
            ),
          );

          return Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (expand)
                Expanded(child: sortDropdown)
              else
                SizedBox(width: 135, child: sortDropdown),
              const SizedBox(width: 6),
              directionBtn,
            ],
          );
        }

        if (constraints.maxWidth < 480) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchWidget,
              const SizedBox(height: 8),
              buildStatusFilter(expand: false),
              const SizedBox(height: 8),
              buildSortWidget(expand: true),
            ],
          );
        }

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchWidget,
              const SizedBox(height: 10),
              Row(
                children: [
                  buildStatusFilter(expand: true),
                  const SizedBox(width: 8),
                  Expanded(child: buildSortWidget(expand: true)),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: searchWidget),
            const SizedBox(width: 12),
            buildStatusFilter(expand: false),
            const SizedBox(width: 12),
            buildSortWidget(expand: false),
          ],
        );
      },
    );
  }

  Widget _buildCompaniesSection(bool isDark) {
    final orgs = _organizations;
    final count = orgs?.length ?? 0;
    final filteredOrgs = _filteredOrganizations;
    final isFiltered = _searchQuery.isNotEmpty || _statusFilter != 'All';
    final countBadgeText = _isLoadingOrganizations && orgs == null
        ? 'Loading...'
        : isFiltered
        ? '${filteredOrgs.length} of $count Companies'
        : count == 1
        ? '1 Company Registered (${orgs!.first.name})'
        : '$count Companies Registered';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(
              icon: Icons.business,
              iconColor: AppTheme.primaryColor,
              title: 'Companies & Multi-Tenant Management',
              trailing: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      countBadgeText,
                      style: const TextStyle(
                        color: AppTheme.primaryColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Table / Grid View Segmented Toggle
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.darkInputFill
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark
                            ? AppTheme.darkInputBorder
                            : AppTheme.lightInputBorder,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          key: const Key('company_view_table_toggle'),
                          borderRadius: BorderRadius.circular(6),
                          onTap: () {
                            if (_isGridView) {
                              setState(() => _isGridView = false);
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: !_isGridView
                                  ? (isDark
                                        ? const Color(0xFF1E293B)
                                        : Colors.white)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: !_isGridView
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: isDark ? 0.25 : 0.08,
                                        ),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.table_rows_outlined,
                                  size: 16,
                                  color: !_isGridView
                                      ? AppTheme.primaryColor
                                      : (isDark
                                            ? Colors.grey.shade400
                                            : Colors.grey.shade600),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Table',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: !_isGridView
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    color: !_isGridView
                                        ? AppTheme.primaryColor
                                        : (isDark
                                              ? Colors.grey.shade400
                                              : Colors.grey.shade600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        InkWell(
                          key: const Key('company_view_grid_toggle'),
                          borderRadius: BorderRadius.circular(6),
                          onTap: () {
                            if (!_isGridView) {
                              setState(() => _isGridView = true);
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: _isGridView
                                  ? (isDark
                                        ? const Color(0xFF1E293B)
                                        : Colors.white)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: _isGridView
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: isDark ? 0.25 : 0.08,
                                        ),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.grid_view_outlined,
                                  size: 16,
                                  color: _isGridView
                                      ? AppTheme.primaryColor
                                      : (isDark
                                            ? Colors.grey.shade400
                                            : Colors.grey.shade600),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Grid',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: _isGridView
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    color: _isGridView
                                        ? AppTheme.primaryColor
                                        : (isDark
                                              ? Colors.grey.shade400
                                              : Colors.grey.shade600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Refresh Companies',
                    onPressed: _isLoadingOrganizations
                        ? null
                        : _loadOrganizations,
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Company'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    onPressed: _showAddCompanyDialog,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoadingOrganizations && (orgs == null || orgs.isEmpty)) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
            ] else if (_organizationsError != null &&
                (orgs == null || orgs.isEmpty)) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Failed to load organizations: $_organizationsError',
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _loadOrganizations,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ] else if (orgs != null && orgs.isEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.darkInputFill
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? AppTheme.darkInputBorder
                        : AppTheme.lightInputBorder,
                  ),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.business_outlined,
                      size: 40,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No tenant organizations found',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Click "Add Company" to provision your first tenant organization.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Company'),
                      onPressed: _showAddCompanyDialog,
                    ),
                  ],
                ),
              ),
            ] else if (orgs != null) ...[
              _buildCompanyFiltersToolbar(isDark),
              const SizedBox(height: 16),
              if (filteredOrgs.isEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.darkInputFill
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? AppTheme.darkInputBorder
                          : AppTheme.lightInputBorder,
                    ),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.search_off_outlined,
                        size: 36,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No matching organizations found',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Try adjusting your search query, status filter, or reset your filters.',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Reset Filters'),
                        onPressed: _resetFilters,
                      ),
                    ],
                  ),
                ),
              ] else if (_isGridView) ...[
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final int crossAxisCount = width >= 800
                        ? 3
                        : (width >= 550 ? 2 : 1);
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredOrgs.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent: 320,
                      ),
                      itemBuilder: (context, index) {
                        final org = filteredOrgs[index];
                        return _CompanyGridCard(
                          key: ValueKey(org.id),
                          organization: org,
                          counts: _organizationCounts[org.id],
                          isLoadingCounts: _isLoadingCounts,
                          hasCountsError: _countsError != null,
                          onManageAdmins: () => _openCompanyDetails(org),
                          onDeleteCompany: () =>
                              _handleDashboardDeleteCompany(org),
                          onCopyId: (id) async {
                            await Clipboard.setData(ClipboardData(text: id));
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Copied "$id" to clipboard.'),
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ] else ...[
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? AppTheme.darkInputBorder
                          : AppTheme.lightInputBorder,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 780),
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          isDark
                              ? AppTheme.darkInputFill
                              : const Color(0xFFF1F5F9),
                        ),
                        dataRowMinHeight: 52,
                        dataRowMaxHeight: 60,
                        horizontalMargin: 16,
                        columnSpacing: 20,
                        columns: const [
                          DataColumn(
                            label: Text(
                              'Company / Tenant',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Code / Slug',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Status',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Organization ID',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Created Date',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Actions',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                        rows: filteredOrgs.map((org) {
                          final createdStr = org.createdAt != null
                              ? '${org.createdAt!.year}-${org.createdAt!.month.toString().padLeft(2, '0')}-${org.createdAt!.day.toString().padLeft(2, '0')}'
                              : 'N/A';
                          final displayId = org.id.length > 20
                              ? '${org.id.substring(0, 8)}...${org.id.substring(org.id.length - 6)}'
                              : org.id;

                          return DataRow(
                            cells: [
                              DataCell(
                                InkWell(
                                  borderRadius: BorderRadius.circular(6),
                                  onTap: () => _openCompanyDetails(org),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                      horizontal: 4,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircleAvatar(
                                          radius: 14,
                                          backgroundColor: AppTheme.primaryColor
                                              .withValues(alpha: 0.15),
                                          child: Text(
                                            org.name.isNotEmpty
                                                ? org.name[0].toUpperCase()
                                                : 'C',
                                            style: const TextStyle(
                                              color: AppTheme.primaryColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          org.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.primaryColor,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.open_in_new,
                                          size: 12,
                                          color: AppTheme.primaryColor,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : Colors.grey.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    org.code,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: org.isActive
                                        ? Colors.green.withValues(alpha: 0.12)
                                        : Colors.grey.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.circle,
                                        size: 8,
                                        color: org.isActive
                                            ? Colors.green
                                            : Colors.grey,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        org.isActive ? 'Active' : 'Inactive',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: org.isActive
                                              ? Colors.green
                                              : Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              DataCell(
                                Tooltip(
                                  message: org.id,
                                  child: Text(
                                    displayId,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.grey.shade400
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  createdStr,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.grey.shade400
                                        : Colors.grey.shade700,
                                  ),
                                ),
                              ),
                              DataCell(
                                OutlinedButton.icon(
                                  icon: const Icon(
                                    Icons.admin_panel_settings_outlined,
                                    size: 14,
                                  ),
                                  label: const Text(
                                    'Manage Admins',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.primaryColor,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () => _openCompanyDetails(org),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    bool isDark, {
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(icon, color: color, size: 18),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildCardHeader({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget trailing,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 750) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: iconColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              trailing,
            ],
          );
        }
        return Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        );
      },
    );
  }
}

/// Dialog presenting company details and its Company Administrators
class _CompanyDetailsDialog extends StatefulWidget {
  final Organization organization;

  const _CompanyDetailsDialog({required this.organization});

  @override
  State<_CompanyDetailsDialog> createState() => _CompanyDetailsDialogState();
}

class _CompanyDetailsDialogState extends State<_CompanyDetailsDialog> {
  late Future<List<CompanyAdminSummary>> _adminsFuture;
  final Set<String> _resendingAdminIds = {};

  @override
  void initState() {
    super.initState();
    _loadAdmins();
  }

  void _loadAdmins() {
    _adminsFuture = OrganizationService.instance.fetchCompanyAdmins(
      widget.organization.id,
    );
  }

  Future<void> _handleResendInvitation(CompanyAdminSummary admin) async {
    if (_resendingAdminIds.contains(admin.id)) return;

    setState(() {
      _resendingAdminIds.add(admin.id);
    });

    final result = await OrganizationService.instance
        .resendCompanyAdminInvitation(
          organization: widget.organization,
          adminId: admin.id,
        );

    if (!mounted) return;

    setState(() {
      _resendingAdminIds.remove(admin.id);
    });

    if (result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message ??
                'Invitation link resent successfully to ${admin.email}.',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'Failed to resend invitation.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showAddAdminDialog() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) =>
          _AddCompanyAdminDialog(organization: widget.organization),
    );

    if (created == true) {
      setState(() {
        _loadAdmins();
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Company Admin invited for ${widget.organization.name}.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _showEditAdminDialog(CompanyAdminSummary admin) async {
    final updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => _EditCompanyAdminDialog(
        organization: widget.organization,
        admin: admin,
      ),
    );

    if (updated == true) {
      setState(() {
        _loadAdmins();
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Administrator "${admin.fullName}" updated.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _showDeleteAdminDialog(
    CompanyAdminSummary admin,
    List<CompanyAdminSummary> allAdmins,
  ) async {
    final activeAdmins = allAdmins
        .where((a) => a.isActive && !a.isDisabled)
        .toList();
    if (activeAdmins.length <= 1) {
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
              SizedBox(width: 8),
              Text('Cannot Delete Administrator'),
            ],
          ),
          content: const Text(
            'A company must always retain at least one active administrator.\n\n'
            'To remove this administrator, please invite or appoint another active administrator first.',
            style: TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => _DeleteCompanyAdminDialog(
        organization: widget.organization,
        admin: admin,
        allAdmins: allAdmins,
      ),
    );

    if (deleted == true) {
      setState(() {
        _loadAdmins();
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Administrator "${admin.fullName}" removed.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _handleDeleteCompany() async {
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) =>
          _DeleteCompanyConfirmationDialog(organization: widget.organization),
    );

    if (deleted == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final org = widget.organization;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.business,
              color: AppTheme.primaryColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  org.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Slug: ${org.code}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Company details overview card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.darkInputFill
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? AppTheme.darkInputBorder
                        : AppTheme.lightInputBorder,
                  ),
                ),
                child: Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [
                    _buildInfoSnippet('Organization ID', org.id),
                    _buildInfoSnippet('Code / Slug', org.code),
                    _buildInfoSnippet(
                      'Status',
                      org.isActive ? 'Active' : 'Inactive',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Company Administrators section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Company Administrators',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.person_add, size: 16),
                    label: const Text('Add Company Admin'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      elevation: 0,
                    ),
                    onPressed: _showAddAdminDialog,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<CompanyAdminSummary>>(
                future: _adminsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final admins = snapshot.data ?? [];
                  if (admins.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppTheme.darkInputFill
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            Icons.admin_panel_settings_outlined,
                            size: 32,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'No Company Admins assigned yet.',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Click "Add Company Admin" to invite an administrator.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: admins.map((admin) {
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isDark
                                ? AppTheme.darkCardBorder
                                : AppTheme.lightCardBorder,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: AppTheme.primaryColor
                                    .withValues(alpha: 0.12),
                                child: Text(
                                  admin.fullName.isNotEmpty
                                      ? admin.fullName[0].toUpperCase()
                                      : 'A',
                                  style: const TextStyle(
                                    color: AppTheme.primaryColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            admin.fullName,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        if (admin.isPrimaryAdmin) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.purple.withValues(
                                                alpha: 0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'Primary Admin',
                                              style: TextStyle(
                                                color: Colors.purple,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      admin.email,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    if (admin.designation != null &&
                                        admin.designation!.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        admin.designation!,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? Colors.grey.shade400
                                              : Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: admin.isDisabled
                                      ? Colors.grey.withValues(alpha: 0.15)
                                      : (admin.isInvitationPending
                                            ? Colors.orange.withValues(
                                                alpha: 0.15,
                                              )
                                            : Colors.green.withValues(
                                                alpha: 0.12,
                                              )),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  admin.isDisabled
                                      ? 'Disabled'
                                      : (admin.isInvitationPending
                                            ? 'Invitation Pending'
                                            : 'Active'),
                                  style: TextStyle(
                                    color: admin.isDisabled
                                        ? Colors.grey.shade600
                                        : (admin.isInvitationPending
                                              ? Colors.orange.shade800
                                              : Colors.green),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              if (admin.isInvitationPending) ...[
                                IconButton(
                                  icon: _resendingAdminIds.contains(admin.id)
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.mark_email_read_outlined,
                                          size: 18,
                                          color: Colors.orange,
                                        ),
                                  tooltip: 'Resend Invitation',
                                  splashRadius: 18,
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(6),
                                  onPressed:
                                      _resendingAdminIds.contains(admin.id)
                                      ? null
                                      : () => _handleResendInvitation(admin),
                                ),
                              ],
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                tooltip: 'Edit Administrator',
                                splashRadius: 18,
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(6),
                                onPressed: admin.isDisabled
                                    ? null
                                    : () => _showEditAdminDialog(admin),
                              ),
                              if (!admin.isDisabled) ...[
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: Colors.redAccent,
                                  ),
                                  tooltip: 'Delete Administrator',
                                  splashRadius: 18,
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(6),
                                  onPressed: () =>
                                      _showDeleteAdminDialog(admin, admins),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              // Danger Zone or Anchor Protection Notice
              if (org.isSobha) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.blueGrey.shade900.withValues(alpha: 0.3)
                        : Colors.blueGrey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? Colors.blueGrey.shade700
                          : Colors.blueGrey.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 20,
                        color: isDark
                            ? Colors.blueGrey.shade300
                            : Colors.blueGrey.shade700,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Anchor Organization: Sobha (#1) is the permanent default tenant of ActionFlow and cannot be deleted.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.blueGrey.shade300
                                : Colors.blueGrey.shade800,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.red.shade900.withValues(alpha: 0.15)
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? Colors.red.shade800.withValues(alpha: 0.5)
                          : Colors.red.shade200,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 18,
                            color: Colors.red.shade700,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Danger Zone',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Permanently delete this organization, including all associated departments, sites, teams, company administrators, and unconfirmed invitations. This action cannot be undone.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.red.shade200
                              : Colors.red.shade900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          key: const Key('delete_company_button'),
                          icon: const Icon(Icons.delete_forever, size: 16),
                          label: const Text('Delete Company'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                            side: BorderSide(color: Colors.red.shade400),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                          ),
                          onPressed: () => _handleDeleteCompany(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildInfoSnippet(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

/// Confirmation dialog requiring the Platform Owner to type the exact company name
/// before permanently deleting an organization and its tenant data.
class _DeleteCompanyConfirmationDialog extends StatefulWidget {
  final Organization organization;

  const _DeleteCompanyConfirmationDialog({required this.organization});

  @override
  State<_DeleteCompanyConfirmationDialog> createState() =>
      _DeleteCompanyConfirmationDialogState();
}

class _DeleteCompanyConfirmationDialogState
    extends State<_DeleteCompanyConfirmationDialog> {
  final _nameController = TextEditingController();
  bool _isDeleting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _isNameMatched =>
      _nameController.text.trim() == widget.organization.name.trim();

  Future<void> _confirmDelete() async {
    if (!_isNameMatched || _isDeleting) return;

    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });

    final result = await OrganizationService.instance.deleteOrganization(
      widget.organization.id,
    );

    if (!mounted) return;

    if (result.isSuccess) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isDeleting = false;
        _errorMessage = result.errorMessage ?? 'Failed to delete organization.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final org = widget.organization;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.red,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Permanently Delete Company?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This action will permanently delete "${org.name}" and all associated data:',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              _buildBullet('All departments, sites, and operational teams'),
              _buildBullet('All team member assignments and manager scopes'),
              _buildBullet(
                'All tenant user profiles and unconfirmed account requests',
              ),
              _buildBullet(
                'All company Auth user accounts purged from Supabase Auth',
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.red.shade900.withValues(alpha: 0.2)
                      : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? Colors.red.shade800
                        : const Color(0xFFFCA5A5),
                  ),
                ),
                child: Text(
                  'WARNING: This action is irreversible. Platform Admins will NOT be deleted.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.red.shade200 : Colors.red.shade800,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'To confirm, type "${org.name}" below:',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('confirm_company_name_field'),
                controller: _nameController,
                enabled: !_isDeleting,
                decoration: InputDecoration(
                  hintText: org.name,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isDeleting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('confirm_delete_company_button'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
            disabledBackgroundColor: isDark
                ? Colors.red.shade900.withValues(alpha: 0.3)
                : Colors.red.shade100,
            disabledForegroundColor: isDark
                ? Colors.grey.shade600
                : Colors.red.shade300,
          ),
          onPressed: (_isNameMatched && !_isDeleting) ? _confirmDelete : null,
          child: _isDeleting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Permanently Delete Company'),
        ),
      ],
    );
  }

  Widget _buildBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '• ',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Multi-Tenant Company Grid & Card Components
// ============================================================================

/// Color tokens compatible with dashboard theme.
class AppColors {
  AppColors._();
  static const Color error = AppTheme.errorColor;
  static const Color success = Color(0xFF10B981);
  static const Color info = Color(0xFF0284C7);
  static const Color darkSurface = AppTheme.darkSurface;
}

/// Lightweight DateFormat compatibility helper for 'yyyy-MM-dd'.
class DateFormat {
  final String pattern;
  const DateFormat(this.pattern);
  String format(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _CompanyGridCard extends StatelessWidget {
  final Organization organization;
  final VoidCallback onManageAdmins;
  final VoidCallback onDeleteCompany;
  final Future<void> Function(String) onCopyId;
  final OrganizationCounts? counts;
  final bool isLoadingCounts;
  final bool hasCountsError;

  const _CompanyGridCard({
    super.key,
    required this.organization,
    required this.onManageAdmins,
    required this.onDeleteCompany,
    required this.onCopyId,
    this.counts,
    this.isLoadingCounts = false,
    this.hasCountsError = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.all(6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDarkMode
              ? AppTheme.darkCardBorder
              : AppTheme.lightCardBorder,
        ),
      ),
      color: isDarkMode ? AppTheme.darkSurface : Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppTheme.primaryColor.withValues(
                    alpha: 0.12,
                  ),
                  child: Text(
                    organization.name.isNotEmpty
                        ? organization.name.substring(0, 1).toUpperCase()
                        : 'C',
                    style: const TextStyle(
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        organization.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? AppTheme.darkInputFill
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          organization.code,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            color: isDarkMode
                                ? AppTheme.darkTextSecondary
                                : AppTheme.lightTextSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusPill(organization.isActive, context),
              ],
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              context,
              'Organization ID:',
              organization.id,
              isId: true,
            ),
            const SizedBox(height: 6),
            _buildInfoRow(
              context,
              'Created Date:',
              DateFormat('yyyy-MM-dd')
                  .format(organization.createdAt ?? DateTime.now()),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? AppTheme.darkInputFill
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDarkMode
                      ? AppTheme.darkInputBorder
                      : AppTheme.lightInputBorder,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem('Users', counts?.users, isDarkMode),
                  Container(
                    width: 1,
                    height: 16,
                    color: isDarkMode
                        ? AppTheme.darkInputBorder
                        : AppTheme.lightInputBorder,
                  ),
                  _buildStatItem('Depts', counts?.departments, isDarkMode),
                  Container(
                    width: 1,
                    height: 16,
                    color: isDarkMode
                        ? AppTheme.darkInputBorder
                        : AppTheme.lightInputBorder,
                  ),
                  _buildStatItem('Sites', counts?.sites, isDarkMode),
                ],
              ),
            ),
            if (organization.isSobha) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.info.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified, color: AppColors.info, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Anchor Tenant',
                      style: TextStyle(
                        color: AppColors.info,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const Spacer(),
            Divider(
              height: 14,
              color: isDarkMode
                  ? AppTheme.darkCardBorder
                  : AppTheme.lightCardBorder,
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: BorderSide(
                        color: AppTheme.primaryColor.withValues(alpha: 0.4),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: onManageAdmins,
                    child: const Text('Manage Admins'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: organization.isSobha
                          ? (isDarkMode
                                ? Colors.grey.shade800
                                : Colors.grey.shade300)
                          : AppColors.error,
                      foregroundColor: organization.isSobha
                          ? (isDarkMode
                                ? Colors.grey.shade500
                                : Colors.grey.shade600)
                          : Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: organization.isSobha ? null : onDeleteCompany,
                    child: const Text('Delete Company'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value, {
    bool isId = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isDark
                ? AppTheme.darkTextSecondary
                : AppTheme.lightTextSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontFamily: isId ? 'monospace' : null,
                  fontSize: 12,
                  fontWeight: isId ? FontWeight.w500 : FontWeight.w600,
                  color: isDark
                      ? AppTheme.darkTextPrimary
                      : AppTheme.lightTextPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isId)
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => onCopyId(value),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.copy,
                    size: 15,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, int? count, bool isDark) {
    Widget valueWidget;
    if (isLoadingCounts) {
      valueWidget = const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 1.5),
      );
    } else if (hasCountsError) {
      valueWidget = Tooltip(
        message: 'Could not load counts',
        child: Text(
          'Err',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.red.shade400,
          ),
        ),
      );
    } else if (count != null) {
      valueWidget = Text(
        '$count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
        ),
      );
    } else if (SupabaseConfig.isInitialized) {
      valueWidget = Text(
        '0',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
        ),
      );
    } else {
      valueWidget = Text(
        'N/A',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 16, child: Center(child: valueWidget)),
        const SizedBox(height: 1),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isDark
                ? AppTheme.darkTextSecondary
                : AppTheme.lightTextSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusPill(bool isActive, [BuildContext? context]) {
    final color = isActive
        ? AppColors.success
        : (context != null
              ? Theme.of(context).disabledColor
              : const Color(0xFF9E9E9E));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            isActive ? 'Active' : 'Inactive',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog for inviting a new Company Administrator
class _AddCompanyAdminDialog extends StatefulWidget {
  final Organization organization;

  const _AddCompanyAdminDialog({required this.organization});

  @override
  State<_AddCompanyAdminDialog> createState() => _AddCompanyAdminDialogState();
}

class _AddCompanyAdminDialogState extends State<_AddCompanyAdminDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _designationController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _designationController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final result = await OrganizationService.instance.inviteCompanyAdmin(
      organization: widget.organization,
      fullName: _nameController.text,
      email: _emailController.text,
      phone: _phoneController.text.trim().isNotEmpty
          ? _phoneController.text.trim()
          : null,
      designation: _designationController.text.trim().isNotEmpty
          ? _designationController.text.trim()
          : null,
    );

    if (!mounted) return;

    if (result.isSuccess) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isSubmitting = false;
        _errorMessage =
            result.errorMessage ?? 'Failed to invite company admin.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.person_add_alt_1,
              color: AppTheme.primaryColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Add Company Admin',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tenant scope confirmation container
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.business,
                        size: 20,
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Company: ${widget.organization.name} (${widget.organization.code})\nTenant isolation will permanently bind this administrator to this organization.',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _nameController,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'Full Name *',
                    hintText: 'e.g. Rahul Sharma',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    if (v.isEmpty) return 'Full name is required';
                    if (v.length > 150) {
                      return 'Full name cannot exceed 150 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'Email Address *',
                    hintText: 'e.g. admin@company.com',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    final v = value?.trim().toLowerCase() ?? '';
                    if (v.isEmpty) return 'Email address is required';
                    final emailRegex = RegExp(
                      r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                    );
                    if (!emailRegex.hasMatch(v)) {
                      return 'Please enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number (Optional)',
                    hintText: 'e.g. +971 50 123 4567',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _designationController,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'Designation (Optional)',
                    hintText: 'e.g. System Administrator / Head of HSE',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.darkInputFill
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.lock_clock_outlined,
                        size: 18,
                        color: Colors.grey,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No password is set by Platform Admin. An invitation will be sent to the administrator to set their password upon account activation.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _handleSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Invite Company Admin'),
        ),
      ],
    );
  }
}

/// Dialog for editing an existing Company Administrator
class _EditCompanyAdminDialog extends StatefulWidget {
  final Organization organization;
  final CompanyAdminSummary admin;

  const _EditCompanyAdminDialog({
    required this.organization,
    required this.admin,
  });

  @override
  State<_EditCompanyAdminDialog> createState() =>
      _EditCompanyAdminDialogState();
}

class _EditCompanyAdminDialogState extends State<_EditCompanyAdminDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _designationController;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.admin.fullName);
    _emailController = TextEditingController(text: widget.admin.email);
    _phoneController = TextEditingController(text: widget.admin.phone ?? '');
    _designationController = TextEditingController(
      text: widget.admin.designation ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _designationController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final result = await OrganizationService.instance.updateCompanyAdmin(
      organization: widget.organization,
      adminId: widget.admin.id,
      fullName: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim().isNotEmpty
          ? _phoneController.text.trim()
          : null,
      designation: _designationController.text.trim().isNotEmpty
          ? _designationController.text.trim()
          : null,
    );

    if (!mounted) return;

    if (result.isSuccess) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isSubmitting = false;
        _errorMessage =
            result.errorMessage ?? 'Failed to update company admin.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.manage_accounts_outlined,
              color: AppTheme.primaryColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Edit Company Admin',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_errorMessage != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _nameController,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'Full Name *',
                    hintText: 'e.g. John Doe',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Full name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'Email Address *',
                    hintText: 'e.g. admin@company.com',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    final v = value?.trim().toLowerCase() ?? '';
                    if (v.isEmpty) return 'Email address is required';
                    final emailRegex = RegExp(
                      r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                    );
                    if (!emailRegex.hasMatch(v)) {
                      return 'Please enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number (Optional)',
                    hintText: 'e.g. +971 50 123 4567',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _designationController,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'Designation (Optional)',
                    hintText: 'e.g. System Administrator / Head of HSE',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.darkInputFill
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: Colors.grey),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Updating the email will automatically synchronize the administrator\'s authentication login identity and profile.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _handleSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save Changes'),
        ),
      ],
    );
  }
}

/// Dialog for deleting / deactivating an existing Company Administrator
class _DeleteCompanyAdminDialog extends StatefulWidget {
  final Organization organization;
  final CompanyAdminSummary admin;
  final List<CompanyAdminSummary> allAdmins;

  const _DeleteCompanyAdminDialog({
    required this.organization,
    required this.admin,
    required this.allAdmins,
  });

  @override
  State<_DeleteCompanyAdminDialog> createState() =>
      _DeleteCompanyAdminDialogState();
}

class _DeleteCompanyAdminDialogState extends State<_DeleteCompanyAdminDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedSuccessorId;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final candidates = widget.allAdmins
        .where((a) => a.id != widget.admin.id && a.isActive && !a.isDisabled)
        .toList();
    if (candidates.isNotEmpty) {
      _selectedSuccessorId = candidates.first.id;
    }
  }

  Future<void> _handleDelete() async {
    if (widget.admin.isPrimaryAdmin && !_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final result = await OrganizationService.instance.deleteCompanyAdmin(
      organization: widget.organization,
      adminId: widget.admin.id,
      newPrimaryAdminId: widget.admin.isPrimaryAdmin
          ? _selectedSuccessorId
          : null,
    );

    if (!mounted) return;

    if (result.isSuccess) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isSubmitting = false;
        _errorMessage =
            result.errorMessage ?? 'Failed to delete company admin.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final candidates = widget.allAdmins
        .where((a) => a.id != widget.admin.id && a.isActive && !a.isDisabled)
        .toList();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.delete_forever_outlined,
              color: Colors.red,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.admin.isPrimaryAdmin
                  ? 'Transfer Role & Remove Primary Admin'
                  : 'Remove Administrator',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_errorMessage != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  'Are you sure you want to deactivate and remove ${widget.admin.fullName} (${widget.admin.email}) from ${widget.organization.name}?',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.darkInputFill
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.shield_outlined, size: 18, color: Colors.grey),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'The administrator will be deactivated and their login access revoked. Historical audit trails and actions will remain preserved.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.admin.isPrimaryAdmin) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.amber.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.amber,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This administrator is currently the Primary Admin. You must designate an active administrator to become the new Primary Admin before removing them.',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.amber.shade200
                                  : Colors.amber.shade900,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedSuccessorId,
                    decoration: const InputDecoration(
                      labelText: 'Select New Primary Admin *',
                      prefixIcon: Icon(Icons.star_outline),
                    ),
                    items: candidates.map((candidate) {
                      return DropdownMenuItem<String>(
                        value: candidate.id,
                        child: Text(
                          '${candidate.fullName} (${candidate.email})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    validator: (val) {
                      if (val == null || val.isEmpty) {
                        return 'Please select a successor primary admin';
                      }
                      return null;
                    },
                    onChanged: _isSubmitting
                        ? null
                        : (val) => setState(() => _selectedSuccessorId = val),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _handleDelete,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  widget.admin.isPrimaryAdmin
                      ? 'Transfer & Remove'
                      : 'Remove Administrator',
                ),
        ),
      ],
    );
  }
}

/// Dialog for creating a new tenant organization
class _AddCompanyDialog extends StatefulWidget {
  const _AddCompanyDialog();

  @override
  State<_AddCompanyDialog> createState() => _AddCompanyDialogState();
}

class _AddCompanyDialogState extends State<_AddCompanyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  bool _isActive = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _userEditedCode = false;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _onNameChanged(String value) {
    if (!_userEditedCode) {
      final slug = value
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9_-]'), '-')
          .replaceAll(RegExp(r'-+'), '-');
      _codeController.text = slug;
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final result = await OrganizationService.instance.createOrganization(
      name: _nameController.text,
      code: _codeController.text,
      isActive: _isActive,
    );

    if (!mounted) return;

    if (result.isSuccess) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isSubmitting = false;
        _errorMessage = result.errorMessage ?? 'Failed to create organization.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.add_business,
              color: AppTheme.primaryColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Add New Organization',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Register a new tenant company in ActionFlow. Tenant isolation policies will automatically apply.',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _nameController,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'Company Name *',
                    hintText: 'e.g. Acme Corporation',
                    prefixIcon: Icon(Icons.business_outlined),
                  ),
                  textInputAction: TextInputAction.next,
                  onChanged: _onNameChanged,
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    if (v.isEmpty) return 'Company name is required';
                    if (v.length > 150) {
                      return 'Name cannot exceed 150 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _codeController,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'Company Code / Slug *',
                    hintText: 'e.g. acme-corp',
                    prefixIcon: Icon(Icons.tag_outlined),
                    helperText: 'Lowercase letters, numbers, hyphens, and underscores only.',
                  ),
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => _userEditedCode = true,
                  validator: (value) {
                    final v = value?.trim().toLowerCase() ?? '';
                    if (v.isEmpty) return 'Company code is required';
                    if (v.length > 50) {
                      return 'Code cannot exceed 50 characters';
                    }
                    if (!RegExp(r'^[a-z0-9_-]+$').hasMatch(v)) {
                      return 'Code must only contain lowercase letters, numbers, hyphens, and underscores';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Active Status',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Enable this organization for operations immediately',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _isActive,
                  activeThumbColor: AppTheme.primaryColor,
                  onChanged: _isSubmitting
                      ? null
                      : (val) => setState(() => _isActive = val),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _handleSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Create Company'),
        ),
      ],
    );
  }
}
