import '../../../users/models/person.dart';

class ActionRecord {
  ActionRecord({
    required this.id,
    required this.subject,
    required this.actionRequired,
    required this.division,
    required this.assignedTo,
    this.department = '',
    this.site = '',
    this.category = '',
    this.source = '',
    this.priority = 'Medium',
    this.status = 'Open',
    this.percentComplete = 0,
    this.supportingPerson = '',
    this.dateRaised = '',
    this.targetDate = '',
    this.lastFollowUpDate = '',
    this.nextFollowUpDate = '',
    this.closeDate = '',
    this.verifiedBy = '',
    this.attachments = const [],
    this.description = '',
    this.history = const [],
    this.workerMessageSubject = '',
    this.workerMessage = '',
    this.messageType = 'Progress Update',
    this.requirement = '',
    this.pendingReason = '',
    this.suggestion = '',
    this.remarks = '',
    this.managerMessage = '',
    this.primaryAssignee,
    this.additionalPeople = const [],
    this.emailReminders = const [],
  });

  final String id;
  final String subject;
  final String actionRequired;
  final String division;
  final String department;
  final String site;
  final String category;
  final String source;
  final String assignedTo;
  final String priority;
  final String status;
  final int percentComplete;
  final String supportingPerson;
  final String dateRaised;
  final String targetDate;
  final String lastFollowUpDate;
  final String nextFollowUpDate;
  final String closeDate;
  final String verifiedBy;
  final List<String> attachments;
  final String description;
  final List<String> history;
  final String workerMessageSubject;
  final String workerMessage;
  final String messageType;
  final String requirement;
  final String pendingReason;
  final String suggestion;
  final String remarks;
  final String managerMessage;
  final ActionPersonReference? primaryAssignee;
  final List<ActionPersonReference> additionalPeople;
  final List<ActionEmailReminder> emailReminders;

  String get percent => '$percentComplete%';
  String get followUp =>
      nextFollowUpDate.isEmpty ? 'Not set' : nextFollowUpDate;

  ActionRecord copyWith({
    String? status,
    int? percentComplete,
    String? nextFollowUpDate,
    List<String>? history,
    String? workerMessageSubject,
    String? workerMessage,
    String? messageType,
    String? requirement,
    String? pendingReason,
    String? suggestion,
    String? remarks,
    String? managerMessage,
    List<String>? attachments,
    ActionPersonReference? primaryAssignee,
    List<ActionPersonReference>? additionalPeople,
    List<ActionEmailReminder>? emailReminders,
  }) {
    return ActionRecord(
      id: id,
      subject: subject,
      actionRequired: actionRequired,
      division: division,
      assignedTo: assignedTo,
      department: department,
      site: site,
      category: category,
      source: source,
      priority: priority,
      status: status ?? this.status,
      percentComplete: percentComplete ?? this.percentComplete,
      supportingPerson: supportingPerson,
      dateRaised: dateRaised,
      targetDate: targetDate,
      lastFollowUpDate: lastFollowUpDate,
      nextFollowUpDate: nextFollowUpDate ?? this.nextFollowUpDate,
      closeDate: closeDate,
      verifiedBy: verifiedBy,
      attachments: attachments ?? this.attachments,
      description: description,
      history: history ?? this.history,
      workerMessageSubject: workerMessageSubject ?? this.workerMessageSubject,
      workerMessage: workerMessage ?? this.workerMessage,
      messageType: messageType ?? this.messageType,
      requirement: requirement ?? this.requirement,
      pendingReason: pendingReason ?? this.pendingReason,
      suggestion: suggestion ?? this.suggestion,
      remarks: remarks ?? this.remarks,
      managerMessage: managerMessage ?? this.managerMessage,
      primaryAssignee: primaryAssignee ?? this.primaryAssignee,
      additionalPeople: additionalPeople ?? this.additionalPeople,
      emailReminders: emailReminders ?? this.emailReminders,
    );
  }
}

class ActionEmailReminder {
  const ActionEmailReminder({
    required this.id,
    this.isEnabled = true,
    this.date = '',
    this.time = '09:00 AM',
    this.recipients = const [],
  });

  final String id;
  final bool isEnabled;
  final String date;
  final String time;
  final List<ActionPersonReference> recipients;

  ActionEmailReminder copyWith({
    String? id,
    bool? isEnabled,
    String? date,
    String? time,
    List<ActionPersonReference>? recipients,
  }) {
    return ActionEmailReminder(
      id: id ?? this.id,
      isEnabled: isEnabled ?? this.isEnabled,
      date: date ?? this.date,
      time: time ?? this.time,
      recipients: recipients ?? this.recipients,
    );
  }
}
