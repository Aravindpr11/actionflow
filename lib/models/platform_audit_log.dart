/// Immutable platform audit log entry for the ActionFlow Platform Owner portal.
///
/// Maps to a row in `public.platform_audit_logs`.
/// Fields [action], [organizationName], [ipAddress], [userAgent] and [details]
/// are convenience accessors / optional fields that may be populated from the DB
/// or derived from [metadata].
class PlatformAuditLog {
  final String id;
  final DateTime createdAt;
  final String eventType;

  /// Human-readable action label (defaults to [eventType] if not explicitly set).
  final String action;

  final String
  category; // 'governance' | 'security' | 'tenancy' | 'configuration'
  final String severity; // 'info' | 'warning' | 'error' | 'critical'
  final String? actorId;
  final String? actorEmail;
  final String? organizationId;
  final String? organizationName;
  final String? organizationCode;
  final String? targetType;
  final String? targetId;
  final String description;
  final String? ipAddress;
  final String? userAgent;

  /// Raw metadata / details map stored in JSONB.
  final Map<String, dynamic> details;

  const PlatformAuditLog({
    required this.id,
    required this.createdAt,
    required this.eventType,
    String? action,
    this.category = 'governance',
    this.severity = 'info',
    this.actorId,
    this.actorEmail,
    this.organizationId,
    this.organizationName,
    this.organizationCode,
    this.targetType,
    this.targetId,
    required this.description,
    this.ipAddress,
    this.userAgent,
    this.details = const {},
  }) : action = action ?? eventType;

  factory PlatformAuditLog.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'] is Map
        ? Map<String, dynamic>.from(json['metadata'] as Map)
        : <String, dynamic>{};

    return PlatformAuditLog(
      id: json['id']?.toString() ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      eventType: json['event_type']?.toString() ?? 'unknown_event',
      action: json['action']?.toString(),
      category: json['category']?.toString() ?? 'governance',
      severity: json['severity']?.toString() ?? 'info',
      actorId: json['actor_id']?.toString(),
      actorEmail: json['actor_email']?.toString(),
      organizationId: json['organization_id']?.toString(),
      organizationName:
          json['organization_name']?.toString() ??
          metadata['organization_name']?.toString() ??
          metadata['name']?.toString(),
      organizationCode:
          json['organization_code']?.toString() ??
          metadata['organization_code']?.toString() ??
          metadata['code']?.toString(),
      targetType: json['target_type']?.toString(),
      targetId: json['target_id']?.toString(),
      description: json['description']?.toString() ?? '',
      ipAddress: json['ip_address']?.toString(),
      userAgent: json['user_agent']?.toString(),
      details: metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
      'event_type': eventType,
      'action': action,
      'category': category,
      'severity': severity,
      'actor_id': actorId,
      'actor_email': actorEmail,
      'organization_id': organizationId,
      'organization_name': organizationName,
      'organization_code': organizationCode,
      'target_type': targetType,
      'target_id': targetId,
      'description': description,
      'ip_address': ipAddress,
      'user_agent': userAgent,
      'metadata': details,
    };
  }

  /// Whether this audit record corresponds to a deleted tenant.
  bool get isDeletedTenant {
    return (organizationName != null &&
            organizationName!.trim().isNotEmpty &&
            organizationId == null) ||
        details['is_deleted'] == true ||
        eventType == 'organization_deleted';
  }

  /// Human-readable display string for the associated organization.
  /// If the tenant was deleted, displays `<Company Name> (Deleted)`.
  String get displayOrganization {
    final name = organizationName?.trim();
    if (name != null && name.isNotEmpty) {
      if (isDeletedTenant) {
        if (name.toLowerCase().endsWith('(deleted)')) return name;
        return '$name (Deleted)';
      }
      return name;
    }
    if (organizationId != null && organizationId!.trim().isNotEmpty) {
      return organizationId!;
    }
    return 'Global';
  }
}
