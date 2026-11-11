import 'dart:convert';

import 'package:flutter/material.dart';

/// Supported Request Types in ActionFlow
class RequestType {
  static const String ptw = 'Permit to Work (PTW)';
  static const String equipment = 'Equipment';
  static const String material = 'Material';
  static const String access = 'Access';
  static const String other = 'Other';

  static const List<String> values = [
    ptw,
    equipment,
    material,
    access,
    other,
  ];

  static IconData getIcon(String type) {
    switch (type) {
      case ptw:
        return Icons.assignment_outlined;
      case equipment:
        return Icons.build_outlined;
      case material:
        return Icons.inventory_2_outlined;
      case access:
        return Icons.vpn_key_outlined;
      case other:
      default:
        return Icons.article_outlined;
    }
  }

  static Color getColor(String type) {
    switch (type) {
      case ptw:
        return const Color(0xFF0284C7); // Sky blue
      case equipment:
        return const Color(0xFFD97706); // Amber
      case material:
        return const Color(0xFF059669); // Emerald
      case access:
        return const Color(0xFF7C3AED); // Purple
      case other:
      default:
        return const Color(0xFF475569); // Slate
    }
  }
}

/// Request Priority Levels
class RequestPriority {
  static const String low = 'Low';
  static const String medium = 'Medium';
  static const String high = 'High';
  static const String critical = 'Critical';

  static const List<String> values = [
    low,
    medium,
    high,
    critical,
  ];

  static Color getColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'critical':
        return const Color(0xFFDC2626); // Red 600
      case 'high':
        return const Color(0xFFEA580C); // Orange 600
      case 'medium':
        return const Color(0xFFD97706); // Amber 600
      case 'low':
      default:
        return const Color(0xFF16A34A); // Green 600
    }
  }
}

/// Approval Types
class ApprovalType {
  static const String sequential = 'Sequential';
  static const String parallel = 'Parallel';

  static const List<String> values = [
    sequential,
    parallel,
  ];
}

/// Request Statuses
class RequestStatus {
  static const String draft = 'Draft';
  static const String pending = 'Pending';
  static const String underReview = 'Under Review';
  static const String approved = 'Approved';
  static const String rejected = 'Rejected';
  static const String completed = 'Completed';

  static const List<String> values = [
    draft,
    pending,
    underReview,
    approved,
    rejected,
    completed,
  ];

  static Color getColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return const Color(0xFF16A34A); // Green 600
      case 'completed':
        return const Color(0xFF0284C7); // Sky 600
      case 'rejected':
        return const Color(0xFFDC2626); // Red 600
      case 'under review':
        return const Color(0xFF7C3AED); // Purple 600
      case 'pending':
        return const Color(0xFFD97706); // Amber 600
      case 'draft':
      default:
        return const Color(0xFF64748B); // Slate 500
    }
  }

  static IconData getIcon(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Icons.check_circle_outline_rounded;
      case 'completed':
        return Icons.task_alt_rounded;
      case 'rejected':
        return Icons.cancel_outlined;
      case 'under review':
        return Icons.rate_review_outlined;
      case 'pending':
        return Icons.hourglass_top_rounded;
      case 'draft':
      default:
        return Icons.edit_note_rounded;
    }
  }
}

/// Model representing an individual approver assignment on a request
class RequestApproverRecord {
  const RequestApproverRecord({
    required this.id,
    required this.requestId,
    required this.approverId,
    required this.approverName,
    required this.approverRole,
    this.approverDepartment = '',
    this.stepOrder = 1,
    this.status = 'Pending',
    this.decisionComments = '',
    this.decidedAt,
    this.createdAt,
  });

  final String id;
  final String requestId;
  final String approverId;
  final String approverName;
  final String approverRole;
  final String approverDepartment;
  final int stepOrder;
  final String status; // 'Pending', 'Approved', 'Rejected'
  final String decisionComments;
  final DateTime? decidedAt;
  final DateTime? createdAt;

  bool get isApproved => status.toLowerCase() == 'approved';
  bool get isRejected => status.toLowerCase() == 'rejected';
  bool get isPending => status.toLowerCase() == 'pending';

  factory RequestApproverRecord.fromJson(Map<String, dynamic> json) {
    return RequestApproverRecord(
      id: json['id']?.toString() ?? '',
      requestId: json['request_id']?.toString() ?? '',
      approverId: json['approver_id']?.toString() ?? '',
      approverName: json['approver_name']?.toString() ?? '',
      approverRole: json['approver_role']?.toString() ?? '',
      approverDepartment: json['approver_department']?.toString() ?? '',
      stepOrder: (json['step_order'] as num?)?.toInt() ?? 1,
      status: json['status']?.toString() ?? 'Pending',
      decisionComments: json['decision_comments']?.toString() ?? '',
      decidedAt: json['decided_at'] != null ? DateTime.tryParse(json['decided_at'].toString()) : null,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'request_id': requestId,
    'approver_id': approverId,
    'approver_name': approverName,
    'approver_role': approverRole,
    'approver_department': approverDepartment,
    'step_order': stepOrder,
    'status': status,
    'decision_comments': decisionComments,
    if (decidedAt != null) 'decided_at': decidedAt!.toIso8601String(),
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
  };
}

/// Model representing a request file attachment
class RequestAttachmentRecord {
  const RequestAttachmentRecord({
    required this.id,
    required this.requestId,
    required this.fileName,
    required this.filePath,
    required this.fileSize,
    this.contentType = '',
    this.uploadedBy = '',
    this.createdAt,
  });

  final String id;
  final String requestId;
  final String fileName;
  final String filePath;
  final int fileSize;
  final String contentType;
  final String uploadedBy;
  final DateTime? createdAt;

  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get fileExtension {
    final dotIdx = fileName.lastIndexOf('.');
    if (dotIdx != -1 && dotIdx < fileName.length - 1) {
      return fileName.substring(dotIdx + 1).toLowerCase();
    }
    return '';
  }

  bool get isImage =>
      contentType.toLowerCase().startsWith('image/') ||
      fileExtension == 'png' ||
      fileExtension == 'jpg' ||
      fileExtension == 'jpeg' ||
      fileExtension == 'webp';

  bool get isPdf =>
      contentType.toLowerCase().contains('pdf') ||
      fileExtension == 'pdf';

  factory RequestAttachmentRecord.fromJson(Map<String, dynamic> json) {
    return RequestAttachmentRecord(
      id: json['id']?.toString() ?? '',
      requestId: json['request_id']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? '',
      filePath: json['file_path']?.toString() ?? '',
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      contentType: json['content_type']?.toString() ?? '',
      uploadedBy: json['uploaded_by']?.toString() ?? '',
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'request_id': requestId,
    'file_name': fileName,
    'file_path': filePath,
    'file_size': fileSize,
    'content_type': contentType,
    'uploaded_by': uploadedBy,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
  };
}

/// Model representing a request forward event
class RequestForwardRecord {
  const RequestForwardRecord({
    required this.id,
    required this.requestId,
    required this.fromUserId,
    required this.fromUserName,
    required this.toUserId,
    required this.toUserName,
    this.notes = '',
    this.createdAt,
  });

  final String id;
  final String requestId;
  final String fromUserId;
  final String fromUserName;
  final String toUserId;
  final String toUserName;
  final String notes;
  final DateTime? createdAt;

  factory RequestForwardRecord.fromJson(Map<String, dynamic> json) {
    return RequestForwardRecord(
      id: json['id']?.toString() ?? '',
      requestId: json['request_id']?.toString() ?? '',
      fromUserId: json['from_user_id']?.toString() ?? '',
      fromUserName: json['from_user_name']?.toString() ?? '',
      toUserId: json['to_user_id']?.toString() ?? '',
      toUserName: json['to_user_name']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'request_id': requestId,
    'from_user_id': fromUserId,
    'from_user_name': fromUserName,
    'to_user_id': toUserId,
    'to_user_name': toUserName,
    'notes': notes,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
  };
}

/// Model representing an audit event on a request
class RequestHistoryRecord {
  const RequestHistoryRecord({
    required this.id,
    required this.requestId,
    required this.actorId,
    required this.actorName,
    required this.actorRole,
    required this.action,
    required this.details,
    this.metadata = const {},
    this.createdAt,
  });

  final String id;
  final String requestId;
  final String actorId;
  final String actorName;
  final String actorRole;
  final String action;
  final String details;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;

  /// Returns a clean, human-readable summary of details, parsing JSON payloads if present
  String get formattedDetails {
    final trimmed = details.trim();
    if (trimmed.isEmpty) return '';

    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          final parts = <String>[];
          final approvalType = decoded['approval_type']?.toString();
          final approversCount = decoded['approvers_count'];
          final attachmentsCount = decoded['attachments_count'];

          if (approvalType != null && approvalType.isNotEmpty) {
            parts.add('$approvalType approval');
          }
          if (approversCount != null) {
            final count = int.tryParse(approversCount.toString()) ?? 0;
            parts.add('$count ${count == 1 ? 'Approver' : 'Approvers'}');
          }
          if (attachmentsCount != null) {
            final count = int.tryParse(attachmentsCount.toString()) ?? 0;
            if (count > 0) {
              parts.add('$count ${count == 1 ? 'Attachment' : 'Attachments'}');
            }
          }

          if (parts.isNotEmpty) {
            final prefix = action.toLowerCase() == 'submitted'
                ? 'Submitted for '
                : '';
            return '$prefix${parts.join(' • ')}';
          }

          return decoded.entries
              .where((e) => e.value != null && e.value.toString().isNotEmpty)
              .map((e) {
                final key = e.key.replaceAll('_', ' ').split(' ').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');
                return '$key: ${e.value}';
              })
              .join(' • ');
        }
      } catch (_) {
        // Fallback to raw trimmed details
      }
    }

    return trimmed;
  }

  factory RequestHistoryRecord.fromJson(Map<String, dynamic> json) {
    return RequestHistoryRecord(
      id: json['id']?.toString() ?? '',
      requestId: json['request_id']?.toString() ?? '',
      actorId: json['actor_id']?.toString() ?? '',
      actorName: json['actor_name']?.toString() ?? '',
      actorRole: json['actor_role']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      details: json['details']?.toString() ?? '',
      metadata: json['metadata'] is Map ? Map<String, dynamic>.from(json['metadata'] as Map) : {},
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'request_id': requestId,
    'actor_id': actorId,
    'actor_name': actorName,
    'actor_role': actorRole,
    'action': action,
    'details': details,
    'metadata': metadata,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
  };
}

/// Master model representing an ActionFlow Request
class RequestRecord {
  const RequestRecord({
    required this.id,
    required this.displayId,
    required this.organizationId,
    required this.title,
    required this.description,
    required this.requestType,
    required this.priority,
    this.departmentId,
    this.departmentName = '',
    this.siteId,
    this.siteName = '',
    required this.requiredByDate,
    this.requiredByTime = '',
    this.approvalType = 'Sequential',
    this.status = 'Pending',
    required this.createdBy,
    required this.createdByName,
    required this.createdByRole,
    this.createdByEmail = '',
    this.additionalNotes = '',
    this.rejectionReason,
    this.rejectedBy,
    this.rejectedAt,
    this.approvedAt,
    this.completedAt,
    this.completedBy,
    this.createdAt,
    this.updatedAt,
    this.approvers = const [],
    this.attachments = const [],
    this.forwards = const [],
    this.history = const [],
  });

  final String id;
  final String displayId;
  final String organizationId;
  final String title;
  final String description;
  final String requestType;
  final String priority;
  final String? departmentId;
  final String departmentName;
  final String? siteId;
  final String siteName;
  final String requiredByDate; // 'YYYY-MM-DD'
  final String requiredByTime;
  final String approvalType; // 'Sequential' or 'Parallel'
  final String status; // 'Draft', 'Pending', 'Under Review', 'Approved', 'Rejected', 'Completed'
  final String createdBy;
  String get createdById => createdBy;
  final String createdByName;
  final String createdByRole;
  final String createdByEmail;
  final String additionalNotes;
  final String? rejectionReason;
  final String? rejectedBy;
  final DateTime? rejectedAt;
  final DateTime? approvedAt;
  final DateTime? completedAt;
  final String? completedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  final List<RequestApproverRecord> approvers;
  final List<RequestAttachmentRecord> attachments;
  final List<RequestForwardRecord> forwards;
  final List<RequestHistoryRecord> history;

  bool get isDraft => status.toLowerCase() == 'draft';
  bool get isPending => status.toLowerCase() == 'pending';
  bool get isUnderReview => status.toLowerCase() == 'under review';
  bool get isApproved => status.toLowerCase() == 'approved';
  bool get isRejected => status.toLowerCase() == 'rejected';
  bool get isCompleted => status.toLowerCase() == 'completed';

  bool get isSequential => approvalType.toLowerCase() == 'sequential';
  bool get isParallel => approvalType.toLowerCase() == 'parallel';

  /// Total count of approvers who have approved
  int get approvedCount => approvers.where((a) => a.isApproved).length;

  /// Approval progress label (e.g. "2 of 3 Approved")
  String get approvalProgress {
    if (approvers.isEmpty) return 'No approvers';
    return '$approvedCount of ${approvers.length} Approved';
  }

  /// Calculates percentage of approvals completed (0-100)
  double get approvalProgressFraction {
    if (approvers.isEmpty) return 0.0;
    return (approvedCount / approvers.length).clamp(0.0, 1.0);
  }

  /// Returns the current pending approver for sequential workflows,
  /// or a comma-separated list of pending approvers for parallel workflows.
  String get pendingApproversSummary {
    if (isApproved || isCompleted || isRejected) return 'None';
    if (isSequential) {
      final sorted = List<RequestApproverRecord>.from(approvers)
        ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
      final next = sorted.firstWhere(
        (a) => a.isPending,
        orElse: () => sorted.first,
      );
      return next.approverName;
    } else {
      final pendingList = approvers.where((a) => a.isPending).map((a) => a.approverName).toList();
      if (pendingList.isEmpty) return 'None';
      if (pendingList.length > 2) {
        return '${pendingList.take(2).join(", ")} +${pendingList.length - 2} more';
      }
      return pendingList.join(', ');
    }
  }

  /// Checks if a specific user can approve this request right now
  bool canUserApprove(String userId) {
    if (isApproved || isCompleted || isRejected) return false;
    final myApproverRecord = approvers.firstWhere(
      (a) => a.approverId == userId,
      orElse: () => const RequestApproverRecord(
        id: '',
        requestId: '',
        approverId: '',
        approverName: '',
        approverRole: '',
      ),
    );
    if (myApproverRecord.id.isEmpty || !myApproverRecord.isPending) return false;

    if (isSequential) {
      // In sequential mode, all earlier steps must be approved
      return !approvers.any((a) => a.stepOrder < myApproverRecord.stepOrder && !a.isApproved);
    }
    // In parallel mode, any pending assigned approver can approve anytime
    return true;
  }

  /// Checks if a user is authorized to mark an approved request as completed.
  /// Rule:
  /// - Original requester: permitted to complete an approved request.
  /// - Scoped Manager: permitted within authorized scope.
  /// - Company Admin: permitted according to administrative permissions.
  /// - Designated approver: approval authority alone does NOT grant completion authority.
  /// - Forwarded recipient: no automatic completion authority.
  /// - Ordinary Staff: no completion authority unless they are the original requester.
  bool canUserComplete(
    String userId, {
    bool isManager = false,
    bool isScoped = false,
    bool isCompanyAdmin = false,
  }) {
    if (!isApproved) return false;
    if (isCompleted) return false;
    if (createdBy == userId) return true;
    if (isCompanyAdmin) return true;
    if (isManager && isScoped) return true;
    return false;
  }

  factory RequestRecord.fromJson(Map<String, dynamic> json) {
    final approversList = (json['request_approvers'] as List?)
            ?.map((e) => RequestApproverRecord.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        (json['approvers'] as List?)
            ?.map((e) => RequestApproverRecord.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        <RequestApproverRecord>[];

    final attachmentsList = (json['request_attachments'] as List?)
            ?.map((e) => RequestAttachmentRecord.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        (json['attachments'] as List?)
            ?.map((e) => RequestAttachmentRecord.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        <RequestAttachmentRecord>[];

    final forwardsList = (json['request_forwards'] as List?)
            ?.map((e) => RequestForwardRecord.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        (json['forwards'] as List?)
            ?.map((e) => RequestForwardRecord.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        <RequestForwardRecord>[];

    final historyList = (json['request_history'] as List?)
            ?.map((e) => RequestHistoryRecord.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        (json['history'] as List?)
            ?.map((e) => RequestHistoryRecord.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        <RequestHistoryRecord>[];

    return RequestRecord(
      id: json['id']?.toString() ?? '',
      displayId: json['display_id']?.toString() ?? '',
      organizationId: json['organization_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      requestType: json['request_type']?.toString() ?? RequestType.other,
      priority: json['priority']?.toString() ?? RequestPriority.medium,
      departmentId: json['department_id']?.toString(),
      departmentName: json['department_name']?.toString() ?? '',
      siteId: json['site_id']?.toString(),
      siteName: json['site_name']?.toString() ?? '',
      requiredByDate: json['required_by_date']?.toString() ?? '',
      requiredByTime: json['required_by_time']?.toString() ?? '',
      approvalType: json['approval_type']?.toString() ?? ApprovalType.sequential,
      status: json['status']?.toString() ?? RequestStatus.pending,
      createdBy: json['created_by']?.toString() ?? '',
      createdByName: json['created_by_name']?.toString() ?? '',
      createdByRole: json['created_by_role']?.toString() ?? '',
      createdByEmail: json['created_by_email']?.toString() ?? '',
      additionalNotes: json['additional_notes']?.toString() ?? '',
      rejectionReason: json['rejection_reason']?.toString(),
      rejectedBy: json['rejected_by']?.toString(),
      rejectedAt: json['rejected_at'] != null ? DateTime.tryParse(json['rejected_at'].toString()) : null,
      approvedAt: json['approved_at'] != null ? DateTime.tryParse(json['approved_at'].toString()) : null,
      completedAt: json['completed_at'] != null ? DateTime.tryParse(json['completed_at'].toString()) : null,
      completedBy: json['completed_by']?.toString(),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
      approvers: approversList,
      attachments: attachmentsList,
      forwards: forwardsList,
      history: historyList,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'display_id': displayId,
    'organization_id': organizationId,
    'title': title,
    'description': description,
    'request_type': requestType,
    'priority': priority,
    'department_id': departmentId,
    'department_name': departmentName,
    'site_id': siteId,
    'site_name': siteName,
    'required_by_date': requiredByDate,
    'required_by_time': requiredByTime,
    'approval_type': approvalType,
    'status': status,
    'created_by': createdBy,
    'created_by_name': createdByName,
    'created_by_role': createdByRole,
    'created_by_email': createdByEmail,
    'additional_notes': additionalNotes,
    'rejection_reason': rejectionReason,
    'rejected_by': rejectedBy,
    if (rejectedAt != null) 'rejected_at': rejectedAt!.toIso8601String(),
    if (approvedAt != null) 'approved_at': approvedAt!.toIso8601String(),
    if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
    'completed_by': completedBy,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    'approvers': approvers.map((a) => a.toJson()).toList(),
    'attachments': attachments.map((a) => a.toJson()).toList(),
    'forwards': forwards.map((f) => f.toJson()).toList(),
    'history': history.map((h) => h.toJson()).toList(),
  };

  RequestRecord copyWith({
    String? id,
    String? displayId,
    String? organizationId,
    String? title,
    String? description,
    String? requestType,
    String? priority,
    String? departmentId,
    String? departmentName,
    String? siteId,
    String? siteName,
    String? requiredByDate,
    String? requiredByTime,
    String? approvalType,
    String? status,
    String? createdBy,
    String? createdByName,
    String? createdByRole,
    String? createdByEmail,
    String? additionalNotes,
    String? rejectionReason,
    String? rejectedBy,
    DateTime? rejectedAt,
    DateTime? approvedAt,
    DateTime? completedAt,
    String? completedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<RequestApproverRecord>? approvers,
    List<RequestAttachmentRecord>? attachments,
    List<RequestForwardRecord>? forwards,
    List<RequestHistoryRecord>? history,
    bool clearRejection = false,
  }) {
    return RequestRecord(
      id: id ?? this.id,
      displayId: displayId ?? this.displayId,
      organizationId: organizationId ?? this.organizationId,
      title: title ?? this.title,
      description: description ?? this.description,
      requestType: requestType ?? this.requestType,
      priority: priority ?? this.priority,
      departmentId: departmentId ?? this.departmentId,
      departmentName: departmentName ?? this.departmentName,
      siteId: siteId ?? this.siteId,
      siteName: siteName ?? this.siteName,
      requiredByDate: requiredByDate ?? this.requiredByDate,
      requiredByTime: requiredByTime ?? this.requiredByTime,
      approvalType: approvalType ?? this.approvalType,
      status: status ?? this.status,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      createdByRole: createdByRole ?? this.createdByRole,
      createdByEmail: createdByEmail ?? this.createdByEmail,
      additionalNotes: additionalNotes ?? this.additionalNotes,
      rejectionReason: clearRejection ? null : (rejectionReason ?? this.rejectionReason),
      rejectedBy: clearRejection ? null : (rejectedBy ?? this.rejectedBy),
      rejectedAt: clearRejection ? null : (rejectedAt ?? this.rejectedAt),
      approvedAt: approvedAt ?? this.approvedAt,
      completedAt: completedAt ?? this.completedAt,
      completedBy: completedBy ?? this.completedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      approvers: approvers ?? this.approvers,
      attachments: attachments ?? this.attachments,
      forwards: forwards ?? this.forwards,
      history: history ?? this.history,
    );
  }
}

/// Container for server-side paginated request queries
class PaginatedRequestsResult {
  const PaginatedRequestsResult({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  });

  final List<RequestRecord> items;
  final int totalCount;
  final int page;
  final int pageSize;

  int get totalPages => pageSize > 0 ? (totalCount / pageSize).ceil() : 0;
  bool get hasNextPage => page < totalPages;
  bool get hasPreviousPage => page > 1;

  static const PaginatedRequestsResult empty = PaginatedRequestsResult(
    items: [],
    totalCount: 0,
    page: 1,
    pageSize: 10,
  );
}

/// Aggregated counts for the Manager Dashboard Request Overview section.
class ManagerRequestOverviewCounts {
  final int total;
  final int pendingMyApproval;
  final int underReview;
  final int approved;
  final int rejected;
  final int completed;

  const ManagerRequestOverviewCounts({
    this.total = 0,
    this.pendingMyApproval = 0,
    this.underReview = 0,
    this.approved = 0,
    this.rejected = 0,
    this.completed = 0,
  });

  bool get isEmpty => total == 0 && pendingMyApproval == 0;

  static const ManagerRequestOverviewCounts zero = ManagerRequestOverviewCounts();
}

/// Aggregated counts for the Staff Dashboard Request Overview section.
class StaffRequestOverviewCounts {
  final int mySubmittedTotal;
  final int pendingApproval;
  final int underReview;
  final int approved;
  final int rejected;
  final int completed;
  final int? pendingMyApproval; // Non-null only if staff is a designated approver

  const StaffRequestOverviewCounts({
    this.mySubmittedTotal = 0,
    this.pendingApproval = 0,
    this.underReview = 0,
    this.approved = 0,
    this.rejected = 0,
    this.completed = 0,
    this.pendingMyApproval,
  });

  bool get isEmpty =>
      mySubmittedTotal == 0 && (pendingMyApproval == null || pendingMyApproval == 0);

  static const StaffRequestOverviewCounts zero = StaffRequestOverviewCounts();
}

/// Independent aggregate counts for the Request Approval screen summary cards.
/// These counts reflect all requests within the user's authorized scope,
/// regardless of the active tab index or pagination page.
class RequestApprovalSummaryCounts {
  final int myActionRequired;
  final int totalInScope;
  final int approved;
  final int rejected;

  const RequestApprovalSummaryCounts({
    this.myActionRequired = 0,
    this.totalInScope = 0,
    this.approved = 0,
    this.rejected = 0,
  });

  static const RequestApprovalSummaryCounts zero = RequestApprovalSummaryCounts();
}


