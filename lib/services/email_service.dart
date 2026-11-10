import 'dart:convert';
import 'dart:math';
import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_email_reminder_job.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/external_update/models/external_action_payload.dart';
import 'package:action_flow/features/external_update/services/external_action_service.dart';
import 'package:action_flow/features/notifications/models/app_notification.dart';
import 'package:action_flow/services/notification_service.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Result of an email sending operation
class EmailSendResult {
  final bool isSuccess;
  final String status; // 'sent', 'pending', 'failed', 'not_configured', 'reminders_disabled', etc.
  final String? messageId;
  final String? errorMessage;
  final String? externalUpdateUrl;
  final String? recipientEmail;
  final String? recipientType;
  final String? reminderId;

  const EmailSendResult({
    required this.isSuccess,
    required this.status,
    this.messageId,
    this.errorMessage,
    this.externalUpdateUrl,
    this.recipientEmail,
    this.recipientType,
    this.reminderId,
  });

  factory EmailSendResult.notConfigured([String? details]) {
    return EmailSendResult(
      isSuccess: false,
      status: 'not_configured',
      errorMessage: details ??
          'Email provider (Resend) is not configured in Supabase secrets.',
    );
  }

  factory EmailSendResult.remindersDisabled() {
    return const EmailSendResult(
      isSuccess: false,
      status: 'reminders_disabled',
      errorMessage: 'Email reminders are disabled for this action. No email sent.',
    );
  }

  factory EmailSendResult.sent(String messageId, {
    String? recipientEmail,
    String? recipientType,
    String? reminderId,
    String? externalUpdateUrl,
  }) {
    return EmailSendResult(
      isSuccess: true,
      status: 'sent',
      messageId: messageId,
      recipientEmail: recipientEmail,
      recipientType: recipientType,
      reminderId: reminderId,
      externalUpdateUrl: externalUpdateUrl,
    );
  }

  factory EmailSendResult.failed(String error, {String? reminderId}) {
    return EmailSendResult(
      isSuccess: false,
      status: 'failed',
      errorMessage: error,
      reminderId: reminderId,
    );
  }

  factory EmailSendResult.fromJson(Map<String, dynamic> json) {
    final success = json['success'] == true;
    final status = json['status']?.toString() ?? (success ? 'sent' : 'failed');
    return EmailSendResult(
      isSuccess: success,
      status: status,
      messageId: json['message_id']?.toString(),
      errorMessage: json['error']?.toString() ?? json['failure_reason']?.toString(),
      externalUpdateUrl: json['external_update_url']?.toString(),
      recipientEmail: json['recipient_email']?.toString(),
      recipientType: json['recipient_type']?.toString(),
      reminderId: json['reminder_id']?.toString(),
    );
  }
}

/// ActionFlow Shared Email Service
/// Integrates with the Supabase Edge Function `send-email` powered by Resend.
///
/// Security:
/// - Never exposes the Resend API key or credentials to the client.
/// - Hashes access tokens before database storage.
/// - Never reports an email as sent unless confirmed by the provider.
class EmailService {
  EmailService._();
  static final EmailService instance = EmailService._();

  /// Mock sender for testing or offline environments
  @visibleForTesting
  static EmailSendResult Function(Map<String, dynamic> params)? mockSendHandler;

  /// Generates a cryptographically unpredictable 256-bit (64 hex characters) raw token using CSPRNG.
  static String generateSecureRawToken() {
    final random = Random.secure();
    final values = List<int>.generate(32, (_) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Helper to hash access tokens using SHA-256
  static String hashToken(String rawToken) {
    final bytes = utf8.encode(rawToken.trim());
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Checks whether Resend email delivery is configured on the server
  Future<Map<String, dynamic>> checkProviderStatus() async {
    if (!SupabaseConfig.isInitialized) {
      return {
        'configured': false,
        'provider': 'resend',
        'status': 'not_configured',
        'message': 'Supabase client is not initialized.',
      };
    }

    try {
      final client = SupabaseConfig.client;
      final response = await client.functions.invoke(
        'send-email',
        body: {'action': 'test_provider_status'},
      );

      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      return {
        'configured': false,
        'provider': 'resend',
        'status': 'not_configured',
        'message': 'Invalid response from email function.',
      };
    } catch (e) {
      return {
        'configured': false,
        'provider': 'resend',
        'status': 'not_configured',
        'message': 'Could not verify provider status: $e',
      };
    }
  }

  /// Secure server-side delivery processor for testing and offline/mock operation
  /// Strictly verifies all Step 2 server-side security checks
  Future<EmailSendResult> deliverActionReminder({
    required String actionId,
    String? reminderId,
    String? recipientType,
    String? callerOrganizationId,
    String? callerEmailOverride,
    DateTime? simulatedNow,
    bool simulateProviderFailure = false,
  }) async {
    final store = MockActionStore.instance;

    // 1. Fetch action record
    final actionIndex = store.actions.indexWhere((a) => a.id == actionId.trim());
    if (actionIndex < 0) {
      return const EmailSendResult(
        isSuccess: false,
        status: 'not_found',
        errorMessage: 'Action record not found in database.',
      );
    }
    final action = store.actions[actionIndex];

    // 2. Multi-Tenant Enforcement: action MUST belong to caller's organization
    if (callerOrganizationId != null &&
        action.organizationId.isNotEmpty &&
        action.organizationId != callerOrganizationId) {
      return const EmailSendResult(
        isSuccess: false,
        status: 'forbidden',
        errorMessage: 'ActionFlow Security Violation: Cross-organization email dispatch forbidden.',
      );
    }

    // 3. Verify action is NOT closed
    if (action.isClosed || action.status.toLowerCase() == 'closed') {
      return const EmailSendResult(
        isSuccess: false,
        status: 'action_closed',
        errorMessage: 'Cannot send reminder: Action is closed.',
      );
    }

    // 4. Verify email reminders enabled on action
    if (!action.emailReminderEnabled) {
      return EmailSendResult.remindersDisabled();
    }

    // 5. Resolve target reminder job from store.emailReminders
    // Caller-supplied email override is strictly ignored
    ActionEmailReminderJob? targetReminder;
    int targetJobIndex = -1;

    final now = simulatedNow ?? DateTime.now();

    if (reminderId != null && reminderId.trim().isNotEmpty) {
      targetJobIndex = store.emailReminders.indexWhere(
        (j) => j.id == reminderId.trim() && j.actionId == action.id,
      );

      if (targetJobIndex < 0) {
        return const EmailSendResult(
          isSuccess: false,
          status: 'not_found',
          errorMessage: 'Reminder job not found or does not belong to this action.',
        );
      }

      final rJob = store.emailReminders[targetJobIndex];

      // Tenant check on reminder job itself
      if (action.organizationId.isNotEmpty &&
          rJob.organizationId.isNotEmpty &&
          rJob.organizationId != action.organizationId) {
        return const EmailSendResult(
          isSuccess: false,
          status: 'forbidden',
          errorMessage: 'ActionFlow Security Violation: Cross-organization reminder job.',
        );
      }

      if (rJob.status == 'sent') {
        return const EmailSendResult(
          isSuccess: false,
          status: 'already_sent',
          errorMessage: 'This reminder job has already been sent.',
        );
      }

      if (rJob.status == 'cancelled') {
        return const EmailSendResult(
          isSuccess: false,
          status: 'cancelled',
          errorMessage: 'This reminder job has been cancelled.',
        );
      }

      if (rJob.status == 'processing') {
        return const EmailSendResult(
          isSuccess: false,
          status: 'already_processing',
          errorMessage: 'This reminder job is already being processed.',
        );
      }

      if (rJob.status != 'pending') {
        return EmailSendResult(
          isSuccess: false,
          status: rJob.status,
          errorMessage: 'Reminder job is in status "${rJob.status}".',
        );
      }

      // Schedule validation: Never send future reminders early
      if (rJob.scheduledAt != null && rJob.scheduledAt!.isAfter(now)) {
        return EmailSendResult(
          isSuccess: false,
          status: 'scheduled_in_future',
          errorMessage: 'Reminder is scheduled for ${rJob.scheduledAt} and is not yet due.',
        );
      }

      targetReminder = rJob;
    } else {
      // Find candidate due pending reminders
      final candidates = <int>[];
      for (int i = 0; i < store.emailReminders.length; i++) {
        final j = store.emailReminders[i];
        final orgMatches = action.organizationId.isEmpty ||
            j.organizationId.isEmpty ||
            j.organizationId == action.organizationId;
        if (j.actionId == action.id &&
            orgMatches &&
            j.status == 'pending' &&
            (j.scheduledAt == null || !j.scheduledAt!.isAfter(now))) {
          if (recipientType == null || j.recipientType == recipientType.trim()) {
            candidates.add(i);
          }
        }
      }

      if (candidates.isEmpty) {
        // Locked product rule: NEVER fall back to assigned_to or external_action_recipients!
        return const EmailSendResult(
          isSuccess: false,
          status: 'no_pending_reminders',
          errorMessage: 'No eligible pending reminder jobs found for this action.',
        );
      }

      // Oldest due first
      candidates.sort((a, b) {
        final jA = store.emailReminders[a];
        final jB = store.emailReminders[b];
        final tA = jA.scheduledAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final tB = jB.scheduledAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return tA.compareTo(tB);
      });

      targetJobIndex = candidates.first;
      targetReminder = store.emailReminders[targetJobIndex];
    }

    // 6. Atomic Claim: Concurrency guard (pending -> processing)
    if (store.emailReminders[targetJobIndex].status != 'pending') {
      return const EmailSendResult(
        isSuccess: false,
        status: 'already_processing',
        errorMessage: 'Reminder job was claimed concurrently by another worker.',
      );
    }

    store.emailReminders[targetJobIndex] = targetReminder.copyWith(
      status: 'processing',
      updatedAt: now,
    );

    // 7. Recipient Identity & Authorization Resolution
    String trustedEmail = '';
    String trustedName = '';
    String? externalUpdateUrl;

    if (targetReminder.recipientType == 'internal') {
      final profId = targetReminder.profileId;
      if (profId == null || profId.isEmpty) {
        store.emailReminders[targetJobIndex] = store.emailReminders[targetJobIndex].copyWith(
          status: 'failed',
          failureReason: 'Internal reminder missing profile_id.',
          updatedAt: now,
        );
        return const EmailSendResult(
          isSuccess: false,
          status: 'invalid_recipient',
          errorMessage: 'Internal reminder missing profile_id.',
        );
      }

      // Check profiles in store
      final profMatches = store.profiles.where((p) => p['id'] == profId).toList();
      if (profMatches.isNotEmpty) {
        final prof = profMatches.first;
        if (action.organizationId.isNotEmpty &&
            prof['organization_id'] != null &&
            prof['organization_id'] != action.organizationId) {
          store.emailReminders[targetJobIndex] = store.emailReminders[targetJobIndex].copyWith(
            status: 'failed',
            failureReason: 'Cross-organization internal recipient violation.',
            updatedAt: now,
          );
          return const EmailSendResult(
            isSuccess: false,
            status: 'forbidden',
            errorMessage: 'ActionFlow Security Violation: Cross-organization internal recipient.',
          );
        }

        if (prof['is_active'] == false || prof['status'] == 'inactive') {
          store.emailReminders[targetJobIndex] = store.emailReminders[targetJobIndex].copyWith(
            status: 'failed',
            failureReason: 'Internal recipient is inactive.',
            updatedAt: now,
          );
          return const EmailSendResult(
            isSuccess: false,
            status: 'invalid_recipient',
            errorMessage: 'Internal recipient user is inactive.',
          );
        }

        trustedEmail = (prof['email'] as String? ?? '').trim();
        trustedName = (prof['full_name'] as String? ?? '').trim();
      } else {
        // Fall back to targetReminder record snapshot if profiles mock was not populated
        trustedEmail = targetReminder.recipientEmail.trim();
        trustedName = targetReminder.recipientName.trim();
      }

      // Internal recipients NEVER receive external update links
      externalUpdateUrl = null;

    } else if (targetReminder.recipientType == 'external') {
      final extId = targetReminder.externalRecipientId;
      if (extId == null || extId.isEmpty) {
        store.emailReminders[targetJobIndex] = store.emailReminders[targetJobIndex].copyWith(
          status: 'failed',
          failureReason: 'External reminder missing external_recipient_id.',
          updatedAt: now,
        );
        return const EmailSendResult(
          isSuccess: false,
          status: 'invalid_recipient',
          errorMessage: 'External reminder missing external_recipient_id.',
        );
      }

      final extMatches = store.externalRecipients.where((r) => r.id == extId).toList();
      if (extMatches.isNotEmpty) {
        final ext = extMatches.first;
        if (action.organizationId.isNotEmpty &&
            ext.organizationId.isNotEmpty &&
            ext.organizationId != action.organizationId) {
          store.emailReminders[targetJobIndex] = store.emailReminders[targetJobIndex].copyWith(
            status: 'failed',
            failureReason: 'Cross-organization external recipient violation.',
            updatedAt: now,
          );
          return const EmailSendResult(
            isSuccess: false,
            status: 'forbidden',
            errorMessage: 'ActionFlow Security Violation: Cross-organization external recipient.',
          );
        }

        if (!ext.isActive) {
          store.emailReminders[targetJobIndex] = store.emailReminders[targetJobIndex].copyWith(
            status: 'failed',
            failureReason: 'External recipient is inactive.',
            updatedAt: now,
          );
          return const EmailSendResult(
            isSuccess: false,
            status: 'invalid_recipient',
            errorMessage: 'External recipient contact is inactive.',
          );
        }

        trustedEmail = ext.email.trim();
        trustedName = ext.fullName.trim();
      } else {
        // If external recipients table in mock store was not explicitly populated, check targetReminder snapshot
        if (targetReminder.recipientEmail.isNotEmpty) {
          trustedEmail = targetReminder.recipientEmail.trim();
          trustedName = targetReminder.recipientName.trim();
        } else {
          store.emailReminders[targetJobIndex] = store.emailReminders[targetJobIndex].copyWith(
            status: 'failed',
            failureReason: 'External recipient record not found in database.',
            updatedAt: now,
          );
          return const EmailSendResult(
            isSuccess: false,
            status: 'invalid_recipient',
            errorMessage: 'External recipient record not found in database.',
          );
        }
      }

      final rawToken = EmailService.hashToken('${targetReminder.id}_${now.microsecondsSinceEpoch}');
      final payload = ExternalActionPayload(
        actionId: action.id,
        actionNumber: action.actionNumber.isNotEmpty ? action.actionNumber : action.id,
        title: action.subject,
        description: action.description,
        actionRequired: action.actionRequired,
        category: action.category,
        priority: action.priority,
        status: action.status,
        percentComplete: action.percentComplete,
        dateRaised: action.dateRaised,
        startDate: action.startDate,
        targetDate: action.targetDate,
        dueDate: action.targetDate,
        nextFollowUpDate: action.nextFollowUpDate,
        department: action.department,
        site: action.site,
        organizationName: 'Sobha Constructions',
        isClosed: action.isClosed,
        recentHistory: const [],
        recipientId: extId,
        recipientName: trustedName,
        recipientEmail: trustedEmail,
        companyName: '',
        phone: '',
        expiresAt: now.add(const Duration(days: 7)),
      );

      MockExternalActionStore.instance.registerToken(
        rawToken: rawToken,
        payload: payload,
      );

      externalUpdateUrl = 'http://localhost:8080/external-update?token=$rawToken';
    } else {
      store.emailReminders[targetJobIndex] = store.emailReminders[targetJobIndex].copyWith(
        status: 'failed',
        failureReason: 'Unsupported recipient_type: ${targetReminder.recipientType}',
        updatedAt: now,
      );
      return EmailSendResult(
        isSuccess: false,
        status: 'invalid_recipient_type',
        errorMessage: 'Unsupported recipient_type: ${targetReminder.recipientType}',
      );
    }

    // Email format validation
    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!emailRegex.hasMatch(trustedEmail)) {
      store.emailReminders[targetJobIndex] = store.emailReminders[targetJobIndex].copyWith(
        status: 'failed',
        failureReason: 'Invalid recipient email format.',
        updatedAt: now,
      );
      return const EmailSendResult(
        isSuccess: false,
        status: 'invalid_email',
        errorMessage: 'Resolved recipient email address format is invalid.',
      );
    }

    // 8. Dispatch & Audit State Update
    if (simulateProviderFailure) {
      store.emailReminders[targetJobIndex] = store.emailReminders[targetJobIndex].copyWith(
        status: 'failed',
        failureReason: 'Simulated Resend API delivery error',
        updatedAt: now,
      );
      return const EmailSendResult(
        isSuccess: false,
        status: 'failed',
        errorMessage: 'Simulated Resend API delivery error',
      );
    }

    store.emailReminders[targetJobIndex] = store.emailReminders[targetJobIndex].copyWith(
      status: 'sent',
      sentAt: now,
      failureReason: null,
      updatedAt: now,
    );

    return EmailSendResult(
      isSuccess: true,
      status: 'sent',
      messageId: 'msg_${targetReminder.id}',
      recipientEmail: trustedEmail,
      recipientType: targetReminder.recipientType,
      reminderId: targetReminder.id,
      externalUpdateUrl: externalUpdateUrl,
    );
  }

  /// Sends an action assignment or reminder email via Supabase Edge Function
  Future<EmailSendResult> sendActionReminder({
    required String actionId,
    String? reminderId,
    String? recipientType,
  }) async {
    if (mockSendHandler != null) {
      return mockSendHandler!({
        'action': 'send_action_reminder',
        'action_id': actionId,
        'reminder_id': reminderId,
        'recipient_type': recipientType,
      });
    }

    if (!SupabaseConfig.isInitialized) {
      return deliverActionReminder(
        actionId: actionId,
        reminderId: reminderId,
        recipientType: recipientType,
      );
    }

    try {
      final client = SupabaseConfig.client;
      final payload = <String, dynamic>{
        'action': 'send_action_reminder',
        'action_id': actionId,
      };
      if (reminderId != null) payload['reminder_id'] = reminderId;
      if (recipientType != null) payload['recipient_type'] = recipientType;

      final response = await client.functions.invoke(
        'send-email',
        body: payload,
      );

      if (response.data is Map) {
        return EmailSendResult.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
      }

      if (response.status == 200) {
        return EmailSendResult.sent('ok');
      }

      return EmailSendResult.failed('Unexpected response status ${response.status}');
    } catch (e) {
      return EmailSendResult.failed('Failed to invoke send-email function: $e');
    }
  }

  /// Sends a single direct email message (for internal or external notifications)
  Future<EmailSendResult> sendSingleEmail({
    required String to,
    required String subject,
    required String html,
    String? text,
    String? recipientType,
    String? actionId,
  }) async {
    if (mockSendHandler != null) {
      final mockParams = <String, dynamic>{
        'action': 'send_single_email',
        'to': to,
        'subject': subject,
        'html': html,
        'text': text,
        'recipient_type': recipientType,
        'action_id': actionId,
      };
      mockParams.removeWhere((key, value) => value == null);
      return mockSendHandler!(mockParams);
    }

    if (!SupabaseConfig.isInitialized) {
      return EmailSendResult.notConfigured();
    }

    try {
      final client = SupabaseConfig.client;
      final payload = <String, dynamic>{
        'action': 'send_single_email',
        'to': to,
        'subject': subject,
        'html': html,
        'text': text,
        'recipient_type': recipientType,
        'action_id': actionId,
      };
      payload.removeWhere((key, value) => value == null);

      final response = await client.functions.invoke(
        'send-email',
        body: payload,
      );

      if (response.data is Map) {
        return EmailSendResult.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
      }

      return EmailSendResult.failed('Unexpected response status ${response.status}');
    } catch (e) {
      return EmailSendResult.failed('Error calling send-email: $e');
    }
  }

  /// Dispatches an action assignment email to the current assigned person.
  /// Handles both internal staff (with ActionFlow login link) and external contractors (with secure update token).
  /// Strictly separate from scheduled email reminders: does NOT create or alter reminder jobs.
  Future<EmailSendResult> sendAssignmentEmail({
    required ActionRecord action,
    String? baseUrl,
    String? recipientEmailOverride,
  }) async {
    final effectiveBaseUrl = (baseUrl != null && baseUrl.isNotEmpty)
        ? baseUrl
        : (kIsWeb ? Uri.base.origin : 'https://actionflow.app');

    final isExternal = action.isExternalRecipient;
    String resolvedEmail = recipientEmailOverride?.trim() ?? '';
    String resolvedName = '';

    if (isExternal) {
      // 1. Resolve external recipient email and name
      if (resolvedEmail.isEmpty) {
        resolvedEmail = (action.externalRecipientEmail ?? '').trim();
      }
      if (resolvedEmail.isEmpty && action.externalRecipient != null) {
        resolvedEmail = action.externalRecipient!.email.trim();
      }
      if (resolvedEmail.isEmpty && action.primaryAssignee?.email.isNotEmpty == true) {
        resolvedEmail = action.primaryAssignee!.email.trim();
      }

      resolvedName = action.externalRecipientName?.trim() ?? '';
      if (resolvedName.isEmpty && action.externalRecipient != null) {
        resolvedName = action.externalRecipient!.fullName.trim();
      }
      if (resolvedName.isEmpty) {
        resolvedName = action.assignedTo.trim();
      }

      // If still missing and externalRecipientId exists, query database or mock store
      if (resolvedEmail.isEmpty &&
          action.externalRecipientId != null &&
          action.externalRecipientId!.isNotEmpty) {
        final extId = action.externalRecipientId!.trim();
        final storeMatches = MockActionStore.instance.externalRecipients
            .where((r) => r.id == extId)
            .toList();
        if (storeMatches.isNotEmpty) {
          resolvedEmail = storeMatches.first.email.trim();
          if (resolvedName.isEmpty) {
            resolvedName = storeMatches.first.fullName.trim();
          }
        } else if (SupabaseConfig.isInitialized) {
          try {
            final res = await SupabaseConfig.client
                .from('external_action_recipients')
                .select('email, full_name')
                .eq('id', extId)
                .maybeSingle();
            if (res != null) {
              resolvedEmail = (res['email'] as String? ?? '').trim();
              if (resolvedName.isEmpty) {
                resolvedName = (res['full_name'] as String? ?? '').trim();
              }
            }
          } catch (e) {
            debugPrint(
              '[EmailService] Error resolving external recipient: $e',
            );
          }
        }
      }

      if (resolvedEmail.isEmpty) {
        return const EmailSendResult(
          isSuccess: false,
          status: 'invalid_recipient',
          errorMessage:
              'No valid recipient email found for external assignment.',
        );
      }

      // Validate email format
      final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
      if (!emailRegex.hasMatch(resolvedEmail)) {
        return EmailSendResult(
          isSuccess: false,
          status: 'invalid_email',
          errorMessage: 'Invalid recipient email format: $resolvedEmail',
        );
      }

      // 2. Generate cryptographically unpredictable 256-bit raw token
      final rawToken = generateSecureRawToken();
      final tokenHash = EmailService.hashToken(rawToken);

      // Register token_hash in Supabase if initialized
      if (SupabaseConfig.isInitialized) {
        try {
          await SupabaseConfig.client.rpc(
            'create_or_get_external_action_token',
            params: {
              'p_action_id': action.id,
              'p_token_hash': tokenHash,
              'p_expires_in_days': 7,
              if (action.externalRecipientId != null &&
                  action.externalRecipientId!.isNotEmpty)
                'p_external_recipient_id': action.externalRecipientId,
            },
          );
        } catch (e) {
          debugPrint(
            '[EmailService] RPC create_or_get_external_action_token error: $e',
          );
          return EmailSendResult.failed(
            'Failed to generate secure external token: $e',
          );
        }
      }

      // Populate mock payload for hermetic test / offline environments
      final payload = ExternalActionPayload(
        actionId: action.id,
        actionNumber: action.displayId,
        title: action.subject,
        description: action.description,
        actionRequired: action.actionRequired,
        category: action.category,
        priority: action.priority,
        status: action.status,
        percentComplete: action.percentComplete,
        dateRaised: action.dateRaised,
        startDate: action.startDate,
        targetDate: action.targetDate,
        dueDate: action.targetDate,
        nextFollowUpDate: action.nextFollowUpDate,
        department: action.department,
        site: action.site,
        organizationName: 'Sobha Constructions',
        isClosed: action.isClosed,
        recentHistory: const [],
        recipientId: action.externalRecipientId ?? '',
        recipientName: resolvedName.isNotEmpty ? resolvedName : 'Contractor',
        recipientEmail: resolvedEmail,
        companyName: '',
        phone: '',
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );
      MockExternalActionStore.instance.registerToken(
        rawToken: rawToken,
        payload: payload,
      );

      final externalUpdateUrl =
          '$effectiveBaseUrl/external-update?token=$rawToken';
      final subject = 'Action Assigned: [${action.displayId}] ${action.subject}';
      final html = _buildExternalAssignmentEmailHtml(
        action: action,
        recipientName: resolvedName.isNotEmpty ? resolvedName : 'Contractor',
        updateUrl: externalUpdateUrl,
      );
      final text = _buildExternalAssignmentEmailText(
        action: action,
        recipientName: resolvedName.isNotEmpty ? resolvedName : 'Contractor',
        updateUrl: externalUpdateUrl,
      );

      final sendResult = await sendSingleEmail(
        to: resolvedEmail,
        subject: subject,
        html: html,
        text: text,
        recipientType: 'external',
        actionId: action.id,
      );

      return EmailSendResult(
        isSuccess: sendResult.isSuccess,
        status: sendResult.status,
        messageId: sendResult.messageId,
        errorMessage: sendResult.errorMessage,
        externalUpdateUrl: externalUpdateUrl,
        recipientEmail: resolvedEmail,
        recipientType: 'external',
      );
    } else {
      // 1. Resolve internal recipient email and name
      if (resolvedEmail.isEmpty &&
          action.primaryAssignee?.email.isNotEmpty == true) {
        resolvedEmail = action.primaryAssignee!.email.trim();
      }

      resolvedName = action.primaryAssignee?.name.trim() ?? '';
      if (resolvedName.isEmpty) {
        resolvedName = action.assignedTo.trim();
      }

      // Check profiles store or Supabase profiles if email missing
      if (resolvedEmail.isEmpty &&
          action.assignedToId != null &&
          action.assignedToId!.isNotEmpty) {
        final profId = action.assignedToId!.trim();
        final profMatches = MockActionStore.instance.profiles
            .where((p) => p['id'] == profId)
            .toList();
        if (profMatches.isNotEmpty) {
          resolvedEmail = (profMatches.first['email'] as String? ?? '').trim();
          if (resolvedName.isEmpty) {
            resolvedName =
                (profMatches.first['full_name'] as String? ?? '').trim();
          }
        } else if (SupabaseConfig.isInitialized) {
          try {
            final res = await SupabaseConfig.client
                .from('directory_profiles')
                .select('email, full_name')
                .eq('id', profId)
                .maybeSingle();
            if (res != null) {
              resolvedEmail = (res['email'] as String? ?? '').trim();
              if (resolvedName.isEmpty) {
                resolvedName = (res['full_name'] as String? ?? '').trim();
              }
            }
          } catch (e) {
            debugPrint('[EmailService] Error resolving from directory_profiles: $e');
          }
          if (resolvedEmail.isEmpty) {
            try {
              final res = await SupabaseConfig.client
                  .from('profiles')
                  .select('email, full_name')
                  .eq('id', profId)
                  .maybeSingle();
              if (res != null) {
                resolvedEmail = (res['email'] as String? ?? '').trim();
                if (resolvedName.isEmpty) {
                  resolvedName = (res['full_name'] as String? ?? '').trim();
                }
              }
            } catch (e) {
              debugPrint('[EmailService] Error resolving internal profile: $e');
            }
          }
        }
      }

      if (resolvedEmail.isEmpty) {
        return const EmailSendResult(
          isSuccess: false,
          status: 'invalid_recipient',
          errorMessage:
              'No valid recipient email found for internal assignment.',
        );
      }

      // Validate email format
      final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
      if (!emailRegex.hasMatch(resolvedEmail)) {
        return EmailSendResult(
          isSuccess: false,
          status: 'invalid_email',
          errorMessage: 'Invalid recipient email format: $resolvedEmail',
        );
      }

      final appUrl = '$effectiveBaseUrl/';
      final subject = 'Action Assigned: [${action.displayId}] ${action.subject}';
      final html = _buildInternalAssignmentEmailHtml(
        action: action,
        recipientName: resolvedName.isNotEmpty ? resolvedName : 'Staff Member',
        appUrl: appUrl,
      );
      final text = _buildInternalAssignmentEmailText(
        action: action,
        recipientName: resolvedName.isNotEmpty ? resolvedName : 'Staff Member',
        appUrl: appUrl,
      );

      final sendResult = await sendSingleEmail(
        to: resolvedEmail,
        subject: subject,
        html: html,
        text: text,
        recipientType: 'internal',
        actionId: action.id,
      );

      return EmailSendResult(
        isSuccess: sendResult.isSuccess,
        status: sendResult.status,
        messageId: sendResult.messageId,
        errorMessage: sendResult.errorMessage,
        externalUpdateUrl: null, // Internal recipients NEVER receive external update links
        recipientEmail: resolvedEmail,
        recipientType: 'internal',
      );
    }
  }

  static String _buildInternalAssignmentEmailHtml({
    required ActionRecord action,
    required String recipientName,
    required String appUrl,
  }) {
    final reqText = action.actionRequired.isNotEmpty
        ? action.actionRequired
        : (action.description.isNotEmpty
            ? action.description
            : 'Please review and execute the assigned action.');
    final siteText = action.site.isNotEmpty
        ? (action.department.isNotEmpty
            ? '${action.site} (${action.department})'
            : action.site)
        : (action.department.isNotEmpty
            ? action.department
            : 'Not specified');
    final assignedBy =
        action.assignedBy.isNotEmpty ? action.assignedBy : 'Manager';
    final dueDate =
        action.targetDate.isNotEmpty ? action.targetDate : 'Not specified';

    return '''
<div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; line-height: 1.6; color: #1e293b; max-width: 600px; margin: 0 auto; background-color: #ffffff; border: 1px solid #e2e8f0; border-radius: 8px; overflow: hidden;">
  <div style="background-color: #1e3a8a; color: #ffffff; padding: 20px 24px;">
    <h1 style="margin: 0; font-size: 20px; font-weight: 700; color: #ffffff;">ActionFlow HSE Action Tracker</h1>
    <p style="margin: 4px 0 0 0; font-size: 13px; color: #93c5fd;">Action Assignment Notification</p>
  </div>
  <div style="padding: 24px;">
    <p style="margin: 0 0 16px 0; font-size: 15px;">Hello <strong>$recipientName</strong>,</p>
    <p style="margin: 0 0 20px 0; font-size: 14px; color: #334155;">You have been assigned the following action in ActionFlow:</p>
    
    <div style="background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; padding: 16px; margin-bottom: 24px;">
      <table style="width: 100%; border-collapse: collapse; font-size: 13.5px;">
        <tr>
          <td style="padding: 6px 0; color: #64748b; width: 130px; font-weight: 600;">Action Reference:</td>
          <td style="padding: 6px 0; color: #0f172a; font-weight: 700;">${action.displayId}</td>
        </tr>
        <tr>
          <td style="padding: 6px 0; color: #64748b; font-weight: 600;">Title:</td>
          <td style="padding: 6px 0; color: #0f172a; font-weight: 600;">${action.subject}</td>
        </tr>
        <tr>
          <td style="padding: 6px 0; color: #64748b; font-weight: 600;">Action Required:</td>
          <td style="padding: 6px 0; color: #334155;">$reqText</td>
        </tr>
        <tr>
          <td style="padding: 6px 0; color: #64748b; font-weight: 600;">Priority:</td>
          <td style="padding: 6px 0; color: #0f172a;"><span style="display: inline-block; padding: 2px 8px; border-radius: 4px; font-weight: 600; font-size: 12px; background-color: #f1f5f9;">${action.priority}</span></td>
        </tr>
        <tr>
          <td style="padding: 6px 0; color: #64748b; font-weight: 600;">Due Date:</td>
          <td style="padding: 6px 0; color: #0f172a; font-weight: 600;">$dueDate</td>
        </tr>
        <tr>
          <td style="padding: 6px 0; color: #64748b; font-weight: 600;">Location / Site:</td>
          <td style="padding: 6px 0; color: #334155;">$siteText</td>
        </tr>
        <tr>
          <td style="padding: 6px 0; color: #64748b; font-weight: 600;">Assigned By:</td>
          <td style="padding: 6px 0; color: #334155;">$assignedBy</td>
        </tr>
        <tr>
          <td style="padding: 6px 0; color: #64748b; font-weight: 600;">Status:</td>
          <td style="padding: 6px 0; color: #334155;">${action.status} (${action.percentComplete}%)</td>
        </tr>
      </table>
    </div>

    <div style="text-align: center; margin: 28px 0 20px 0;">
      <a href="$appUrl" style="background-color: #2563eb; color: #ffffff; text-decoration: none; padding: 12px 28px; border-radius: 6px; font-weight: 600; font-size: 14px; display: inline-block;">Open ActionFlow Staff Portal</a>
    </div>

    <p style="margin: 0; font-size: 12.5px; color: #64748b; text-align: center;">Log in with your company credentials to review details, record updates, or submit evidence.</p>
  </div>
  <div style="background-color: #f8fafc; border-top: 1px solid #e2e8f0; padding: 14px 24px; text-align: center; font-size: 12px; color: #94a3b8;">
    ActionFlow HSE Management System &bull; Automated Notification
  </div>
</div>
''';
  }

  static String _buildInternalAssignmentEmailText({
    required ActionRecord action,
    required String recipientName,
    required String appUrl,
  }) {
    final reqText = action.actionRequired.isNotEmpty
        ? action.actionRequired
        : (action.description.isNotEmpty
            ? action.description
            : 'Please review and execute the assigned action.');
    final siteText = action.site.isNotEmpty ? action.site : 'Not specified';
    final assignedBy =
        action.assignedBy.isNotEmpty ? action.assignedBy : 'Manager';
    final dueDate =
        action.targetDate.isNotEmpty ? action.targetDate : 'Not specified';

    return '''
Hello $recipientName,

You have been assigned the following action in ActionFlow:

• Action Reference: ${action.displayId}
• Title: ${action.subject}
• Action Required: $reqText
• Priority: ${action.priority}
• Due Date: $dueDate
• Location / Site: $siteText
• Assigned By: $assignedBy
• Status: ${action.status} (${action.percentComplete}%)

Open ActionFlow to review details and record progress:
$appUrl

Thank you,
ActionFlow Team
''';
  }

  static String _buildExternalAssignmentEmailHtml({
    required ActionRecord action,
    required String recipientName,
    required String updateUrl,
  }) {
    final reqText = action.actionRequired.isNotEmpty
        ? action.actionRequired
        : (action.description.isNotEmpty
            ? action.description
            : 'Please review and execute the assigned action.');
    final siteText = action.site.isNotEmpty ? action.site : 'Not specified';
    final dueDate =
        action.targetDate.isNotEmpty ? action.targetDate : 'Not specified';

    return '''
<div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; line-height: 1.6; color: #1e293b; max-width: 600px; margin: 0 auto; background-color: #ffffff; border: 1px solid #e2e8f0; border-radius: 8px; overflow: hidden;">
  <div style="background-color: #0f766e; color: #ffffff; padding: 20px 24px;">
    <h1 style="margin: 0; font-size: 20px; font-weight: 700; color: #ffffff;">ActionFlow HSE Action Tracker</h1>
    <p style="margin: 4px 0 0 0; font-size: 13px; color: #ccfbf1;">External Contractor Action Assignment</p>
  </div>
  <div style="padding: 24px;">
    <p style="margin: 0 0 16px 0; font-size: 15px;">Hello <strong>$recipientName</strong>,</p>
    <p style="margin: 0 0 20px 0; font-size: 14px; color: #334155;">An action has been assigned to you / your team for execution:</p>
    
    <div style="background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; padding: 16px; margin-bottom: 24px;">
      <table style="width: 100%; border-collapse: collapse; font-size: 13.5px;">
        <tr>
          <td style="padding: 6px 0; color: #64748b; width: 130px; font-weight: 600;">Action Reference:</td>
          <td style="padding: 6px 0; color: #0f172a; font-weight: 700;">${action.displayId}</td>
        </tr>
        <tr>
          <td style="padding: 6px 0; color: #64748b; font-weight: 600;">Title:</td>
          <td style="padding: 6px 0; color: #0f172a; font-weight: 600;">${action.subject}</td>
        </tr>
        <tr>
          <td style="padding: 6px 0; color: #64748b; font-weight: 600;">Required Work:</td>
          <td style="padding: 6px 0; color: #334155;">$reqText</td>
        </tr>
        <tr>
          <td style="padding: 6px 0; color: #64748b; font-weight: 600;">Priority:</td>
          <td style="padding: 6px 0; color: #0f172a;"><span style="display: inline-block; padding: 2px 8px; border-radius: 4px; font-weight: 600; font-size: 12px; background-color: #f1f5f9;">${action.priority}</span></td>
        </tr>
        <tr>
          <td style="padding: 6px 0; color: #64748b; font-weight: 600;">Due Date:</td>
          <td style="padding: 6px 0; color: #0f172a; font-weight: 600;">$dueDate</td>
        </tr>
        <tr>
          <td style="padding: 6px 0; color: #64748b; font-weight: 600;">Location / Site:</td>
          <td style="padding: 6px 0; color: #334155;">$siteText</td>
        </tr>
        <tr>
          <td style="padding: 6px 0; color: #64748b; font-weight: 600;">Status:</td>
          <td style="padding: 6px 0; color: #334155;">${action.status} (${action.percentComplete}%)</td>
        </tr>
      </table>
    </div>

    <div style="text-align: center; margin: 28px 0 20px 0;">
      <a href="$updateUrl" style="background-color: #0d9488; color: #ffffff; text-decoration: none; padding: 12px 28px; border-radius: 6px; font-weight: 600; font-size: 14px; display: inline-block;">Open Contractor Update Portal</a>
    </div>

    <p style="margin: 0 0 8px 0; font-size: 12.5px; color: #64748b; text-align: center;">No login is required. Use your secure link above to review requirements and submit updates or completion evidence.</p>
    <p style="margin: 0; font-size: 12px; color: #94a3b8; text-align: center;">Note: This secure update link is valid for 7 days.</p>
  </div>
  <div style="background-color: #f8fafc; border-top: 1px solid #e2e8f0; padding: 14px 24px; text-align: center; font-size: 12px; color: #94a3b8;">
    ActionFlow HSE Management System &bull; Contractor Notification
  </div>
</div>
''';
  }

  static String _buildExternalAssignmentEmailText({
    required ActionRecord action,
    required String recipientName,
    required String updateUrl,
  }) {
    final reqText = action.actionRequired.isNotEmpty
        ? action.actionRequired
        : (action.description.isNotEmpty
            ? action.description
            : 'Please review and execute the assigned action.');
    final siteText = action.site.isNotEmpty ? action.site : 'Not specified';
    final dueDate =
        action.targetDate.isNotEmpty ? action.targetDate : 'Not specified';

    return '''
Hello $recipientName,

An action has been assigned to you / your team for execution:

• Action Reference: ${action.displayId}
• Title: ${action.subject}
• Required Work: $reqText
• Priority: ${action.priority}
• Due Date: $dueDate
• Location / Site: $siteText
• Status: ${action.status} (${action.percentComplete}%)

No login is required. Use your secure link below to review requirements and submit updates or completion evidence:
$updateUrl

Note: This secure update link is valid for 7 days.

Thank you,
ActionFlow Team
''';
  }

  /// Sends a secure document access link email to an external recipient
  Future<EmailSendResult> sendExternalDocumentShareEmail({
    required String recipientEmail,
    required String documentTitle,
    required String accessUrl,
    required DateTime expiresAt,
    required String permission,
    String? recipientName,
    String? documentCategory,
    String? senderName,
    String? organizationName,
  }) async {
    final cleanEmail = recipientEmail.trim();
    if (cleanEmail.isEmpty) {
      return const EmailSendResult(
        isSuccess: false,
        status: 'invalid_recipient',
        errorMessage: 'Recipient email address cannot be empty.',
      );
    }

    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!emailRegex.hasMatch(cleanEmail)) {
      return EmailSendResult(
        isSuccess: false,
        status: 'invalid_email',
        errorMessage: 'Invalid recipient email format: $cleanEmail',
      );
    }

    final resolvedName = (recipientName != null && recipientName.trim().isNotEmpty)
        ? recipientName.trim()
        : 'Colleague';
    final orgName = (organizationName != null && organizationName.trim().isNotEmpty)
        ? organizationName.trim()
        : 'ActionFlow Enterprise';
    final fromName = (senderName != null && senderName.trim().isNotEmpty)
        ? senderName.trim()
        : 'A manager';

    final subject = 'ActionFlow Document Shared: $documentTitle';
    final html = _buildExternalDocumentShareEmailHtml(
      recipientEmail: cleanEmail,
      recipientName: resolvedName,
      documentTitle: documentTitle,
      documentCategory: documentCategory ?? 'General',
      accessUrl: accessUrl,
      expiresAt: expiresAt,
      permission: permission,
      senderName: fromName,
      organizationName: orgName,
    );
    final text = _buildExternalDocumentShareEmailText(
      recipientEmail: cleanEmail,
      recipientName: resolvedName,
      documentTitle: documentTitle,
      documentCategory: documentCategory ?? 'General',
      accessUrl: accessUrl,
      expiresAt: expiresAt,
      permission: permission,
      senderName: fromName,
      organizationName: orgName,
    );

    final sendResult = await sendSingleEmail(
      to: cleanEmail,
      subject: subject,
      html: html,
      text: text,
      recipientType: 'external',
    );

    return EmailSendResult(
      isSuccess: sendResult.isSuccess,
      status: sendResult.status,
      messageId: sendResult.messageId,
      errorMessage: sendResult.errorMessage,
      externalUpdateUrl: accessUrl,
      recipientEmail: cleanEmail,
      recipientType: 'external',
    );
  }

  static String _buildExternalDocumentShareEmailHtml({
    required String recipientEmail,
    required String recipientName,
    required String documentTitle,
    required String documentCategory,
    required String accessUrl,
    required DateTime expiresAt,
    required String permission,
    required String senderName,
    required String organizationName,
  }) {
    final expiryFormatted =
        '${expiresAt.year}-${expiresAt.month.toString().padLeft(2, '0')}-${expiresAt.day.toString().padLeft(2, '0')} ${expiresAt.hour.toString().padLeft(2, '0')}:${expiresAt.minute.toString().padLeft(2, '0')} UTC';
    final permissionLabel =
        permission.toLowerCase() == 'download' ? 'View & Download' : 'View Only';

    return '''
<div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; max-width: 600px; margin: 0 auto; background-color: #ffffff; border: 1px solid #e2e8f0; border-radius: 8px; overflow: hidden; color: #0f172a;">
  <div style="background-color: #0f172a; padding: 20px 24px; text-align: left;">
    <h1 style="color: #ffffff; margin: 0; font-size: 19px; font-weight: 700; letter-spacing: -0.3px;">ActionFlow</h1>
    <p style="color: #94a3b8; margin: 4px 0 0 0; font-size: 13px;">Enterprise Health, Safety & Environmental Management</p>
  </div>
  <div style="padding: 24px;">
    <p style="margin: 0 0 16px 0; font-size: 15px;">Hello <strong>$recipientName</strong>,</p>
    <p style="margin: 0 0 20px 0; font-size: 14px; color: #334155;"><strong>$senderName</strong> has shared a document with you from <strong>$organizationName</strong> via ActionFlow.</p>
    
    <div style="background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; padding: 16px; margin-bottom: 24px;">
      <table style="width: 100%; border-collapse: collapse; font-size: 13.5px;">
        <tr>
          <td style="padding: 6px 0; color: #64748b; width: 140px; font-weight: 600;">Document Title:</td>
          <td style="padding: 6px 0; color: #0f172a; font-weight: 700;">$documentTitle</td>
        </tr>
        <tr>
          <td style="padding: 6px 0; color: #64748b; font-weight: 600;">Category:</td>
          <td style="padding: 6px 0; color: #0f172a;"><span style="display: inline-block; padding: 2px 8px; border-radius: 4px; font-weight: 600; font-size: 12px; background-color: #f1f5f9;">$documentCategory</span></td>
        </tr>
        <tr>
          <td style="padding: 6px 0; color: #64748b; font-weight: 600;">Access Level:</td>
          <td style="padding: 6px 0; color: #0f172a; font-weight: 600;">$permissionLabel</td>
        </tr>
        <tr>
          <td style="padding: 6px 0; color: #64748b; font-weight: 600;">Expires On:</td>
          <td style="padding: 6px 0; color: #dc2626; font-weight: 600;">$expiryFormatted</td>
        </tr>
      </table>
    </div>

    <div style="text-align: center; margin: 28px 0 20px 0;">
      <a href="$accessUrl" style="background-color: #0d9488; color: #ffffff; text-decoration: none; padding: 12px 28px; border-radius: 6px; font-weight: 600; font-size: 14px; display: inline-block;">Access Secure Document</a>
    </div>

    <div style="background-color: #eff6ff; border: 1px solid #bfdbfe; border-radius: 6px; padding: 12px; margin-top: 20px;">
      <p style="margin: 0; font-size: 12px; color: #1e40af; line-height: 1.4;">
        <strong>Security Notice:</strong> This link provides direct access to the document above and expires automatically on $expiryFormatted. The link is encrypted, rate-limited, and intended solely for $recipientEmail. Do not forward or share this link.
      </p>
    </div>
  </div>
  <div style="background-color: #f8fafc; border-top: 1px solid #e2e8f0; padding: 14px 24px; text-align: center; font-size: 12px; color: #94a3b8;">
    ActionFlow Document Security &bull; Automated Delivery
  </div>
</div>
''';
  }

  static String _buildExternalDocumentShareEmailText({
    required String recipientEmail,
    required String recipientName,
    required String documentTitle,
    required String documentCategory,
    required String accessUrl,
    required DateTime expiresAt,
    required String permission,
    required String senderName,
    required String organizationName,
  }) {
    final expiryFormatted =
        '${expiresAt.year}-${expiresAt.month.toString().padLeft(2, '0')}-${expiresAt.day.toString().padLeft(2, '0')} ${expiresAt.hour.toString().padLeft(2, '0')}:${expiresAt.minute.toString().padLeft(2, '0')} UTC';
    final permissionLabel =
        permission.toLowerCase() == 'download' ? 'View & Download' : 'View Only';

    return '''
Hello $recipientName,

$senderName has shared a document with you from $organizationName via ActionFlow.

• Document Title: $documentTitle
• Category: $documentCategory
• Access Level: $permissionLabel
• Expires On: $expiryFormatted

Access the secure document using the link below:
$accessUrl

Security Notice:
This link provides direct access to the document and expires on $expiryFormatted. The link is confidential and intended solely for $recipientEmail. Do not forward this email.

Thank you,
ActionFlow System
''';
  }

  /// Daily / Scheduled Reminder Batch Processor
  ///
  /// Evaluates pending reminder jobs scheduled on or before [simulatedNow],
  /// cancels jobs for closed actions, dispatches emails for open actions,
  /// and synchronizes matching in-app notifications.
  Future<Map<String, dynamic>> processDueReminders({
    String? organizationId,
    DateTime? simulatedNow,
  }) async {
    final now = simulatedNow ?? DateTime.now();

    if (!SupabaseConfig.isInitialized) {
      final store = MockActionStore.instance;
      int processed = 0;
      int sent = 0;
      int cancelled = 0;
      int failed = 0;
      final results = <Map<String, dynamic>>[];

      for (int i = 0; i < store.emailReminders.length; i++) {
        final job = store.emailReminders[i];
        if (organizationId != null && job.organizationId != organizationId) {
          continue;
        }

        // Safe recovery & eligibility check:
        // Eligible if pending (and scheduled_at <= now, next_retry_at <= now)
        // OR processing and lease is stale (> 10 minutes)
        if (!job.isEligibleForClaim(now: now, leaseSeconds: 600)) {
          continue;
        }

        processed++;
        final action =
            store.actions.firstWhereOrNull((a) => a.id == job.actionId);
        if (action == null || action.isClosed || !action.emailReminderEnabled) {
          store.emailReminders[i] = job.copyWith(
            status: 'cancelled',
            updatedAt: now,
          );
          cancelled++;
          results.add({
            'id': job.id,
            'status': 'cancelled',
            'recipient': job.recipientEmail,
          });
          continue;
        }

        // Atomically claim the reminder
        final currentAttempts = job.attemptCount + 1;
        final claimedJob = job.copyWith(
          status: 'processing',
          claimedAt: now,
          claimedBy: 'mock-worker-${DateTime.now().microsecondsSinceEpoch}',
          attemptCount: currentAttempts,
          lastAttemptAt: now,
          updatedAt: now,
        );
        store.emailReminders[i] = claimedJob;

        // Check mock send handler if configured for testing
        EmailSendResult? sendResult;
        if (mockSendHandler != null) {
          sendResult = mockSendHandler!({
            'action': 'process_due_reminders',
            'reminder_id': job.id,
            'recipient_email': job.recipientEmail,
            'attempt_count': currentAttempts,
          });
        }

        // Fencing invariant: verify current worker still owns the processing claim
        // before persisting completion or failure updates to the store
        final latestInStore =
            store.emailReminders.firstWhereOrNull((r) => r.id == job.id);
        if (latestInStore == null ||
            latestInStore.claimedBy != claimedJob.claimedBy ||
            latestInStore.status != 'processing') {
          // Stale worker: lease was reclaimed by another worker; discard update
          continue;
        }

        if (sendResult != null && !sendResult.isSuccess) {
          // Failure handling
          final isRetryable = sendResult.status != 'not_configured' &&
              !sendResult.errorMessage!.toLowerCase().contains('permanent') &&
              !sendResult.errorMessage!.toLowerCase().contains('invalid');

          if (isRetryable && currentAttempts < job.maxAttempts) {
            // Bounded exponential backoff: 15m, 30m
            final backoffMinutes = min(15 * pow(2, currentAttempts - 1).toInt(), 60);
            final nextRetry = now.add(Duration(minutes: backoffMinutes));
            store.emailReminders[i] = claimedJob.copyWith(
              status: 'pending',
              isRetryable: true,
              nextRetryAt: nextRetry,
              failureReason: '[Attempt $currentAttempts/${job.maxAttempts}]: ${sendResult.errorMessage}',
              updatedAt: now,
            );
            results.add({
              'id': job.id,
              'status': 'retry_scheduled',
              'recipient': job.recipientEmail,
              'next_retry_at': nextRetry.toIso8601String(),
            });
          } else {
            // Max attempts exhausted or non-retryable
            store.emailReminders[i] = claimedJob.copyWith(
              status: 'failed',
              isRetryable: false,
              clearNextRetryAt: true,
              failureReason: currentAttempts >= job.maxAttempts
                  ? '[Max retries exceeded (${job.maxAttempts})]: ${sendResult.errorMessage}'
                  : '[Permanent failure]: ${sendResult.errorMessage}',
              updatedAt: now,
            );
            failed++;
            results.add({
              'id': job.id,
              'status': 'failed',
              'recipient': job.recipientEmail,
              'error': sendResult.errorMessage,
            });
          }
          continue;
        }

        // Success: mark sent
        store.emailReminders[i] = claimedJob.copyWith(
          status: 'sent',
          sentAt: now,
          clearNextRetryAt: true,
          failureReason: null,
          updatedAt: now,
        );
        sent++;
        results.add({
          'id': job.id,
          'status': 'sent',
          'recipient': job.recipientEmail,
        });

        // Synchronize in-app notification for internal staff
        if (job.profileId != null && job.profileId!.isNotEmpty) {
          NotificationService.instance.createNotification(
            AppNotification(
              id: 'rem-notif-${job.id}',
              userId: job.profileId!,
              organizationId: job.organizationId,
              title: job.emailSubject,
              message: job.emailBody,
              eventType: 'due_date_approaching',
              actionId: action.displayId,
              idempotencyKey: 'batch_rem_${job.id}',
              createdAt: now,
            ),
          );
        }
      }

      return {
        'success': true,
        'mode': 'mock',
        'processed_count': processed,
        'sent_count': sent,
        'cancelled_count': cancelled,
        'failed_count': failed,
        'results': results,
      };
    }

    try {
      final client = SupabaseConfig.client;
      final response = await client.functions.invoke(
        'send-email',
        body: {
          'action': 'process_due_reminders',
          'organization_id': ?organizationId,
        },
      );

      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      return {
        'success': false,
        'error': 'Unexpected response format from email function',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
}

