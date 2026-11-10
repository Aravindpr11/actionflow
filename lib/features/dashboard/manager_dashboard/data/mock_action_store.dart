import '../models/action_email_reminder_job.dart';
import '../models/action_record.dart';
import '../models/external_recipient.dart';

class MockActionStore {
  MockActionStore._();

  static final MockActionStore instance = MockActionStore._();

  final List<ExternalRecipient> externalRecipients = [];
  final List<ActionEmailReminderJob> emailReminders = [];
  final List<Map<String, dynamic>> profiles = [];

  final List<ActionRecord> actions = [
    ActionRecord(
      id: 'AF-1042',
      actionNumber: 'AC-1029',
      subject: 'Equipment Inspection',
      actionRequired: 'Complete inspection and upload the signed checklist.',
      division: 'Operations',
      department: 'Maintenance',
      site: 'North Plant',
      category: 'Inspection',
      source: 'Monthly HSSE audit',
      assignedBy: 'M. Ali',
      assignedTo: 'R. Kumar',
      priority: 'High',
      status: 'Open',
      percentComplete: 65,
      dateRaised: '01 Aug 2026',
      targetDate: '12 Aug 2026',
      nextFollowUpDate: '20 Aug 2026',
      description: 'Verify equipment guarding and record any corrective work.',
      history: ['01 Aug 2026: Action raised by M. Ali.'],
    ),
    ActionRecord(
      id: 'AF-1048',
      actionNumber: 'AC-1048',
      subject: 'Safety Training',
      actionRequired: 'Deliver refresher training to the warehouse team.',
      division: 'Operations',
      department: 'HSE',
      site: 'Warehouse B',
      category: 'Training',
      assignedBy: 'R. Kumar',
      assignedTo: 'M. Ali',
      priority: 'Medium',
      status: 'In Progress',
      percentComplete: 40,
      dateRaised: '03 Aug 2026',
      targetDate: '18 Aug 2026',
      nextFollowUpDate: '24 Aug 2026',
      description: 'Coordinate attendance and retain the completed register.',
      history: [
        '03 Aug 2026: Action raised by R. Kumar.',
        '12 Aug 2026: Training scheduled.',
      ],
    ),
    ActionRecord(
      id: 'AF-1053',
      actionNumber: 'AC-1053',
      subject: 'Site Inspection',
      actionRequired: 'Close the findings from the Central Yard inspection.',
      division: 'Projects',
      department: 'HSE',
      site: 'Central Yard',
      category: 'Inspection',
      assignedBy: 'N. Shah',
      assignedTo: 'S. Jones',
      priority: 'Critical',
      status: 'Overdue',
      percentComplete: 80,
      dateRaised: '02 Aug 2026',
      targetDate: '08 Aug 2026',
      nextFollowUpDate: '15 Aug 2026',
      description:
          'Resolve the remaining critical finding and provide evidence.',
      history: ['02 Aug 2026: Critical finding raised by N. Shah.'],
    ),
    ActionRecord(
      id: 'AF-1061',
      actionNumber: 'AC-1061',
      subject: 'Emergency Exit Check',
      actionRequired: 'Clear and verify all emergency exit routes.',
      division: 'Corporate',
      department: 'Operations',
      site: 'Admin Block',
      category: 'Emergency Preparedness',
      assignedBy: 'M. Ali',
      assignedTo: 'N. Shah',
      priority: 'High',
      status: 'Pending Review',
      percentComplete: 90,
      dateRaised: '05 Aug 2026',
      targetDate: '16 Aug 2026',
      nextFollowUpDate: '19 Aug 2026',
      description: 'Review photographic evidence with the facilities lead.',
      history: [
        '05 Aug 2026: Action raised by M. Ali.',
        '14 Aug 2026: Evidence submitted.',
      ],
    ),
    ActionRecord(
      id: 'AF-1067',
      actionNumber: 'AC-1067',
      subject: 'PPE Compliance Review',
      actionRequired: 'Complete the PPE compliance review and archive records.',
      division: 'Operations',
      department: 'HSE',
      site: 'Storage Area',
      category: 'Compliance',
      assignedBy: 'M. Ali',
      assignedTo: 'T. Reed',
      priority: 'Medium',
      status: 'Closed',
      percentComplete: 100,
      dateRaised: '07 Aug 2026',
      targetDate: '22 Aug 2026',
      closeDate: '21 Aug 2026',
      verifiedBy: 'A. Manager',
      description: 'Review completed PPE issue records.',
      history: [
        '07 Aug 2026: Action raised by M. Ali.',
        '21 Aug 2026: Action verified and closed.',
      ],
    ),
  ];

  int nextId() => 128 + actions.length;

  void add(ActionRecord action) => actions.insert(0, action);

  void update(ActionRecord action) {
    final index = actions.indexWhere((item) => item.id == action.id);
    if (index >= 0) actions[index] = action;
  }

  bool deleteAction(String id) {
    final initialLen = actions.length;
    actions.removeWhere((item) => item.id == id);
    return actions.length < initialLen;
  }
}
