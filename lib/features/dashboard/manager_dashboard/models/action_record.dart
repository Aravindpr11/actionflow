import 'dart:convert';
import 'package:collection/collection.dart';
import '../../../users/models/person.dart';
import 'action_email_reminder_job.dart';
import 'external_recipient.dart';

class ActionSubTask {
  const ActionSubTask({
    required this.id,
    required this.parentActionId,
    required this.title,
    required this.instruction,
    required this.assignedStaff,
    this.assignedStaffId = '',
    this.assignedStaffEmail = '',
    this.assigneeType = 'internal',
    this.dueDate = '',
    this.status = 'Open',
    this.progressWeight = 20,
    this.remarks = '',
    this.evidence = '',
    this.completedAt = '',
    this.completedBy = '',
    this.reopenReason = '',
  });

  final String id;
  final String parentActionId;
  final String title;
  final String instruction;
  final String assignedStaff;
  final String assignedStaffId;
  final String assignedStaffEmail;
  final String assigneeType; // 'internal' | 'external'
  final String dueDate;
  final String status; // 'Open', 'In Progress', 'Completed'
  final int progressWeight; // percentage contribution e.g. 20
  final String remarks;
  final String evidence;
  final String completedAt;
  final String completedBy;
  final String reopenReason;

  bool get isCompleted => status.toLowerCase() == 'completed';
  bool get isExternal => assigneeType.toLowerCase() == 'external';
  bool get isInternal => !isExternal;
  bool get isReopened => reopenReason.isNotEmpty && !isCompleted;

  ActionSubTask copyWith({
    String? id,
    String? parentActionId,
    String? title,
    String? instruction,
    String? assignedStaff,
    String? assignedStaffId,
    String? assignedStaffEmail,
    String? assigneeType,
    String? dueDate,
    String? status,
    int? progressWeight,
    String? remarks,
    String? evidence,
    String? completedAt,
    String? completedBy,
    String? reopenReason,
  }) {
    return ActionSubTask(
      id: id ?? this.id,
      parentActionId: parentActionId ?? this.parentActionId,
      title: title ?? this.title,
      instruction: instruction ?? this.instruction,
      assignedStaff: assignedStaff ?? this.assignedStaff,
      assignedStaffId: assignedStaffId ?? this.assignedStaffId,
      assignedStaffEmail: assignedStaffEmail ?? this.assignedStaffEmail,
      assigneeType: assigneeType ?? this.assigneeType,
      dueDate: dueDate ?? this.dueDate,
      status: status ?? this.status,
      progressWeight: progressWeight ?? this.progressWeight,
      remarks: remarks ?? this.remarks,
      evidence: evidence ?? this.evidence,
      completedAt: completedAt ?? this.completedAt,
      completedBy: completedBy ?? this.completedBy,
      reopenReason: reopenReason ?? this.reopenReason,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'parent_action_id': parentActionId,
    'title': title,
    'instruction': instruction,
    'assigned_staff': assignedStaff,
    'assigned_staff_id': assignedStaffId,
    'assigned_staff_email': assignedStaffEmail,
    'assignee_type': assigneeType,
    'due_date': dueDate,
    'status': status,
    'progress_weight': progressWeight,
    'remarks': remarks,
    'evidence': evidence,
    'completed_at': completedAt,
    'completed_by': completedBy,
    'reopen_reason': reopenReason,
  };

  factory ActionSubTask.fromJson(Map<String, dynamic> json) {
    final rawType = (json['assignee_type'] as String?) ??
        (json['assigneeType'] as String?) ??
        'internal';
    final assigneeType =
        rawType.toLowerCase() == 'external' ? 'external' : 'internal';

    return ActionSubTask(
      id: (json['id'] as String?) ?? '',
      parentActionId:
          (json['parent_action_id'] as String?) ??
          (json['parentActionId'] as String?) ??
          '',
      title: (json['title'] as String?) ?? '',
      instruction: (json['instruction'] as String?) ?? '',
      assignedStaff:
          (json['assigned_staff'] as String?) ??
          (json['assignedStaff'] as String?) ??
          '',
      assignedStaffId:
          (json['assigned_staff_id'] as String?) ??
          (json['assignedStaffId'] as String?) ??
          '',
      assignedStaffEmail:
          (json['assigned_staff_email'] as String?) ??
          (json['assignedStaffEmail'] as String?) ??
          '',
      assigneeType: assigneeType,
      dueDate:
          (json['due_date'] as String?) ?? (json['dueDate'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'Open',
      progressWeight:
          (json['progress_weight'] as num?)?.toInt() ??
          (json['progressWeight'] as num?)?.toInt() ??
          20,
      remarks: (json['remarks'] as String?) ?? '',
      evidence: (json['evidence'] as String?) ?? '',
      completedAt:
          (json['completed_at'] as String?) ??
          (json['completedAt'] as String?) ??
          '',
      completedBy:
          (json['completed_by'] as String?) ??
          (json['completedBy'] as String?) ??
          '',
      reopenReason:
          (json['reopen_reason'] as String?) ??
          (json['reopenReason'] as String?) ??
          '',
    );
  }
}

class ActionFollowUpRecord {
  const ActionFollowUpRecord({
    required this.id,
    required this.actionId,
    required this.followUpDate,
    this.notes = '',
    this.status = 'Scheduled',
    this.actualProgress,
    this.createdBy = '',
    this.createdByName = '',
    this.completedAt,
    this.createdAt,
  });

  final String id;
  final String actionId;
  final String followUpDate; // 'DD MMM YYYY'
  final String notes;
  final String status; // 'Scheduled', 'Completed', 'Rescheduled', 'Missed'
  final int? actualProgress;
  final String createdBy;
  final String createdByName;
  final DateTime? completedAt;
  final DateTime? createdAt;

  bool get isCompleted => status.toLowerCase() == 'completed';
  bool get isCancelled => status.toLowerCase() == 'cancelled';
  bool get isScheduled => status.toLowerCase() == 'scheduled';

  DateTime? get followUpDateTime {
    final str = followUpDate.trim();
    if (str.isEmpty || str.toLowerCase() == 'not set') return null;
    final dbFormatted = ActionRecord.formatDateForDb(str);
    return DateTime.tryParse(dbFormatted) ?? DateTime.tryParse(str);
  }

  ActionFollowUpRecord copyWith({
    String? id,
    String? actionId,
    String? followUpDate,
    String? notes,
    String? status,
    int? actualProgress,
    String? createdBy,
    String? createdByName,
    DateTime? completedAt,
    DateTime? createdAt,
  }) {
    return ActionFollowUpRecord(
      id: id ?? this.id,
      actionId: actionId ?? this.actionId,
      followUpDate: followUpDate ?? this.followUpDate,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      actualProgress: actualProgress ?? this.actualProgress,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'action_id': actionId,
    'follow_up_date': ActionRecord.formatDateForDb(followUpDate),
    'notes': notes,
    'status': status,
    'actual_progress': actualProgress,
    'created_by': createdBy,
    'completed_at': completedAt?.toIso8601String(),
    'created_at': createdAt?.toIso8601String(),
  };

  factory ActionFollowUpRecord.fromJson(Map<String, dynamic> json) {
    String creator = '';
    if (json['creator'] is Map) {
      creator = (json['creator']['full_name'] as String?) ?? '';
    } else if (json['created_by_name'] != null) {
      creator = json['created_by_name'].toString();
    }

    return ActionFollowUpRecord(
      id: (json['id'] as String?) ?? '',
      actionId: (json['action_id'] as String?) ?? '',
      followUpDate: ActionRecord.formatDateForUi(json['follow_up_date']),
      notes: (json['notes'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'Scheduled',
      actualProgress: (json['actual_progress'] as num?)?.toInt(),
      createdBy: (json['created_by'] as String?) ?? '',
      createdByName: creator,
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }
}

class ActionAssigneeRecord {
  const ActionAssigneeRecord({
    required this.id,
    required this.actionId,
    required this.profileId,
    this.profileName = '',
    this.profileEmail = '',
    this.assignmentRole = 'assignee', // 'owner', 'assignee'
    this.isRequired = true,
    this.workCompleted = false,
    this.completedAt,
    this.assignedBy = '',
    this.createdAt,
  });

  final String id;
  final String actionId;
  final String profileId;
  final String profileName;
  final String profileEmail;
  final String assignmentRole;
  final bool isRequired;
  final bool workCompleted;
  final DateTime? completedAt;
  final String assignedBy;
  final DateTime? createdAt;

  bool get isOwner => assignmentRole.toLowerCase() == 'owner';

  ActionAssigneeRecord copyWith({
    String? id,
    String? actionId,
    String? profileId,
    String? profileName,
    String? profileEmail,
    String? assignmentRole,
    bool? isRequired,
    bool? workCompleted,
    DateTime? completedAt,
    String? assignedBy,
    DateTime? createdAt,
  }) {
    return ActionAssigneeRecord(
      id: id ?? this.id,
      actionId: actionId ?? this.actionId,
      profileId: profileId ?? this.profileId,
      profileName: profileName ?? this.profileName,
      profileEmail: profileEmail ?? this.profileEmail,
      assignmentRole: assignmentRole ?? this.assignmentRole,
      isRequired: isRequired ?? this.isRequired,
      workCompleted: workCompleted ?? this.workCompleted,
      completedAt: completedAt ?? this.completedAt,
      assignedBy: assignedBy ?? this.assignedBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'action_id': actionId,
    'profile_id': profileId,
    'assignment_role': assignmentRole,
    'is_required': isRequired,
    'work_completed': workCompleted,
    'completed_at': completedAt?.toIso8601String(),
    'assigned_by': assignedBy,
    'created_at': createdAt?.toIso8601String(),
  };

  factory ActionAssigneeRecord.fromJson(Map<String, dynamic> json) {
    String name = '';
    String email = '';
    if (json['profile'] is Map) {
      name = (json['profile']['full_name'] as String?) ?? '';
      email = (json['profile']['email'] as String?) ?? '';
    } else {
      name =
          (json['profile_name'] as String?) ?? (json['name'] as String?) ?? '';
      email =
          (json['profile_email'] as String?) ??
          (json['email'] as String?) ??
          '';
    }

    return ActionAssigneeRecord(
      id: (json['id'] as String?) ?? '',
      actionId: (json['action_id'] as String?) ?? '',
      profileId:
          (json['profile_id'] as String?) ??
          (json['person_id'] as String?) ??
          '',
      profileName: name,
      profileEmail: email,
      assignmentRole: (json['assignment_role'] as String?) ?? 'assignee',
      isRequired: json['is_required'] != false,
      workCompleted: json['work_completed'] == true,
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'].toString())
          : null,
      assignedBy: (json['assigned_by'] as String?) ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }
}

class ActionContributorRecord {
  const ActionContributorRecord({
    required this.id,
    required this.actionId,
    required this.profileId,
    this.profileName = '',
    this.profileEmail = '',
    this.addedBy = '',
    this.addedByName = '',
    this.notes = '',
    this.createdAt,
  });

  final String id;
  final String actionId;
  final String profileId;
  final String profileName;
  final String profileEmail;
  final String addedBy;
  final String addedByName;
  final String notes;
  final DateTime? createdAt;

  String get userName => profileName;

  ActionContributorRecord copyWith({
    String? id,
    String? actionId,
    String? profileId,
    String? profileName,
    String? profileEmail,
    String? addedBy,
    String? addedByName,
    String? notes,
    DateTime? createdAt,
  }) {
    return ActionContributorRecord(
      id: id ?? this.id,
      actionId: actionId ?? this.actionId,
      profileId: profileId ?? this.profileId,
      profileName: profileName ?? this.profileName,
      profileEmail: profileEmail ?? this.profileEmail,
      addedBy: addedBy ?? this.addedBy,
      addedByName: addedByName ?? this.addedByName,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'action_id': actionId,
    'profile_id': profileId,
    'added_by': addedBy,
    'added_by_name': addedByName,
    'notes': notes,
    'created_at': createdAt?.toIso8601String(),
  };

  factory ActionContributorRecord.fromJson(Map<String, dynamic> json) {
    String name = '';
    String email = '';
    if (json['profile'] is Map) {
      name = (json['profile']['full_name'] as String?) ?? '';
      email = (json['profile']['email'] as String?) ?? '';
    } else {
      name =
          (json['profile_name'] as String?) ?? (json['name'] as String?) ?? '';
      email =
          (json['profile_email'] as String?) ??
          (json['email'] as String?) ??
          '';
    }

    return ActionContributorRecord(
      id: (json['id'] as String?) ?? '',
      actionId: (json['action_id'] as String?) ?? '',
      profileId:
          (json['profile_id'] as String?) ??
          (json['person_id'] as String?) ??
          '',
      profileName: name,
      profileEmail: email,
      addedBy: (json['added_by'] as String?) ?? '',
      addedByName: (json['added_by_name'] as String?) ??
          (json['added_by_profile'] is Map
              ? (json['added_by_profile']['full_name'] as String?) ?? ''
              : ''),
      notes: (json['notes'] as String?) ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }
}

class ActionProgressUpdate {
  const ActionProgressUpdate({
    required this.id,
    required this.actionId,
    required this.updatedById,
    this.updatedByName = '',
    required this.updateDate,
    required this.progress,
    required this.status,
    required this.comments,
    this.attachments = const [],
    this.roleInAction = 'assignee',
    this.contributionValue = 0,
    this.createdAt,
    this.subject = '',
    this.messageType = 'Progress Update',
    this.workCompleted = '',
    this.pendingWork = '',
    this.requirement = '',
    this.suggestion = '',
    this.remarks = '',
  });

  final String id;
  final String actionId;
  final String updatedById;
  final String updatedByName;
  final String updateDate; // 'DD MMM YYYY' or 'YYYY-MM-DD'
  final int progress;
  final String status;
  final String comments;
  final List<String> attachments;
  final String roleInAction; // 'owner', 'assignee', 'contributor', 'manager'
  final int contributionValue;
  final DateTime? createdAt;
  final String subject;
  final String messageType;
  final String workCompleted;
  final String pendingWork;
  final String requirement;
  final String suggestion;
  final String remarks;

  /// Effective description of the work completed, falling back to comments.
  String get effectiveWorkCompleted {
    if (workCompleted.trim().isNotEmpty) return workCompleted.trim();
    if (comments.trim().startsWith('{') && comments.trim().endsWith('}')) {
      try {
        final d = jsonDecode(comments.trim());
        if (d is Map && d['work_completed'] != null && d['work_completed'].toString().trim().isNotEmpty) {
          return d['work_completed'].toString().trim();
        }
      } catch (_) {}
    }
    if (comments.trim().isNotEmpty) return comments.trim();
    return '';
  }

  /// Effective subject of the update.
  String get effectiveSubject {
    if (subject.trim().isNotEmpty) return subject.trim();
    if (comments.trim().startsWith('{') && comments.trim().endsWith('}')) {
      try {
        final d = jsonDecode(comments.trim());
        if (d is Map && d['subject'] != null && d['subject'].toString().trim().isNotEmpty) {
          return d['subject'].toString().trim();
        }
      } catch (_) {}
    }
    if (messageType.isNotEmpty && messageType != 'Progress Update') {
      return messageType;
    }
    return 'Progress Update';
  }

  /// Returns true if this update contains work completed or comments.
  bool get hasWorkCompletedRemarks {
    return effectiveWorkCompleted.isNotEmpty || effectiveSubject.isNotEmpty;
  }

  /// Returns true if this update contains pending work, requirements, suggestions, or general remarks.
  bool get hasPendingWorkOrRoadblocks {
    return pendingWork.trim().isNotEmpty ||
        requirement.trim().isNotEmpty ||
        suggestion.trim().isNotEmpty ||
        remarks.trim().isNotEmpty;
  }

  /// Normalized role label ('Staff' or 'Manager').
  String get submitterRoleLabel {
    final lowerRole = roleInAction.toLowerCase();
    final lowerName = updatedByName.toLowerCase();
    if (lowerRole.contains('manager') || lowerName.contains('manager')) {
      return 'Manager';
    }
    return 'Staff';
  }

  ActionProgressUpdate copyWith({
    String? id,
    String? actionId,
    String? updatedById,
    String? updatedByName,
    String? updateDate,
    int? progress,
    String? status,
    String? comments,
    List<String>? attachments,
    String? roleInAction,
    int? contributionValue,
    DateTime? createdAt,
    String? subject,
    String? messageType,
    String? workCompleted,
    String? pendingWork,
    String? requirement,
    String? suggestion,
    String? remarks,
  }) {
    return ActionProgressUpdate(
      id: id ?? this.id,
      actionId: actionId ?? this.actionId,
      updatedById: updatedById ?? this.updatedById,
      updatedByName: updatedByName ?? this.updatedByName,
      updateDate: updateDate ?? this.updateDate,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      comments: comments ?? this.comments,
      attachments: attachments ?? this.attachments,
      roleInAction: roleInAction ?? this.roleInAction,
      contributionValue: contributionValue ?? this.contributionValue,
      createdAt: createdAt ?? this.createdAt,
      subject: subject ?? this.subject,
      messageType: messageType ?? this.messageType,
      workCompleted: workCompleted ?? this.workCompleted,
      pendingWork: pendingWork ?? this.pendingWork,
      requirement: requirement ?? this.requirement,
      suggestion: suggestion ?? this.suggestion,
      remarks: remarks ?? this.remarks,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'action_id': actionId,
    'updated_by': updatedById,
    'updated_by_name': updatedByName,
    'update_date': updateDate,
    'progress': progress,
    'status': status,
    'comments': comments,
    'attachments': attachments,
    'role_in_action': roleInAction,
    'contribution_value': contributionValue,
    'created_at': createdAt?.toIso8601String(),
    'subject': subject,
    'message_type': messageType,
    'work_completed': workCompleted,
    'pending_work': pendingWork,
    'requirement': requirement,
    'suggestion': suggestion,
    'remarks': remarks,
  };

  factory ActionProgressUpdate.fromJson(Map<String, dynamic> json) {
    String updaterName = '';
    if (json['updater'] is Map) {
      updaterName = (json['updater']['full_name'] as String?) ?? '';
    } else if (json['updated_by_name'] != null) {
      updaterName = json['updated_by_name'].toString();
    } else if (json['profiles'] is Map) {
      updaterName = (json['profiles']['full_name'] as String?) ?? '';
    }

    final rawAtts = json['attachments'];
    final List<String> atts = [];
    if (rawAtts is List) {
      for (final a in rawAtts) {
        if (a != null) atts.add(a.toString());
      }
    }

    final rawComments = (json['comments'] as String?) ??
        (json['work_update'] as String? ?? '');

    String subject = (json['subject'] as String?) ??
        (json['update_subject'] as String?) ??
        (json['worker_message_subject'] as String?) ??
        '';
    String messageType = (json['message_type'] as String?) ??
        (json['messageType'] as String?) ??
        (json['worker_message_type'] as String?) ??
        'Progress Update';
    String workCompleted = (json['work_completed'] as String?) ??
        (json['workCompleted'] as String?) ??
        (json['work_description'] as String?) ??
        '';
    String pendingWork = (json['pending_work'] as String?) ??
        (json['work_pending'] as String?) ??
        (json['pendingWork'] as String?) ??
        (json['workPending'] as String?) ??
        (json['pending_reason'] as String?) ??
        (json['roadblocks'] as String?) ??
        '';
    String requirement = (json['requirement'] as String?) ??
        (json['requirements'] as String?) ??
        (json['equipment_required'] as String?) ??
        (json['equipmentRequired'] as String?) ??
        (json['material_requirement'] as String?) ??
        '';
    String suggestion = (json['suggestion'] as String?) ??
        (json['suggestions'] as String?) ??
        (json['suggestion_for_manager'] as String?) ??
        (json['suggestionForManager'] as String?) ??
        '';
    String remarks = (json['remarks'] as String?) ??
        (json['general_remarks'] as String?) ??
        (json['safety_remarks'] as String?) ??
        (json['safetyRemarks'] as String?) ??
        '';

    final isJsonComments = rawComments.trim().startsWith('{') && rawComments.trim().endsWith('}');
    if (isJsonComments) {
      try {
        final decoded = jsonDecode(rawComments.trim());
        if (decoded is Map) {
          final subjCandidate = decoded['subject'] ?? decoded['update_subject'] ?? decoded['worker_message_subject'];
          if (subject.isEmpty && subjCandidate != null) {
            subject = subjCandidate.toString();
          }
          final typeCandidate = decoded['message_type'] ?? decoded['messageType'] ?? decoded['worker_message_type'];
          if (messageType == 'Progress Update' && typeCandidate != null) {
            messageType = typeCandidate.toString();
          }
          final completedCandidate = decoded['work_completed'] ??
              decoded['workCompleted'] ??
              decoded['work_update'] ??
              decoded['completed_work'] ??
              decoded['work_description'];
          if (workCompleted.isEmpty && completedCandidate != null) {
            workCompleted = completedCandidate.toString();
          }
          final pendingCandidate = decoded['pending_work'] ??
              decoded['work_pending'] ??
              decoded['pending_reason'] ??
              decoded['pendingWork'] ??
              decoded['workPending'] ??
              decoded['roadblocks'] ??
              decoded['work_still_pending'];
          if (pendingWork.isEmpty && pendingCandidate != null) {
            pendingWork = pendingCandidate.toString();
          }
          final reqCandidate = decoded['requirement'] ??
              decoded['requirements'] ??
              decoded['equipment_required'] ??
              decoded['equipmentRequired'] ??
              decoded['material_requirement'];
          if (requirement.isEmpty && reqCandidate != null) {
            requirement = reqCandidate.toString();
          }
          final suggCandidate = decoded['suggestion'] ??
              decoded['suggestions'] ??
              decoded['suggestion_for_manager'] ??
              decoded['suggestionForManager'] ??
              decoded['suggestions_for_manager'];
          if (suggestion.isEmpty && suggCandidate != null) {
            suggestion = suggCandidate.toString();
          }
          final remCandidate = decoded['remarks'] ??
              decoded['general_remarks'] ??
              decoded['safety_remarks'] ??
              decoded['safetyRemarks'];
          if (remarks.isEmpty && remCandidate != null) {
            remarks = remCandidate.toString();
          }
        }
      } catch (_) {}
    }

    if (workCompleted.isEmpty && !isJsonComments) {
      workCompleted = rawComments;
    }

    return ActionProgressUpdate(
      id: (json['id'] as String?) ?? '',
      actionId: (json['action_id'] as String?) ?? '',
      updatedById: (json['updated_by'] as String?) ?? '',
      updatedByName: updaterName,
      updateDate: ActionRecord.formatDateForUi(
        json['update_date'] ?? json['timestamp'],
      ),
      progress: (json['progress'] as num?)?.toInt() ?? 0,
      status: (json['status'] as String?) ?? 'In Progress',
      comments: rawComments,
      attachments: atts,
      roleInAction:
          (json['role_in_action'] as String?) ??
          (json['role'] as String?) ??
          'assignee',
      contributionValue:
          (json['contribution_value'] as num?)?.toInt() ??
          (json['contribution'] as num?)?.toInt() ??
          0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : (json['timestamp'] != null
                ? DateTime.tryParse(json['timestamp'].toString())
                : null),
      subject: subject,
      messageType: messageType,
      workCompleted: workCompleted,
      pendingWork: pendingWork,
      requirement: requirement,
      suggestion: suggestion,
      remarks: remarks,
    );
  }
}

enum EvidenceClassification {
  originalActionDocument,
  staffUpdateEvidence,
  managerUpdateEvidence,
  actionEvidence,
}

class ActionEvidenceItem {
  const ActionEvidenceItem({
    required this.fileName,
    required this.fileType,
    required this.classification,
    this.uploadedBy = '',
    this.uploaderRole = '',
    this.uploadedAt,
    this.updateId,
    this.storagePath = '',
    this.actionId = '',
    this.progress,
    this.comments = '',
  });

  final String fileName;
  final String fileType;
  final EvidenceClassification classification;
  final String uploadedBy;
  final String uploaderRole;
  final DateTime? uploadedAt;
  final String? updateId;
  final String storagePath;
  final String actionId;
  final int? progress;
  final String comments;

  bool get isOriginal =>
      classification == EvidenceClassification.originalActionDocument;
  bool get isStaffUpdate =>
      classification == EvidenceClassification.staffUpdateEvidence;
  bool get isManagerUpdate =>
      classification == EvidenceClassification.managerUpdateEvidence;
  bool get isActionEvidence =>
      classification == EvidenceClassification.actionEvidence;

  String get classificationLabel {
    switch (classification) {
      case EvidenceClassification.originalActionDocument:
        return 'Original Action Documents';
      case EvidenceClassification.staffUpdateEvidence:
        return 'Staff-Submitted Update Evidence';
      case EvidenceClassification.managerUpdateEvidence:
        return 'Manager-Submitted Update Evidence';
      case EvidenceClassification.actionEvidence:
        return 'Action Evidence';
    }
  }

  static String resolveFileType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'PDF';
    if (lower.endsWith('.png')) return 'PNG Image';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'JPEG Image';
    if (lower.endsWith('.webp')) return 'WebP Image';
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) return 'Word Document';
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) return 'Excel Spreadsheet';
    if (lower.endsWith('.csv')) return 'CSV File';
    return 'Document';
  }
}

class ActionRecord {
  ActionRecord({
    required this.id,
    this.actionNumber = '',
    this.organizationId = '',
    this.departmentId = '',
    this.siteId = '',
    this.teamId,
    this.team = '',
    this.createdById = '',
    this.createdByName = '',
    this.createdByPerson,
    this.assignedToId,
    this.verifiedById,
    this.closedAt,
    this.closedById,
    this.closedByName,
    this.closureComment = '',
    this.sectionId,
    this.section = '',
    this.divisionId,
    required this.subject,
    required this.actionRequired,
    required this.division,
    required this.assignedTo,
    String? originalAssignee,
    String? assignedBy,
    String? originalAssignedBy,
    this.assignedByPerson,
    this.originalAssignedByPerson,
    this.department = '',
    this.site = '',
    this.category = '',
    this.source = '',
    this.priority = 'Medium',
    this.status = 'Open',
    this.percentComplete = 0,
    this.supportingPerson = '',
    this.startDate = '',
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
    this.subTasks = const [],
    this.progressUpdates = const [],
    this.followUps = const [],
    this.assignees = const [],
    this.contributors = const [],
    this.recipientType = 'internal',
    this.externalRecipientId,
    this.externalRecipientEmail,
    this.externalRecipientName,
    this.emailReminderEnabled = false,
    this.externalRecipient,
    this.scopeType = 'specific',
    this.createdAt,
  }) : originalAssignee = originalAssignee ?? assignedTo,
       assignedBy = (assignedBy != null && assignedBy.isNotEmpty)
           ? assignedBy
           : (createdByName.isNotEmpty ? createdByName : 'Unspecified'),
       originalAssignedBy =
           (originalAssignedBy != null && originalAssignedBy.isNotEmpty)
           ? originalAssignedBy
           : ((assignedBy != null && assignedBy.isNotEmpty)
                 ? assignedBy
                 : (createdByName.isNotEmpty ? createdByName : 'Unspecified'));

  final String id;
  final String actionNumber;
  final String organizationId;
  final String departmentId;
  final String siteId;
  final String? teamId;
  final String team;
  final String createdById;
  final String createdByName;
  final ActionPersonReference? createdByPerson;
  final String? assignedToId;
  final String? verifiedById;
  final DateTime? closedAt;
  final String? closedById;
  final String? closedByName;
  final String closureComment;
  final String? sectionId;
  final String section;
  final String? divisionId;

  final String subject;
  final String actionRequired;
  final String division;
  final String department;
  final String site;
  final String category;
  final String source;
  final String assignedTo;
  final String originalAssignee;
  final String assignedBy;
  final String originalAssignedBy;
  final ActionPersonReference? assignedByPerson;
  final ActionPersonReference? originalAssignedByPerson;
  final String priority;
  final String status;
  final int percentComplete;
  final String supportingPerson;
  final String startDate;
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
  final List<ActionSubTask> subTasks;
  final List<ActionProgressUpdate> progressUpdates;
  final List<ActionFollowUpRecord> followUps;
  final List<ActionAssigneeRecord> assignees;
  final List<ActionContributorRecord> contributors;

  final String recipientType; // 'internal', 'external'
  final String? externalRecipientId;
  final String? externalRecipientEmail;
  final String? externalRecipientName;
  final bool emailReminderEnabled;
  final ExternalRecipient? externalRecipient;
  final String scopeType; // 'specific', 'department', 'site', 'organization'
  final DateTime? createdAt;

  bool get isOrganizationWide =>
      scopeType == 'organization' ||
      (departmentId.isEmpty &&
          siteId.isEmpty &&
          (department == 'All Departments' || department.isEmpty) &&
          (site == 'All Sites / Locations' || site == 'All Sites' || site.isEmpty));

  bool get isDepartmentWide =>
      scopeType == 'department' ||
      (departmentId.isNotEmpty && siteId.isEmpty);

  bool get isSiteWide =>
      scopeType == 'site' ||
      (departmentId.isEmpty && siteId.isNotEmpty);

  bool get isSpecificScope =>
      !isOrganizationWide && !isDepartmentWide && !isSiteWide;

  bool get isExternalRecipient => recipientType.toLowerCase() == 'external';
  bool get isInternalRecipient => !isExternalRecipient;

  /// True if the action is assigned to at least one internal staff member
  bool get hasInternalAssignee {
    if (primaryAssignee != null) {
      if (primaryAssignee!.type == PersonType.internalUser) return true;
    } else {
      if (recipientType.toLowerCase() == 'internal' &&
          (externalRecipientId == null || externalRecipientId!.isEmpty)) {
        return true;
      }
    }
    if (assignees.any((a) => a.profileId.isNotEmpty)) return true;
    for (final p in additionalPeople) {
      if (p.type == PersonType.internalUser) return true;
    }
    return false;
  }

  /// True if the action is assigned to at least one external user / contractor
  bool get hasExternalAssignee {
    if (primaryAssignee != null) {
      if (primaryAssignee!.type == PersonType.externalWorker) return true;
    }
    if (recipientType.toLowerCase() == 'external' ||
        (externalRecipientId != null && externalRecipientId!.isNotEmpty) ||
        externalRecipient != null) {
      return true;
    }
    for (final p in additionalPeople) {
      if (p.type == PersonType.externalWorker) return true;
    }
    return false;
  }

  /// Display identifier: prefer generated actionNumber (e.g. ACT-1001), fallback to id
  String get displayId => actionNumber.isNotEmpty ? actionNumber : id;

  String get percent => '$percentComplete%';
  String get followUp {
    if (nextFollowUpDate.isNotEmpty && nextFollowUpDate != 'Not set') {
      return nextFollowUpDate;
    }
    if (followUps.isNotEmpty) {
      final scheduled = followUps.where((f) => f.status == 'Scheduled').toList();
      if (scheduled.isNotEmpty) return scheduled.first.followUpDate;
      return followUps.last.followUpDate;
    }
    if (lastFollowUpDate.isNotEmpty && lastFollowUpDate != 'Not set') {
      return lastFollowUpDate;
    }
    return 'Not set';
  }

  /// True if the action has been formally verified and closed
  bool get isClosed => status.trim().toLowerCase() == 'closed';

  /// True if the action has been soft-deleted and removed from active views
  bool get isDeleted => status.trim().toLowerCase() == 'deleted';

  /// True if the action is overdue based on status or target date
  bool get isOverdue {
    if (isClosed) return false;
    if (status.trim().toLowerCase() == 'overdue') return true;
    final target = targetDateTime;
    if (target == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDay = DateTime(target.year, target.month, target.day);
    return targetDay.isBefore(today);
  }

  /// True if the action is ready for manager review (100% complete, or status is Pending/Ready for Review)
  bool get isReadyForReview =>
      !isClosed &&
      (status == 'Pending Review' ||
          status == 'Ready for Review' ||
          status == 'Under Review' ||
          percentComplete >= 100);

  /// True if there are multiple assignees assigned
  bool get hasMultipleAssignees => assignees.length > 1;

  /// Required assignees who must finish before action can close
  List<ActionAssigneeRecord> get requiredAssignees =>
      assignees.where((a) => a.isRequired).toList();

  /// True if all required assignees have completed their work
  bool get allRequiredAssigneesCompleted =>
      requiredAssignees.isEmpty ||
      requiredAssignees.every((a) => a.workCompleted);

  /// True if this action has been forwarded to contributors or delegated as sub-tasks
  bool get isForwarded => contributors.isNotEmpty || subTasks.isNotEmpty;

  /// True if the specified user is an owner, creator, or primary assignee of this action
  bool isOwner(String? userId, [String? userName, String? userEmail]) {
    final uid = userId?.trim() ?? '';
    final uname = userName?.trim().toLowerCase() ?? '';
    final uemail = userEmail?.trim().toLowerCase() ?? '';
    if (uid.isNotEmpty &&
        (assignedToId?.trim() == uid ||
            primaryAssignee?.personId.trim() == uid ||
            createdById.trim() == uid)) {
      return true;
    }
    if (uname.isNotEmpty &&
        (assignedTo.trim().toLowerCase() == uname ||
            primaryAssignee?.name.trim().toLowerCase() == uname)) {
      return true;
    }
    if (uemail.isNotEmpty &&
        (primaryAssignee?.email.trim().toLowerCase() == uemail ||
            externalRecipientEmail?.trim().toLowerCase() == uemail)) {
      return true;
    }
    return assignees.any((a) =>
        a.isOwner &&
        ((uid.isNotEmpty && a.profileId == uid) ||
            (uname.isNotEmpty && a.profileName.toLowerCase() == uname) ||
            (uemail.isNotEmpty && a.profileEmail.toLowerCase() == uemail)));
  }

  /// True if the specified user is an authorized primary owner (explicit 'owner' role in assignees)
  bool isAuthorizedPrimaryOwner(String? userId, [String? userName, String? userEmail]) {
    final uid = userId?.trim() ?? '';
    final uname = userName?.trim().toLowerCase() ?? '';
    final uemail = userEmail?.trim().toLowerCase() ?? '';
    return assignees.any((a) =>
        a.isOwner &&
        ((uid.isNotEmpty && a.profileId.trim().toLowerCase() == uid.toLowerCase()) ||
            (uname.isNotEmpty && a.profileName.trim().toLowerCase() == uname) ||
            (uemail.isNotEmpty && a.profileEmail.trim().toLowerCase() == uemail)));
  }

  /// True if the specified user is the action creator
  bool isCreator(String? userId, [String? userName, String? userEmail]) {
    final uid = userId?.trim() ?? '';
    final uname = userName?.trim().toLowerCase() ?? '';
    if (uid.isNotEmpty && createdById.trim().toLowerCase() == uid.toLowerCase()) {
      return true;
    }
    if (assignedByPerson?.personId.isNotEmpty == true &&
        uid.isNotEmpty &&
        assignedByPerson!.personId.trim().toLowerCase() == uid.toLowerCase()) {
      return true;
    }
    if (uname.isNotEmpty &&
        (assignedBy.trim().toLowerCase() == uname ||
            originalAssignedBy.trim().toLowerCase() == uname ||
            (assignedByPerson?.name.isNotEmpty == true &&
                assignedByPerson!.name.trim().toLowerCase() == uname))) {
      return true;
    }
    return false;
  }

  /// True if this action has been forwarded to the specified user as contributor or sub-task assignee
  bool isForwardedTo(String? userId, [String? userName, String? userEmail]) {
    final uid = userId?.trim() ?? '';
    final uname = userName?.trim().toLowerCase() ?? '';
    final uemail = userEmail?.trim().toLowerCase() ?? '';

    final inContributors = contributors.any((c) {
      if (uid.isNotEmpty && c.profileId.trim() == uid) return true;
      if (uname.isNotEmpty && c.profileName.trim().toLowerCase() == uname) return true;
      if (uemail.isNotEmpty && c.profileEmail.trim().toLowerCase() == uemail) return true;
      return false;
    });
    if (inContributors) return true;

    final inSubTasks = subTasks.any((st) {
      if (uid.isNotEmpty && st.assignedStaffId.trim() == uid) return true;
      if (uname.isNotEmpty && st.assignedStaff.trim().toLowerCase() == uname) return true;
      if (uemail.isNotEmpty && st.assignedStaffEmail.trim().toLowerCase() == uemail) return true;
      return false;
    });
    return inSubTasks;
  }

  /// True if this action was forwarded by the specified user (as contributor forwarder, subtask delegator, or creator/assigner)
  bool isForwardedBy(String? userId, [String? userName, String? userEmail]) {
    final uid = userId?.trim() ?? '';
    final uname = userName?.trim().toLowerCase() ?? '';
    final uemail = userEmail?.trim().toLowerCase() ?? '';

    // 1. Explicitly recorded as addedBy in contributors
    final inContributors = contributors.any((c) {
      if (uid.isNotEmpty && c.addedBy.trim() == uid) return true;
      if (uname.isNotEmpty && c.addedByName.trim().toLowerCase() == uname) return true;
      return false;
    });
    if (inContributors) return true;

    // 2. Primary assignee who forwarded to other contributors or delegated subtasks
    final isPrimaryOwner = (uid.isNotEmpty && (assignedToId?.trim() == uid || primaryAssignee?.personId.trim() == uid)) ||
        (uname.isNotEmpty && assignedTo.trim().toLowerCase() == uname) ||
        (uemail.isNotEmpty && primaryAssignee?.email.trim().toLowerCase() == uemail);

    if (isPrimaryOwner && isForwarded) {
      // Check if there are other contributors or subtasks assigned to someone else
      final hasOtherContributors = contributors.any((c) =>
          (uid.isNotEmpty && c.profileId.trim() != uid) ||
          (uname.isNotEmpty && c.profileName.trim().toLowerCase() != uname));
      final hasOtherSubtasks = subTasks.any((st) =>
          (uid.isNotEmpty && st.assignedStaffId.trim() != uid) ||
          (uname.isNotEmpty && st.assignedStaff.trim().toLowerCase() != uname));
      if (hasOtherContributors || hasOtherSubtasks) return true;
    }

    // 3. Manager/Creator who created or assigned the action and forwarded/delegated tasks
    final isCreatorOrManager = (uname.isNotEmpty && assignedBy.trim().toLowerCase() == uname);
    if (isCreatorOrManager && isForwarded) {
      return true;
    }

    // 4. Audit trail check in action history
    if (uname.isNotEmpty && isForwarded) {
      final matchesHistory = history.any((h) {
        final hl = h.toLowerCase();
        return hl.contains(uname) &&
            (hl.contains('forwarded') ||
                hl.contains('added by $uname') ||
                hl.contains('created and assigned') ||
                hl.contains('delegated'));
      });
      if (matchesHistory) return true;
    }

    return false;
  }

  /// Upcoming scheduled follow-ups (today or future)
  List<ActionFollowUpRecord> get upcomingFollowUps {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return followUps.where((f) {
      if (f.isCompleted) return false;
      final parsed = DateTime.tryParse(formatDateForDb(f.followUpDate));
      return parsed == null || !parsed.isBefore(today);
    }).toList();
  }

  /// Past or completed follow-ups
  List<ActionFollowUpRecord> get pastFollowUps {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return followUps.where((f) {
      if (f.isCompleted) return true;
      final parsed = DateTime.tryParse(formatDateForDb(f.followUpDate));
      return parsed != null && parsed.isBefore(today);
    }).toList();
  }

  /// Calculates individual contribution percentage for a specific user UUID
  int myContribution(String? userId) {
    if (userId == null || userId.isEmpty) return 0;
    int total = 0;
    for (final u in progressUpdates) {
      if (u.updatedById == userId) {
        total += u.contributionValue;
      }
    }
    // If no explicit contributionValue was recorded (legacy updates)
    if (total == 0) {
      final userUpdates = progressUpdates
          .where((u) => u.updatedById == userId)
          .toList();
      if (userUpdates.isNotEmpty) {
        return userUpdates
            .map((u) => u.progress)
            .reduce((a, b) => a > b ? a : b);
      }
    }
    return total.clamp(0, 100);
  }

  /// Returns the role of a given user profile ID in this action: 'Owner', 'Assignee', or 'Contributor'.
  String getUserRoleInAction(String? userId) {
    if (userId == null || userId.isEmpty) return 'Assignee';
    if (userId == assignedToId) return 'Owner';
    for (final a in assignees) {
      if (a.profileId == userId) {
        return a.isOwner ? 'Owner' : 'Assignee';
      }
    }
    if (contributors.any((c) => c.profileId == userId)) {
      return 'Contributor';
    }
    return 'Assignee';
  }

  /// Returns a map of user profile ID / name to their total contribution %
  Map<String, int> get individualContributions {
    final map = <String, int>{};
    for (final u in progressUpdates) {
      final key = u.updatedByName.isNotEmpty ? u.updatedByName : u.updatedById;
      map[key] = (map[key] ?? 0) + u.contributionValue;
    }
    if (map.isEmpty && percentComplete > 0) {
      map[assignedTo.isNotEmpty ? assignedTo : 'Owner'] = percentComplete;
    }
    return map;
  }

  /// Returns the latest progress update recorded for this action, if any.
  ActionProgressUpdate? get latestProgressUpdate {
    if (progressUpdates.isEmpty) return null;
    final sorted = List<ActionProgressUpdate>.from(progressUpdates)
      ..sort((a, b) {
        final bDate =
            b.createdAt ??
            DateTime.tryParse(formatDateForDb(b.updateDate)) ??
            DateTime(1970);
        final aDate =
            a.createdAt ??
            DateTime.tryParse(formatDateForDb(a.updateDate)) ??
            DateTime(1970);
        return bDate.compareTo(aDate);
      });
    return sorted.first;
  }

  /// Returns the latest progress update submitted by a specific user ID or role.
  ActionProgressUpdate? latestProgressUpdateFor(String? userId, {bool isManager = false}) {
    final all = allProgressUpdates;
    if (all.isEmpty) return null;
    if (userId != null && userId.isNotEmpty) {
      final userMatch = all.firstWhereOrNull((u) => u.updatedById == userId);
      if (userMatch != null) return userMatch;
    }
    final roleMatch = all.firstWhereOrNull((u) {
      final isMgr = u.roleInAction.toLowerCase().contains('manager') ||
          u.updatedByName.toLowerCase().contains('manager');
      return isManager ? isMgr : !isMgr;
    });
    return roleMatch ?? all.first;
  }

  /// Replaces an existing update or prepends a new one without creating duplicates.
  ActionRecord updateProgressUpdate(ActionProgressUpdate updated) {
    final existingIdx = progressUpdates.indexWhere((u) => u.id == updated.id);
    final List<ActionProgressUpdate> next;
    if (existingIdx >= 0) {
      next = List<ActionProgressUpdate>.from(progressUpdates);
      next[existingIdx] = updated;
    } else {
      next = [updated, ...progressUpdates];
    }
    return copyWith(
      progressUpdates: next,
      percentComplete: updated.progress,
      status: updated.status,
      workerMessageSubject: updated.effectiveSubject,
      workerMessage: updated.effectiveWorkCompleted,
      pendingReason: updated.pendingWork,
      requirement: updated.requirement,
      suggestion: updated.suggestion,
      remarks: updated.remarks,
      messageType: updated.messageType,
    );
  }

  String get latestUpdateDate => latestProgressUpdate?.updateDate ?? '';
  String get lastUpdatedBy => latestProgressUpdate?.updatedByName ?? '';
  String get latestWorkUpdate => latestProgressUpdate?.comments ?? '';

  /// Returns all historical progress updates, newest first.
  /// If [progressUpdates] is empty, returns synthetic entries for legacy action-level remarks.
  List<ActionProgressUpdate> get allProgressUpdates {
    final list = <ActionProgressUpdate>[];
    for (final u in progressUpdates) {
      list.add(u);
    }
    if (list.isEmpty) {
      if (workerMessage.trim().isNotEmpty ||
          workerMessageSubject.trim().isNotEmpty ||
          pendingReason.trim().isNotEmpty ||
          requirement.trim().isNotEmpty ||
          suggestion.trim().isNotEmpty ||
          remarks.trim().isNotEmpty) {
        list.add(
          ActionProgressUpdate(
            id: 'legacy-staff-$id',
            actionId: id,
            updatedById: assignedToId ?? '',
            updatedByName: assignedTo.isNotEmpty ? assignedTo : 'Staff Member',
            updateDate: lastFollowUpDate.isNotEmpty
                ? lastFollowUpDate
                : (startDate.isNotEmpty ? startDate : dateRaised),
            progress: percentComplete,
            status: status,
            comments: workerMessage.isNotEmpty
                ? workerMessage
                : (workerMessageSubject.isNotEmpty
                    ? workerMessageSubject
                    : 'Action progress update'),
            subject: workerMessageSubject,
            messageType: messageType.isNotEmpty ? messageType : 'Progress Update',
            workCompleted: workerMessage.isNotEmpty
                ? workerMessage
                : (workerMessageSubject.isNotEmpty ? workerMessageSubject : ''),
            pendingWork: pendingReason,
            requirement: requirement,
            suggestion: suggestion,
            remarks: remarks,
            roleInAction: 'assignee',
            createdAt: createdAt,
          ),
        );
      }
      if (managerMessage.trim().isNotEmpty) {
        list.add(
          ActionProgressUpdate(
            id: 'legacy-manager-$id',
            actionId: id,
            updatedById: createdById,
            updatedByName: assignedBy.isNotEmpty ? assignedBy : 'Manager',
            updateDate: lastFollowUpDate.isNotEmpty ? lastFollowUpDate : dateRaised,
            progress: percentComplete,
            status: status,
            comments: managerMessage,
            subject: 'Manager Remarks',
            messageType: 'Manager Remarks',
            workCompleted: managerMessage,
            roleInAction: 'manager',
            createdAt: createdAt,
          ),
        );
      }
    } else {
      // If none of the updates have pending/roadblock fields, but the action record does,
      // inherit them onto the newest update so legacy action remarks are not lost.
      if (!list.any((u) => u.hasPendingWorkOrRoadblocks) &&
          (pendingReason.trim().isNotEmpty ||
              requirement.trim().isNotEmpty ||
              suggestion.trim().isNotEmpty ||
              remarks.trim().isNotEmpty)) {
        final first = list.first;
        list[0] = first.copyWith(
          pendingWork: first.pendingWork.isEmpty ? pendingReason : first.pendingWork,
          requirement: first.requirement.isEmpty ? requirement : first.requirement,
          suggestion: first.suggestion.isEmpty ? suggestion : first.suggestion,
          remarks: first.remarks.isEmpty ? remarks : first.remarks,
        );
      }
    }

    list.sort((a, b) {
      final bDate =
          b.createdAt ??
          DateTime.tryParse(formatDateForDb(b.updateDate)) ??
          DateTime(1970);
      final aDate =
          a.createdAt ??
          DateTime.tryParse(formatDateForDb(a.updateDate)) ??
          DateTime(1970);
      return bDate.compareTo(aDate);
    });

    return list;
  }

  /// Parsed target DateTime, handling both UI 'DD MMM YYYY' and ISO formats
  DateTime? get targetDateTime {
    if (targetDate.isEmpty) return null;
    final parts = targetDate.trim().split(' ');
    if (parts.length >= 3) {
      final dbFormatted = formatDateForDb(targetDate);
      return DateTime.tryParse(dbFormatted);
    }
    return DateTime.tryParse(targetDate);
  }

  /// Exact creation timestamp with fallback to parsed dateRaised
  DateTime? get createdDateTime {
    if (createdAt != null) return createdAt;
    if (dateRaised.isEmpty) return null;
    final parts = dateRaised.trim().split(' ');
    if (parts.length >= 3) {
      final dbFormatted = formatDateForDb(dateRaised);
      return DateTime.tryParse(dbFormatted);
    }
    return DateTime.tryParse(dateRaised);
  }

  /// Classified evidence documents associated with this action:
  /// 1. Staff-Submitted Update Evidence (from progress updates by staff/assignees)
  /// 2. Manager-Submitted Update Evidence (from progress updates by managers/creators)
  /// 3. Original Action Documents (from action creation, not in progress updates)
  List<ActionEvidenceItem> get allClassifiedEvidence {
    final List<ActionEvidenceItem> items = [];
    final Set<String> processedFiles = {};

    // 1. Process progress updates (chronological or recent first)
    for (final pu in progressUpdates) {
      final isMgr = pu.roleInAction.toLowerCase() == 'manager' ||
          (createdById.isNotEmpty && pu.updatedById == createdById) ||
          (assignedByPerson?.personId.isNotEmpty == true &&
              pu.updatedById == assignedByPerson!.personId);
      final classification = isMgr
          ? EvidenceClassification.managerUpdateEvidence
          : EvidenceClassification.staffUpdateEvidence;
      final defaultUploader =
          isMgr ? 'Manager' : (assignedTo.isNotEmpty ? assignedTo : 'Staff');
      final uploaderName =
          pu.updatedByName.isNotEmpty ? pu.updatedByName : defaultUploader;

      for (final att in pu.attachments) {
        final clean = att.trim();
        if (clean.isEmpty || processedFiles.contains(clean)) continue;
        processedFiles.add(clean);

        items.add(
          ActionEvidenceItem(
            fileName: clean,
            fileType: ActionEvidenceItem.resolveFileType(clean),
            classification: classification,
            uploadedBy: uploaderName,
            uploaderRole: pu.roleInAction.isNotEmpty
                ? pu.roleInAction
                : (isMgr ? 'manager' : 'staff'),
            uploadedAt: pu.createdAt,
            updateId: pu.id,
            actionId: id,
            progress: pu.progress,
            comments: pu.comments,
          ),
        );
      }
    }

    // 2. Process action attachments (differentiating top-level uploaded action evidence from original action documents)
    final creatorName = (assignedByPerson?.name.isNotEmpty ?? false)
        ? assignedByPerson!.name
        : (assignedBy.isNotEmpty ? assignedBy : 'Action Creator');

    for (final att in attachments) {
      final clean = att.trim();
      if (clean.isEmpty || processedFiles.contains(clean)) continue;
      processedFiles.add(clean);

      // Check if this attachment was uploaded as top-level action evidence in history
      String? uploadHistoryEntry;
      for (final h in history) {
        if (h.contains('"$clean"') &&
            (h.toLowerCase().contains('evidence') || h.toLowerCase().contains('uploaded'))) {
          uploadHistoryEntry = h;
          break;
        }
      }

      if (uploadHistoryEntry != null) {
        String uploadedBy = 'Action Participant';
        String uploaderRole = 'Staff';
        DateTime? uploadedAt;

        final byIdx = uploadHistoryEntry.toLowerCase().indexOf('uploaded by ');
        if (byIdx != -1) {
          final authorPart = uploadHistoryEntry.substring(byIdx + 'uploaded by '.length).trim();
          final roleMatch = RegExp(r'^(.*?)\s*\((.*?)\)').firstMatch(authorPart);
          if (roleMatch != null) {
            uploadedBy = roleMatch.group(1)?.trim() ?? uploadedBy;
            uploaderRole = roleMatch.group(2)?.trim() ?? uploaderRole;
          } else {
            uploadedBy = authorPart.replaceAll('.', '').trim();
          }
        }

        final colonIdx = uploadHistoryEntry.indexOf(':');
        if (colonIdx != -1) {
          final dateStr = uploadHistoryEntry.substring(0, colonIdx).trim();
          uploadedAt = DateTime.tryParse(dateStr) ?? DateTime.tryParse(formatDateForDb(dateStr));
        }

        items.add(
          ActionEvidenceItem(
            fileName: clean,
            fileType: ActionEvidenceItem.resolveFileType(clean),
            classification: EvidenceClassification.actionEvidence,
            uploadedBy: uploadedBy,
            uploaderRole: uploaderRole,
            uploadedAt: uploadedAt ?? createdAt ?? createdDateTime,
            actionId: id,
          ),
        );
      } else {
        items.add(
          ActionEvidenceItem(
            fileName: clean,
            fileType: ActionEvidenceItem.resolveFileType(clean),
            classification: EvidenceClassification.originalActionDocument,
            uploadedBy: creatorName,
            uploaderRole: 'Creator',
            uploadedAt: createdAt ?? createdDateTime,
            actionId: id,
          ),
        );
      }
    }

    return items;
  }

  List<ActionEvidenceItem> get originalDocuments =>
      allClassifiedEvidence.where((e) => e.isOriginal).toList();

  List<ActionEvidenceItem> get staffUpdateEvidence =>
      allClassifiedEvidence.where((e) => e.isStaffUpdate).toList();

  List<ActionEvidenceItem> get managerUpdateEvidence =>
      allClassifiedEvidence.where((e) => e.isManagerUpdate).toList();

  List<ActionEvidenceItem> get actionEvidence =>
      allClassifiedEvidence.where((e) => e.isActionEvidence).toList();

  // --------------------------------------------------------------------------
  // Date Conversion Helpers
  // --------------------------------------------------------------------------
  static const List<String> _months = [
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

  static String formatDateForUi(dynamic dateVal) {
    if (dateVal == null) return '';
    if (dateVal is DateTime) {
      final d = dateVal.day.toString().padLeft(2, '0');
      final m = _months[dateVal.month - 1];
      return '$d $m ${dateVal.year}';
    }
    final str = dateVal.toString().trim();
    if (str.isEmpty) return '';
    // If already in UI format 'DD MMM YYYY'
    final parts = str.split(' ');
    if (parts.length == 3 && _months.contains(parts[1])) {
      return str;
    }
    // If in ISO format 'YYYY-MM-DD'
    try {
      final dt = DateTime.parse(str);
      final d = dt.day.toString().padLeft(2, '0');
      final m = _months[dt.month - 1];
      return '$d $m ${dt.year}';
    } catch (_) {
      return str;
    }
  }

  static String formatDateForDb(String dateStr) {
    final str = dateStr.trim();
    if (str.isEmpty) return DateTime.now().toIso8601String().substring(0, 10);
    // If already YYYY-MM-DD
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(str)) {
      return str.substring(0, 10);
    }
    // If 'DD MMM YYYY'
    final parts = str.split(' ');
    if (parts.length >= 3) {
      final day = int.tryParse(parts[0]) ?? 1;
      final mIdx = _months.indexWhere(
        (m) => m.toLowerCase() == parts[1].toLowerCase(),
      );
      final month = mIdx != -1 ? mIdx + 1 : 1;
      final year = int.tryParse(parts[2]) ?? DateTime.now().year;
      return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
    }
    try {
      final dt = DateTime.parse(str);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return DateTime.now().toIso8601String().substring(0, 10);
    }
  }

  /// Converts an optional date string into YYYY-MM-DD format for database storage,
  /// or returns null if the string is empty or unparseable.
  static String? formatOptionalDateForDb(String? dateStr) {
    if (dateStr == null) return null;
    final str = dateStr.trim();
    if (str.isEmpty ||
        str.toLowerCase() == 'not set' ||
        str.toLowerCase() == 'not scheduled') {
      return null;
    }
    // If already YYYY-MM-DD
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(str)) {
      return str.substring(0, 10);
    }
    // If 'DD MMM YYYY'
    final parts = str.split(' ');
    if (parts.length >= 3) {
      final day = int.tryParse(parts[0]) ?? 1;
      final mIdx = _months.indexWhere(
        (m) => m.toLowerCase() == parts[1].toLowerCase(),
      );
      final month = mIdx != -1 ? mIdx + 1 : 1;
      final year = int.tryParse(parts[2]) ?? DateTime.now().year;
      return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
    }
    try {
      final dt = DateTime.parse(str);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return null;
    }
  }

  static DateTime parseScheduledDateTime(String dateStr, String timeStr) {
    final dbDate = formatDateForDb(dateStr);
    final dateParts = dbDate.split('-');
    final year = int.tryParse(dateParts[0]) ?? DateTime.now().year;
    final month = int.tryParse(dateParts[1]) ?? 1;
    final day = int.tryParse(dateParts[2]) ?? 1;

    int hour = 9;
    int minute = 0;
    final trimmedTime = timeStr.trim().toUpperCase();
    final timeMatch =
        RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$').firstMatch(trimmedTime);
    if (timeMatch != null) {
      int h = int.tryParse(timeMatch.group(1) ?? '9') ?? 9;
      final m = int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
      final period = timeMatch.group(3);
      if (period == 'PM' && h < 12) h += 12;
      if (period == 'AM' && h == 12) h = 0;
      hour = h;
      minute = m;
    }

    return DateTime(year, month, day, hour, minute);
  }

  static String formatTimeForUi(dynamic timeVal) {
    if (timeVal is DateTime) {
      final hour = timeVal.hour;
      final minute = timeVal.minute;
      final period = hour >= 12 ? 'PM' : 'AM';
      final h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      return '${h.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
    }
    final str = timeVal?.toString().trim() ?? '';
    if (str.isEmpty) return '09:00 AM';
    if (RegExp(r'^\d{1,2}:\d{2}\s*(AM|PM)$', caseSensitive: false)
        .hasMatch(str)) {
      return str;
    }
    final parsed = DateTime.tryParse(str);
    if (parsed != null) {
      return formatTimeForUi(parsed);
    }
    return str;
  }

  static List<ActionEmailReminder> parseRemindersFromJobs(
    List<ActionEmailReminderJob> jobs,
  ) {
    if (jobs.isEmpty) return const [];

    final Map<String, List<ActionEmailReminderJob>> groups = {};
    for (final job in jobs) {
      final key = (job.reminderGroupId != null &&
              job.reminderGroupId!.isNotEmpty)
          ? job.reminderGroupId!
          : (job.scheduledAt != null
              ? '${formatDateForUi(job.scheduledAt)}_${formatTimeForUi(job.scheduledAt)}'
              : job.id);
      groups.putIfAbsent(key, () => []).add(job);
    }

    final List<ActionEmailReminder> result = [];
    for (final entry in groups.entries) {
      final groupJobs = entry.value;
      if (groupJobs.isEmpty) continue;

      final first = groupJobs.first;
      final scheduled = first.scheduledAt;
      final dateStr = scheduled != null ? formatDateForUi(scheduled) : '';
      final timeStr =
          scheduled != null ? formatTimeForUi(scheduled) : '09:00 AM';

      final hasActive = groupJobs.any((j) => j.status != 'cancelled');
      final jobsToUse = hasActive
          ? groupJobs.where((j) => j.status != 'cancelled')
          : groupJobs;

      final recips = <ActionPersonReference>[];
      final seen = <String>{};

      for (final j in jobsToUse) {
        final id = j.profileId ?? j.externalRecipientId ?? '';
        final key = id.isNotEmpty ? id : j.recipientName.toLowerCase();
        if (!seen.contains(key)) {
          seen.add(key);
          recips.add(
            ActionPersonReference(
              personId: id,
              name: j.recipientName,
              type: j.recipientType == 'external'
                  ? PersonType.externalWorker
                  : PersonType.internalUser,
              email: j.recipientEmail,
            ),
          );
        }
      }

      result.add(
        ActionEmailReminder(
          id: entry.key,
          isEnabled: hasActive,
          date: dateStr,
          time: timeStr,
          recipients: recips,
        ),
      );
    }

    return result;
  }

  // --------------------------------------------------------------------------
  // Serialization: From Supabase
  // --------------------------------------------------------------------------
  factory ActionRecord.fromSupabase(Map<String, dynamic> data) {
    // 0. Resolve scope type
    final rawScopeType = (data['scope_type'] as String?)?.trim().toLowerCase();
    final String resolvedScopeType;
    if (rawScopeType != null && rawScopeType.isNotEmpty) {
      resolvedScopeType = rawScopeType;
    } else if (data['department_id'] == null && data['site_id'] == null) {
      resolvedScopeType = 'organization';
    } else if (data['department_id'] != null && data['site_id'] == null) {
      resolvedScopeType = 'department';
    } else if (data['department_id'] == null && data['site_id'] != null) {
      resolvedScopeType = 'site';
    } else {
      resolvedScopeType = 'specific';
    }

    // 1. Resolve department name
    String deptName = '';
    String deptDivision = 'Operations';
    if (data['departments'] is Map) {
      final dMap = data['departments'] as Map<String, dynamic>;
      deptName = (dMap['name'] as String?) ?? '';
      deptDivision = (dMap['division'] as String?) ?? 'Operations';
    } else if (data['department_name'] != null) {
      deptName = data['department_name'].toString();
    }
    if (deptName.isEmpty &&
        (data['department_id'] == null ||
            data['department_id'].toString().isEmpty)) {
      deptName = 'All Departments';
    }

    // 2. Resolve site name
    String siteName = '';
    if (data['sites'] is Map) {
      final sMap = data['sites'] as Map<String, dynamic>;
      siteName = (sMap['name'] as String?) ?? '';
    } else if (data['site_name'] != null) {
      siteName = data['site_name'].toString();
    }
    if (siteName.isEmpty &&
        (data['site_id'] == null ||
            data['site_id'].toString().isEmpty)) {
      siteName = 'All Sites / Locations';
    }

    // 3. Resolve assignee
    ActionPersonReference? primaryPerson;
    String assigneeName = 'Unassigned';
    if (data['assignee'] is Map) {
      final aMap = data['assignee'] as Map<String, dynamic>;
      assigneeName = (aMap['full_name'] as String?) ?? 'Staff Member';
      primaryPerson = ActionPersonReference(
        personId:
            (aMap['id'] as String?) ?? (data['assigned_to'] as String? ?? ''),
        name: assigneeName,
        type: PersonType.internalUser,
        email: (aMap['email'] as String?) ?? '',
        phone: (aMap['phone'] as String?) ?? '',
        designation: (aMap['designation'] as String?) ?? 'Staff',
        department: deptName,
        site: siteName,
      );
    } else if (data['assigned_to_profile'] is Map) {
      final aMap = data['assigned_to_profile'] as Map<String, dynamic>;
      assigneeName = (aMap['full_name'] as String?) ?? 'Staff Member';
      primaryPerson = ActionPersonReference(
        personId:
            (aMap['id'] as String?) ?? (data['assigned_to'] as String? ?? ''),
        name: assigneeName,
        type: PersonType.internalUser,
        email: (aMap['email'] as String?) ?? '',
        phone: (aMap['phone'] as String?) ?? '',
        designation: (aMap['designation'] as String?) ?? 'Staff',
        department: deptName,
        site: siteName,
      );
    } else if (data['profiles_assigned'] is Map) {
      final aMap = data['profiles_assigned'] as Map<String, dynamic>;
      assigneeName = (aMap['full_name'] as String?) ?? 'Staff Member';
      primaryPerson = ActionPersonReference(
        personId:
            (aMap['id'] as String?) ?? (data['assigned_to'] as String? ?? ''),
        name: assigneeName,
        type: PersonType.internalUser,
        email: (aMap['email'] as String?) ?? '',
        phone: (aMap['phone'] as String?) ?? '',
        designation: (aMap['designation'] as String?) ?? 'Staff',
        department: deptName,
        site: siteName,
      );
    }

    // 3.1 Resolve external recipient
    final recType = (data['recipient_type'] as String?) ?? 'internal';
    final extId = data['external_recipient_id'] as String?;
    final emailReminderOn = data['email_reminder_enabled'] == true;

    ExternalRecipient? extRecipient;
    String? extName;
    String? extEmail;
    if (data['external_recipient'] is Map) {
      extRecipient = ExternalRecipient.fromJson(
        Map<String, dynamic>.from(data['external_recipient']),
      );
      extName = extRecipient.fullName;
      extEmail = extRecipient.email;
    } else if (data['external_action_recipients'] is Map) {
      extRecipient = ExternalRecipient.fromJson(
        Map<String, dynamic>.from(data['external_action_recipients']),
      );
      extName = extRecipient.fullName;
      extEmail = extRecipient.email;
    } else if (data['external_recipient_name'] != null) {
      extName = data['external_recipient_name'].toString();
      extEmail = data['external_recipient_email']?.toString();
    }

    if (recType == 'external' && extName != null && extName.isNotEmpty) {
      assigneeName = extName;
    }

    // 4. Resolve creator and assigner
    String creatorName = '';
    ActionPersonReference? creatorPerson;
    if (data['creator'] is Map) {
      final cMap = data['creator'] as Map<String, dynamic>;
      creatorName = (cMap['full_name'] as String?) ?? '';
      creatorPerson = ActionPersonReference(
        personId: (cMap['id'] as String?) ?? (data['created_by'] as String? ?? ''),
        name: creatorName.isNotEmpty ? creatorName : 'Unspecified',
        type: PersonType.internalUser,
        email: (cMap['email'] as String?) ?? '',
        phone: (cMap['phone'] as String?) ?? '',
        designation: (cMap['designation'] as String?) ?? '',
        department: (cMap['department'] as String?) ?? '',
      );
    } else if (data['created_by_profile'] is Map) {
      final cMap = data['created_by_profile'] as Map<String, dynamic>;
      creatorName = (cMap['full_name'] as String?) ?? '';
      creatorPerson = ActionPersonReference(
        personId: (cMap['id'] as String?) ?? (data['created_by'] as String? ?? ''),
        name: creatorName.isNotEmpty ? creatorName : 'Unspecified',
        type: PersonType.internalUser,
        email: (cMap['email'] as String?) ?? '',
        phone: (cMap['phone'] as String?) ?? '',
        designation: (cMap['designation'] as String?) ?? '',
        department: (cMap['department'] as String?) ?? '',
      );
    } else if (data['created_by_name'] != null) {
      creatorName = data['created_by_name'].toString();
    }

    String assignerName = '';
    ActionPersonReference? assignerPerson;
    if (data['assigner'] is Map) {
      final asgMap = data['assigner'] as Map<String, dynamic>;
      assignerName = (asgMap['full_name'] as String?) ?? '';
      assignerPerson = ActionPersonReference(
        personId: (asgMap['id'] as String?) ?? '',
        name: assignerName.isNotEmpty ? assignerName : 'Unspecified',
        type: PersonType.internalUser,
        email: (asgMap['email'] as String?) ?? '',
      );
    } else if (data['assigned_by_name'] != null) {
      assignerName = data['assigned_by_name'].toString();
    } else if (data['assigned_by'] != null) {
      if (data['assigned_by'] == data['created_by'] && creatorName.isNotEmpty) {
        assignerName = creatorName;
        assignerPerson = creatorPerson;
      }
    }
    if (assignerName.isEmpty) {
      assignerName = creatorName.isNotEmpty ? creatorName : 'Unspecified';
      assignerPerson = creatorPerson;
    }

    // 5. Parse subtasks
    final List<ActionSubTask> parsedSubtasks = [];
    final rawSubtasks = data['subtasks'] ?? data['sub_tasks'];
    if (rawSubtasks is List) {
      for (final item in rawSubtasks) {
        if (item is Map) {
          parsedSubtasks.add(
            ActionSubTask.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    // 6. Parse attachments
    final List<String> parsedAttachments = [];
    if (data['attachments'] is List) {
      for (final att in data['attachments'] as List) {
        if (att != null) parsedAttachments.add(att.toString());
      }
    }

    // 7. Parse history
    final List<String> parsedHistory = [];
    if (data['history'] is List) {
      for (final h in data['history'] as List) {
        if (h is Map) {
          final hAction = h['action'] ?? h['message'] ?? 'Status update';
          final hTime = h['timestamp'] != null
              ? formatDateForUi(h['timestamp'])
              : '';
          parsedHistory.add(hTime.isNotEmpty ? '$hTime: $hAction' : '$hAction');
        } else if (h != null) {
          parsedHistory.add(h.toString());
        }
      }
    }

    // 7.1 Parse progress updates
    final List<ActionProgressUpdate> parsedProgressUpdates = [];
    final rawUpdates =
        data['action_progress_updates'] ?? data['progress_updates'];
    if (rawUpdates is List) {
      for (final u in rawUpdates) {
        if (u is Map) {
          parsedProgressUpdates.add(
            ActionProgressUpdate.fromJson(Map<String, dynamic>.from(u)),
          );
        }
      }
    }

    // Also check data['history'] for progress updates (e.g. from submit_action_progress_update)
    if (data['history'] is List) {
      for (final h in data['history'] as List) {
        if (h is Map &&
            (h['type'] == 'progress_update' ||
                (h['progress'] != null && h['comments'] != null))) {
          final hMap = Map<String, dynamic>.from(h);
          final hId = hMap['id']?.toString() ?? '';
          if (hId.isEmpty || !parsedProgressUpdates.any((pu) => pu.id == hId)) {
            parsedProgressUpdates.add(
              ActionProgressUpdate.fromJson({
                'id': hId,
                'action_id': (data['id'] as String?) ?? '',
                'updated_by': hMap['updated_by'] ?? '',
                'updated_by_name': hMap['updated_by_name'] ?? '',
                'update_date': hMap['update_date'] ?? hMap['timestamp'],
                'progress': hMap['progress'] ?? 0,
                'status': hMap['status'] ?? 'In Progress',
                'comments': hMap['comments'] ?? hMap['action'] ?? '',
                'attachments': hMap['attachments'] ?? [],
                'created_at': hMap['timestamp'] ?? hMap['created_at'],
              }),
            );
          }
        }
      }
    }

    // Merge attachments from progress updates into parsedAttachments so staff update evidence
    // is immediately visible across manager portal and all action views
    for (final pu in parsedProgressUpdates) {
      for (final att in pu.attachments) {
        final clean = att.trim();
        if (clean.isNotEmpty && !parsedAttachments.contains(clean)) {
          parsedAttachments.add(clean);
        }
      }
    }

    // 7.2 Parse follow-ups
    final List<ActionFollowUpRecord> parsedFollowUps = [];
    final rawFollowUps = data['action_follow_ups'] ?? data['follow_ups'];
    if (rawFollowUps is List) {
      for (final f in rawFollowUps) {
        if (f is Map) {
          parsedFollowUps.add(
            ActionFollowUpRecord.fromJson(Map<String, dynamic>.from(f)),
          );
        }
      }
    }

    // 7.3 Parse assignees
    final List<ActionAssigneeRecord> parsedAssignees = [];
    final rawAssignees = data['action_assignees'] ?? data['assignees'];
    if (rawAssignees is List) {
      for (final a in rawAssignees) {
        if (a is Map) {
          parsedAssignees.add(
            ActionAssigneeRecord.fromJson(Map<String, dynamic>.from(a)),
          );
        }
      }
    }
    // Backward compatibility: ensure primary owner is in assignees list
    if (parsedAssignees.isEmpty &&
        data['assigned_to'] != null &&
        data['assigned_to'].toString().isNotEmpty) {
      parsedAssignees.add(
        ActionAssigneeRecord(
          id: 'primary-${data['id']}',
          actionId: (data['id'] as String?) ?? '',
          profileId: data['assigned_to'].toString(),
          profileName: assigneeName,
          assignmentRole: 'owner',
          isRequired: true,
          workCompleted: (data['percent_complete'] as num?)?.toInt() == 100,
        ),
      );
    }

    // 7.4 Parse contributors
    final List<ActionContributorRecord> parsedContributors = [];
    final rawContributors = data['action_contributors'] ?? data['contributors'];
    if (rawContributors is List) {
      for (final c in rawContributors) {
        if (c is Map) {
          parsedContributors.add(
            ActionContributorRecord.fromJson(Map<String, dynamic>.from(c)),
          );
        }
      }
    }

    // 7.5 Parse additional people / secondary assignees
    final List<ActionPersonReference> parsedAdditionalPeople = [];
    final rawAdditional = data['additional_people'] ?? data['additionalPeople'];
    if (rawAdditional is List && rawAdditional.isNotEmpty) {
      for (final p in rawAdditional) {
        if (p is Map) {
          parsedAdditionalPeople.add(
            ActionPersonReference(
              personId: (p['person_id'] ?? p['id'] ?? '').toString(),
              name: (p['name'] ?? '').toString(),
              type: (p['type']?.toString().contains('external') ?? false)
                  ? PersonType.externalWorker
                  : PersonType.internalUser,
              email: (p['email'] ?? '').toString(),
              phone: (p['phone'] ?? '').toString(),
              company: (p['company'] ?? '').toString(),
            ),
          );
        } else if (p is ActionPersonReference) {
          parsedAdditionalPeople.add(p);
        }
      }
    }
    // Also include secondary assignees from parsedAssignees
    for (final a in parsedAssignees) {
      if (!a.isOwner && a.profileId.isNotEmpty) {
        if (!parsedAdditionalPeople.any((p) => p.personId == a.profileId)) {
          parsedAdditionalPeople.add(
            ActionPersonReference(
              personId: a.profileId,
              name: a.profileName.isNotEmpty ? a.profileName : 'Staff Member',
              type: PersonType.internalUser,
              email: a.profileEmail,
            ),
          );
        }
      }
    }

    // Also parse relational external contacts from action_external_contacts if present
    final rawExternalContacts = data['action_external_contacts'];
    if (rawExternalContacts is List && rawExternalContacts.isNotEmpty) {
      for (final item in rawExternalContacts) {
        if (item is Map) {
          final rec = item['recipient'] ?? item['external_recipient'] ?? item;
          final recMap = rec is Map ? rec : item;
          final rId = (recMap['id'] ?? item['external_recipient_id'] ?? '').toString();
          if (rId.isNotEmpty && !parsedAdditionalPeople.any((p) => p.personId == rId)) {
            parsedAdditionalPeople.add(
              ActionPersonReference(
                personId: rId,
                name: (recMap['full_name'] ?? recMap['name'] ?? 'External Contact').toString(),
                type: PersonType.externalWorker,
                email: (recMap['email'] ?? '').toString(),
                phone: (recMap['phone'] ?? '').toString(),
                company: (recMap['company_name'] ?? recMap['company'] ?? '').toString(),
              ),
            );
          }
        }
      }
    }

    // 8. Resolve section
    final secId = data['section_id'] as String?;
    String secName = '';
    if (data['action_sections'] is Map) {
      final sMap = data['action_sections'] as Map<String, dynamic>;
      secName = (sMap['name'] as String?) ?? '';
    } else if (data['sections'] is Map) {
      final sMap = data['sections'] as Map<String, dynamic>;
      secName = (sMap['name'] as String?) ?? '';
    } else if (data['section_name'] != null) {
      secName = data['section_name'].toString();
    } else if (data['section'] != null) {
      secName = data['section'].toString();
    }

    // Resolve team
    String teamName = '';
    if (data['teams'] is Map) {
      final tMap = data['teams'] as Map<String, dynamic>;
      teamName = (tMap['name'] as String?) ?? '';
    } else if (data['team_name'] != null) {
      teamName = data['team_name'].toString();
    } else if (data['team'] != null) {
      teamName = data['team'].toString();
    }

    // 9. Resolve division
    final divId = data['division_id'] as String?;
    String resolvedDivName = deptDivision;
    if (data['divisions'] is Map) {
      final divMap = data['divisions'] as Map<String, dynamic>;
      resolvedDivName = (divMap['name'] as String?) ?? resolvedDivName;
    } else if (data['division_name'] != null) {
      resolvedDivName = data['division_name'].toString();
    } else if (data['division'] != null) {
      resolvedDivName = data['division'].toString();
    }

    // 10. Parse email reminders
    final List<ActionEmailReminder> parsedReminders = [];
    final rawReminders =
        data['action_email_reminders'] ?? data['email_reminders'];
    if (rawReminders is List && rawReminders.isNotEmpty) {
      final jobs = <ActionEmailReminderJob>[];
      for (final r in rawReminders) {
        if (r is Map) {
          jobs.add(
            ActionEmailReminderJob.fromJson(Map<String, dynamic>.from(r)),
          );
        } else if (r is ActionEmailReminderJob) {
          jobs.add(r);
        }
      }
      parsedReminders.addAll(parseRemindersFromJobs(jobs));
    }

    // 11. Resolve follow-up dates with fallback to scheduled checkpoints
    final String rawLastFollowUp = formatDateForUi(data['last_follow_up_date']);
    String rawNextFollowUp = formatDateForUi(data['next_follow_up_date']);
    if (rawNextFollowUp.isEmpty && parsedFollowUps.isNotEmpty) {
      final scheduled = parsedFollowUps.where((f) => f.status == 'Scheduled').toList();
      if (scheduled.isNotEmpty) {
        rawNextFollowUp = scheduled.first.followUpDate;
      } else {
        rawNextFollowUp = parsedFollowUps.last.followUpDate;
      }
    }
    if (rawNextFollowUp.isEmpty && rawLastFollowUp.isNotEmpty) {
      rawNextFollowUp = rawLastFollowUp;
    }

    final latestPu = parsedProgressUpdates.isNotEmpty
        ? (List<ActionProgressUpdate>.from(parsedProgressUpdates)
          ..sort((a, b) {
            final bDate = b.createdAt ??
                DateTime.tryParse(formatDateForDb(b.updateDate)) ??
                DateTime(1970);
            final aDate = a.createdAt ??
                DateTime.tryParse(formatDateForDb(a.updateDate)) ??
                DateTime(1970);
            return bDate.compareTo(aDate);
          }))
            .first
        : null;

    final String initialWorkerSubject =
        (data['worker_message_subject'] as String?) ?? '';
    final String resolvedWorkerSubject = initialWorkerSubject.isNotEmpty
        ? initialWorkerSubject
        : (latestPu?.effectiveSubject ?? '');

    final String initialWorkerMessage =
        (data['worker_message'] as String?) ?? '';
    final String resolvedWorkerMessage = initialWorkerMessage.isNotEmpty
        ? initialWorkerMessage
        : (latestPu?.effectiveWorkCompleted ?? '');

    final String resolvedPendingReason =
        (data['pending_reason'] as String?) ?? (latestPu?.pendingWork ?? '');
    final String resolvedRequirement =
        (data['requirement'] as String?) ?? (latestPu?.requirement ?? '');
    final String resolvedSuggestion =
        (data['suggestion'] as String?) ?? (latestPu?.suggestion ?? '');
    final String resolvedRemarks =
        (data['remarks'] as String?) ?? (latestPu?.remarks ?? '');
    final String resolvedMessageType = (data['message_type'] as String?) ??
        (latestPu?.messageType.isNotEmpty == true
            ? latestPu!.messageType
            : 'Progress Update');

    return ActionRecord(
      id: (data['id'] as String?) ?? '',
      actionNumber: (data['action_number'] as String?) ?? '',
      organizationId: (data['organization_id'] as String?) ?? '',
      departmentId: (data['department_id'] as String?) ?? '',
      siteId: (data['site_id'] as String?) ?? '',
      teamId: data['team_id'] as String?,
      team: teamName,
      sectionId: secId,
      section: secName,
      divisionId: divId,
      createdById: ((data['created_by'] as String?)?.trim().isNotEmpty == true)
          ? (data['created_by'] as String).trim()
          : (creatorPerson?.personId.trim().isNotEmpty == true
              ? creatorPerson!.personId.trim()
              : (((data['creator'] is Map)
                      ? (data['creator']['id'] as String?)
                      : null) ??
                  ((data['created_by_profile'] is Map)
                      ? (data['created_by_profile']['id'] as String?)
                      : null) ??
                  '')),
      assignedToId: data['assigned_to'] as String?,
      verifiedById: data['verified_by'] as String?,
      closedAt: data['closed_at'] != null
          ? DateTime.tryParse(data['closed_at'].toString())
          : null,
      closedById:
          (data['closed_by'] as String?) ?? (data['verified_by'] as String?),
      closedByName:
          (data['closer'] is Map
              ? (data['closer']['full_name'] as String?)
              : null) ??
          (data['closed_by_name'] as String?),
      closureComment: (data['closure_comment'] as String?) ?? '',
      subject: (data['title'] as String?) ?? '',
      actionRequired: (data['action_required'] as String?) ?? '',
      description: (data['description'] as String?) ?? '',
      category: (data['category'] as String?) ?? 'Inspection',
      source: (data['source'] as String?) ?? 'Direct Action',
      priority: (data['priority'] as String?) ?? 'Medium',
      status: (data['status'] as String?) ?? 'Open',
      percentComplete: (data['percent_complete'] as num?)?.toInt() ?? 0,
      startDate: formatDateForUi(data['start_date']),
      targetDate: formatDateForUi(data['due_date'] ?? data['target_date']),
      dateRaised: formatDateForUi(
        data['date_raised'] ?? data['created_date'] ?? data['created_at'],
      ),
      lastFollowUpDate: rawLastFollowUp,
      nextFollowUpDate: rawNextFollowUp,
      closeDate: formatDateForUi(data['close_date'] ?? data['closed_at']),
      verifiedBy: (data['verified_by'] as String?) ?? '',
      division: resolvedDivName,
      department: deptName,
      site: siteName,
      assignedTo: assigneeName,
      createdByName: creatorName.isNotEmpty ? creatorName : 'Unspecified',
      createdByPerson: creatorPerson,
      assignedBy: assignerName.isNotEmpty ? assignerName : 'Unspecified',
      assignedByPerson: assignerPerson,
      primaryAssignee: primaryPerson,
      additionalPeople: parsedAdditionalPeople,
      subTasks: parsedSubtasks,
      attachments: parsedAttachments,
      history: parsedHistory,
      progressUpdates: parsedProgressUpdates,
      followUps: parsedFollowUps,
      assignees: parsedAssignees,
      contributors: parsedContributors,
      workerMessageSubject: resolvedWorkerSubject,
      workerMessage: resolvedWorkerMessage,
      managerMessage: (data['manager_message'] as String?) ?? '',
      pendingReason: resolvedPendingReason,
      requirement: resolvedRequirement,
      suggestion: resolvedSuggestion,
      remarks: resolvedRemarks,
      messageType: resolvedMessageType,
      recipientType: recType,
      externalRecipientId: extId,
      externalRecipientEmail: extEmail,
      externalRecipientName: extName,
      emailReminderEnabled: emailReminderOn,
      emailReminders: parsedReminders,
      externalRecipient: extRecipient,
      scopeType: resolvedScopeType,
      createdAt: data['created_at'] != null
          ? DateTime.tryParse(data['created_at'].toString())
          : null,
    );
  }

  // --------------------------------------------------------------------------
  // Serialization: To Supabase Insert Map
  // --------------------------------------------------------------------------
  Map<String, dynamic> toSupabaseInsertMap() {
    final isClosedStatus = status.trim().toLowerCase() == 'closed';
    final map = <String, dynamic>{
      'title': subject.trim(),
      'description': description.trim().isNotEmpty
          ? description.trim()
          : actionRequired.trim(),
      'action_required': actionRequired.trim(),
      'category': category.isNotEmpty ? category : 'Inspection',
      'source': source.isNotEmpty ? source : 'Direct Action',
      'priority': priority.isNotEmpty ? priority : 'Medium',
      'status': status.isNotEmpty ? status : 'Open',
      'percent_complete': percentComplete.clamp(0, 100),
      'target_date': formatDateForDb(targetDate),
      'due_date': formatDateForDb(targetDate),
      'start_date':
          formatOptionalDateForDb(startDate) ?? formatDateForDb(dateRaised),
      'date_raised': formatDateForDb(dateRaised),
      'created_date': formatDateForDb(dateRaised),
      'organization_id': organizationId,
      'department_id': departmentId.isNotEmpty ? departmentId : null,
      'site_id': siteId.isNotEmpty ? siteId : null,
      'created_by': createdById,
      'subtasks': subTasks.map((st) => st.toJson()).toList(),
      'attachments': attachments,
      'worker_message_subject': workerMessageSubject,
      'worker_message': workerMessage,
      'manager_message': managerMessage,
      'recipient_type': recipientType,
      'email_reminder_enabled': emailReminderEnabled,
    };

    map['team_id'] = (teamId != null && teamId!.isNotEmpty) ? teamId : null;
    map['section_id'] =
        (sectionId != null && sectionId!.isNotEmpty) ? sectionId : null;
    map['division_id'] =
        (divisionId != null && divisionId!.isNotEmpty) ? divisionId : null;

    if (recipientType == 'external') {
      map['assigned_to'] = null;
      map['external_recipient_id'] =
          (externalRecipientId != null && externalRecipientId!.isNotEmpty)
              ? externalRecipientId
              : null;
    } else {
      map['assigned_to'] =
          (assignedToId != null && assignedToId!.isNotEmpty)
              ? assignedToId
              : null;
      map['external_recipient_id'] = null;
    }

    final parsedFollowUp = formatOptionalDateForDb(nextFollowUpDate);
    if (parsedFollowUp != null) {
      map['next_follow_up_date'] = parsedFollowUp;
    }
    final parsedLastFollowUp = formatOptionalDateForDb(lastFollowUpDate);
    if (parsedLastFollowUp != null) {
      map['last_follow_up_date'] = parsedLastFollowUp;
    }

    if (isClosedStatus) {
      map['close_date'] = closeDate.isNotEmpty
          ? formatDateForDb(closeDate)
          : DateTime.now().toIso8601String().substring(0, 10);
      map['closed_at'] =
          closedAt?.toIso8601String() ?? DateTime.now().toIso8601String();
      if (closedById != null && closedById!.isNotEmpty) {
        map['closed_by'] = closedById;
      }
    }

    return map;
  }

  // --------------------------------------------------------------------------
  // Serialization: To Supabase Update Map
  // --------------------------------------------------------------------------
  Map<String, dynamic> toSupabaseUpdateMap() {
    final isClosedStatus = status.trim().toLowerCase() == 'closed';
    final map = <String, dynamic>{
      'title': subject.trim(),
      'description': description.trim().isNotEmpty
          ? description.trim()
          : actionRequired.trim(),
      'action_required': actionRequired.trim(),
      'category': category.isNotEmpty ? category : 'Inspection',
      'source': source.isNotEmpty ? source : 'Direct Action',
      'priority': priority,
      'status': status,
      'percent_complete': percentComplete.clamp(0, 100),
      'target_date': formatDateForDb(targetDate),
      'due_date': formatDateForDb(targetDate),
      'start_date': formatOptionalDateForDb(startDate),
      'last_follow_up_date': formatOptionalDateForDb(lastFollowUpDate),
      'next_follow_up_date': formatOptionalDateForDb(nextFollowUpDate),
      'subtasks': subTasks.map((st) => st.toJson()).toList(),
      'attachments': attachments,
      'worker_message_subject': workerMessageSubject,
      'worker_message': workerMessage,
      'manager_message': managerMessage,
      'recipient_type': recipientType,
      'email_reminder_enabled': emailReminderEnabled,
      'department_id': departmentId.isNotEmpty ? departmentId : null,
      'site_id': siteId.isNotEmpty ? siteId : null,
      'team_id': (teamId != null && teamId!.isNotEmpty) ? teamId : null,
      'section_id':
          (sectionId != null && sectionId!.isNotEmpty) ? sectionId : null,
      'division_id':
          (divisionId != null && divisionId!.isNotEmpty) ? divisionId : null,
    };

    if (recipientType == 'external') {
      map['assigned_to'] = null;
      map['external_recipient_id'] =
          (externalRecipientId != null && externalRecipientId!.isNotEmpty)
              ? externalRecipientId
              : null;
    } else {
      map['assigned_to'] =
          (assignedToId != null && assignedToId!.isNotEmpty)
              ? assignedToId
              : null;
      map['external_recipient_id'] = null;
    }

    if (isClosedStatus) {
      map['close_date'] = closeDate.isNotEmpty
          ? formatDateForDb(closeDate)
          : DateTime.now().toIso8601String().substring(0, 10);
      map['closed_at'] =
          closedAt?.toIso8601String() ?? DateTime.now().toIso8601String();
      if (closedById != null && closedById!.isNotEmpty) {
        map['closed_by'] = closedById;
      }
      map['closure_comment'] =
          closureComment.isNotEmpty ? closureComment : '';
    } else {
      // Reopened or active action: intentionally clear closure columns
      map['close_date'] = null;
      map['closed_at'] = null;
      map['closed_by'] = null;
      if (closureComment.isNotEmpty) {
        map['closure_comment'] = closureComment;
      }
    }

    return map;
  }

  ActionRecord copyWith({
    String? id,
    String? actionNumber,
    String? organizationId,
    String? departmentId,
    String? siteId,
    String? teamId,
    String? team,
    String? sectionId,
    String? section,
    String? divisionId,
    String? createdById,
    String? createdByName,
    ActionPersonReference? createdByPerson,
    String? assignedToId,
    String? verifiedById,
    DateTime? closedAt,
    String? closedById,
    String? closedByName,
    String? closureComment,
    String? subject,
    String? actionRequired,
    String? division,
    String? department,
    String? site,
    String? category,
    String? source,
    String? assignedTo,
    String? originalAssignee,
    String? assignedBy,
    String? originalAssignedBy,
    ActionPersonReference? assignedByPerson,
    ActionPersonReference? originalAssignedByPerson,
    String? priority,
    String? status,
    int? percentComplete,
    String? supportingPerson,
    String? startDate,
    String? dateRaised,
    String? targetDate,
    String? lastFollowUpDate,
    String? nextFollowUpDate,
    String? closeDate,
    String? verifiedBy,
    List<String>? attachments,
    String? description,
    List<String>? history,
    String? workerMessageSubject,
    String? workerMessage,
    String? messageType,
    String? requirement,
    String? pendingReason,
    String? suggestion,
    String? remarks,
    String? managerMessage,
    ActionPersonReference? primaryAssignee,
    List<ActionPersonReference>? additionalPeople,
    List<ActionEmailReminder>? emailReminders,
    List<ActionSubTask>? subTasks,
    List<ActionProgressUpdate>? progressUpdates,
    List<ActionFollowUpRecord>? followUps,
    List<ActionAssigneeRecord>? assignees,
    List<ActionContributorRecord>? contributors,
    String? recipientType,
    String? externalRecipientId,
    String? externalRecipientEmail,
    String? externalRecipientName,
    bool? emailReminderEnabled,
    ExternalRecipient? externalRecipient,
    String? scopeType,
    DateTime? createdAt,
  }) {
    return ActionRecord(
      id: id ?? this.id,
      actionNumber: actionNumber ?? this.actionNumber,
      organizationId: organizationId ?? this.organizationId,
      departmentId: departmentId ?? this.departmentId,
      siteId: siteId ?? this.siteId,
      teamId: teamId ?? this.teamId,
      team: team ?? this.team,
      sectionId: sectionId ?? this.sectionId,
      section: section ?? this.section,
      divisionId: divisionId ?? this.divisionId,
      createdById: createdById ?? this.createdById,
      createdByName: createdByName ?? this.createdByName,
      createdByPerson: createdByPerson ?? this.createdByPerson,
      assignedToId: assignedToId ?? this.assignedToId,
      verifiedById: verifiedById ?? this.verifiedById,
      closedAt: closedAt ?? this.closedAt,
      closedById: closedById ?? this.closedById,
      closedByName: closedByName ?? this.closedByName,
      closureComment: closureComment ?? this.closureComment,
      subject: subject ?? this.subject,
      actionRequired: actionRequired ?? this.actionRequired,
      division: division ?? this.division,
      department: department ?? this.department,
      site: site ?? this.site,
      category: category ?? this.category,
      source: source ?? this.source,
      assignedTo: assignedTo ?? this.assignedTo,
      originalAssignee: originalAssignee ?? this.originalAssignee,
      assignedBy: assignedBy ?? this.assignedBy,
      originalAssignedBy: originalAssignedBy ?? this.originalAssignedBy,
      assignedByPerson: assignedByPerson ?? this.assignedByPerson,
      originalAssignedByPerson:
          originalAssignedByPerson ?? this.originalAssignedByPerson,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      percentComplete: percentComplete ?? this.percentComplete,
      supportingPerson: supportingPerson ?? this.supportingPerson,
      startDate: startDate ?? this.startDate,
      dateRaised: dateRaised ?? this.dateRaised,
      targetDate: targetDate ?? this.targetDate,
      lastFollowUpDate: lastFollowUpDate ?? this.lastFollowUpDate,
      nextFollowUpDate: nextFollowUpDate ?? this.nextFollowUpDate,
      closeDate: closeDate ?? this.closeDate,
      verifiedBy: verifiedBy ?? this.verifiedBy,
      attachments: attachments ?? this.attachments,
      description: description ?? this.description,
      history: history ?? this.history,
      progressUpdates: progressUpdates ?? this.progressUpdates,
      followUps: followUps ?? this.followUps,
      assignees: assignees ?? this.assignees,
      contributors: contributors ?? this.contributors,
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
      subTasks: subTasks ?? this.subTasks,
      recipientType: recipientType ?? this.recipientType,
      externalRecipientId: externalRecipientId ?? this.externalRecipientId,
      externalRecipientEmail:
          externalRecipientEmail ?? this.externalRecipientEmail,
      externalRecipientName:
          externalRecipientName ?? this.externalRecipientName,
      emailReminderEnabled: emailReminderEnabled ?? this.emailReminderEnabled,
      externalRecipient: externalRecipient ?? this.externalRecipient,
      scopeType: scopeType ?? this.scopeType,
      createdAt: createdAt ?? this.createdAt,
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'is_enabled': isEnabled,
    'date': date,
    'time': time,
    'recipients': recipients
        .map(
          (r) => {
            'person_id': r.personId,
            'name': r.name,
            'type':
                r.type == PersonType.externalWorker ? 'external' : 'internal',
            'email': r.email,
            'phone': r.phone,
            'company': r.company,
            'designation': r.designation,
            'department': r.department,
            'site': r.site,
            'role': r.role,
          },
        )
        .toList(),
  };

  factory ActionEmailReminder.fromJson(Map<String, dynamic> json) {
    final rawRecips = json['recipients'];
    final List<ActionPersonReference> recips = [];
    if (rawRecips is List) {
      for (final r in rawRecips) {
        if (r is Map) {
          recips.add(
            ActionPersonReference(
              personId:
                  (r['person_id'] as String?) ??
                  (r['personId'] as String?) ??
                  '',
              name: (r['name'] as String?) ?? '',
              type:
                  (r['type'] == 'external' ||
                          r['type'] == PersonType.externalWorker.name)
                      ? PersonType.externalWorker
                      : PersonType.internalUser,
              email: (r['email'] as String?) ?? '',
              phone: (r['phone'] as String?) ?? '',
              company: (r['company'] as String?) ?? '',
              designation: (r['designation'] as String?) ?? '',
              department: (r['department'] as String?) ?? '',
              site: (r['site'] as String?) ?? '',
              role: (r['role'] as String?) ?? '',
            ),
          );
        }
      }
    }
    return ActionEmailReminder(
      id: (json['id'] as String?) ?? '',
      isEnabled: json['is_enabled'] != false && json['isEnabled'] != false,
      date: (json['date'] as String?) ?? '',
      time: (json['time'] as String?) ?? '09:00 AM',
      recipients: recips,
    );
  }
}
