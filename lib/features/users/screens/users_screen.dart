import 'package:flutter/material.dart';

import '../data/mock_people_store.dart';
import '../models/person.dart';
import 'person_form_screen.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

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

  List<String> get availableDepartments {
    final set = <String>{};
    for (final p in store.people) {
      if (p.department.trim().isNotEmpty) {
        set.add(p.department.trim());
      }
    }
    final list = set.toList()..sort();
    return ['All Departments', ...list];
  }

  List<String> get availableSites {
    final set = <String>{};
    for (final p in store.people) {
      if (p.site.trim().isNotEmpty) {
        set.add(p.site.trim());
      }
    }
    final list = set.toList()..sort();
    return ['All Sites', ...list];
  }

  List<Person> get visiblePeople {
    final query = searchController.text.trim().toLowerCase();
    return store.people.where((person) {
      final searchable = [
        person.name,
        person.email,
        person.phone,
        person.designation,
        person.department,
        person.site,
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
    final updated = await Navigator.of(context).push<Person>(
      MaterialPageRoute(builder: (_) => PersonFormScreen(person: person)),
    );
    if (updated != null && mounted) {
      store.update(updated);
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
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        title: const Text('People / Workers'),
        actions: [
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
              LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth >= 850
                    ? _desktopTable(people)
                    : _mobileList(people),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addPerson,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add Person'),
      ),
    );
  }

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
              'People / Workers Directory',
              style: TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${store.people.length} people available for HSSE action assignment',
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
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Search name, email, phone, designation...',
                prefixIcon: Icon(Icons.search_rounded),
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
          _select(
            'Department',
            departmentFilter,
            availableDepartments,
            (value) =>
                setState(() => departmentFilter = value ?? 'All Departments'),
            width: _width(constraints.maxWidth, 165),
          ),
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
        columns: const [
          DataColumn(label: Text('Person')),
          DataColumn(label: Text('Type')),
          DataColumn(label: Text('Contact')),
          DataColumn(label: Text('Role / Teams')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Actions')),
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
                  DataCell(Text('${person.email}\n${person.phone}')),
                  DataCell(
                    Text(
                      person.type == PersonType.internalUser
                          ? '${person.roleLabel}\n${person.teamIds.map((id) => store.teams.firstWhere((team) => team.id == id).department).join(', ')}'
                          : person.company,
                    ),
                  ),
                  DataCell(_statusBadge(person)),
                  DataCell(
                    IconButton(
                      onPressed: () => editPerson(person),
                      icon: const Icon(Icons.edit_rounded),
                      tooltip: 'Edit person',
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    ),
  );

  Widget _mobileList(List<Person> people) => _Panel(
    title: 'Directory',
    child: Column(
      children: people
          .map(
            (person) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
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
                        '${person.email}  •  ${person.phone}\n${person.type == PersonType.internalUser ? person.roleLabel : person.company}',
                        style: const TextStyle(color: Color(0xFF64748B)),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => editPerson(person),
                          icon: const Icon(Icons.edit_rounded),
                          label: const Text('Edit Person'),
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
      Text(person.name, style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 3),
      Text(
        '${person.designation}  •  ${person.id}',
        style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
      ),
    ],
  );
  Widget _typeBadge(Person person) => _badge(
    person.type == PersonType.internalUser
        ? 'Internal User'
        : 'External Worker',
    person.type == PersonType.internalUser
        ? const Color(0xFF1565C0)
        : const Color(0xFF7E57C2),
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
      initialValue: values.contains(value) ? value : values.first,
      decoration: InputDecoration(labelText: label),
      items: values
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(item, overflow: TextOverflow.ellipsis),
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
  const _PersonDetails({required this.person, required this.onEdit});
  final Person person;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        person.name,
        style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 5),
      Text(
        person.typeLabel,
        style: const TextStyle(
          color: Color(0xFF1565C0),
          fontWeight: FontWeight.w600,
        ),
      ),
      const Divider(height: 28),
      _detail('Stable ID', person.id),
      _detail('Email', person.email),
      _detail('Phone', person.phone),
      _detail('Designation', person.designation),
      if (person.type == PersonType.internalUser) ...[
        _detail('Role', person.roleLabel),
        _detail(
          'Teams',
          person.teamIds
              .map(
                (id) => MockPeopleStore.instance.teams
                    .firstWhere((team) => team.id == id)
                    .department,
              )
              .join(', '),
        ),
      ],
      _detail(
        person.type == PersonType.internalUser
            ? 'Division / Department / Site'
            : 'Company / Organization',
        person.type == PersonType.internalUser
            ? '${person.division} / ${person.department} / ${person.site}'
            : person.company,
      ),
      if (person.type == PersonType.externalWorker) ...[
        if (person.site.isNotEmpty) _detail('Project / Site', person.site),
        if (person.notes.isNotEmpty) _detail('Notes', person.notes),
      ],
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: onEdit,
        icon: const Icon(Icons.edit_rounded),
        label: const Text('Edit Person'),
      ),
    ],
  );
  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: Text(value.isEmpty ? 'Not provided' : value)),
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
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}
