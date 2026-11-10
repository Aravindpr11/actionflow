import 'package:flutter/material.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/action_service.dart';
import '../../../services/user_service.dart';
import '../../dashboard/manager_dashboard/data/mock_action_store.dart';
import '../../dashboard/manager_dashboard/models/external_recipient.dart';
import '../../dashboard/manager_dashboard/models/manager_context.dart';
import '../data/mock_people_store.dart';
import '../models/person.dart';
import 'person_form_screen.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({
    super.key,
    this.isEmbedded = false,
    this.onClose,
    this.managerContext,
    this.userService,
    this.actionService,
  });

  final bool isEmbedded;
  final VoidCallback? onClose;
  final ManagerContext? managerContext;
  final UserService? userService;
  final ActionService? actionService;

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final store = MockPeopleStore.instance;
  final searchController = TextEditingController();
  String typeFilter = 'All Types';
  String statusFilter = 'All Statuses';
  String departmentFilter = 'All Departments';
  String siteFilter = 'All Sites';

  bool _isLoading = false;
  String? _errorMessage;
  List<Person> _realPeople = [];

  bool get isManagerMode => widget.managerContext != null;

  @override
  void initState() {
    super.initState();
    if (isManagerMode) {
      _loadManagerDirectory();
    }
  }

  @override
  void didUpdateWidget(covariant UsersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.managerContext != oldWidget.managerContext && isManagerMode) {
      _loadManagerDirectory();
    }
  }

  Future<void> _loadManagerDirectory() async {
    final ctx = widget.managerContext;
    if (ctx == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final uService = widget.userService ?? UserService.instance;
      final aService = widget.actionService ?? ActionService.instance;

      List<Person> internalPeople = [];
      try {
        internalPeople = await uService.fetchManagerDirectory(managerContext: ctx);
      } catch (e) {
        if (widget.userService == null && !SupabaseConfig.isInitialized) {
          internalPeople = MockPeopleStore.instance.people
              .where((p) => p.type == PersonType.internalUser)
              .toList();
        } else {
          rethrow;
        }
      }

      List<ExternalRecipient> externalRecipients = [];
      try {
        externalRecipients = await aService.fetchExternalRecipients(ctx.organizationId);
      } catch (e) {
        debugPrint('[UsersScreen] Error fetching external recipients: $e');
      }

      final externalPeople = externalRecipients.map((ext) => Person(
        id: ext.id,
        name: ext.fullName,
        email: ext.email,
        phone: ext.phone,
        designation: ext.companyName.isNotEmpty
            ? 'External Contact (${ext.companyName})'
            : 'External Contact',
        type: PersonType.externalWorker,
        isActive: ext.isActive,
        company: ext.companyName,
        organizationId: ext.organizationId,
      )).toList();

      if (!SupabaseConfig.isInitialized && widget.userService == null) {
        for (final p in MockPeopleStore.instance.people.where(
          (p) => p.type == PersonType.externalWorker,
        )) {
          if (!externalPeople.any(
            (e) => e.email.toLowerCase() == p.email.toLowerCase(),
          )) {
            externalPeople.add(p);
          }
        }
      }

      final combined = <Person>[...internalPeople];
      for (final ext in externalPeople) {
        if (!combined.any(
          (p) =>
              p.id == ext.id ||
              p.email.toLowerCase() == ext.email.toLowerCase(),
        )) {
          combined.add(ext);
        }
      }

      if (mounted) {
        setState(() {
          _realPeople = combined;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  List<Person> get peopleSource {
    if (isManagerMode) {
      return _realPeople;
    }
    final externalFromActionStore = MockActionStore.instance.externalRecipients.map(
      (ext) => Person(
        id: ext.id,
        name: ext.fullName,
        email: ext.email,
        phone: ext.phone,
        designation: ext.companyName.isNotEmpty
            ? 'External Contact (${ext.companyName})'
            : 'External Contact',
        type: PersonType.externalWorker,
        isActive: ext.isActive,
        company: ext.companyName,
        organizationId: ext.organizationId,
      ),
    ).toList();

    final combined = List<Person>.from(store.people);
    for (final ext in externalFromActionStore) {
      if (!combined.any(
        (p) =>
            p.id == ext.id ||
            p.email.toLowerCase() == ext.email.toLowerCase(),
      )) {
        combined.add(ext);
      }
    }
    return combined;
  }

  List<String> get availableDepartments {
    final ctx = widget.managerContext;
    if (ctx != null && ctx.hasScopes) {
      final names = ctx.scopedDepartmentNames;
      return ['All Departments', ...names];
    }
    final set = <String>{};
    for (final p in peopleSource) {
      if (p.department.trim().isNotEmpty) {
        set.add(p.department.trim());
      }
    }
    final list = set.toList()..sort();
    return ['All Departments', ...list];
  }

  List<String> get availableSites {
    final ctx = widget.managerContext;
    if (ctx != null && ctx.hasScopes) {
      final names = ctx.permittedSiteNamesForDepartmentName(departmentFilter);
      return ['All Sites', ...names];
    }
    final set = <String>{};
    for (final p in peopleSource) {
      if (p.site.trim().isNotEmpty) {
        set.add(p.site.trim());
      }
    }
    final list = set.toList()..sort();
    return ['All Sites', ...list];
  }

  List<Person> get visiblePeople {
    final query = searchController.text.trim().toLowerCase();
    return peopleSource.where((person) {
      final searchable = [
        person.name,
        person.email,
        person.phone,
        person.designation,
        person.company,
        person.department,
        person.site,
        person.id,
        person.roleLabel,
      ].join(' ').toLowerCase();
      final typeMatches =
          typeFilter == 'All Types' ||
          (typeFilter == 'Internal'
              ? person.type == PersonType.internalUser
              : person.type == PersonType.externalWorker);
      final statusMatches =
          statusFilter == 'All Statuses' ||
          (statusFilter == 'Active' ? person.isActive : !person.isActive);
      final departmentMatches =
          departmentFilter == 'All Departments' ||
          person.department.toLowerCase() == departmentFilter.toLowerCase();
      final siteMatches =
          siteFilter == 'All Sites' ||
          person.site.toLowerCase() == siteFilter.toLowerCase();
      return (query.isEmpty || searchable.contains(query)) &&
          typeMatches &&
          statusMatches &&
          departmentMatches &&
          siteMatches;
    }).toList();
  }

  Future<void> addPerson() async {
    final person = await Navigator.of(
      context,
    ).push<Person>(MaterialPageRoute(builder: (_) => const PersonFormScreen()));
    if (person != null && mounted) {
      store.addWithTeamNotifications(person);
      setState(() {});
    }
  }

  Future<void> editPerson(Person person) async {
    if (isManagerMode) {
      showDetails(person);
      return;
    }
    final updated = await Navigator.of(context).push<Person>(
      MaterialPageRoute(builder: (_) => PersonFormScreen(person: person)),
    );
    if (updated != null && mounted) {
      store.update(updated);
      if (SupabaseConfig.isInitialized) {
        try {
          await (widget.userService ?? UserService.instance).updateUser(
            organizationId: updated.organizationId ?? '',
            person: updated,
          );
        } catch (e) {
          debugPrint('[UsersScreen] updateUser note: $e');
        }
      }
      setState(() {});
    }
  }

  void showDetails(Person person) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: _PersonDetails(
            person: person,
            isManagerMode: isManagerMode,
            onEdit: () {
              Navigator.pop(context);
              editPerson(person);
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final people = visiblePeople;
    return Scaffold(
      backgroundColor: widget.isEmbedded
          ? Colors.transparent
          : AppTheme.scaffoldBg(context),
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              backgroundColor: AppTheme.headerBg(context),
              foregroundColor: AppTheme.textPrimary(context),
              elevation: 0,
              title: Text(
                'People / Staff',
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
                if (!isManagerMode)
                  TextButton.icon(
                    onPressed: addPerson,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Add Person'),
                  ),
              ],
            ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1250),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _intro(),
              const SizedBox(height: 16),
              _filters(),
              const SizedBox(height: 16),
              if (_isLoading)
                _loadingState()
              else if (_errorMessage != null)
                _errorState()
              else if (people.isEmpty)
                _emptyState()
              else
                LayoutBuilder(
                  builder: (context, constraints) => constraints.maxWidth >= 850
                      ? _desktopTable(people)
                      : _mobileList(people),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: (!widget.isEmbedded && !isManagerMode)
          ? FloatingActionButton.extended(
              onPressed: addPerson,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add Person'),
            )
          : null,
    );
  }

  Widget _loadingState() => Container(
    padding: const EdgeInsets.all(40),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppTheme.cardBg(context),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppTheme.cardBorder(context)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(
            AppTheme.primaryAccent(context),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Loading Staff Directory...',
          style: TextStyle(
            color: AppTheme.textSecondary(context),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _errorState() => Container(
    padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(
      color: AppTheme.cardBg(context),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFEF4444)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.error_outline_rounded,
          color: Color(0xFFEF4444),
          size: 48,
        ),
        const SizedBox(height: 12),
        Text(
          'Failed to load directory',
          style: TextStyle(
            color: AppTheme.textPrimary(context),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _errorMessage ?? 'Unknown error occurred',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary(context)),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _loadManagerDirectory,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      ],
    ),
  );

  Widget _emptyState() => Container(
    padding: const EdgeInsets.all(40),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppTheme.cardBg(context),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppTheme.cardBorder(context)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.people_outline_rounded,
          size: 54,
          color: AppTheme.textMuted(context),
        ),
        const SizedBox(height: 14),
        Text(
          'No Staff Members Found',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary(context),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isManagerMode
              ? 'No staff members match the selected filters within your managed scopes.'
              : 'No staff members currently in directory.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary(context)),
        ),
      ],
    ),
  );

  Widget _intro() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFF1565C0),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      runSpacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'People / Staff Directory',
              style: TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isManagerMode
                  ? '${peopleSource.length} staff members available within your permitted scopes'
                  : '${peopleSource.length} people available for HSSE action assignment',
              style: const TextStyle(color: Color(0xFFDCEBFA)),
            ),
          ],
        ),
        const Icon(Icons.groups_rounded, color: Colors.white, size: 46),
      ],
    ),
  );

  Widget _filters() => _Panel(
    title: 'Find a person',
    child: LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
            width: _width(constraints.maxWidth, 260),
            child: TextField(
              controller: searchController,
              style: TextStyle(color: AppTheme.textPrimary(context)),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Search name, email, phone, designation...',
                labelStyle: TextStyle(color: AppTheme.textSecondary(context)),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: AppTheme.textSecondary(context),
                ),
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
            ),
          ),
          _select(
            'Person Type',
            typeFilter,
            ['All Types', 'Internal', 'External'],
            (value) => setState(() => typeFilter = value ?? 'All Types'),
            width: _width(constraints.maxWidth, 150),
          ),
          _select('Department', departmentFilter, availableDepartments, (
            value,
          ) {
            setState(() {
              departmentFilter = value ?? 'All Departments';
              if (isManagerMode && !availableSites.contains(siteFilter)) {
                siteFilter = 'All Sites';
              }
            });
          }, width: _width(constraints.maxWidth, 165)),
          _select(
            'Site',
            siteFilter,
            availableSites,
            (value) => setState(() => siteFilter = value ?? 'All Sites'),
            width: _width(constraints.maxWidth, 165),
          ),
          _select(
            'Status',
            statusFilter,
            ['All Statuses', 'Active', 'Inactive'],
            (value) => setState(() => statusFilter = value ?? 'All Statuses'),
            width: _width(constraints.maxWidth, 140),
          ),
        ],
      ),
    ),
  );

  Widget _desktopTable(List<Person> people) => _Panel(
    title: 'Directory',
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(AppTheme.containerBg(context)),
        columns: [
          DataColumn(
            label: Text(
              'Person',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ),
          DataColumn(
            label: Text(
              'Type',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ),
          DataColumn(
            label: Text(
              'Contact',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ),
          DataColumn(
            label: Text(
              'Role / Teams',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ),
          DataColumn(
            label: Text(
              'Status',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ),
          DataColumn(
            label: Text(
              'Actions',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ),
        ],
        rows: people
            .map(
              (person) => DataRow(
                cells: [
                  DataCell(
                    InkWell(
                      onTap: () => showDetails(person),
                      child: _personCell(person),
                    ),
                  ),
                  DataCell(_typeBadge(person)),
                  DataCell(
                    Text(
                      '${person.email}\n${person.phone}',
                      style: TextStyle(color: AppTheme.textPrimary(context)),
                    ),
                  ),
                  DataCell(
                    Text(
                      person.type == PersonType.internalUser
                          ? '${person.roleLabel}\n${_formatTeams(person)}'
                          : (person.company.isNotEmpty
                                ? person.company
                                : 'External Contact'),
                      style: TextStyle(color: AppTheme.textPrimary(context)),
                    ),
                  ),
                  DataCell(_statusBadge(person)),
                  DataCell(
                    IconButton(
                      onPressed: () => editPerson(person),
                      icon: Icon(
                        isManagerMode
                            ? Icons.visibility_rounded
                            : Icons.edit_rounded,
                        color: AppTheme.textSecondary(context),
                      ),
                      tooltip: isManagerMode
                          ? 'View staff details'
                          : 'Edit person',
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    ),
  );

  String _formatTeams(Person person) {
    if (person.teamNames.isNotEmpty) {
      return person.teamNames.join(', ');
    }
    if (person.teamIds.isEmpty) return 'No teams assigned';
    if (!isManagerMode) {
      return person.teamIds
          .map((id) {
            try {
              return store.teams.firstWhere((t) => t.id == id).department;
            } catch (_) {
              return id;
            }
          })
          .join(', ');
    }
    return person.teamIds.join(', ');
  }

  Widget _mobileList(List<Person> people) => _Panel(
    title: 'Directory',
    child: Column(
      children: people
          .map(
            (person) => Card(
              color: AppTheme.cardBg(context),
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: AppTheme.cardBorder(context)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => showDetails(person),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _personCell(person),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [_typeBadge(person), _statusBadge(person)],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${person.email}  •  ${person.phone}\n${person.type == PersonType.internalUser ? person.roleLabel : (person.company.isNotEmpty ? person.company : "External Contact")}',
                        style: TextStyle(
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => editPerson(person),
                          icon: Icon(
                            isManagerMode
                                ? Icons.visibility_rounded
                                : Icons.edit_rounded,
                          ),
                          label: Text(
                            isManagerMode ? 'View Details' : 'Edit Person',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    ),
  );

  Widget _personCell(Person person) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        person.name,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: AppTheme.textPrimary(context),
        ),
      ),
      const SizedBox(height: 3),
      Text(
        '${person.designation}  •  ${person.id}',
        style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 12),
      ),
    ],
  );

  Widget _typeBadge(Person person) => _badge(
    person.type == PersonType.internalUser ? 'Internal User' : 'External User',
    person.type == PersonType.internalUser
        ? const Color(0xFF1565C0)
        : const Color(0xFFEA580C),
  );

  Widget _statusBadge(Person person) => _badge(
    person.isActive ? 'Active' : 'Inactive',
    person.isActive ? const Color(0xFF2E7D32) : const Color(0xFF64748B),
  );

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
    ),
  );

  Widget _select(
    String label,
    String value,
    List<String> values,
    ValueChanged<String?> onChanged, {
    double width = 170,
  }) => SizedBox(
    width: width,
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label-$value'),
      isExpanded: true,
      dropdownColor: AppTheme.cardBg(context),
      style: TextStyle(color: AppTheme.textPrimary(context)),
      initialValue: values.contains(value)
          ? value
          : (values.isNotEmpty ? values.first : null),
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
      items: values
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
    ),
  );

  double _width(double available, double preferred) =>
      available < preferred ? available : preferred;
}

class _PersonDetails extends StatelessWidget {
  const _PersonDetails({
    required this.person,
    required this.onEdit,
    this.isManagerMode = false,
  });

  final Person person;
  final VoidCallback onEdit;
  final bool isManagerMode;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              person.name,
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ),
          if (isManagerMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (person.type == PersonType.externalWorker
                        ? const Color(0xFFEA580C)
                        : const Color(0xFF0284C7))
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: person.type == PersonType.externalWorker
                      ? const Color(0xFFEA580C)
                      : const Color(0xFF0284C7),
                ),
              ),
              child: Text(
                person.type == PersonType.externalWorker
                    ? 'External Contact Profile'
                    : 'Managed Staff Profile',
                style: TextStyle(
                  color: person.type == PersonType.externalWorker
                      ? const Color(0xFFEA580C)
                      : const Color(0xFF0284C7),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 5),
      Text(
        person.typeLabel,
        style: TextStyle(
          color: AppTheme.primaryAccent(context),
          fontWeight: FontWeight.w600,
        ),
      ),
      Divider(height: 28, color: AppTheme.cardBorder(context)),
      _detail(context, 'Stable UUID', person.id),
      _detail(context, 'Email', person.email),
      _detail(context, 'Phone', person.phone),
      _detail(context, 'Designation', person.designation),
      _detail(context, 'Status', person.isActive ? 'Active' : 'Inactive'),
      if (person.type == PersonType.internalUser) ...[
        _detail(context, 'Role', person.roleLabel),
        _detail(
          context,
          'Teams',
          person.teamNames.isNotEmpty
              ? person.teamNames.join(', ')
              : (person.teamIds.isNotEmpty
                    ? person.teamIds.join(', ')
                    : 'Not assigned to a team'),
        ),
      ],
      _detail(
        context,
        person.type == PersonType.internalUser
            ? 'Department / Site'
            : 'Company / Organization',
        person.type == PersonType.internalUser
            ? '${person.department.isNotEmpty ? person.department : "None"} / ${person.site.isNotEmpty ? person.site : "None"}'
            : person.company,
      ),
      if (person.type == PersonType.externalWorker) ...[
        if (person.site.isNotEmpty)
          _detail(context, 'Project / Site', person.site),
        if (person.notes.isNotEmpty) _detail(context, 'Notes', person.notes),
      ],
      const SizedBox(height: 16),
      if (isManagerMode)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.cardBg(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.cardBorder(context)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: AppTheme.textMuted(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  person.type == PersonType.externalWorker
                      ? 'External user records are contact references without ActionFlow login accounts or internal scopes.'
                      : 'User authorization, roles, and manager scopes are managed by Company Admin.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted(context),
                  ),
                ),
              ),
            ],
          ),
        )
      else
        FilledButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_rounded),
          label: const Text('Edit Person'),
        ),
    ],
  );

  Widget _detail(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(
            label,
            style: TextStyle(
              color: AppTheme.textSecondary(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? 'Not provided' : value,
            style: TextStyle(color: AppTheme.textPrimary(context)),
          ),
        ),
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppTheme.cardBg(context),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppTheme.cardBorder(context)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary(context),
          ),
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}
