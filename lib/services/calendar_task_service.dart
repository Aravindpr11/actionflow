import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/supabase_config.dart';
import '../features/calendar/models/calendar_task.dart';
import 'auth_service.dart';
import 'notification_service.dart';

/// Exception thrown when personal calendar task persistence fails.
class CalendarTaskPersistenceException implements Exception {
  const CalendarTaskPersistenceException({
    required this.message,
    this.code,
    this.originalError,
    this.stackTrace,
    this.isTableMissing = false,
  });

  final String message;
  final String? code;
  final Object? originalError;
  final StackTrace? stackTrace;
  final bool isTableMissing;

  @override
  String toString() => message;
}

/// In-memory store for personal calendar tasks.
///
/// Used for tests, offline mode, and in-session caching.
/// Strictly enforces user isolation: User A cannot read, update, or delete
/// tasks belonging to User B.
class MockCalendarTaskStore {
  static final MockCalendarTaskStore instance = MockCalendarTaskStore._internal();
  MockCalendarTaskStore._internal();

  final List<CalendarTask> _tasks = [];

  List<CalendarTask> get allTasksForTesting => List.unmodifiable(_tasks);

  void clear() {
    _tasks.clear();
  }

  void clearForUser(String userId) {
    _tasks.removeWhere((t) => t.userId == userId);
  }

  void seed(List<CalendarTask> tasks) {
    for (final task in tasks) {
      _tasks.removeWhere((t) => t.id == task.id && t.userId == task.userId);
      _tasks.add(task);
    }
  }

  List<CalendarTask> getTasks(String userId) {
    return _tasks
        .where((t) => t.userId == userId)
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  CalendarTask createTask(CalendarTask task) {
    final now = DateTime.now();
    final newTask = task.copyWith(
      id: task.id.isEmpty
          ? 'task-${DateTime.now().microsecondsSinceEpoch}'
          : task.id,
      createdAt: task.createdAt,
      updatedAt: now,
    );
    _tasks.removeWhere((t) => t.id == newTask.id && t.userId == newTask.userId);
    _tasks.add(newTask);
    return newTask;
  }

  CalendarTask updateTask(CalendarTask task) {
    final index = _tasks.indexWhere(
      (t) => t.id == task.id && t.userId == task.userId,
    );
    if (index == -1) {
      throw Exception('Task not found or access denied');
    }
    final updated = task.copyWith(updatedAt: DateTime.now());
    _tasks[index] = updated;
    return updated;
  }

  void toggleCompletion({
    required String taskId,
    required String userId,
    required bool isCompleted,
  }) {
    final index = _tasks.indexWhere(
      (t) => t.id == taskId && t.userId == userId,
    );
    if (index == -1) {
      throw Exception('Task not found or access denied');
    }
    final existing = _tasks[index];
    _tasks[index] = existing.copyWith(
      isCompleted: isCompleted,
      completedAt: isCompleted ? DateTime.now() : null,
      clearCompletedAt: !isCompleted,
      updatedAt: DateTime.now(),
    );
  }

  void deleteTask({required String taskId, required String userId}) {
    _tasks.removeWhere((t) => t.id == taskId && t.userId == userId);
  }
}

/// Service handling private personal Calendar Tasks.
///
/// Guaranteed properties:
/// 1. Strict user-isolation: only the authenticated user's tasks are fetched/mutated.
/// 2. Complete decoupling from official HSSE actions and Add Action workflow.
/// 3. Resilient error handling without false claims of production persistence.
class CalendarTaskService {
  final SupabaseClient? _clientOverride;
  static bool useMockOnly = false;

  @visibleForTesting
  bool mockPersistenceShouldFail = false;

  @visibleForTesting
  String? mockPersistenceFailureReason;

  CalendarTaskService([SupabaseClient? client]) : _clientOverride = client;

  SupabaseClient? get _client => _clientOverride ?? SupabaseConfig.clientOrNull;

  bool get isReady {
    if (useMockOnly) return false;
    final client = _client;
    if (client == null) return false;
    if (_clientOverride != null) return true;
    return SupabaseConfig.isInitialized && client.auth.currentUser != null;
  }

  MockCalendarTaskStore get _mockStore => MockCalendarTaskStore.instance;

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  String _effectiveUserId(String? candidateUserId) {
    final authId = _client?.auth.currentUser?.id;
    if (authId != null && authId.isNotEmpty) {
      return authId;
    }
    if (candidateUserId != null && candidateUserId.isNotEmpty) {
      return candidateUserId;
    }
    final profileId = AuthService.instance.currentProfile?.id;
    if (profileId != null && profileId.isNotEmpty) {
      return profileId;
    }
    return '';
  }

  String? _sanitizeOrgId(String? orgId) {
    if (orgId == null) return null;
    final trimmed = orgId.trim();
    if (trimmed.isEmpty) return null;
    if (_uuidRegex.hasMatch(trimmed)) return trimmed;
    if (trimmed.toUpperCase() == 'SOBHA-001' || trimmed == 'org-sobha-01') {
      return '00000000-0000-0000-0000-000000000001';
    }
    return null;
  }

  String? _sanitizeTaskId(String? id) {
    if (id == null) return null;
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;
    if (_uuidRegex.hasMatch(trimmed)) return trimmed;
    return null;
  }

  bool _isMissingTableError(Object error) {
    final str = error.toString().toLowerCase();
    return str.contains('pgrst205') ||
        str.contains('schema cache') ||
        str.contains('relation "public.calendar_tasks" does not exist') ||
        str.contains('relation "calendar_tasks" does not exist') ||
        str.contains("could not find the table 'public.calendar_tasks'") ||
        str.contains("could not find the table 'calendar_tasks'");
  }

  /// Fetch all personal tasks for [userId].
  Future<List<CalendarTask>> getTasks({required String userId}) async {
    final client = _client;
    if (useMockOnly || client == null) {
      return _mockStore.getTasks(userId);
    }

    if (!isReady) {
      return _mockStore.getTasks(userId);
    }

    final effectiveUser = _effectiveUserId(userId);
    if (effectiveUser.isEmpty) return _mockStore.getTasks(userId);

    try {
      final response = await client
          .from('calendar_tasks')
          .select()
          .eq('user_id', effectiveUser)
          .order('due_date', ascending: true);

      final List<dynamic> data = response as List<dynamic>;
      final tasks = data
          .map((json) => CalendarTask.fromJson(json as Map<String, dynamic>))
          .toList();

      _mockStore.clearForUser(effectiveUser);
      _mockStore.seed(tasks);
      return tasks;
    } catch (e, st) {
      if (_isMissingTableError(e)) {
        debugPrint(
          '[CalendarTaskService] Table public.calendar_tasks not migrated on remote Supabase (PGRST205). Falling back to local store.',
        );
        return _mockStore.getTasks(effectiveUser.isNotEmpty ? effectiveUser : userId);
      }
      debugPrint('[CalendarTaskService] Remote query failed: $e');
      throw CalendarTaskPersistenceException(
        message: 'Failed to fetch personal tasks: $e',
        originalError: e,
        stackTrace: st,
      );
    }
  }

  /// Create a new personal task.
  Future<CalendarTask> createTask(CalendarTask task) async {
    if (mockPersistenceShouldFail) {
      throw CalendarTaskPersistenceException(
        message: mockPersistenceFailureReason ?? 'Simulated task persistence failure.',
      );
    }

    final client = _client;
    if (useMockOnly || client == null) {
      final created = _mockStore.createTask(task);
      final effUser = _effectiveUserId(task.userId);
      if (effUser.isNotEmpty) {
        NotificationService.safeDispatch(
          () => NotificationService.instance.notifyCalendarEventAssigned(
            taskId: created.id,
            taskTitle: created.title,
            assigneeUserId: effUser,
            scheduledDate: created.dueDate.toLocal().toString().split(' ').first,
            organizationId: created.organizationId,
          ),
          context: 'CalendarTaskService.createTask (mock)',
        );
      }
      return created;
    }

    if (!isReady) {
      throw const CalendarTaskPersistenceException(
        message: 'Database connection is not ready or user is not authenticated. Tasks cannot be saved.',
      );
    }

    final effectiveUser = _effectiveUserId(task.userId);
    if (effectiveUser.isEmpty) {
      throw const CalendarTaskPersistenceException(
        message: 'User authentication required to save personal calendar tasks.',
      );
    }

    final sanitizedOrg = _sanitizeOrgId(task.organizationId);

    final payload = <String, dynamic>{
      'user_id': effectiveUser,
      'title': task.title.trim(),
      'description': task.description?.trim().isEmpty == true ? null : task.description?.trim(),
      'due_date': task.dueDate.toUtc().toIso8601String(),
      'start_date': task.startDate?.toUtc().toIso8601String(),
      'priority': task.priority,
      'is_completed': task.isCompleted,
      'completed_at': task.completedAt?.toUtc().toIso8601String(),
    };

    if (sanitizedOrg != null) {
      payload['organization_id'] = sanitizedOrg;
    }

    final sanitizedId = _sanitizeTaskId(task.id);
    if (sanitizedId != null) {
      payload['id'] = sanitizedId;
    }

    try {
      final response = await client
          .from('calendar_tasks')
          .insert(payload)
          .select()
          .single();

      final saved = CalendarTask.fromJson(response);
      _mockStore.createTask(saved);

      NotificationService.safeDispatch(
        () => NotificationService.instance.notifyCalendarEventAssigned(
          taskId: saved.id,
          taskTitle: saved.title,
          assigneeUserId: effectiveUser,
          scheduledDate: saved.dueDate.toLocal().toString().split(' ').first,
          organizationId: saved.organizationId,
        ),
        context: 'CalendarTaskService.createTask',
      );

      return saved;
    } catch (e, st) {
      if (_isMissingTableError(e)) {
        throw CalendarTaskPersistenceException(
          message: 'Database table public.calendar_tasks is not migrated (PGRST205). Personal tasks cannot be saved permanently until the migration is deployed to Supabase.',
          code: 'PGRST205',
          isTableMissing: true,
          originalError: e,
          stackTrace: st,
        );
      }
      debugPrint('[CalendarTaskService] Remote insert failed: $e');
      throw CalendarTaskPersistenceException(
        message: 'Failed to persist personal task: $e',
        originalError: e,
        stackTrace: st,
      );
    }
  }

  /// Update an existing personal task.
  Future<CalendarTask> updateTask(CalendarTask task) async {
    if (mockPersistenceShouldFail) {
      throw CalendarTaskPersistenceException(
        message: mockPersistenceFailureReason ?? 'Simulated task persistence failure.',
      );
    }

    final client = _client;
    if (useMockOnly || client == null) {
      final updated = _mockStore.updateTask(task);
      final effUser = _effectiveUserId(task.userId);
      if (effUser.isNotEmpty) {
        NotificationService.safeDispatch(
          () => NotificationService.instance.notifyCalendarEventUpdated(
            taskId: updated.id,
            taskTitle: updated.title,
            recipientUserId: effUser,
            newDate: updated.dueDate.toLocal().toString().split(' ').first,
            organizationId: updated.organizationId,
          ),
          context: 'CalendarTaskService.updateTask (mock)',
        );
      }
      return updated;
    }

    if (!isReady) {
      throw const CalendarTaskPersistenceException(
        message: 'Database connection is not ready or user is not authenticated.',
      );
    }

    final effectiveUser = _effectiveUserId(task.userId);
    if (effectiveUser.isEmpty) {
      throw const CalendarTaskPersistenceException(
        message: 'User authentication required to update personal calendar tasks.',
      );
    }

    final payload = <String, dynamic>{
      'title': task.title.trim(),
      'description': task.description?.trim().isEmpty == true ? null : task.description?.trim(),
      'due_date': task.dueDate.toUtc().toIso8601String(),
      'start_date': task.startDate?.toUtc().toIso8601String(),
      'priority': task.priority,
      'is_completed': task.isCompleted,
      'completed_at': task.completedAt?.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    final sanitizedOrg = _sanitizeOrgId(task.organizationId);
    if (sanitizedOrg != null) {
      payload['organization_id'] = sanitizedOrg;
    }

    try {
      final response = await client
          .from('calendar_tasks')
          .update(payload)
          .eq('id', task.id)
          .eq('user_id', effectiveUser)
          .select()
          .single();

      final updated = CalendarTask.fromJson(response);
      _mockStore.updateTask(updated);

      NotificationService.safeDispatch(
        () => NotificationService.instance.notifyCalendarEventUpdated(
          taskId: updated.id,
          taskTitle: updated.title,
          recipientUserId: effectiveUser,
          newDate: updated.dueDate.toLocal().toString().split(' ').first,
          organizationId: updated.organizationId,
        ),
        context: 'CalendarTaskService.updateTask',
      );

      return updated;
    } catch (e, st) {
      if (_isMissingTableError(e)) {
        throw CalendarTaskPersistenceException(
          message: 'Database table public.calendar_tasks is not migrated (PGRST205). Task update cannot be persisted.',
          code: 'PGRST205',
          isTableMissing: true,
          originalError: e,
          stackTrace: st,
        );
      }
      debugPrint('[CalendarTaskService] Remote update failed: $e');
      throw CalendarTaskPersistenceException(
        message: 'Failed to update personal task: $e',
        originalError: e,
        stackTrace: st,
      );
    }
  }

  /// Toggle task completion status.
  Future<void> toggleTaskCompletion({
    required String taskId,
    required String userId,
    required bool isCompleted,
  }) async {
    if (mockPersistenceShouldFail) {
      throw CalendarTaskPersistenceException(
        message: mockPersistenceFailureReason ?? 'Simulated task persistence failure.',
      );
    }

    final client = _client;
    if (useMockOnly || client == null) {
      _mockStore.toggleCompletion(
        taskId: taskId,
        userId: userId,
        isCompleted: isCompleted,
      );
      return;
    }

    if (!isReady) {
      throw const CalendarTaskPersistenceException(
        message: 'Database connection is not ready or user is not authenticated.',
      );
    }

    final effectiveUser = _effectiveUserId(userId);
    final now = DateTime.now().toUtc();
    try {
      await client
          .from('calendar_tasks')
          .update({
            'is_completed': isCompleted,
            'completed_at': isCompleted ? now.toIso8601String() : null,
            'updated_at': now.toIso8601String(),
          })
          .eq('id', taskId)
          .eq('user_id', effectiveUser);

      _mockStore.toggleCompletion(
        taskId: taskId,
        userId: effectiveUser,
        isCompleted: isCompleted,
      );
    } catch (e, st) {
      if (_isMissingTableError(e)) {
        throw CalendarTaskPersistenceException(
          message: 'Database table public.calendar_tasks is not migrated (PGRST205). Task completion cannot be persisted.',
          code: 'PGRST205',
          isTableMissing: true,
          originalError: e,
          stackTrace: st,
        );
      }
      debugPrint('[CalendarTaskService] Remote toggle failed: $e');
      throw CalendarTaskPersistenceException(
        message: 'Failed to toggle personal task completion: $e',
        originalError: e,
        stackTrace: st,
      );
    }
  }

  /// Delete a personal task.
  Future<void> deleteTask({
    required String taskId,
    required String userId,
  }) async {
    if (mockPersistenceShouldFail) {
      throw CalendarTaskPersistenceException(
        message: mockPersistenceFailureReason ?? 'Simulated task persistence failure.',
      );
    }

    final client = _client;
    if (useMockOnly || client == null) {
      _mockStore.deleteTask(taskId: taskId, userId: userId);
      return;
    }

    if (!isReady) {
      throw const CalendarTaskPersistenceException(
        message: 'Database connection is not ready or user is not authenticated.',
      );
    }

    final effectiveUser = _effectiveUserId(userId);
    try {
      await client
          .from('calendar_tasks')
          .delete()
          .eq('id', taskId)
          .eq('user_id', effectiveUser);

      _mockStore.deleteTask(taskId: taskId, userId: effectiveUser);
    } catch (e, st) {
      if (_isMissingTableError(e)) {
        throw CalendarTaskPersistenceException(
          message: 'Database table public.calendar_tasks is not migrated (PGRST205). Task deletion cannot be persisted.',
          code: 'PGRST205',
          isTableMissing: true,
          originalError: e,
          stackTrace: st,
        );
      }
      debugPrint('[CalendarTaskService] Remote delete failed: $e');
      throw CalendarTaskPersistenceException(
        message: 'Failed to delete personal task: $e',
        originalError: e,
        stackTrace: st,
      );
    }
  }
}
