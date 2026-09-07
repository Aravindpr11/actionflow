import 'package:flutter/material.dart';

import '../../../users/models/person.dart';
import '../models/action_record.dart';

class ActionDetailsScreen extends StatelessWidget {
  const ActionDetailsScreen({
    required this.action,
    this.onUpdateAction,
    super.key,
  });

  final ActionRecord action;
  final VoidCallback? onUpdateAction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        title: Text(action.id),
        actions: [
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.edit_rounded),
            label: const Text('Edit Action'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _hero(context),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 760;
                  final width = wide
                      ? (constraints.maxWidth - 16) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      SizedBox(
                        width: width,
                        child: _panel('Action information', [
                          _detail('Action Required', action.actionRequired),
                          _detail(
                            'Description',
                            action.description.isEmpty
                                ? 'No description provided.'
                                : action.description,
                          ),
                          _detail(
                            'Division / Department',
                            '${action.division} / ${action.department.isEmpty ? 'Not set' : action.department}',
                          ),
                        ]),
                      ),
                      SizedBox(
                        width: width,
                        child: _panel('Ownership & dates', [
                          _detail('Assigned Worker', action.assignedTo),
                          if (action.primaryAssignee != null) ...[
                            _detail(
                              action.primaryAssignee!.type ==
                                      PersonType.internalUser
                                  ? 'Internal Primary Person'
                                  : 'External Primary Person',
                              '${action.primaryAssignee!.name} • ${action.primaryAssignee!.typeLabel}',
                            ),
                            _detail(
                              'Primary Contact',
                              '${action.primaryAssignee!.email} / ${action.primaryAssignee!.phone}',
                            ),
                          ],
                          if (action.additionalPeople.any(
                            (person) => person.type == PersonType.internalUser,
                          ))
                            _detail(
                              'Additional Internal People',
                              action.additionalPeople
                                  .where(
                                    (person) =>
                                        person.type == PersonType.internalUser,
                                  )
                                  .map(
                                    (person) =>
                                        '${person.name} • ${person.email}',
                                  )
                                  .join(', '),
                            ),
                          if (action.additionalPeople.any(
                            (person) =>
                                person.type == PersonType.externalWorker,
                          ))
                            _detail(
                              'Additional External People',
                              action.additionalPeople
                                  .where(
                                    (person) =>
                                        person.type ==
                                        PersonType.externalWorker,
                                  )
                                  .map(
                                    (person) =>
                                        '${person.name} • ${person.email}',
                                  )
                                  .join(', '),
                            ),
                          _detail('Project / Site', action.site),
                          _detail('Target Date', action.targetDate),
                          _detail('Follow-up Date', action.followUp),
                        ]),
                      ),
                      SizedBox(
                        width: width,
                        child: _panel('Evidence / attachments', [
                          if (action.attachments.isEmpty)
                            const Text(
                              'No attachments added yet.',
                              style: TextStyle(color: Color(0xFF64748B)),
                            ),
                          ...action.attachments.map(
                            (file) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.attach_file_rounded),
                              title: Text(file),
                            ),
                          ),
                        ]),
                      ),
                      SizedBox(
                        width: width,
                        child: _panel(
                          'Action history',
                          action.history.isEmpty
                              ? [const Text('No history recorded.')]
                              : action.history
                                    .map(
                                      (item) => ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: const Icon(
                                          Icons.history_rounded,
                                          color: Color(0xFF1565C0),
                                        ),
                                        title: Text(item),
                                      ),
                                    )
                                    .toList(),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.add_alarm_rounded),
                    label: const Text('Add Follow-up'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onUpdateAction ?? () {},
                    icon: const Icon(Icons.sync_rounded),
                    label: Text(
                      onUpdateAction == null
                          ? 'Update Status'
                          : 'Update Action',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Edit Action'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      runSpacing: 16,
      children: [
        SizedBox(
          width: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                action.subject,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${action.id}  •  ${action.category.isEmpty ? 'HSSE Action' : action.category}',
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        Row(
          children: [
            _badge(action.priority, const Color(0xFFF57C00)),
            const SizedBox(width: 8),
            _badge(action.status, _statusColor(action.status)),
          ],
        ),
      ],
    ),
  );

  Widget _panel(String title, List<Widget> children) => Container(
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
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 14),
        ...children,
      ],
    ),
  );

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
        ),
      ],
    ),
  );

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
    ),
  );

  Color _statusColor(String status) => status == 'Closed'
      ? const Color(0xFF2E7D32)
      : status == 'Overdue'
      ? const Color(0xFFF57C00)
      : const Color(0xFF1565C0);
}
