import '../../dashboard/manager_dashboard/models/action_record.dart';

/// Sanitized action payload retrieved by an external contractor via secure token
class ExternalActionPayload {
  final String actionId;
  final String actionNumber;
  final String title;
  final String description;
  final String actionRequired;
  final String category;
  final String priority;
  final String status;
  final int percentComplete;
  final String dateRaised;
  final String startDate;
  final String targetDate;
  final String dueDate;
  final String nextFollowUpDate;
  final String department;
  final String site;
  final String organizationName;
  final bool isClosed;
  final List<Map<String, dynamic>> recentHistory;
  final List<ActionSubTask> subTasks;

  final String recipientId;
  final String recipientName;
  final String recipientEmail;
  final String companyName;
  final String phone;

  final DateTime? expiresAt;
  final int accessCount;

  const ExternalActionPayload({
    required this.actionId,
    required this.actionNumber,
    required this.title,
    required this.description,
    required this.actionRequired,
    required this.category,
    required this.priority,
    required this.status,
    required this.percentComplete,
    required this.dateRaised,
    required this.startDate,
    required this.targetDate,
    required this.dueDate,
    required this.nextFollowUpDate,
    required this.department,
    required this.site,
    required this.organizationName,
    required this.isClosed,
    required this.recentHistory,
    this.subTasks = const [],
    required this.recipientId,
    required this.recipientName,
    required this.recipientEmail,
    required this.companyName,
    required this.phone,
    this.expiresAt,
    this.accessCount = 0,
  });

  factory ExternalActionPayload.fromJson(Map<String, dynamic> json) {
    final action = json['action'] is Map
        ? Map<String, dynamic>.from(json['action'] as Map)
        : json;
    final recipient = json['recipient'] is Map
        ? Map<String, dynamic>.from(json['recipient'] as Map)
        : <String, dynamic>{
            'id': json['recipient_id'] ?? json['recipientId'],
            'email': json['recipient_email'] ?? json['recipientEmail'],
            'name': json['recipient_name'] ?? json['recipientName'],
            'company_name': json['company_name'] ?? json['companyName'],
            'phone': json['phone'],
          };
    final token = json['token'] is Map
        ? Map<String, dynamic>.from(json['token'] as Map)
        : json;

    final rawHistory = action['recent_history'];
    final List<Map<String, dynamic>> history = [];
    if (rawHistory is List) {
      for (final item in rawHistory) {
        if (item is Map) {
          history.add(Map<String, dynamic>.from(item));
        }
      }
    }

    final recipId = recipient['id']?.toString() ?? '';
    final recipEmail = recipient['email']?.toString() ?? '';

    final rawSubtasks = action['subtasks'] ?? action['sub_tasks'];
    final List<ActionSubTask> filteredSubTasks = [];
    if (rawSubtasks is List) {
      for (final item in rawSubtasks) {
        if (item is Map) {
          final st = ActionSubTask.fromJson(Map<String, dynamic>.from(item));
          final matchesId = st.assignedStaffId.isNotEmpty && st.assignedStaffId == recipId;
          final matchesEmail = st.assignedStaffEmail.isNotEmpty &&
              st.assignedStaffEmail.toLowerCase() == recipEmail.toLowerCase();
          // Contractor must only receive tasks authorized for them
          if (st.isExternal && (matchesId || matchesEmail)) {
            filteredSubTasks.add(st);
          }
        }
      }
    }

    return ExternalActionPayload(
      actionId: action['id']?.toString() ?? '',
      actionNumber: action['action_number']?.toString() ?? '',
      title: action['title']?.toString() ?? '',
      description: action['description']?.toString() ?? '',
      actionRequired: action['action_required']?.toString() ?? '',
      category: action['category']?.toString() ?? 'General',
      priority: action['priority']?.toString() ?? 'Medium',
      status: action['status']?.toString() ?? 'Open',
      percentComplete: (action['percent_complete'] as num?)?.toInt() ?? 0,
      dateRaised: action['date_raised']?.toString() ?? '',
      startDate: action['start_date']?.toString() ?? '',
      targetDate: action['target_date']?.toString() ?? '',
      dueDate: action['due_date']?.toString() ?? '',
      nextFollowUpDate: action['next_follow_up_date']?.toString() ?? '',
      department: action['department']?.toString() ?? '',
      site: action['site']?.toString() ?? '',
      organizationName: action['organization_name']?.toString() ?? 'ActionFlow',
      isClosed: action['is_closed'] == true || action['status'] == 'Closed',
      recentHistory: history,
      subTasks: filteredSubTasks,
      recipientId: recipId,
      recipientName: recipient['name']?.toString() ?? '',
      recipientEmail: recipEmail,
      companyName: recipient['company_name']?.toString() ?? '',
      phone: recipient['phone']?.toString() ?? '',
      expiresAt: token['expires_at'] != null
          ? DateTime.tryParse(token['expires_at'].toString())
          : null,
      accessCount: (token['access_count'] as num?)?.toInt() ?? 0,
    );
  }
}
