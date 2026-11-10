import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/external_update/models/external_action_payload.dart';
import 'package:action_flow/services/email_service.dart';
import 'package:collection/collection.dart';

/// Sealed class representing the result of fetching an action via access token
sealed class ExternalActionFetchResult {
  const ExternalActionFetchResult();
}

class ExternalActionFetchSuccess extends ExternalActionFetchResult {
  final ExternalActionPayload payload;
  const ExternalActionFetchSuccess(this.payload);
}

class ExternalActionFetchFailure extends ExternalActionFetchResult {
  final String errorMessage;
  final bool isExpired;
  final bool isRevoked;
  const ExternalActionFetchFailure(
    this.errorMessage, {
    this.isExpired = false,
    this.isRevoked = false,
  });
}

/// Sealed class representing the result of an external update submission
sealed class ExternalActionSubmitResult {
  const ExternalActionSubmitResult();
}

class ExternalActionSubmitSuccess extends ExternalActionSubmitResult {
  final String updateId;
  final String actionId;
  final int progress;
  final String status;
  final DateTime submittedAt;

  const ExternalActionSubmitSuccess({
    required this.updateId,
    required this.actionId,
    required this.progress,
    required this.status,
    required this.submittedAt,
  });
}

class ExternalActionSubmitFailure extends ExternalActionSubmitResult {
  final String errorMessage;
  const ExternalActionSubmitFailure(this.errorMessage);
}

/// Mock entry for hermetic testing and offline operation
class MockExternalTokenEntry {
  final String rawToken;
  final String tokenHash;
  final ExternalActionPayload payload;
  bool isRevoked;
  DateTime expiresAt;

  MockExternalTokenEntry({
    required this.rawToken,
    required this.tokenHash,
    required this.payload,
    this.isRevoked = false,
    required this.expiresAt,
  });
}

/// In-memory mock store for unit and widget tests
class MockExternalActionStore {
  MockExternalActionStore._();
  static final MockExternalActionStore instance = MockExternalActionStore._();

  final Map<String, MockExternalTokenEntry> _tokensByHash = {};

  void reset() {
    _tokensByHash.clear();
  }

  void registerToken({
    required String rawToken,
    required ExternalActionPayload payload,
    Duration expiry = const Duration(days: 7),
    bool isRevoked = false,
  }) {
    final hash = EmailService.hashToken(rawToken);
    _tokensByHash[hash] = MockExternalTokenEntry(
      rawToken: rawToken,
      tokenHash: hash,
      payload: payload,
      isRevoked: isRevoked,
      expiresAt: DateTime.now().add(expiry),
    );
  }

  MockExternalTokenEntry? findByHash(String hash) => _tokensByHash[hash];

  void revokeToken(String rawToken) {
    final hash = EmailService.hashToken(rawToken);
    if (_tokensByHash.containsKey(hash)) {
      _tokensByHash[hash]!.isRevoked = true;
    }
  }

  void expireToken(String rawToken) {
    final hash = EmailService.hashToken(rawToken);
    if (_tokensByHash.containsKey(hash)) {
      _tokensByHash[hash]!.expiresAt = DateTime.now().subtract(const Duration(minutes: 1));
    }
  }
}

/// External Action Service: communicates with Supabase RPCs or MockStore
class ExternalActionService {
  ExternalActionService._();
  static final ExternalActionService instance = ExternalActionService._();

  /// Fetches action details by raw access token
  Future<ExternalActionFetchResult> fetchActionByToken(String rawToken) async {
    final token = rawToken.trim();
    if (token.isEmpty) {
      return const ExternalActionFetchFailure('Access token is missing or empty.');
    }

    final tokenHash = EmailService.hashToken(token);

    // 1. Check Mock Store (for tests or local verification)
    final mockEntry = MockExternalActionStore.instance.findByHash(tokenHash);
    if (mockEntry != null) {
      if (mockEntry.isRevoked) {
        return const ExternalActionFetchFailure(
          'This access link has been revoked. Please request a new link from your ActionFlow manager.',
          isRevoked: true,
        );
      }
      if (mockEntry.expiresAt.isBefore(DateTime.now())) {
        return const ExternalActionFetchFailure(
          'This access link has expired. Please contact your ActionFlow manager for an updated link.',
          isExpired: true,
        );
      }
      return ExternalActionFetchSuccess(mockEntry.payload);
    }

    // 2. Query Supabase RPC
    if (!SupabaseConfig.isInitialized) {
      return const ExternalActionFetchFailure(
        'Backend service not connected. Please verify your internet connection or contact support.',
      );
    }

    try {
      final client = SupabaseConfig.client;
      final response = await client.rpc(
        'get_external_action_by_token',
        params: {'p_token_hash': tokenHash},
      );

      if (response is Map) {
        final map = Map<String, dynamic>.from(response);
        if (map['valid'] == true) {
          final payload = ExternalActionPayload.fromJson(map);
          return ExternalActionFetchSuccess(payload);
        } else {
          final errMsg = map['error']?.toString() ?? 'Invalid or expired access token.';
          final isRevoked = errMsg.toLowerCase().contains('revoked');
          final isExpired = errMsg.toLowerCase().contains('expired');
          return ExternalActionFetchFailure(
            errMsg,
            isRevoked: isRevoked,
            isExpired: isExpired,
          );
        }
      }

      return const ExternalActionFetchFailure('Unexpected response from server.');
    } catch (e) {
      return ExternalActionFetchFailure('Failed to load action details: $e');
    }
  }

  /// Submits progress update from external contractor
  Future<ExternalActionSubmitResult> submitProgressUpdate({
    required String rawToken,
    required int progress,
    required String status,
    required String comments,
    List<String>? attachments,
  }) async {
    final token = rawToken.trim();
    if (token.isEmpty) {
      return const ExternalActionSubmitFailure('Access token is missing.');
    }

    // Security check: external recipients cannot close actions
    if (status.trim().toLowerCase() == 'closed') {
      return const ExternalActionSubmitFailure(
        'ActionFlow Security Violation: External contractors cannot approve or close actions. Please set status to Pending Review.',
      );
    }

    if (comments.trim().isEmpty) {
      return const ExternalActionSubmitFailure(
        'Work update notes / comments are required.',
      );
    }

    if (progress < 0 || progress > 100) {
      return const ExternalActionSubmitFailure(
        'Progress percentage must be between 0 and 100.',
      );
    }

    final tokenHash = EmailService.hashToken(token);

    // 1. Check Mock Store
    final mockEntry = MockExternalActionStore.instance.findByHash(tokenHash);
    if (mockEntry != null) {
      if (mockEntry.isRevoked) {
        return const ExternalActionSubmitFailure('Access token has been revoked.');
      }
      if (mockEntry.expiresAt.isBefore(DateTime.now())) {
        return const ExternalActionSubmitFailure('Access token has expired.');
      }

      // Record update into mock payload history
      final newHistoryEntry = {
        'timestamp': DateTime.now().toIso8601String(),
        'actor_type': 'external',
        'actor_name': mockEntry.payload.recipientName,
        'progress': progress,
        'status': status,
        'comment': comments.trim(),
        'action': '$progress% (External Update by ${mockEntry.payload.recipientName}) — ${comments.trim()}',
      };

      final updatedPayload = ExternalActionPayload(
        actionId: mockEntry.payload.actionId,
        actionNumber: mockEntry.payload.actionNumber,
        title: mockEntry.payload.title,
        description: mockEntry.payload.description,
        actionRequired: mockEntry.payload.actionRequired,
        category: mockEntry.payload.category,
        priority: mockEntry.payload.priority,
        status: status,
        percentComplete: progress,
        dateRaised: mockEntry.payload.dateRaised,
        startDate: mockEntry.payload.startDate,
        targetDate: mockEntry.payload.targetDate,
        dueDate: mockEntry.payload.dueDate,
        nextFollowUpDate: mockEntry.payload.nextFollowUpDate,
        department: mockEntry.payload.department,
        site: mockEntry.payload.site,
        organizationName: mockEntry.payload.organizationName,
        isClosed: false,
        recentHistory: [newHistoryEntry, ...mockEntry.payload.recentHistory],
        recipientId: mockEntry.payload.recipientId,
        recipientName: mockEntry.payload.recipientName,
        recipientEmail: mockEntry.payload.recipientEmail,
        companyName: mockEntry.payload.companyName,
        phone: mockEntry.payload.phone,
        expiresAt: mockEntry.expiresAt,
        accessCount: mockEntry.payload.accessCount + 1,
      );

      MockExternalActionStore.instance.registerToken(
        rawToken: rawToken,
        payload: updatedPayload,
        expiry: mockEntry.expiresAt.difference(DateTime.now()),
      );

      return ExternalActionSubmitSuccess(
        updateId: 'mock-update-${DateTime.now().millisecondsSinceEpoch}',
        actionId: mockEntry.payload.actionId,
        progress: progress,
        status: status,
        submittedAt: DateTime.now(),
      );
    }

    // 2. Query Supabase RPC
    if (!SupabaseConfig.isInitialized) {
      return const ExternalActionSubmitFailure(
        'Backend service not connected. Please verify your internet connection.',
      );
    }

    try {
      final client = SupabaseConfig.client;
      final response = await client.rpc(
        'submit_external_action_update',
        params: {
          'p_token_hash': tokenHash,
          'p_progress': progress,
          'p_status': status,
          'p_comments': comments.trim(),
          'p_attachments': attachments ?? [],
        },
      );

      if (response is Map) {
        final map = Map<String, dynamic>.from(response);
        if (map['success'] == true) {
          return ExternalActionSubmitSuccess(
            updateId: map['update_id']?.toString() ?? '',
            actionId: map['action_id']?.toString() ?? '',
            progress: (map['progress'] as num?)?.toInt() ?? progress,
            status: map['status']?.toString() ?? status,
            submittedAt: DateTime.tryParse(map['submitted_at']?.toString() ?? '') ?? DateTime.now(),
          );
        }
      }

      return const ExternalActionSubmitFailure('Failed to submit progress update.');
    } catch (e) {
      return ExternalActionSubmitFailure('Error submitting update: $e');
    }
  }

  static String _monthName(int m) {
    const months = [
      '',
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
    return m >= 1 && m <= 12 ? months[m] : '';
  }

  /// Submits external subtask checkbox toggle by external contractor token
  Future<Map<String, dynamic>> submitSubtaskToggle({
    required String rawToken,
    required String taskId,
    required bool isCompleted,
  }) async {
    final token = rawToken.trim();
    if (token.isEmpty) {
      return {'success': false, 'error': 'Access token is missing.'};
    }
    if (taskId.trim().isEmpty) {
      return {'success': false, 'error': 'Task ID is missing.'};
    }

    final tokenHash = EmailService.hashToken(token);

    // 1. Check Mock Store (for hermetic testing and offline operation)
    var mockEntry = MockExternalActionStore.instance.findByHash(tokenHash);
    if (mockEntry == null && !SupabaseConfig.isInitialized) {
      final matching = MockActionStore.instance.actions.firstWhereOrNull(
        (a) => a.subTasks.any((t) => t.id == taskId),
      );
      if (matching != null) {
        final payload = ExternalActionPayload(
          actionId: matching.id,
          actionNumber: matching.actionNumber,
          title: matching.subject,
          description: matching.description,
          actionRequired: matching.actionRequired,
          category: matching.category,
          priority: matching.priority,
          status: matching.status,
          percentComplete: matching.percentComplete,
          dateRaised: matching.dateRaised,
          startDate: matching.startDate,
          targetDate: matching.targetDate,
          dueDate: matching.targetDate,
          nextFollowUpDate: matching.nextFollowUpDate,
          department: matching.department,
          site: matching.site,
          organizationName: 'ActionFlow',
          isClosed: matching.isClosed,
          recentHistory: const [],
          subTasks: matching.subTasks,
          recipientId: '',
          recipientName: 'External Contractor',
          recipientEmail: '',
          companyName: '',
          phone: '',
        );
        MockExternalActionStore.instance.registerToken(
          rawToken: rawToken,
          payload: payload,
        );
        mockEntry = MockExternalActionStore.instance.findByHash(tokenHash);
      }
    }
    if (mockEntry != null) {
      if (mockEntry.isRevoked) {
        return {'success': false, 'error': 'Access token has been revoked.'};
      }
      if (mockEntry.expiresAt.isBefore(DateTime.now())) {
        return {'success': false, 'error': 'Access token has expired.'};
      }

      final payload = mockEntry.payload;
      final existingTasks = List<ActionSubTask>.from(payload.subTasks);
      final taskIdx = existingTasks.indexWhere((t) => t.id == taskId);
      if (taskIdx == -1) {
        return {'success': false, 'error': 'Task not found or not assigned to contractor.'};
      }

      final now = DateTime.now();
      final nowStr =
          '${now.day.toString().padLeft(2, '0')} ${_monthName(now.month)} ${now.year}';
      if (isCompleted) {
        existingTasks[taskIdx] = existingTasks[taskIdx].copyWith(
          status: 'Completed',
          completedAt: nowStr,
          completedBy: payload.recipientName,
        );
      } else {
        existingTasks[taskIdx] = existingTasks[taskIdx].copyWith(
          status: 'Open',
          completedAt: '',
          completedBy: '',
        );
      }

      final completedCount = existingTasks.where((t) => t.isCompleted).length;
      final newPercent = existingTasks.isNotEmpty
          ? ((completedCount / existingTasks.length) * 100).round()
          : payload.percentComplete;

      final updatedPayload = ExternalActionPayload(
        actionId: payload.actionId,
        actionNumber: payload.actionNumber,
        title: payload.title,
        description: payload.description,
        actionRequired: payload.actionRequired,
        category: payload.category,
        priority: payload.priority,
        status: payload.status,
        percentComplete: newPercent,
        dateRaised: payload.dateRaised,
        startDate: payload.startDate,
        targetDate: payload.targetDate,
        dueDate: payload.dueDate,
        nextFollowUpDate: payload.nextFollowUpDate,
        department: payload.department,
        site: payload.site,
        organizationName: payload.organizationName,
        isClosed: payload.isClosed,
        recentHistory: payload.recentHistory,
        subTasks: existingTasks,
        recipientId: payload.recipientId,
        recipientName: payload.recipientName,
        recipientEmail: payload.recipientEmail,
        companyName: payload.companyName,
        phone: payload.phone,
        expiresAt: payload.expiresAt,
        accessCount: payload.accessCount,
      );

      MockExternalActionStore.instance.registerToken(
        rawToken: rawToken,
        payload: updatedPayload,
        expiry: mockEntry.expiresAt.difference(DateTime.now()),
      );

      // Sync with MockActionStore if an ActionRecord matches
      final matchingMockAction = MockActionStore.instance.actions
          .firstWhereOrNull((a) => a.id == payload.actionId || a.actionNumber == payload.actionNumber);
      if (matchingMockAction != null) {
        final syncedSubtasks = matchingMockAction.subTasks.map((t) {
          if (t.id == taskId) {
            return isCompleted
                ? t.copyWith(status: 'Completed', completedAt: nowStr, completedBy: payload.recipientName)
                : t.copyWith(status: 'Open', completedAt: '', completedBy: '');
          }
          return t;
        }).toList();
        final syncedCompleted = syncedSubtasks.where((t) => t.isCompleted).length;
        final syncedPercent = syncedSubtasks.isNotEmpty
            ? ((syncedCompleted / syncedSubtasks.length) * 100).round()
            : matchingMockAction.percentComplete;
        MockActionStore.instance.update(
          matchingMockAction.copyWith(
            subTasks: syncedSubtasks,
            percentComplete: syncedPercent,
          ),
        );
      }

      return {
        'success': true,
        'percent_complete': newPercent,
        'completed_count': completedCount,
        'total_tasks': existingTasks.length,
        'task_id': taskId,
        'is_completed': isCompleted,
      };
    }

    // 2. Query Supabase RPC
    if (!SupabaseConfig.isInitialized) {
      return {
        'success': false,
        'error': 'Backend service not connected. Please verify your internet connection.',
      };
    }

    try {
      final client = SupabaseConfig.client;
      final response = await client.rpc(
        'submit_external_subtask_toggle',
        params: {
          'p_token_hash': tokenHash,
          'p_task_id': taskId,
          'p_completed': isCompleted,
        },
      );

      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }

      return {'success': false, 'error': 'Failed to toggle task completion.'};
    } catch (e) {
      return {'success': false, 'error': 'Error toggling task: $e'};
    }
  }
}

