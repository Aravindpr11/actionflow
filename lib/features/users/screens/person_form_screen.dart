import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/mock_people_store.dart';
import '../models/person.dart';
import '../models/team.dart';
import '../widgets/duplicate_person_dialog.dart';

class PersonFormScreen extends StatefulWidget {
  const PersonFormScreen({
    this.person,
    this.availableDepartments,
    this.availableSites,
    this.availableTeams,
    super.key,
  });

  final Person? person;
  final List<Map<String, dynamic>>? availableDepartments;
  final List<Map<String, dynamic>>? availableSites;
  final List<Map<String, dynamic>>? availableTeams;

  @override
  State<PersonFormScreen> createState() => _PersonFormScreenState();
}

class _PersonFormScreenState extends State<PersonFormScreen> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController email;
  late final TextEditingController phone;
  late final TextEditingController designation;
  late final TextEditingController department;
  late final TextEditingController site;
  late final TextEditingController company;
  late final TextEditingController notes;

  late PersonType type;
  late bool active;
  late UserRole role;
  late Set<String> teamIds;
  String? selectedDeptId;
  String? selectedSiteId;
  String? selectedRoleId;

  // Manager multiple scopes state
  late List<ManagerScopeItem> managerScopes;
  String? newScopeDeptId;
  String? newScopeSiteId;
  String? managerScopeError;
  int _scopeAddCounter = 0;



  @override
  void initState() {
    super.initState();
    final person = widget.person;
    name = TextEditingController(text: person?.name);
    email = TextEditingController(text: person?.email);
    phone = TextEditingController(text: person?.phone);
    designation = TextEditingController(text: person?.designation);
    department = TextEditingController(text: person?.department);
    site = TextEditingController(text: person?.site);
    company = TextEditingController(text: person?.company);
    notes = TextEditingController(text: person?.notes);
    type = person?.type ?? PersonType.internalUser;
    active = person?.isActive ?? true;
    role = person?.role ?? UserRole.actionOwnerWorker;
    teamIds = {...?person?.teamIds};
    selectedDeptId = person?.departmentId;
    selectedSiteId = person?.siteId;
    selectedRoleId = person?.roleId;

    // Resolve initial manager scopes
    managerScopes = List<ManagerScopeItem>.from(person?.managerScopes ?? []);



    // If departmentId was null but department name exists, try to match
    if (selectedDeptId == null &&
        department.text.isNotEmpty &&
        widget.availableDepartments != null) {
      for (final d in widget.availableDepartments!) {
        if (d['name'] == department.text) {
          selectedDeptId = d['id']?.toString();
          break;
        }
      }
    } else if (selectedDeptId != null &&
        department.text.isEmpty &&
        widget.availableDepartments != null) {
      for (final d in widget.availableDepartments!) {
        if (d['id']?.toString() == selectedDeptId) {
          department.text = d['name']?.toString() ?? '';
          break;
        }
      }
    }

    // If siteId was null but site name exists, try to match
    if (selectedSiteId == null &&
        site.text.isNotEmpty &&
        widget.availableSites != null) {
      for (final s in widget.availableSites!) {
        if (s['name'] == site.text) {
          selectedSiteId = s['id']?.toString();
          break;
        }
      }
    } else if (selectedSiteId != null &&
        site.text.isEmpty &&
        widget.availableSites != null) {
      for (final s in widget.availableSites!) {
        if (s['id']?.toString() == selectedSiteId) {
          site.text = s['name']?.toString() ?? '';
          break;
        }
      }
    }

    // Fallback: If manager has 0 managerScopes in person object but has department and site
    if (role == UserRole.departmentManager &&
        managerScopes.isEmpty &&
        selectedDeptId != null &&
        selectedDeptId!.isNotEmpty) {
      String dName = department.text;
      if (widget.availableDepartments != null) {
        for (final d in widget.availableDepartments!) {
          if (d['id']?.toString() == selectedDeptId) {
            dName = d['name']?.toString() ?? department.text;
            break;
          }
        }
      }
      String sName = site.text;
      if (widget.availableSites != null) {
        for (final s in widget.availableSites!) {
          if (s['id']?.toString() == selectedSiteId) {
            sName = s['name']?.toString() ?? site.text;
            break;
          }
        }
      }
      managerScopes.add(
        ManagerScopeItem(
          departmentId: selectedDeptId!,
          departmentName: dName.isNotEmpty ? dName : 'Primary Department',
          siteId: selectedSiteId ?? '',
          siteName: sName.isNotEmpty ? sName : 'Primary Site',
        ),
      );
    }


  }

  @override
  void dispose() {
    for (final controller in [
      name,
      email,
      phone,
      designation,
      department,
      site,
      company,
      notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addManagerScope() {
    setState(() {
      managerScopeError = null;
      if (newScopeDeptId == null || newScopeDeptId!.isEmpty) {
        managerScopeError = 'Please select a Department for the new scope.';
        return;
      }
      if (newScopeSiteId == null || newScopeSiteId!.isEmpty) {
        managerScopeError = 'Please select a Site for the new scope.';
        return;
      }

      // Check duplicate scope
      final isDuplicate = managerScopes.any(
        (s) => s.departmentId == newScopeDeptId && s.siteId == newScopeSiteId,
      );
      if (isDuplicate) {
        managerScopeError = 'This Department + Site scope has already been added to the Manager.';
        return;
      }

      String dName = '';
      if (widget.availableDepartments != null) {
        for (final d in widget.availableDepartments!) {
          if (d['id']?.toString() == newScopeDeptId) {
            dName = d['name']?.toString() ?? '';
            break;
          }
        }
      }

      String sName = '';
      if (widget.availableSites != null) {
        for (final s in widget.availableSites!) {
          if (s['id']?.toString() == newScopeSiteId) {
            sName = s['name']?.toString() ?? '';
            break;
          }
        }
      }

      managerScopes.add(
        ManagerScopeItem(
          departmentId: newScopeDeptId!,
          departmentName: dName.isNotEmpty ? dName : 'Department',
          siteId: newScopeSiteId!,
          siteName: sName.isNotEmpty ? sName : 'Site',
        ),
      );

      newScopeDeptId = null;
      newScopeSiteId = null;
      _scopeAddCounter++;
    });
  }

  void _removeManagerScope(int index) {
    setState(() {
      managerScopes.removeAt(index);
      if (managerScopes.isEmpty) {
        managerScopeError =
            'A Manager must have at least one Department + Site scope.';
      } else {
        managerScopeError = null;
      }
    });
  }


  Future<void> save() async {
    final isInternal = type == PersonType.internalUser;
    final isManager = isInternal && role == UserRole.departmentManager;

    // Manager validation: must have at least 1 scope
    if (isManager) {
      if (managerScopes.isEmpty) {
        setState(() {
          managerScopeError =
              'A Manager must have at least one Department + Site scope.';
        });
        return;
      }

      final seen = <String>{};
      for (final s in managerScopes) {
        final key = '${s.departmentId}::${s.siteId}';
        if (!seen.add(key)) {
          setState(() {
            managerScopeError =
                'Duplicate scope detected: ${s.displayName}. Each scope must be unique.';
          });
          return;
        }
      }
    }

    // Staff validation: must have at least 1 scope

    // Validate form (team selection is optional for staff and managers)
    if (!formKey.currentState!.validate()) {
      setState(() {});
      return;
    }

    final trimmedEmail = email.text.trim();
    final trimmedPhone = phone.text.trim();

    // Check for duplicate by email or phone
    final duplicate = MockPeopleStore.instance.findDuplicate(
      email: trimmedEmail,
      phone: trimmedPhone,
      excludeId: widget.person?.id,
    );

    if (duplicate != null) {
      final chosen = await showDialog<Person>(
        context: context,
        builder: (context) => DuplicatePersonDialog(existingPerson: duplicate),
      );
      if (!mounted) return;
      if (chosen != null) {
        Navigator.of(context).pop(chosen);
      }
      return;
    }

    final existing = widget.person;

    // Determine primary department and site for profile column backwards-compatibility
    final primaryDeptId = isManager && managerScopes.isNotEmpty
        ? managerScopes.first.departmentId
        : selectedDeptId;
    final primaryDeptName = isManager && managerScopes.isNotEmpty
        ? managerScopes.first.departmentName
        : department.text.trim();
    final primarySiteId = isManager && managerScopes.isNotEmpty
        ? managerScopes.first.siteId
        : selectedSiteId;
    final primarySiteName = isManager && managerScopes.isNotEmpty
        ? managerScopes.first.siteName
        : site.text.trim();

    Navigator.of(context).pop(
      Person(
        id:
            existing?.id ??
            '${type == PersonType.internalUser ? 'AFU' : 'EXT'}-${DateTime.now().millisecondsSinceEpoch % 1000}',
        name: name.text.trim(),
        email: trimmedEmail,
        phone: trimmedPhone,
        designation: designation.text.trim(),
        department: isInternal ? primaryDeptName : '',
        site: primarySiteName,
        company: type == PersonType.externalWorker ? company.text.trim() : '',
        notes: type == PersonType.externalWorker ? notes.text.trim() : '',
        type: type,
        isActive: active,
        role: isInternal ? role : UserRole.actionOwnerWorker,
        teamIds: isInternal ? teamIds.toList() : const [],
        managerScopes: isManager ? managerScopes : const [],
        departmentId: primaryDeptId,
        siteId: primarySiteId,
        roleId: selectedRoleId,
        organizationId: widget.person?.organizationId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final external = type == PersonType.externalWorker;
    final isManager = !external && role == UserRole.departmentManager;
    final isStaff = !external && role == UserRole.actionOwnerWorker;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.headerBg(context),
        foregroundColor: AppTheme.textPrimary(context),
        elevation: 0,
        title: Text(
          existingTitle,
          style: TextStyle(
            color: AppTheme.textPrimary(context),
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: AppTheme.cardBorder(context),
          ),
        ),
        actions: [
          TextButton(onPressed: save, child: const Text('SAVE PERSON')),
        ],
      ),
      body: Form(
        key: formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _panel('PERSON TYPE', [
                  SegmentedButton<PersonType>(
                    segments: const [
                      ButtonSegment(
                        value: PersonType.internalUser,
                        label: Text('Internal ActionFlow User'),
                        icon: Icon(Icons.badge_outlined),
                      ),
                      ButtonSegment(
                        value: PersonType.externalWorker,
                        label: Text('External Staff'),
                        icon: Icon(Icons.engineering_outlined),
                      ),
                    ],
                    selected: {type},
                    onSelectionChanged: widget.person != null
                        ? null
                        : (value) => setState(() => type = value.first),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    external
                        ? 'No ActionFlow account. Used as an external action owner.'
                        : 'Has an ActionFlow account and can sign in.',
                    style: TextStyle(color: AppTheme.textSecondary(context)),
                  ),
                  if (!external) ...[
                    DropdownButtonFormField<UserRole>(
                      isExpanded: true,
                      dropdownColor: AppTheme.cardBg(context),
                      style: TextStyle(color: AppTheme.textPrimary(context)),
                      initialValue: role,
                      decoration: InputDecoration(
                        labelText: 'Role *',
                        labelStyle: TextStyle(
                          color: AppTheme.textSecondary(context),
                        ),
                        filled: true,
                        fillColor: AppTheme.inputFill(context),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: AppTheme.inputBorder(context),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: AppTheme.primaryAccent(context),
                            width: 2,
                          ),
                        ),
                      ),
                      items: UserRole.values
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(
                                item.label,
                                style: TextStyle(
                                  color: AppTheme.textPrimary(context),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => role = value!),
                    ),
                  ],
                ]),
                _panel('PROFILE', [
                  _field('Name *', name),
                  _field(
                    'Email *',
                    email,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  _field('Phone', phone, keyboardType: TextInputType.phone),
                  _field('Designation *', designation),
                ]),

                // External Staff Panel
                if (external)
                  _panel('EXTERNAL STAFF DETAILS', [
                    _field('Company / Organization *', company),
                    _field('Project / Site', site),
                    _field('Notes', notes, maxLines: 2),
                    _buildActiveSwitch(),
                  ]),

                // Manager Multiple Scopes Section
                if (isManager) ...[
                  _buildManagerScopesPanel(),
                  _panel('TEAM MEMBERSHIPS (OPTIONAL)', [
                    _managerTeamSelector(),
                    _buildActiveSwitch(),
                  ]),
                ],

                // Staff (Action Owner / Worker) Single Scope Section
                if (isStaff) ...[
                  _panel('ORGANIZATION ASSIGNMENT', [
                    if (widget.availableDepartments != null &&
                        widget.availableDepartments!.isNotEmpty)
                      _dropdownField(
                        label: 'Department *',
                        value:
                            widget.availableDepartments!.any(
                              (d) => d['name'] == department.text,
                            )
                            ? department.text
                            : null,
                        items: widget.availableDepartments!
                            .map((d) => d['name'] as String)
                            .toList(),
                        onChanged: (val) {
                          setState(() {
                            department.text = val ?? '';
                            Map<dynamic, dynamic>? match;
                            for (final d in widget.availableDepartments!) {
                              if (d['name'] == val) {
                                match = d;
                                break;
                              }
                            }
                            selectedDeptId = match?['id']?.toString();
                          });
                        },
                      )
                    else
                      _field('Department', department),
                    if (widget.availableSites != null &&
                        widget.availableSites!.isNotEmpty)
                      _dropdownField(
                        label: 'Site *',
                        value:
                            widget.availableSites!.any(
                              (s) => s['name'] == site.text,
                            )
                            ? site.text
                            : null,
                        items: widget.availableSites!
                            .map((s) => s['name'] as String)
                            .toList(),
                        onChanged: (val) {
                          setState(() {
                            site.text = val ?? '';
                            selectedSiteId = null;
                            if (widget.availableSites != null) {
                              for (final s in widget.availableSites!) {
                                if (s['name'] == val) {
                                  selectedSiteId = s['id']?.toString();
                                  break;
                                }
                              }
                            }
                          });
                        },
                      )
                    else
                      _field('Site', site),
                  ]),
                  _panel('TEAM ASSIGNMENT (OPTIONAL)', [
                    _staffTeamSelector(),
                    _buildActiveSwitch(),
                  ]),
                ],

                // Admin Assignment Section
                if (!external && !isManager && !isStaff)
                  _panel('ADMIN ACCESS', [
                    _field('Site', site),
                    _managerTeamSelector(),
                    _buildActiveSwitch(),
                  ]),

                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: save,
                  icon: const Icon(Icons.save_rounded),
                  label: Text(
                    widget.person == null ? 'Add Person' : 'Save Changes',
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveSwitch() {
    return Material(
      color: Colors.transparent,
      child: SwitchListTile.adaptive(
        title: Text(
          'Active person',
          style: TextStyle(color: AppTheme.textPrimary(context)),
        ),
        value: active,
        onChanged: (value) => setState(() => active = value),
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  /// Manager Access Scopes panel allowing multiple Department + Site management scopes
  Widget _buildManagerScopesPanel() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hub_rounded, size: 18, color: Color(0xFF0284C7)),
              const SizedBox(width: 8),
              Text(
                'MANAGER ACCESS SCOPES',
                style: TextStyle(
                  color: AppTheme.primaryAccent(context),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Managers oversee actions across one or more Department + Site management scopes. At least one scope is required.',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary(context),
            ),
          ),
          if (managerScopeError != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFEF4444)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 16,
                    color: Color(0xFFEF4444),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      managerScopeError!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),

          // Scopes List / Table
          if (managerScopes.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.containerBg(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cardBorder(context)),
              ),
              child: Text(
                'No scopes added yet. Use the selector below to add at least one Department + Site scope.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMuted(context),
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: AppTheme.containerBg(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cardBorder(context)),
              ),
              child: Column(
                children: [
                  // Table Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppTheme.cardBorder(context)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: Text(
                            'DEPARTMENT',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 5,
                          child: Text(
                            'SITE / LOCATION',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: Center(
                            child: Text(
                              'ACTION',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textSecondary(context),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Table Rows
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: managerScopes.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      thickness: 1,
                      color: AppTheme.cardBorder(context),
                    ),
                    itemBuilder: (context, index) {
                      final scope = managerScopes[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 5,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.business_rounded,
                                    size: 15,
                                    color: Color(0xFF0284C7),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      scope.departmentName,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textPrimary(context),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 5,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.location_on_outlined,
                                    size: 15,
                                    color: Color(0xFF10B981),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      scope.siteName,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.textPrimary(context),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 40,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.remove_circle_outline_rounded,
                                  size: 18,
                                  color: Color(0xFFDC2626),
                                ),
                                tooltip: 'Remove Scope',
                                onPressed: () => _removeManagerScope(index),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),
          Text(
            'Add Scope Pair',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),

          // Add Scope Form Row
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 600;

              final activeDepts = (widget.availableDepartments ?? [])
                  .where(
                    (d) => d['status'] != 'Inactive' && d['is_active'] != false,
                  )
                  .toList();
              final activeSites = (widget.availableSites ?? [])
                  .where(
                    (s) => s['status'] != 'Inactive' && s['is_active'] != false,
                  )
                  .toList();

              final deptWidget = DropdownButtonFormField<String>(
                key: ValueKey('scope_dept_$_scopeAddCounter'),
                initialValue: newScopeDeptId,
                isExpanded: true,
                dropdownColor: AppTheme.cardBg(context),
                style: TextStyle(color: AppTheme.textPrimary(context)),
                decoration: InputDecoration(
                  labelText: 'Department',
                  labelStyle: TextStyle(color: AppTheme.textSecondary(context)),
                  filled: true,
                  fillColor: AppTheme.inputFill(context),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: AppTheme.inputBorder(context),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: AppTheme.primaryAccent(context),
                      width: 2,
                    ),
                  ),
                ),
                items: activeDepts
                    .map(
                      (d) => DropdownMenuItem(
                        value: d['id']?.toString(),
                        child: Text(
                          d['name']?.toString() ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) => setState(() => newScopeDeptId = val),
              );

              final siteWidget = DropdownButtonFormField<String>(
                key: ValueKey('scope_site_$_scopeAddCounter'),
                initialValue: newScopeSiteId,
                isExpanded: true,
                dropdownColor: AppTheme.cardBg(context),
                style: TextStyle(color: AppTheme.textPrimary(context)),
                decoration: InputDecoration(
                  labelText: 'Site / Location',
                  labelStyle: TextStyle(color: AppTheme.textSecondary(context)),
                  filled: true,
                  fillColor: AppTheme.inputFill(context),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: AppTheme.inputBorder(context),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: AppTheme.primaryAccent(context),
                      width: 2,
                    ),
                  ),
                ),
                items: activeSites
                    .map(
                      (s) => DropdownMenuItem(
                        value: s['id']?.toString(),
                        child: Text(
                          s['name']?.toString() ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) => setState(() => newScopeSiteId = val),
              );

              final addBtn = ElevatedButton.icon(
                onPressed: _addManagerScope,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Scope'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              );

              if (isNarrow) {
                return Column(
                  children: [
                    deptWidget,
                    const SizedBox(height: 10),
                    siteWidget,
                    const SizedBox(height: 10),
                    SizedBox(width: double.infinity, child: addBtn),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(flex: 5, child: deptWidget),
                  const SizedBox(width: 10),
                  Expanded(flex: 5, child: siteWidget),
                  const SizedBox(width: 10),
                  addBtn,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String get existingTitle =>
      widget.person == null ? 'Add Person' : 'Edit Person';

  /// Teams selector for Staff (Optional, supports cross-department teams across the organization)
  Widget _staffTeamSelector() {
    final selectableTeams =
        widget.availableTeams ?? MockPeopleStore.instance.teams;

    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Department / Team memberships (Optional)',
        labelStyle: TextStyle(color: AppTheme.textSecondary(context)),
        filled: true,
        fillColor: AppTheme.inputFill(context),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.inputBorder(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppTheme.primaryAccent(context),
            width: 2,
          ),
        ),
      ),
      child: selectableTeams.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'No teams configured in the organization.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 4,
              children: selectableTeams.map((teamItem) {
                final id = (teamItem is Map)
                    ? teamItem['id'].toString()
                    : (teamItem as Team).id;
                final label = (teamItem is Map)
                    ? (teamItem['name']?.toString() ??
                          teamItem['dept']?.toString() ??
                          '')
                    : (teamItem as Team).department;
                return FilterChip(
                  backgroundColor: AppTheme.containerBg(context),
                  label: Text(
                    label,
                    style: TextStyle(
                      color: teamIds.contains(id)
                          ? Colors.white
                          : AppTheme.textPrimary(context),
                    ),
                  ),
                  selected: teamIds.contains(id),
                  onSelected: (selected) => setState(
                    () => selected ? teamIds.add(id) : teamIds.remove(id),
                  ),
                );
              }).toList(),
            ),
    );
  }

  /// Teams selector for Managers (Optional, 0 or more teams allowed)
  Widget _managerTeamSelector() {
    final selectableTeams =
        widget.availableTeams ?? MockPeopleStore.instance.teams;

    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Team memberships (Optional)',
        labelStyle: TextStyle(color: AppTheme.textSecondary(context)),
        filled: true,
        fillColor: AppTheme.inputFill(context),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.inputBorder(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppTheme.primaryAccent(context),
            width: 2,
          ),
        ),
      ),
      child: selectableTeams.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'No teams configured in the organization.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 4,
              children: selectableTeams.map((teamItem) {
                final id = (teamItem is Map)
                    ? teamItem['id'].toString()
                    : (teamItem as Team).id;
                final label = (teamItem is Map)
                    ? (teamItem['name']?.toString() ??
                          teamItem['dept']?.toString() ??
                          '')
                    : (teamItem as Team).department;
                return FilterChip(
                  backgroundColor: AppTheme.containerBg(context),
                  label: Text(
                    label,
                    style: TextStyle(
                      color: teamIds.contains(id)
                          ? Colors.white
                          : AppTheme.textPrimary(context),
                    ),
                  ),
                  selected: teamIds.contains(id),
                  onSelected: (selected) => setState(
                    () => selected ? teamIds.add(id) : teamIds.remove(id),
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _dropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: AppTheme.cardBg(context),
      style: TextStyle(color: AppTheme.textPrimary(context)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppTheme.textSecondary(context)),
        filled: true,
        fillColor: AppTheme.inputFill(context),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.inputBorder(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppTheme.primaryAccent(context),
            width: 2,
          ),
        ),
      ),
      items: items
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(
                item,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppTheme.textPrimary(context)),
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _panel(String title, List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppTheme.cardBg(context),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.cardBorder(context)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppTheme.primaryAccent(context),
            fontWeight: FontWeight.bold,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 14,
            runSpacing: 14,
            children: children
                .map(
                  (child) => SizedBox(
                    width: constraints.maxWidth >= 650
                        ? (constraints.maxWidth - 14) / 2
                        : constraints.maxWidth,
                    child: child,
                  ),
                )
                .toList(),
          ),
        ),
      ],
    ),
  );

  Widget _field(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) => TextFormField(
    controller: controller,
    maxLines: maxLines,
    keyboardType: keyboardType,
    style: TextStyle(color: AppTheme.textPrimary(context)),
    validator: label.endsWith('*')
        ? (value) => value == null || value.trim().isEmpty
              ? 'Please enter $label'
              : null
        : null,
    decoration: InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: AppTheme.textSecondary(context)),
      filled: true,
      fillColor: AppTheme.inputFill(context),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppTheme.inputBorder(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: AppTheme.primaryAccent(context),
          width: 2,
        ),
      ),
    ),
  );
}
