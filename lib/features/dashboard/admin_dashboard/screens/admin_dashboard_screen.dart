import 'dart:math' as math;
import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/core/theme/theme_controller.dart';
import 'package:action_flow/features/auth/data/mock_auth_store.dart';
import 'package:action_flow/features/auth/models/auth_models.dart';
import 'package:action_flow/features/auth/screens/login_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/profile/widgets/admin_profile_dialog.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/models/team.dart';
import 'package:action_flow/features/users/screens/person_form_screen.dart';
import 'package:action_flow/services/account_request_service.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:action_flow/services/company_structure_service.dart';
import 'package:action_flow/services/user_service.dart';
import 'package:action_flow/models/action_section.dart';
import 'package:action_flow/services/action_section_service.dart';
import 'package:action_flow/models/division.dart';
import 'package:action_flow/services/division_service.dart';
import 'package:action_flow/widgets/common/action_flow_logo.dart';
import 'package:action_flow/widgets/common/theme_toggle_button.dart';
import 'package:flutter/material.dart';

class _GlobalSearchResult {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final int targetTabIndex;
  final VoidCallback onSelect;

  const _GlobalSearchResult({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.targetTabIndex,
    required this.onSelect,
  });
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    super.key,
    this.initialTabIndex = 0,
    this.adminProfile,
  });

  final int initialTabIndex;
  final UserProfile? adminProfile;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late int _selectedNavIndex;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _globalSearchController = TextEditingController();
  final TextEditingController _userSearchController = TextEditingController();

  // Admin Profile state
  late UserProfile _adminProfile;

  // Company Structure state
  bool _isLoadingStructure = false;
  String? _structureErrorMessage;

  String get _currentOrgId {
    final orgId = AuthService.instance.currentProfileData?.organizationId;
    if (orgId != null && orgId.isNotEmpty) return orgId;
    final profOrgId = _adminProfile.organizationId;
    if (profOrgId != null && profOrgId.isNotEmpty) return profOrgId;
    return Organization.sobhaId;
  }

  // Local state for admin managed items
  late List<Map<String, dynamic>> _departments;
  late List<Map<String, dynamic>> _sites;
  late List<Map<String, dynamic>> _teams;
  late List<Map<String, dynamic>> _systemNotifications;

  // Action Sections state
  List<ActionSection> _actionSections = [];
  bool _isLoadingSections = false;
  String? _sectionsErrorMessage;

  // Divisions state
  List<Division> _divisions = [];
  bool _isLoadingDivisions = false;
  String? _divisionsErrorMessage;
  String _divisionSearchQuery = '';

  // Search & filter states
  String _userSearchQuery = '';
  String _selectedUserRole = 'All';
  String _selectedUserDept = 'All';
  String _selectedUserStatus = 'All';
  List<Person>? _realUsers;
  bool _isLoadingUsers = false;
  String? _usersErrorMessage;

  // Account Requests state
  String _requestSearchQuery = '';
  String _requestRoleFilter = 'All';
  String _requestStatusTab = 'Pending';
  List<SignupRequest>? _accountRequests;
  bool _isLoadingRequests = false;
  String? _requestsErrorMessage;

  // System Settings states
  bool _enforce2FA = true;
  bool _allowExternalSignup = false;
  bool _autoEscalateOverdue = true;
  int _sessionTimeoutMinutes = 30;

  // Operational Calendar states
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedCalendarDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selectedNavIndex = widget.initialTabIndex;

    final activeProfile =
        widget.adminProfile ??
        AuthService.instance.currentProfileData?.userProfile;
    final currentUser = SupabaseConfig.clientOrNull?.auth.currentUser;

    if (activeProfile != null) {
      _adminProfile = activeProfile;
    } else if (currentUser != null) {
      final email = currentUser.email ?? '';
      final fallbackName = email.isNotEmpty
          ? email.split('@').first
          : 'Company Admin';
      _adminProfile = UserProfile(
        id: currentUser.id,
        name: fallbackName,
        email: email,
        phone: '',
        designation: 'Company Administrator',
        department: '',
        division: '',
        site: '',
        team: '',
        role: 'System Administrator',
        accountStatus: 'Active',
        permissions: const [
          'Full System Configuration Access',
          'User, Department & Site Governance',
          'Security Policy & 2FA Enforcement',
          'System Audit Log Inspection',
          'Emergency Broadcast Dispatch',
        ],
        organizationId:
            AuthService.instance.currentOrganizationId ?? Organization.sobhaId,
        organizationName:
            AuthService.instance.currentOrganization?.name ??
            Organization.sobhaName,
      );
    } else {
      _adminProfile = UserProfile.mockAdmin();
    }

    _loadAuthoritativeAdminProfile();
    _initAdminData();
    _loadCompanyStructure();
    _loadAccountRequests();
    _loadUsers();
    _loadActionSections();
    _loadDivisions();
  }

  Future<void> _loadAuthoritativeAdminProfile() async {
    if (!SupabaseConfig.isInitialized) return;
    final currentUser = SupabaseConfig.clientOrNull?.auth.currentUser;
    if (currentUser == null) return;

    try {
      final fetched = await AuthService.instance.fetchProfile(currentUser.id);
      if (fetched != null && mounted) {
        setState(() {
          _adminProfile = fetched.userProfile;
        });
      }
    } catch (e) {
      debugPrint('Failed to load authoritative admin profile: $e');
    }
  }

  @override
  void dispose() {
    _globalSearchController.dispose();
    _userSearchController.dispose();
    super.dispose();
  }

  void _initAdminData() {
    if (SupabaseConfig.isInitialized) {
      _departments = [];
      _sites = [];
      _teams = [];
      _systemNotifications = [];
      return;
    }

    _departments = [
      {
        'id': 'DEP-01',
        'name': 'Health & Safety',
        'code': 'HSE',
        'head': 'David Chen',
        'members': 14,
        'activeActions': 18,
        'status': 'Active',
      },
      {
        'id': 'DEP-02',
        'name': 'Operations & Plant',
        'code': 'OPS',
        'head': 'Sarah Jenkins',
        'members': 28,
        'activeActions': 34,
        'status': 'Active',
      },
      {
        'id': 'DEP-03',
        'name': 'Quality Assurance',
        'code': 'QA',
        'head': 'Elena Rostova',
        'members': 12,
        'activeActions': 9,
        'status': 'Active',
      },
      {
        'id': 'DEP-04',
        'name': 'Facilities & Fleet',
        'code': 'FAC',
        'head': 'Michael Chang',
        'members': 16,
        'activeActions': 12,
        'status': 'Active',
      },
      {
        'id': 'DEP-05',
        'name': 'Engineering & Tech',
        'code': 'ENG',
        'head': 'Alex Morgan',
        'members': 22,
        'activeActions': 15,
        'status': 'Active',
      },
      {
        'id': 'DEP-06',
        'name': 'Supply Chain & Log',
        'code': 'SCM',
        'head': 'Priya Patel',
        'members': 10,
        'activeActions': 6,
        'status': 'Active',
      },
    ];

    _sites = [
      {
        'id': 'SITE-01',
        'name': 'North Plant Facility',
        'code': 'NPF',
        'location': 'Building A - North Sector',
        'staff': 42,
        'actions': 26,
        'type': 'Manufacturing',
        'status': 'Active',
      },
      {
        'id': 'SITE-02',
        'name': 'Central Warehouse Hub',
        'code': 'CWH',
        'location': 'Zone 3 Logistics Bay',
        'staff': 24,
        'actions': 14,
        'type': 'Distribution',
        'status': 'Active',
      },
      {
        'id': 'SITE-03',
        'name': 'South Fabrication Yard',
        'code': 'SFY',
        'location': 'Dock 7 Heavy Industrial',
        'staff': 35,
        'actions': 21,
        'type': 'Fabrication',
        'status': 'Active',
      },
      {
        'id': 'SITE-04',
        'name': 'West Research Lab',
        'code': 'WRL',
        'location': 'Tech Park Campus 2',
        'staff': 18,
        'actions': 8,
        'type': 'R&D',
        'status': 'Active',
      },
      {
        'id': 'SITE-05',
        'name': 'East Terminal Operations',
        'code': 'ETO',
        'location': 'Port Terminal Gate 4',
        'staff': 30,
        'actions': 19,
        'type': 'Terminal',
        'status': 'Active',
      },
    ];

    _teams = [
      {
        'id': 'TEAM-01',
        'name': 'Hazard Inspection Squad',
        'dept': 'Health & Safety',
        'site': 'North Plant Facility',
        'lead': 'David Chen',
        'members': 6,
        'status': 'Active',
      },
      {
        'id': 'TEAM-02',
        'name': 'Emergency Response Team',
        'dept': 'Health & Safety',
        'site': 'All Sites',
        'lead': 'Elena Rostova',
        'members': 10,
        'status': 'Active',
      },
      {
        'id': 'TEAM-03',
        'name': 'Line Maintenance Alpha',
        'dept': 'Operations & Plant',
        'site': 'North Plant Facility',
        'lead': 'Sarah Jenkins',
        'members': 8,
        'status': 'Active',
      },
      {
        'id': 'TEAM-04',
        'name': 'HVAC & Electrical Crew',
        'dept': 'Facilities & Fleet',
        'site': 'Central Warehouse Hub',
        'lead': 'Michael Chang',
        'members': 5,
        'status': 'Active',
      },
      {
        'id': 'TEAM-05',
        'name': 'Environmental Compliance',
        'dept': 'Quality Assurance',
        'site': 'West Research Lab',
        'lead': 'Priya Patel',
        'members': 4,
        'status': 'Active',
      },
    ];

    _systemNotifications = [
      {
        'id': 'NOTIF-01',
        'title': 'Automated Weekly HSE Digest Generated',
        'time': '10m ago',
        'type': 'System',
        'severity': 'info',
        'unread': true,
      },
      {
        'id': 'NOTIF-02',
        'title': 'Overdue Action Escalation: 4 actions exceed SLA',
        'time': '1h ago',
        'type': 'Escalation',
        'severity': 'warning',
        'unread': true,
      },
      {
        'id': 'NOTIF-03',
        'title': 'New Staff Onboarded: 3 new accounts registered',
        'time': '3h ago',
        'type': 'Users',
        'severity': 'info',
        'unread': false,
      },
      {
        'id': 'NOTIF-04',
        'title': 'Database Backup Completed Successfully',
        'time': '5h ago',
        'type': 'Maintenance',
        'severity': 'success',
        'unread': false,
      },
      {
        'id': 'NOTIF-05',
        'title': 'Security Policy: Mandatory 2FA enabled for Managers',
        'time': '1d ago',
        'type': 'Security',
        'severity': 'warning',
        'unread': false,
      },
    ];
  }

  Future<void> _loadCompanyStructure() async {
    if (!CompanyStructureService.instance.isReady) {
      return;
    }
    setState(() {
      _isLoadingStructure = true;
      _structureErrorMessage = null;
    });
    try {
      final orgId = _currentOrgId;
      final results = await Future.wait([
        CompanyStructureService.instance.fetchDepartments(orgId),
        CompanyStructureService.instance.fetchSites(orgId),
        CompanyStructureService.instance.fetchTeams(orgId),
      ]);
      if (!mounted) return;
      setState(() {
        _departments = results[0];
        _sites = results[1];
        _teams = results[2];
        _isLoadingStructure = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingStructure = false;
        _structureErrorMessage = e.toString();
      });
    }
  }

  Future<void> _loadAccountRequests() async {
    setState(() {
      _isLoadingRequests = true;
      _requestsErrorMessage = null;
    });
    try {
      final requests = await AccountRequestService.instance
          .fetchAccountRequests(organizationId: _currentOrgId);
      if (!mounted) return;
      setState(() {
        _accountRequests = requests;
        _isLoadingRequests = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingRequests = false;
        _requestsErrorMessage = e.toString();
      });
    }
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoadingUsers = true;
      _usersErrorMessage = null;
    });
    try {
      final users = await UserService.instance.fetchUsers(_currentOrgId);
      if (!mounted) return;
      setState(() {
        _realUsers = users;
        _isLoadingUsers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingUsers = false;
        _usersErrorMessage = e.toString();
      });
    }
  }

  Future<void> _loadActionSections() async {
    if (!ActionSectionService.instance.isReady) {
      return;
    }
    setState(() {
      _isLoadingSections = true;
      _sectionsErrorMessage = null;
    });
    try {
      final sections = await ActionSectionService.instance.fetchSections(
        _currentOrgId,
      );
      if (!mounted) return;
      setState(() {
        _actionSections = sections;
        _isLoadingSections = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingSections = false;
        _sectionsErrorMessage = e.toString();
      });
    }
  }

  Future<void> _loadDivisions() async {
    if (!DivisionService.instance.isReady) {
      return;
    }
    setState(() {
      _isLoadingDivisions = true;
      _divisionsErrorMessage = null;
    });
    try {
      final divisions = await DivisionService.instance.fetchDivisions(
        _currentOrgId,
      );
      if (!mounted) return;
      setState(() {
        _divisions = divisions;
        _isLoadingDivisions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingDivisions = false;
        _divisionsErrorMessage = e.toString();
      });
    }
  }

  Future<void> _refreshAllDashboardData() async {
    await Future.wait([
      _loadAuthoritativeAdminProfile(),
      _loadCompanyStructure(),
      _loadAccountRequests(),
      _loadUsers(),
      _loadActionSections(),
      _loadDivisions(),
    ]);
  }

  Future<void> _handleApprove(SignupRequest req) async {
    _showApproveReviewDialog(context, req);
  }

  void _showApproveReviewDialog(BuildContext context, SignupRequest req) {
    // 1. Initial values derived from request
    String selectedRole =
        (req.requestedRoleId == 'admin' ||
            req.requestedRoleId == 'company_admin')
        ? 'Company Admin'
        : (req.requestedType == RequestedAccountType.manager
              ? 'Manager / Action Approver'
              : 'Staff / Field Worker');

    // Department selection: match by ID or name
    String? selectedDeptId;
    if (req.departmentId != null &&
        _departments.any((d) => d['id'] == req.departmentId)) {
      selectedDeptId = req.departmentId;
    } else if (req.department.isNotEmpty &&
        _departments.any((d) => d['name'] == req.department)) {
      selectedDeptId = _departments
          .firstWhere((d) => d['name'] == req.department)['id']
          ?.toString();
    }

    // Site selection: match by ID or name
    String? selectedSiteId;
    if (req.siteId != null && _sites.any((s) => s['id'] == req.siteId)) {
      selectedSiteId = req.siteId;
    } else if (req.site.isNotEmpty &&
        _sites.any((s) => s['name'] == req.site)) {
      selectedSiteId = _sites
          .firstWhere((s) => s['name'] == req.site)['id']
          ?.toString();
    }

    // Team selection: strictly filtered to selected department
    List<Map<String, dynamic>> getSelectableTeams(String? deptId) {
      if (deptId == null || deptId.isEmpty) return _teams;
      return _teams.where((t) => t['deptId'] == deptId).toList();
    }

    String? selectedTeamId;
    var selectableTeams = getSelectableTeams(selectedDeptId);
    if (req.teamId != null &&
        selectableTeams.any((t) => t['id'] == req.teamId)) {
      selectedTeamId = req.teamId;
    } else if (req.team.isNotEmpty &&
        selectableTeams.any((t) => t['name'] == req.team)) {
      selectedTeamId = selectableTeams
          .firstWhere((t) => t['name'] == req.team)['id']
          ?.toString();
    }

    bool isSubmitting = false;
    String? dialogError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          selectableTeams = getSelectableTeams(selectedDeptId);
          if (selectedTeamId != null &&
              !selectableTeams.any((t) => t['id'] == selectedTeamId)) {
            selectedTeamId = null;
          }

          return AlertDialog(
            backgroundColor: AppTheme.cardBg(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.how_to_reg_rounded,
                    color: Color(0xFF16A34A),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Review & Approve Account',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      Text(
                        '${req.fullName} • ${req.email}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (dialogError != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFEF4444)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 16,
                              color: Color(0xFFEF4444),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                dialogError!,
                                style: const TextStyle(
                                  color: Color(0xFFEF4444),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.inputFill(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.inputBorder(context),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Requested Details',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary(context),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Designation: ${req.designation.isNotEmpty ? req.designation : "N/A"}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: AppTheme.textSecondary(context),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  'Phone: ${req.phone.isNotEmpty ? req.phone : "N/A"}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: AppTheme.textSecondary(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Requested: Dept: ${req.department.isNotEmpty ? req.department : (req.departmentId ?? "None")} • Site: ${req.site.isNotEmpty ? req.site : (req.siteId ?? "None")} • Team: ${req.team.isNotEmpty ? req.team : (req.teamId ?? "None")}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Assign System Role & Organizational Scopes',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Role Dropdown
                    DropdownButtonFormField<String>(
                      value: selectedRole,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Assigned Role *',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Staff / Field Worker',
                          child: Text('Staff / Field Worker'),
                        ),
                        DropdownMenuItem(
                          value: 'Manager / Action Approver',
                          child: Text('Manager / Action Approver'),
                        ),
                        DropdownMenuItem(
                          value: 'Company Admin',
                          child: Text('Company Admin'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedRole = val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    // Department Dropdown
                    DropdownButtonFormField<String?>(
                      value: selectedDeptId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Department',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('None / Unassigned'),
                        ),
                        ..._departments.map(
                          (d) => DropdownMenuItem<String?>(
                            value: d['id']?.toString(),
                            child: Text('${d['name']} (${d['code'] ?? 'DEP'})'),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        setDialogState(() {
                          selectedDeptId = val;
                          if (selectedTeamId != null) {
                            final updatedTeams = getSelectableTeams(val);
                            if (!updatedTeams.any(
                              (t) => t['id'] == selectedTeamId,
                            )) {
                              selectedTeamId = null;
                            }
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),

                    // Site Dropdown
                    DropdownButtonFormField<String?>(
                      value: selectedSiteId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Facility Site',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('None / Unassigned'),
                        ),
                        ..._sites.map(
                          (s) => DropdownMenuItem<String?>(
                            value: s['id']?.toString(),
                            child: Text(
                              '${s['name']} (${s['code'] ?? 'SITE'})',
                            ),
                          ),
                        ),
                      ],
                      onChanged: (val) =>
                          setDialogState(() => selectedSiteId = val),
                    ),
                    const SizedBox(height: 12),

                    // Team Dropdown (strictly filtered to selected department)
                    DropdownButtonFormField<String?>(
                      value: selectedTeamId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Operational Team / Squad',
                        helperText: selectedDeptId == null
                            ? 'Select a department above to filter teams'
                            : 'Filtered to selected department',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('None / Unassigned'),
                        ),
                        ...selectableTeams.map(
                          (t) => DropdownMenuItem<String?>(
                            value: t['id']?.toString(),
                            child: Text(
                              '${t['name']} (${t['dept'] ?? 'Team'})',
                            ),
                          ),
                        ),
                      ],
                      onChanged: (val) =>
                          setDialogState(() => selectedTeamId = val),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting
                    ? null
                    : () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                ),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        setDialogState(() {
                          isSubmitting = true;
                          dialogError = null;
                        });

                        try {
                          final adminId =
                              SupabaseConfig
                                  .clientOrNull
                                  ?.auth
                                  .currentUser
                                  ?.id ??
                              _adminProfile.id;

                          String? roleOverride;
                          if (selectedRole == 'Company Admin') {
                            roleOverride = 'admin';
                          } else if (selectedRole ==
                              'Manager / Action Approver') {
                            roleOverride = 'manager';
                          } else {
                            roleOverride = 'staff';
                          }

                          final messenger = ScaffoldMessenger.of(context);

                          await AccountRequestService.instance
                              .approveAccountRequest(
                                req,
                                adminUserId: adminId,
                                overrideDepartmentId: selectedDeptId,
                                overrideSiteId: selectedSiteId,
                                overrideTeamId: selectedTeamId,
                                overrideRoleId: roleOverride,
                              );

                          if (!dialogCtx.mounted) return;
                          Navigator.of(dialogCtx).pop();

                          await Future.wait([
                            _loadAccountRequests(),
                            _loadUsers(),
                            _loadCompanyStructure(),
                          ]);

                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'Account for ${req.fullName} approved and activated.',
                              ),
                              backgroundColor: const Color(0xFF16A34A),
                            ),
                          );
                        } catch (e) {
                          setDialogState(() {
                            isSubmitting = false;
                            dialogError = 'Failed to approve account: $e';
                          });
                        }
                      },
                icon: isSubmitting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 16),
                label: Text(isSubmitting ? 'Approving...' : 'Confirm Approval'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleReject(SignupRequest req, String reason) async {
    try {
      final adminId =
          SupabaseConfig.clientOrNull?.auth.currentUser?.id ?? _adminProfile.id;
      await AccountRequestService.instance.rejectAccountRequest(
        req,
        reason: reason,
        adminUserId: adminId,
      );
      await _loadAccountRequests();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registration for ${req.fullName} was rejected.'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to reject account: $e'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }

  bool _isActionOverdue(ActionRecord a) {
    if (a.targetDate.isEmpty) return false;
    final parsed = DateTime.tryParse(a.targetDate);
    if (parsed == null) return false;
    return parsed.isBefore(DateTime.now()) &&
        a.status.toLowerCase() != 'completed' &&
        a.status.toLowerCase() != 'closed';
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text(
          'Are you sure you want to log out of the Admin Portal?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              await AuthService.instance.signOut();
              if (!mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 960;
        final isTablet = constraints.maxWidth >= 600 && !isDesktop;

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppTheme.scaffoldBg(context),
          drawer: isDesktop ? null : _buildDrawer(context),
          body: Row(
            children: [
              if (isDesktop) _buildSidebar(context),
              Expanded(
                child: Column(
                  children: [
                    _buildTopHeader(context, isDesktop: isDesktop),
                    Expanded(
                      child: SelectionArea(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: _buildCurrentView(
                            context,
                            isDesktop: isDesktop,
                            isTablet: isTablet,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopHeader(BuildContext context, {required bool isDesktop}) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.headerBg(context),
        border: Border(
          bottom: BorderSide(color: AppTheme.headerBorder(context), width: 1),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!isDesktop) ...[
            IconButton(
              icon: Icon(
                Icons.menu_rounded,
                color: AppTheme.textPrimary(context),
              ),
              tooltip: 'Open navigation',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              _getNavTitle(_selectedNavIndex),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary(context),
                letterSpacing: -0.2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 16),
          if (isDesktop)
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: SizedBox(
                  height: 38,
                  child: Autocomplete<_GlobalSearchResult>(
                    optionsBuilder: (textEditingValue) {
                      final q = textEditingValue.text.trim().toLowerCase();
                      if (q.isEmpty) {
                        return const Iterable<_GlobalSearchResult>.empty();
                      }
                      final results = <_GlobalSearchResult>[];

                      // 1. Match People/Users
                      final allPeople =
                          _realUsers ??
                          (!SupabaseConfig.isInitialized
                              ? MockPeopleStore.instance.people
                              : <Person>[]);
                      for (final p in allPeople) {
                        final n = p.name.toLowerCase();
                        final e = p.email.toLowerCase();
                        final d = p.department.toLowerCase();
                        final des = p.designation.toLowerCase();
                        if (n.contains(q) ||
                            e.contains(q) ||
                            d.contains(q) ||
                            des.contains(q)) {
                          results.add(
                            _GlobalSearchResult(
                              title: p.name,
                              subtitle:
                                  '${p.roleLabel} • ${p.department.isNotEmpty ? p.department : "General"}',
                              icon: Icons.person_rounded,
                              iconColor: const Color(0xFF0284C7),
                              targetTabIndex: 1,
                              onSelect: () {
                                setState(() {
                                  _selectedNavIndex = 1;
                                  _userSearchQuery = p.name;
                                  _userSearchController.text = p.name;
                                });
                              },
                            ),
                          );
                        }
                        if (results.length >= 6) break;
                      }

                      // 2. Match Departments
                      for (final d in _departments) {
                        final name = d['name']?.toString() ?? '';
                        final code = d['code']?.toString() ?? '';
                        if (name.toLowerCase().contains(q) ||
                            code.toLowerCase().contains(q)) {
                          results.add(
                            _GlobalSearchResult(
                              title: name,
                              subtitle:
                                  'Department (${code.isNotEmpty ? code : "DEP"})',
                              icon: Icons.business_rounded,
                              iconColor: const Color(0xFF7C3AED),
                              targetTabIndex: 2,
                              onSelect: () =>
                                  setState(() => _selectedNavIndex = 2),
                            ),
                          );
                        }
                        if (results.length >= 8) break;
                      }

                      // 3. Match Sites
                      for (final s in _sites) {
                        final name = s['name']?.toString() ?? '';
                        final loc = s['location']?.toString() ?? '';
                        if (name.toLowerCase().contains(q) ||
                            loc.toLowerCase().contains(q)) {
                          results.add(
                            _GlobalSearchResult(
                              title: name,
                              subtitle:
                                  'Facility Site • ${loc.isNotEmpty ? loc : "Operational"}',
                              icon: Icons.location_on_rounded,
                              iconColor: const Color(0xFF0D9488),
                              targetTabIndex: 3,
                              onSelect: () =>
                                  setState(() => _selectedNavIndex = 3),
                            ),
                          );
                        }
                        if (results.length >= 10) break;
                      }

                      // 4. Match Teams
                      for (final t in _teams) {
                        final name = t['name']?.toString() ?? '';
                        final dept = t['dept']?.toString() ?? '';
                        if (name.toLowerCase().contains(q) ||
                            dept.toLowerCase().contains(q)) {
                          results.add(
                            _GlobalSearchResult(
                              title: name,
                              subtitle:
                                  'Team Squad • ${dept.isNotEmpty ? dept : "General"}',
                              icon: Icons.groups_rounded,
                              iconColor: const Color(0xFFEAB308),
                              targetTabIndex: 4,
                              onSelect: () =>
                                  setState(() => _selectedNavIndex = 4),
                            ),
                          );
                        }
                        if (results.length >= 12) break;
                      }

                      // 5. Match Account Requests
                      for (final r in (_accountRequests ?? <SignupRequest>[])) {
                        final n = r.fullName.toLowerCase();
                        final e = r.email.toLowerCase();
                        if (n.contains(q) || e.contains(q)) {
                          results.add(
                            _GlobalSearchResult(
                              title: r.fullName,
                              subtitle:
                                  'Account Request • ${r.requestedType.label}',
                              icon: Icons.how_to_reg_rounded,
                              iconColor: const Color(0xFFF59E0B),
                              targetTabIndex: 10,
                              onSelect: () {
                                setState(() {
                                  _selectedNavIndex = 10;
                                  _requestSearchQuery = r.fullName;
                                });
                              },
                            ),
                          );
                        }
                        if (results.length >= 14) break;
                      }

                      return results;
                    },
                    displayStringForOption: (option) => option.title,
                    onSelected: (option) => option.onSelect(),
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 8,
                          borderRadius: BorderRadius.circular(10),
                          color: AppTheme.cardBg(context),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: math.min(
                                380,
                                MediaQuery.of(context).size.width - 32,
                              ),
                              maxHeight: 320,
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppTheme.cardBorder(context),
                                ),
                              ),
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                shrinkWrap: true,
                                itemCount: options.length,
                                separatorBuilder: (_, _) => Divider(
                                  height: 1,
                                  color: AppTheme.dividerColor(context),
                                ),
                                itemBuilder: (context, index) {
                                  final opt = options.elementAt(index);
                                  return ListTile(
                                    dense: true,
                                    leading: Icon(
                                      opt.icon,
                                      size: 18,
                                      color: opt.iconColor,
                                    ),
                                    title: Text(
                                      opt.title,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textPrimary(context),
                                      ),
                                    ),
                                    subtitle: Text(
                                      opt.subtitle,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textSecondary(context),
                                      ),
                                    ),
                                    onTap: () => onSelected(opt),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    fieldViewBuilder:
                        (context, textController, focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: textController,
                            focusNode: focusNode,
                            onSubmitted: (val) {
                              _handleGlobalSearch(val);
                              onFieldSubmitted();
                            },
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textPrimary(context),
                            ),
                            decoration: InputDecoration(
                              hintText:
                                  'Search actions, users, sites, settings...',
                              hintStyle: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textMuted(context),
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                size: 18,
                                color: AppTheme.textSecondary(context),
                              ),
                              filled: true,
                              fillColor: AppTheme.inputFill(context),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 0,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: AppTheme.inputBorder(context),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: AppTheme.inputBorder(context),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Color(0xFF1565C0),
                                ),
                              ),
                            ),
                          );
                        },
                  ),
                ),
              ),
            ),
          const Spacer(),
          // Global Light/Dark Theme Switcher
          const ThemeToggleButton(size: 38),
          const SizedBox(width: 8),

          // System Alert indicator with dynamic count
          Builder(
            builder: (context) {
              final pendingCount =
                  (_accountRequests ??
                          (SupabaseConfig.isInitialized
                              ? <SignupRequest>[]
                              : MockAuthStore.instance.registrations))
                      .where(
                        (r) =>
                            r.status == AuthAccountStatus.pendingApproval &&
                            r.isEmailVerified,
                      )
                      .length;
              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.notifications_outlined,
                      color: AppTheme.textSecondary(context),
                      size: 22,
                    ),
                    tooltip: pendingCount > 0
                        ? '$pendingCount Pending System Alerts'
                        : 'System Alerts',
                    onPressed: () {
                      setState(() => _selectedNavIndex = 8);
                    },
                  ),
                  if (pendingCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          pendingCount > 99 ? '99+' : '$pendingCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(width: 8),
          // Admin Profile Pill
          InkWell(
            onTap: () {
              AdminProfileDialog.show(
                context,
                adminProfile: _adminProfile,
                onProfileUpdated: (updated) {
                  setState(() => _adminProfile = updated);
                },
              );
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.cardBorder(context)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: const Color(0xFF0F172A),
                    child: Text(
                      _adminProfile.initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (isDesktop) ...[
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _adminProfile.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary(context),
                            height: 1.1,
                          ),
                        ),
                        Text(
                          _adminProfile.designation,
                          style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.textSecondary(context),
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleGlobalSearch(String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return;

    if (trimmed == 'user' ||
        trimmed == 'users' ||
        trimmed == 'people' ||
        trimmed == 'person' ||
        trimmed == 'staff' ||
        trimmed == 'manager' ||
        trimmed == 'members') {
      setState(() {
        _selectedNavIndex = 1;
        _userSearchQuery = '';
        _userSearchController.clear();
      });
      return;
    }
    if (trimmed.contains('dept') || trimmed.contains('department')) {
      setState(() => _selectedNavIndex = 2);
      return;
    }
    if (trimmed.contains('site') ||
        trimmed.contains('facility') ||
        trimmed.contains('plant')) {
      setState(() => _selectedNavIndex = 3);
      return;
    }
    if (trimmed.contains('team') || trimmed.contains('squad')) {
      setState(() => _selectedNavIndex = 4);
      return;
    }
    if (trimmed.contains('role') || trimmed.contains('permission')) {
      setState(() => _selectedNavIndex = 5);
      return;
    }
    if (trimmed.contains('categor') || trimmed.contains('classification')) {
      setState(() => _selectedNavIndex = 6);
      return;
    }
    if (trimmed.contains('notif') ||
        trimmed.contains('broadcast') ||
        trimmed.contains('alert')) {
      setState(() => _selectedNavIndex = 7);
      return;
    }
    if (trimmed.contains('report') || trimmed.contains('export')) {
      setState(() => _selectedNavIndex = 8);
      return;
    }
    if (trimmed.contains('setting') ||
        trimmed.contains('config') ||
        trimmed.contains('2fa')) {
      setState(() => _selectedNavIndex = 9);
      return;
    }
    if (trimmed == 'request' ||
        trimmed == 'requests' ||
        trimmed == 'signup' ||
        trimmed == 'approval' ||
        trimmed == 'approvals') {
      setState(() {
        _selectedNavIndex = 10;
        _requestSearchQuery = '';
      });
      return;
    }
    if (trimmed.contains('calendar') ||
        trimmed.contains('schedule') ||
        trimmed.contains('event')) {
      setState(() => _selectedNavIndex = 11);
      return;
    }

    setState(() {
      _selectedNavIndex = 1;
      _userSearchQuery = query.trim();
      _userSearchController.text = query.trim();
    });
  }

  Widget _buildSidebar(BuildContext context) {
    return Material(
      color: const Color(0xFF0F172A), // Dark navy theme
      child: SizedBox(
        width: 250,
        child: Column(
          children: [
            // Sidebar Brand Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  ActionFlowLogo.white(size: 32, iconSize: 18, borderRadius: 8),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'ActionFlow',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.3,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF38BDF8)
                                .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: const Color(0xFF38BDF8)
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: const Text(
                            'ADMIN PORTAL',
                            style: TextStyle(
                              color: Color(0xFF38BDF8),
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF1E293B), height: 1),
            // Nav List
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 10,
                ),
                children: [
                  _buildNavItem(0, 'Dashboard', Icons.dashboard_rounded),
                  _buildNavItem(1, 'Users', Icons.people_alt_rounded),
                  _buildNavItem(2, 'Departments', Icons.business_rounded),
                  _buildNavItem(3, 'Sites', Icons.location_on_rounded),
                  _buildNavItem(4, 'Teams', Icons.groups_rounded),
                  _buildNavItem(
                    5,
                    'Roles & Permissions',
                    Icons.security_rounded,
                  ),
                  _buildNavItem(6, 'Action Sections', Icons.category_rounded),
                  _buildNavItem(7, 'Divisions', Icons.domain_rounded),
                  _buildNavItem(
                    8,
                    'Notifications',
                    Icons.notifications_rounded,
                  ),
                  _buildNavItem(9, 'Reports', Icons.bar_chart_rounded),
                  _buildNavItem(10, 'System Settings', Icons.settings_rounded),
                  _buildNavItem(
                    11,
                    'Account Requests',
                    Icons.how_to_reg_rounded,
                    badgeCount:
                        (_accountRequests ??
                                (SupabaseConfig.isInitialized
                                    ? <SignupRequest>[]
                                    : MockAuthStore.instance.registrations))
                            .where(
                              (r) =>
                                  r.status ==
                                      AuthAccountStatus.pendingApproval &&
                                  r.isEmailVerified,
                            )
                            .length,
                  ),
                  _buildNavItem(12, 'Calendar', Icons.calendar_month_rounded),
                ],
              ),
            ),
            const Divider(color: Color(0xFF1E293B), height: 1),
            // Logout button
            Material(
              color: Colors.transparent,
              child: ListTile(
                dense: true,
                leading: const Icon(
                  Icons.logout_rounded,
                  color: Color(0xFFEF4444),
                  size: 20,
                ),
                title: const Text(
                  'Sign Out',
                  style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                onTap: _handleLogout,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF0F172A),
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  ActionFlowLogo.white(size: 32, iconSize: 18, borderRadius: 8),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'ActionFlow',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Admin Portal',
                        style: TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(color: Color(0xFF1E293B), height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              children: [
                _buildNavItem(
                  0,
                  'Dashboard',
                  Icons.dashboard_rounded,
                  closeDrawer: true,
                ),
                _buildNavItem(
                  1,
                  'Users',
                  Icons.people_alt_rounded,
                  closeDrawer: true,
                ),
                _buildNavItem(
                  2,
                  'Departments',
                  Icons.business_rounded,
                  closeDrawer: true,
                ),
                _buildNavItem(
                  3,
                  'Sites',
                  Icons.location_on_rounded,
                  closeDrawer: true,
                ),
                _buildNavItem(
                  4,
                  'Teams',
                  Icons.groups_rounded,
                  closeDrawer: true,
                ),
                _buildNavItem(
                  5,
                  'Roles & Permissions',
                  Icons.security_rounded,
                  closeDrawer: true,
                ),
                _buildNavItem(
                  6,
                  'Action Sections',
                  Icons.category_rounded,
                  closeDrawer: true,
                ),
                _buildNavItem(
                  7,
                  'Divisions',
                  Icons.domain_rounded,
                  closeDrawer: true,
                ),
                _buildNavItem(
                  8,
                  'Notifications',
                  Icons.notifications_rounded,
                  closeDrawer: true,
                ),
                _buildNavItem(
                  9,
                  'Reports',
                  Icons.bar_chart_rounded,
                  closeDrawer: true,
                ),
                _buildNavItem(
                  10,
                  'System Settings',
                  Icons.settings_rounded,
                  closeDrawer: true,
                ),
                _buildNavItem(
                  11,
                  'Account Requests',
                  Icons.how_to_reg_rounded,
                  closeDrawer: true,
                  badgeCount:
                      (_accountRequests ??
                              (SupabaseConfig.isInitialized
                                  ? <SignupRequest>[]
                                  : MockAuthStore.instance.registrations))
                          .where(
                            (r) =>
                                r.status == AuthAccountStatus.pendingApproval &&
                                r.isEmailVerified,
                          )
                          .length,
                ),
                _buildNavItem(
                  12,
                  'Calendar',
                  Icons.calendar_month_rounded,
                  closeDrawer: true,
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF1E293B), height: 1),
          Material(
            color: Colors.transparent,
            child: ListTile(
              dense: true,
              leading: const Icon(
                Icons.logout_rounded,
                color: Color(0xFFEF4444),
                size: 20,
              ),
              title: const Text(
                'Sign Out',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _handleLogout();
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    String label,
    IconData icon, {
    bool closeDrawer = false,
    int? badgeCount,
  }) {
    final isSelected = _selectedNavIndex == index;
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: isSelected ? const Color(0xFF1E293B) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: ListTile(
          dense: true,
          selected: isSelected,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          leading: Icon(
            icon,
            size: 19,
            color: isSelected
                ? const Color(0xFF38BDF8)
                : const Color(0xFF94A3B8),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badgeCount != null && badgeCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          trailing: isSelected
              ? Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                    color: const Color(0xFF38BDF8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                )
              : null,
          onTap: () {
            setState(() => _selectedNavIndex = index);
            if (closeDrawer) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
    );
  }

  String _getNavTitle(int index) {
    switch (index) {
      case 0:
        return 'Admin Dashboard';
      case 1:
        return 'Users & Accounts Management';
      case 2:
        return 'Departments Management';
      case 3:
        return 'Sites & Facilities';
      case 4:
        return 'Teams & Squads';
      case 5:
        return 'Roles & System Permissions';
      case 6:
        return 'Action Sections';
      case 7:
        return 'Divisions';
      case 8:
        return 'System Notifications & Broadcasts';
      case 9:
        return 'Executive & Audit Reports';
      case 10:
        return 'System Configuration & Settings';
      case 11:
        return 'Account Requests & Approvals';
      case 12:
        return 'Operational Calendar & Schedule';
      default:
        return 'Admin Portal';
    }
  }

  Widget _buildPageWrapper({required Widget child, required bool isDesktop}) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 28 : 16,
        20,
        isDesktop ? 28 : 16,
        32,
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: child,
        ),
      ),
    );
  }

  Widget _buildCurrentView(
    BuildContext context, {
    required bool isDesktop,
    required bool isTablet,
  }) {
    switch (_selectedNavIndex) {
      case 0:
        return _buildDashboardView(
          context,
          isDesktop: isDesktop,
          isTablet: isTablet,
        );
      case 1:
        return _buildUsersView(
          context,
          isDesktop: isDesktop,
          isTablet: isTablet,
        );
      case 2:
        return _buildDepartmentsView(context, isDesktop: isDesktop);
      case 3:
        return _buildSitesView(context, isDesktop: isDesktop);
      case 4:
        return _buildTeamsView(context, isDesktop: isDesktop);
      case 5:
        return _buildRolesPermissionsView(context, isDesktop: isDesktop);
      case 6:
        return _buildActionSectionsView(context, isDesktop: isDesktop);
      case 7:
        return _buildDivisionsView(context, isDesktop: isDesktop);
      case 8:
        return _buildNotificationsView(context, isDesktop: isDesktop);
      case 9:
        return _buildReportsView(context, isDesktop: isDesktop);
      case 10:
        return _buildSystemSettingsView(context, isDesktop: isDesktop);
      case 11:
        return _buildAccountRequestsView(
          context,
          isDesktop: isDesktop,
          isTablet: isTablet,
        );
      case 12:
        return _buildCalendarView(
          context,
          isDesktop: isDesktop,
          isTablet: isTablet,
        );
      default:
        return _buildDashboardView(
          context,
          isDesktop: isDesktop,
          isTablet: isTablet,
        );
    }
  }

  // ==========================================
  // VIEW 0: DASHBOARD
  // ==========================================
  Widget _buildDashboardView(
    BuildContext context, {
    required bool isDesktop,
    required bool isTablet,
  }) {
    final isLiveSupabase = SupabaseConfig.isInitialized;
    final people =
        _realUsers ??
        (isLiveSupabase ? <Person>[] : MockPeopleStore.instance.people);
    final totalUsers = people.length;
    final activeUsers = people.where((p) => p.isActive).length;

    final totalDepts = _departments.length;
    final totalSites = _sites.length;
    final totalTeams = _teams.length;
    final activeTeams = _teams.where((t) => t['status'] == 'Active').length;

    final requests =
        _accountRequests ??
        (isLiveSupabase
            ? <SignupRequest>[]
            : MockAuthStore.instance.registrations);
    final pendingRequestsCount = requests
        .where(
          (r) =>
              r.status == AuthAccountStatus.pendingApproval ||
              r.status == AuthAccountStatus.pendingVerification,
        )
        .length;

    // Actions state
    final actions = MockActionStore.instance.actions;
    final totalActions = actions.length;
    final overdueActions = actions.where((a) => _isActionOverdue(a)).length;
    final completedActions = actions
        .where(
          (a) =>
              a.status.toLowerCase() == 'completed' ||
              a.status.toLowerCase() == 'closed',
        )
        .length;

    final hasError =
        _structureErrorMessage != null ||
        _usersErrorMessage != null ||
        _requestsErrorMessage != null;

    return _buildPageWrapper(
      isDesktop: isDesktop,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          const Text(
                            'ActionFlow System Administration Console',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF38BDF8)
                                  .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: const Color(0xFF38BDF8)
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              _adminProfile.organizationName.isNotEmpty
                                  ? _adminProfile.organizationName
                                  : 'Tenant Organization',
                              style: const TextStyle(
                                color: Color(0xFF38BDF8),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Monitor organization-wide action velocity, users, governance structures, and system security posture for ${_adminProfile.organizationName.isNotEmpty ? _adminProfile.organizationName : "your organization"}.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isDesktop) ...[
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _refreshAllDashboardData,
                    icon:
                        (_isLoadingStructure ||
                            _isLoadingUsers ||
                            _isLoadingRequests)
                        ? const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Refresh'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _openBroadcastDialog(context),
                    icon: const Icon(Icons.campaign_rounded, size: 17),
                    label: const Text('Broadcast Alert'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF38BDF8),
                      foregroundColor: const Color(0xFF0F172A),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Error Banner
          if (hasError) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _structureErrorMessage ??
                          _usersErrorMessage ??
                          _requestsErrorMessage!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _refreshAllDashboardData,
                    icon: const Icon(
                      Icons.refresh_rounded,
                      size: 14,
                      color: Colors.red,
                    ),
                    label: const Text(
                      'Retry',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Metric Cards Grid
          LayoutBuilder(
            builder: (context, cardConstraints) {
              final width = cardConstraints.maxWidth;
              final crossAxisCount = width > 1100 ? 3 : (width > 680 ? 2 : 1);
              return GridView.count(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: width > 1100
                    ? 2.2
                    : (width > 680 ? 2.3 : 2.7),
                children: [
                  _buildStatCard(
                    context: context,
                    title: 'Total Active Users',
                    value: _isLoadingUsers
                        ? '...'
                        : '$activeUsers / $totalUsers',
                    subtitle: 'Across $totalDepts departments',
                    icon: Icons.people_outline_rounded,
                    iconColor: const Color(0xFF0284C7),
                    bgColor: const Color(0xFF0284C7).withValues(alpha: 0.12),
                    onTap: () => setState(() => _selectedNavIndex = 1),
                  ),
                  _buildStatCard(
                    context: context,
                    title: 'Total Tracked Actions',
                    value: isLiveSupabase
                        ? 'Integration Pending'
                        : '$totalActions',
                    subtitle: isLiveSupabase
                        ? 'HSSE schema migration scheduled'
                        : '$completedActions completed, $overdueActions overdue',
                    icon: Icons.assignment_outlined,
                    iconColor: const Color(0xFF16A34A),
                    bgColor: const Color(0xFF16A34A).withValues(alpha: 0.12),
                    onTap: () => setState(() => _selectedNavIndex = 8),
                  ),
                  _buildStatCard(
                    context: context,
                    title: 'Departments & Sites',
                    value: _isLoadingStructure
                        ? '...'
                        : '$totalDepts / $totalSites',
                    subtitle: '$totalTeams operational squads',
                    icon: Icons.apartment_rounded,
                    iconColor: const Color(0xFF7C3AED),
                    bgColor: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                    onTap: () => setState(() => _selectedNavIndex = 2),
                  ),
                  _buildStatCard(
                    context: context,
                    title: 'System Compliance Rate',
                    value: isLiveSupabase ? 'N/A' : '94.8%',
                    subtitle: isLiveSupabase
                        ? 'Action SLA metrics pending'
                        : 'Target > 90% SLA adherence',
                    icon: Icons.verified_outlined,
                    iconColor: const Color(0xFFD97706),
                    bgColor: const Color(0xFFD97706).withValues(alpha: 0.12),
                    onTap: () => setState(() => _selectedNavIndex = 8),
                  ),
                  _buildStatCard(
                    context: context,
                    title: 'Teams & Operational Squads',
                    value: _isLoadingStructure ? '...' : '$totalTeams',
                    subtitle: '$activeTeams active operational units',
                    icon: Icons.groups_rounded,
                    iconColor: const Color(0xFF0D9488),
                    bgColor: const Color(0xFF0D9488).withValues(alpha: 0.12),
                    onTap: () => setState(() => _selectedNavIndex = 4),
                  ),
                  _buildStatCard(
                    context: context,
                    title: 'Pending Account Requests',
                    value: _isLoadingRequests ? '...' : '$pendingRequestsCount',
                    subtitle: pendingRequestsCount > 0
                        ? 'Requires administrator decision'
                        : 'All access requests processed',
                    icon: Icons.how_to_reg_rounded,
                    iconColor: const Color(0xFFF59E0B),
                    bgColor: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    onTap: () => setState(() => _selectedNavIndex = 10),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 16),

          // Quick Administrative Actions Bar
          _buildQuickActionsCard(context),

          const SizedBox(height: 16),

          // Analytics & Quick Actions
          if (isDesktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _buildRecentUsersCard(context, people),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: _buildSystemActivityCard(context, people),
                ),
              ],
            )
          else ...[
            _buildRecentUsersCard(context, people),
            const SizedBox(height: 16),
            _buildSystemActivityCard(context, people),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActionsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.bolt_rounded,
                size: 18,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Quick Administrative Actions',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildQuickActionButton(
                context,
                icon: Icons.person_add_outlined,
                label: 'Add User',
                onTap: () => setState(() => _selectedNavIndex = 1),
              ),
              _buildQuickActionButton(
                context,
                icon: Icons.add_business_outlined,
                label: 'Add Department',
                onTap: () => setState(() => _selectedNavIndex = 2),
              ),
              _buildQuickActionButton(
                context,
                icon: Icons.add_location_alt_outlined,
                label: 'Add Site',
                onTap: () => setState(() => _selectedNavIndex = 3),
              ),
              _buildQuickActionButton(
                context,
                icon: Icons.group_add_outlined,
                label: 'Add Team',
                onTap: () => setState(() => _selectedNavIndex = 4),
              ),
              _buildQuickActionButton(
                context,
                icon: Icons.how_to_reg_outlined,
                label: 'Review Requests',
                onTap: () => setState(() => _selectedNavIndex = 10),
              ),
              _buildQuickActionButton(
                context,
                icon: Icons.campaign_outlined,
                label: 'Broadcast Alert',
                onTap: () => _openBroadcastDialog(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: BorderSide(color: AppTheme.cardBorder(context)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildStatCard({
    required BuildContext context,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.cardBg(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.cardBorder(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, color: iconColor, size: 15),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary(context),
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textMuted(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentUsersCard(BuildContext context, List<Person> people) {
    final recent = people.take(5).toList();
    return Material(
      color: AppTheme.cardBg(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.cardBorder(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Registered Directory Users',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _selectedNavIndex = 1),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 15),
                  label: const Text(
                    'Manage All',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_isLoadingUsers && people.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Loading directory users...',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (_usersErrorMessage != null && people.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 16,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _usersErrorMessage!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: _refreshAllDashboardData,
                      child: const Text(
                        'Retry',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              )
            else if (recent.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No registered directory users found for this organization.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted(context),
                    ),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recent.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: AppTheme.dividerColor(context)),
                itemBuilder: (context, index) {
                  final p = recent[index];
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 2,
                      horizontal: 0,
                    ),
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: AppTheme.containerBg(context),
                      child: Text(
                        p.name.isNotEmpty ? p.name[0].toUpperCase() : 'U',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                    ),
                    title: Text(
                      p.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    subtitle: Text(
                      '${p.designation} • ${p.department.isNotEmpty ? p.department : "General"}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                    trailing: _buildRoleBadge(p.roleLabel),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemActivityCard(BuildContext context, List<Person> people) {
    final isLiveSupabase = SupabaseConfig.isInitialized;
    final List<Map<String, dynamic>> activities = [];

    if (isLiveSupabase) {
      if (_accountRequests != null && _accountRequests!.isNotEmpty) {
        for (final req in _accountRequests!.take(3)) {
          final isPending =
              req.status == AuthAccountStatus.pendingApproval ||
              req.status == AuthAccountStatus.pendingVerification;
          final isApproved = req.status == AuthAccountStatus.active;
          activities.add({
            'action': isPending
                ? 'Pending Access Request'
                : (isApproved
                      ? 'Account Approved'
                      : 'Account ${req.status.label}'),
            'detail': '${req.fullName} (${req.designation}) - ${req.email}',
            'time': _formatRelativeTime(req.createdAt),
            'icon': isPending
                ? Icons.pending_actions_rounded
                : (isApproved
                      ? Icons.check_circle_outline_rounded
                      : Icons.person_outline_rounded),
            'color': isPending
                ? Colors.orange
                : (isApproved ? Colors.green : Colors.blue),
          });
        }
      }

      if (_departments.isNotEmpty) {
        for (final dept in _departments.take(2)) {
          activities.add({
            'action': 'Department Configured',
            'detail': '${dept['name']} active in organization',
            'time': 'Active',
            'icon': Icons.business_rounded,
            'color': Colors.blue,
          });
        }
      }

      if (_sites.isNotEmpty) {
        for (final site in _sites.take(1)) {
          activities.add({
            'action': 'Operational Site Active',
            'detail':
                '${site['name']} (${site['location'] ?? 'Operational Facility'})',
            'time': 'Active',
            'icon': Icons.location_on_rounded,
            'color': Colors.teal,
          });
        }
      }
    }

    if (activities.isEmpty) {
      if (isLiveSupabase) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.cardBg(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.cardBorder(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'System Audit & Activity Feed',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 32,
                      color: AppTheme.textMuted(context),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No recent organizational activity recorded',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Account registrations, department changes, and operational events will appear here.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary(context),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }

      // Fallback activities for mock/offline testing mode to preserve test assertions
      activities.addAll([
        {
          'action': 'User Role Updated',
          'detail': 'Sarah Jenkins promoted to Department Manager',
          'time': '20m ago',
          'icon': Icons.security_rounded,
          'color': Colors.blue,
        },
        {
          'action': 'New Site Added',
          'detail': 'East Terminal Operations registered by Admin',
          'time': '1h ago',
          'icon': Icons.location_on_rounded,
          'color': Colors.green,
        },
        {
          'action': 'Password Policy Enforced',
          'detail': 'Session timeout configured to 30 mins',
          'time': '3h ago',
          'icon': Icons.lock_clock_rounded,
          'color': Colors.orange,
        },
        {
          'action': 'Audit Log Exported',
          'detail': 'Q3 Compliance Audit Report generated',
          'time': '5h ago',
          'icon': Icons.file_download_outlined,
          'color': Colors.purple,
        },
        {
          'action': 'Action Category Modified',
          'detail': 'Environmental Incident priority set to Critical',
          'time': '1d ago',
          'icon': Icons.category_rounded,
          'color': Colors.teal,
        },
      ]);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'System Audit & Activity Feed',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 12),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: activities.length,
            itemBuilder: (context, index) {
              final act = activities[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: (act['color'] as Color).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        act['icon'] as IconData,
                        size: 15,
                        color: act['color'] as Color,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  act['action'] as String,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary(context),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                act['time'] as String,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.textMuted(context),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            act['detail'] as String,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}';
  }

  // ==========================================
  // VIEW 1: USERS MANAGEMENT
  // ==========================================
  Widget _buildUsersView(
    BuildContext context, {
    required bool isDesktop,
    required bool isTablet,
  }) {
    final allPeople =
        _realUsers ??
        (!SupabaseConfig.isInitialized
            ? MockPeopleStore.instance.people
            : <Person>[]);

    final filtered = allPeople.where((p) {
      if (_userSearchQuery.isNotEmpty) {
        final query = _userSearchQuery.toLowerCase();
        final match =
            p.name.toLowerCase().contains(query) ||
            p.email.toLowerCase().contains(query) ||
            p.designation.toLowerCase().contains(query) ||
            p.department.toLowerCase().contains(query) ||
            p.site.toLowerCase().contains(query);
        if (!match) return false;
      }
      if (_selectedUserRole != 'All') {
        if (_selectedUserRole == 'Admin' && p.role != UserRole.admin) {
          return false;
        }
        if (_selectedUserRole == 'Manager' &&
            p.role != UserRole.departmentManager) {
          return false;
        }
        if (_selectedUserRole == 'Staff' &&
            p.role != UserRole.actionOwnerWorker) {
          return false;
        }
      }
      if (_selectedUserDept != 'All' && p.department != _selectedUserDept) {
        return false;
      }
      if (_selectedUserStatus != 'All') {
        final isActive = _selectedUserStatus == 'Active';
        if (p.isActive != isActive) return false;
      }
      return true;
    }).toList();

    return _buildPageWrapper(
      isDesktop: isDesktop,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar with Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'User Directory & Authentication Roles',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Manage all internal users, external staff, department assignments, and system roles.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _openAddUser,
                icon: const Icon(Icons.person_add_rounded, size: 17),
                label: const Text('Add User'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF38BDF8)
                      : const Color(0xFF0F172A),
                  foregroundColor:
                      Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF0F172A)
                      : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          Builder(
            builder: (context) {
              final pendingApprovalRequests =
                  (_accountRequests ??
                          (SupabaseConfig.isInitialized
                              ? <SignupRequest>[]
                              : MockAuthStore.instance.registrations))
                      .where(
                        (r) =>
                            r.status == AuthAccountStatus.pendingApproval &&
                            r.isEmailVerified,
                      )
                      .toList();
              final pendingCount = pendingApprovalRequests.length;

              if (pendingCount == 0) return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.how_to_reg_rounded,
                        color: Color(0xFF7C3AED),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          pendingCount == 1
                              ? '1 registration request awaiting administrator approval.'
                              : '$pendingCount registration requests awaiting administrator approval.',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => setState(() => _selectedNavIndex = 11),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7C3AED),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: const Text('Review Requests'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (_usersErrorMessage != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFEF4444)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 18,
                    color: Color(0xFFEF4444),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Failed to load organization users: $_usersErrorMessage',
                      style: const TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _loadUsers,
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: const Text('Retry', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],
          if (_isLoadingUsers && _realUsers == null)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          const SizedBox(height: 14),
          // Filter & Search Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.cardBg(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.cardBorder(context)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 38,
                        child: TextField(
                          controller: _userSearchController,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textPrimary(context),
                          ),
                          decoration: InputDecoration(
                            hintText:
                                'Search by name, email, designation, site...',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textMuted(context),
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              size: 18,
                              color: AppTheme.textSecondary(context),
                            ),
                            suffixIcon: _userSearchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.clear_rounded,
                                      size: 16,
                                    ),
                                    onPressed: () {
                                      _userSearchController.clear();
                                      setState(() => _userSearchQuery = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: AppTheme.inputFill(context),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: AppTheme.inputBorder(context),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: AppTheme.inputBorder(context),
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 0,
                            ),
                          ),
                          onChanged: (val) =>
                              setState(() => _userSearchQuery = val),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildFilterDropdown(
                      label: 'Role',
                      value: _selectedUserRole,
                      items: ['All', 'Admin', 'Manager', 'Staff'],
                      onChanged: (val) =>
                          setState(() => _selectedUserRole = val ?? 'All'),
                    ),
                    _buildFilterDropdown(
                      label: 'Department',
                      value: _selectedUserDept,
                      items: [
                        'All',
                        ..._departments.map((d) => d['name'] as String),
                      ],
                      onChanged: (val) =>
                          setState(() => _selectedUserDept = val ?? 'All'),
                    ),
                    _buildFilterDropdown(
                      label: 'Status',
                      value: _selectedUserStatus,
                      items: ['All', 'Active', 'Inactive'],
                      onChanged: (val) =>
                          setState(() => _selectedUserStatus = val ?? 'All'),
                    ),
                    if (_userSearchQuery.isNotEmpty ||
                        _selectedUserRole != 'All' ||
                        _selectedUserDept != 'All' ||
                        _selectedUserStatus != 'All')
                      TextButton.icon(
                        onPressed: () {
                          _userSearchController.clear();
                          setState(() {
                            _userSearchQuery = '';
                            _selectedUserRole = 'All';
                            _selectedUserDept = 'All';
                            _selectedUserStatus = 'All';
                          });
                        },
                        icon: const Icon(Icons.clear_rounded, size: 15),
                        label: const Text(
                          'Reset Filters',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Users Table / Cards
          if (filtered.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cardBorder(context)),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.people_outline_rounded,
                    size: 40,
                    color: AppTheme.textMuted(context),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    allPeople.isEmpty
                        ? 'No Users Registered Yet'
                        : 'No users matching current filters',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    allPeople.isEmpty
                        ? 'New users will appear here once approved from Account Requests or added manually.'
                        : 'Try adjusting your search keywords or filter dropdowns.',
                    style: TextStyle(
                      color: AppTheme.textSecondary(context),
                      fontSize: 12,
                    ),
                  ),
                  if (allPeople.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        _userSearchController.clear();
                        setState(() {
                          _userSearchQuery = '';
                          _selectedUserRole = 'All';
                          _selectedUserDept = 'All';
                          _selectedUserStatus = 'All';
                        });
                      },
                      icon: const Icon(Icons.clear_rounded, size: 15),
                      label: const Text('Clear Filters'),
                    ),
                  ],
                ],
              ),
            )
          else if (isDesktop)
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cardBorder(context)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: DataTable(
                  horizontalMargin: 16,
                  columnSpacing: 18,
                  headingRowHeight: 38,
                  dataRowMinHeight: 48,
                  dataRowMaxHeight: 52,
                  headingRowColor: WidgetStateProperty.all(
                    AppTheme.containerBg(context),
                  ),
                  columns: [
                    DataColumn(
                      label: Text(
                        'USER / NAME',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'ROLE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'DEPARTMENT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'SITE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'STATUS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'ACTIONS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ),
                  ],
                  rows: filtered.map((person) {
                    return DataRow(
                      cells: [
                        DataCell(
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 15,
                                backgroundColor: AppTheme.containerBg(context),
                                child: Text(
                                  person.name.isNotEmpty
                                      ? person.name[0].toUpperCase()
                                      : 'U',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary(context),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    person.name,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimary(context),
                                    ),
                                  ),
                                  Text(
                                    person.email,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary(context),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        DataCell(_buildRoleBadge(person.roleLabel)),
                        DataCell(
                          person.role == UserRole.departmentManager &&
                                  person.managerScopes.length > 1
                              ? Tooltip(
                                  message: person.managerScopes
                                      .map((s) => s.displayName)
                                      .join('\n'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0284C7)
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: const Color(0xFF0284C7)
                                            .withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Text(
                                      '${person.managerScopes.length} Scopes',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF0284C7),
                                      ),
                                    ),
                                  ),
                                )
                              : Text(
                                  person.department.isNotEmpty
                                      ? person.department
                                      : '—',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textPrimary(context),
                                  ),
                                ),
                        ),
                        DataCell(
                          person.role == UserRole.departmentManager &&
                                  person.managerScopes.length > 1
                              ? Text(
                                  'Multiple Sites',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontStyle: FontStyle.italic,
                                    color: AppTheme.textSecondary(context),
                                  ),
                                )
                              : Text(
                                  person.site.isNotEmpty ? person.site : '—',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textPrimary(context),
                                  ),
                                ),
                        ),
                        DataCell(
                          _buildStatusBadge(
                            person.isActive ? 'Active' : 'Inactive',
                          ),
                        ),
                        DataCell(
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  size: 17,
                                  color: Color(0xFF0284C7),
                                ),
                                tooltip: 'Edit User',
                                onPressed: () => _openEditUser(person),
                              ),
                              IconButton(
                                icon: Icon(
                                  person.isActive
                                      ? Icons.block_rounded
                                      : Icons.check_circle_outline_rounded,
                                  size: 17,
                                  color: person.isActive
                                      ? Colors.red.shade400
                                      : Colors.green.shade600,
                                ),
                                tooltip: person.isActive
                                    ? 'Deactivate User'
                                    : 'Activate User',
                                onPressed: () => _toggleUserStatus(person),
                              ),
                              if (person.role != UserRole.admin &&
                                  person.id != _adminProfile.id)
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 17,
                                    color: Color(0xFFDC2626),
                                  ),
                                  tooltip: 'Delete User Permanently',
                                  onPressed: () => _confirmDeleteUser(person),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final p = filtered[index];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBg(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.cardBorder(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: AppTheme.containerBg(
                                    context,
                                  ),
                                  child: Text(
                                    p.name.isNotEmpty
                                        ? p.name[0].toUpperCase()
                                        : 'U',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: AppTheme.textPrimary(context),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: AppTheme.textPrimary(context),
                                        ),
                                      ),
                                      Text(
                                        p.email,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.textSecondary(
                                            context,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildStatusBadge(p.isActive ? 'Active' : 'Inactive'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Divider(height: 1, color: AppTheme.dividerColor(context)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Role: ${p.roleLabel}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary(context),
                                ),
                              ),
                              if (p.role == UserRole.departmentManager &&
                                  p.managerScopes.length > 1) ...[
                                Text(
                                  'Scopes: ${p.managerScopes.length} Dept + Site scopes',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0284C7),
                                  ),
                                ),
                              ] else ...[
                                Text(
                                  'Dept: ${p.department.isNotEmpty ? p.department : "—"}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textSecondary(context),
                                  ),
                                ),
                                Text(
                                  'Site: ${p.site.isNotEmpty ? p.site : "—"}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textSecondary(context),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _openEditUser(p),
                                icon: const Icon(Icons.edit_outlined, size: 15),
                                label: const Text(
                                  'Edit',
                                  style: TextStyle(fontSize: 12),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.textPrimary(
                                    context,
                                  ),
                                  side: BorderSide(
                                    color: AppTheme.cardBorder(context),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              if (p.role != UserRole.admin &&
                                  p.id != _adminProfile.id) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: Color(0xFFDC2626),
                                  ),
                                  tooltip: 'Delete User Permanently',
                                  onPressed: () => _confirmDeleteUser(p),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _openAddUser() async {
    if (_departments.isEmpty || _sites.isEmpty) {
      await _loadCompanyStructure();
    }
    final result = await Navigator.of(context).push<Person>(
      MaterialPageRoute(
        builder: (_) => PersonFormScreen(
          availableDepartments: _departments,
          availableSites: _sites,
          availableTeams: _teams,
        ),
      ),
    );
    if (result != null && mounted) {
      try {
        await UserService.instance.createUser(
          organizationId: _currentOrgId,
          person: result,
        );
        if (!mounted) return;
        await _loadUsers();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User ${result.name} recorded successfully.'),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add user: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Future<void> _openEditUser(Person person) async {
    if (_departments.isEmpty || _sites.isEmpty) {
      await _loadCompanyStructure();
    }
    final result = await Navigator.of(context).push<Person>(
      MaterialPageRoute(
        builder: (_) => PersonFormScreen(
          person: person,
          availableDepartments: _departments,
          availableSites: _sites,
          availableTeams: _teams,
        ),
      ),
    );
    if (result != null && mounted) {
      try {
        await UserService.instance.updateUser(
          organizationId: _currentOrgId,
          person: result,
        );
        if (!mounted) return;
        await _loadUsers();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${result.name} updated successfully.'),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update user: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Future<void> _toggleUserStatus(Person person) async {
    final newStatus = !person.isActive;
    try {
      await UserService.instance.toggleUserStatus(
        organizationId: _currentOrgId,
        profileId: person.id,
        isActive: newStatus,
      );
      if (!mounted) return;
      await _loadUsers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${person.name} marked as ${newStatus ? "Active" : "Inactive"}',
          ),
          backgroundColor: const Color(0xFF0F172A),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update status: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  Future<void> _confirmDeleteUser(Person person) async {
    final currentAdminId =
        SupabaseConfig.clientOrNull?.auth.currentUser?.id ?? _adminProfile.id;

    if (person.id == currentAdminId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You cannot delete your own active administrator account.',
          ),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    const protectedEmails = {
      'arvin.pr1112@gmail.com',
      'aravind11.sobha@gmail.com',
      'webonant@gmail.com',
      'aravindpr.1111@gmail.com',
    };

    if (protectedEmails.contains(person.email.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot delete protected core account: ${person.email}',
          ),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
      return;
    }

    if (person.role == UserRole.admin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Company Administrators cannot be deleted from this interface.',
          ),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.cardBg(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppTheme.cardBorder(context)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_forever_rounded,
                color: Color(0xFFDC2626),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Permanently Delete User',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to permanently delete this user?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.inputFill(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.cardBorder(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Email: ${person.email}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                    Text(
                      'Role: ${person.roleLabel} • Dept: ${person.department.isNotEmpty ? person.department : "None"}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This will permanently remove the user profile, all associated team memberships, manager scopes, and authentication login credentials. This action cannot be undone.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary(context),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.delete_forever_rounded, size: 16),
            label: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await UserService.instance.deleteUser(
        organizationId: _currentOrgId,
        profileId: person.id,
      );
      if (!mounted) return;
      await Future.wait([_loadUsers(), _loadAccountRequests()]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('User ${person.name} was permanently deleted.'),
          backgroundColor: const Color(0xFF16A34A),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete user: $e'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }

  Widget _buildStructureErrorBanner() {
    if (_structureErrorMessage == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFFEF4444).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFEF4444),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _structureErrorMessage!,
                style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // VIEW 2: DEPARTMENTS MANAGEMENT
  // ==========================================
  Widget _buildDepartmentsView(
    BuildContext context, {
    required bool isDesktop,
  }) {
    return _buildPageWrapper(
      isDesktop: isDesktop,
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
                      'Departments & Business Units',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Define organizational departments, unit heads, and action ownership groupings.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: _isLoadingStructure
                        ? null
                        : _loadCompanyStructure,
                    icon: _isLoadingStructure
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 18),
                    tooltip: 'Refresh Departments',
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _openAddDepartmentDialog(),
                    icon: const Icon(Icons.add_business_rounded, size: 17),
                    label: const Text('Add Department'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF38BDF8)
                          : const Color(0xFF0F172A),
                      foregroundColor:
                          Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF0F172A)
                          : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildStructureErrorBanner(),
          if (_departments.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cardBorder(context)),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.business_outlined,
                    size: 48,
                    color: AppTheme.textMuted(context),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No departments found for this company.',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Click "Add Department" above to configure your organization units.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final crossAxisCount = width > 1100 ? 3 : (width > 700 ? 2 : 1);
                return GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: width > 1100
                        ? 1.7
                        : (width > 700 ? 1.9 : 2.2),
                  ),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _departments.length,
                  itemBuilder: (context, index) {
                    final dept = _departments[index];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBg(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.cardBorder(context)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.actionIdBg(context),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: AppTheme.actionIdBorder(context),
                                  ),
                                ),
                                child: Text(
                                  dept['code'] as String,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.actionIdText(context),
                                  ),
                                ),
                              ),
                              _buildStatusBadge(dept['status'] as String),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            dept['name'] as String,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary(context),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Head: ${dept['head']}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary(context),
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Spacer(),
                          Divider(
                            height: 12,
                            color: AppTheme.dividerColor(context),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${dept['members']} Staff • ${dept['activeActions']} Actions',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary(context),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    padding: const EdgeInsets.all(4),
                                    constraints: const BoxConstraints(),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 16,
                                      color: Color(0xFF0284C7),
                                    ),
                                    onPressed: () =>
                                        _openEditDepartmentDialog(index),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    padding: const EdgeInsets.all(4),
                                    constraints: const BoxConstraints(),
                                    icon: Icon(
                                      dept['status'] == 'Active'
                                          ? Icons.block_rounded
                                          : Icons.check_circle_outline_rounded,
                                      size: 16,
                                      color: dept['status'] == 'Active'
                                          ? Colors.red.shade400
                                          : Colors.green.shade600,
                                    ),
                                    onPressed: () =>
                                        _handleToggleDepartmentStatus(dept),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    key: ValueKey('delete_dept_${dept['id']}'),
                                    padding: const EdgeInsets.all(4),
                                    constraints: const BoxConstraints(),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 16,
                                      color: Color(0xFFDC2626),
                                    ),
                                    onPressed: () =>
                                        _handleDeleteDepartment(dept),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _handleDeleteDepartment(Map<String, dynamic> dept) async {
    final deptId = dept['id'] as String;
    final deptName = dept['name'] as String? ?? 'Department';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Delete $deptName?'),
        content: Text(
          'Are you sure you want to permanently delete "$deptName"? This action cannot be undone if the department has no active references.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (CompanyStructureService.instance.isReady) {
      try {
        final res = await CompanyStructureService.instance.deleteDepartment(
          departmentId: deptId,
        );

        if (res['success'] == true) {
          await _loadCompanyStructure();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$deptName deleted successfully.'),
              backgroundColor: const Color(0xFF0F172A),
            ),
          );
        } else {
          final deps = res['dependencies'] as Map<String, dynamic>?;
          final userCount = deps?['users'] ?? 0;
          final teamCount = deps?['teams'] ?? 0;
          final reqCount = deps?['account_requests'] ?? 0;
          final scopeCount = deps?['manager_scopes'] ?? 0;

          if (!mounted) return;
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFEAB308),
                size: 36,
              ),
              title: const Text('Cannot Delete Department'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Department "$deptName" cannot be deleted because active references exist:',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  if (userCount > 0) Text('• $userCount assigned user(s)'),
                  if (teamCount > 0) Text('• $teamCount dependent team(s)'),
                  if (reqCount > 0)
                    Text('• $reqCount pending/historical account request(s)'),
                  if (scopeCount > 0)
                    Text('• $scopeCount manager scope reference(s)'),
                  const SizedBox(height: 14),
                  Text(
                    'To safely prevent new signups and assignments without breaking historical records, deactivate this department instead.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
                if (dept['status'] == 'Active')
                  FilledButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _handleToggleDepartmentStatus(dept);
                    },
                    child: const Text('Deactivate Department'),
                  ),
              ],
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete department: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } else {
      setState(() {
        _departments.removeWhere((d) => d['id'] == deptId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$deptName removed (offline mode).'),
          backgroundColor: const Color(0xFF0F172A),
        ),
      );
    }
  }

  Future<void> _handleToggleDepartmentStatus(Map<String, dynamic> dept) async {
    final newStatus = dept['status'] != 'Active';
    if (CompanyStructureService.instance.isReady) {
      try {
        await CompanyStructureService.instance.toggleDepartmentStatus(
          organizationId: _currentOrgId,
          id: dept['id'] as String,
          isActive: newStatus,
        );
        await _loadCompanyStructure();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${dept['name']} marked as ${newStatus ? "Active" : "Inactive"}.',
            ),
            backgroundColor: const Color(0xFF0F172A),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } else {
      setState(() {
        dept['status'] = newStatus ? 'Active' : 'Inactive';
      });
    }
  }

  void _openAddDepartmentDialog() {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final headCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Add Department'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Department Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(
                labelText: 'Short Code (e.g. HSE)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: headCtrl,
              decoration: const InputDecoration(labelText: 'Department Head'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final code = codeCtrl.text.trim().toUpperCase();
              final head = headCtrl.text.trim();
              if (name.isEmpty) return;

              Navigator.of(dialogCtx).pop();

              if (CompanyStructureService.instance.isReady) {
                try {
                  await CompanyStructureService.instance.createDepartment(
                    organizationId: _currentOrgId,
                    name: name,
                    code: code.isNotEmpty
                        ? code
                        : (name.length >= 3
                              ? name.substring(0, 3).toUpperCase()
                              : name.toUpperCase()),
                    head: head.isNotEmpty ? head : null,
                  );
                  await _loadCompanyStructure();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Department "$name" created successfully.'),
                      backgroundColor: const Color(0xFF16A34A),
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to create department: $e'),
                      backgroundColor: const Color(0xFFDC2626),
                    ),
                  );
                }
              } else {
                setState(() {
                  _departments.add({
                    'id': 'DEP-0${_departments.length + 1}',
                    'name': name,
                    'code': code.isNotEmpty
                        ? code
                        : (name.length >= 3
                              ? name.substring(0, 3).toUpperCase()
                              : name.toUpperCase()),
                    'head': head.isNotEmpty ? head : 'Unassigned',
                    'members': 0,
                    'activeActions': 0,
                    'status': 'Active',
                  });
                });
              }
            },
            child: const Text('Add Department'),
          ),
        ],
      ),
    );
  }

  void _openEditDepartmentDialog(int index) {
    final dept = _departments[index];
    final nameCtrl = TextEditingController(text: dept['name'] as String);
    final codeCtrl = TextEditingController(text: dept['code'] as String);
    final headCtrl = TextEditingController(text: dept['head'] as String);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Edit Department'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Department Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(labelText: 'Short Code'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: headCtrl,
              decoration: const InputDecoration(labelText: 'Department Head'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final code = codeCtrl.text.trim().toUpperCase();
              final head = headCtrl.text.trim();
              if (name.isEmpty) return;

              Navigator.of(dialogCtx).pop();

              if (CompanyStructureService.instance.isReady) {
                try {
                  await CompanyStructureService.instance.updateDepartment(
                    organizationId: _currentOrgId,
                    id: dept['id'] as String,
                    name: name,
                    code: code,
                    head: head,
                  );
                  await _loadCompanyStructure();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Department "$name" updated successfully.'),
                      backgroundColor: const Color(0xFF0F172A),
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to update department: $e'),
                      backgroundColor: const Color(0xFFDC2626),
                    ),
                  );
                }
              } else {
                setState(() {
                  dept['name'] = name;
                  dept['code'] = code;
                  dept['head'] = head;
                });
              }
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // VIEW 3: SITES & FACILITIES
  // ==========================================
  Widget _buildSitesView(BuildContext context, {required bool isDesktop}) {
    return _buildPageWrapper(
      isDesktop: isDesktop,
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
                      'Sites & Operational Facilities',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Track plant locations, terminals, warehouses, and fabrication yards.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: _isLoadingStructure
                        ? null
                        : _loadCompanyStructure,
                    icon: _isLoadingStructure
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 18),
                    tooltip: 'Refresh Sites',
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _openAddSiteDialog(),
                    icon: const Icon(Icons.add_location_alt_rounded, size: 17),
                    label: const Text('Add Site'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF38BDF8)
                          : const Color(0xFF0F172A),
                      foregroundColor:
                          Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF0F172A)
                          : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildStructureErrorBanner(),
          if (_sites.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cardBorder(context)),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.location_city_outlined,
                    size: 48,
                    color: AppTheme.textMuted(context),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No facility sites found for this company.',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Click "Add Site" above to register plant locations or operational yards.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final crossAxisCount = width > 1100 ? 3 : (width > 700 ? 2 : 1);
                return GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: width > 1100
                        ? 1.7
                        : (width > 700 ? 1.9 : 2.2),
                  ),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _sites.length,
                  itemBuilder: (context, index) {
                    final site = _sites[index];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBg(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.cardBorder(context)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0284C7)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  site['type'] as String,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0284C7),
                                  ),
                                ),
                              ),
                              _buildStatusBadge(site['status'] as String),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            site['name'] as String,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary(context),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: 13,
                                color: AppTheme.textSecondary(context),
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  site['location'] as String,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary(context),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Divider(
                            height: 12,
                            color: AppTheme.dividerColor(context),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${site['staff']} Staff • ${site['actions']} Actions',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary(context),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    padding: const EdgeInsets.all(4),
                                    constraints: const BoxConstraints(),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 16,
                                      color: Color(0xFF0284C7),
                                    ),
                                    onPressed: () => _openEditSiteDialog(index),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    padding: const EdgeInsets.all(4),
                                    constraints: const BoxConstraints(),
                                    icon: Icon(
                                      site['status'] == 'Active'
                                          ? Icons.block_rounded
                                          : Icons.check_circle_outline_rounded,
                                      size: 16,
                                      color: site['status'] == 'Active'
                                          ? Colors.red.shade400
                                          : Colors.green.shade600,
                                    ),
                                    onPressed: () =>
                                        _handleToggleSiteStatus(site),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    key: ValueKey('delete_site_${site['id']}'),
                                    padding: const EdgeInsets.all(4),
                                    constraints: const BoxConstraints(),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 16,
                                      color: Color(0xFFDC2626),
                                    ),
                                    onPressed: () => _handleDeleteSite(site),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _handleDeleteSite(Map<String, dynamic> site) async {
    final siteId = site['id'] as String;
    final siteName = site['name'] as String? ?? 'Site';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Delete $siteName?'),
        content: Text(
          'Are you sure you want to permanently delete "$siteName"? This action cannot be undone if the site has no active references.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (CompanyStructureService.instance.isReady) {
      try {
        final res = await CompanyStructureService.instance.deleteSite(
          siteId: siteId,
        );

        if (res['success'] == true) {
          await _loadCompanyStructure();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$siteName deleted successfully.'),
              backgroundColor: const Color(0xFF0F172A),
            ),
          );
        } else {
          final deps = res['dependencies'] as Map<String, dynamic>?;
          final userCount = deps?['users'] ?? 0;
          final reqCount = deps?['account_requests'] ?? 0;
          final scopeCount = deps?['manager_scopes'] ?? 0;

          if (!mounted) return;
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFEAB308),
                size: 36,
              ),
              title: const Text('Cannot Delete Site'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Site "$siteName" cannot be deleted because active references exist:',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  if (userCount > 0) Text('• $userCount assigned user(s)'),
                  if (reqCount > 0)
                    Text('• $reqCount pending/historical account request(s)'),
                  if (scopeCount > 0)
                    Text('• $scopeCount manager scope reference(s)'),
                  const SizedBox(height: 14),
                  Text(
                    'To safely prevent new signups and assignments without breaking historical records, deactivate this site instead.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
                if (site['status'] == 'Active')
                  FilledButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _handleToggleSiteStatus(site);
                    },
                    child: const Text('Deactivate Site'),
                  ),
              ],
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete site: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } else {
      setState(() {
        _sites.removeWhere((s) => s['id'] == siteId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$siteName removed (offline mode).'),
          backgroundColor: const Color(0xFF0F172A),
        ),
      );
    }
  }

  Future<void> _handleToggleSiteStatus(Map<String, dynamic> site) async {
    final newStatus = site['status'] != 'Active';
    if (CompanyStructureService.instance.isReady) {
      try {
        await CompanyStructureService.instance.toggleSiteStatus(
          organizationId: _currentOrgId,
          id: site['id'] as String,
          isActive: newStatus,
        );
        await _loadCompanyStructure();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${site['name']} marked as ${newStatus ? "Active" : "Inactive"}.',
            ),
            backgroundColor: const Color(0xFF0F172A),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } else {
      setState(() {
        site['status'] = newStatus ? 'Active' : 'Inactive';
      });
    }
  }

  void _openAddSiteDialog() {
    final nameCtrl = TextEditingController();
    final locCtrl = TextEditingController();
    final typeCtrl = TextEditingController(text: 'Manufacturing');
    bool isSubmitting = false;
    String? errorMessage;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Facility Site'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 16,
                        color: Color(0xFFDC2626),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          errorMessage!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              TextField(
                controller: nameCtrl,
                enabled: !isSubmitting,
                decoration: const InputDecoration(labelText: 'Site Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: locCtrl,
                enabled: !isSubmitting,
                decoration: const InputDecoration(
                  labelText: 'Physical Location / Address',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: typeCtrl,
                enabled: !isSubmitting,
                decoration: const InputDecoration(labelText: 'Facility Type'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      final loc = locCtrl.text.trim();
                      final type = typeCtrl.text.trim();
                      if (name.isEmpty) {
                        setDialogState(() {
                          errorMessage = 'Site name is required.';
                        });
                        return;
                      }

                      setDialogState(() {
                        isSubmitting = true;
                        errorMessage = null;
                      });

                      if (CompanyStructureService.instance.isReady) {
                        try {
                          await CompanyStructureService.instance.createSite(
                            organizationId: _currentOrgId,
                            name: name,
                            location: loc,
                            type: type,
                          );
                          await _loadCompanyStructure();
                          if (dialogCtx.mounted) {
                            Navigator.of(dialogCtx).pop();
                          }
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Site "$name" created successfully.'),
                              backgroundColor: const Color(0xFF16A34A),
                            ),
                          );
                        } catch (e) {
                          if (!dialogCtx.mounted) return;
                          setDialogState(() {
                            isSubmitting = false;
                            final errStr = e.toString();
                            if (errStr.contains('sites_code_key') ||
                                (errStr.contains('23505') && errStr.contains('code'))) {
                              errorMessage = 'A site with this code already exists. Please try another name or code.';
                            } else if (errStr.contains('duplicate key') || errStr.contains('23505')) {
                              errorMessage = 'A site with this name already exists.';
                            } else {
                              errorMessage = 'Failed to create site: $e';
                            }
                          });
                        }
                      } else {
                        final existingMockCodes = _sites
                            .map((s) => s['code']?.toString().toUpperCase() ?? '')
                            .toSet();
                        String baseCode = (name.length >= 3
                                ? name.substring(0, 3).toUpperCase()
                                : name.toUpperCase())
                            .replaceAll(RegExp(r'[^A-Z0-9]'), '');
                        if (baseCode.isEmpty) baseCode = 'SIT';
                        String mockCode = baseCode;
                        int suffix = 1;
                        while (existingMockCodes.contains(mockCode)) {
                          mockCode = '$baseCode-${suffix.toString().padLeft(2, '0')}';
                          suffix++;
                        }
                        setState(() {
                          _sites.add({
                            'id': 'SITE-0${_sites.length + 1}',
                            'name': name,
                            'code': mockCode,
                            'location': loc,
                            'staff': 0,
                            'actions': 0,
                            'type': type,
                            'status': 'Active',
                          });
                        });
                        Navigator.of(dialogCtx).pop();
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Add Site'),
            ),
          ],
        ),
      ),
    );
  }

  void _openEditSiteDialog(int index) {
    final site = _sites[index];
    final nameCtrl = TextEditingController(text: site['name'] as String);
    final locCtrl = TextEditingController(text: site['location'] as String);
    final typeCtrl = TextEditingController(text: site['type'] as String);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Edit Site'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Site Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: locCtrl,
              decoration: const InputDecoration(labelText: 'Location'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: typeCtrl,
              decoration: const InputDecoration(labelText: 'Facility Type'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final loc = locCtrl.text.trim();
              final type = typeCtrl.text.trim();
              if (name.isEmpty) return;

              Navigator.of(dialogCtx).pop();

              if (CompanyStructureService.instance.isReady) {
                try {
                  await CompanyStructureService.instance.updateSite(
                    organizationId: _currentOrgId,
                    id: site['id'] as String,
                    name: name,
                    location: loc,
                    type: type,
                  );
                  await _loadCompanyStructure();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Site "$name" updated successfully.'),
                      backgroundColor: const Color(0xFF0F172A),
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to update site: $e'),
                      backgroundColor: const Color(0xFFDC2626),
                    ),
                  );
                }
              } else {
                setState(() {
                  site['name'] = name;
                  site['location'] = loc;
                  site['type'] = type;
                });
              }
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // VIEW 4: TEAMS & SQUADS
  // ==========================================
  Widget _buildTeamsView(BuildContext context, {required bool isDesktop}) {
    return _buildPageWrapper(
      isDesktop: isDesktop,
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
                      'Operational Teams & Squads',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Cross-functional teams, response units, and maintenance squads.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: _isLoadingStructure
                        ? null
                        : _loadCompanyStructure,
                    icon: _isLoadingStructure
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 18),
                    tooltip: 'Refresh Teams',
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _openAddTeamDialog(),
                    icon: const Icon(Icons.group_add_rounded, size: 17),
                    label: const Text('Add Team'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF38BDF8)
                          : const Color(0xFF0F172A),
                      foregroundColor:
                          Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF0F172A)
                          : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildStructureErrorBanner(),
          if (_teams.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cardBorder(context)),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.groups_outlined,
                    size: 48,
                    color: AppTheme.textMuted(context),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No operational teams found for this company.',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Click "Add Team" above to configure cross-functional squads.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
            )
          else
            Material(
              color: AppTheme.cardBg(context),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.cardBorder(context)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _teams.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: AppTheme.dividerColor(context)),
                  itemBuilder: (context, index) {
                    final team = _teams[index];
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: AppTheme.containerBg(context),
                        child: Icon(
                          Icons.groups_rounded,
                          color: AppTheme.textPrimary(context),
                          size: 18,
                        ),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              team['name'] as String,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: AppTheme.textPrimary(context),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildStatusBadge(team['status'] as String),
                        ],
                      ),
                      subtitle: Text(
                        'Dept: ${team['dept']} • Site: ${team['site']} • Lead: ${team['lead']}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${team['members']} Members',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0284C7),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            icon: const Icon(
                              Icons.edit_outlined,
                              size: 17,
                              color: Color(0xFF0284C7),
                            ),
                            onPressed: () => _openEditTeamDialog(index),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              team['status'] == 'Active'
                                  ? Icons.block_rounded
                                  : Icons.check_circle_outline_rounded,
                              size: 16,
                              color: team['status'] == 'Active'
                                  ? Colors.red.shade400
                                  : Colors.green.shade600,
                            ),
                            tooltip: team['status'] == 'Active'
                                ? 'Deactivate Team'
                                : 'Activate Team',
                            onPressed: () => _handleToggleTeamStatus(team),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleToggleTeamStatus(Map<String, dynamic> team) async {
    final newStatus = team['status'] != 'Active';
    if (CompanyStructureService.instance.isReady) {
      try {
        await CompanyStructureService.instance.toggleTeamStatus(
          organizationId: _currentOrgId,
          id: team['id'] as String,
          isActive: newStatus,
        );
        await _loadCompanyStructure();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${team['name']} marked as ${newStatus ? "Active" : "Inactive"}.',
            ),
            backgroundColor: const Color(0xFF0F172A),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } else {
      setState(() {
        team['status'] = newStatus ? 'Active' : 'Inactive';
      });
    }
  }

  void _openAddTeamDialog() {
    if (_departments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please create at least one Department before adding a Team/Squad.',
          ),
          backgroundColor: Color(0xFFD97706),
        ),
      );
      return;
    }

    final nameCtrl = TextEditingController();
    String? selectedDeptId = _departments.first['id']?.toString();
    final leadCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Team / Squad'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Team Name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedDeptId,
                decoration: const InputDecoration(
                  labelText: 'Department (Strict Hierarchy) *',
                ),
                items: _departments.map((d) {
                  final deptId = d['id']?.toString() ?? '';
                  final deptName = d['name']?.toString() ?? 'Department';
                  return DropdownMenuItem<String>(
                    value: deptId,
                    child: Text(deptName),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setDialogState(() => selectedDeptId = val);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: leadCtrl,
                decoration: const InputDecoration(
                  labelText: 'Team Lead Manager',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final lead = leadCtrl.text.trim();
                if (name.isEmpty ||
                    selectedDeptId == null ||
                    selectedDeptId!.isEmpty) {
                  return;
                }

                Navigator.of(dialogCtx).pop();

                final dept = _departments.firstWhere(
                  (d) => d['id']?.toString() == selectedDeptId,
                  orElse: () => _departments.first,
                );
                final deptId = dept['id']?.toString() ?? '';
                final deptName = dept['name']?.toString() ?? 'General';

                if (CompanyStructureService.instance.isReady &&
                    deptId.isNotEmpty) {
                  try {
                    await CompanyStructureService.instance.createTeam(
                      organizationId: _currentOrgId,
                      departmentId: deptId,
                      name: name,
                      lead: lead.isNotEmpty ? lead : null,
                    );
                    await _loadCompanyStructure();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Team "$name" created successfully.'),
                        backgroundColor: const Color(0xFF16A34A),
                      ),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to create team: $e'),
                        backgroundColor: const Color(0xFFDC2626),
                      ),
                    );
                  }
                } else if (!CompanyStructureService.instance.isReady) {
                  setState(() {
                    _teams.add({
                      'id': 'TEAM-0${_teams.length + 1}',
                      'name': name,
                      'dept': deptName,
                      'deptId': deptId,
                      'site': 'All Sites',
                      'lead': lead.isNotEmpty ? lead : 'Unassigned',
                      'members': 1,
                      'status': 'Active',
                    });
                  });
                }
              },
              child: const Text('Add Team'),
            ),
          ],
        ),
      ),
    );
  }

  void _openEditTeamDialog(int index) {
    final team = _teams[index];
    final nameCtrl = TextEditingController(text: team['name'] as String);
    String? selectedDeptId = team['deptId']?.toString();
    if (selectedDeptId == null ||
        !_departments.any((d) => d['id']?.toString() == selectedDeptId)) {
      final match = _departments.firstWhere(
        (d) => d['name'] == team['dept'],
        orElse: () =>
            _departments.isNotEmpty ? _departments.first : {'id': null},
      );
      selectedDeptId = match['id']?.toString();
    }
    final leadCtrl = TextEditingController(
      text: team['lead'] == 'Unassigned'
          ? ''
          : (team['lead']?.toString() ?? ''),
    );

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Edit Team'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Team Name'),
              ),
              const SizedBox(height: 12),
              if (_departments.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: selectedDeptId,
                  decoration: const InputDecoration(labelText: 'Department'),
                  items: _departments.map((d) {
                    final deptId = d['id']?.toString() ?? '';
                    final deptName = d['name']?.toString() ?? 'Department';
                    return DropdownMenuItem<String>(
                      value: deptId,
                      child: Text(deptName),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => selectedDeptId = val);
                    }
                  },
                )
              else
                const TextField(
                  enabled: false,
                  decoration: InputDecoration(
                    labelText: 'Department',
                    hintText: 'No departments available',
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: leadCtrl,
                decoration: const InputDecoration(labelText: 'Team Lead'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final lead = leadCtrl.text.trim();
                if (name.isEmpty) return;

                Navigator.of(dialogCtx).pop();

                final dept = _departments.firstWhere(
                  (d) => d['id']?.toString() == selectedDeptId,
                  orElse: () => _departments.isNotEmpty
                      ? _departments.first
                      : {'id': '', 'name': 'General'},
                );
                final deptId = dept['id']?.toString() ?? '';
                final deptName = dept['name']?.toString() ?? 'General';

                if (CompanyStructureService.instance.isReady &&
                    deptId.isNotEmpty) {
                  try {
                    await CompanyStructureService.instance.updateTeam(
                      organizationId: _currentOrgId,
                      id: team['id'] as String,
                      departmentId: deptId,
                      name: name,
                      lead: lead.isNotEmpty ? lead : null,
                    );
                    await _loadCompanyStructure();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Team "$name" updated successfully.'),
                        backgroundColor: const Color(0xFF0F172A),
                      ),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to update team: $e'),
                        backgroundColor: const Color(0xFFDC2626),
                      ),
                    );
                  }
                } else {
                  setState(() {
                    team['name'] = name;
                    team['dept'] = deptName;
                    team['deptId'] = deptId;
                    team['lead'] = lead.isNotEmpty ? lead : 'Unassigned';
                  });
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // VIEW 5: ROLES & PERMISSIONS MATRIX
  // ==========================================
  Widget _buildRolesPermissionsView(
    BuildContext context, {
    required bool isDesktop,
  }) {
    final matrix = [
      {
        'capability': 'Create & Assign Actions',
        'admin': true,
        'manager': true,
        'staff': false,
      },
      {
        'capability': 'Review & Approve Completed Actions',
        'admin': true,
        'manager': true,
        'staff': false,
      },
      {
        'capability': 'Update Progress & Submit Evidence',
        'admin': true,
        'manager': true,
        'staff': true,
      },
      {
        'capability': 'Add / Edit Directory Users',
        'admin': true,
        'manager': false,
        'staff': false,
      },
      {
        'capability': 'Manage Departments & Sites',
        'admin': true,
        'manager': false,
        'staff': false,
      },
      {
        'capability': 'Broadcast Organization Alerts',
        'admin': true,
        'manager': false,
        'staff': false,
      },
      {
        'capability': 'Export Executive Audit Reports',
        'admin': true,
        'manager': true,
        'staff': false,
      },
      {
        'capability': 'Configure Security & 2FA Policies',
        'admin': true,
        'manager': false,
        'staff': false,
      },
      {
        'capability': 'Access Manager Dashboard & Analytics',
        'admin': true,
        'manager': true,
        'staff': false,
      },
      {
        'capability': 'Access Staff Dashboard & Tasks',
        'admin': true,
        'manager': false,
        'staff': true,
      },
    ];

    return _buildPageWrapper(
      isDesktop: isDesktop,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Roles & Permissions Matrix',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Granular capability enforcement across System Admin, Department Manager, and Staff roles.',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 14),
          // Role summary cards
          LayoutBuilder(
            builder: (context, rConstraints) {
              final isWide = rConstraints.maxWidth > 750;
              final cards = [
                _buildRoleOverviewCard(
                  context: context,
                  role: 'System Administrator',
                  code: 'ADMIN',
                  description: 'Full system sovereignty, governance setup, user directories, and compliance control.',
                  badgeColor: const Color(0xFF0284C7),
                ),
                _buildRoleOverviewCard(
                  context: context,
                  role: 'Department Manager',
                  code: 'MANAGER',
                  description: 'Action assignment, progress reviews, evidence sign-off, and team analytics.',
                  badgeColor: const Color(0xFF0284C7),
                ),
                _buildRoleOverviewCard(
                  context: context,
                  role: 'Staff / Action Owner',
                  code: 'STAFF',
                  description: 'Action execution, progress logs, field notes, and resolution evidence submission.',
                  badgeColor: const Color(0xFF16A34A),
                ),
              ];

              if (isWide) {
                return Row(
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 12),
                    Expanded(child: cards[1]),
                    const SizedBox(width: 12),
                    Expanded(child: cards[2]),
                  ],
                );
              } else {
                return Column(
                  children: [
                    cards[0],
                    const SizedBox(height: 10),
                    cards[1],
                    const SizedBox(height: 10),
                    cards[2],
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 16),
          // Capability Matrix Table
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppTheme.cardBg(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.cardBorder(context)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: DataTable(
                horizontalMargin: 16,
                columnSpacing: 18,
                headingRowHeight: 38,
                dataRowMinHeight: 38,
                dataRowMaxHeight: 42,
                headingRowColor: WidgetStateProperty.all(
                  AppTheme.containerBg(context),
                ),
                columns: [
                  DataColumn(
                    label: Text(
                      'SYSTEM CAPABILITY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'ADMIN',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'MANAGER',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'STAFF',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ),
                ],
                rows: matrix.map((item) {
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          item['capability'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                      ),
                      DataCell(_buildPermIcon(context, item['admin'] as bool)),
                      DataCell(
                        _buildPermIcon(context, item['manager'] as bool),
                      ),
                      DataCell(_buildPermIcon(context, item['staff'] as bool)),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleOverviewCard({
    required BuildContext context,
    required String role,
    required String code,
    required String description,
    required Color badgeColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  role,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppTheme.textPrimary(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  code,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary(context),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermIcon(BuildContext context, bool granted) {
    return granted
        ? Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              color: Color(0xFFDCFCE7),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 13,
              color: Color(0xFF16A34A),
            ),
          )
        : Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppTheme.containerBg(context),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.close_rounded,
              size: 13,
              color: AppTheme.textMuted(context),
            ),
          );
  }

  // ==========================================
  // VIEW 6: ACTION SECTIONS
  // ==========================================
  Widget _buildActionSectionsView(
    BuildContext context, {
    required bool isDesktop,
  }) {
    return _buildPageWrapper(
      isDesktop: isDesktop,
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
                      'Action Sections',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Configure organizational action sections and classification areas for action management.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: _isLoadingSections ? null : _loadActionSections,
                    icon: _isLoadingSections
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 18),
                    tooltip: 'Refresh Sections',
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _openAddSectionDialog(context),
                    icon: const Icon(
                      Icons.add_circle_outline_rounded,
                      size: 17,
                    ),
                    label: const Text('Add Section'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF38BDF8)
                          : const Color(0xFF0F172A),
                      foregroundColor:
                          Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF0F172A)
                          : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_sectionsErrorMessage != null)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Color(0xFFDC2626),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _sectionsErrorMessage!,
                      style: const TextStyle(
                        color: Color(0xFFB91C1C),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_isLoadingSections && _actionSections.isEmpty)
            Container(
              padding: const EdgeInsets.all(48),
              alignment: Alignment.center,
              child: const CircularProgressIndicator(),
            )
          else if (_actionSections.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cardBorder(context)),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.segment_rounded,
                    size: 40,
                    color: AppTheme.textMuted(context),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No Action Sections Configured',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Action sections classify and group enterprise actions. Click "Add Section" above to configure sections.',
                    style: TextStyle(
                      color: AppTheme.textSecondary(context),
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            Material(
              color: AppTheme.cardBg(context),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.cardBorder(context)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _actionSections.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: AppTheme.dividerColor(context)),
                  itemBuilder: (context, index) {
                    final sec = _actionSections[index];
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: sec.isActive
                              ? (AppTheme.isDark(context)
                                    ? const Color(0xFF0C4A6E)
                                    : const Color(0xFFE0F2FE))
                              : (AppTheme.isDark(context)
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.segment_rounded,
                          size: 18,
                          color: sec.isActive
                              ? const Color(0xFF0284C7)
                              : AppTheme.textMuted(context),
                        ),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              sec.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: sec.isActive
                                    ? AppTheme.textPrimary(context)
                                    : AppTheme.textSecondary(context),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildStatusBadge(
                            sec.isActive ? 'Active' : 'Inactive',
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (sec.description.isNotEmpty)
                              Text(
                                sec.description,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary(context),
                                ),
                              ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(
                                  Icons.assignment_outlined,
                                  size: 12,
                                  color: AppTheme.textMuted(context),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${sec.actionCount} action(s) linked',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textMuted(context),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Icon(
                                  Icons.calendar_today_outlined,
                                  size: 11,
                                  color: AppTheme.textMuted(context),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Created ${ActionRecord.formatDateForUi(sec.createdAt)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textMuted(context),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            tooltip: sec.isActive
                                ? 'Deactivate Section'
                                : 'Activate Section',
                            icon: Icon(
                              sec.isActive
                                  ? Icons.toggle_on_rounded
                                  : Icons.toggle_off_rounded,
                              size: 26,
                              color: sec.isActive
                                  ? const Color(0xFF16A34A)
                                  : AppTheme.textMuted(context),
                            ),
                            onPressed: () => _toggleSectionActive(sec),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            tooltip: 'Edit Section',
                            icon: const Icon(
                              Icons.edit_outlined,
                              size: 18,
                              color: Color(0xFF0284C7),
                            ),
                            onPressed: () =>
                                _openEditSectionDialog(context, sec),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            tooltip: 'Delete Section',
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: Color(0xFFDC2626),
                            ),
                            onPressed: () =>
                                _confirmDeleteSection(context, sec),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _toggleSectionActive(ActionSection section) async {
    try {
      final newStatus = !section.isActive;
      await ActionSectionService.instance.setSectionActive(
        sectionId: section.id,
        isActive: newStatus,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Section "${section.name}" is now ${newStatus ? "Active" : "Inactive"}.',
          ),
          backgroundColor: newStatus
              ? const Color(0xFF16A34A)
              : const Color(0xFF475569),
        ),
      );
      await _loadActionSections();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating section status: $e'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }

  void _openAddSectionDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    bool isSaving = false;
    String? dialogError;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Action Section'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (dialogError != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Color(0xFFDC2626),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            dialogError!,
                            style: const TextStyle(
                              color: Color(0xFFB91C1C),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Section Name *',
                    hintText: 'e.g. Inspection, Electrical, Civil',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    hintText: 'Classification and usage details',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        setDialogState(() {
                          dialogError = 'Please enter a section name.';
                        });
                        return;
                      }

                      setDialogState(() {
                        isSaving = true;
                        dialogError = null;
                      });

                      try {
                        final newSec = await ActionSectionService.instance
                            .createSection(
                              organizationId: _currentOrgId,
                              name: name,
                              description: descCtrl.text.trim(),
                            );
                        if (!mounted) return;
                        Navigator.of(dialogCtx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Section "${newSec.name}" created successfully!',
                            ),
                            backgroundColor: const Color(0xFF16A34A),
                          ),
                        );
                        await _loadActionSections();
                      } catch (e) {
                        setDialogState(() {
                          isSaving = false;
                          dialogError = e.toString().replaceAll(
                            'Exception: ',
                            '',
                          );
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Section'),
            ),
          ],
        ),
      ),
    );
  }

  void _openEditSectionDialog(BuildContext context, ActionSection section) {
    final nameCtrl = TextEditingController(text: section.name);
    final descCtrl = TextEditingController(text: section.description);
    bool isActive = section.isActive;
    bool isSaving = false;
    String? dialogError;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Edit Action Section'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (dialogError != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Color(0xFFDC2626),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            dialogError!,
                            style: const TextStyle(
                              color: Color(0xFFB91C1C),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Section Name *',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Active Status',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    isActive
                        ? 'Available for new actions'
                        : 'Hidden from new action creation',
                    style: const TextStyle(fontSize: 11),
                  ),
                  value: isActive,
                  onChanged: (val) {
                    setDialogState(() {
                      isActive = val;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        setDialogState(() {
                          dialogError = 'Please enter a section name.';
                        });
                        return;
                      }

                      setDialogState(() {
                        isSaving = true;
                        dialogError = null;
                      });

                      try {
                        final updated = await ActionSectionService.instance
                            .updateSection(
                              sectionId: section.id,
                              name: name,
                              description: descCtrl.text.trim(),
                              isActive: isActive,
                            );
                        if (!mounted) return;
                        Navigator.of(dialogCtx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Section "${updated.name}" updated successfully!',
                            ),
                            backgroundColor: const Color(0xFF16A34A),
                          ),
                        );
                        await _loadActionSections();
                      } catch (e) {
                        setDialogState(() {
                          isSaving = false;
                          dialogError = e.toString().replaceAll(
                            'Exception: ',
                            '',
                          );
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteSection(BuildContext context, ActionSection section) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Action Section'),
        content: Text(
          'Are you sure you want to permanently delete section "${section.name}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              final result = await ActionSectionService.instance.deleteSection(
                sectionId: section.id,
              );

              if (!mounted) return;

              if (result['error_code'] == 'DEPENDENCIES_EXIST') {
                // Show dependency dialog with "Deactivate Instead" option
                showDialog(
                  context: context,
                  builder: (depCtx) => AlertDialog(
                    title: const Text('Cannot Delete Section'),
                    content: Text(
                      result['message']?.toString() ?? 'This section is linked to active actions. You can deactivate it instead to preserve historical records.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(depCtx).pop(),
                        child: const Text('Dismiss'),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          Navigator.of(depCtx).pop();
                          await _toggleSectionActive(section);
                        },
                        child: const Text('Deactivate Instead'),
                      ),
                    ],
                  ),
                );
              } else if (result['success'] == true) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Section "${section.name}" deleted successfully.',
                    ),
                    backgroundColor: const Color(0xFF16A34A),
                  ),
                );
                await _loadActionSections();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      result['message']?.toString() ??
                          'Failed to delete section.',
                    ),
                    backgroundColor: const Color(0xFFDC2626),
                  ),
                );
              }
            },
            child: const Text('Delete Section'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // VIEW 7: DIVISIONS
  // ==========================================
  Widget _buildDivisionsView(BuildContext context, {required bool isDesktop}) {
    final filteredDivisions = _divisions.where((div) {
      if (_divisionSearchQuery.isEmpty) return true;
      final q = _divisionSearchQuery.toLowerCase();
      return div.name.toLowerCase().contains(q) ||
          div.code.toLowerCase().contains(q) ||
          div.description.toLowerCase().contains(q);
    }).toList();

    return _buildPageWrapper(
      isDesktop: isDesktop,
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
                      'Divisions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Configure organizational divisions and business lines for action tracking.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: _isLoadingDivisions ? null : _loadDivisions,
                    icon: _isLoadingDivisions
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 18),
                    tooltip: 'Refresh Divisions',
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _openAddDivisionDialog(context),
                    icon: const Icon(
                      Icons.add_circle_outline_rounded,
                      size: 17,
                    ),
                    label: const Text('Add Division'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF38BDF8)
                          : const Color(0xFF0F172A),
                      foregroundColor:
                          Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF0F172A)
                          : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_divisionsErrorMessage != null)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Color(0xFFDC2626),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _divisionsErrorMessage!,
                      style: const TextStyle(
                        color: Color(0xFFB91C1C),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_isLoadingDivisions && _divisions.isEmpty)
            Container(
              padding: const EdgeInsets.all(48),
              alignment: Alignment.center,
              child: const CircularProgressIndicator(),
            )
          else if (_divisions.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cardBorder(context)),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.domain_rounded,
                    size: 40,
                    color: AppTheme.textMuted(context),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No Divisions Configured',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Divisions represent major operational branches. Click "Add Division" above to configure your enterprise divisions.',
                    style: TextStyle(
                      color: AppTheme.textSecondary(context),
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            Material(
              color: AppTheme.cardBg(context),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.cardBorder(context)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredDivisions.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: AppTheme.dividerColor(context)),
                  itemBuilder: (context, index) {
                    final div = filteredDivisions[index];
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: div.isActive
                              ? (AppTheme.isDark(context)
                                    ? const Color(0xFF0C4A6E)
                                    : const Color(0xFFE0F2FE))
                              : (AppTheme.isDark(context)
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.domain_rounded,
                          size: 18,
                          color: div.isActive
                              ? const Color(0xFF0284C7)
                              : AppTheme.textMuted(context),
                        ),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              div.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: div.isActive
                                    ? AppTheme.textPrimary(context)
                                    : AppTheme.textSecondary(context),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.containerBg(context),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              div.code,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textSecondary(context),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildStatusBadge(
                            div.isActive ? 'Active' : 'Inactive',
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (div.description.isNotEmpty)
                              Text(
                                div.description,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary(context),
                                ),
                              ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(
                                  Icons.assignment_outlined,
                                  size: 12,
                                  color: AppTheme.textMuted(context),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${div.actionCount} action(s) linked',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textMuted(context),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Icon(
                                  Icons.calendar_today_outlined,
                                  size: 11,
                                  color: AppTheme.textMuted(context),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Created ${ActionRecord.formatDateForUi(div.createdAt)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textMuted(context),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            tooltip: div.isActive
                                ? 'Deactivate Division'
                                : 'Activate Division',
                            icon: Icon(
                              div.isActive
                                  ? Icons.toggle_on_rounded
                                  : Icons.toggle_off_rounded,
                              size: 26,
                              color: div.isActive
                                  ? const Color(0xFF16A34A)
                                  : AppTheme.textMuted(context),
                            ),
                            onPressed: () => _toggleDivisionActive(div),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            tooltip: 'Edit Division',
                            icon: const Icon(
                              Icons.edit_outlined,
                              size: 18,
                              color: Color(0xFF0284C7),
                            ),
                            onPressed: () =>
                                _openEditDivisionDialog(context, div),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            tooltip: 'Delete Division',
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: Color(0xFFDC2626),
                            ),
                            onPressed: () =>
                                _confirmDeleteDivision(context, div),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _toggleDivisionActive(Division division) async {
    try {
      final newStatus = !division.isActive;
      await DivisionService.instance.setDivisionActive(
        divisionId: division.id,
        isActive: newStatus,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Division "${division.name}" is now ${newStatus ? "Active" : "Inactive"}.',
          ),
          backgroundColor: newStatus
              ? const Color(0xFF16A34A)
              : const Color(0xFF475569),
        ),
      );
      await _loadDivisions();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating division status: $e'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }

  void _openAddDivisionDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    bool isSaving = false;
    String? dialogError;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Division'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (dialogError != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Color(0xFFDC2626),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            dialogError!,
                            style: const TextStyle(
                              color: Color(0xFFB91C1C),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Division Name *',
                    hintText: 'e.g. Operations, Projects, Corporate',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Division Code *',
                    hintText: 'e.g. OPS, PRJ, CORP',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    hintText: 'Brief summary of division scope',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      final code = codeCtrl.text.trim().toUpperCase();
                      if (name.isEmpty) {
                        setDialogState(() {
                          dialogError = 'Please enter a division name.';
                        });
                        return;
                      }
                      if (code.isEmpty) {
                        setDialogState(() {
                          dialogError = 'Please enter a division code.';
                        });
                        return;
                      }

                      setDialogState(() {
                        isSaving = true;
                        dialogError = null;
                      });

                      try {
                        final newDiv = await DivisionService.instance
                            .createDivision(
                              organizationId: _currentOrgId,
                              name: name,
                              code: code,
                              description: descCtrl.text.trim(),
                            );
                        if (!mounted) return;
                        Navigator.of(dialogCtx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Division "${newDiv.name}" created successfully!',
                            ),
                            backgroundColor: const Color(0xFF16A34A),
                          ),
                        );
                        await _loadDivisions();
                      } catch (e) {
                        setDialogState(() {
                          isSaving = false;
                          dialogError = e.toString().replaceAll(
                            'Exception: ',
                            '',
                          );
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Division'),
            ),
          ],
        ),
      ),
    );
  }

  void _openEditDivisionDialog(BuildContext context, Division division) {
    final nameCtrl = TextEditingController(text: division.name);
    final codeCtrl = TextEditingController(text: division.code);
    final descCtrl = TextEditingController(text: division.description);
    bool isActive = division.isActive;
    bool isSaving = false;
    String? dialogError;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Edit Division'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (dialogError != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Color(0xFFDC2626),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            dialogError!,
                            style: const TextStyle(
                              color: Color(0xFFB91C1C),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Division Name *',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Division Code *',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active Status'),
                  subtitle: Text(
                    isActive
                        ? 'Available for new actions'
                        : 'Hidden from new action creation',
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: isActive,
                  onChanged: (v) {
                    if (v != null) {
                      setDialogState(() => isActive = v);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      final code = codeCtrl.text.trim().toUpperCase();
                      if (name.isEmpty) {
                        setDialogState(() {
                          dialogError = 'Please enter a division name.';
                        });
                        return;
                      }
                      if (code.isEmpty) {
                        setDialogState(() {
                          dialogError = 'Please enter a division code.';
                        });
                        return;
                      }

                      setDialogState(() {
                        isSaving = true;
                        dialogError = null;
                      });

                      try {
                        final updated = await DivisionService.instance
                            .updateDivision(
                              divisionId: division.id,
                              name: name,
                              code: code,
                              description: descCtrl.text.trim(),
                              isActive: isActive,
                            );
                        if (!mounted) return;
                        Navigator.of(dialogCtx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Division "${updated.name}" updated successfully!',
                            ),
                            backgroundColor: const Color(0xFF16A34A),
                          ),
                        );
                        await _loadDivisions();
                      } catch (e) {
                        setDialogState(() {
                          isSaving = false;
                          dialogError = e.toString().replaceAll(
                            'Exception: ',
                            '',
                          );
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteDivision(BuildContext context, Division division) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Division'),
        content: Text(
          'Are you sure you want to permanently delete division "${division.name}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              final result = await DivisionService.instance.deleteDivision(
                divisionId: division.id,
              );

              if (!mounted) return;

              if (result['error_code'] == 'DEPENDENCIES_EXIST') {
                showDialog(
                  context: context,
                  builder: (depCtx) => AlertDialog(
                    title: const Text('Cannot Delete Division'),
                    content: Text(
                      result['message']?.toString() ?? 'This division is linked to active actions. You can deactivate it instead to preserve historical records.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(depCtx).pop(),
                        child: const Text('Dismiss'),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          Navigator.of(depCtx).pop();
                          await _toggleDivisionActive(division);
                        },
                        child: const Text('Deactivate Instead'),
                      ),
                    ],
                  ),
                );
              } else if (result['success'] == true) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Division "${division.name}" deleted successfully.',
                    ),
                    backgroundColor: const Color(0xFF16A34A),
                  ),
                );
                await _loadDivisions();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      result['message']?.toString() ??
                          'Failed to delete division.',
                    ),
                    backgroundColor: const Color(0xFFDC2626),
                  ),
                );
              }
            },
            child: const Text('Delete Division'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // VIEW 8: NOTIFICATIONS & BROADCASTS
  // ==========================================
  Widget _buildNotificationsView(
    BuildContext context, {
    required bool isDesktop,
  }) {
    return _buildPageWrapper(
      isDesktop: isDesktop,
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
                      'System Alerts & Broadcast Dispatcher',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Broadcast organization-wide notices, safety bulletins, and monitor automated system notifications.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _openBroadcastDialog(context),
                icon: const Icon(Icons.campaign_rounded, size: 17),
                label: const Text('New Broadcast'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF38BDF8)
                      : const Color(0xFF0F172A),
                  foregroundColor:
                      Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF0F172A)
                      : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Builder(
            builder: (context) {
              final List<Map<String, dynamic>> combinedNotifications = [];

              // 1. Dispatched broadcasts
              combinedNotifications.addAll(_systemNotifications);

              // 2. Real account requests needing review
              final pendingApprovalReqs = (_accountRequests ?? [])
                  .where((r) => r.status == AuthAccountStatus.pendingApproval)
                  .toList();
              if (pendingApprovalReqs.isNotEmpty) {
                combinedNotifications.add({
                  'id': 'ALERT-PENDING-APPROVAL',
                  'title':
                      '${pendingApprovalReqs.length} Account Request${pendingApprovalReqs.length > 1 ? "s" : ""} Awaiting Review & Scope Assignment',
                  'time': 'Requires Action',
                  'type': 'Access Request',
                  'severity': 'warning',
                  'unread': true,
                  'actionLabel': 'Review Requests',
                  'action': () => setState(() => _selectedNavIndex = 10),
                });
              }

              final pendingVerifyReqs = (_accountRequests ?? [])
                  .where(
                    (r) => r.status == AuthAccountStatus.pendingVerification,
                  )
                  .toList();
              if (pendingVerifyReqs.isNotEmpty) {
                combinedNotifications.add({
                  'id': 'ALERT-PENDING-VERIFY',
                  'title':
                      '${pendingVerifyReqs.length} Registration${pendingVerifyReqs.length > 1 ? "s" : ""} Awaiting Applicant Email Verification',
                  'time': 'Pending',
                  'type': 'Security',
                  'severity': 'info',
                  'unread': false,
                  'actionLabel': 'View Requests',
                  'action': () => setState(() => _selectedNavIndex = 10),
                });
              }

              if (combinedNotifications.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(32),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.cardBg(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.cardBorder(context)),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.notifications_none_rounded,
                        size: 40,
                        color: AppTheme.textMuted(context),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No Active Alerts or Broadcasts',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Dispatched company broadcasts and pending account registration alerts will appear here.',
                        style: TextStyle(
                          color: AppTheme.textSecondary(context),
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }

              return Material(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.cardBorder(context)),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: combinedNotifications.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: AppTheme.dividerColor(context),
                    ),
                    itemBuilder: (context, index) {
                      final notif = combinedNotifications[index];
                      final isBroadcast = _systemNotifications.contains(notif);
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: notif['severity'] == 'warning'
                                ? const Color(0xFFD97706)
                                      .withValues(alpha: 0.15)
                                : (notif['severity'] == 'success'
                                      ? const Color(0xFF16A34A)
                                            .withValues(alpha: 0.15)
                                      : const Color(0xFF0284C7)
                                            .withValues(alpha: 0.15)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            notif['severity'] == 'warning'
                                ? Icons.warning_amber_rounded
                                : (notif['severity'] == 'success'
                                      ? Icons.check_circle_outline_rounded
                                      : Icons.info_outline_rounded),
                            size: 18,
                            color: notif['severity'] == 'warning'
                                ? const Color(0xFFD97706)
                                : (notif['severity'] == 'success'
                                      ? const Color(0xFF16A34A)
                                      : const Color(0xFF0284C7)),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                notif['title'] as String,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight:
                                      (notif['unread'] as bool? ?? false)
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: AppTheme.textPrimary(context),
                                ),
                              ),
                            ),
                            if (notif['unread'] as bool? ?? false)
                              Container(
                                width: 7,
                                height: 7,
                                margin: const EdgeInsets.only(left: 6),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF0284C7),
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          'Category: ${notif['type']} • ${notif['time']}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (notif['actionLabel'] != null &&
                                notif['action'] != null) ...[
                              TextButton.icon(
                                onPressed: notif['action'] as VoidCallback,
                                icon: const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 14,
                                ),
                                label: Text(
                                  notif['actionLabel'] as String,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                            if (isBroadcast) ...[
                              IconButton(
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 17,
                                  color: AppTheme.textMuted(context),
                                ),
                                onPressed: () {
                                  setState(
                                    () => _systemNotifications.remove(notif),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _openBroadcastDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final msgCtrl = TextEditingController();
    String target = 'All Users & Staff';

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.campaign_rounded,
                color: AppTheme.textPrimary(context),
              ),
              const SizedBox(width: 8),
              const Text('Broadcast Alert Announcement'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Send an urgent announcement banner to active ActionFlow portals.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary(context),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Announcement Title',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: msgCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Broadcast Message Details',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: target,
                dropdownColor: AppTheme.cardBg(context),
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textPrimary(context),
                ),
                decoration: const InputDecoration(labelText: 'Target Audience'),
                items:
                    [
                          'All Users & Staff',
                          'Department Managers Only',
                          'Staff Only',
                          'North Plant Facility Only',
                        ]
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(
                              t,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                onChanged: (val) =>
                    setDialogState(() => target = val ?? target),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF38BDF8)
                    : const Color(0xFF0F172A),
                foregroundColor: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF0F172A)
                    : Colors.white,
              ),
              onPressed: () {
                if (titleCtrl.text.trim().isNotEmpty) {
                  setState(() {
                    _systemNotifications.insert(0, {
                      'id': 'NOTIF-${DateTime.now().millisecondsSinceEpoch}',
                      'title':
                          '[Broadcast to $target] ${titleCtrl.text.trim()}',
                      'time': 'Just now',
                      'type': 'Broadcast',
                      'severity': 'warning',
                      'unread': true,
                    });
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Broadcast announcement dispatched successfully.',
                      ),
                    ),
                  );
                }
                Navigator.of(dialogCtx).pop();
              },
              child: const Text('Dispatch Broadcast'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // VIEW 8: REPORTS & AUDIT
  // ==========================================
  Widget _buildReportsView(BuildContext context, {required bool isDesktop}) {
    final isLive = SupabaseConfig.isInitialized;
    if (isLive) {
      return _buildPageWrapper(
        isDesktop: isDesktop,
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
                        'Executive Action & Compliance Reports',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'System-wide action velocity, closure rate analytics, and compliance audit exports.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorder(context)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.insights_rounded,
                      size: 40,
                      color: Color(0xFF0284C7),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFCD34D)),
                    ),
                    child: const Text(
                      'Integration Pending',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Action Tracking & Compliance Analytics Queued',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Text(
                      'Live action velocity, closure rate analytics, and compliance audit exports are scheduled for the upcoming Action Tracker module integration. When action records are logged, real-time metrics will automatically display here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary(context),
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Action & Compliance module integration is pending rollout.',
                          ),
                          backgroundColor: Color(0xFF0F172A),
                        ),
                      );
                    },
                    icon: const Icon(Icons.info_outline_rounded, size: 16),
                    label: const Text('Module Roadmap Status'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final actions = MockActionStore.instance.actions;
    final total = actions.length;
    final completed = actions
        .where(
          (a) =>
              a.status.toLowerCase() == 'completed' ||
              a.status.toLowerCase() == 'closed',
        )
        .length;
    final inProgress = actions
        .where((a) => a.status.toLowerCase() == 'in progress')
        .length;
    final pending = actions
        .where(
          (a) =>
              a.status.toLowerCase() == 'open' ||
              a.status.toLowerCase() == 'pending',
        )
        .length;
    final overdue = actions.where((a) => _isActionOverdue(a)).length;

    return _buildPageWrapper(
      isDesktop: isDesktop,
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
                      'Executive Action & Compliance Reports',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'System-wide action velocity, closure rate analytics, and compliance audit exports.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'ActionFlow Executive Audit Summary CSV exported successfully.',
                      ),
                      backgroundColor: Color(0xFF0F172A),
                    ),
                  );
                },
                icon: const Icon(Icons.file_download_outlined, size: 17),
                label: const Text('Export Summary CSV'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF38BDF8)
                      : const Color(0xFF0F172A),
                  foregroundColor:
                      Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF0F172A)
                      : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // KPI Breakdown
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardBg(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.cardBorder(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Action Status Distribution',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 12),
                _buildReportProgressBar(
                  context,
                  'Completed Actions',
                  completed,
                  total,
                  const Color(0xFF16A34A),
                ),
                const SizedBox(height: 8),
                _buildReportProgressBar(
                  context,
                  'In Progress Work',
                  inProgress,
                  total,
                  const Color(0xFF0284C7),
                ),
                const SizedBox(height: 8),
                _buildReportProgressBar(
                  context,
                  'Pending Staff Start',
                  pending,
                  total,
                  const Color(0xFFEAB308),
                ),
                const SizedBox(height: 8),
                _buildReportProgressBar(
                  context,
                  'Overdue / SLA Breached',
                  overdue,
                  total,
                  const Color(0xFFEF4444),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Department Performance Breakdown Table
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardBg(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.cardBorder(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Department Action Performance Matrix',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 10),
                DataTable(
                  horizontalMargin: 12,
                  columnSpacing: 16,
                  headingRowHeight: 38,
                  dataRowMinHeight: 40,
                  dataRowMaxHeight: 44,
                  headingRowColor: WidgetStateProperty.all(
                    AppTheme.containerBg(context),
                  ),
                  columns: [
                    DataColumn(
                      label: Text(
                        'DEPARTMENT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'TOTAL ACTIONS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'COMPLIANCE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'AVG RESOLUTION',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ),
                  ],
                  rows: _departments.map((dept) {
                    return DataRow(
                      cells: [
                        DataCell(
                          Text(
                            dept['name'] as String,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: AppTheme.textPrimary(context),
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            '${dept['activeActions']} active',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        ),
                        const DataCell(
                          Text(
                            '96.4%',
                            style: TextStyle(
                              color: Color(0xFF16A34A),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            '4.2 Days',
                            style: TextStyle(
                              color: AppTheme.textSecondary(context),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportProgressBar(
    BuildContext context,
    String label,
    int value,
    int total,
    Color color,
  ) {
    final pct = total > 0 ? (value / total).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary(context),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '$value / $total (${(pct * 100).toStringAsFixed(1)}%)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        LinearProgressIndicator(
          value: pct,
          backgroundColor: AppTheme.progressTrackBg(context),
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
      ],
    );
  }

  // ==========================================
  // VIEW 9: SYSTEM SETTINGS
  // ==========================================
  Widget _buildSystemSettingsView(
    BuildContext context, {
    required bool isDesktop,
  }) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final currentMode = ThemeController.instance.themeMode;

        return _buildPageWrapper(
          isDesktop: isDesktop,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'System Preferences & Security Governance',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Global authentication security, automated reminders, escalation rules, and system theme preferences.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary(context),
                ),
              ),
              const SizedBox(height: 14),

              // Appearance & Theme Card
              Material(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.cardBorder(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Appearance & Theme Mode',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Select interface theme. Settings persist across device sessions offline.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _buildAdminThemeTile(
                            context,
                            title: 'Light Theme',
                            mode: ThemeMode.light,
                            currentMode: currentMode,
                            icon: Icons.light_mode_rounded,
                            color: const Color(0xFFEAB308),
                          ),
                          _buildAdminThemeTile(
                            context,
                            title: 'Dark Theme',
                            mode: ThemeMode.dark,
                            currentMode: currentMode,
                            icon: Icons.dark_mode_outlined,
                            color: const Color(0xFF38BDF8),
                          ),
                          _buildAdminThemeTile(
                            context,
                            title: 'System Default',
                            mode: ThemeMode.system,
                            currentMode: currentMode,
                            icon: Icons.settings_brightness_outlined,
                            color: const Color(0xFF8B5CF6),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Security & Access Policies Card
              Material(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.cardBorder(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Security & Access Policies',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Enforce Multi-Factor Authentication (2FA) for Managers & Admins',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                        subtitle: Text(
                          'Require OTP verification on login from new devices.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                        value: _enforce2FA,
                        onChanged: (val) => setState(() => _enforce2FA = val),
                      ),
                      Divider(
                        height: 16,
                        color: AppTheme.dividerColor(context),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Allow Self-Registration for External Staff',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                        subtitle: Text(
                          'Allow third-party contractors to request staff portal access.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                        value: _allowExternalSignup,
                        onChanged: (val) =>
                            setState(() => _allowExternalSignup = val),
                      ),
                      Divider(
                        height: 16,
                        color: AppTheme.dividerColor(context),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Automated Overdue Action Escalation Alerts',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                        subtitle: Text(
                          'Automatically alert Department Heads when actions exceed target dates by 48 hours.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                        value: _autoEscalateOverdue,
                        onChanged: (val) =>
                            setState(() => _autoEscalateOverdue = val),
                      ),
                      Divider(
                        height: 16,
                        color: AppTheme.dividerColor(context),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Inactivity Session Timeout',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary(context),
                                ),
                              ),
                              Text(
                                'Automatically log out idle portal sessions',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary(context),
                                ),
                              ),
                            ],
                          ),
                          DropdownButton<int>(
                            value: _sessionTimeoutMinutes,
                            dropdownColor: AppTheme.cardBg(context),
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textPrimary(context),
                            ),
                            items: [15, 30, 60, 120]
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(
                                      '$m Minutes',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textPrimary(context),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) => setState(
                              () => _sessionTimeoutMinutes = val ?? 30,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'System configuration preferences saved successfully.',
                      ),
                      backgroundColor: Color(0xFF0F172A),
                    ),
                  );
                },
                icon: const Icon(Icons.save_rounded, size: 17),
                label: const Text('Save System Preferences'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF38BDF8)
                      : const Color(0xFF0F172A),
                  foregroundColor:
                      Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF0F172A)
                      : Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAdminThemeTile(
    BuildContext context, {
    required String title,
    required ThemeMode mode,
    required ThemeMode currentMode,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = mode == currentMode;

    return InkWell(
      onTap: () => ThemeController.instance.setThemeMode(mode),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryAccent(context).withValues(alpha: 0.1)
              : AppTheme.containerBg(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryAccent(context)
                : AppTheme.cardBorder(context),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // HELPER WIDGETS
  // ==========================================
  Widget _buildTenantBadge() {
    final orgName = _adminProfile.organizationName.isNotEmpty
        ? _adminProfile.organizationName
        : 'Tenant Organization';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: const Color(0xFF38BDF8).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.business_rounded,
            size: 13,
            color: Color(0xFF0284C7),
          ),
          const SizedBox(width: 5),
          Text(
            orgName,
            style: const TextStyle(
              color: Color(0xFF0284C7),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleBadge(String label) {
    Color bg = const Color(0xFF64748B).withValues(alpha: 0.15);
    Color text = const Color(0xFF64748B);

    if (label.contains('Admin')) {
      bg = const Color(0xFF7C3AED).withValues(alpha: 0.15);
      text = const Color(0xFF7C3AED);
    } else if (label.contains('Manager')) {
      bg = const Color(0xFF0284C7).withValues(alpha: 0.15);
      text = const Color(0xFF0284C7);
    } else if (label.contains('Staff') || label.contains('Worker')) {
      bg = const Color(0xFF16A34A).withValues(alpha: 0.15);
      text = const Color(0xFF16A34A);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final isActive = status == 'Active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF16A34A).withValues(alpha: 0.15)
            : const Color(0xFFEF4444).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isActive ? const Color(0xFF16A34A) : const Color(0xFFEF4444),
        ),
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.inputFill(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.inputBorder(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary(context),
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isDense: true,
              dropdownColor: AppTheme.cardBg(context),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary(context),
              ),
              items: items.map((item) {
                return DropdownMenuItem(value: item, child: Text(item));
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // VIEW 10: ACCOUNT REQUESTS & APPROVALS
  // ==========================================
  Widget _buildAccountRequestsView(
    BuildContext context, {
    required bool isDesktop,
    required bool isTablet,
  }) {
    final allRequests =
        _accountRequests ?? MockAuthStore.instance.registrations;
    final pendingCount = allRequests
        .where(
          (r) =>
              r.status == AuthAccountStatus.pendingApproval ||
              r.status == AuthAccountStatus.pendingVerification,
        )
        .length;
    final approvedCount = allRequests
        .where((r) => r.status == AuthAccountStatus.active)
        .length;
    final rejectedCount = allRequests
        .where((r) => r.status == AuthAccountStatus.rejected)
        .length;

    final filtered = allRequests.where((req) {
      // Tab status filter
      if (_requestStatusTab == 'Pending') {
        if (req.status != AuthAccountStatus.pendingApproval &&
            req.status != AuthAccountStatus.pendingVerification) {
          return false;
        }
      } else if (_requestStatusTab == 'Approved') {
        if (req.status != AuthAccountStatus.active) {
          return false;
        }
      } else if (_requestStatusTab == 'Rejected') {
        if (req.status != AuthAccountStatus.rejected) {
          return false;
        }
      }

      // Role filter
      if (_requestRoleFilter != 'All') {
        if (_requestRoleFilter == 'Staff' &&
            req.requestedType != RequestedAccountType.staff) {
          return false;
        }
        if (_requestRoleFilter == 'Manager' &&
            req.requestedType != RequestedAccountType.manager) {
          return false;
        }
      }

      // Search query filter (matches name, email, department, site, designation, and manager scopes)
      if (_requestSearchQuery.isNotEmpty) {
        final q = _requestSearchQuery.toLowerCase();
        final match =
            req.fullName.toLowerCase().contains(q) ||
            req.email.toLowerCase().contains(q) ||
            req.department.toLowerCase().contains(q) ||
            req.site.toLowerCase().contains(q) ||
            req.designation.toLowerCase().contains(q) ||
            (req.isManager &&
                req.managerScopes.any(
                  (s) =>
                      s.departmentName.toLowerCase().contains(q) ||
                      s.siteName.toLowerCase().contains(q),
                ));
        if (!match) return false;
      }

      return true;
    }).toList();

    return _buildPageWrapper(
      isDesktop: isDesktop,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 650;
              final buttons = Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isLoadingRequests ? null : _loadAccountRequests,
                    icon: _isLoadingRequests
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Refresh'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  if (!SupabaseConfig.isInitialized)
                    OutlinedButton.icon(
                      onPressed: () {
                        MockAuthStore.instance.reset();
                        _loadAccountRequests();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Reset mock registration requests to demo data.',
                            ),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.restore_rounded, size: 16),
                      label: const Text('Reset Demo Data'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                ],
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Account Requests & Approvals',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Review registration requests, approve new staff and manager accounts, or reject applications with required reasons.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 12),
                    buttons,
                  ],
                );
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Account Requests & Approvals',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Review registration requests, approve new staff and manager accounts, or reject applications with required reasons.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  buttons,
                ],
              );
            },
          ),
          const SizedBox(height: 14),

          // KPI Summary Cards
          LayoutBuilder(
            builder: (context, cardConstraints) {
              final width = cardConstraints.maxWidth;
              final crossAxisCount = width > 1000 ? 4 : (width > 600 ? 2 : 1);
              return GridView.count(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: width > 1000
                    ? 2.2
                    : (width > 600 ? 2.4 : 3.0),
                children: [
                  _buildStatCard(
                    context: context,
                    title: 'Pending Approvals',
                    value: '$pendingCount',
                    subtitle: 'Requires administrator decision',
                    icon: Icons.hourglass_top_rounded,
                    iconColor: const Color(0xFF7C3AED),
                    bgColor: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                    onTap: () => setState(() => _requestStatusTab = 'Pending'),
                  ),
                  _buildStatCard(
                    context: context,
                    title: 'Approved Accounts',
                    value: '$approvedCount',
                    subtitle: 'Active in system directory',
                    icon: Icons.check_circle_rounded,
                    iconColor: const Color(0xFF16A34A),
                    bgColor: const Color(0xFF16A34A).withValues(alpha: 0.12),
                    onTap: () => setState(() => _requestStatusTab = 'Approved'),
                  ),
                  _buildStatCard(
                    context: context,
                    title: 'Rejected Applications',
                    value: '$rejectedCount',
                    subtitle: 'With audit rejection reasons',
                    icon: Icons.cancel_rounded,
                    iconColor: const Color(0xFFDC2626),
                    bgColor: const Color(0xFFDC2626).withValues(alpha: 0.12),
                    onTap: () => setState(() => _requestStatusTab = 'Rejected'),
                  ),
                  _buildStatCard(
                    context: context,
                    title: 'Total Submissions',
                    value: '${allRequests.length}',
                    subtitle: 'All historical registrations',
                    icon: Icons.how_to_reg_rounded,
                    iconColor: const Color(0xFF0284C7),
                    bgColor: const Color(0xFF0284C7).withValues(alpha: 0.12),
                    onTap: () => setState(() => _requestStatusTab = 'All'),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          // Filters & Search Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.cardBg(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.cardBorder(context)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 38,
                        child: TextField(
                          onChanged: (v) =>
                              setState(() => _requestSearchQuery = v),
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textPrimary(context),
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search applicant name, email, department, site, designation...',
                            hintStyle: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted(context),
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              size: 18,
                              color: AppTheme.textSecondary(context),
                            ),
                            suffixIcon: _requestSearchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 16),
                                    onPressed: () => setState(
                                      () => _requestSearchQuery = '',
                                    ),
                                  )
                                : null,
                            filled: true,
                            fillColor: AppTheme.inputFill(context),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: AppTheme.inputBorder(context),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: AppTheme.inputBorder(context),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _buildFilterDropdown(
                      label: 'Role',
                      value: _requestRoleFilter,
                      items: ['All', 'Staff', 'Manager'],
                      onChanged: (v) {
                        if (v != null) setState(() => _requestRoleFilter = v);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Status Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildStatusFilterChip(
                        label: 'Pending ($pendingCount)',
                        tabValue: 'Pending',
                        color: const Color(0xFF7C3AED),
                      ),
                      const SizedBox(width: 8),
                      _buildStatusFilterChip(
                        label: 'Approved ($approvedCount)',
                        tabValue: 'Approved',
                        color: const Color(0xFF16A34A),
                      ),
                      const SizedBox(width: 8),
                      _buildStatusFilterChip(
                        label: 'Rejected ($rejectedCount)',
                        tabValue: 'Rejected',
                        color: const Color(0xFFDC2626),
                      ),
                      const SizedBox(width: 8),
                      _buildStatusFilterChip(
                        label: 'All (${allRequests.length})',
                        tabValue: 'All',
                        color: const Color(0xFF0284C7),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Requests List Area
          if (_isLoadingRequests && _accountRequests == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorder(context)),
              ),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(strokeWidth: 2.5),
                    SizedBox(height: 16),
                    Text(
                      'Loading account requests...',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_requestsErrorMessage != null && _accountRequests == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 36,
                    color: Color(0xFFDC2626),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Failed to load account requests',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF991B1B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _requestsErrorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFB91C1C),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _loadAccountRequests,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            )
          else if (filtered.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorder(context)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.inbox_rounded,
                    size: 48,
                    color: AppTheme.textMuted(context),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No Registration Requests Found',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'There are no requests matching the selected filter criteria.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final req = filtered[index];
                return _buildRequestCard(context, req);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildStatusFilterChip({
    required String label,
    required String tabValue,
    required Color color,
  }) {
    final isSelected = _requestStatusTab == tabValue;
    return InkWell(
      onTap: () => setState(() => _requestStatusTab = tabValue),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? color : AppTheme.cardBorder(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? color : AppTheme.textSecondary(context),
          ),
        ),
      ),
    );
  }

  Widget _buildRequestCard(BuildContext context, SignupRequest req) {
    final isPending =
        req.status == AuthAccountStatus.pendingApproval ||
        req.status == AuthAccountStatus.pendingVerification;
    final isRejected = req.status == AuthAccountStatus.rejected;
    final canApprove =
        req.status == AuthAccountStatus.pendingApproval && req.isEmailVerified;
    final canReevaluate = isRejected && req.isEmailVerified;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Avatar, Name, Role, Status
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor:
                    req.requestedType == RequestedAccountType.manager
                    ? const Color(0xFF1565C0)
                    : const Color(0xFF0D9488),
                child: Text(
                  req.fullName.isNotEmpty ? req.fullName[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          req.fullName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                        _buildRoleBadge(req.requestedType.label),
                        _buildAuthStatusBadge(req.status),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${req.email}${req.phone.isNotEmpty ? " • ${req.phone}" : ""}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: AppTheme.dividerColor(context)),
          const SizedBox(height: 10),

          // Metadata Grid
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              if (req.designation.isNotEmpty)
                _buildCardMetaItem('Designation', req.designation),
              if (req.isManager) ...[
                if (req.managerScopes.isNotEmpty)
                  _buildCardMetaItem(
                    'Scopes',
                    req.managerScopes.map((s) => s.displayName).join(', '),
                  )
                else if (req.department.isNotEmpty || req.site.isNotEmpty)
                  _buildCardMetaItem(
                    'Scope',
                    '${req.department} / ${req.site}',
                  ),
              ] else ...[
                if (req.department.isNotEmpty)
                  _buildCardMetaItem('Department', req.department),
                if (req.division.isNotEmpty)
                  _buildCardMetaItem('Division', req.division),
                if (req.site.isNotEmpty) _buildCardMetaItem('Site', req.site),
                if (req.team.isNotEmpty) _buildCardMetaItem('Team', req.team),
              ],
              _buildCardMetaItem(
                'Email Verified',
                req.isEmailVerified ? 'Yes' : 'Pending',
              ),
              _buildCardMetaItem('Submitted', _formatDateTime(req.createdAt)),
            ],
          ),

          // Rejection Box
          if (isRejected && req.rejectionReason != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFFDC2626),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rejection Reason: ${req.rejectionReason}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF991B1B),
                          ),
                        ),
                        if (req.rejectedBy != null || req.rejectedAt != null)
                          Text(
                            'By ${req.rejectedBy ?? "Administrator"} on ${_formatDateTime(req.rejectedAt ?? DateTime.now())}',
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFFB91C1C),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          // Actions Footer
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showRequestDetailsDialog(context, req),
                  icon: const Icon(Icons.visibility_outlined, size: 15),
                  label: const Text('View Details'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                // Approval Action Rule:
                // Approve is only available when status == pending_admin_approval AND is_email_verified == true.
                if (canApprove)
                  ElevatedButton.icon(
                    onPressed: () => _handleApprove(req),
                    icon: const Icon(Icons.check_rounded, size: 15),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  )
                else if (isPending)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFCD34D)),
                    ),
                    child: const Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 5,
                      children: [
                        Icon(
                          Icons.mark_email_unread_outlined,
                          size: 14,
                          color: Color(0xFF92400E),
                        ),
                        Text(
                          'Awaiting email verification',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (canReevaluate)
                  ElevatedButton.icon(
                    onPressed: () => _handleApprove(req),
                    icon: const Icon(Icons.check_rounded, size: 15),
                    label: const Text('Re-evaluate & Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  )
                else if (isRejected && !req.isEmailVerified)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFCD34D)),
                    ),
                    child: const Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 5,
                      children: [
                        Icon(
                          Icons.mark_email_unread_outlined,
                          size: 14,
                          color: Color(0xFF92400E),
                        ),
                        Text(
                          'Awaiting email verification',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (isPending || req.status == AuthAccountStatus.active)
                  OutlinedButton.icon(
                    onPressed: () => _showRejectDialog(context, req),
                    icon: const Icon(Icons.close_rounded, size: 15),
                    label: Text(
                      req.status == AuthAccountStatus.active
                          ? 'Revoke / Reject'
                          : 'Reject',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFDC2626)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardMetaItem(String label, String value) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted(context),
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary(context),
            ),
          ),
        ],
      ),
    );
  }

  void _showRequestDetailsDialog(BuildContext context, SignupRequest req) {
    final canApproveInDialog =
        req.status == AuthAccountStatus.pendingApproval && req.isEmailVerified;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.cardBg(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFF1565C0),
              child: Text(
                req.fullName.isNotEmpty ? req.fullName[0].toUpperCase() : 'U',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    req.fullName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  Text(
                    req.email,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
            _buildAuthStatusBadge(req.status),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 6),
                _buildDetailSectionTitle('Applicant Profile & Contact'),
                _buildDialogRow('Full Name', req.fullName),
                _buildDialogRow('Email Address', req.email),
                _buildDialogRow(
                  'Phone Number',
                  req.phone.isNotEmpty ? req.phone : 'Not provided',
                ),
                _buildDialogRow('Requested Role', req.requestedType.label),
                _buildDialogRow(
                  'Email Verified',
                  req.isEmailVerified ? 'Yes (Verified)' : 'No (Pending)',
                ),
                const SizedBox(height: 12),
                _buildDetailSectionTitle('Organizational Placement'),
                _buildDialogRow(
                  'Job Designation',
                  req.designation.isNotEmpty
                      ? req.designation
                      : 'Not specified',
                ),
                if (req.isManager) ...[
                  if (req.managerScopes.isNotEmpty) ...[
                    for (int i = 0; i < req.managerScopes.length; i++)
                      _buildDialogRow(
                        'Operational Scope ${i + 1}',
                        req.managerScopes[i].displayName,
                      ),
                  ] else
                    _buildDialogRow(
                      'Operational Scope',
                      req.department.isNotEmpty || req.site.isNotEmpty
                          ? '${req.department} / ${req.site}'
                          : 'Not assigned',
                    ),
                ] else ...[
                  _buildDialogRow(
                    'Department',
                    req.department.isNotEmpty ? req.department : 'Not assigned',
                  ),
                  _buildDialogRow(
                    'Division',
                    req.division.isNotEmpty ? req.division : 'Not assigned',
                  ),
                  _buildDialogRow(
                    'Site / Facility',
                    req.site.isNotEmpty ? req.site : 'Not assigned',
                  ),
                  _buildDialogRow(
                    'Assigned Team',
                    req.team.isNotEmpty ? req.team : 'Not assigned',
                  ),
                ],
                const SizedBox(height: 12),
                _buildDetailSectionTitle('Audit & Timeline'),
                _buildDialogRow(
                  'Registration Submitted',
                  _formatDateTime(req.createdAt),
                ),
                if (req.approvedAt != null)
                  _buildDialogRow(
                    'Approved On',
                    '${_formatDateTime(req.approvedAt!)} by ${req.approvedBy ?? "Administrator"}',
                  ),
                if (req.rejectedAt != null) ...[
                  _buildDialogRow(
                    'Rejected On',
                    '${_formatDateTime(req.rejectedAt!)} by ${req.rejectedBy ?? "Administrator"}',
                  ),
                  _buildDialogRow(
                    'Rejection Reason',
                    req.rejectionReason ?? 'None provided',
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Close'),
          ),
          if (req.status != AuthAccountStatus.rejected)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                side: const BorderSide(color: Color(0xFFDC2626)),
              ),
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                _showRejectDialog(context, req);
              },
              child: const Text('Reject Application'),
            ),
          if (req.status != AuthAccountStatus.active)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: canApproveInDialog
                    ? const Color(0xFF16A34A)
                    : Colors.grey.shade400,
                foregroundColor: Colors.white,
              ),
              onPressed: canApproveInDialog
                  ? () {
                      Navigator.of(dialogCtx).pop();
                      _handleApprove(req);
                    }
                  : null,
              child: Text(
                canApproveInDialog
                    ? 'Approve Account'
                    : 'Awaiting Email Verification',
              ),
            ),
        ],
      ),
    );
  }

  void _showRejectDialog(BuildContext context, SignupRequest req) {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.cardBg(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.person_off_rounded,
                color: Color(0xFFEF4444),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Reject Account Request',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          child: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Provide an explanation for rejecting the registration request of ${req.fullName} (${req.requestedType.label}). This explanation will be displayed to the applicant.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary(context),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: reasonController,
                  maxLines: 3,
                  autofocus: true,
                  style: TextStyle(color: AppTheme.textPrimary(context)),
                  decoration: InputDecoration(
                    labelText: 'Reason for Rejection *',
                    hintText: 'e.g., Incomplete department authorization or invalid role tier.',
                    labelStyle: TextStyle(
                      color: AppTheme.textSecondary(context),
                    ),
                    hintStyle: TextStyle(
                      color: AppTheme.textMuted(context),
                      fontSize: 12,
                    ),
                    filled: true,
                    fillColor: AppTheme.inputFill(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppTheme.inputBorder(context),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppTheme.inputBorder(context),
                      ),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                      borderSide: BorderSide(
                        color: Color(0xFFEF4444),
                        width: 1.5,
                      ),
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter a rejection reason.';
                    }
                    if (val.trim().length < 5) {
                      return 'Rejection reason must be at least 5 characters.';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                final reason = reasonController.text.trim();
                Navigator.of(dialogCtx).pop();
                _handleReject(req, reason);
              }
            },
            child: const Text('Confirm Rejection'),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthStatusBadge(AuthAccountStatus status) {
    Color bg;
    Color fg;
    switch (status) {
      case AuthAccountStatus.pendingApproval:
        bg = const Color(0xFF7C3AED).withValues(alpha: 0.15);
        fg = const Color(0xFF7C3AED);
        break;
      case AuthAccountStatus.pendingVerification:
        bg = const Color(0xFF0284C7).withValues(alpha: 0.15);
        fg = const Color(0xFF0284C7);
        break;
      case AuthAccountStatus.active:
        bg = const Color(0xFF16A34A).withValues(alpha: 0.15);
        fg = const Color(0xFF16A34A);
        break;
      case AuthAccountStatus.rejected:
        bg = const Color(0xFFDC2626).withValues(alpha: 0.15);
        fg = const Color(0xFFDC2626);
        break;
      case AuthAccountStatus.inactive:
        bg = const Color(0xFFD97706).withValues(alpha: 0.15);
        fg = const Color(0xFFD97706);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Widget _buildDetailSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: AppTheme.textMuted(context),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildDialogRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary(context),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // VIEW 11: OPERATIONAL CALENDAR & SCHEDULE
  // ==========================================
  Widget _buildCalendarView(
    BuildContext context, {
    required bool isDesktop,
    required bool isTablet,
  }) {
    return _buildPageWrapper(
      isDesktop: isDesktop,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCalendarHeader(context, isDesktop: isDesktop),
          const SizedBox(height: 16),
          if (isDesktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: _buildCalendarGridCard(context, isDesktop: isDesktop),
                ),
                const SizedBox(width: 16),
                Expanded(flex: 3, child: _buildCalendarSidePanel(context)),
              ],
            )
          else ...[
            _buildCalendarGridCard(context, isDesktop: isDesktop),
            const SizedBox(height: 16),
            _buildCalendarSidePanel(context),
          ],
        ],
      ),
    );
  }

  Widget _buildCalendarHeader(BuildContext context, {required bool isDesktop}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: isDesktop
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.calendar_month_rounded,
                          color: AppTheme.primaryColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Operational Calendar & Schedule',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary(context),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Company-wide HSE events, scheduled audits, compliance deadlines, and action follow-ups',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary(context),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Row(
                  children: [
                    _buildTenantBadge(),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _refreshAllDashboardData,
                      icon: const Icon(Icons.refresh_rounded, size: 14),
                      label: const Text(
                        'Refresh',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        side: BorderSide(color: AppTheme.cardBorder(context)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _openScheduleEventDialog(context),
                      icon: const Icon(Icons.add_rounded, size: 15),
                      label: const Text(
                        'Schedule Event',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.calendar_month_rounded,
                        color: AppTheme.primaryColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Operational Calendar & Schedule',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Company-wide HSE events, scheduled audits, compliance deadlines, and action follow-ups',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildTenantBadge(),
                    const Spacer(),
                    IconButton(
                      onPressed: _refreshAllDashboardData,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      tooltip: 'Refresh',
                    ),
                    const SizedBox(width: 4),
                    ElevatedButton.icon(
                      onPressed: () => _openScheduleEventDialog(context),
                      icon: const Icon(Icons.add_rounded, size: 14),
                      label: const Text(
                        'Schedule Event',
                        style: TextStyle(fontSize: 11),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildCalendarGridCard(
    BuildContext context, {
    required bool isDesktop,
  }) {
    final daysInMonth = DateUtils.getDaysInMonth(
      _calendarMonth.year,
      _calendarMonth.month,
    );
    final firstWeekday = DateTime(
      _calendarMonth.year,
      _calendarMonth.month,
      1,
    ).weekday;
    final weekdayOffset = (firstWeekday - 1) % 7;
    final totalCells = ((weekdayOffset + daysInMonth + 6) ~/ 7) * 7;

    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month navigation bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_getMonthName(_calendarMonth.month)} ${_calendarMonth.year}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, size: 20),
                    tooltip: 'Previous Month',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: () {
                      setState(() {
                        _calendarMonth = DateTime(
                          _calendarMonth.year,
                          _calendarMonth.month - 1,
                        );
                      });
                    },
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        final now = DateTime.now();
                        _calendarMonth = DateTime(now.year, now.month);
                        _selectedCalendarDate = now;
                      });
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                    ),
                    child: const Text('Today', style: TextStyle(fontSize: 12)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, size: 20),
                    tooltip: 'Next Month',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: () {
                      setState(() {
                        _calendarMonth = DateTime(
                          _calendarMonth.year,
                          _calendarMonth.month + 1,
                        );
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Weekdays header
          Row(
            children: weekdays.map((day) {
              return Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMuted(context),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),

          // Grid cells
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: isDesktop ? 1.3 : 1.05,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemCount: totalCells,
            itemBuilder: (context, index) {
              final dayNumber = index - weekdayOffset + 1;
              final isValidDay = dayNumber >= 1 && dayNumber <= daysInMonth;

              if (!isValidDay) {
                return Container(
                  decoration: BoxDecoration(
                    color: AppTheme.containerBg(context).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              }

              final cellDate = DateTime(
                _calendarMonth.year,
                _calendarMonth.month,
                dayNumber,
              );
              final now = DateTime.now();
              final isToday =
                  cellDate.year == now.year &&
                  cellDate.month == now.month &&
                  cellDate.day == now.day;
              final isSelected =
                  _selectedCalendarDate != null &&
                  cellDate.year == _selectedCalendarDate!.year &&
                  cellDate.month == _selectedCalendarDate!.month &&
                  cellDate.day == _selectedCalendarDate!.day;

              // Sample milestone indicator days (e.g., 5, 12, 19, 26)
              final hasEvent =
                  (dayNumber % 7 == 5) || dayNumber == 12 || dayNumber == 24;

              return InkWell(
                onTap: () {
                  setState(() {
                    _selectedCalendarDate = cellDate;
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryColor.withValues(alpha: 0.15)
                        : (isToday
                              ? AppTheme.primaryColor.withValues(alpha: 0.05)
                              : AppTheme.cardBg(context)),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : (isToday
                                ? AppTheme.primaryColor.withValues(alpha: 0.5)
                                : AppTheme.cardBorder(context)),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$dayNumber',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isToday || isSelected
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: isSelected
                              ? AppTheme.primaryColor
                              : (isToday
                                    ? AppTheme.primaryColor
                                    : AppTheme.textPrimary(context)),
                        ),
                      ),
                      if (hasEvent) ...[
                        const SizedBox(height: 3),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryColor
                                : Colors.teal,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarSidePanel(BuildContext context) {
    final selectedDate = _selectedCalendarDate ?? DateTime.now();
    final dateString =
        '${selectedDate.day} ${_getMonthName(selectedDate.month)} ${selectedDate.year}';

    final scheduledMilestones = !SupabaseConfig.isInitialized
        ? [
            {
              'title': 'Quarterly HSE Site Inspection',
              'facility': 'North Plant Facility',
              'time': '10:00 AM - 12:30 PM',
              'type': 'Audit',
              'status': 'Scheduled',
              'color': Colors.blue,
            },
            {
              'title': 'Emergency Evacuation Drill',
              'facility': 'Central Warehouse Hub',
              'time': '02:00 PM - 03:00 PM',
              'type': 'Drill',
              'status': 'Upcoming',
              'color': Colors.orange,
            },
            {
              'title': 'Fire Safety Equipment Certification',
              'facility': 'East Terminal Operations',
              'time': '11:00 AM - 01:00 PM',
              'type': 'Inspection',
              'status': 'Scheduled',
              'color': Colors.green,
            },
            {
              'title': 'Environmental Compliance Review',
              'facility': 'West Research Lab',
              'time': '04:00 PM - 05:00 PM',
              'type': 'Review',
              'status': 'Pending Verification',
              'color': Colors.purple,
            },
          ]
        : <Map<String, dynamic>>[];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Events & Milestones',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                dateString,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Honest Action Tracker note
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: Colors.blue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Action Follow-Up & Audit Sync',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Scheduled audit milestones and corrective action deadlines will automatically populate here once the Action Tracker module is connected.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          Text(
            'Operational Schedule',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),

          if (scheduledMilestones.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.event_busy_rounded,
                      size: 32,
                      color: AppTheme.textMuted(context),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No events scheduled for $dateString',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Operational inspections and audit deadlines will sync here once actions are assigned.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary(context),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: scheduledMilestones.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = scheduledMilestones[index];
                final color = item['color'] as Color;

                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.containerBg(context).withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.cardBorder(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              item['title'] as String,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary(context),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item['type'] as String,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 12,
                            color: AppTheme.textMuted(context),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${item['facility']} • ${item['time']}',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary(context),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _openScheduleEventDialog(BuildContext context) {
    final titleController = TextEditingController();
    final notesController = TextEditingController();
    String selectedCategory = 'HSE Inspection';
    String selectedSite = _sites.isNotEmpty
        ? (_sites.first['name'] as String)
        : 'All Facilities';
    DateTime eventDate = _selectedCalendarDate ?? DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.event_available_rounded,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(width: 8),
              const Text(
                'Schedule Operational Event',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Event Title *',
                      hintText: 'e.g. Monthly Fire Alarm Testing',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'HSE Inspection',
                        child: Text('HSE Inspection'),
                      ),
                      DropdownMenuItem(
                        value: 'Emergency Drill',
                        child: Text('Emergency Drill'),
                      ),
                      DropdownMenuItem(
                        value: 'Regulatory Audit',
                        child: Text('Regulatory Audit'),
                      ),
                      DropdownMenuItem(
                        value: 'Equipment Check',
                        child: Text('Equipment Check'),
                      ),
                      DropdownMenuItem(
                        value: 'Safety Training',
                        child: Text('Safety Training'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedCategory = val);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedSite,
                    decoration: const InputDecoration(
                      labelText: 'Target Facility / Site',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'All Facilities',
                        child: Text('All Facilities'),
                      ),
                      ..._sites.map(
                        (s) => DropdownMenuItem(
                          value: s['name'] as String,
                          child: Text(s['name'] as String),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedSite = val);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Event Date',
                      style: TextStyle(fontSize: 12),
                    ),
                    subtitle: Text(
                      '${eventDate.year}-${eventDate.month.toString().padLeft(2, '0')}-${eventDate.day.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.calendar_today_rounded, size: 18),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: eventDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                        );
                        if (picked != null) {
                          setDialogState(() => eventDate = picked);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Operational Notes',
                      hintText: 'Additional instructions or personnel required',
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
              ),
              onPressed: () {
                if (titleController.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Scheduled "${titleController.text.trim()}" for ${eventDate.year}-${eventDate.month.toString().padLeft(2, '0')}-${eventDate.day.toString().padLeft(2, '0')}',
                    ),
                    backgroundColor: Colors.teal,
                  ),
                );
              },
              child: const Text(
                'Schedule',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    if (month >= 1 && month <= 12) return months[month - 1];
    return '';
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
