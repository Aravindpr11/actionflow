// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/models/action_section.dart';
import 'package:action_flow/models/division.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/action_section_service.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:action_flow/services/company_structure_service.dart';
import 'package:action_flow/services/division_service.dart';
import 'package:action_flow/services/user_service.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/models/team.dart';
import 'package:action_flow/features/users/widgets/duplicate_person_dialog.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/external_recipient.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/services/app_file_picker_service.dart';

class AddActionScreen extends StatefulWidget {
  const AddActionScreen({
    super.key,
    required this.actionId,
    this.existingAction,
    this.managerContext,
    this.isEmbedded = false,
    this.isManager = true,
    this.isStaff = false,
    this.onClose,
    this.onSaved,
    this.organizationId,
    this.companyStructureService,
    this.divisionService,
    this.actionSectionService,
    this.userService,
  });

  final String actionId;
  final ActionRecord? existingAction;
  final ManagerContext? managerContext;
  final bool isEmbedded;
  final bool isManager;
  final bool isStaff;
  final VoidCallback? onClose;
  final ValueChanged<ActionRecord>? onSaved;
  final String? organizationId;
  final CompanyStructureService? companyStructureService;
  final DivisionService? divisionService;
  final ActionSectionService? actionSectionService;
  final UserService? userService;

  @override
  State<AddActionScreen> createState() => _AddActionScreenState();
}

class _AddActionScreenState extends State<AddActionScreen> {
  final _formKey = GlobalKey<FormState>();

  // What the action is
  final actionTitle = TextEditingController();
  final actionDescription = TextEditingController();

  // Where it belongs
  String division = '';
  String department = '';
  String section = '';
  String unit = '';
  String team = '';
  final locationSite = TextEditingController();

  String? _selectedDivisionId;
  String? _selectedDepartmentId;
  String? _selectedSectionId;
  String? _selectedSiteId;
  String? _selectedTeamId;

  List<Division> _availableDivisions = [];
  List<Map<String, dynamic>> _availableDepartments = [];
  List<ActionSection> _availableSections = [];
  List<Map<String, dynamic>> _availableSites = [];
  List<Map<String, dynamic>> _availableTeams = [];
  List<Person> _companyUsers = [];

  bool _isLoadingOrgData = false;
  String? _orgDataErrorMessage;

  CompanyStructureService get _structureService =>
      widget.companyStructureService ?? CompanyStructureService.instance;
  DivisionService get _divisionService =>
      widget.divisionService ?? DivisionService.instance;
  ActionSectionService get _sectionService =>
      widget.actionSectionService ?? ActionSectionService.instance;
  UserService get _userService =>
      widget.userService ?? UserService.instance;

  String get _effectiveOrgId {
    if (widget.organizationId != null && widget.organizationId!.isNotEmpty) {
      return widget.organizationId!;
    }
    if (widget.managerContext?.organizationId != null &&
        widget.managerContext!.organizationId.isNotEmpty) {
      return widget.managerContext!.organizationId;
    }
    if (widget.existingAction?.organizationId != null &&
        widget.existingAction!.organizationId.isNotEmpty) {
      return widget.existingAction!.organizationId;
    }
    final authOrg = AuthService.instance.currentOrganizationId;
    if (authOrg != null && authOrg.isNotEmpty) {
      return authOrg;
    }
    final profOrg = AuthService.instance.currentProfile?.organizationId;
    if (profOrg != null && profOrg.isNotEmpty) {
      return profOrg;
    }
    return '';
  }

  ManagerContext? _freshManagerContext;
  ManagerContext? get _effectiveManagerContext =>
      _freshManagerContext ?? widget.managerContext;

  bool get _isCompanyAdmin {
    if (AuthService.instance.currentProfileData?.isPrimaryAdmin == true) {
      return true;
    }
    final ctx = _effectiveManagerContext;
    if (ctx != null) {
      final role = ctx.profile.role.toLowerCase();
      return role == 'admin' ||
          role == 'company_admin' ||
          role == 'platform_admin';
    }
    final role = (AuthService.instance.currentProfile?.role ??
            AuthService.instance.currentProfileData?.roleCode ??
            '')
        .toLowerCase();
    return role == 'admin' ||
        role == 'company_admin' ||
        role == 'platform_admin';
  }

  bool get _isStaff {
    if (widget.isStaff) return true;
    if (!widget.isManager) return true;
    if (_isCompanyAdmin) return false;
    final role = (AuthService.instance.currentProfile?.role ??
            AuthService.instance.currentProfileData?.roleCode ??
            '')
        .toLowerCase();
    return role == 'staff' || role == 'worker';
  }

  bool get _hasManagerScopes {
    if (_isStaff) return false;
    final ctx = _effectiveManagerContext;
    return ctx != null && ctx.hasScopes && !_isCompanyAdmin;
  }

  List<Map<String, dynamic>> get _permittedDepartments {
    if (_isStaff) {
      final staffDeptId = AuthService.instance.currentProfile?.departmentId ??
          AuthService.instance.currentProfileData?.userProfile.departmentId ??
          '';
      final staffDeptName = AuthService.instance.currentProfile?.department ??
          AuthService.instance.currentProfileData?.userProfile.department ??
          '';
      return _availableDepartments.where((d) {
        final dId = d['id']?.toString() ?? '';
        final dName = d['name']?.toString().trim().toLowerCase() ?? '';
        final matchId = staffDeptId.isNotEmpty && dId == staffDeptId;
        final matchName = staffDeptName.isNotEmpty &&
            dName == staffDeptName.trim().toLowerCase();
        return matchId || matchName;
      }).toList();
    }
    if (!_hasManagerScopes) {
      return _availableDepartments;
    }
    final ctx = _effectiveManagerContext!;
    return _availableDepartments.where((d) {
      final dId = d['id']?.toString() ?? '';
      final dName = d['name']?.toString().trim().toLowerCase() ?? '';
      final matchId = ctx.scopedDepartmentIds.contains(dId);
      final matchName = ctx.scopedDepartmentNames
          .any((name) => name.trim().toLowerCase() == dName);
      return matchId || matchName;
    }).toList();
  }

  List<Map<String, dynamic>> get _permittedSites {
    if (_isStaff) {
      final staffSiteId = AuthService.instance.currentProfile?.siteId ??
          AuthService.instance.currentProfileData?.userProfile.siteId ??
          '';
      final staffSiteName = AuthService.instance.currentProfile?.site ??
          AuthService.instance.currentProfileData?.userProfile.site ??
          '';
      return _availableSites.where((s) {
        final sId = s['id']?.toString() ?? '';
        final sName = s['name']?.toString().trim().toLowerCase() ?? '';
        final matchId = staffSiteId.isNotEmpty && sId == staffSiteId;
        final matchName = staffSiteName.isNotEmpty &&
            sName == staffSiteName.trim().toLowerCase();
        return matchId || matchName;
      }).toList();
    }
    if (!_hasManagerScopes) {
      return _availableSites;
    }
    final ctx = _effectiveManagerContext!;
    if (_selectedDepartmentId == null) {
      final permittedSiteIds = ctx.scopedSiteIds;
      final permittedSiteNames = ctx.scopedSiteNames
          .map((s) => s.trim().toLowerCase())
          .where((n) => n.isNotEmpty)
          .toSet();
      if (permittedSiteIds.isEmpty && permittedSiteNames.isEmpty) {
        return _availableSites;
      }
      return _availableSites.where((s) {
        final sId = s['id']?.toString() ?? '';
        final sName = s['name']?.toString().trim().toLowerCase() ?? '';
        final matchId = permittedSiteIds.contains(sId);
        final matchName = permittedSiteNames.contains(sName);
        return matchId || matchName;
      }).toList();
    }
    final deptId = _selectedDepartmentId!;
    final permittedScopes = deptId.isNotEmpty ? ctx.scopesForDepartment(deptId) : <ManagerScopeItem>[];

    // If the manager has a department-wide scope (siteId is empty) for the selected department,
    // or if the manager has no site restrictions at all, all available sites are permitted.
    final hasUnrestrictedSiteScope = permittedScopes.any((s) => s.siteId.isEmpty);
    if (hasUnrestrictedSiteScope || (permittedScopes.isEmpty && ctx.scopedSiteIds.isEmpty)) {
      return _availableSites;
    }

    // Otherwise, restrict to sites specified in the manager's scopes for this department (or overall scoped sites)
    final permittedSiteIds = permittedScopes.isNotEmpty
        ? permittedScopes.map((s) => s.siteId).where((id) => id.isNotEmpty).toSet()
        : ctx.scopedSiteIds;
    final permittedSiteNames = permittedScopes.isNotEmpty
        ? ctx.permittedSiteNamesForDepartmentName(department).map((s) => s.trim().toLowerCase()).where((n) => n.isNotEmpty).toSet()
        : ctx.scopedSiteNames.map((s) => s.trim().toLowerCase()).where((n) => n.isNotEmpty).toSet();

    if (permittedSiteIds.isEmpty && permittedSiteNames.isEmpty) {
      return _availableSites;
    }

    return _availableSites.where((s) {
      final sId = s['id']?.toString() ?? '';
      final sName = s['name']?.toString().trim().toLowerCase() ?? '';
      final matchId = permittedSiteIds.contains(sId);
      final matchName = permittedSiteNames.contains(sName);
      return matchId || matchName;
    }).toList();
  }

  bool _isPersonEligibleForScope(
    Person person, {
    required String? deptId,
    required String deptName,
    required String? siteId,
    required String siteName,
  }) {
    if (!person.isActive || person.type != PersonType.internalUser) {
      return false;
    }

    // Operational Assignee Exclusion: Admin-role users are excluded from operational assignees
    final roleStr = person.role.toString().toLowerCase();
    final roleName = person.role.name.toLowerCase();
    final isPersonAdmin = roleStr.contains('admin') ||
        roleName.contains('admin') ||
        person.role == UserRole.admin ||
        person.designation.toLowerCase().contains('admin');
    if (isPersonAdmin) {
      return false;
    }

    if (_isStaff) {
      final currentUserId = (AuthService.instance.currentProfile?.id ??
              AuthService.instance.currentUser?.id ??
              '')
          .trim()
          .toLowerCase();
      // 1. Self assignment is always permitted
      if (currentUserId.isNotEmpty &&
          person.id.trim().toLowerCase() == currentUserId) {
        return true;
      }

      final staffDeptId = AuthService.instance.currentProfile?.departmentId ??
          AuthService.instance.currentProfileData?.userProfile.departmentId ??
          '';
      final staffDeptName = (AuthService.instance.currentProfile?.department ??
              AuthService.instance.currentProfileData?.userProfile.department ??
              '')
          .trim()
          .toLowerCase();

      final effectiveDeptId =
          (deptId != null && deptId.isNotEmpty) ? deptId : staffDeptId;
      final effectiveDeptName = deptName.isNotEmpty
          ? deptName.trim().toLowerCase()
          : staffDeptName;

      final pDeptId = person.departmentId ?? '';
      final pDeptName = person.department.trim().toLowerCase();

      final deptMatches = (effectiveDeptId.isNotEmpty &&
              pDeptId.isNotEmpty &&
              pDeptId == effectiveDeptId) ||
          (effectiveDeptName.isNotEmpty &&
              pDeptName.isNotEmpty &&
              pDeptName == effectiveDeptName);

      // 2. Active Staff in creator's department (cross-site within same department permitted)
      final isStaffRole = person.role == UserRole.actionOwnerWorker ||
          roleStr.contains('staff') ||
          roleStr.contains('worker') ||
          roleName.contains('staff') ||
          roleName.contains('worker');

      if (isStaffRole && deptMatches) {
        return true;
      }

      // 3. Active Manager in creator's department
      final isManagerRole = person.role == UserRole.departmentManager ||
          roleStr.contains('manager') ||
          roleName.contains('manager') ||
          person.designation.toLowerCase().contains('manager');

      if (isManagerRole) {
        if (deptMatches) return true;
        if (person.managerScopes.isNotEmpty) {
          final hasScopeInDept = person.managerScopes.any((s) {
            final matchId =
                effectiveDeptId.isNotEmpty && s.departmentId == effectiveDeptId;
            final matchName = effectiveDeptName.isNotEmpty &&
                s.departmentName.trim().toLowerCase() == effectiveDeptName;
            return matchId || matchName;
          });
          if (hasScopeInDept) return true;
        }
      }

      return false;
    }

    // Admins and unrestricted managers have company-wide authority to assign across all departments
    if (!_hasManagerScopes) {
      return true;
    }

    if (person.managerScopes.isNotEmpty) {
      final hasMatchingScope = person.managerScopes.any((s) {
        final deptMatch = (deptId != null &&
                deptId.isNotEmpty &&
                s.departmentId == deptId) ||
            (deptName.isNotEmpty &&
                s.departmentName.trim().toLowerCase() ==
                    deptName.trim().toLowerCase());
        final siteMatch = (siteId != null &&
                siteId.isNotEmpty &&
                s.siteId == siteId) ||
            (siteName.isNotEmpty &&
                s.siteName.trim().toLowerCase() ==
                    siteName.trim().toLowerCase()) ||
            s.siteId.isEmpty ||
            s.siteName.isEmpty;
        return deptMatch && siteMatch;
      });
      if (hasMatchingScope) return true;
    }

    final pDeptId = person.departmentId;
    final pDeptName = person.department.trim().toLowerCase();
    final reqDeptName = deptName.trim().toLowerCase();

    bool deptMatches = false;
    if (deptId != null &&
        deptId.isNotEmpty &&
        pDeptId != null &&
        pDeptId.isNotEmpty) {
      deptMatches = (pDeptId == deptId);
    }
    if (!deptMatches && reqDeptName.isNotEmpty && pDeptName.isNotEmpty) {
      deptMatches = (pDeptName == reqDeptName);
    }
    if (!deptMatches && pDeptName.isNotEmpty) {
      return false;
    }

    if (siteName == 'All Sites / Locations' || siteName.isEmpty) {
      return true;
    }

    final pSiteId = person.siteId;
    final pSiteName = person.site.trim().toLowerCase();
    final reqSiteName = siteName.trim().toLowerCase();

    if (pSiteId != null &&
        pSiteId.isNotEmpty &&
        siteId != null &&
        siteId.isNotEmpty) {
      if (pSiteId != siteId) {
        return false;
      }
    } else if (pSiteName.isNotEmpty && reqSiteName.isNotEmpty) {
      if (pSiteName != reqSiteName) {
        return false;
      }
    }

    return true;
  }

  List<Person> get _eligibleInternalAssignees {
    final all = _companyUsers.isNotEmpty
        ? _companyUsers
        : MockPeopleStore.instance.people;
    return all
        .where(
          (p) => _isPersonEligibleForScope(
            p,
            deptId: _selectedDepartmentId,
            deptName: department,
            siteId: _selectedSiteId,
            siteName: locationSite.text,
          ),
        )
        .toList();
  }

  void _revalidateAssigneesOnScopeChange() {
    if (internalPrimary != null) {
      final isStillEligible = _eligibleInternalAssignees.any(
        (p) =>
            p.id == internalPrimary!.personId ||
            (p.email.isNotEmpty &&
                p.email.toLowerCase() == internalPrimary!.email.toLowerCase()) ||
            p.name.toLowerCase() == internalPrimary!.name.toLowerCase(),
      );
      if (!isStillEligible) {
        setState(() {
          internalPrimary = null;
          assignedTo = 'Select worker';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Primary assignee cleared: not eligible for the selected Department and Site scope.',
              ),
              backgroundColor: Color(0xFFF59E0B),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }

    // NOTE: additionalInternalPeople are cross-department and cross-site assignees
    // and are preserved when changing discovery or ownership scope.
  }

  // Assignment - Internal
  ActionPersonReference? internalPrimary;
  final List<ActionPersonReference> additionalInternalPeople = [];
  final internalSearchController = TextEditingController();

  // Assignment - External
  ActionPersonReference? externalPrimary;
  final List<ActionPersonReference> additionalExternalPeople = [];
  final externalSearchController = TextEditingController();
  final externalName = TextEditingController();
  final externalEmail = TextEditingController();
  final externalPhone = TextEditingController();
  final externalCompany = TextEditingController();
  final externalDesignation = TextEditingController();
  final externalSite = TextEditingController();

  // Legacy assignedTo for compatibility
  String assignedTo = 'Select worker';
  String recipientType = 'internal';
  ExternalRecipient? _selectedExternalRecipient;
  final List<ActionSubTask> _tasks = [];
  final List<String> _attachments = [];
  final List<String> _removedAttachments = [];
  final List<AppPickedFile> _pendingPickedFiles = [];
  ActionRecord? _createdActionRecord;

  // Priority & Status
  String priority = 'Medium';
  String status = 'Open';
  int percent = 0;
  bool _isPercentManuallyModified = false;
  bool _isSubmitting = false;

  // Dates
  String raiseDate = '01 Jan 2026';
  String targetDate = '15 Jan 2026';
  String followUpDate = '';
  String closeDate = '';

  // Email Reminder
  bool emailReminderEnabled = false;
  final List<ActionEmailReminder> emailReminders = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    raiseDate = _formatDate(now);
    targetDate = _formatDate(now.add(const Duration(days: 14)));

    final existing = widget.existingAction;
    if (existing != null) {
      actionTitle.text = existing.subject;
      actionDescription.text = existing.actionRequired.isNotEmpty
          ? existing.actionRequired
          : existing.description;
      division = existing.division;
      _selectedDivisionId = existing.divisionId;
      department = existing.department;
      _selectedDepartmentId = existing.departmentId;
      section = existing.section;
      _selectedSectionId = existing.sectionId;
      locationSite.text = existing.site;
      _selectedSiteId = existing.siteId;
      _selectedTeamId = existing.teamId;
      team = '';
      unit = '';
      priority = existing.priority.isNotEmpty ? existing.priority : 'Medium';
      status = existing.status.isNotEmpty ? existing.status : 'Open';
      percent = existing.percentComplete;
      if (existing.subTasks.isNotEmpty) {
        final taskRatio = ((existing.subTasks.where((t) => t.isCompleted).length /
                    existing.subTasks.length) *
                100)
            .round();
        if (existing.percentComplete != taskRatio) {
          _isPercentManuallyModified = true;
        }
      }
      if (existing.dateRaised.isNotEmpty) raiseDate = existing.dateRaised;
      if (existing.targetDate.isNotEmpty) targetDate = existing.targetDate;
      followUpDate = existing.nextFollowUpDate.isNotEmpty
          ? existing.nextFollowUpDate
          : existing.lastFollowUpDate;
      closeDate = existing.closeDate;
      recipientType = existing.recipientType.toLowerCase() == 'external' ? 'external' : 'internal';
      if (recipientType == 'internal') {
        internalPrimary = existing.primaryAssignee;
        if (internalPrimary == null && existing.assignedTo.isNotEmpty && existing.assignedTo != 'Select worker') {
          internalPrimary = ActionPersonReference(
            personId: existing.assignedToId ?? '00000000-0000-0000-0000-000000000001',
            name: existing.assignedTo,
            type: PersonType.internalUser,
          );
        }
        additionalInternalPeople.addAll(
          existing.additionalPeople.where((p) => p.type == PersonType.internalUser),
        );
      } else {
        externalPrimary = existing.primaryAssignee;
        if (externalPrimary != null) {
          externalName.text = externalPrimary!.name;
          externalEmail.text = externalPrimary!.email;
          externalPhone.text = externalPrimary!.phone;
          externalCompany.text = externalPrimary!.company;
          externalDesignation.text = externalPrimary!.designation;
          externalSite.text = externalPrimary!.site;
        } else if (existing.externalRecipient != null) {
          final rec = existing.externalRecipient!;
          externalName.text = rec.fullName;
          externalEmail.text = rec.email;
          externalPhone.text = rec.phone;
          externalCompany.text = rec.companyName;
        }
        additionalExternalPeople.addAll(
          existing.additionalPeople.where((p) => p.type == PersonType.externalWorker),
        );
      }
      _tasks.addAll(existing.subTasks);
      _attachments.addAll(existing.attachments);
      emailReminderEnabled = existing.emailReminderEnabled;
      emailReminders.addAll(existing.emailReminders);
      _selectedDepartmentId = existing.departmentId;
      _selectedSiteId = existing.siteId;
    }

    final ctx = widget.managerContext;
    if (ctx != null) {
      final firstScope = ctx.scopes.isNotEmpty ? ctx.scopes.first : null;
      _selectedDepartmentId ??= firstScope?.departmentId;
      _selectedSiteId ??= firstScope?.siteId;
      if (department.isEmpty && firstScope?.departmentName.isNotEmpty == true) {
        department = firstScope!.departmentName;
      }
      if (locationSite.text.isEmpty && firstScope?.siteName.isNotEmpty == true) {
        locationSite.text = firstScope!.siteName;
      }
    } else {
      final profileData = AuthService.instance.currentProfileData;
      if (profileData != null) {
        if (department.isEmpty && profileData.userProfile.department.isNotEmpty) {
          department = profileData.userProfile.department;
        }
        _selectedDepartmentId ??= profileData.userProfile.departmentId;
        if (locationSite.text.isEmpty && profileData.userProfile.site.isNotEmpty) {
          locationSite.text = profileData.userProfile.site;
        }
        _selectedSiteId ??= profileData.userProfile.siteId;
      }
    }

    _loadOrganizationalData();
  }

  Future<void> _loadOrganizationalData() async {
    final orgId = _effectiveOrgId;
    if (orgId.isEmpty) {
      return;
    }

    setState(() {
      _isLoadingOrgData = true;
      _orgDataErrorMessage = null;
    });

    // Refresh manager context and scopes if user is authenticated
    final currentAuthId = SupabaseConfig.clientOrNull?.auth.currentUser?.id;
    if (currentAuthId != null && currentAuthId.isNotEmpty) {
      try {
        final freshCtx = await AuthService.instance.fetchManagerContext(currentAuthId);
        if (freshCtx != null) {
          _freshManagerContext = freshCtx;
        }
      } catch (e) {
        debugPrint('[AddAction] fetchManagerContext refresh note: $e');
      }
    }

    try {
      _userService.invalidateCache();
      final results = await Future.wait([
        _divisionService.fetchDivisions(orgId, onlyActive: true),
        _structureService.fetchDepartments(orgId),
        _sectionService.fetchSections(orgId, onlyActive: true),
        _structureService.fetchSites(orgId),
        _structureService.fetchTeams(orgId),
        _userService.fetchUsers(orgId).catchError((e) {
          debugPrint('UserService fetchUsers note: $e');
          return MockPeopleStore.instance.people;
        }),
      ]);

      if (!mounted) return;

      final divs = results[0] as List<Division>;
      final rawDepts = results[1] as List<Map<String, dynamic>>;
      final secs = results[2] as List<ActionSection>;
      final rawSites = results[3] as List<Map<String, dynamic>>;
      final rawTeams = results[4] as List<Map<String, dynamic>>;
      final users = results[5] as List<Person>;

      bool isEntityActive(Map<String, dynamic> item) {
        if (item['is_active'] == false || item['status']?.toString().toLowerCase() == 'inactive') {
          return false;
        }
        if (item['raw'] is Map) {
          final raw = item['raw'] as Map;
          if (raw['is_active'] == false || raw['status']?.toString().toLowerCase() == 'inactive') {
            return false;
          }
        }
        return item['status']?.toString().toLowerCase() == 'active' ||
            item['is_active'] == true ||
            (item['raw'] is Map &&
                (item['raw']['is_active'] == true || item['raw']['status']?.toString().toLowerCase() == 'active'));
      }

      final activeDepts = rawDepts.where(isEntityActive).toList();
      final activeSites = rawSites.where(isEntityActive).toList();
      final activeTeams = rawTeams.where(isEntityActive).toList();

      // Dynamically resolve and merge Department Manager for Staff's department
      if (_isStaff) {
        final staffDeptId = AuthService.instance.currentProfile?.departmentId ??
            AuthService.instance.currentProfileData?.userProfile.departmentId ??
            '';
        if (staffDeptId.isNotEmpty) {
          try {
            final mgrs = await _userService.fetchDepartmentManagers(
              departmentId: staffDeptId,
              organizationId: orgId,
            );
            if (mgrs.isNotEmpty) {
              for (final mgr in mgrs) {
                final existingIdx = users.indexWhere((u) => u.id == mgr.id);
                final hydratedMgr = mgr.copyWith(
                  department: department.isNotEmpty ? department : mgr.department,
                  departmentId: mgr.departmentId ?? staffDeptId,
                  managerScopes: [
                    ...mgr.managerScopes,
                    if (mgr.managerScopes.every((s) => s.departmentId != staffDeptId))
                      ManagerScopeItem(
                        departmentId: staffDeptId,
                        departmentName: department,
                        siteId: '',
                        siteName: '',
                      ),
                  ],
                );
                if (existingIdx == -1) {
                  users.add(hydratedMgr);
                } else {
                  final existing = users[existingIdx];
                  users[existingIdx] = existing.copyWith(
                    role: UserRole.departmentManager,
                    departmentId: existing.departmentId ?? staffDeptId,
                    department: existing.department.isNotEmpty ? existing.department : department,
                    managerScopes: [
                      ...existing.managerScopes,
                      if (existing.managerScopes.every((s) => s.departmentId != staffDeptId))
                        ManagerScopeItem(
                          departmentId: staffDeptId,
                          departmentName: department,
                          siteId: '',
                          siteName: '',
                        ),
                    ],
                  );
                }
              }
            }
          } catch (e) {
            debugPrint('[AddActionScreen] Note fetching department managers: $e');
          }
        }
      }

      // Historical Inactive Team Preservation for Existing Action:
      // Allow the currently assigned inactive team to remain visible and preserved with an (Inactive) label.
      // Inactive teams are never offered as new assignments.
      final existingTeamId = widget.existingAction?.teamId;
      if (existingTeamId != null && existingTeamId.isNotEmpty) {
        final alreadyInActive = activeTeams.any((t) => t['id']?.toString() == existingTeamId);
        if (!alreadyInActive) {
          final rawMatch = rawTeams.firstWhereOrNull((t) => t['id']?.toString() == existingTeamId);
          if (rawMatch != null) {
            final rawName = rawMatch['name']?.toString() ?? 'Team';
            final displayName = rawName.contains('(Inactive)') ? rawName : '$rawName (Inactive)';
            activeTeams.add({
              ...rawMatch,
              'name': displayName,
              'original_name': rawName,
              'is_active': false,
              'is_historical_inactive': true,
            });
          } else {
            activeTeams.add({
              'id': existingTeamId,
              'name': 'Assigned Team (Inactive)',
              'original_name': 'Assigned Team',
              'department_id': widget.existingAction?.departmentId,
              'deptId': widget.existingAction?.departmentId,
              'is_active': false,
              'is_historical_inactive': true,
            });
          }
        }
      }

      setState(() {
        _availableDivisions = divs;
        _availableDepartments = activeDepts;
        _availableSections = secs;
        _availableSites = activeSites;
        _availableTeams = activeTeams;
        _companyUsers = users;
        _isLoadingOrgData = false;

        _syncInitialOrExistingSelections();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingOrgData = false;
        _orgDataErrorMessage = 'Failed to load organizational configuration: $e';
      });
    }
  }

  void _syncInitialOrExistingSelections() {
    final existing = widget.existingAction;
    if (existing != null) {
      if (existing.divisionId != null && existing.divisionId!.isNotEmpty) {
        final match = _availableDivisions.firstWhereOrNull((d) => d.id == existing.divisionId);
        division = match?.name ?? existing.division;
        _selectedDivisionId = match?.id ?? existing.divisionId;
      } else if (existing.division.isNotEmpty) {
        final match = _availableDivisions.firstWhereOrNull((d) => d.name.toLowerCase() == existing.division.toLowerCase());
        division = match?.name ?? existing.division;
        _selectedDivisionId = match?.id;
      }

      if (existing.departmentId.isNotEmpty) {
        final match = _availableDepartments.firstWhereOrNull((d) => d['id'] == existing.departmentId);
        department = match?['name']?.toString() ?? existing.department;
        _selectedDepartmentId = match?['id']?.toString() ?? existing.departmentId;
      } else if (existing.department.isNotEmpty) {
        final match = _availableDepartments.firstWhereOrNull((d) => d['name']?.toString().toLowerCase() == existing.department.toLowerCase());
        department = match?['name']?.toString() ?? existing.department;
        _selectedDepartmentId = match?['id']?.toString();
      }

      if (existing.sectionId != null && existing.sectionId!.isNotEmpty) {
        final match = _availableSections.firstWhereOrNull((s) => s.id == existing.sectionId);
        section = match?.name ?? existing.section;
        _selectedSectionId = match?.id ?? existing.sectionId;
      } else if (existing.section.isNotEmpty) {
        final match = _availableSections.firstWhereOrNull((s) => s.name.toLowerCase() == existing.section.toLowerCase());
        section = match?.name ?? existing.section;
        _selectedSectionId = match?.id;
      }

      if (existing.siteId.isNotEmpty) {
        final match = _availableSites.firstWhereOrNull((s) => s['id'] == existing.siteId);
        final sName = match?['name']?.toString() ?? existing.site;
        locationSite.text = sName;
        _selectedSiteId = match?['id']?.toString() ?? existing.siteId;
      } else if (existing.site.isNotEmpty) {
        final match = _availableSites.firstWhereOrNull((s) => s['name']?.toString().toLowerCase() == existing.site.toLowerCase());
        locationSite.text = match?['name']?.toString() ?? existing.site;
        _selectedSiteId = match?['id']?.toString();
      }

      if (existing.teamId != null && existing.teamId!.isNotEmpty) {
        final match = _availableTeams.firstWhereOrNull((t) => t['id']?.toString() == existing.teamId);
        if (match != null) {
          team = match['name']?.toString() ?? '';
          unit = team;
          _selectedTeamId = match['id']?.toString() ?? existing.teamId;
        } else {
          const fallbackName = 'Assigned Team (Inactive)';
          team = fallbackName;
          unit = fallbackName;
          _selectedTeamId = existing.teamId;
          _availableTeams.add({
            'id': existing.teamId,
            'name': fallbackName,
            'original_name': 'Assigned Team',
            'department_id': existing.departmentId,
            'deptId': existing.departmentId,
            'is_active': false,
            'is_historical_inactive': true,
          });
        }
      }
      return;
    }

    if (_isStaff) {
      final staffDeptId = AuthService.instance.currentProfile?.departmentId ??
          AuthService.instance.currentProfileData?.userProfile.departmentId ??
          '';
      final staffDeptName = AuthService.instance.currentProfile?.department ??
          AuthService.instance.currentProfileData?.userProfile.department ??
          '';
      final staffSiteId = AuthService.instance.currentProfile?.siteId ??
          AuthService.instance.currentProfileData?.userProfile.siteId ??
          '';
      final staffSiteName = AuthService.instance.currentProfile?.site ??
          AuthService.instance.currentProfileData?.userProfile.site ??
          '';

      final matchDept = _availableDepartments.firstWhereOrNull(
        (d) =>
            (staffDeptId.isNotEmpty && d['id']?.toString() == staffDeptId) ||
            (staffDeptName.isNotEmpty &&
                d['name']?.toString().toLowerCase() ==
                    staffDeptName.toLowerCase()),
      );
      if (matchDept != null) {
        department = matchDept['name']?.toString() ?? staffDeptName;
        _selectedDepartmentId = matchDept['id']?.toString() ?? staffDeptId;

        final deptDiv =
            (matchDept['division'] ?? matchDept['raw']?['division'])?.toString();
        if (deptDiv != null && deptDiv.isNotEmpty) {
          final matchDiv = _availableDivisions.firstWhereOrNull(
            (div) => div.name.toLowerCase() == deptDiv.toLowerCase(),
          );
          if (matchDiv != null) {
            division = matchDiv.name;
            _selectedDivisionId = matchDiv.id;
          }
        }
      } else {
        if (staffDeptName.isNotEmpty) department = staffDeptName;
        if (staffDeptId.isNotEmpty) _selectedDepartmentId = staffDeptId;
      }

      final matchSite = _availableSites.firstWhereOrNull(
        (s) =>
            (staffSiteId.isNotEmpty && s['id']?.toString() == staffSiteId) ||
            (staffSiteName.isNotEmpty &&
                s['name']?.toString().toLowerCase() ==
                    staffSiteName.toLowerCase()),
      );
      if (matchSite != null) {
        locationSite.text = matchSite['name']?.toString() ?? staffSiteName;
        _selectedSiteId = matchSite['id']?.toString() ?? staffSiteId;
      } else {
        if (staffSiteName.isNotEmpty) locationSite.text = staffSiteName;
        if (staffSiteId.isNotEmpty) _selectedSiteId = staffSiteId;
      }
      return;
    }

    if (_hasManagerScopes) {
      final firstScope = widget.managerContext!.scopes.first;
      final matchDept = _availableDepartments.firstWhereOrNull(
        (d) => d['id'] == firstScope.departmentId || d['name']?.toString().toLowerCase() == firstScope.departmentName.toLowerCase(),
      );
      if (matchDept != null) {
        department = matchDept['name']?.toString() ?? firstScope.departmentName;
        _selectedDepartmentId = matchDept['id']?.toString() ?? firstScope.departmentId;

        final deptDiv = (matchDept['division'] ?? matchDept['raw']?['division'])?.toString();
        if (deptDiv != null && deptDiv.isNotEmpty) {
          final matchDiv = _availableDivisions.firstWhereOrNull(
            (div) => div.name.toLowerCase() == deptDiv.toLowerCase(),
          );
          if (matchDiv != null) {
            division = matchDiv.name;
            _selectedDivisionId = matchDiv.id;
          }
        }
      }

      final permittedSites = _permittedSites;
      final matchSite = permittedSites.firstWhereOrNull(
        (s) => s['id'] == firstScope.siteId || s['name']?.toString().toLowerCase() == firstScope.siteName.toLowerCase(),
      );
      if (matchSite != null) {
        locationSite.text = matchSite['name']?.toString() ?? firstScope.siteName;
        _selectedSiteId = matchSite['id']?.toString() ?? firstScope.siteId;
      } else if (permittedSites.isNotEmpty) {
        locationSite.text = permittedSites.first['name']?.toString() ?? '';
        _selectedSiteId = permittedSites.first['id']?.toString();
      }
    } else {
      final validDepts = _permittedDepartments;
      if (department.isEmpty && validDepts.isNotEmpty) {
        department = validDepts.first['name']?.toString() ?? '';
        _selectedDepartmentId = validDepts.first['id']?.toString();

        final deptDiv = (validDepts.first['division'] ?? validDepts.first['raw']?['division'])?.toString();
        if (deptDiv != null && deptDiv.isNotEmpty) {
          final matchDiv = _availableDivisions.firstWhereOrNull(
            (div) => div.name.toLowerCase() == deptDiv.toLowerCase(),
          );
          if (matchDiv != null) {
            division = matchDiv.name;
            _selectedDivisionId = matchDiv.id;
          }
        }
      }

      final validSites = _permittedSites;
      if (locationSite.text.isEmpty && validSites.isNotEmpty) {
        locationSite.text = validSites.first['name']?.toString() ?? '';
        _selectedSiteId = validSites.first['id']?.toString();
      }
    }

    // Section, division, and unit remain optional for new actions unless explicitly chosen
  }

  List<Map<String, dynamic>> get _filteredTeams {
    final deptId = _selectedDepartmentId;
    final deptName = department.trim().toLowerCase();
    if (deptId == null || deptId.isEmpty) {
      if (deptName.isEmpty) return [];
      final matchDept = _availableDepartments.firstWhereOrNull(
        (d) => d['name']?.toString().trim().toLowerCase() == deptName,
      );
      final dId = matchDept?['id']?.toString();
      if (dId == null || dId.isEmpty) return [];
      return _availableTeams.where((t) {
        final tDeptId = (t['deptId'] ?? t['department_id'] ?? t['raw']?['department_id'])?.toString();
        final tDeptName = t['dept']?.toString().trim().toLowerCase() ?? '';
        return tDeptId == dId || (tDeptName.isNotEmpty && tDeptName == deptName);
      }).toList();
    }
    return _availableTeams.where((t) {
      final tDeptId = (t['deptId'] ?? t['department_id'] ?? t['raw']?['department_id'])?.toString();
      final tDeptName = t['dept']?.toString().trim().toLowerCase() ?? '';
      return tDeptId == deptId || (deptName.isNotEmpty && tDeptName.isNotEmpty && tDeptName == deptName);
    }).toList();
  }

  void _onDepartmentChanged(String? newDept) {
    if (newDept == null || newDept == department) return;
    setState(() {
      department = newDept;
      final matchedDept = _availableDepartments.firstWhereOrNull((d) => d['name'] == newDept);
      _selectedDepartmentId = matchedDept?['id']?.toString();

      // Automatically sync division if department defines one
      final deptDiv = (matchedDept?['division'] ?? matchedDept?['raw']?['division'])?.toString();
      if (deptDiv != null && deptDiv.isNotEmpty) {
        final matchDiv = _availableDivisions.firstWhereOrNull(
          (div) => div.name.toLowerCase() == deptDiv.toLowerCase(),
        );
        if (matchDiv != null) {
          division = matchDiv.name;
          _selectedDivisionId = matchDiv.id;
        }
      }

      // Check if current site is permitted for this new department
      final validSites = _permittedSites;
      final validSiteNames = validSites.map((s) => s['name']?.toString() ?? '').where((s) => s.isNotEmpty).toSet();
      if (!validSiteNames.contains(locationSite.text)) {
        if (validSites.isNotEmpty) {
          locationSite.text = validSites.first['name']?.toString() ?? '';
          _selectedSiteId = validSites.first['id']?.toString();
        } else {
          locationSite.text = '';
          _selectedSiteId = null;
        }
      }

      _syncTeamForDepartment();
      _revalidateAssigneesOnScopeChange();
    });
  }

  void _syncTeamForDepartment() {
    final validTeams = _filteredTeams;
    if (!validTeams.any((t) => t['name'] == team || (t['id'] != null && t['id']?.toString() == _selectedTeamId))) {
      team = '';
      unit = '';
      _selectedTeamId = null;
    }
  }

  void _onSectionChanged(String? newSec) {
    if (newSec == null || newSec == section) return;
    setState(() {
      if (newSec == 'None' || newSec.isEmpty) {
        section = '';
        _selectedSectionId = null;
      } else {
        section = newSec;
        final matchedSec = _availableSections.firstWhereOrNull((s) => s.name == newSec);
        _selectedSectionId = matchedSec?.id;
      }
    });
  }

  void _onTeamChanged(String? newTeam) {
    if (newTeam == null || newTeam == team) return;
    setState(() {
      if (newTeam == 'None' || newTeam.isEmpty) {
        team = '';
        unit = '';
        _selectedTeamId = null;
      } else {
        team = newTeam;
        unit = newTeam;
        final matchedTeam = _filteredTeams.firstWhereOrNull((t) => t['name'] == newTeam);
        _selectedTeamId = matchedTeam?['id']?.toString();
      }
    });
  }

  void _onSiteChanged(String? newSite) {
    if (newSite == null || newSite == locationSite.text) return;
    setState(() {
      locationSite.text = newSite;
      final matchedSite = _availableSites.firstWhereOrNull((s) => s['name'] == newSite);
      _selectedSiteId = matchedSite?['id']?.toString();

      _revalidateAssigneesOnScopeChange();
    });
  }

  @override
  void dispose() {
    actionTitle.dispose();
    actionDescription.dispose();
    locationSite.dispose();
    internalSearchController.dispose();
    externalSearchController.dispose();
    externalName.dispose();
    externalEmail.dispose();
    externalPhone.dispose();
    externalCompany.dispose();
    externalDesignation.dispose();
    externalSite.dispose();
    super.dispose();
  }

  // ============================================================================
  // HELPERS
  // ============================================================================

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static bool _isValidUuid(String? val) {
    if (val == null) return false;
    return _uuidRegex.hasMatch(val.trim());
  }

  static String _month(int m) {
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
    if (m >= 1 && m <= 12) return months[m - 1];
    return 'Jan';
  }

  static int _monthIndex(String name) {
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
    final idx = months.indexWhere((m) => m.toLowerCase() == name.toLowerCase());
    return idx != -1 ? idx + 1 : 0;
  }

  static String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = _month(dt.month);
    return '$d $m ${dt.year}';
  }

  static DateTime? _parseDate(String dateStr) {
    if (dateStr.trim().isEmpty) return null;
    try {
      final parts = dateStr.trim().split(' ');
      if (parts.length < 3) return null;
      final day = int.parse(parts[0]);
      final month = _monthIndex(parts[1]);
      final year = int.parse(parts[2]);
      if (month == 0) return null;
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  static bool _isDateAfter(String dateA, String dateB) {
    final da = _parseDate(dateA);
    final db = _parseDate(dateB);
    if (da == null || db == null) return false;
    return da.isAfter(db);
  }

  Future<void> chooseDate(ValueChanged<String> onSelected) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      onSelected(_formatDate(picked));
    }
  }

  Future<void> chooseTime(ValueChanged<String> onSelected) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) {
      final hour = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
      final minute = picked.minute.toString().padLeft(2, '0');
      final period = picked.period == DayPeriod.am ? 'AM' : 'PM';
      onSelected('${hour.toString().padLeft(2, '0')}:$minute $period');
    }
  }

  ActionEmailReminder _createDefaultReminder() {
    return ActionEmailReminder(
      id: 'REM-${DateTime.now().millisecondsSinceEpoch}',
      date: targetDate.isNotEmpty ? targetDate : raiseDate,
      time: '09:00 AM',
      recipients: const [],
    );
  }

  List<ActionPersonReference> _getAssignedPeople() {
    final list = <ActionPersonReference>[];
    final seen = <String>{};

    void addRef(ActionPersonReference? ref) {
      if (ref == null) return;
      final key = ref.personId.isNotEmpty
          ? ref.personId
          : ref.name.toLowerCase();
      if (!seen.contains(key)) {
        seen.add(key);
        list.add(ref);
      }
    }

    addRef(internalPrimary);
    for (final p in additionalInternalPeople) {
      addRef(p);
    }
    if (externalPrimary != null) {
      addRef(externalPrimary);
    } else if (externalName.text.trim().isNotEmpty) {
      addRef(
        ActionPersonReference(
          personId: '',
          name: externalName.text.trim(),
          type: PersonType.externalWorker,
          email: externalEmail.text.trim(),
          phone: externalPhone.text.trim(),
          company: externalCompany.text.trim(),
          designation: externalDesignation.text.trim(),
          site: externalSite.text.trim(),
        ),
      );
    }
    for (final p in additionalExternalPeople) {
      addRef(p);
    }
    return list;
  }

  void _syncReminderRecipients() {
    final currentAssigned = _getAssignedPeople();
    final validIds = currentAssigned
        .map((p) => p.personId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final validNames = currentAssigned.map((p) => p.name.toLowerCase()).toSet();

    for (int i = 0; i < emailReminders.length; i++) {
      final r = emailReminders[i];
      final filteredRecipients = r.recipients.where((recip) {
        if (recip.personId.isNotEmpty) {
          return validIds.contains(recip.personId);
        }
        return validNames.contains(recip.name.toLowerCase());
      }).toList();

      emailReminders[i] = r.copyWith(recipients: filteredRecipients);
    }
  }

  ActionPersonReference _reference(Person person) {
    return ActionPersonReference(
      personId: person.id,
      name: person.name,
      type: person.type,
      email: person.email,
      phone: person.phone,
      company: person.company,
      designation: person.designation,
      department: person.department,
      site: person.site,
    );
  }

  Future<void> _saveAction() async {
    if (_isSubmitting) return;

    if (widget.existingAction?.isClosed == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Closed actions are locked for audit compliance and cannot be edited directly. Please use the authorized Reopen Action workflow.',
          ),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all required fields correctly.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    if (recipientType == 'internal' && internalPrimary == null) {
      if (assignedTo.isNotEmpty && assignedTo != 'Select worker') {
        internalPrimary = ActionPersonReference(
          personId: '00000000-0000-0000-0000-000000000001',
          name: assignedTo,
          type: PersonType.internalUser,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please assign at least one internal person.'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
        return;
      }
    }

    if (recipientType == 'external' &&
        externalPrimary == null &&
        externalName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide external recipient details.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    for (int i = 0; i < _tasks.length; i++) {
      if (_tasks[i].title.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Task #${i + 1} requires a title. Please provide a title or remove the task.',
            ),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
        return;
      }
    }

    if (emailReminderEnabled && closeDate.isNotEmpty) {
      for (final r in emailReminders) {
        if (r.date.isNotEmpty && _isDateAfter(r.date, closeDate)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Reminder date (${r.date}) cannot be after Close Date ($closeDate).',
              ),
              backgroundColor: const Color(0xFFDC2626),
            ),
          );
          return;
        }
      }
    }

    final isActionClosed = status == 'Closed' || (closeDate.isNotEmpty && percent == 100);
    final String effectiveCloseDate = isActionClosed
        ? (closeDate.isNotEmpty ? closeDate : _formatDate(DateTime.now()))
        : '';

    final effectiveReminders = emailReminderEnabled
        ? (isActionClosed
              ? emailReminders.map((r) => r.copyWith(isEnabled: false)).toList()
              : emailReminders)
        : <ActionEmailReminder>[];

    final primaryExternalRef = externalPrimary ??
        (externalName.text.trim().isNotEmpty
            ? ActionPersonReference(
                personId: _selectedExternalRecipient?.id ?? '',
                name: externalName.text.trim(),
                type: PersonType.externalWorker,
                email: externalEmail.text.trim(),
                phone: externalPhone.text.trim(),
                company: externalCompany.text.trim(),
                designation: externalDesignation.text.trim(),
                site: externalSite.text.trim(),
              )
            : null);

    final assignedToName = recipientType == 'internal'
        ? (internalPrimary?.name ?? 'Unassigned')
        : (primaryExternalRef?.name ?? externalName.text.trim());

    final actualActionId = _createdActionRecord?.id ??
        (widget.existingAction != null
            ? widget.existingAction!.id
            : ((widget.actionId == 'AUTO' || widget.actionId.isEmpty)
                ? 'AC-${DateTime.now().millisecondsSinceEpoch % 10000}'
                : widget.actionId));

    final int effectivePercent = (_isPercentManuallyModified || _tasks.isEmpty)
        ? percent.clamp(0, 100)
        : ((_tasks.where((t) => t.isCompleted).length / _tasks.length) * 100).round();

    if ((_selectedDepartmentId == null || _selectedDepartmentId!.isEmpty) && department.isNotEmpty) {
      _selectedDepartmentId = _availableDepartments.firstWhereOrNull(
        (d) => d['name']?.toString().trim().toLowerCase() == department.trim().toLowerCase(),
      )?['id']?.toString();
    }
    if ((_selectedSiteId == null || _selectedSiteId!.isEmpty) && locationSite.text.trim().isNotEmpty) {
      _selectedSiteId = _availableSites.firstWhereOrNull(
        (s) => s['name']?.toString().trim().toLowerCase() == locationSite.text.trim().toLowerCase(),
      )?['id']?.toString();
    }
    if ((_selectedSectionId == null || _selectedSectionId!.isEmpty) && section.isNotEmpty) {
      _selectedSectionId = _availableSections.firstWhereOrNull(
        (s) => s.name.trim().toLowerCase() == section.trim().toLowerCase(),
      )?.id;
    }
    if ((_selectedTeamId == null || _selectedTeamId!.isEmpty) && team.isNotEmpty) {
      _selectedTeamId = _filteredTeams.firstWhereOrNull(
        (t) => t['name']?.toString().trim().toLowerCase() == team.trim().toLowerCase(),
      )?['id']?.toString();
    }
    if ((_selectedTeamId == null || _selectedTeamId!.isEmpty) && unit.isNotEmpty) {
      _selectedTeamId = _filteredTeams.firstWhereOrNull(
        (t) => t['name']?.toString().trim().toLowerCase() == unit.trim().toLowerCase(),
      )?['id']?.toString();
    }

    // Safety guard: Ensure selected team belongs to the selected department
    if (_selectedTeamId != null && _selectedTeamId!.isNotEmpty) {
      final teamMatch = _availableTeams.firstWhereOrNull((t) => t['id']?.toString() == _selectedTeamId);
      if (teamMatch != null) {
        final tDeptId = (teamMatch['deptId'] ?? teamMatch['department_id'] ?? teamMatch['raw']?['department_id'])?.toString();
        if (tDeptId != null && tDeptId.isNotEmpty && _selectedDepartmentId != null && _selectedDepartmentId!.isNotEmpty && tDeptId != _selectedDepartmentId) {
          _selectedTeamId = null;
          team = '';
          unit = '';
        }
      }
    }

    final effectiveDivisionId = widget.existingAction?.divisionId ?? _selectedDivisionId;
    final effectiveDivision = widget.existingAction?.division ?? division;

    final effectiveDept = widget.existingAction?.department ??
        (department.isNotEmpty ? department : (_availableDepartments.isNotEmpty ? _availableDepartments.first['name']?.toString() ?? 'HSE' : 'HSE'));
    final effectiveDeptId = widget.existingAction?.departmentId ?? _selectedDepartmentId;
    final effectiveSite = widget.existingAction?.site ??
        (locationSite.text.trim().isNotEmpty ? locationSite.text.trim() : (_availableSites.isNotEmpty ? _availableSites.first['name']?.toString() ?? 'Site 1' : 'Site 1'));
    final effectiveSiteId = widget.existingAction?.siteId ?? _selectedSiteId;

    if (SupabaseConfig.isInitialized) {
      if (!_isValidUuid(effectiveDeptId)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a Department within your organization scope.'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
        return;
      }
      if (!_isValidUuid(effectiveSiteId)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a Location / Site within your organization scope.'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
        return;
      }
    } else {
      if (effectiveDept.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a Department.'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
        return;
      }
      if (effectiveSite.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a Location / Site.'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
        return;
      }
    }

    if (_isStaff) {
      recipientType = 'internal';
      final staffDeptId = AuthService.instance.currentProfile?.departmentId ??
          AuthService.instance.currentProfileData?.userProfile.departmentId ??
          '';
      final staffDeptName = (AuthService.instance.currentProfile?.department ??
              AuthService.instance.currentProfileData?.userProfile.department ??
              '')
          .trim()
          .toLowerCase();
      final staffSiteId = AuthService.instance.currentProfile?.siteId ??
          AuthService.instance.currentProfileData?.userProfile.siteId ??
          '';
      final staffSiteName = (AuthService.instance.currentProfile?.site ??
              AuthService.instance.currentProfileData?.userProfile.site ??
              '')
          .trim()
          .toLowerCase();

      final deptValid = (staffDeptId.isNotEmpty && effectiveDeptId == staffDeptId) ||
          (staffDeptName.isNotEmpty &&
              effectiveDept.trim().toLowerCase() == staffDeptName);
      final siteValid = (staffSiteId.isNotEmpty && effectiveSiteId == staffSiteId) ||
          (staffSiteName.isNotEmpty &&
              effectiveSite.trim().toLowerCase() == staffSiteName);

      if (!deptValid || !siteValid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Staff members can only create actions within their assigned Department ($staffDeptName) and Site ($staffSiteName).',
            ),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
        return;
      }
    }

    if (_hasManagerScopes) {
      final ctx = widget.managerContext!;
      final deptId = effectiveDeptId ?? '';
      final sId = effectiveSiteId ?? '';
      bool permitted = ctx.isScopePermitted(deptId, sId);
      if (!permitted && effectiveDept.isNotEmpty && effectiveSite.isNotEmpty) {
        permitted = ctx.findScopeByNames(effectiveDept, effectiveSite) != null;
      }
      if (!permitted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'You are only authorized to create actions within your assigned management scopes: '
              '${ctx.scopes.map((s) => '${s.departmentName} (${s.siteName})').join(', ')}.',
            ),
            backgroundColor: const Color(0xFFDC2626),
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);

    String resolvedOrgId = _effectiveOrgId;
    if (!_isValidUuid(resolvedOrgId)) {
      resolvedOrgId = Organization.sobhaId;
    }

    final currentAuthUserId = SupabaseConfig.clientOrNull?.auth.currentUser?.id;
    String resolvedCreatedBy = (currentAuthUserId != null && currentAuthUserId.isNotEmpty)
        ? currentAuthUserId
        : (widget.managerContext?.authUserId ?? AuthService.instance.currentUser?.id ?? '');
    if (!_isValidUuid(resolvedCreatedBy)) {
      resolvedCreatedBy = '00000000-0000-0000-0000-000000000001';
    }

    final record = ActionRecord(
      id: actualActionId,
      subject: actionTitle.text.trim(),
      actionRequired: actionDescription.text.trim(),
      priority: priority,
      status: status,
      percentComplete: effectivePercent,
      division: effectiveDivision,
      divisionId: effectiveDivisionId,
      department: effectiveDept,
      departmentId: effectiveDeptId ?? '',
      section: section,
      sectionId: _selectedSectionId,
      site: effectiveSite.trim(),
      siteId: effectiveSiteId ?? '',
      teamId: _selectedTeamId,
      scopeType: 'specific',
      dateRaised: raiseDate,
      targetDate: targetDate,
      lastFollowUpDate: followUpDate,
      nextFollowUpDate: followUpDate,
      closeDate: effectiveCloseDate,
      assignedTo: assignedToName,
      assignedToId: recipientType == 'internal' ? internalPrimary?.personId : null,
      recipientType: recipientType,
      externalRecipientId: _selectedExternalRecipient?.id,
      externalRecipientEmail: primaryExternalRef?.email,
      externalRecipientName: primaryExternalRef?.name,
      organizationId: resolvedOrgId,
      createdById: resolvedCreatedBy,
      primaryAssignee: recipientType == 'internal' ? internalPrimary : primaryExternalRef,
      additionalPeople: recipientType == 'internal'
          ? List<ActionPersonReference>.from(additionalInternalPeople)
          : List<ActionPersonReference>.from(additionalExternalPeople),
      subTasks: List<ActionSubTask>.from(_tasks),
      attachments: List<String>.from(_attachments),
      followUps: (followUpDate.isNotEmpty && (widget.existingAction?.followUps.isEmpty ?? true))
          ? [
              ActionFollowUpRecord(
                id: 'initial-fu-${DateTime.now().millisecondsSinceEpoch}',
                actionId: '',
                followUpDate: followUpDate,
                notes: 'Initial follow-up checkpoint scheduled at creation',
                status: 'Scheduled',
                createdAt: DateTime.now(),
              )
            ]
          : (widget.existingAction?.followUps ?? const []),
      emailReminderEnabled: emailReminderEnabled,
      emailReminders: effectiveReminders,
    );

    ActionRecord savedRecord;
    try {
      if (_createdActionRecord != null) {
        // Retry or subsequent save of an action already created in this session
        final effectiveRecord = record.copyWith(
          id: _createdActionRecord!.id,
          actionNumber: _createdActionRecord!.actionNumber,
        );
        savedRecord = await ActionService.instance.updateAction(effectiveRecord);
        _createdActionRecord = savedRecord;
      } else if (widget.existingAction != null) {
        savedRecord = await ActionService.instance.updateAction(record);
      } else {
        // Creating new action: persist first via ActionService to get the real database row
        final createdAction = await ActionService.instance.createAction(record);
        _createdActionRecord = createdAction;
        savedRecord = createdAction;
      }

      final failedUploads = <String>[];
      if (_pendingPickedFiles.isNotEmpty) {
        for (final f in List<AppPickedFile>.from(_pendingPickedFiles)) {
          final uploadRes = await ActionService.instance.uploadActionAttachment(
            action: savedRecord,
            fileName: f.name,
            bytes: f.bytes,
          );
          if (uploadRes.success) {
            if (uploadRes.updatedAction != null) {
              savedRecord = uploadRes.updatedAction!;
              if (_createdActionRecord != null) {
                _createdActionRecord = savedRecord;
              }
            }
            _pendingPickedFiles.removeWhere((p) => p.name == f.name);
          } else {
            debugPrint('Warning: Attachment upload failed for ${f.name}: ${uploadRes.error}');
            failedUploads.add(f.name);
          }
        }
      }

      if (failedUploads.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Warning: Failed to upload: ${failedUploads.join(', ')}. These attachments were not added to the action.',
            ),
            backgroundColor: const Color(0xFFDC2626),
            duration: const Duration(seconds: 4),
          ),
        );
      }

      if (_removedAttachments.isNotEmpty) {
        for (final remName in _removedAttachments) {
          unawaited(
            ActionService.instance.removeActionAttachment(
              action: savedRecord,
              fileName: remName,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[AddActionScreen] Error saving action: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save action: $e'),
            backgroundColor: const Color(0xFFDC2626),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    if (mounted) {
      setState(() => _isSubmitting = false);
    }

    widget.onSaved?.call(savedRecord);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Action ${savedRecord.displayId} ${widget.existingAction != null ? 'updated' : 'created'} successfully!',
        ),
        backgroundColor: const Color(0xFF16A34A),
      ),
    );

    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.maybePop(context, savedRecord);
    }
  }

  // ============================================================================
  // BUILD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSection1What(),
                          const SizedBox(height: 20),
                          _buildSection2Where(),
                          const SizedBox(height: 20),
                          _buildSection3Assignment(),
                          const SizedBox(height: 20),
                          _buildSectionTasks(),
                          const SizedBox(height: 20),
                          _buildSection4PriorityStatus(),
                          const SizedBox(height: 20),
                          _buildSection5Dates(),
                          const SizedBox(height: 20),
                          _buildSection6EmailReminder(),
                          const SizedBox(height: 20),
                          _buildSection7Evidence(),
                          const SizedBox(height: 24),
                          _buildBottomActionButtons(),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 450;
          return Row(
            children: [
              IconButton(
                key: const Key('add_action_back_button'),
                tooltip: 'Back',
                icon: Icon(
                  Icons.arrow_back,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : const Color(0xFF94A3B8),
                ),
                onPressed: () {
                  if (widget.onClose != null) {
                    widget.onClose!();
                  } else {
                    Navigator.maybePop(context);
                  }
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      widget.existingAction != null
                          ? 'Edit Action'
                          : 'Add New Action',
                      style: const TextStyle(
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
                        color: const Color(0xFF334155),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF475569)),
                      ),
                      child: Text(
                        widget.actionId,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _isSubmitting ? null : _saveAction,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 16),
                label: Text(
                  widget.existingAction != null
                      ? (isNarrow ? 'SAVE' : 'SAVE CHANGES')
                      : (isNarrow ? 'SEND' : 'SEND ACTION'),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  padding: EdgeInsets.symmetric(
                    horizontal: isNarrow ? 12 : 16,
                    vertical: 10,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================================================================
  // SECTION 1: WHAT THE ACTION IS
  // ============================================================================

  Widget _buildSection1What() {
    return _cardWrapper(
      number: '1',
      title: 'WHAT THE ACTION IS',
      subtitle: 'Provide title and clear details of the safety action',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _textField(
            label: 'Action Title *',
            controller: actionTitle,
            hint: 'e.g. Install Guardrails on Platform 3',
            required: true,
          ),
          const SizedBox(height: 16),
          _textField(
            label: 'Action Description',
            controller: actionDescription,
            hint: 'Enter full description, context, and corrective action details...',
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // SECTION 2: WHERE IT BELONGS
  // ============================================================================

  Widget _buildSection2Where() {
    return _cardWrapper(
      number: '2',
      title: 'WHERE IT BELONGS',
      subtitle: 'Specify department, section, and physical location',
      child: _isLoadingOrgData
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Loading organizational configuration...',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            )
          : _orgDataErrorMessage != null
              ? Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Color(0xFFDC2626),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _orgDataErrorMessage!,
                              style: const TextStyle(
                                color: Color(0xFF991B1B),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        key: const Key('retry_load_org_data_btn'),
                        onPressed: _loadOrganizationalData,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 550;
                    final permittedDepts = _permittedDepartments;
                    final deptItems = permittedDepts.isNotEmpty
                        ? [
                            ...permittedDepts
                                .map((d) => d['name']?.toString() ?? '')
                                .where((s) => s.isNotEmpty && s != 'All Departments')
                                .toSet(),
                          ]
                        : <String>[];
                    final permittedSitesList = _permittedSites;
                    final siteItems = permittedSitesList.isNotEmpty
                        ? [
                            ...permittedSitesList
                                .map((s) => s['name']?.toString() ?? '')
                                .where((s) => s.isNotEmpty && s != 'All Sites / Locations')
                                .toSet(),
                          ]
                        : <String>[];
                    final secItems = [
                      'None',
                      ..._availableSections.map((s) => s.name),
                    ];
                    final validTeams = _filteredTeams;
                    final teamItems = validTeams.isNotEmpty
                        ? [
                            'None',
                            ...validTeams
                                .map((t) => t['name']?.toString() ?? '')
                                .where((s) => s.isNotEmpty),
                          ]
                        : <String>[];

                    return Column(
                      children: [
                        if (isWide)
                          Row(
                            children: [
                              Expanded(
                                child: _dropdownField(
                                  'Department',
                                  department,
                                  deptItems,
                                  _onDepartmentChanged,
                                  isRequired: true,
                                  hint: deptItems.isEmpty
                                      ? 'No departments configured'
                                      : 'Select Department',
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: _dropdownField(
                                  'Location / Site',
                                  locationSite.text,
                                  siteItems,
                                  _onSiteChanged,
                                  isRequired: true,
                                  hint: siteItems.isEmpty
                                      ? 'No sites configured'
                                      : 'Select Location / Site',
                                ),
                              ),
                            ],
                          )
                        else ...[
                          _dropdownField(
                            'Department',
                            department,
                            deptItems,
                            _onDepartmentChanged,
                            isRequired: true,
                            hint: deptItems.isEmpty
                                ? 'No departments configured'
                                : 'Select Department',
                          ),
                          const SizedBox(height: 14),
                          _dropdownField(
                            'Location / Site',
                            locationSite.text,
                            siteItems,
                            _onSiteChanged,
                            isRequired: true,
                            hint: siteItems.isEmpty
                                ? 'No sites configured'
                                : 'Select Location / Site',
                          ),
                        ],
                        const SizedBox(height: 14),
                        if (isWide)
                          Row(
                            children: [
                              Expanded(
                                child: _dropdownField(
                                  'Section',
                                  section.isEmpty ? 'None' : section,
                                  secItems,
                                  _onSectionChanged,
                                  hint: secItems.length <= 1
                                      ? 'No sections configured'
                                      : 'Select Section (Optional)',
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: _dropdownField(
                                  'Teams',
                                  team.isEmpty ? 'None' : team,
                                  teamItems,
                                  _onTeamChanged,
                                  hint: teamItems.isEmpty
                                      ? 'No teams configured'
                                      : 'Select Team (Optional)',
                                ),
                              ),
                            ],
                          )
                        else ...[
                          _dropdownField(
                            'Section',
                            section.isEmpty ? 'None' : section,
                            secItems,
                            _onSectionChanged,
                            hint: secItems.length <= 1
                                ? 'No sections configured'
                                : 'Select Section (Optional)',
                          ),
                          const SizedBox(height: 14),
                          _dropdownField(
                            'Teams',
                            team.isEmpty ? 'None' : team,
                            teamItems,
                            _onTeamChanged,
                            hint: teamItems.isEmpty
                                ? 'No teams configured'
                                : 'Select Team (Optional)',
                          ),
                        ],
                      ],
                    );
                  },
                ),
    );
  }

  // ============================================================================
  // SECTION 3: ASSIGNMENT
  // ============================================================================

  Widget _buildSection3Assignment() {
    return _cardWrapper(
      number: '3',
      title: 'ASSIGNMENT',
      subtitle: _isStaff
          ? 'Assign yourself, a colleague in your department, or your department manager'
          : 'Assign primary and additional internal and external owners',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_isStaff) ...[
            _buildRecipientTypeToggle(),
            const SizedBox(height: 16),
          ],
          _isStaff || recipientType == 'internal'
              ? _buildInternalAssignmentPanel()
              : _buildExternalAssignmentPanel(),
        ],
      ),
    );
  }

  Widget _buildRecipientTypeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: const Key('recipient_type_internal'),
              onTap: () => setState(() => recipientType = 'internal'),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: recipientType == 'internal' ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: recipientType == 'internal'
                      ? [const BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 1))]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.business_rounded,
                      size: 16,
                      color: recipientType == 'internal' ? const Color(0xFF1565C0) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Internal Person',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: recipientType == 'internal' ? const Color(0xFF1565C0) : const Color(0xFF64748B),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: InkWell(
              key: const Key('recipient_type_external'),
              onTap: () => setState(() => recipientType = 'external'),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: recipientType == 'external' ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: recipientType == 'external'
                      ? [const BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 1))]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.business_center_rounded,
                      size: 16,
                      color: recipientType == 'external' ? const Color(0xFF1565C0) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'External User / Recipient',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: recipientType == 'external' ? const Color(0xFF1565C0) : const Color(0xFF64748B),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInternalAssignmentPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.business_rounded,
                  color: Color(0xFF1565C0),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'INTERNAL PERSON',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'ActionFlow user inside organization',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _openAddNewInternalPersonModal,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
              label: const Text('Add New Internal Person'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF1565C0),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Primary Internal Person *',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          if (internalPrimary != null)
            _selectedInternalPersonCard(internalPrimary!, isPrimary: true)
          else
            _internalAutocomplete(
              controller: internalSearchController,
              onSelected: (ref) {
                setState(() {
                  internalPrimary = ref;
                  assignedTo = ref.name;
                  _syncReminderRecipients();
                });
              },
              hint: 'Search by name, email, or phone...',
            ),
          if (additionalInternalPeople.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Additional Internal Persons (${additionalInternalPeople.length})',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 6),
            ...additionalInternalPeople.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _selectedInternalPersonCard(p, isPrimary: false),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _quickAddSelectedInternalPerson,
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 16),
              label: const Text('Add Internal Person'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1565C0),
                side: const BorderSide(color: Color(0xFFBFDBFE)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectedInternalPersonCard(
    ActionPersonReference person, {
    required bool isPrimary,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF93C5FD)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF1565C0),
            radius: 20,
            child: Text(
              person.name.isNotEmpty ? person.name[0].toUpperCase() : 'U',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      person.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isPrimary ? 'Primary' : 'Additional',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1D4ED8),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (person.department.isNotEmpty) person.department,
                    if (person.site.isNotEmpty) person.site,
                    if (person.designation.isNotEmpty) person.designation,
                    if (person.phone.isNotEmpty) person.phone,
                  ].join(' • '),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: Color(0xFF1E293B),
                ),
                tooltip: 'Edit Internal Person',
                onPressed: () =>
                    _editInternalPerson(isPrimary: isPrimary, person: person),
              ),
              IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Color(0xFF64748B),
                ),
                tooltip: 'Remove',
                onPressed: () => setState(() {
                  if (isPrimary) {
                    internalPrimary = null;
                    assignedTo = 'Select worker';
                    internalSearchController.clear();
                  } else {
                    additionalInternalPeople.remove(person);
                  }
                  _syncReminderRecipients();
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _internalAutocomplete({
    required TextEditingController controller,
    required ValueChanged<ActionPersonReference> onSelected,
    required String hint,
  }) {
    return Autocomplete<Person>(
      displayStringForOption: (p) => p.name,
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) return const Iterable<Person>.empty();

        return _eligibleInternalAssignees.where((p) {
          final n = p.name.toLowerCase();
          final e = p.email.toLowerCase();
          final ph = p.phone.toLowerCase();
          final d = p.department.toLowerCase();
          final s = p.site.toLowerCase();
          final des = p.designation.toLowerCase();
          return n.contains(query) ||
              e.contains(query) ||
              ph.contains(query) ||
              d.contains(query) ||
              s.contains(query) ||
              des.contains(query);
        });
      },
      onSelected: (person) {
        onSelected(_reference(person));
      },
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelect, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 250,
                maxWidth: math.min(
                  450,
                  MediaQuery.of(context).size.width - 32,
                ),
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final person = options.elementAt(index);
                  return ListTile(
                    key: Key('internal_person_option_${person.name}'),
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: const Color(0xFF1565C0),
                      child: Text(
                        person.name.isNotEmpty
                            ? person.name[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          person.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        if (person.department.isNotEmpty ||
                            person.site.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: const Color(0xFFBFDBFE),
                              ),
                            ),
                            child: Text(
                              [
                                if (person.department.isNotEmpty)
                                  person.department,
                                if (person.site.isNotEmpty) person.site,
                              ].join(' • '),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1D4ED8),
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (person.designation.isNotEmpty)
                          Text(
                            person.designation,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF334155),
                            ),
                          ),
                        Text(
                          [
                            if (person.email.isNotEmpty) person.email,
                            if (person.phone.isNotEmpty) person.phone,
                          ].join(' • '),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    onTap: () => onSelect(person),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _quickAddSelectedInternalPerson() async {
    final allPeople = _companyUsers.isNotEmpty
        ? _companyUsers
        : MockPeopleStore.instance.people;
    final assignedIds = {
      if (internalPrimary != null) internalPrimary!.personId,
      ...additionalInternalPeople.map((p) => p.personId),
    };

    final initDept = department.trim();
    final initSite = locationSite.text.trim();

    final result = await showDialog<dynamic>(
      context: context,
      builder: (ctx) => _InternalPersonDialog(
        existingPeople: allPeople,
        availableDepartments: _availableDepartments,
        availableSites: _availableSites,
        alreadyAssignedIds: assignedIds,
        initialDepartment: initDept,
        initialSite: initSite,
        initialTabIndex: 0,
      ),
    );

    if (result != null && mounted) {
      if (result is List<Person>) {
        setState(() {
          for (final person in result) {
            final ref = _reference(person);
            final exists = additionalInternalPeople.any(
              (p) => p.personId == ref.personId,
            );
            if (!exists && internalPrimary?.personId != ref.personId) {
              additionalInternalPeople.add(ref);
            }
          }
          _syncReminderRecipients();
        });
      } else if (result is Person) {
        final ref = _reference(result);
        setState(() {
          final exists = additionalInternalPeople.any(
            (p) => p.personId == ref.personId,
          );
          if (!exists && internalPrimary?.personId != ref.personId) {
            additionalInternalPeople.add(ref);
          }
          _syncReminderRecipients();
        });
      }
    }
  }

  Future<void> _openAddNewInternalPersonModal() async {
    final allPeople = _companyUsers.isNotEmpty
        ? _companyUsers
        : MockPeopleStore.instance.people;
    final assignedIds = {
      if (internalPrimary != null) internalPrimary!.personId,
      ...additionalInternalPeople.map((p) => p.personId),
    };

    final result = await showDialog<dynamic>(
      context: context,
      builder: (ctx) => _InternalPersonDialog(
        existingPeople: allPeople,
        availableDepartments: _availableDepartments,
        availableSites: _availableSites,
        alreadyAssignedIds: assignedIds,
        initialTabIndex: 1,
      ),
    );

    if (result != null && mounted) {
      if (result is List<Person>) {
        setState(() {
          for (final person in result) {
            final ref = _reference(person);
            if (internalPrimary == null) {
              internalPrimary = ref;
              assignedTo = person.name;
            } else {
              final exists = additionalInternalPeople.any(
                (p) => p.personId == ref.personId,
              );
              if (!exists && internalPrimary?.personId != ref.personId) {
                additionalInternalPeople.add(ref);
              }
            }
          }
          _syncReminderRecipients();
        });
      } else if (result is Person) {
        final ref = _reference(result);
        setState(() {
          if (internalPrimary == null) {
            internalPrimary = ref;
            assignedTo = result.name;
          } else {
            final exists = additionalInternalPeople.any(
              (p) => p.personId == ref.personId,
            );
            if (!exists && internalPrimary?.personId != ref.personId) {
              additionalInternalPeople.add(ref);
            }
          }
          _syncReminderRecipients();
        });
      }
    }
  }

  Future<void> _editInternalPerson({
    required bool isPrimary,
    required ActionPersonReference person,
  }) async {
    final allPeople = _companyUsers.isNotEmpty
        ? _companyUsers
        : MockPeopleStore.instance.people;
    final updated = await showDialog<dynamic>(
      context: context,
      builder: (ctx) => _InternalPersonDialog(
        existingPeople: allPeople,
        availableDepartments: _availableDepartments,
        availableSites: _availableSites,
        initialPerson: person,
      ),
    );

    if (updated != null && mounted && updated is Person) {
      final updatedRef = ActionPersonReference(
        personId: person.personId,
        name: updated.name,
        type: PersonType.internalUser,
        email: updated.email,
        phone: updated.phone,
        designation: updated.designation,
        department: updated.department,
        site: updated.site,
      );

      setState(() {
        if (isPrimary) {
          internalPrimary = updatedRef;
          assignedTo = updated.name;
        } else {
          final idx = additionalInternalPeople.indexWhere(
            (p) => p.personId == person.personId,
          );
          if (idx != -1) {
            additionalInternalPeople[idx] = updatedRef;
          }
        }
        _syncReminderRecipients();
      });
    }
  }

  // ============================================================================
  // EXTERNAL ASSIGNMENT PANEL
  // ============================================================================

    Widget _buildExternalAssignmentPanel() {
    final storeRecipients = MockActionStore.instance.externalRecipients;
    final allAvailable = <ExternalRecipient>[...storeRecipients];
    if (_selectedExternalRecipient != null &&
        !allAvailable.any((r) => r.id == _selectedExternalRecipient!.id)) {
      allAvailable.add(_selectedExternalRecipient!);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.business_center_rounded,
                  color: Color(0xFF475569),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EXTERNAL USER / RECIPIENT',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'Contractor, vendor, or external agency',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('add_another_external_user_btn'),
              onPressed: _openAddNewExternalPersonModal,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
              label: const Text('+ Add Another External User'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF1565C0),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Primary External Person / Company',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String?>(
            key: const Key('external_recipient_dropdown'),
            value: _selectedExternalRecipient?.id,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Select Existing Recipient',
              filled: true,
              fillColor: Colors.white,
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('-- Select Existing Recipient --'),
              ),
              ...allAvailable.map(
                (r) => DropdownMenuItem<String?>(
                  value: r.id,
                  child: Text('${r.fullName} • ${r.companyName}'),
                ),
              ),
            ],
            onChanged: (id) {
              if (id == null) {
                setState(() {
                  _selectedExternalRecipient = null;
                });
                return;
              }
              final match = allAvailable.firstWhere((r) => r.id == id);
              setState(() {
                _selectedExternalRecipient = match;
                externalName.text = match.fullName;
                externalEmail.text = match.email;
                externalPhone.text = match.phone;
                externalCompany.text = match.companyName;
                externalPrimary = ActionPersonReference(
                  personId: match.id,
                  name: match.fullName,
                  type: PersonType.externalWorker,
                  email: match.email,
                  phone: match.phone,
                  company: match.companyName,
                );
                _syncReminderRecipients();
              });
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: externalName,
            decoration: const InputDecoration(
              labelText: 'Full Name *',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            onChanged: (v) {
              setState(() {
                externalPrimary = ActionPersonReference(
                  personId: _selectedExternalRecipient?.id ?? '',
                  name: v.trim(),
                  type: PersonType.externalWorker,
                  email: externalEmail.text.trim(),
                  phone: externalPhone.text.trim(),
                  company: externalCompany.text.trim(),
                );
                _syncReminderRecipients();
              });
            },
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: externalEmail,
            decoration: const InputDecoration(
              labelText: 'Email Address *',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            keyboardType: TextInputType.emailAddress,
            onChanged: (v) {
              setState(() {
                externalPrimary = ActionPersonReference(
                  personId: _selectedExternalRecipient?.id ?? '',
                  name: externalName.text.trim(),
                  type: PersonType.externalWorker,
                  email: v.trim(),
                  phone: externalPhone.text.trim(),
                  company: externalCompany.text.trim(),
                );
                _syncReminderRecipients();
              });
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: externalCompany,
                  decoration: const InputDecoration(
                    labelText: 'Company / Organization',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: externalPhone,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  keyboardType: TextInputType.phone,
                ),
              ),
            ],
          ),
          if (additionalExternalPeople.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Additional External Users (${additionalExternalPeople.length})',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 8),
            ...additionalExternalPeople.asMap().entries.map((entry) {
              final idx = entry.key;
              final person = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFF64748B),
                      radius: 18,
                      child: Text(
                        person.name.isNotEmpty ? person.name[0].toUpperCase() : 'E',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            person.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                          ),
                          Text(
                            [
                              if (person.company.isNotEmpty) person.company,
                              if (person.email.isNotEmpty) person.email,
                              if (person.phone.isNotEmpty) person.phone,
                            ].join(' • '),
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF1E293B)),
                      tooltip: 'Edit External User',
                      onPressed: () => _editExternalPerson(isPrimary: false, person: person),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF64748B)),
                      tooltip: 'Remove',
                      onPressed: () => setState(() {
                        additionalExternalPeople.removeAt(idx);
                        _syncReminderRecipients();
                      }),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Future<void> _openAddNewExternalPersonModal() async {
    final existing = MockActionStore.instance.externalRecipients;
    final created = await showDialog<ActionPersonReference>(
      context: context,
      builder: (ctx) {
        String? selectedId;
        final nameC = TextEditingController();
        final emailC = TextEditingController();
        final phoneC = TextEditingController();
        final compC = TextEditingController();
        final fKey = GlobalKey<FormState>();

        return StatefulBuilder(
          builder: (context, setDState) {
            return AlertDialog(
              title: const Text('Add Another External User'),
              content: SizedBox(
                width: 450,
                child: Form(
                  key: fKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<String?>(
                          value: selectedId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Select existing external recipient',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('-- Select Existing Recipient --'),
                            ),
                            ...existing.map(
                              (r) => DropdownMenuItem<String?>(
                                value: r.id,
                                child: Text('${r.fullName} • ${r.companyName}'),
                              ),
                            ),
                          ],
                          onChanged: (id) {
                            if (id != null) {
                              final match = existing.firstWhere((r) => r.id == id);
                              setDState(() {
                                selectedId = id;
                                nameC.text = match.fullName;
                                emailC.text = match.email;
                                phoneC.text = match.phone;
                                compC.text = match.companyName;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: nameC,
                          decoration: const InputDecoration(
                            labelText: 'Full Name *',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: emailC,
                          decoration: const InputDecoration(
                            labelText: 'Email Address *',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: compC,
                          decoration: const InputDecoration(
                            labelText: 'Company / Organization',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: phoneC,
                          decoration: const InputDecoration(
                            labelText: 'Phone',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (fKey.currentState!.validate()) {
                      Navigator.pop(
                        ctx,
                        ActionPersonReference(
                          personId: selectedId ?? 'ext_${DateTime.now().millisecondsSinceEpoch}',
                          name: nameC.text.trim(),
                          type: PersonType.externalWorker,
                          email: emailC.text.trim(),
                          phone: phoneC.text.trim(),
                          company: compC.text.trim(),
                        ),
                      );
                    }
                  },
                  child: const Text('Add External User'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created != null && mounted) {
      final normalizedEmail = created.email.toLowerCase().trim();
      final isDuplicate = additionalExternalPeople.any(
            (p) => p.email.toLowerCase().trim() == normalizedEmail,
          ) ||
          externalEmail.text.toLowerCase().trim() == normalizedEmail;

      if (!isDuplicate) {
        setState(() {
          additionalExternalPeople.add(created);
          _syncReminderRecipients();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'An external recipient with the email "${created.email}" has already been added.',
            ),
            backgroundColor: const Color(0xFFDC2626),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _editExternalPerson({
    required bool isPrimary,
    required ActionPersonReference person,
  }) async {
    final updated = await showDialog<ActionPersonReference>(
      context: context,
      builder: (ctx) {
        final nameC = TextEditingController(text: person.name);
        final emailC = TextEditingController(text: person.email);
        final phoneC = TextEditingController(text: person.phone);
        final compC = TextEditingController(text: person.company);
        final fKey = GlobalKey<FormState>();

        return AlertDialog(
          title: const Text('Edit External User'),
          content: SizedBox(
            width: 450,
            child: Form(
              key: fKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameC,
                      decoration: const InputDecoration(
                        labelText: 'Full Name *',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: emailC,
                      decoration: const InputDecoration(
                        labelText: 'Email Address *',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: compC,
                      decoration: const InputDecoration(
                        labelText: 'Company / Organization',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: phoneC,
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (fKey.currentState!.validate()) {
                  Navigator.pop(
                    ctx,
                    person.copyWith(
                      name: nameC.text.trim(),
                      email: emailC.text.trim(),
                      phone: phoneC.text.trim(),
                      company: compC.text.trim(),
                    ),
                  );
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        );
      },
    );

    if (updated != null && mounted) {
      setState(() {
        if (isPrimary) {
          externalPrimary = updated;
          externalName.text = updated.name;
          externalEmail.text = updated.email;
          externalPhone.text = updated.phone;
          externalCompany.text = updated.company;
        } else {
          final idx = additionalExternalPeople.indexWhere(
            (p) => p.personId == person.personId,
          );
          if (idx != -1) {
            additionalExternalPeople[idx] = updated;
          }
        }
        _syncReminderRecipients();
      });
    }
  }

  Widget _buildSectionTasks() {
    return _cardWrapper(
      number: '3B',
      title: 'ACTION TASKS / CHECKLIST',
      subtitle: 'Define subtasks/checklist items for assignees',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_tasks.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Center(
                child: Text(
                  'No tasks defined. Add tasks to break this action down into trackable checklist items for assignees.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          ..._tasks.asMap().entries.map((entry) {
            final index = entry.key;
            final task = entry.value;
            return _buildTaskRow(task, index);
          }),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('add_task_btn'),
              onPressed: _addTask,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('+ Add Task'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1565C0),
                side: const BorderSide(color: Color(0xFF93C5FD)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskRow(ActionSubTask task, int index) {
    // Collect all selectable assignees
    final allPeople = <ActionPersonReference>[];
    if (internalPrimary != null) allPeople.add(internalPrimary!);
    allPeople.addAll(additionalInternalPeople);
    if (externalPrimary != null) allPeople.add(externalPrimary!);
    allPeople.addAll(additionalExternalPeople);

    // Also include active users from loaded _companyUsers, MockPeopleStore and externalRecipients
    for (final p in _companyUsers) {
      if (p.isActive && !allPeople.any((a) => a.personId == p.id || a.name == p.name)) {
        allPeople.add(_reference(p));
      }
    }
    for (final p in MockPeopleStore.instance.people) {
      if (!allPeople.any((a) => a.personId == p.id || a.name == p.name)) {
        allPeople.add(_reference(p));
      }
    }
    for (final ext in MockActionStore.instance.externalRecipients) {
      if (!allPeople.any((a) => a.name == ext.fullName)) {
        allPeople.add(
          ActionPersonReference(
            personId: ext.id,
            name: ext.fullName,
            type: PersonType.externalWorker,
            email: ext.email,
            phone: ext.phone,
            company: ext.companyName,
          ),
        );
      }
    }

    final currentAssigneeValue = task.assignedStaff.isNotEmpty
        ? task.assignedStaff
        : (allPeople.isNotEmpty ? allPeople.first.name : '');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: Key('task_title_input_$index'),
                  initialValue: task.title,
                  decoration: InputDecoration(
                    labelText: 'Task Title *',
                    hintText: 'e.g. Inspect scaffolding anchors',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onChanged: (v) {
                    _tasks[index] = _tasks[index].copyWith(title: v.trim());
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: Key('remove_task_btn_$index'),
                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                tooltip: 'Remove',
                onPressed: () => _removeTask(index),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: Key('task_assignee_selector_$index'),
                  value: allPeople.any((p) => p.name == currentAssigneeValue)
                      ? currentAssigneeValue
                      : (allPeople.isNotEmpty ? allPeople.first.name : null),
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Assignee',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: allPeople.map((p) {
                    final typeStr = p.type == PersonType.externalWorker
                        ? 'External Contractor'
                        : 'Internal';
                    return DropdownMenuItem<String>(
                      value: p.name,
                      child: Text('${p.name} ($typeStr)'),
                    );
                  }).toList(),
                  onChanged: (name) {
                    if (name != null) {
                      final match = allPeople.firstWhere((p) => p.name == name);
                      setState(() {
                        _tasks[index] = _tasks[index].copyWith(
                          assignedStaff: match.name,
                          assignedStaffId: match.personId,
                          assignedStaffEmail: match.email,
                          assigneeType: match.type == PersonType.externalWorker ? 'external' : 'internal',
                        );
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Container(
                key: Key('task_assignee_badge_$index'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: task.isExternal ? const Color(0xFFFEF3C7) : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: task.isExternal ? const Color(0xFFFDE68A) : const Color(0xFFBFDBFE),
                  ),
                ),
                child: Text(
                  task.isExternal ? 'External' : 'Internal',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: task.isExternal ? const Color(0xFFB45309) : const Color(0xFF1D4ED8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _addTask() {
    setState(() {
      final nextIndex = _tasks.length;
      final defaultAssignee = internalPrimary?.name.isNotEmpty == true
          ? internalPrimary!.name
          : (externalPrimary?.name.isNotEmpty == true
              ? externalPrimary!.name
              : (externalName.text.isNotEmpty ? externalName.text.trim() : 'Primary Assignee'));
      final defaultId = internalPrimary?.personId ?? externalPrimary?.personId ?? '';
      final defaultEmail = internalPrimary?.email ?? externalPrimary?.email ?? externalEmail.text.trim();
      final defaultType = recipientType == 'external' ? 'external' : 'internal';

      _tasks.add(
        ActionSubTask(
          id: 'task_${DateTime.now().millisecondsSinceEpoch}_$nextIndex',
          parentActionId: widget.actionId,
          title: '',
          instruction: '',
          assignedStaff: defaultAssignee,
          assignedStaffId: defaultId,
          assignedStaffEmail: defaultEmail,
          assigneeType: defaultType,
        ),
      );
    });
  }

  void _removeTask(int index) {
    setState(() {
      _tasks.removeAt(index);
    });
  }

  Widget _buildSection4PriorityStatus() {
    const canonicalStatuses = [
      'Open',
      'In Progress',
      'Pending Review',
      'Under Review',
      'Ready for Review',
      'Completed',
      'Overdue',
      'Closed',
    ];

    final percentOptions = [0, 10, 20, 25, 30, 40, 50, 60, 70, 75, 80, 90, 100];
    final effectivePercents = percentOptions.contains(percent)
        ? percentOptions
        : [...percentOptions, percent]..sort();

    return _cardWrapper(
      number: '4',
      title: 'PRIORITY & STATUS',
      subtitle: 'Set urgency level and current implementation status',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 550;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isWide)
                Row(
                  children: [
                    Expanded(
                      child: _dropdownField('Priority', priority, [
                        'Critical',
                        'High',
                        'Medium',
                        'Low',
                      ], (v) => setState(() => priority = v!)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _dropdownField('Status', status, canonicalStatuses,
                          (v) => setState(() => status = v!)),
                    ),
                  ],
                )
              else ...[
                _dropdownField('Priority', priority, [
                  'Critical',
                  'High',
                  'Medium',
                  'Low',
                ], (v) => setState(() => priority = v!)),
                const SizedBox(height: 14),
                _dropdownField('Status', status, canonicalStatuses,
                    (v) => setState(() => status = v!)),
              ],
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                value: percent,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '% Complete',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
                items: effectivePercents
                    .map(
                      (v) => DropdownMenuItem<int>(value: v, child: Text('$v%')),
                    )
                    .toList(),
                onChanged: (v) => setState(() {
                  percent = v ?? 0;
                  _isPercentManuallyModified = true;
                }),
              ),
              if (_tasks.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: Color(0xFF1D4ED8)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Checklist tasks (${_tasks.where((t) => t.isCompleted).length}/${_tasks.length} done) track operational execution. Overall Action Progress (% Complete) is set manually per Step 25 rules.',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF1E40AF)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  // ============================================================================
  // SECTION 5: DATES
  // ============================================================================

  Widget _buildSection5Dates() {
    return _cardWrapper(
      number: '5',
      title: 'DATES',
      subtitle:
          'Set raise date, target closure date, and optional actual close date',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 750;
          return isWide
              ? Row(
                  children: [
                    Expanded(
                      child: _datePickerField(
                        label: 'Raise Date',
                        value: raiseDate,
                        onSelected: (v) => setState(() => raiseDate = v),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _datePickerField(
                        label: 'Target / Due Date *',
                        value: targetDate,
                        onSelected: (v) => setState(() => targetDate = v),
                        required: true,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _datePickerField(
                        label: 'Follow-Up Date',
                        value: followUpDate,
                        onSelected: (v) => setState(() => followUpDate = v),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _datePickerField(
                        label: 'Close Date',
                        value: closeDate,
                        onSelected: (v) => setState(() => closeDate = v),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    _datePickerField(
                      label: 'Raise Date',
                      value: raiseDate,
                      onSelected: (v) => setState(() => raiseDate = v),
                    ),
                    const SizedBox(height: 14),
                    _datePickerField(
                      label: 'Target / Due Date *',
                      value: targetDate,
                      onSelected: (v) => setState(() => targetDate = v),
                      required: true,
                    ),
                    const SizedBox(height: 14),
                    _datePickerField(
                      label: 'Follow-Up Date',
                      value: followUpDate,
                      onSelected: (v) => setState(() => followUpDate = v),
                    ),
                    const SizedBox(height: 14),
                    _datePickerField(
                      label: 'Close Date',
                      value: closeDate,
                      onSelected: (v) => setState(() => closeDate = v),
                    ),
                  ],
                );
        },
      ),
    );
  }

  Widget _datePickerField({
    required String label,
    required String value,
    required ValueChanged<String> onSelected,
    bool required = false,
  }) {
    return InkWell(
      onTap: () => chooseDate(onSelected),
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
          suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
        ),
        child: Text(
          value.isNotEmpty ? value : 'Select Date',
          style: TextStyle(
            fontSize: 14,
            color: value.isNotEmpty
                ? const Color(0xFF0F172A)
                : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // SECTION 6: EMAIL REMINDER
  // ============================================================================

  Widget _buildSection6EmailReminder() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: emailReminderEnabled
              ? const Color(0xFF93C5FD)
              : const Color(0xFFE2E8F0),
          width: emailReminderEnabled ? 1.5 : 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header (Clean Wrap avoiding horizontal overflow)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: emailReminderEnabled
                  ? const Color(0xFFEFF6FF)
                  : const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              border: const Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: emailReminderEnabled
                          ? const Color(0xFF1565C0)
                          : const Color(0xFF64748B),
                      child: const Text(
                        '6',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Text(
                      'EMAIL REMINDER',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    const Text(
                      'Enable Email Reminder',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF334155),
                      ),
                    ),
                    Switch(
                      value: emailReminderEnabled,
                      activeTrackColor: const Color(0xFF1565C0),
                      onChanged: (val) {
                        setState(() {
                          emailReminderEnabled = val;
                          if (val && emailReminders.isEmpty) {
                            emailReminders.add(_createDefaultReminder());
                          }
                          _syncReminderRecipients();
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Body (Visible when enabled)
          if (emailReminderEnabled)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...emailReminders.asMap().entries.map((entry) {
                    final index = entry.key;
                    final reminder = entry.value;
                    return _buildReminderCard(reminder, index);
                  }),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          emailReminders.add(_createDefaultReminder());
                          _syncReminderRecipients();
                        });
                      },
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('+ Add Another Reminder'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1565C0),
                        side: const BorderSide(color: Color(0xFF93C5FD)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
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
  }

  Widget _buildReminderCard(ActionEmailReminder reminder, int index) {
    final assignedPeople = _getAssignedPeople();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Reminder badge + Actions
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Reminder ${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: Color(0xFF475569),
                ),
                tooltip: 'Edit Reminder',
                onPressed: () => _openEditReminderDialog(reminder, index),
              ),
              if (emailReminders.length > 1)
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: Color(0xFFEF4444),
                  ),
                  tooltip: 'Remove Reminder',
                  onPressed: () =>
                      setState(() => emailReminders.removeAt(index)),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Date & Time pickers
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 200,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reminder Date *',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () => chooseDate((v) {
                        if (closeDate.isNotEmpty &&
                            _isDateAfter(v, closeDate)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Reminder date cannot be after Close Date ($closeDate).',
                              ),
                              backgroundColor: const Color(0xFFDC2626),
                            ),
                          );
                          return;
                        }
                        setState(() {
                          emailReminders[index] = reminder.copyWith(date: v);
                        });
                      }),
                      borderRadius: BorderRadius.circular(8),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFFCBD5E1),
                            ),
                          ),
                          suffixIcon: const Icon(
                            Icons.calendar_today_rounded,
                            size: 16,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        child: Text(
                          reminder.date.isNotEmpty
                              ? reminder.date
                              : 'Select Date',
                          style: TextStyle(
                            fontSize: 13,
                            color: reminder.date.isNotEmpty
                                ? const Color(0xFF0F172A)
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 170,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reminder Time *',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () => chooseTime((v) {
                        setState(() {
                          emailReminders[index] = reminder.copyWith(time: v);
                        });
                      }),
                      borderRadius: BorderRadius.circular(8),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFFCBD5E1),
                            ),
                          ),
                          suffixIcon: const Icon(
                            Icons.access_time_rounded,
                            size: 16,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        child: Text(
                          reminder.time.isNotEmpty
                              ? reminder.time
                              : 'Select Time',
                          style: TextStyle(
                            fontSize: 13,
                            color: reminder.time.isNotEmpty
                                ? const Color(0xFF0F172A)
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Recipient Selection
          const Text(
            'Send Reminder To',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Select Person(s)',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: Color(0xFF334155),
            ),
          ),
          const Text(
            'Who should receive this reminder?',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF475569),
            ),
          ),
          const Text(
            '(Select from people assigned to this action)',
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 8),

          if (assignedPeople.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: Color(0xFFD97706),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Add at least one person in Assignment before selecting email reminder recipients.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Column(
                children: assignedPeople.map((person) {
                  final isSelected = reminder.recipients.any(
                    (r) =>
                        (r.personId.isNotEmpty &&
                            r.personId == person.personId) ||
                        r.name.toLowerCase() == person.name.toLowerCase(),
                  );
                  return _recipientCheckboxItem(
                    person: person,
                    isSelected: isSelected,
                    onChanged: (checked) {
                      setState(() {
                        final currentList = List<ActionPersonReference>.from(
                          reminder.recipients,
                        );
                        if (checked == true) {
                          if (!currentList.any(
                            (r) =>
                                r.personId == person.personId &&
                                r.name.toLowerCase() ==
                                    person.name.toLowerCase(),
                          )) {
                            currentList.add(person);
                          }
                        } else {
                          currentList.removeWhere(
                            (r) =>
                                (r.personId.isNotEmpty &&
                                    r.personId == person.personId) ||
                                r.name.toLowerCase() ==
                                    person.name.toLowerCase(),
                          );
                        }
                        emailReminders[index] = reminder.copyWith(
                          recipients: currentList,
                        );
                      });
                    },
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _recipientCheckboxItem({
    required ActionPersonReference person,
    required bool isSelected,
    required ValueChanged<bool?> onChanged,
  }) {
    final isInternal = person.type == PersonType.internalUser;
    return InkWell(
      onTap: () => onChanged(!isSelected),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Checkbox(
              value: isSelected,
              activeColor: const Color(0xFF1565C0),
              onChanged: onChanged,
            ),
            CircleAvatar(
              radius: 14,
              backgroundColor: isInternal
                  ? const Color(0xFF1565C0)
                  : const Color(0xFF475569),
              child: Text(
                person.name.isNotEmpty ? person.name[0].toUpperCase() : 'P',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        person.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: isInternal
                              ? const Color(0xFFEFF6FF)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isInternal
                                ? const Color(0xFFBFDBFE)
                                : const Color(0xFFCBD5E1),
                          ),
                        ),
                        child: Text(
                          isInternal ? 'Internal' : 'External',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: isInternal
                                ? const Color(0xFF1D4ED8)
                                : const Color(0xFF475569),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (person.company.isNotEmpty) person.company,
                      if (person.designation.isNotEmpty) person.designation,
                      if (person.email.isNotEmpty) person.email,
                    ].join(' • '),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditReminderDialog(
    ActionEmailReminder reminder,
    int index,
  ) async {
    final updated = await showDialog<ActionEmailReminder>(
      context: context,
      builder: (ctx) => _EditReminderDialog(
        reminder: reminder,
        index: index,
        availablePeople: _getAssignedPeople(),
        closeDate: closeDate,
      ),
    );

    if (updated != null && mounted) {
      setState(() {
        emailReminders[index] = updated;
      });
    }
  }

  // ============================================================================
  // SECTION 7: EVIDENCE
  // ============================================================================

  Widget _buildSection7Evidence() {
    return _cardWrapper(
      number: '7',
      title: 'EVIDENCE / ATTACHMENTS',
      subtitle: 'Attach photos, safety reports, and documentation',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const Key('add_action_upload_evidence_box'),
            onTap: _pickAttachment,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFCBD5E1),
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                children: const [
                  Icon(
                    Icons.cloud_upload_outlined,
                    size: 36,
                    color: Color(0xFF94A3B8),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Click to upload or drag & drop files here',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF475569),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'PNG, JPG, PDF up to 10MB',
                    style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),
          ),
          if (_attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._attachments.asMap().entries.map((entry) {
              final idx = entry.key;
              final fileName = entry.value;
              final pending = _pendingPickedFiles.firstWhere(
                (p) => p.name == fileName,
                orElse: () => AppPickedFile(name: fileName, bytes: Uint8List(0), size: 0),
              );
              final sizeText = pending.size > 0 ? ' • ${pending.formattedSize}' : '';
              return Container(
                key: Key('attachment_item_$idx'),
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.attach_file_rounded, size: 16, color: Color(0xFF1565C0)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$fileName$sizeText',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      key: Key('remove_attachment_${idx}_btn'),
                      icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF94A3B8)),
                      tooltip: 'Remove',
                      onPressed: () => setState(() {
                        _attachments.removeAt(idx);
                        _pendingPickedFiles.removeWhere((p) => p.name == fileName);
                        if (widget.existingAction != null &&
                            widget.existingAction!.attachments.contains(fileName)) {
                          _removedAttachments.add(fileName);
                        }
                      }),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Future<void> _pickAttachment() async {
    try {
      final file = await AppFilePicker.pickSingleFile();
      if (file != null) {
        const maxBytes = 10 * 1024 * 1024;
        if (file.size > maxBytes) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'File size exceeds 10 MB limit (${file.formattedSize}).',
                ),
                backgroundColor: const Color(0xFFDC2626),
              ),
            );
          }
          return;
        }

        setState(() {
          if (!_attachments.contains(file.name)) {
            _attachments.add(file.name);
            _pendingPickedFiles.add(file);
          }
        });
      }
    } catch (e) {
      debugPrint('Error picking attachment: $e');
    }
  }

  Widget _buildBottomActionButtons() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Wrap(
          alignment: WrapAlignment.end,
          spacing: 14,
          runSpacing: 10,
          children: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                foregroundColor: const Color(0xFF475569),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _saveAction,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(
                widget.existingAction != null ? 'Save Changes' : 'Send Action',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================================
  // GENERIC WIDGETS
  // ============================================================================

  Widget _cardWrapper({
    required String number,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: const Color(0xFF1565C0),
                  child: Text(
                    number,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }

  Widget _textField({
    required String label,
    required TextEditingController controller,
    required String hint,
    bool required = false,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          onChanged: onChanged,
          validator: required
              ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
              : null,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dropdownField(
    String label,
    String value,
    List<String> items,
    ValueChanged<String?> onChanged, {
    bool enabled = true,
    String? hint,
    bool isRequired = false,
  }) {
    final hasItems = items.isNotEmpty;
    final effectiveItems = items.contains(value) && value.isNotEmpty
        ? items
        : (value.isNotEmpty ? [...items, value] : items);
    final selectedVal =
        (effectiveItems.contains(value) && value.isNotEmpty) ? value : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Color(0xFF334155),
              ),
            ),
            if (isRequired)
              const Text(
                ' *',
                style: TextStyle(
                  color: Color(0xFFDC2626),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: selectedVal,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: isRequired ? '$label *' : label,
            hintText: hint ??
                (hasItems
                    ? 'Select $label'
                    : 'No ${label.toLowerCase()} configured'),
            filled: true,
            fillColor:
                enabled && hasItems ? Colors.white : const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
          ),
          items: effectiveItems
              .map((i) => DropdownMenuItem(value: i, child: Text(i)))
              .toList(),
          onChanged: (enabled && hasItems) ? onChanged : null,
        ),
      ],
    );
  }
}

// ============================================================================
// EDIT REMINDER DIALOG
// ============================================================================

class _EditReminderDialog extends StatefulWidget {
  const _EditReminderDialog({
    required this.reminder,
    required this.index,
    required this.availablePeople,
    this.closeDate,
  });

  final ActionEmailReminder reminder;
  final int index;
  final List<ActionPersonReference> availablePeople;
  final String? closeDate;

  @override
  State<_EditReminderDialog> createState() => _EditReminderDialogState();
}

class _EditReminderDialogState extends State<_EditReminderDialog> {
  late String date;
  late String time;
  late List<ActionPersonReference> selectedRecipients;

  @override
  void initState() {
    super.initState();
    date = widget.reminder.date;
    time = widget.reminder.time;
    selectedRecipients = List.from(widget.reminder.recipients);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: Color(0xFF1565C0),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.edit_calendar_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Edit Reminder ${widget.index + 1}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                      size: 20,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final now = DateTime.now();
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: now,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) {
                                final formatted =
                                    _AddActionScreenState._formatDate(picked);
                                if (widget.closeDate != null &&
                                    widget.closeDate!.isNotEmpty &&
                                    _AddActionScreenState._isDateAfter(
                                      formatted,
                                      widget.closeDate!,
                                    )) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Reminder date cannot be after Close Date (${widget.closeDate}).',
                                        ),
                                        backgroundColor: const Color(
                                          0xFFDC2626,
                                        ),
                                      ),
                                    );
                                  }
                                  return;
                                }
                                setState(() => date = formatted);
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Reminder Date *',
                                suffixIcon: Icon(Icons.calendar_month_rounded),
                              ),
                              child: Text(
                                date.isNotEmpty ? date : 'Select Date',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: const TimeOfDay(
                                  hour: 9,
                                  minute: 0,
                                ),
                              );
                              if (picked != null) {
                                final hour = picked.hourOfPeriod == 0
                                    ? 12
                                    : picked.hourOfPeriod;
                                final minute = picked.minute.toString().padLeft(
                                  2,
                                  '0',
                                );
                                final period = picked.period == DayPeriod.am
                                    ? 'AM'
                                    : 'PM';
                                setState(
                                  () => time =
                                      '${hour.toString().padLeft(2, '0')}:$minute $period',
                                );
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Reminder Time *',
                                suffixIcon: Icon(Icons.access_time_rounded),
                              ),
                              child: Text(
                                time.isNotEmpty ? time : 'Select Time',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Assigned Recipients',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Select who should receive this reminder from people assigned to this action.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 10),
                    if (widget.availablePeople.isEmpty)
                      const Text(
                        'No people currently assigned in Assignment section.',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Color(0xFF94A3B8),
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: widget.availablePeople.map((person) {
                            final isChecked = selectedRecipients.any(
                              (p) =>
                                  (p.personId.isNotEmpty &&
                                      p.personId == person.personId) ||
                                  p.name.toLowerCase() ==
                                      person.name.toLowerCase(),
                            );
                            return CheckboxListTile(
                              dense: true,
                              value: isChecked,
                              title: Text(
                                person.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  if (person.company.isNotEmpty) person.company,
                                  if (person.designation.isNotEmpty)
                                    person.designation,
                                  if (person.email.isNotEmpty) person.email,
                                ].join(' • '),
                                style: const TextStyle(fontSize: 11),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    if (!selectedRecipients.any(
                                      (p) =>
                                          p.personId == person.personId &&
                                          p.name.toLowerCase() ==
                                              person.name.toLowerCase(),
                                    )) {
                                      selectedRecipients.add(person);
                                    }
                                  } else {
                                    selectedRecipients.removeWhere(
                                      (p) =>
                                          (p.personId.isNotEmpty &&
                                              p.personId == person.personId) ||
                                          p.name.toLowerCase() ==
                                              person.name.toLowerCase(),
                                    );
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      final updated = widget.reminder.copyWith(
                        date: date,
                        time: time,
                        recipients: selectedRecipients,
                      );
                      Navigator.pop(context, updated);
                    },
                    child: const Text('Save Changes'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// INTERNAL PERSON DIALOG
// ============================================================================

class _InternalPersonDialog extends StatefulWidget {
  const _InternalPersonDialog({
    required this.existingPeople,
    this.initialPerson,
    this.availableDepartments = const [],
    this.availableSites = const [],
    this.alreadyAssignedIds = const {},
    this.initialDepartment,
    this.initialSite,
    this.initialTabIndex = 0,
  });

  final List<Person> existingPeople;
  final ActionPersonReference? initialPerson;
  final List<Map<String, dynamic>> availableDepartments;
  final List<Map<String, dynamic>> availableSites;
  final Set<String> alreadyAssignedIds;
  final String? initialDepartment;
  final String? initialSite;
  final int initialTabIndex;

  @override
  State<_InternalPersonDialog> createState() => _InternalPersonDialogState();
}

class _InternalPersonDialogState extends State<_InternalPersonDialog> {
  late int _currentTab;
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController email;
  late final TextEditingController phone;
  late final TextEditingController designation;
  late final TextEditingController department;
  late final TextEditingController site;
  Person? existing;

  // Multi-select state
  String _selectedDept = '';
  String _selectedSite = '';
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedUserIds = {};
  final Map<String, Person> _selectedPeopleMap = {};

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialPerson != null ? 1 : widget.initialTabIndex;
    _selectedDept = (widget.initialDepartment != null &&
            widget.initialDepartment != 'All Departments')
        ? widget.initialDepartment!
        : '';
    _selectedSite = (widget.initialSite != null &&
            widget.initialSite != 'All Sites / Locations')
        ? widget.initialSite!
        : '';
    if (_selectedSite.isNotEmpty && !_siteOptions.contains(_selectedSite)) {
      _selectedSite = '';
    }
    final initial = widget.initialPerson;
    name = TextEditingController(text: initial?.name);
    email = TextEditingController(text: initial?.email);
    phone = TextEditingController(text: initial?.phone);
    designation = TextEditingController(text: initial?.designation);
    department = TextEditingController(text: initial?.department);
    site = TextEditingController(text: initial?.site);

    if (initial != null) {
      existing = widget.existingPeople.cast<Person?>().firstWhere(
        (p) => p?.id == initial.personId,
        orElse: () => null,
      );
      if (existing != null && department.text.isEmpty) {
        department.text = existing!.department;
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final controller in [
      name,
      email,
      phone,
      designation,
      department,
      site,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void choose(Person person) {
    setState(() => existing = person);
    name.text = person.name;
    email.text = person.email;
    phone.text = person.phone;
    designation.text = person.designation;
    department.text = person.department;
    site.text = person.site;
  }

  List<String> get _departmentOptions {
    final set = <String>{};
    for (final d in widget.availableDepartments) {
      if (d['is_active'] == false ||
          d['status']?.toString().toLowerCase() == 'inactive') {
        continue;
      }
      final n = d['name']?.toString().trim();
      if (n != null && n.isNotEmpty) set.add(n);
    }
    for (final p in widget.existingPeople) {
      if (p.isActive &&
          p.type == PersonType.internalUser &&
          p.department.trim().isNotEmpty) {
        set.add(p.department.trim());
      }
    }
    final list = set.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  List<String> get _siteOptions {
    final set = <String>{};
    for (final s in widget.availableSites) {
      if (s['is_active'] == false ||
          s['status']?.toString().toLowerCase() == 'inactive') {
        continue;
      }
      final sName = s['name']?.toString().trim();
      if (sName == null || sName.isEmpty) continue;
      if (_selectedDept.isNotEmpty && _selectedDept != 'All Departments') {
        final sDept = s['department_name'] ?? s['department'];
        if (sDept != null &&
            sDept.toString().trim().toLowerCase() ==
                _selectedDept.toLowerCase()) {
          set.add(sName);
        } else if (s['department_id'] != null) {
          final matchedDept = widget.availableDepartments.firstWhereOrNull(
            (d) =>
                d['name']?.toString().trim().toLowerCase() ==
                _selectedDept.toLowerCase(),
          );
          if (matchedDept != null &&
              s['department_id']?.toString() ==
                  matchedDept['id']?.toString()) {
            set.add(sName);
          }
        }
      } else {
        set.add(sName);
      }
    }
    for (final p in widget.existingPeople) {
      if (!p.isActive || p.type != PersonType.internalUser) continue;
      if (_selectedDept.isNotEmpty && _selectedDept != 'All Departments') {
        if (p.department.trim().toLowerCase() != _selectedDept.toLowerCase()) {
          continue;
        }
      }
      if (p.site.trim().isNotEmpty) {
        set.add(p.site.trim());
      }
    }
    if (set.isEmpty) {
      for (final s in widget.availableSites) {
        if (s['is_active'] == false ||
            s['status']?.toString().toLowerCase() == 'inactive') {
          continue;
        }
        final n = s['name']?.toString().trim();
        if (n != null && n.isNotEmpty) set.add(n);
      }
      for (final p in widget.existingPeople) {
        if (p.isActive &&
            p.type == PersonType.internalUser &&
            p.site.trim().isNotEmpty) {
          set.add(p.site.trim());
        }
      }
    }
    final list = set.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  List<Person> get _filteredEligibleUsers {
    final query = _searchController.text.trim().toLowerCase();
    return widget.existingPeople.where((p) {
      if (!p.isActive || p.type != PersonType.internalUser) return false;

      // Operational Assignee Exclusion: Admin-role users are excluded from operational assignees
      final roleStr = p.role.toString().toLowerCase();
      final isPersonAdmin = roleStr.contains('admin') ||
          p.role.name.toLowerCase().contains('admin') ||
          p.role == UserRole.admin ||
          p.designation.toLowerCase().contains('admin');
      if (isPersonAdmin) return false;

      if (_selectedDept.isNotEmpty && _selectedDept != 'All Departments') {
        if (p.department.trim().toLowerCase() != _selectedDept.toLowerCase()) {
          return false;
        }
      }

      if (_selectedSite.isNotEmpty && _selectedSite != 'All Sites / Locations') {
        if (p.site.trim().toLowerCase() != _selectedSite.toLowerCase()) {
          return false;
        }
      }

      if (query.isNotEmpty) {
        final nameMatch = p.name.toLowerCase().contains(query);
        final emailMatch = p.email.toLowerCase().contains(query);
        final desigMatch = p.designation.toLowerCase().contains(query);
        if (!nameMatch && !emailMatch && !desigMatch) return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialPerson != null;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDialogHeader(isEdit),
              if (!isEdit) _buildTabSelector(),
              Expanded(
                child: isEdit || _currentTab == 1
                    ? _buildManualFormTab(isEdit)
                    : _buildExistingUsersTab(),
              ),
              if (!isEdit && _currentTab == 0)
                _buildExistingUsersBottomBar()
              else
                _buildManualFormBottomBar(isEdit),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDialogHeader(bool isEdit) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF1565C0),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.person_add_alt_1_rounded,
            color: Colors.white,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isEdit ? 'Edit Internal Person' : 'Add New Internal Person',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white70,
              size: 20,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSelector() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: const Key('tab_select_existing_users'),
              onTap: () => setState(() => _currentTab = 0),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                decoration: BoxDecoration(
                  color: _currentTab == 0 ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: _currentTab == 0
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          )
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.group_add_outlined,
                      size: 15,
                      color: _currentTab == 0
                          ? const Color(0xFF1565C0)
                          : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Select Existing Users',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _currentTab == 0
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: _currentTab == 0
                              ? const Color(0xFF1565C0)
                              : const Color(0xFF64748B),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: InkWell(
              key: const Key('tab_add_custom_person'),
              onTap: () => setState(() => _currentTab = 1),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                decoration: BoxDecoration(
                  color: _currentTab == 1 ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: _currentTab == 1
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          )
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.person_add_alt_outlined,
                      size: 15,
                      color: _currentTab == 1
                          ? const Color(0xFF1565C0)
                          : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Add New / Custom Person',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _currentTab == 1
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: _currentTab == 1
                              ? const Color(0xFF1565C0)
                              : const Color(0xFF64748B),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExistingUsersTab() {
    final depts = _departmentOptions;
    final sites = _siteOptions;
    final users = _filteredEligibleUsers;
    final selectableUsers = users
        .where((u) => !widget.alreadyAssignedIds.contains(u.id))
        .toList();
    final allSelectableSelected = selectableUsers.isNotEmpty &&
        selectableUsers.every((u) => _selectedUserIds.contains(u.id));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (ctx, constraints) {
              final isNarrow = constraints.maxWidth < 420;
              final deptDropdown = DropdownButtonFormField<String>(
                key: const Key('dialog_department_dropdown'),
                value: _selectedDept.isEmpty ? '' : _selectedDept,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Department',
                  hintText: 'All Departments',
                  prefixIcon: const Icon(Icons.domain_outlined, size: 18),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('All Departments'),
                  ),
                  ...depts.map(
                    (d) => DropdownMenuItem<String>(
                      value: d,
                      child: Text(d, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedDept = val ?? '';
                    final currentSites = _siteOptions;
                    if (_selectedSite.isNotEmpty &&
                        !currentSites.contains(_selectedSite)) {
                      _selectedSite = '';
                    }
                  });
                },
              );

              final siteDropdown = DropdownButtonFormField<String>(
                key: const Key('dialog_site_dropdown'),
                value: _selectedSite.isEmpty ? '' : _selectedSite,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Site / Location',
                  hintText: 'All Sites / Locations',
                  prefixIcon: const Icon(Icons.location_on_outlined, size: 18),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('All Sites / Locations'),
                  ),
                  ...sites.map(
                    (s) => DropdownMenuItem<String>(
                      value: s,
                      child: Text(s, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedSite = val ?? '';
                  });
                },
              );

              if (isNarrow) {
                return Column(
                  children: [
                    deptDropdown,
                    const SizedBox(height: 10),
                    siteDropdown,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: deptDropdown),
                  const SizedBox(width: 12),
                  Expanded(child: siteDropdown),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('dialog_user_search_input'),
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by name, designation, or email...',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Eligible Users (${users.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: Color(0xFF475569),
                ),
              ),
              Row(
                children: [
                  if (_selectedUserIds.isNotEmpty)
                    Text(
                      '${_selectedUserIds.length} selected',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1565C0),
                      ),
                    ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    key: const Key('dialog_select_all_button'),
                    onPressed: selectableUsers.isEmpty
                        ? null
                        : () {
                            setState(() {
                              if (allSelectableSelected) {
                                for (final u in selectableUsers) {
                                  _selectedUserIds.remove(u.id);
                                  _selectedPeopleMap.remove(u.id);
                                }
                              } else {
                                for (final u in selectableUsers) {
                                  _selectedUserIds.add(u.id);
                                  _selectedPeopleMap[u.id] = u;
                                }
                              }
                            });
                          },
                    icon: Icon(
                      allSelectableSelected
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                      size: 14,
                      color: selectableUsers.isEmpty
                          ? Colors.grey
                          : const Color(0xFF1565C0),
                    ),
                    label: Text(
                      allSelectableSelected ? 'Deselect All' : 'Select All',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: selectableUsers.isEmpty
                            ? Colors.grey
                            : const Color(0xFF1565C0),
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: users.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.people_outline_rounded,
                            size: 40,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _selectedDept.isNotEmpty || _selectedSite.isNotEmpty
                                ? 'No eligible users found for the selected department and site.'
                                : 'No eligible users found matching your search.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: users.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      itemBuilder: (ctx, idx) {
                        final p = users[idx];
                        final isAlready =
                            widget.alreadyAssignedIds.contains(p.id);
                        final isSelected = _selectedUserIds.contains(p.id);

                        return Material(
                          color: isAlready
                              ? const Color(0xFFF8FAFC)
                              : isSelected
                                  ? const Color(0xFFEFF6FF)
                                  : Colors.white,
                          child: InkWell(
                            onTap: isAlready
                                ? null
                                : () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedUserIds.remove(p.id);
                                        _selectedPeopleMap.remove(p.id);
                                      } else {
                                        _selectedUserIds.add(p.id);
                                        _selectedPeopleMap[p.id] = p;
                                      }
                                    });
                                  },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Checkbox(
                                    key: Key('user_checkbox_${p.id}'),
                                    value: isAlready ? true : isSelected,
                                    onChanged: isAlready
                                        ? null
                                        : (val) {
                                            setState(() {
                                              if (val == true) {
                                                _selectedUserIds.add(p.id);
                                                _selectedPeopleMap[p.id] = p;
                                              } else {
                                                _selectedUserIds.remove(p.id);
                                                _selectedPeopleMap.remove(p.id);
                                              }
                                            });
                                          },
                                    activeColor: isAlready
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF1565C0),
                                  ),
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: isAlready
                                        ? const Color(0xFFCBD5E1)
                                        : const Color(0xFF1565C0),
                                    child: Text(
                                      p.name.isNotEmpty
                                          ? p.name[0].toUpperCase()
                                          : 'U',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                p.name,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                  color: isAlready
                                                      ? const Color(0xFF64748B)
                                                      : const Color(0xFF0F172A),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isAlready) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 1,
                                                ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      const Color(0xFFE2E8F0),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'Already Added',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF64748B),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          [
                                            if (p.designation.isNotEmpty)
                                              p.designation,
                                            if (p.department.isNotEmpty)
                                              p.department,
                                            if (p.site.isNotEmpty) p.site,
                                          ].join(' • '),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF64748B),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
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

  Widget _buildExistingUsersBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _selectedUserIds.isEmpty
                  ? 'No users selected'
                  : '${_selectedUserIds.length} user(s) selected',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _selectedUserIds.isEmpty
                    ? const Color(0xFF64748B)
                    : const Color(0xFF1565C0),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF475569),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            key: const Key('dialog_add_selected_users_button'),
            onPressed: _selectedUserIds.isEmpty
                ? null
                : () => Navigator.pop(
                      context,
                      _selectedPeopleMap.values.toList(),
                    ),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
            label: Text(
              _selectedUserIds.isEmpty
                  ? 'Add to Action'
                  : 'Add Selected Users (${_selectedUserIds.length})',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualFormTab(bool isEdit) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isEdit) ...[
              DropdownButtonFormField<Person>(
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Select existing ActionFlow person',
                  prefixIcon: Icon(Icons.person_search_rounded),
                ),
                items: widget.existingPeople
                    .where(
                      (p) =>
                          p.isActive && p.type == PersonType.internalUser,
                    )
                    .map(
                      (p) => DropdownMenuItem<Person>(
                        value: p,
                        child: Text('${p.name} (${p.designation})'),
                      ),
                    )
                    .toList(),
                onChanged: (selected) {
                  if (selected != null) {
                    choose(selected);
                  }
                },
              ),
              const SizedBox(height: 16),
            ],
            _dialogField(
              label: 'Full Name *',
              controller: name,
              hint: 'e.g. Rahul Sharma',
              required: true,
              prefixIcon: Icons.badge_outlined,
            ),
            const SizedBox(height: 14),
            _dialogField(
              label: 'Email *',
              controller: email,
              hint: 'e.g. rahul.sharma@sobha.com',
              required: true,
              prefixIcon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 14),
            _dialogField(
              label: 'Phone Number',
              controller: phone,
              hint: 'e.g. +91 98765 43210',
              prefixIcon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 14),
            _dialogField(
              label: 'Designation / Role',
              controller: designation,
              hint: 'e.g. HSE Officer',
              prefixIcon: Icons.work_outline_rounded,
            ),
            const SizedBox(height: 14),
            _dialogField(
              label: 'Department',
              controller: department,
              hint: 'e.g. HSE, Engineering, Civil',
              prefixIcon: Icons.domain_outlined,
            ),
            const SizedBox(height: 14),
            _dialogField(
              label: 'Project / Site',
              controller: site,
              hint: 'e.g. Site 1, Tower B',
              prefixIcon: Icons.location_on_outlined,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualFormBottomBar(bool isEdit) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF475569),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              final emailVal = email.text.trim();
              final phoneVal = phone.text.trim();

              final duplicate = MockPeopleStore.instance.findDuplicate(
                email: emailVal,
                phone: phoneVal,
                excludeId: isEdit ? widget.initialPerson?.personId : null,
              );

              if (duplicate != null) {
                final useExisting = await showDialog<dynamic>(
                  context: context,
                  builder: (ctx) =>
                      DuplicatePersonDialog(existingPerson: duplicate),
                );

                if (useExisting != null && mounted) {
                  Navigator.pop(context, duplicate);
                  return;
                } else {
                  return;
                }
              }

              if (isEdit && widget.initialPerson != null) {
                final updated = Person(
                  id: widget.initialPerson!.personId,
                  name: name.text.trim(),
                  email: emailVal,
                  phone: phoneVal,
                  designation: designation.text.trim(),
                  department: department.text.trim(),
                  site: site.text.trim(),
                  type: PersonType.internalUser,
                  isActive: true,
                );
                Navigator.pop(context, updated);
                return;
              }

              final newPerson = Person(
                id: 'AFU-${DateTime.now().millisecondsSinceEpoch}',
                name: name.text.trim(),
                email: emailVal,
                phone: phoneVal,
                designation: designation.text.trim(),
                department: department.text.trim(),
                site: site.text.trim(),
                type: PersonType.internalUser,
                isActive: true,
              );
              MockPeopleStore.instance.add(newPerson);
              if (context.mounted) {
                Navigator.pop(context, newPerson);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
            ),
            child: const Text('Save Person'),
          ),
        ],
      ),
    );
  }

  Widget _dialogField({
    required String label,
    required TextEditingController controller,
    required String hint,
    IconData? prefixIcon,
    bool required = false,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: required
              ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
              : null,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 18) : null,
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
          ),
        ),
      ],
    );
  }
}

