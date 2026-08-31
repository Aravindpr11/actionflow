import 'package:flutter/material.dart';

import '../../../users/data/mock_people_store.dart';
import '../../../users/models/person.dart';
import '../models/action_record.dart';

class AddActionScreen extends StatefulWidget {
  const AddActionScreen({required this.actionId, super.key});

  final String actionId;

  @override
  State<AddActionScreen> createState() => _AddActionScreenState();
}

class _AddActionScreenState extends State<AddActionScreen> {
  final formKey = GlobalKey<FormState>();
  final subject = TextEditingController();
  final requiredAction = TextEditingController();
  final department = TextEditingController();
  final site = TextEditingController();
  final source = TextEditingController();
  final supporting = TextEditingController();
  final description = TextEditingController();
  final assignedController = TextEditingController();
  final externalEmail = TextEditingController();
  final externalPhone = TextEditingController();
  final externalDesignation = TextEditingController();
  final externalSite = TextEditingController();
  String division = 'Operations';
  String category = 'Inspection';
  String assignedTo = 'Select worker';
  String priority = 'Medium';
  String status = 'Open';
  String targetDate = '';
  String dateRaised = '31 Aug 2026';
  String nextFollowUp = '';
  int percent = 0;
  final attachments = <String>[];
  Person? selectedPrimary;
  PersonType primaryType = PersonType.internalUser;
  final additionalPeople = <ActionPersonReference>[];

  @override
  void dispose() {
    for (final controller in [
      subject,
      requiredAction,
      department,
      site,
      source,
      supporting,
      description,
      assignedController,
      externalEmail,
      externalPhone,
      externalDesignation,
      externalSite,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> chooseDate(ValueChanged<String> onPicked) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDate: DateTime.now(),
    );
    if (picked != null) {
      onPicked(
        '${picked.day.toString().padLeft(2, '0')} ${_month(picked.month)} ${picked.year}',
      );
    }
  }

  String _month(int month) => const [
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
  ][month - 1];

  void save() {
    if (primaryType == PersonType.externalWorker) {
      assignedTo = assignedController.text.trim();
    }
    if (!formKey.currentState!.validate() ||
        targetDate.isEmpty ||
        assignedTo == 'Select worker') {
      setState(() {});
      return;
    }
    Navigator.of(context).pop(
      ActionRecord(
        id: widget.actionId,
        subject: subject.text.trim(),
        actionRequired: requiredAction.text.trim(),
        division: division,
        department: department.text.trim(),
        site: site.text.trim(),
        category: category,
        source: source.text.trim(),
        assignedTo: assignedTo,
        priority: priority,
        status: status,
        percentComplete: percent,
        supportingPerson: supporting.text.trim(),
        dateRaised: dateRaised,
        targetDate: targetDate,
        nextFollowUpDate: nextFollowUp,
        attachments: List.of(attachments),
        description: description.text.trim(),
        history: ['$dateRaised: Action raised and assigned to $assignedTo.'],
        primaryAssignee: selectedPrimary == null
            ? (assignedTo == 'Select worker' || assignedTo.trim().isEmpty
                  ? null
                  : ActionPersonReference(
                      personId: 'MANUAL-${assignedTo.trim().toUpperCase()}',
                      name: assignedTo.trim(),
                      type: primaryType,
                      email: externalEmail.text.trim(),
                      phone: externalPhone.text.trim(),
                      designation: externalDesignation.text.trim(),
                      site: externalSite.text.trim(),
                    ))
            : ActionPersonReference(
                personId: selectedPrimary!.id,
                name: selectedPrimary!.name,
                type: selectedPrimary!.type,
                email: selectedPrimary!.email,
                phone: selectedPrimary!.phone,
                designation: selectedPrimary!.designation,
                site: selectedPrimary!.site,
              ),
        additionalPeople: List.of(additionalPeople),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        title: const Text('Add New Action'),
        actions: [
          TextButton(onPressed: save, child: const Text('SAVE ACTION')),
        ],
      ),
      body: Form(
        key: formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _section('WHAT THE ACTION IS', [
                  _field('Action Subject *', subject),
                  _field('Action Required *', requiredAction, maxLines: 3),
                ]),
                _section('WHERE IT BELONGS', [
                  _select('Division *', division, [
                    'Operations',
                    'Projects',
                    'Corporate',
                  ], (value) => setState(() => division = value!)),
                  _field('Department', department),
                  _field('Project / Site', site),
                  _select('Action Category', category, [
                    'Inspection',
                    'Training',
                    'Compliance',
                    'Emergency Preparedness',
                  ], (value) => setState(() => category = value!)),
                  _field('Source / Raised By', source),
                  _assignedPersonField(),
                ]),
                _section('PRIORITY & STATUS', [
                  _select('Priority', priority, [
                    'Low',
                    'Medium',
                    'High',
                    'Critical',
                  ], (value) => setState(() => priority = value!)),
                  _select('Current Status', status, [
                    'Open',
                    'In Progress',
                    'Pending Review',
                    'Overdue',
                    'Closed',
                  ], (value) => setState(() => status = value!)),
                  _percentField(),
                  _field('Supporting Person', supporting),
                ]),
                _section('DATES', [
                  _dateField(
                    'Date Raised',
                    dateRaised,
                    (value) => setState(() => dateRaised = value),
                  ),
                  _dateField(
                    'Target Date *',
                    targetDate,
                    (value) => setState(() => targetDate = value),
                  ),
                  _dateField('Last Follow-up Date', '', (_) {}),
                  _dateField(
                    'Next Follow-up Date',
                    nextFollowUp,
                    (value) => setState(() => nextFollowUp = value),
                  ),
                  _dateField('Close Date / Actual', '', (_) {}),
                  _field('Verified By', TextEditingController()),
                ]),
                _section('EVIDENCE / ATTACHMENTS', [
                  _field('Description', description, maxLines: 4),
                  OutlinedButton.icon(
                    onPressed: () => setState(
                      () => attachments.add(
                        'evidence_${attachments.length + 1}.pdf',
                      ),
                    ),
                    icon: const Icon(Icons.attach_file_rounded),
                    label: const Text('Attach mock file'),
                  ),
                  if (attachments.isNotEmpty)
                    ...attachments.map(
                      (file) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.insert_drive_file_outlined),
                        title: Text(file),
                      ),
                    ),
                ]),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: save,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save Action'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Container(
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
                    width: constraints.maxWidth >= 700
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
  }) => TextFormField(
    controller: controller,
    maxLines: maxLines,
    validator: label.endsWith('*')
        ? (value) => value == null || value.trim().isEmpty
              ? 'Please enter $label'
              : null
        : null,
    decoration: InputDecoration(labelText: label),
  );

  Widget _select(
    String label,
    String value,
    List<String> values,
    ValueChanged<String?> onChanged,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: values
        .map((item) => DropdownMenuItem(value: item, child: Text(item)))
        .toList(),
    onChanged: onChanged,
    validator: label.endsWith('*') && value == 'Select worker'
        ? (_) => 'Please select an assigned worker'
        : null,
  );

  Widget _assignedPersonField() {
    final activePeople = MockPeopleStore.instance.people
        .where((person) => person.isActive)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<PersonType>(
          segments: const [
            ButtonSegment(
              value: PersonType.internalUser,
              label: Text('Internal Person'),
            ),
            ButtonSegment(
              value: PersonType.externalWorker,
              label: Text('External Person'),
            ),
          ],
          selected: {primaryType},
          onSelectionChanged: (value) => setState(() {
            primaryType = value.first;
            selectedPrimary = null;
            assignedTo = 'Select worker';
            assignedController.clear();
          }),
        ),
        const SizedBox(height: 12),
        if (primaryType == PersonType.externalWorker) ...[
          _field('External Person Name *', assignedController),
          _field('External Email', externalEmail),
          _field('External Phone', externalPhone),
          _field('External Designation', externalDesignation),
          _field('Project / Site', externalSite),
        ],
        if (primaryType == PersonType.internalUser) ...[
          Autocomplete<Person>(
            displayStringForOption: (person) => person.name,
            optionsBuilder: (value) {
              final query = value.text.trim().toLowerCase();
              return activePeople.where(
                (person) =>
                    query.isEmpty ||
                    '${person.name} ${person.designation} ${person.email} ${person.phone}'
                        .toLowerCase()
                        .contains(query),
              );
            },
            onSelected: (person) {
              assignedController.text = person.name;
              setState(() {
                assignedTo = person.name;
                selectedPrimary = person;
              });
            },
            fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
              if (assignedController.text.isNotEmpty &&
                  controller.text.isEmpty) {
                controller.text = assignedController.text;
              }
              return TextFormField(
                controller: controller,
                focusNode: focusNode,
                onChanged: (value) => assignedTo = value,
                validator: (_) =>
                    assignedTo == 'Select worker' || assignedTo.trim().isEmpty
                    ? 'Please select an active person'
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Assigned To (Worker/Owner) *',
                  prefixIcon: Icon(Icons.person_search_rounded),
                  hintText: 'Search name, email, or designation',
                ),
              );
            },
            optionsViewBuilder: (context, onSelected, options) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 280,
                    maxWidth: 520,
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final person = options.elementAt(index);
                      return ListTile(
                        onTap: () => onSelected(person),
                        leading: CircleAvatar(
                          child: Text(person.name.substring(0, 1)),
                        ),
                        title: Text(person.name),
                        subtitle: Text(
                          '${person.designation} • ${person.type == PersonType.internalUser ? 'Internal ActionFlow User' : 'External Worker'}\n${person.email} • ${person.phone}',
                        ),
                        isThreeLine: true,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
        OutlinedButton.icon(
          onPressed: _addAdditionalPerson,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: Text('Add Person (${additionalPeople.length})'),
        ),
        if (additionalPeople.isNotEmpty)
          ...additionalPeople.map(
            (person) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.group_add_outlined),
              title: Text(person.name),
              subtitle: Text('${person.typeLabel} • ${person.email}'),
            ),
          ),
        TextButton.icon(
          onPressed: () async {
            final external = activePeople
                .where((person) => person.type == PersonType.externalWorker)
                .toList();
            final selected = await showDialog<Person>(
              context: context,
              builder: (context) => SimpleDialog(
                title: const Text('Assign External Person'),
                children: external
                    .map(
                      (person) => SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, person),
                        child: Text('${person.name} • ${person.company}'),
                      ),
                    )
                    .toList(),
              ),
            );
            if (selected != null) {
              assignedController.text = selected.name;
              setState(() {
                assignedTo = selected.name;
                primaryType = PersonType.externalWorker;
                selectedPrimary = selected;
              });
            }
          },
          icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
          label: const Text('Assign External Person'),
        ),
      ],
    );
  }

  Future<void> _addAdditionalPerson() async {
    final activePeople = MockPeopleStore.instance.people
        .where((person) => person.isActive)
        .toList();
    final selected = await showDialog<Person>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add Person to This Action'),
        children: activePeople
            .map(
              (person) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, person),
                child: Text('${person.name} • ${person.typeLabel}'),
              ),
            )
            .toList(),
      ),
    );
    if (selected != null && mounted) {
      setState(
        () => additionalPeople.add(
          ActionPersonReference(
            personId: selected.id,
            name: selected.name,
            type: selected.type,
            email: selected.email,
            phone: selected.phone,
            designation: selected.designation,
            site: selected.site,
          ),
        ),
      );
    }
  }

  Widget _dateField(
    String label,
    String value,
    ValueChanged<String> onChanged,
  ) => TextFormField(
    readOnly: true,
    controller: TextEditingController(text: value),
    validator: label.contains('Target')
        ? (_) => value.isEmpty ? 'Please select a target date' : null
        : null,
    onTap: () => chooseDate(onChanged),
    decoration: InputDecoration(
      labelText: label,
      suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
    ),
  );

  Widget _percentField() => DropdownButtonFormField<int>(
    initialValue: percent,
    decoration: const InputDecoration(labelText: '% Complete'),
    items: [0, 25, 50, 75, 100]
        .map((value) => DropdownMenuItem(value: value, child: Text('$value%')))
        .toList(),
    onChanged: (value) => setState(() => percent = value ?? 0),
  );
}
