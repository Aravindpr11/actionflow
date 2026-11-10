import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Document category types for HSSE compliance and action tracking
class DocumentCategory {
  static const String hsseManuals = 'HSSE Manuals';
  static const String auditChecklists = 'Audit Checklists';
  static const String incidentReports = 'Incident Reports';
  static const String riskAssessments = 'Risk Assessments';
  static const String policies = 'Policies';
  static const String actionEvidence = 'Action Evidence';
  static const String general = 'General';

  static const List<String> all = [
    hsseManuals,
    auditChecklists,
    incidentReports,
    riskAssessments,
    policies,
    actionEvidence,
    general,
  ];
}

/// Core Document Record representing an uploaded HSSE document
class DocumentRecord {
  const DocumentRecord({
    required this.id,
    required this.organizationId,
    this.departmentId,
    required this.title,
    this.description = '',
    this.category = DocumentCategory.general,
    required this.fileName,
    required this.filePath,
    required this.fileSize,
    required this.fileType,
    this.storageBucket = 'documents',
    this.actionId,
    this.actionNumber,
    this.createdBy,
    this.createdByName = '',
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
    this.sharedInternalCount = 0,
    this.sharedExternalCount = 0,
    this.sharedWithUserIds = const [],
    this.sharedByUserIds = const [],
    this.sharedByUserName,
    this.sharedAt,
    this.fileBytes,
    this.isPersisted = true,
  });

  final String id;
  final String organizationId;
  final String? departmentId;
  final String title;
  final String description;
  final String category;
  final String fileName;
  final String filePath;
  final int fileSize; // bytes
  final String fileType; // MIME type or extension
  final String storageBucket;
  final String? actionId;
  final String? actionNumber;
  final String? createdBy;
  final String createdByName;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int sharedInternalCount;
  final int sharedExternalCount;
  final List<String> sharedWithUserIds;
  final List<String> sharedByUserIds;
  final String? sharedByUserName;
  final DateTime? sharedAt;

  int get totalSharedCount => sharedInternalCount + sharedExternalCount;

  /// Optional in-memory bytes for offline preview or testing
  final List<int>? fileBytes;

  /// Whether the document has been successfully persisted to backend database and storage
  final bool isPersisted;

  String get formattedFileSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get fileExtension {
    final dotIdx = fileName.lastIndexOf('.');
    if (dotIdx != -1 && dotIdx < fileName.length - 1) {
      return fileName.substring(dotIdx + 1).toLowerCase();
    }
    return '';
  }

  bool get isPdf => fileExtension == 'pdf';
  bool get isExcel => fileExtension == 'xlsx' || fileExtension == 'xls';
  bool get isWord => fileExtension == 'docx' || fileExtension == 'doc';

  /// Whether the document is authored/owned by the given user ID
  bool isOwnedBy(String? userId) {
    if (userId == null || userId.trim().isEmpty) return false;
    final uid = userId.trim();
    return createdBy != null && (createdBy == uid || createdBy!.trim() == uid);
  }

  /// Whether the document is explicitly shared with the given user ID
  bool isSharedWith(String? userId) {
    if (userId == null || userId.trim().isEmpty) return false;
    final uid = userId.trim();
    return sharedWithUserIds.contains(uid);
  }

  /// Whether the document was explicitly shared by the given user ID
  bool isSharedBy(String? userId) {
    if (userId == null || userId.trim().isEmpty) return false;
    final uid = userId.trim();
    return sharedByUserIds.contains(uid);
  }
  bool get isImage =>
      fileExtension == 'png' ||
      fileExtension == 'jpg' ||
      fileExtension == 'jpeg' ||
      fileExtension == 'webp';

  DocumentRecord copyWith({
    String? id,
    String? organizationId,
    String? departmentId,
    String? title,
    String? description,
    String? category,
    String? fileName,
    String? filePath,
    int? fileSize,
    String? fileType,
    String? storageBucket,
    String? actionId,
    String? actionNumber,
    bool clearAction = false,
    String? createdBy,
    String? createdByName,
    bool? isArchived,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? sharedInternalCount,
    int? sharedExternalCount,
    List<String>? sharedWithUserIds,
    List<String>? sharedByUserIds,
    String? sharedByUserName,
    DateTime? sharedAt,
    List<int>? fileBytes,
    bool? isPersisted,
  }) {
    return DocumentRecord(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      departmentId: departmentId ?? this.departmentId,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      fileSize: fileSize ?? this.fileSize,
      fileType: fileType ?? this.fileType,
      storageBucket: storageBucket ?? this.storageBucket,
      actionId: clearAction ? null : (actionId ?? this.actionId),
      actionNumber: clearAction ? null : (actionNumber ?? this.actionNumber),
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sharedInternalCount: sharedInternalCount ?? this.sharedInternalCount,
      sharedExternalCount: sharedExternalCount ?? this.sharedExternalCount,
      sharedWithUserIds: sharedWithUserIds ?? this.sharedWithUserIds,
      sharedByUserIds: sharedByUserIds ?? this.sharedByUserIds,
      sharedByUserName: sharedByUserName ?? this.sharedByUserName,
      sharedAt: sharedAt ?? this.sharedAt,
      fileBytes: fileBytes ?? this.fileBytes,
      isPersisted: isPersisted ?? this.isPersisted,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'organization_id': organizationId,
    'department_id': departmentId,
    'title': title,
    'description': description,
    'category': category,
    'file_name': fileName,
    'file_path': filePath,
    'file_size': fileSize,
    'file_type': fileType,
    'storage_bucket': storageBucket,
    'action_id': actionId,
    'action_number': actionNumber,
    'created_by': createdBy,
    'created_by_name': createdByName,
    'is_archived': isArchived,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'shared_internal_count': sharedInternalCount,
    'shared_external_count': sharedExternalCount,
    'shared_with_user_ids': sharedWithUserIds,
    'shared_by_user_ids': sharedByUserIds,
    'shared_by_user_name': sharedByUserName,
    'shared_at': sharedAt?.toIso8601String(),
    'is_persisted': isPersisted,
  };

  factory DocumentRecord.fromJson(Map<String, dynamic> json) {
    return DocumentRecord(
      id: json['id']?.toString() ?? '',
      organizationId: json['organization_id']?.toString() ?? '',
      departmentId: json['department_id']?.toString(),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      category: json['category']?.toString() ?? DocumentCategory.general,
      fileName: json['file_name']?.toString() ?? '',
      filePath: json['file_path']?.toString() ?? '',
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      fileType: json['file_type']?.toString() ?? 'application/octet-stream',
      storageBucket: json['storage_bucket']?.toString() ?? 'documents',
      actionId: json['action_id']?.toString(),
      actionNumber: json['action_number']?.toString(),
      createdBy: json['created_by']?.toString(),
      createdByName: json['created_by_name']?.toString() ?? '',
      isArchived: json['is_archived'] == true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      sharedInternalCount: (json['shared_internal_count'] as num?)?.toInt() ?? 0,
      sharedExternalCount: (json['shared_external_count'] as num?)?.toInt() ?? 0,
      isPersisted: json['is_persisted'] as bool? ?? true,
      sharedWithUserIds: (json['shared_with_user_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      sharedByUserIds: (json['shared_by_user_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      sharedByUserName: json['shared_by_user_name']?.toString(),
      sharedAt: json['shared_at'] != null
          ? DateTime.tryParse(json['shared_at'].toString())
          : null,
    );
  }
}

/// Internal recipient share record
class DocumentShare {
  const DocumentShare({
    required this.id,
    required this.documentId,
    required this.userId,
    this.userName = '',
    this.userEmail = '',
    required this.organizationId,
    this.permission = 'view',
    this.sharedBy = '',
    this.sharedByName = '',
    required this.createdAt,
  });

  final String id;
  final String documentId;
  final String userId;
  final String userName;
  final String userEmail;
  final String organizationId;
  final String permission; // 'view', 'download', 'edit'
  final String sharedBy;
  final String sharedByName;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'document_id': documentId,
    'user_id': userId,
    'user_name': userName,
    'user_email': userEmail,
    'organization_id': organizationId,
    'permission': permission,
    'shared_by': sharedBy,
    'shared_by_name': sharedByName,
    'created_at': createdAt.toIso8601String(),
  };

  factory DocumentShare.fromJson(Map<String, dynamic> json) {
    return DocumentShare(
      id: json['id']?.toString() ?? '',
      documentId: json['document_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      userName: json['user_name']?.toString() ?? '',
      userEmail: json['user_email']?.toString() ?? '',
      organizationId: json['organization_id']?.toString() ?? '',
      permission: json['permission']?.toString() ?? 'view',
      sharedBy: json['shared_by']?.toString() ?? '',
      sharedByName: json['shared_by_name']?.toString() ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// External recipient token share record
class DocumentExternalToken {
  const DocumentExternalToken({
    required this.id,
    required this.documentId,
    this.externalRecipientId = '',
    this.recipientName = '',
    required this.recipientEmail,
    required this.organizationId,
    required this.tokenHash,
    this.rawToken,
    this.permission = 'view',
    required this.expiresAt,
    this.isRevoked = false,
    this.accessCount = 0,
    this.lastAccessedAt,
    this.createdBy = '',
    required this.createdAt,
  });

  final String id;
  final String documentId;
  final String externalRecipientId;
  final String recipientName;
  final String recipientEmail;
  final String organizationId;
  final String tokenHash;
  final String? rawToken;
  final String permission;
  final DateTime expiresAt;
  final bool isRevoked;
  final int accessCount;
  final DateTime? lastAccessedAt;
  final String createdBy;
  final DateTime createdAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isValid => !isRevoked && !isExpired;

  static String computeHash(String rawToken) {
    final bytes = utf8.encode(rawToken.trim());
    return sha256.convert(bytes).toString();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'document_id': documentId,
    'external_recipient_id': externalRecipientId,
    'recipient_name': recipientName,
    'recipient_email': recipientEmail,
    'organization_id': organizationId,
    'token_hash': tokenHash,
    'raw_token': rawToken,
    'permission': permission,
    'expires_at': expiresAt.toIso8601String(),
    'is_revoked': isRevoked,
    'access_count': accessCount,
    'last_accessed_at': lastAccessedAt?.toIso8601String(),
    'created_by': createdBy,
    'created_at': createdAt.toIso8601String(),
  };

  factory DocumentExternalToken.fromJson(Map<String, dynamic> json) {
    return DocumentExternalToken(
      id: json['id']?.toString() ?? '',
      documentId: json['document_id']?.toString() ?? '',
      externalRecipientId: json['external_recipient_id']?.toString() ?? '',
      recipientName: json['recipient_name']?.toString() ?? '',
      recipientEmail: json['recipient_email']?.toString() ?? '',
      organizationId: json['organization_id']?.toString() ?? '',
      tokenHash: json['token_hash']?.toString() ?? '',
      rawToken: json['raw_token']?.toString(),
      permission: json['permission']?.toString() ?? 'view',
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isRevoked: json['is_revoked'] == true,
      accessCount: (json['access_count'] as num?)?.toInt() ?? 0,
      lastAccessedAt: json['last_accessed_at'] != null
          ? DateTime.tryParse(json['last_accessed_at'].toString())
          : null,
      createdBy: json['created_by']?.toString() ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
