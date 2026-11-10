import 'package:flutter/material.dart';

/// Supported notification event types for ActionFlow HSSE Action, Request, and Calendar workflows.
enum NotificationEventType {
  // Action events
  actionAssigned,
  actionForwarded,
  contributorAdded,
  subtaskAssigned,
  subtaskDelegated,
  dueDateApproaching,
  actionOverdue,
  statusChanged,
  actionUpdated,
  actionCompleted,
  actionReopened,
  // Request events
  requestSubmitted,
  requestAssigned,
  requestApproved,
  requestRejected,
  requestForwarded,
  requestCompleted,
  // Calendar events
  calendarEventAssigned,
  calendarEventUpdated,
  calendarEventReminder,
  // System / General events
  systemAlert,
  announcement,
  general,
}

/// Filter categories for the compact notification dropdown and center.
enum NotificationCategory {
  all,
  actionReminders,
  assignments,
  updates,
}

extension NotificationCategoryExtension on NotificationCategory {
  String get label {
    switch (this) {
      case NotificationCategory.all:
        return 'All';
      case NotificationCategory.actionReminders:
        return 'Action Reminders';
      case NotificationCategory.assignments:
        return 'Assignments';
      case NotificationCategory.updates:
        return 'Updates';
    }
  }
}

extension NotificationEventTypeExtension on NotificationEventType {
  String get value {
    switch (this) {
      case NotificationEventType.actionAssigned:
        return 'action_assigned';
      case NotificationEventType.actionForwarded:
        return 'action_forwarded';
      case NotificationEventType.contributorAdded:
        return 'contributor_added';
      case NotificationEventType.subtaskAssigned:
        return 'subtask_assigned';
      case NotificationEventType.subtaskDelegated:
        return 'subtask_delegated';
      case NotificationEventType.dueDateApproaching:
        return 'due_date_approaching';
      case NotificationEventType.actionOverdue:
        return 'action_overdue';
      case NotificationEventType.statusChanged:
        return 'status_changed';
      case NotificationEventType.actionUpdated:
        return 'action_updated';
      case NotificationEventType.actionCompleted:
        return 'action_completed';
      case NotificationEventType.actionReopened:
        return 'action_reopened';
      case NotificationEventType.requestSubmitted:
        return 'request_submitted';
      case NotificationEventType.requestAssigned:
        return 'request_assigned';
      case NotificationEventType.requestApproved:
        return 'request_approved';
      case NotificationEventType.requestRejected:
        return 'request_rejected';
      case NotificationEventType.requestForwarded:
        return 'request_forwarded';
      case NotificationEventType.requestCompleted:
        return 'request_completed';
      case NotificationEventType.calendarEventAssigned:
        return 'calendar_event_assigned';
      case NotificationEventType.calendarEventUpdated:
        return 'calendar_event_updated';
      case NotificationEventType.calendarEventReminder:
        return 'calendar_event_reminder';
      case NotificationEventType.systemAlert:
        return 'system_alert';
      case NotificationEventType.announcement:
        return 'announcement';
      case NotificationEventType.general:
        return 'general';
    }
  }

  static NotificationEventType fromString(String? val) {
    switch (val?.trim().toLowerCase()) {
      case 'action_assigned':
        return NotificationEventType.actionAssigned;
      case 'action_forwarded':
        return NotificationEventType.actionForwarded;
      case 'contributor_added':
        return NotificationEventType.contributorAdded;
      case 'subtask_assigned':
        return NotificationEventType.subtaskAssigned;
      case 'subtask_delegated':
        return NotificationEventType.subtaskDelegated;
      case 'due_date_approaching':
        return NotificationEventType.dueDateApproaching;
      case 'action_overdue':
        return NotificationEventType.actionOverdue;
      case 'status_changed':
        return NotificationEventType.statusChanged;
      case 'action_updated':
        return NotificationEventType.actionUpdated;
      case 'action_completed':
        return NotificationEventType.actionCompleted;
      case 'action_reopened':
        return NotificationEventType.actionReopened;
      case 'request_submitted':
        return NotificationEventType.requestSubmitted;
      case 'request_assigned':
        return NotificationEventType.requestAssigned;
      case 'request_approved':
        return NotificationEventType.requestApproved;
      case 'request_rejected':
        return NotificationEventType.requestRejected;
      case 'request_forwarded':
        return NotificationEventType.requestForwarded;
      case 'request_completed':
        return NotificationEventType.requestCompleted;
      case 'calendar_event_assigned':
        return NotificationEventType.calendarEventAssigned;
      case 'calendar_event_updated':
        return NotificationEventType.calendarEventUpdated;
      case 'calendar_event_reminder':
        return NotificationEventType.calendarEventReminder;
      case 'system_alert':
        return NotificationEventType.systemAlert;
      case 'announcement':
        return NotificationEventType.announcement;
      case 'general':
        return NotificationEventType.general;
      default:
        final s = val?.trim().toLowerCase() ?? '';
        if (s.contains('system') || s.contains('alert')) {
          return NotificationEventType.systemAlert;
        }
        if (s.contains('announce')) {
          return NotificationEventType.announcement;
        }
        if (s.contains('request')) {
          return NotificationEventType.requestSubmitted;
        }
        if (s.contains('calendar')) {
          return NotificationEventType.calendarEventAssigned;
        }
        return NotificationEventType.general;
    }
  }

  String get label {
    switch (this) {
      case NotificationEventType.actionAssigned:
        return 'Action Assigned';
      case NotificationEventType.actionForwarded:
        return 'Action Forwarded';
      case NotificationEventType.contributorAdded:
        return 'Contributor Added';
      case NotificationEventType.subtaskAssigned:
        return 'Subtask Assigned';
      case NotificationEventType.subtaskDelegated:
        return 'Subtask Delegated';
      case NotificationEventType.dueDateApproaching:
        return 'Due Date Approaching';
      case NotificationEventType.actionOverdue:
        return 'Action Overdue';
      case NotificationEventType.statusChanged:
        return 'Status Changed';
      case NotificationEventType.actionUpdated:
        return 'Action Update';
      case NotificationEventType.actionCompleted:
        return 'Action Completed';
      case NotificationEventType.actionReopened:
        return 'Action Reopened';
      case NotificationEventType.requestSubmitted:
        return 'Request Submitted';
      case NotificationEventType.requestAssigned:
        return 'Request Assigned';
      case NotificationEventType.requestApproved:
        return 'Request Approved';
      case NotificationEventType.requestRejected:
        return 'Request Rejected';
      case NotificationEventType.requestForwarded:
        return 'Request Forwarded';
      case NotificationEventType.requestCompleted:
        return 'Request Completed';
      case NotificationEventType.calendarEventAssigned:
        return 'Calendar Event';
      case NotificationEventType.calendarEventUpdated:
        return 'Event Rescheduled';
      case NotificationEventType.calendarEventReminder:
        return 'Event Reminder';
      case NotificationEventType.systemAlert:
        return 'System Alert';
      case NotificationEventType.announcement:
        return 'Announcement';
      case NotificationEventType.general:
        return 'General';
    }
  }

  IconData get icon {
    switch (this) {
      case NotificationEventType.actionAssigned:
        return Icons.person_add_alt_1_rounded;
      case NotificationEventType.actionForwarded:
        return Icons.forward_to_inbox_rounded;
      case NotificationEventType.contributorAdded:
        return Icons.group_add_rounded;
      case NotificationEventType.subtaskAssigned:
        return Icons.playlist_add_check_rounded;
      case NotificationEventType.subtaskDelegated:
        return Icons.alt_route_rounded;
      case NotificationEventType.dueDateApproaching:
        return Icons.alarm_rounded;
      case NotificationEventType.actionOverdue:
        return Icons.warning_amber_rounded;
      case NotificationEventType.statusChanged:
        return Icons.sync_alt_rounded;
      case NotificationEventType.actionUpdated:
        return Icons.assignment_late_outlined;
      case NotificationEventType.actionCompleted:
        return Icons.check_circle_outline_rounded;
      case NotificationEventType.actionReopened:
        return Icons.replay_rounded;
      case NotificationEventType.requestSubmitted:
        return Icons.send_rounded;
      case NotificationEventType.requestAssigned:
        return Icons.assignment_ind_rounded;
      case NotificationEventType.requestApproved:
        return Icons.thumb_up_alt_rounded;
      case NotificationEventType.requestRejected:
        return Icons.thumb_down_alt_rounded;
      case NotificationEventType.requestForwarded:
        return Icons.forward_rounded;
      case NotificationEventType.requestCompleted:
        return Icons.task_alt_rounded;
      case NotificationEventType.calendarEventAssigned:
        return Icons.event_available_rounded;
      case NotificationEventType.calendarEventUpdated:
        return Icons.edit_calendar_rounded;
      case NotificationEventType.calendarEventReminder:
        return Icons.notification_important_rounded;
      case NotificationEventType.systemAlert:
        return Icons.info_outline_rounded;
      case NotificationEventType.announcement:
        return Icons.campaign_outlined;
      case NotificationEventType.general:
        return Icons.notifications_outlined;
    }
  }

  Color get color {
    switch (this) {
      case NotificationEventType.actionAssigned:
        return const Color(0xFF1565C0); // Blue
      case NotificationEventType.actionForwarded:
        return const Color(0xFF2563EB); // Royal Blue
      case NotificationEventType.contributorAdded:
        return const Color(0xFF0284C7); // Cyan
      case NotificationEventType.subtaskAssigned:
        return const Color(0xFF7C3AED); // Purple
      case NotificationEventType.subtaskDelegated:
        return const Color(0xFF9333EA); // Fuchsia
      case NotificationEventType.dueDateApproaching:
        return const Color(0xFF0284C7); // Sky Blue
      case NotificationEventType.actionOverdue:
        return const Color(0xFFDC2626); // Red
      case NotificationEventType.statusChanged:
        return const Color(0xFF8B5CF6); // Purple
      case NotificationEventType.actionUpdated:
        return const Color(0xFFEA580C); // Orange
      case NotificationEventType.actionCompleted:
        return const Color(0xFF16A34A); // Green
      case NotificationEventType.actionReopened:
        return const Color(0xFFD97706); // Amber
      case NotificationEventType.requestSubmitted:
        return const Color(0xFF0D9488); // Teal
      case NotificationEventType.requestAssigned:
        return const Color(0xFF0891B2); // Cyan
      case NotificationEventType.requestApproved:
        return const Color(0xFF16A34A); // Green
      case NotificationEventType.requestRejected:
        return const Color(0xFFDC2626); // Red
      case NotificationEventType.requestForwarded:
        return const Color(0xFFD97706); // Amber
      case NotificationEventType.requestCompleted:
        return const Color(0xFF059669); // Emerald
      case NotificationEventType.calendarEventAssigned:
        return const Color(0xFF3B82F6); // Blue
      case NotificationEventType.calendarEventUpdated:
        return const Color(0xFFF59E0B); // Amber
      case NotificationEventType.calendarEventReminder:
        return const Color(0xFFE11D48); // Rose
      case NotificationEventType.systemAlert:
        return const Color(0xFF64748B); // Slate
      case NotificationEventType.announcement:
        return const Color(0xFF0D9488); // Teal
      case NotificationEventType.general:
        return const Color(0xFF6B7280); // Gray
    }
  }
}

/// Represents an in-app notification delivered to a user.
///
/// STRICT PRIVACY & ISOLATION RULES:
/// - [userId] matches recipient's auth.uid(). Users can ONLY access their own notifications.
/// - In-app only: No external email dispatches or Resend calls occur when notifications are created.
/// - Deterministic [idempotencyKey] prevents duplicate notifications on rebuilds or retries.
@immutable
class AppNotification {
  final String id;
  final String userId;
  final String? organizationId;
  final String title;
  final String message;
  final String eventType;
  final String? actionId;
  final bool isRead;
  final String? idempotencyKey;
  final DateTime createdAt;
  final DateTime? readAt;

  const AppNotification({
    required this.id,
    required this.userId,
    this.organizationId,
    required this.title,
    required this.message,
    required this.eventType,
    this.actionId,
    this.isRead = false,
    this.idempotencyKey,
    required this.createdAt,
    this.readAt,
  });

  NotificationEventType get parsedEventType =>
      NotificationEventTypeExtension.fromString(eventType);

  NotificationCategory get category {
    switch (parsedEventType) {
      case NotificationEventType.dueDateApproaching:
      case NotificationEventType.actionOverdue:
      case NotificationEventType.calendarEventReminder:
        return NotificationCategory.actionReminders;
      case NotificationEventType.actionAssigned:
      case NotificationEventType.actionForwarded:
      case NotificationEventType.contributorAdded:
      case NotificationEventType.subtaskAssigned:
      case NotificationEventType.subtaskDelegated:
      case NotificationEventType.requestAssigned:
      case NotificationEventType.calendarEventAssigned:
        return NotificationCategory.assignments;
      case NotificationEventType.statusChanged:
      case NotificationEventType.actionUpdated:
      case NotificationEventType.actionCompleted:
      case NotificationEventType.actionReopened:
      case NotificationEventType.requestSubmitted:
      case NotificationEventType.requestApproved:
      case NotificationEventType.requestRejected:
      case NotificationEventType.requestForwarded:
      case NotificationEventType.requestCompleted:
      case NotificationEventType.calendarEventUpdated:
        return NotificationCategory.updates;
      case NotificationEventType.systemAlert:
      case NotificationEventType.announcement:
      case NotificationEventType.general:
        return NotificationCategory.all;
    }
  }

  /// Whether this notification is associated with an HSSE action workflow.
  bool get isActionRelated {
    switch (parsedEventType) {
      case NotificationEventType.actionAssigned:
      case NotificationEventType.actionForwarded:
      case NotificationEventType.contributorAdded:
      case NotificationEventType.subtaskAssigned:
      case NotificationEventType.subtaskDelegated:
      case NotificationEventType.dueDateApproaching:
      case NotificationEventType.actionOverdue:
      case NotificationEventType.statusChanged:
      case NotificationEventType.actionUpdated:
      case NotificationEventType.actionCompleted:
      case NotificationEventType.actionReopened:
        return true;
      case NotificationEventType.requestSubmitted:
      case NotificationEventType.requestAssigned:
      case NotificationEventType.requestApproved:
      case NotificationEventType.requestRejected:
      case NotificationEventType.requestForwarded:
      case NotificationEventType.requestCompleted:
      case NotificationEventType.calendarEventAssigned:
      case NotificationEventType.calendarEventUpdated:
      case NotificationEventType.calendarEventReminder:
      case NotificationEventType.systemAlert:
      case NotificationEventType.announcement:
      case NotificationEventType.general:
        return false;
    }
  }

  /// Whether this notification is associated with a Request workflow.
  bool get isRequestRelated {
    switch (parsedEventType) {
      case NotificationEventType.requestSubmitted:
      case NotificationEventType.requestAssigned:
      case NotificationEventType.requestApproved:
      case NotificationEventType.requestRejected:
      case NotificationEventType.requestForwarded:
      case NotificationEventType.requestCompleted:
        return true;
      default:
        return false;
    }
  }

  /// Whether this notification is associated with a Calendar event.
  bool get isCalendarRelated {
    switch (parsedEventType) {
      case NotificationEventType.calendarEventAssigned:
      case NotificationEventType.calendarEventUpdated:
      case NotificationEventType.calendarEventReminder:
        return true;
      default:
        return false;
    }
  }

  /// Extracts the target action identifier from explicit [actionId] or [title]/[message].
  String? get effectiveActionIdentifier {
    final explicit = actionId?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    // Attempt extracting UUID from title or message
    final combined = '$title $message';
    final uuidMatch = RegExp(
      r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',
    ).firstMatch(combined);
    if (uuidMatch != null) return uuidMatch.group(0);

    // Attempt extracting action number (e.g. AC-1029, ACT-1048, AF-1042)
    final codeMatch = RegExp(
      r'\b(?:AC|ACT|AF)-\d+\b',
      caseSensitive: false,
    ).firstMatch(combined);
    if (codeMatch != null) return codeMatch.group(0);

    return null;
  }

  /// Extracts the target request identifier if present.
  String? get effectiveRequestIdentifier {
    final explicit = actionId?.trim();
    if (explicit != null && explicit.toUpperCase().startsWith('REQ-')) {
      return explicit;
    }
    final combined = '$title $message';
    final reqMatch = RegExp(
      r'\bREQ-[0-9a-zA-Z-]+\b',
      caseSensitive: false,
    ).firstMatch(combined);
    if (reqMatch != null) return reqMatch.group(0);
    return null;
  }

  IconData get iconData => parsedEventType.icon;
  Color get themeColor => parsedEventType.color;

  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      final mins = difference.inMinutes;
      return '$mins min${mins == 1 ? '' : 's'} ago';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours hour${hours == 1 ? '' : 's'} ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}';
    }
  }

  AppNotification copyWith({
    String? id,
    String? userId,
    String? organizationId,
    String? title,
    String? message,
    String? eventType,
    String? actionId,
    bool? isRead,
    String? idempotencyKey,
    DateTime? createdAt,
    DateTime? readAt,
  }) {
    return AppNotification(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      organizationId: organizationId ?? this.organizationId,
      title: title ?? this.title,
      message: message ?? this.message,
      eventType: eventType ?? this.eventType,
      actionId: actionId ?? this.actionId,
      isRead: isRead ?? this.isRead,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      createdAt: createdAt ?? this.createdAt,
      readAt: readAt ?? this.readAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'organization_id': organizationId,
      'title': title,
      'message': message,
      'event_type': eventType,
      'action_id': actionId,
      'is_read': isRead,
      'idempotency_key': idempotencyKey,
      'created_at': createdAt.toIso8601String(),
      'read_at': readAt?.toIso8601String(),
    };
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      organizationId: json['organization_id'] as String?,
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      eventType: json['event_type'] as String? ?? 'action_assigned',
      actionId: json['action_id'] as String?,
      isRead: json['is_read'] as bool? ?? false,
      idempotencyKey: json['idempotency_key'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      readAt: json['read_at'] != null
          ? DateTime.tryParse(json['read_at'].toString())
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppNotification &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          userId == other.userId &&
          title == other.title &&
          message == other.message &&
          eventType == other.eventType &&
          actionId == other.actionId &&
          isRead == other.isRead &&
          idempotencyKey == other.idempotencyKey;

  @override
  int get hashCode =>
      id.hashCode ^
      userId.hashCode ^
      title.hashCode ^
      message.hashCode ^
      eventType.hashCode ^
      actionId.hashCode ^
      isRead.hashCode ^
      idempotencyKey.hashCode;
}
