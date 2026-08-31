import 'package:flutter/material.dart';

import '../../manager_dashboard/models/action_record.dart';

class WorkerActionUpdateScreen extends StatefulWidget {
  const WorkerActionUpdateScreen({required this.action, super.key});

  final ActionRecord action;

  @override
  State<WorkerActionUpdateScreen> createState() =>
      _WorkerActionUpdateScreenState();
}

class _WorkerActionUpdateScreenState extends State<WorkerActionUpdateScreen> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController subject;
  late final TextEditingController message;
  late final TextEditingController requirement;
  late final TextEditingController pendingReason;
  late final TextEditingController suggestion;
  late final TextEditingController remarks;
  late int percent;
  late String status;
  String messageType = 'Progress Update';
  final attachments = <String>[];

  @override
  void initState() {
    super.initState();
    final action = widget.action;
    subject = TextEditingController(text: action.workerMessageSubject);
    message = TextEditingController(text: action.workerMessage);
    requirement = TextEditingController(text: action.requirement);
    pendingReason = TextEditingController(text: action.pendingReason);
    suggestion = TextEditingController(text: action.suggestion);
    remarks = TextEditingController(text: action.remarks);
    percent = action.percentComplete;
    status = action.status == 'Completed' ? 'In Progress' : action.status;
    messageType = action.messageType;
    attachments.addAll(action.attachments);
  }

  @override
  void dispose() {
    for (final controller in [
      subject,
      message,
      requirement,
      pendingReason,
      suggestion,
      remarks,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void submit() {
    final completed = status == 'Completed';
    if (!formKey.currentState!.validate() || (completed && percent != 100)) {
      setState(() {});
      return;
    }
    final nextStatus = completed ? 'Pending Review' : status;
    final nextHistory = [
      ...widget.action.history,
      '31 Aug 2026: Worker update submitted as $nextStatus.',
    ];
    Navigator.of(context).pop(
      widget.action.copyWith(
        status: nextStatus,
        percentComplete: completed ? 100 : percent,
        history: nextHistory,
        workerMessageSubject: subject.text.trim(),
        workerMessage: message.text.trim(),
        messageType: messageType,
        requirement: requirement.text.trim(),
        pendingReason: pendingReason.text.trim(),
        suggestion: suggestion.text.trim(),
        remarks: remarks.text.trim(),
        attachments: List.of(attachments),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final completion = status == 'Completed';
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        title: Text('Update ${widget.action.id}'),
        actions: [
          TextButton(onPressed: submit, child: const Text('SUBMIT UPDATE')),
        ],
      ),
      body: Form(
        key: formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _actionSummary(),
                const SizedBox(height: 16),
                _panel('PROGRESS & STATUS', [
                  _select(
                    'Current Status',
                    status,
                    [
                      'Open',
                      'In Progress',
                      'Pending',
                      'Pending Review',
                      'Overdue',
                      'Completed',
                    ],
                    (value) => setState(() {
                      status = value!;
                      if (status == 'Completed') percent = 100;
                    }),
                  ),
                  _select(
                    '% Complete',
                    '$percent%',
                    ['0%', '25%', '40%', '65%', '80%', '90%', '100%'],
                    (value) => setState(
                      () => percent = int.parse(value!.replaceAll('%', '')),
                    ),
                  ),
                ]),
                if (completion)
                  _panel('COMPLETION CONFIRMATION', [
                    _field('Completion Subject *', subject),
                    _field(
                      'Completion Description / Explanation *',
                      message,
                      maxLines: 5,
                    ),
                    const Text(
                      'Completed submissions move to Pending Review for manager verification.',
                      style: TextStyle(color: Color(0xFF1565C0)),
                    ),
                  ]),
                _panel('WORKER UPDATE / MESSAGE', [
                  _field('Subject *', subject),
                  _field(
                    'Message / Description *',
                    message,
                    maxLines: 7,
                    helperText: 'Explain completed work, pending items, requirements, suggestions, or issues.',
                  ),
                  _select('Message Type', messageType, const [
                    'Progress Update',
                    'Completion Explanation',
                    'Pending Reason',
                    'Requirement',
                    'Suggestion',
                    'General Remark',
                  ], (value) => setState(() => messageType = value!)),
                ]),
                _panel('ADDITIONAL INFORMATION', [
                  _field('Requirement', requirement, maxLines: 3),
                  _field(
                    'Why is this action pending?',
                    pendingReason,
                    maxLines: 3,
                  ),
                  _field('Suggestion for Manager', suggestion, maxLines: 3),
                  _field('Remarks / Comments', remarks, maxLines: 3),
                ]),
                _panel('ATTACHMENTS / EVIDENCE', [
                  OutlinedButton.icon(
                    onPressed: () => setState(
                      () => attachments.add(
                        'worker_evidence_${attachments.length + 1}.pdf',
                      ),
                    ),
                    icon: const Icon(Icons.attach_file_rounded),
                    label: const Text('Add mock photo or document'),
                  ),
                  if (attachments.isNotEmpty)
                    ...attachments.map(
                      (file) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.description_outlined),
                        title: Text(file),
                      ),
                    ),
                ]),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: submit,
                  icon: const Icon(Icons.send_rounded),
                  label: Text(
                    completion ? 'Submit for Manager Review' : 'Submit Update',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionSummary() => Container(
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
          widget.action.id,
          style: const TextStyle(
            color: Color(0xFF1565C0),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          widget.action.subject,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 5),
        Text(
          '${widget.action.site}  •  Assigned by HSSE Manager',
          style: const TextStyle(color: Color(0xFF64748B)),
        ),
      ],
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
    String? helperText,
  }) => TextFormField(
    controller: controller,
    maxLines: maxLines,
    validator: label.endsWith('*')
        ? (value) => value == null || value.trim().isEmpty
              ? 'Please enter $label'
              : null
        : null,
    decoration: InputDecoration(labelText: label, helperText: helperText),
  );

  Widget _select(
    String label,
    String value,
    List<String> values,
    ValueChanged<String?> onChanged,
  ) => DropdownButtonFormField<String>(
    isExpanded: true,
    initialValue: value,
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
  );
}
