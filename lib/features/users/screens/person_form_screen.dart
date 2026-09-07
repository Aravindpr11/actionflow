import 'package:flutter/material.dart';

import '../data/mock_people_store.dart';
import '../models/person.dart';
import '../models/team.dart';
import '../widgets/duplicate_person_dialog.dart';

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
  late final TextEditingController notes;
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
    notes = TextEditingController(text: person?.notes);
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
      notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate() ||
        (type == PersonType.internalUser && teamIds.isEmpty)) {
      setState(() {});
      return;
    }

    final trimmedEmail = email.text.trim();
    final trimmedPhone = phone.text.trim();

    // Check for strong duplicate by email or phone (ignoring current person's own ID)
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
    Navigator.of(context).pop(
      Person(
        id:
            existing?.id ??
            '${type == PersonType.internalUser ? 'AFU' : 'EXT'}-${DateTime.now().millisecondsSinceEpoch % 1000}',
        name: name.text.trim(),
        email: trimmedEmail,
        phone: trimmedPhone,
        designation: designation.text.trim(),
        department: type == PersonType.internalUser
            ? department.text.trim()
            : '',
        division: type == PersonType.internalUser ? division.text.trim() : '',
        site: site.text.trim(),
        company: type == PersonType.externalWorker ? company.text.trim() : '',
        notes: type == PersonType.externalWorker ? notes.text.trim() : '',
        type: type,
        isActive: active,
        role: type == PersonType.internalUser
            ? role
            : UserRole.actionOwnerWorker,
        teamIds: type == PersonType.internalUser ? teamIds.toList() : const [],
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
                    onSelectionChanged: widget.person != null
                        ? null
                        : (value) => setState(() => type = value.first),
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
                    if (external) ...[
                      _field('Company / Organization *', company),
                      _field('Project / Site', site),
                      _field('Notes', notes, maxLines: 2),
                    ],
                    if (!external) ...[
                      _field('Department', department),
                      _field('Division', division),
                      _field('Site', site),
                    ],
                    Material(
                      color: Colors.transparent,
                      child: SwitchListTile.adaptive(
                        title: const Text('Active person'),
                        value: active,
                        onChanged: (value) => setState(() => active = value),
                        contentPadding: EdgeInsets.zero,
                      ),
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
    int maxLines = 1,
    TextInputType? keyboardType,
  }) => TextFormField(
    controller: controller,
    maxLines: maxLines,
    keyboardType: keyboardType,
    validator: label.endsWith('*')
        ? (value) => value == null || value.trim().isEmpty
              ? 'Please enter $label'
              : null
        : null,
    decoration: InputDecoration(labelText: label),
  );
}
