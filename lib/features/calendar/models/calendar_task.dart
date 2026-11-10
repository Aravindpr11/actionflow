import 'package:flutter/foundation.dart';

/// Priority levels for personal calendar tasks.
enum CalendarTaskPriority {
  low,
  medium,
  high,
  critical,
}

extension CalendarTaskPriorityExtension on CalendarTaskPriority {
  String get label {
    switch (this) {
      case CalendarTaskPriority.low:
        return 'Low';
      case CalendarTaskPriority.medium:
        return 'Medium';
      case CalendarTaskPriority.high:
        return 'High';
      case CalendarTaskPriority.critical:
        return 'Critical';
    }
  }

  static CalendarTaskPriority fromString(String? val) {
    switch (val?.trim().toLowerCase()) {
      case 'low':
        return CalendarTaskPriority.low;
      case 'high':
        return CalendarTaskPriority.high;
      case 'critical':
        return CalendarTaskPriority.critical;
      case 'medium':
      default:
        return CalendarTaskPriority.medium;
    }
  }
}

/// Represents a private, personal task created by a user directly on the Calendar.
///
/// STRICT PRIVACY RULES:
/// - strictly private to [userId] (auth.uid())
/// - NO sharing, NO recipient picker, NO assignment to other users
/// - NEVER alters, links to, or modifies official HSSE Actions
/// - Managers cannot view or manage other users' personal tasks
@immutable
class CalendarTask {
  final String id;
  final String userId;
  final String? organizationId;
  final String title;
  final String? description;
  final DateTime? startDate;
  final DateTime dueDate;
  final String priority;
  final bool isCompleted;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  CalendarTask({
    required this.id,
    required this.userId,
    this.organizationId,
    required this.title,
    this.description,
    this.startDate,
    required this.dueDate,
    this.priority = 'Medium',
    this.isCompleted = false,
    this.completedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  CalendarTask copyWith({
    String? id,
    String? userId,
    String? organizationId,
    String? title,
    String? description,
    DateTime? startDate,
    DateTime? dueDate,
    String? priority,
    bool? isCompleted,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CalendarTask(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      organizationId: organizationId ?? this.organizationId,
      title: title ?? this.title,
      description: description ?? this.description,
      startDate: startDate ?? this.startDate,
      dueDate: dueDate ?? this.dueDate,
      priority: priority ?? this.priority,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: clearCompletedAt
          ? null
          : ((isCompleted == false && completedAt == null)
              ? null
              : (completedAt ?? this.completedAt)),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'organization_id': organizationId,
      'title': title,
      'description': description,
      'start_date': startDate?.toUtc().toIso8601String(),
      'due_date': dueDate.toUtc().toIso8601String(),
      'priority': priority,
      'is_completed': isCompleted,
      'completed_at': completedAt?.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory CalendarTask.fromJson(Map<String, dynamic> json) {
    DateTime parseDt(dynamic val, DateTime fallback) {
      if (val == null) return fallback;
      if (val is DateTime) return val.toLocal();
      final dt = DateTime.tryParse(val.toString());
      return dt != null ? dt.toLocal() : fallback;
    }

    DateTime? parseDtNullable(dynamic val) {
      if (val == null) return null;
      if (val is DateTime) return val.toLocal();
      final dt = DateTime.tryParse(val.toString());
      return dt?.toLocal();
    }

    return CalendarTask(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      organizationId: json['organization_id']?.toString(),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      startDate: parseDtNullable(json['start_date']),
      dueDate: parseDt(json['due_date'], DateTime.now()),
      priority: json['priority']?.toString() ?? 'Medium',
      isCompleted: json['is_completed'] == true,
      completedAt: parseDtNullable(json['completed_at']),
      createdAt: parseDt(json['created_at'], DateTime.now()),
      updatedAt: parseDt(json['updated_at'], DateTime.now()),
    );
  }

  /// Date at local midnight for day-level comparison without timezone shift
  DateTime get dueDayMidnight => DateTime(dueDate.year, dueDate.month, dueDate.day);

  bool isOverdue([DateTime? referenceDate]) {
    if (isCompleted) return false;
    final now = referenceDate ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return dueDayMidnight.isBefore(today);
  }

  bool isDueToday([DateTime? referenceDate]) {
    if (isCompleted) return false;
    final now = referenceDate ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return dueDayMidnight.isAtSameMomentAs(today);
  }

  bool isUpcoming([DateTime? referenceDate]) {
    if (isCompleted) return false;
    final now = referenceDate ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return dueDayMidnight.isAfter(today);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalendarTask &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

