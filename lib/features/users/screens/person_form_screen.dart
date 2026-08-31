import 'package:flutter/material.dart';

import '../data/mock_people_store.dart';
import '../models/person.dart';
import '../models/team.dart';

class PersonFormScreen extends StatefulWidget {
  const PersonFormScreen({this.person, super.key});

  final Person? person;

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
  late final TextEditingController division;
  late final TextEditingController site;
  late final TextEditingController company;
  late PersonType type;
  late bool active;
  late UserRole role;
  late Set<String> teamIds;

  @override
  void initState() {
    super.initState();
    final person = widget.person;
    name = TextEditingController(text: person?.name);
    email = TextEditingController(text: person?.email);
    phone = TextEditingController(text: person?.phone);
    designation = TextEditingController(text: person?.designation);
    department = TextEditingController(text: person?.department);
    division = TextEditingController(text: person?.division);
    site = TextEditingController(text: person?.site);
    company = TextEditingController(text: person?.company);
    type = person?.type ?? PersonType.internalUser;
    active = person?.isActive ?? true;
    role = person?.role ?? UserRole.actionOwnerWorker;
    teamIds = {...?person?.teamIds};
  }

  @override
  void dispose() {
    for (final controller in [
      name,
      email,
      phone,
      designation,
      department,
      division,
      site,
      company,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void save() {
    if (!formKey.currentState!.validate() ||
        (type == PersonType.internalUser && teamIds.isEmpty)) {
      setState(() {});
      return;
    }
    final existing = widget.person;
    Navigator.of(context).pop(
      Person(
        id:
            existing?.id ??
            '${type == PersonType.internalUser ? 'AFU' : 'EXT'}-${DateTime.now().millisecondsSinceEpoch % 1000}',
        name: name.text.trim(),
        email: email.text.trim(),
        phone: phone.text.trim(),
        designation: designation.text.trim(),
        department: department.text.trim(),
        division: division.text.trim(),
        site: site.text.trim(),
        company: company.text.trim(),
        type: type,
        isActive: active,
        role: role,
        teamIds: teamIds.toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final external = type == PersonType.externalWorker;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        title: Text(existingTitle),
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
                        label: Text('External Worker'),
                        icon: Icon(Icons.engineering_outlined),
                      ),
                    ],
                    selected: {type},
                    onSelectionChanged: (value) =>
                        setState(() => type = value.first),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    external
                        ? 'No ActionFlow account. Used as an external action owner.'
                        : 'Has an ActionFlow account and can sign in.',
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                  if (!external) ...[
                    DropdownButtonFormField<UserRole>(
                      isExpanded: true,
                      initialValue: role,
                      decoration: const InputDecoration(labelText: 'Role *'),
                      items: UserRole.values
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => role = value!),
                    ),
                    _teamSelector(),
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
                _panel(
                  external
                      ? 'EXTERNAL WORKER DETAILS'
                      : 'ACTIONFLOW ORGANISATION',
                  [
                    if (external) _field('Company *', company),
                    if (!external) ...[
                      _field('Department', department),
                      _field('Division', division),
                      _field('Site', site),
                    ],
                    SwitchListTile.adaptive(
                      title: const Text('Active person'),
                      value: active,
                      onChanged: (value) => setState(() => active = value),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
                FilledButton.icon(
                  onPressed: save,
                  icon: const Icon(Icons.save_rounded),
                  label: Text(
                    widget.person == null ? 'Add Person' : 'Save Changes',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get existingTitle =>
      widget.person == null ? 'Add Person' : 'Edit Person';

  Widget _teamSelector() => InputDecorator(
    decoration: InputDecoration(
      labelText: 'Department / Team memberships *',
      errorText: teamIds.isEmpty ? 'Select at least one team' : null,
    ),
    child: Wrap(
      spacing: 8,
      runSpacing: 4,
      children: MockPeopleStore.instance.teams
          .map(
            (team) => FilterChip(
              label: Text(team.department),
              selected: teamIds.contains(team.id),
              onSelected: (selected) => setState(
                () => selected ? teamIds.add(team.id) : teamIds.remove(team.id),
              ),
            ),
          )
          .toList(),
    ),
  );

  Widget _panel(String title, List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF1565C0),
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
    TextInputType? keyboardType,
  }) => TextFormField(
    controller: controller,
    keyboardType: keyboardType,
    validator: label.endsWith('*')
        ? (value) => value == null || value.trim().isEmpty
              ? 'Please enter $label'
              : null
        : null,
    decoration: InputDecoration(labelText: label),
  );
}
