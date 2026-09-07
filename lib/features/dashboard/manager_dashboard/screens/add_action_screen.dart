import 'package:flutter/material.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/widgets/duplicate_person_dialog.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';

class AddActionScreen extends StatefulWidget {
  const AddActionScreen({super.key, required this.actionId});

  final String actionId;

  @override
  State<AddActionScreen> createState() => _AddActionScreenState();
}

class _AddActionScreenState extends State<AddActionScreen> {
  final _formKey = GlobalKey<FormState>();

  // What the action is
  final actionTitle = TextEditingController();
  final actionDescription = TextEditingController();

  // Where it belongs
  String division = 'Operations';
  String department = 'HSE';
  String section = 'General';
  String unit = 'Site 1';
  final locationSite = TextEditingController(text: 'Site 1');

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

  // Priority & Status
  String priority = 'Medium';
  String status = 'Open';
  int percent = 0;

  // Dates
  String raiseDate = '01 Jan 2026';
  String targetDate = '15 Jan 2026';
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

  void _saveAction() {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all required fields correctly.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    if (internalPrimary == null &&
        externalPrimary == null &&
        externalName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please assign at least one internal or external person.',
          ),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
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

    final isActionClosed =
        status == 'Closed' || (closeDate.isNotEmpty && percent == 100);
    final effectiveReminders = emailReminderEnabled
        ? (isActionClosed
              ? emailReminders.map((r) => r.copyWith(isEnabled: false)).toList()
              : emailReminders)
        : <ActionEmailReminder>[];

    final record = ActionRecord(
      id: widget.actionId,
      subject: actionTitle.text.trim(),
      actionRequired: actionDescription.text.trim(),
      priority: priority,
      status: status,
      percentComplete: percent,
      division: division,
      department: department,
      site: locationSite.text.trim(),
      dateRaised: raiseDate,
      targetDate: targetDate,
      closeDate: closeDate,
      assignedTo:
          internalPrimary?.name ??
          externalPrimary?.name ??
          externalName.text.trim(),
      primaryAssignee:
          internalPrimary ??
          externalPrimary ??
          ActionPersonReference(
            personId: '',
            name: externalName.text.trim(),
            type: PersonType.externalWorker,
            email: externalEmail.text.trim(),
            phone: externalPhone.text.trim(),
            company: externalCompany.text.trim(),
          ),
      additionalPeople: [
        ...additionalInternalPeople,
        ...additionalExternalPeople,
      ],
      emailReminders: effectiveReminders,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Action ${widget.actionId} created successfully!'),
        backgroundColor: const Color(0xFF16A34A),
      ),
    );

    Navigator.pop(context, record);
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
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'Add New Action',
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
                onPressed: _saveAction,
                icon: const Icon(Icons.send_rounded, size: 16),
                label: Text(isNarrow ? 'SEND' : 'SEND ACTION'),
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
      subtitle: 'Specify division, department, section, and physical location',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 550;
          return Column(
            children: [
              if (isWide)
                Row(
                  children: [
                    Expanded(
                      child: _dropdownField('Division', division, [
                        'Operations',
                        'Projects',
                        'Corporate',
                      ], (v) => setState(() => division = v!)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _dropdownField('Department', department, [
                        'HSE',
                        'Maintenance',
                        'Engineering',
                        'Civil',
                      ], (v) => setState(() => department = v!)),
                    ),
                  ],
                )
              else ...[
                _dropdownField('Division', division, [
                  'Operations',
                  'Projects',
                  'Corporate',
                ], (v) => setState(() => division = v!)),
                const SizedBox(height: 14),
                _dropdownField('Department', department, [
                  'HSE',
                  'Maintenance',
                  'Engineering',
                  'Civil',
                ], (v) => setState(() => department = v!)),
              ],
              const SizedBox(height: 14),
              if (isWide)
                Row(
                  children: [
                    Expanded(
                      child: _dropdownField('Section', section, [
                        'General',
                        'Safety Inspection',
                        'Mechanical',
                        'Electrical',
                      ], (v) => setState(() => section = v!)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _dropdownField('Unit', unit, [
                        'Site 1',
                        'North Plant',
                        'Tower B',
                        'HQ',
                      ], (v) => setState(() => unit = v!)),
                    ),
                  ],
                )
              else ...[
                _dropdownField('Section', section, [
                  'General',
                  'Safety Inspection',
                  'Mechanical',
                  'Electrical',
                ], (v) => setState(() => section = v!)),
                const SizedBox(height: 14),
                _dropdownField('Unit', unit, [
                  'Site 1',
                  'North Plant',
                  'Tower B',
                  'HQ',
                ], (v) => setState(() => unit = v!)),
              ],
              const SizedBox(height: 14),
              _textField(
                label: 'Location / Site',
                controller: locationSite,
                hint: 'Specific area or building location',
              ),
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
      subtitle: 'Assign primary and additional internal and external owners',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 700;
          return isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildInternalAssignmentPanel()),
                    const SizedBox(width: 16),
                    Expanded(child: _buildExternalAssignmentPanel()),
                  ],
                )
              : Column(
                  children: [
                    _buildInternalAssignmentPanel(),
                    const SizedBox(height: 16),
                    _buildExternalAssignmentPanel(),
                  ],
                );
        },
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

        final active = MockPeopleStore.instance.people.where(
          (p) => p.isActive && p.type == PersonType.internalUser,
        );

        return active.where((p) {
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
              constraints: const BoxConstraints(maxHeight: 250, maxWidth: 450),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final person = options.elementAt(index);
                  return ListTile(
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

  void _quickAddSelectedInternalPerson() {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Add Additional Internal Person'),
          content: SizedBox(
            width: 400,
            child: _internalAutocomplete(
              controller: TextEditingController(),
              hint: 'Search by name, email, or phone...',
              onSelected: (ref) {
                setState(() {
                  final exists = additionalInternalPeople.any(
                    (p) => p.personId == ref.personId,
                  );
                  if (!exists && internalPrimary?.personId != ref.personId) {
                    additionalInternalPeople.add(ref);
                    _syncReminderRecipients();
                  }
                });
                Navigator.of(ctx).pop();
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openAddNewInternalPersonModal() async {
    final newPerson = await showDialog<Person>(
      context: context,
      builder: (ctx) => _InternalPersonDialog(
        existingPeople: MockPeopleStore.instance.people,
      ),
    );

    if (newPerson != null && mounted) {
      final ref = _reference(newPerson);
      setState(() {
        if (internalPrimary == null) {
          internalPrimary = ref;
          assignedTo = newPerson.name;
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

  Future<void> _editInternalPerson({
    required bool isPrimary,
    required ActionPersonReference person,
  }) async {
    final updated = await showDialog<Person>(
      context: context,
      builder: (ctx) => _InternalPersonDialog(
        existingPeople: MockPeopleStore.instance.people,
        initialPerson: person,
      ),
    );

    if (updated != null && mounted) {
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
                      'EXTERNAL PERSON / COMPANY',
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
              onPressed: _openAddNewExternalPersonModal,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
              label: const Text('Add New External Person'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF475569),
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
          if (externalPrimary != null)
            _selectedExternalPersonCard(externalPrimary!, isPrimary: true)
          else
            _buildExternalInputOrSearch(),
          if (additionalExternalPeople.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Additional External Persons (${additionalExternalPeople.length})',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 6),
            ...additionalExternalPeople.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _selectedExternalPersonCard(p, isPrimary: false),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _quickAddExternalPersonFromDialog,
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 16),
              label: const Text('Add External Person'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF475569),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
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

  Widget _buildExternalInputOrSearch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Autocomplete<Person>(
          displayStringForOption: (p) => p.name,
          optionsBuilder: (textEditingValue) {
            final query = textEditingValue.text.trim().toLowerCase();
            if (query.isEmpty) return const Iterable<Person>.empty();

            final active = MockPeopleStore.instance.people.where(
              (p) => p.isActive && p.type == PersonType.externalWorker,
            );

            return active.where((p) {
              final n = p.name.toLowerCase();
              final e = p.email.toLowerCase();
              final ph = p.phone.toLowerCase();
              final c = p.company.toLowerCase();
              return n.contains(query) ||
                  e.contains(query) ||
                  ph.contains(query) ||
                  c.contains(query);
            });
          },
          onSelected: (person) {
            setState(() {
              externalPrimary = _reference(person);
              externalName.text = person.name;
              externalEmail.text = person.email;
              externalPhone.text = person.phone;
              externalCompany.text = person.company;
              _syncReminderRecipients();
            });
          },
          fieldViewBuilder:
              (context, textController, focusNode, onFieldSubmitted) {
                return TextFormField(
                  controller: textController,
                  focusNode: focusNode,
                  onChanged: (val) {
                    externalName.text = val;
                    _syncReminderRecipients();
                  },
                  decoration: InputDecoration(
                    labelText: 'Search by name, email, phone, or company...',
                    hintText: 'Search or enter external contractor name...',
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
                  constraints: const BoxConstraints(
                    maxHeight: 250,
                    maxWidth: 450,
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final person = options.elementAt(index);
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: const Color(0xFF475569),
                          child: Text(
                            person.name.isNotEmpty
                                ? person.name[0].toUpperCase()
                                : 'E',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          person.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (person.company.isNotEmpty)
                              Text(
                                person.company,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF334155),
                                ),
                              ),
                            Text(
                              [
                                if (person.designation.isNotEmpty)
                                  person.designation,
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
        ),
        const SizedBox(height: 10),
        _textField(
          label: 'External Email',
          controller: externalEmail,
          hint: 'john@contractor.com',
          onChanged: (_) => _syncReminderRecipients(),
        ),
        const SizedBox(height: 10),
        _textField(
          label: 'External Phone',
          controller: externalPhone,
          hint: '+91 98765 00000',
        ),
        const SizedBox(height: 10),
        _textField(
          label: 'External Company / Organization *',
          controller: externalCompany,
          hint: 'e.g. Apex Safety Solutions Ltd',
        ),
      ],
    );
  }

  Widget _selectedExternalPersonCard(
    ActionPersonReference person, {
    required bool isPrimary,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF475569),
            radius: 20,
            child: Text(
              person.name.isNotEmpty ? person.name[0].toUpperCase() : 'E',
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
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isPrimary ? 'Primary External' : 'Additional External',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                if (person.company.isNotEmpty)
                  Text(
                    person.company,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF334155),
                    ),
                  ),
                Text(
                  [
                    if (person.designation.isNotEmpty) person.designation,
                    if (person.email.isNotEmpty) person.email,
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
                tooltip: 'Edit External Person',
                onPressed: () =>
                    _editExternalPerson(isPrimary: isPrimary, person: person),
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
                    externalPrimary = null;
                    externalName.clear();
                    externalEmail.clear();
                    externalPhone.clear();
                    externalCompany.clear();
                    externalSearchController.clear();
                  } else {
                    additionalExternalPeople.remove(person);
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

  void _quickAddExternalPersonFromDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Add Additional External Person'),
          content: SizedBox(
            width: 400,
            child: Autocomplete<Person>(
              displayStringForOption: (p) => p.name,
              optionsBuilder: (textEditingValue) {
                final query = textEditingValue.text.trim().toLowerCase();
                if (query.isEmpty) return const Iterable<Person>.empty();

                final active = MockPeopleStore.instance.people.where(
                  (p) => p.isActive && p.type == PersonType.externalWorker,
                );

                return active.where((p) {
                  return p.name.toLowerCase().contains(query) ||
                      p.email.toLowerCase().contains(query) ||
                      p.company.toLowerCase().contains(query);
                });
              },
              onSelected: (person) {
                setState(() {
                  final ref = _reference(person);
                  final exists = additionalExternalPeople.any(
                    (p) => p.personId == ref.personId,
                  );
                  if (!exists && externalPrimary?.personId != ref.personId) {
                    additionalExternalPeople.add(ref);
                    _syncReminderRecipients();
                  }
                });
                Navigator.of(ctx).pop();
              },
              fieldViewBuilder:
                  (context, textController, focusNode, onFieldSubmitted) {
                    return TextFormField(
                      controller: textController,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Search external person...',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    );
                  },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openAddNewExternalPersonModal() async {
    final newPerson = await showDialog<Person>(
      context: context,
      builder: (ctx) => _ExternalPersonDialog(
        existingPeople: MockPeopleStore.instance.people,
      ),
    );

    if (newPerson != null && mounted) {
      final ref = _reference(newPerson);
      setState(() {
        if (externalPrimary == null) {
          externalPrimary = ref;
          externalName.text = newPerson.name;
          externalEmail.text = newPerson.email;
          externalPhone.text = newPerson.phone;
          externalCompany.text = newPerson.company;
        } else {
          final exists = additionalExternalPeople.any(
            (p) => p.personId == ref.personId,
          );
          if (!exists && externalPrimary?.personId != ref.personId) {
            additionalExternalPeople.add(ref);
          }
        }
        _syncReminderRecipients();
      });
    }
  }

  Future<void> _editExternalPerson({
    required bool isPrimary,
    required ActionPersonReference person,
  }) async {
    final updated = await showDialog<Person>(
      context: context,
      builder: (ctx) => _ExternalPersonDialog(
        existingPeople: MockPeopleStore.instance.people,
        initialPerson: person,
      ),
    );

    if (updated != null && mounted) {
      final updatedRef = ActionPersonReference(
        personId: person.personId,
        name: updated.name,
        type: PersonType.externalWorker,
        email: updated.email,
        phone: updated.phone,
        company: updated.company,
        designation: updated.designation,
        site: updated.site,
      );

      setState(() {
        if (isPrimary) {
          externalPrimary = updatedRef;
          externalName.text = updated.name;
          externalEmail.text = updated.email;
          externalPhone.text = updated.phone;
          externalCompany.text = updated.company;
        } else {
          final idx = additionalExternalPeople.indexWhere(
            (p) => p.personId == person.personId,
          );
          if (idx != -1) {
            additionalExternalPeople[idx] = updatedRef;
          }
        }
        _syncReminderRecipients();
      });
    }
  }

  // ============================================================================
  // SECTION 4: PRIORITY & STATUS
  // ============================================================================

  Widget _buildSection4PriorityStatus() {
    return _cardWrapper(
      number: '4',
      title: 'PRIORITY & STATUS',
      subtitle: 'Set urgency level and current implementation status',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 550;
          return Column(
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
                      child: _dropdownField('Status', status, [
                        'Open',
                        'In Progress',
                        'Under Review',
                        'Closed',
                      ], (v) => setState(() => status = v!)),
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
                _dropdownField('Status', status, [
                  'Open',
                  'In Progress',
                  'Under Review',
                  'Closed',
                ], (v) => setState(() => status = v!)),
              ],
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: percent,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '% Complete',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
                items: [0, 25, 50, 75, 100]
                    .map(
                      (v) =>
                          DropdownMenuItem<int>(value: v, child: Text('$v%')),
                    )
                    .toList(),
                onChanged: (v) => setState(() => percent = v ?? 0),
              ),
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
          final isWide = constraints.maxWidth > 650;
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
                        label: 'Target Date *',
                        value: targetDate,
                        onSelected: (v) => setState(() => targetDate = v),
                        required: true,
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
                      label: 'Target Date *',
                      value: targetDate,
                      onSelected: (v) => setState(() => targetDate = v),
                      required: true,
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
    );
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
              onPressed: _saveAction,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Send Action'),
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
    ValueChanged<String?> onChanged,
  ) {
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
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
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
          ),
          items: items
              .map((i) => DropdownMenuItem(value: i, child: Text(i)))
              .toList(),
          onChanged: onChanged,
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
  });

  final List<Person> existingPeople;
  final ActionPersonReference? initialPerson;

  @override
  State<_InternalPersonDialog> createState() => _InternalPersonDialogState();
}

class _InternalPersonDialogState extends State<_InternalPersonDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController email;
  late final TextEditingController phone;
  late final TextEditingController designation;
  late final TextEditingController department;
  late final TextEditingController site;
  Person? existing;

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialPerson != null;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Column(
          children: [
            Container(
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
                      isEdit
                          ? 'Edit Internal Person'
                          : 'Add New Internal Person',
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
            ),
            Expanded(
              child: SingleChildScrollView(
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
                                    p.isActive &&
                                    p.type == PersonType.internalUser,
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
              ),
            ),
            Container(
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
                        excludeId: isEdit
                            ? widget.initialPerson?.personId
                            : null,
                      );

                      if (duplicate != null) {
                        final useExisting = await showDialog<dynamic>(
                          context: context,
                          builder: (ctx) =>
                              DuplicatePersonDialog(existingPerson: duplicate),
                        );

                        if (useExisting != null && context.mounted) {
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
            ),
          ],
        ),
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

// ============================================================================
// EXTERNAL PERSON DIALOG
// ============================================================================

class _ExternalPersonDialog extends StatefulWidget {
  const _ExternalPersonDialog({
    required this.existingPeople,
    this.initialPerson,
  });

  final List<Person> existingPeople;
  final ActionPersonReference? initialPerson;

  @override
  State<_ExternalPersonDialog> createState() => _ExternalPersonDialogState();
}

class _ExternalPersonDialogState extends State<_ExternalPersonDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController email;
  late final TextEditingController phone;
  late final TextEditingController company;
  late final TextEditingController designation;
  late final TextEditingController site;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPerson;
    name = TextEditingController(text: initial?.name);
    email = TextEditingController(text: initial?.email);
    phone = TextEditingController(text: initial?.phone);
    company = TextEditingController(text: initial?.company);
    designation = TextEditingController(text: initial?.designation);
    site = TextEditingController(text: initial?.site);
  }

  @override
  void dispose() {
    for (final controller in [name, email, phone, company, designation, site]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialPerson != null;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                color: Color(0xFF475569),
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
                      isEdit
                          ? 'Edit External Person'
                          : 'Add New External Person',
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
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _dialogField(
                        label: 'Full Name *',
                        controller: name,
                        hint: 'e.g. John Doe',
                        required: true,
                        prefixIcon: Icons.person_outline_rounded,
                      ),
                      const SizedBox(height: 14),
                      _dialogField(
                        label: 'Email *',
                        controller: email,
                        hint: 'e.g. john.doe@contractor.com',
                        required: true,
                        prefixIcon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 14),
                      _dialogField(
                        label: 'Phone Number',
                        controller: phone,
                        hint: 'e.g. +91 98765 00000',
                        prefixIcon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 14),
                      _dialogField(
                        label: 'Company / Organization *',
                        controller: company,
                        hint: 'e.g. BuildWell Infrastructure',
                        required: true,
                        prefixIcon: Icons.business_outlined,
                      ),
                      const SizedBox(height: 14),
                      _dialogField(
                        label: 'Designation / Role',
                        controller: designation,
                        hint: 'e.g. Site Supervisor',
                        prefixIcon: Icons.work_outline_rounded,
                      ),
                      const SizedBox(height: 14),
                      _dialogField(
                        label: 'Project / Site',
                        controller: site,
                        hint: 'e.g. Site 1',
                        prefixIcon: Icons.location_on_outlined,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
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
                        excludeId: isEdit
                            ? widget.initialPerson?.personId
                            : null,
                      );

                      if (duplicate != null) {
                        final useExisting = await showDialog<dynamic>(
                          context: context,
                          builder: (ctx) =>
                              DuplicatePersonDialog(existingPerson: duplicate),
                        );

                        if (useExisting != null && context.mounted) {
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
                          company: company.text.trim(),
                          designation: designation.text.trim(),
                          site: site.text.trim(),
                          type: PersonType.externalWorker,
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
                        company: company.text.trim(),
                        designation: designation.text.trim(),
                        site: site.text.trim(),
                        type: PersonType.externalWorker,
                        isActive: true,
                      );
                      MockPeopleStore.instance.add(newPerson);
                      if (context.mounted) {
                        Navigator.pop(context, newPerson);
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF475569),
                    ),
                    child: const Text('Save Person'),
                  ),
                ],
              ),
            ),
          ],
        ),
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
