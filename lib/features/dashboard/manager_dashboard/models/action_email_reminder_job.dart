class ActionEmailReminderJob {
  const ActionEmailReminderJob({
    required this.id,
    required this.organizationId,
    required this.actionId,
    this.reminderGroupId,
    this.recipientType = 'internal',
    this.profileId,
    this.externalRecipientId,
    required this.recipientName,
    required this.recipientEmail,
    this.reminderType = 'pending_action',
    required this.emailSubject,
    required this.emailBody,
    this.scheduledAt,
    this.status = 'pending',
    this.sentAt,
    this.failureReason,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.claimedAt,
    this.claimedBy,
    this.attemptCount = 0,
    this.maxAttempts = 3,
    this.nextRetryAt,
    this.lastAttemptAt,
    this.isRetryable = true,
    this.idempotencyKey,
  });

  final String id;
  final String organizationId;
  final String actionId;
  final String? reminderGroupId;
  final String recipientType; // 'internal' or 'external'
  final String? profileId;
  final String? externalRecipientId;
  final String recipientName;
  final String recipientEmail;
  final String reminderType; // 'pending_action', 'follow_up', 'due_date', 'overdue', 'review_ready'
  final String emailSubject;
  final String emailBody;
  final DateTime? scheduledAt;
  final String status; // 'pending', 'processing', 'sent', 'failed', 'cancelled'
  final DateTime? sentAt;
  final String? failureReason;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Safe recovery lease & bounded retry metadata
  final DateTime? claimedAt;
  final String? claimedBy;
  final int attemptCount;
  final int maxAttempts;
  final DateTime? nextRetryAt;
  final DateTime? lastAttemptAt;
  final bool isRetryable;
  final String? idempotencyKey;

  bool get isPending => status == 'pending';
  bool get isProcessing => status == 'processing';
  bool get isSent => status == 'sent';
  bool get isFailed => status == 'failed';
  bool get isCancelled => status == 'cancelled';

  bool get isExternal => recipientType == 'external';
  bool get isInternal => recipientType == 'internal';

  /// Evaluates whether an active lease in 'processing' status has become stale (> leaseSeconds)
  bool isClaimStale({int leaseSeconds = 600, DateTime? now}) {
    if (status != 'processing') return false;
    final currentTime = now ?? DateTime.now();
    final claimTime = claimedAt ?? updatedAt ?? createdAt;
    if (claimTime == null) return true;
    return currentTime.difference(claimTime).inSeconds >= leaseSeconds;
  }

  /// Determines whether this reminder is eligible for worker claim / recovery
  bool isEligibleForClaim({DateTime? now, int leaseSeconds = 600}) {
    if (isSent || isCancelled) return false;
    if (attemptCount >= maxAttempts) return false;

    final currentTime = now ?? DateTime.now();
    if (scheduledAt != null && scheduledAt!.isAfter(currentTime)) {
      return false; // Future reminder cannot be claimed
    }

    if (isPending) {
      if (nextRetryAt != null && nextRetryAt!.isAfter(currentTime)) {
        return false; // Retry backoff delay has not elapsed
      }
      return true;
    }

    if (isProcessing) {
      return isClaimStale(leaseSeconds: leaseSeconds, now: currentTime);
    }

    return false;
  }

  ActionEmailReminderJob copyWith({
    String? id,
    String? organizationId,
    String? actionId,
    String? reminderGroupId,
    String? recipientType,
    String? profileId,
    String? externalRecipientId,
    String? recipientName,
    String? recipientEmail,
    String? reminderType,
    String? emailSubject,
    String? emailBody,
    DateTime? scheduledAt,
    String? status,
    DateTime? sentAt,
    String? failureReason,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? claimedAt,
    String? claimedBy,
    int? attemptCount,
    int? maxAttempts,
    DateTime? nextRetryAt,
    bool clearNextRetryAt = false,
    DateTime? lastAttemptAt,
    bool? isRetryable,
    String? idempotencyKey,
  }) {
    return ActionEmailReminderJob(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      actionId: actionId ?? this.actionId,
      reminderGroupId: reminderGroupId ?? this.reminderGroupId,
      recipientType: recipientType ?? this.recipientType,
      profileId: profileId ?? this.profileId,
      externalRecipientId: externalRecipientId ?? this.externalRecipientId,
      recipientName: recipientName ?? this.recipientName,
      recipientEmail: recipientEmail ?? this.recipientEmail,
      reminderType: reminderType ?? this.reminderType,
      emailSubject: emailSubject ?? this.emailSubject,
      emailBody: emailBody ?? this.emailBody,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      status: status ?? this.status,
      sentAt: sentAt ?? this.sentAt,
      failureReason: failureReason ?? this.failureReason,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      claimedAt: claimedAt ?? this.claimedAt,
      claimedBy: claimedBy ?? this.claimedBy,
      attemptCount: attemptCount ?? this.attemptCount,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      nextRetryAt: clearNextRetryAt ? null : (nextRetryAt ?? this.nextRetryAt),
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      isRetryable: isRetryable ?? this.isRetryable,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'organization_id': organizationId,
    'action_id': actionId,
    'reminder_group_id': reminderGroupId,
    'recipient_type': recipientType,
    'profile_id': profileId,
    'external_recipient_id': externalRecipientId,
    'recipient_name': recipientName,
    'recipient_email': recipientEmail,
    'reminder_type': reminderType,
    'email_subject': emailSubject,
    'email_body': emailBody,
    'scheduled_at': scheduledAt?.toIso8601String(),
    'status': status,
    'sent_at': sentAt?.toIso8601String(),
    'failure_reason': failureReason,
    'created_by': createdBy,
    'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
    'claimed_at': claimedAt?.toIso8601String(),
    'claimed_by': claimedBy,
    'attempt_count': attemptCount,
    'max_attempts': maxAttempts,
    'next_retry_at': nextRetryAt?.toIso8601String(),
    'last_attempt_at': lastAttemptAt?.toIso8601String(),
    'is_retryable': isRetryable,
    'idempotency_key': idempotencyKey,
  };

  factory ActionEmailReminderJob.fromJson(Map<String, dynamic> json) {
    return ActionEmailReminderJob(
      id: (json['id'] as String?) ?? '',
      organizationId: (json['organization_id'] as String?) ?? '',
      actionId: (json['action_id'] as String?) ?? '',
      reminderGroupId: json['reminder_group_id'] as String?,
      recipientType: (json['recipient_type'] as String?) ??
          ((json['external_recipient_id'] != null) ? 'external' : 'internal'),
      profileId: json['profile_id'] as String?,
      externalRecipientId: json['external_recipient_id'] as String?,
      recipientName: (json['recipient_name'] as String?) ?? '',
      recipientEmail: (json['recipient_email'] as String?) ?? '',
      reminderType: (json['reminder_type'] as String?) ?? 'pending_action',
      emailSubject: (json['email_subject'] as String?) ?? '',
      emailBody: (json['email_body'] as String?) ?? '',
      scheduledAt: json['scheduled_at'] != null
          ? DateTime.tryParse(json['scheduled_at'].toString())
          : null,
      status: (json['status'] as String?) ?? 'pending',
      sentAt: json['sent_at'] != null
          ? DateTime.tryParse(json['sent_at'].toString())
          : null,
      failureReason: json['failure_reason'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
      claimedAt: json['claimed_at'] != null
          ? DateTime.tryParse(json['claimed_at'].toString())
          : null,
      claimedBy: json['claimed_by'] as String?,
      attemptCount: (json['attempt_count'] as num?)?.toInt() ?? 0,
      maxAttempts: (json['max_attempts'] as num?)?.toInt() ?? 3,
      nextRetryAt: json['next_retry_at'] != null
          ? DateTime.tryParse(json['next_retry_at'].toString())
          : null,
      lastAttemptAt: json['last_attempt_at'] != null
          ? DateTime.tryParse(json['last_attempt_at'].toString())
          : null,
      isRetryable: (json['is_retryable'] as bool?) ?? true,
      idempotencyKey: json['idempotency_key'] as String?,
    );
  }
}
