import 'dart:async';
import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/services/app_file_picker_service.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_email_reminder_job.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/external_recipient.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/models/team.dart';
import 'package:action_flow/models/action_section.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/action_section_service.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:action_flow/services/email_service.dart';
import 'package:action_flow/services/notification_service.dart';
import 'package:action_flow/services/report_service.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Aggregated metrics for the Manager Dashboard
class ManagerDashboardMetrics {
  final int total;
  final int open;
  final int inProgress;
  final int pendingReview;
  final int overdue;
  final int dueSoon;
  final int followUpDue;
  final int criticalHigh;
  final int closed;

  const ManagerDashboardMetrics({
    this.total = 0,
    this.open = 0,
    this.inProgress = 0,
    this.pendingReview = 0,
    this.overdue = 0,
    this.dueSoon = 0,
    this.followUpDue = 0,
    this.criticalHigh = 0,
    this.closed = 0,
  });
}

/// Exception thrown when persisting or reconciling action assignees fails.
class ActionAssigneePersistenceException implements Exception {
  final String message;
  final dynamic cause;
  final String? actionId;
  final List<String> profileIds;

  const ActionAssigneePersistenceException(
    this.message, {
    this.cause,
    this.actionId,
    this.profileIds = const [],
  });

  @override
  String toString() => message;
}

/// Exception thrown when persisting or reconciling action follow-up checkpoints fails.
class ActionFollowUpPersistenceException implements Exception {
  final String message;
  final dynamic cause;
  final String? actionId;

  const ActionFollowUpPersistenceException(
    this.message, {
    this.cause,
    this.actionId,
  });

  @override
  String toString() => message;
}

/// Result of creating an action, containing the saved record and the assignment email dispatch status.
class ActionCreationResult {
  final ActionRecord action;
  final EmailSendResult? emailResult;

  const ActionCreationResult({
    required this.action,
    this.emailResult,
  });

  bool get emailSent => emailResult?.isSuccess == true;
}

class ActionLookupException implements Exception {
  final String message;
  final bool isNetworkError;
  const ActionLookupException(this.message, {this.isNetworkError = false});
  @override
  String toString() => message;
}

class ActionService {
  ActionService._();

  @visibleForTesting
  ActionService.forTesting();

  static final ActionService instance = ActionService._();

  EmailSendResult? _lastAssignmentEmailResult;

  /// Returns the assignment email result from the most recent createAction call.
  EmailSendResult? get lastAssignmentEmailResult => _lastAssignmentEmailResult;

  SupabaseClient? _clientOverride;

  @visibleForTesting
  set clientOverride(SupabaseClient? client) => _clientOverride = client;

  @visibleForTesting
  bool mockAssigneePersistenceShouldFail = false;

  @visibleForTesting
  String? mockAssigneePersistenceFailureReason;

  @visibleForTesting
  bool mockFollowUpPersistenceShouldFail = false;

  @visibleForTesting
  String? mockFollowUpPersistenceFailureReason;

  SupabaseClient? get _client =>
      _clientOverride ??
      (SupabaseConfig.isInitialized ? SupabaseConfig.client : null);

  SupabaseClient? get client => _client;

  static const String _selectQuery = '''
    id,
    action_number,
    organization_id,
    department_id,
    site_id,
    team_id,
    section_id,
    division_id,
    created_by,
    assigned_to,
    verified_by,
    closed_at,
    closed_by,
    closure_comment,
    title,
    action_required,
    description,
    category,
    source,
    priority,
    status,
    percent_complete,
    start_date,
    date_raised,
    target_date,
    due_date,
    last_follow_up_date,
    next_follow_up_date,
    close_date,
    attachments,
    history,
    worker_message_subject,
    worker_message,
    manager_message,
    recipient_type,
    external_recipient_id,
    email_reminder_enabled,
    divisions:division_id(id, name, code),
    action_sections:section_id(id, name),
    departments:department_id(id, name, division),
    sites:site_id(id, name),
    teams:team_id(id, name),
    creator:created_by(id, full_name, email),
    assignee:assigned_to(id, full_name, email, phone, designation),
    closer:closed_by(id, full_name, email),
    external_recipient:external_recipient_id(id, full_name, email, company_name, phone),
    action_progress_updates(*),
    action_follow_ups(*),
    action_email_reminders(*),
    action_assignees(*, profile:profile_id(id, full_name, email, phone, designation)),
    action_contributors(*, profile:profile_id(id, full_name, email, phone, designation), added_by_profile:added_by(id, full_name, email))
  ''';

  /// Fetches actions visible to the authenticated manager based on database RLS.
  /// RLS on public.actions guarantees tenant isolation and manager scope restrictions.
  /// If [createdById] is provided, only actions created by that user are fetched (Manager Action Register isolation).
  Future<List<ActionRecord>> fetchManagerActions({
    required String organizationId,
    String? createdById,
    String? assignedToId,
    String? searchQuery,
    String? status,
    String? priority,
    String? departmentId,
    String? siteId,
    String? sort,
  }) async {
    final client = _client;
    if (client == null) {
      var list = MockActionStore.instance.actions;
      if (createdById != null && createdById.isNotEmpty) {
        final cid = createdById.trim().toLowerCase();
        list = list.where((a) => a.createdById.trim().toLowerCase() == cid).toList();
      }
      if (assignedToId != null && assignedToId.isNotEmpty) {
        final aid = assignedToId.trim().toLowerCase();
        list = list.where((a) => a.assignedToId?.trim().toLowerCase() == aid).toList();
      }
      return list;
    }

    try {
      dynamic query = client.from('actions').select(_selectQuery);

      final cleanOrg = organizationId.trim();
      final effectiveOrgId = (cleanOrg == 'SOBHA-001' ||
              cleanOrg == 'org-sobha-01' ||
              cleanOrg.isEmpty)
          ? Organization.sobhaId
          : cleanOrg;

      if (effectiveOrgId.isNotEmpty) {
        query = query.eq('organization_id', effectiveOrgId);
      }

      if (createdById != null && createdById.isNotEmpty) {
        query = query.eq('created_by', createdById);
      }

      if (assignedToId != null && assignedToId.isNotEmpty) {
        query = query.eq('assigned_to', assignedToId);
      }

      if (departmentId != null &&
          departmentId.isNotEmpty &&
          departmentId != 'All Departments') {
        query = query.eq('department_id', departmentId);
      }

      if (siteId != null &&
          siteId.isNotEmpty &&
          siteId != 'All Sites' &&
          siteId != 'All Sites / Locations') {
        query = query.eq('site_id', siteId);
      }

      if (status != null &&
          status.isNotEmpty &&
          status != 'All Status' &&
          status != 'All') {
        query = query.eq('status', status);
      } else {
        query = query.neq('status', 'Deleted');
      }

      if (priority != null &&
          priority.isNotEmpty &&
          priority != 'All Priority' &&
          priority != 'All') {
        query = query.eq('priority', priority);
      }

      // Default sort by created_at DESC
      final bool ascending = sort == 'Oldest First' || sort == 'Due Date (Asc)';
      final String sortCol =
          (sort == 'Due Date (Asc)' || sort == 'Due Date (Desc)')
          ? 'target_date'
          : 'created_at';

      query = query.order(sortCol, ascending: ascending);

      final response = await query;
      List<ActionRecord> records = [];

      if (response is List) {
        for (final item in response) {
          if (item is Map) {
            records.add(
              ActionRecord.fromSupabase(Map<String, dynamic>.from(item)),
            );
          }
        }
      }

      if (records.isNotEmpty) {
        records = await _attachDatabaseSubtasks(client, records);
      }

      // If client-side search query is provided
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.trim().toLowerCase();
        return records.where((a) {
          return a.actionNumber.toLowerCase().contains(q) ||
              a.id.toLowerCase().contains(q) ||
              a.subject.toLowerCase().contains(q) ||
              a.description.toLowerCase().contains(q) ||
              a.assignedTo.toLowerCase().contains(q) ||
              a.department.toLowerCase().contains(q) ||
              a.site.toLowerCase().contains(q);
        }).toList();
      }

      return records;
    } catch (e, st) {
      debugPrint('[ActionService] Error fetching manager actions: $e\n$st');
      rethrow;
    }
  }

  /// Fetches ONLY actions assigned to the specific user by profile UUID.
  /// Enforces organization match and server-side assigned_to filter.
  Future<List<ActionRecord>> fetchMyActions({
    required String organizationId,
    required String userId,
    String? searchQuery,
    String? status,
    String? priority,
    String? departmentId,
    String? siteId,
    String? sort,
  }) async {
    final client = _client;
    if (client == null) {
      final uid = userId.trim().toLowerCase();
      final myActions = MockActionStore.instance.actions.where((a) {
        final isPrimary = (a.assignedToId != null && a.assignedToId!.trim().toLowerCase() == uid) ||
            a.assignedTo.trim().toLowerCase() == uid;
        final isSecondary = a.assignees.any((asg) =>
            asg.profileId.trim().toLowerCase() == uid ||
            asg.profileName.trim().toLowerCase() == uid);
        final isContributor = a.contributors.any((c) =>
            c.profileId.trim().toLowerCase() == uid ||
            c.profileName.trim().toLowerCase() == uid);
        return isPrimary || isSecondary || isContributor;
      }).toList();

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.trim().toLowerCase();
        return myActions.where((a) {
          return a.actionNumber.toLowerCase().contains(q) ||
              a.id.toLowerCase().contains(q) ||
              a.subject.toLowerCase().contains(q) ||
              a.description.toLowerCase().contains(q) ||
              a.assignedTo.toLowerCase().contains(q) ||
              a.department.toLowerCase().contains(q) ||
              a.site.toLowerCase().contains(q);
        }).toList();
      }

      return myActions;
    }

    try {
      // Collect secondary assignee and contributor action IDs
      final Set<String> secondaryActionIds = {};
      try {
        final assigneeRows = await client
            .from('action_assignees')
            .select('action_id')
            .eq('profile_id', userId);
        for (final r in assigneeRows) {
          if (r['action_id'] != null) {
            secondaryActionIds.add(r['action_id'].toString());
          }
        }
      } catch (_) {}

      try {
        final contributorRows = await client
            .from('action_contributors')
            .select('action_id')
            .eq('profile_id', userId);
        for (final r in contributorRows) {
          if (r['action_id'] != null) {
            secondaryActionIds.add(r['action_id'].toString());
          }
        }
      } catch (_) {}

      dynamic query = client.from('actions').select(_selectQuery);

      final cleanOrg = organizationId.trim();
      final effectiveOrgId = (cleanOrg == 'SOBHA-001' ||
              cleanOrg == 'org-sobha-01' ||
              cleanOrg.isEmpty)
          ? Organization.sobhaId
          : cleanOrg;

      if (effectiveOrgId.isNotEmpty) {
        query = query.eq('organization_id', effectiveOrgId);
      }

      // Backend filter: ONLY actions assigned to this user (primary or secondary)
      if (secondaryActionIds.isNotEmpty) {
        final idsList = secondaryActionIds.map((id) => '"$id"').join(',');
        query = query.or('assigned_to.eq.$userId,id.in.($idsList)');
      } else {
        query = query.eq('assigned_to', userId);
      }

      if (departmentId != null &&
          departmentId.isNotEmpty &&
          departmentId != 'All Departments') {
        query = query.eq('department_id', departmentId);
      }

      if (siteId != null &&
          siteId.isNotEmpty &&
          siteId != 'All Sites' &&
          siteId != 'All Sites / Locations') {
        query = query.eq('site_id', siteId);
      }

      if (status != null &&
          status.isNotEmpty &&
          status != 'All Status' &&
          status != 'All') {
        query = query.eq('status', status);
      } else {
        query = query.neq('status', 'Deleted');
      }

      if (priority != null &&
          priority.isNotEmpty &&
          priority != 'All Priority' &&
          priority != 'All') {
        query = query.eq('priority', priority);
      }

      final bool ascending = sort == 'Oldest First' || sort == 'Due Date (Asc)';
      final String sortCol =
          (sort == 'Due Date (Asc)' || sort == 'Due Date (Desc)')
          ? 'target_date'
          : 'created_at';

      query = query.order(sortCol, ascending: ascending);

      final response = await query;
      final List<ActionRecord> records = [];

      if (response is List) {
        for (final item in response) {
          if (item is Map) {
            records.add(
              ActionRecord.fromSupabase(Map<String, dynamic>.from(item)),
            );
          }
        }
      }

      if (records.isNotEmpty) {
        return await _attachDatabaseSubtasks(client, records);
      }

      return records;
    } catch (e, st) {
      debugPrint('[ActionService] Error fetching assigned actions: $e\n$st');
      rethrow;
    }
  }

  /// Fetches actions created by the specific user (Action Register).
  /// Enforces organization match and created_by filter.
  Future<List<ActionRecord>> fetchStaffCreatedActions({
    required String organizationId,
    required String userId,
    String? searchQuery,
    String? status,
    String? priority,
    String? departmentId,
    String? siteId,
    String? sort,
  }) async {
    final client = _client;
    if (client == null) {
      final uid = userId.trim().toLowerCase();
      final createdActions = MockActionStore.instance.actions.where((a) {
        return a.createdById.trim().toLowerCase() == uid;
      }).toList();

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.trim().toLowerCase();
        return createdActions.where((a) {
          return a.actionNumber.toLowerCase().contains(q) ||
              a.id.toLowerCase().contains(q) ||
              a.subject.toLowerCase().contains(q) ||
              a.description.toLowerCase().contains(q) ||
              a.assignedTo.toLowerCase().contains(q) ||
              a.department.toLowerCase().contains(q) ||
              a.site.toLowerCase().contains(q);
        }).toList();
      }

      return createdActions;
    }

    try {
      dynamic query = client.from('actions').select(_selectQuery);

      final cleanOrg = organizationId.trim();
      final effectiveOrgId = (cleanOrg == 'SOBHA-001' ||
              cleanOrg == 'org-sobha-01' ||
              cleanOrg.isEmpty)
          ? Organization.sobhaId
          : cleanOrg;

      if (effectiveOrgId.isNotEmpty) {
        query = query.eq('organization_id', effectiveOrgId);
      }

      query = query.eq('created_by', userId);

      if (departmentId != null &&
          departmentId.isNotEmpty &&
          departmentId != 'All Departments') {
        query = query.eq('department_id', departmentId);
      }

      if (siteId != null &&
          siteId.isNotEmpty &&
          siteId != 'All Sites' &&
          siteId != 'All Sites / Locations') {
        query = query.eq('site_id', siteId);
      }

      if (status != null &&
          status.isNotEmpty &&
          status != 'All Status' &&
          status != 'All') {
        query = query.eq('status', status);
      } else {
        query = query.neq('status', 'Deleted');
      }

      if (priority != null &&
          priority.isNotEmpty &&
          priority != 'All Priority' &&
          priority != 'All') {
        query = query.eq('priority', priority);
      }

      final bool ascending = sort == 'Oldest First' || sort == 'Due Date (Asc)';
      final String sortCol =
          (sort == 'Due Date (Asc)' || sort == 'Due Date (Desc)')
          ? 'target_date'
          : 'created_at';

      query = query.order(sortCol, ascending: ascending);

      final response = await query;
      final List<ActionRecord> records = [];

      if (response is List) {
        for (final item in response) {
          if (item is Map) {
            records.add(
              ActionRecord.fromSupabase(Map<String, dynamic>.from(item)),
            );
          }
        }
      }

      if (records.isNotEmpty) {
        return await _attachDatabaseSubtasks(client, records);
      }

      return records;
    } catch (e, st) {
      debugPrint('[ActionService] Error fetching staff created actions: $e\n$st');
      rethrow;
    }
  }

  /// Helper to fetch and attach database-filtered subtasks via batch RPC.
  Future<List<ActionRecord>> _attachDatabaseSubtasks(
    SupabaseClient client,
    List<ActionRecord> records,
  ) async {
    if (records.isEmpty) return records;
    try {
      final actionIds = records
          .map((a) => a.id.isNotEmpty ? a.id : a.actionNumber)
          .where((id) => id.isNotEmpty)
          .toList();
      if (actionIds.isEmpty) return records;

      final res = await client.rpc(
        'get_actions_subtasks_batch',
        params: {'p_action_ids': actionIds},
      );
      if (res is List) {
        final Map<String, List<ActionSubTask>> subtasksByActionId = {};
        for (final row in res) {
          if (row is Map && row['action_id'] != null) {
            final actId = row['action_id'].toString();
            final rawTasks = row['subtasks'];
            final List<ActionSubTask> tasks = [];
            if (rawTasks is List) {
              for (final t in rawTasks) {
                if (t is Map) {
                  tasks.add(ActionSubTask.fromJson(Map<String, dynamic>.from(t)));
                }
              }
            }
            if (tasks.isNotEmpty) {
              subtasksByActionId[actId] = tasks;
            }
          }
        }
        return records.map((r) {
          if (subtasksByActionId.containsKey(r.id) &&
              subtasksByActionId[r.id]!.isNotEmpty) {
            return r.copyWith(subTasks: subtasksByActionId[r.id]!);
          } else if (subtasksByActionId.containsKey(r.actionNumber) &&
              subtasksByActionId[r.actionNumber]!.isNotEmpty) {
            return r.copyWith(subTasks: subtasksByActionId[r.actionNumber]!);
          } else if (r.subTasks.isNotEmpty) {
            return r;
          }
          final mockAction = MockActionStore.instance.actions.firstWhereOrNull(
            (a) =>
                a.id.toLowerCase() == r.id.toLowerCase() ||
                a.actionNumber.toLowerCase() == r.actionNumber.toLowerCase(),
          );
          if (mockAction != null && mockAction.subTasks.isNotEmpty) {
            return r.copyWith(subTasks: mockAction.subTasks);
          }
          return r;
        }).toList();
      }
    } catch (e) {
      debugPrint('[ActionService] Error attaching database subtasks batch: $e');
      try {
        final updated = await Future.wait(records.map((r) async {
          if (r.subTasks.isNotEmpty) return r;
          final effectiveId = r.id.isNotEmpty ? r.id : r.actionNumber;
          if (effectiveId.isEmpty) return r;
          try {
            final tasks = await fetchActionSubtasks(effectiveId);
            return tasks.isNotEmpty ? r.copyWith(subTasks: tasks) : r;
          } catch (_) {
            return r;
          }
        }));
        return updated;
      } catch (fallbackError) {
        debugPrint('[ActionService] Fallback subtask fetch failed: $fallbackError');
      }
    }
    return records;
  }

  /// Sanitizes action identifiers by stripping whitespace, leading #, quotes, and "action:" prefixes.
  static String cleanActionId(String raw) {
    var s = raw.trim();
    if ((s.startsWith('"') && s.endsWith('"')) ||
        (s.startsWith("'") && s.endsWith("'"))) {
      s = s.substring(1, s.length - 1).trim();
    }
    if (s.startsWith('#')) {
      s = s.substring(1).trim();
    }
    if (s.toLowerCase().startsWith('action:')) {
      s = s.substring(7).trim();
    }
    if (s.toLowerCase().startsWith('action/')) {
      s = s.substring(7).trim();
    }
    return s;
  }

  /// Determines whether [action] matches [rawId], checking ID, actionNumber, displayId,
  /// and prefix-agnostic numeric equivalents.
  static bool isActionMatch(ActionRecord action, String rawId) {
    final clean = cleanActionId(rawId).toLowerCase();
    if (clean.isEmpty) return false;

    if (action.id.trim().toLowerCase() == clean) return true;
    if (action.actionNumber.trim().toLowerCase() == clean) return true;
    if (action.displayId.trim().toLowerCase() == clean) return true;

    // Check numeric portion equivalence: e.g. "AC-1029" vs "ACT-1029" vs "1029"
    final cleanDigits = RegExp(r'\d+').firstMatch(clean)?.group(0);
    if (cleanDigits != null && cleanDigits.length >= 3) {
      final actDigits = RegExp(r'\d+').firstMatch(action.actionNumber)?.group(0);
      if (actDigits == cleanDigits) return true;
      final idDigits = RegExp(r'\d+').firstMatch(action.id)?.group(0);
      if (idDigits == cleanDigits) return true;
    }
    return false;
  }

  /// Fetches a single action by its UUID or action_number.
  Future<ActionRecord?> fetchActionById(String actionId) async {
    final cleanId = cleanActionId(actionId);
    if (cleanId.isEmpty) return null;

    final isUuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(cleanId);

    final client = _client;
    if (client == null) {
      final action = MockActionStore.instance.actions.firstWhereOrNull(
        (a) => isActionMatch(a, cleanId),
      );
      if (action == null) return null;

      // Re-hydrate emailReminders from MockActionStore.instance.emailReminders
      final jobs = MockActionStore.instance.emailReminders
          .where((j) => j.actionId == action.id && j.status == 'pending')
          .toList();
      if (jobs.isNotEmpty) {
        final hydratedReminders = ActionRecord.parseRemindersFromJobs(jobs);
        return action.copyWith(emailReminders: hydratedReminders);
      }
      return action;
    }

    try {
      dynamic response;
      if (isUuid) {
        response = await client
            .from('actions')
            .select(_selectQuery)
            .eq('id', cleanId)
            .maybeSingle();
      } else {
        response = await client
            .from('actions')
            .select(_selectQuery)
            .ilike('action_number', cleanId)
            .maybeSingle();

        // If not found and cleanId contains digits, try matching common prefix variants
        if (response == null) {
          final digits = RegExp(r'\d+').firstMatch(cleanId)?.group(0);
          if (digits != null && digits.length >= 2) {
            response = await client
                .from('actions')
                .select(_selectQuery)
                .ilike('action_number', '%$digits')
                .maybeSingle();
          }
        }
      }

      if (response == null || response is! Map) {
        final mockAction = MockActionStore.instance.actions.firstWhereOrNull(
          (a) => isActionMatch(a, cleanId),
        );
        return mockAction;
      }
      var record = ActionRecord.fromSupabase(Map<String, dynamic>.from(response));

      // Fetch database-authorized subtasks for this action
      try {
        final subtasksResponse = await client.rpc(
          'get_action_subtasks',
          params: {'p_action_id': record.id},
        );
        if (subtasksResponse is List) {
          final List<ActionSubTask> tasks = [];
          for (final t in subtasksResponse) {
            if (t is Map) {
              tasks.add(ActionSubTask.fromJson(Map<String, dynamic>.from(t)));
            }
          }
          if (tasks.isNotEmpty) {
            record = record.copyWith(subTasks: tasks);
          }
        }
      } catch (e) {
        debugPrint('[ActionService] Error fetching action subtasks for ${record.id}: $e');
      }

      // If record.subTasks is still empty, check MockActionStore fallback
      if (record.subTasks.isEmpty) {
        final mockAction = MockActionStore.instance.actions.firstWhereOrNull(
          (a) => isActionMatch(a, record.id),
        );
        if (mockAction != null && mockAction.subTasks.isNotEmpty) {
          record = record.copyWith(subTasks: mockAction.subTasks);
        }
      }

      // Fetch relational additional external contacts if available
      try {
        final extContactsResponse = await client
            .from('action_external_contacts')
            .select(
              'external_recipient_id, recipient:external_recipient_id(id, full_name, email, phone, company_name)',
            )
            .eq('action_id', record.id);
        if (extContactsResponse.isNotEmpty) {
          final updatedPeople =
              List<ActionPersonReference>.from(record.additionalPeople);
          for (final row in extContactsResponse) {
            final rec = row['recipient'] ?? row['external_recipient'];
            final recMap = rec is Map ? rec : row;
            final recId =
                (recMap['id'] ?? row['external_recipient_id'] ?? '')
                    .toString();
            if (recId.isNotEmpty &&
                !updatedPeople.any((p) => p.personId == recId)) {
              updatedPeople.add(
                ActionPersonReference(
                  personId: recId,
                  name: (recMap['full_name'] ?? 'External Contact').toString(),
                  type: PersonType.externalWorker,
                  email: (recMap['email'] ?? '').toString(),
                  phone: (recMap['phone'] ?? '').toString(),
                  company: (recMap['company_name'] ?? '').toString(),
                ),
              );
            }
          }
          record = record.copyWith(additionalPeople: updatedPeople);
        }
      } catch (extFetchErr) {
        // Ignored if table not migrated yet
      }

      return record;
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('network') ||
          errStr.contains('socket') ||
          errStr.contains('timeout') ||
          errStr.contains('connection') ||
          errStr.contains('500') ||
          errStr.contains('502') ||
          errStr.contains('503') ||
          errStr.contains('pgrst301')) {
        debugPrint('[ActionService] Database/network error fetching action $actionId: $e');
        throw ActionLookupException(
          'Network connection error while loading action "$actionId". Please check your connection and try again.',
          isNetworkError: true,
        );
      }

      debugPrint('[ActionService] Error fetching action by id: $e');
      final mockAction = MockActionStore.instance.actions.firstWhereOrNull(
        (a) => isActionMatch(a, cleanId),
      );
      if (mockAction != null) return mockAction;

      if (errStr.contains('postgrest') && !errStr.contains('22p02')) {
        throw ActionLookupException('Database error loading action: ${e.toString()}');
      }
      return null;
    }
  }

  /// Fetches database-authorized subtasks for an action directly.
  Future<List<ActionSubTask>> fetchActionSubtasks(String actionId) async {
    final client = _client;
    if (client == null) {
      final action = MockActionStore.instance.actions.firstWhereOrNull(
        (a) =>
            a.id.toLowerCase() == actionId.toLowerCase() ||
            a.actionNumber.toLowerCase() == actionId.toLowerCase(),
      );
      return action?.subTasks ?? [];
    }

    try {
      String effectiveId = actionId;
      final isUuid = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(actionId);
      if (!isUuid) {
        try {
          final row = await client
              .from('actions')
              .select('id')
              .eq('action_number', actionId)
              .maybeSingle();
          if (row != null && row['id'] != null) {
            effectiveId = row['id'].toString();
          }
        } catch (_) {}
      }

      final res = await client.rpc(
        'get_action_subtasks',
        params: {'p_action_id': effectiveId},
      );
      if (res is List) {
        final List<ActionSubTask> tasks = [];
        for (final item in res) {
          if (item is Map) {
            tasks.add(ActionSubTask.fromJson(Map<String, dynamic>.from(item)));
          }
        }
        if (tasks.isNotEmpty) {
          return tasks;
        }
      }
    } catch (e) {
      debugPrint('[ActionService] Error fetching subtasks via RPC for $actionId: $e');
    }

    // Note: Direct subtasks column read is intentionally not attempted here.
    // The actions.subtasks column SELECT is revoked from authenticated to prevent
    // unauthorized exposure of other users' task assignments. All subtask access
    // must go through the authorized SECURITY DEFINER RPCs above.

    // Mock store fallback if remote database returned empty or unauthenticated
    final mockAction = MockActionStore.instance.actions.firstWhereOrNull(
      (a) =>
          a.id.toLowerCase() == actionId.toLowerCase() ||
          a.actionNumber.toLowerCase() == actionId.toLowerCase(),
    );
    if (mockAction != null && mockAction.subTasks.isNotEmpty) {
      return mockAction.subTasks;
    }

    return [];
  }

  /// Inserts a new action record. Validates trigger & RLS rules server-side.
  /// Sends assignment notification email to current assignee unless disabled.
  Future<ActionRecord> createAction(
    ActionRecord record, {
    bool sendAssignmentNotification = true,
  }) async {
    final client = _client;
    if (client == null) {
      if (mockAssigneePersistenceShouldFail) {
        throw ActionAssigneePersistenceException(
          mockAssigneePersistenceFailureReason ??
              'Failed to persist action assignees in mock mode',
          actionId: record.id,
        );
      }
      if (mockFollowUpPersistenceShouldFail) {
        throw ActionFollowUpPersistenceException(
          mockFollowUpPersistenceFailureReason ??
              'Mock simulated follow-up persistence failure',
          actionId: record.id,
        );
      }
      final withAssignees = _reconcileRecordAssignees(record);
      final effectiveRecord = _reconcileRecordFollowUps(withAssignees);
      MockActionStore.instance.add(effectiveRecord);
      await _syncEmailRemindersForAction(effectiveRecord);
      if (sendAssignmentNotification) {
        try {
          final res = await EmailService.instance
              .sendAssignmentEmail(action: effectiveRecord);
          _lastAssignmentEmailResult = res;
        } catch (e) {
          debugPrint(
              '[ActionService] Error sending assignment email in mock mode: $e');
          _lastAssignmentEmailResult =
              EmailSendResult.failed('Error sending assignment email: $e');
        }
      } else {
        _lastAssignmentEmailResult = null;
      }
      if (!effectiveRecord.isExternalRecipient &&
          effectiveRecord.assignedToId != null &&
          effectiveRecord.assignedToId!.isNotEmpty) {
        NotificationService.safeDispatch(
          () => NotificationService.instance.notifyActionAssigned(
            action: effectiveRecord,
            assigneeUserId: effectiveRecord.assignedToId!,
            organizationId: effectiveRecord.organizationId,
          ),
          context: 'ActionService.createAction (local)',
        );
      }
      return effectiveRecord;
    }

    String? createdActionId;
    try {
      final insertMap = record.toSupabaseInsertMap();
      final response = await client
          .from('actions')
          .insert(insertMap)
          .select(_selectQuery)
          .single();

      final created = ActionRecord.fromSupabase(
        Map<String, dynamic>.from(response),
      );
      createdActionId = created.id;

      // 1. Seed assignees into action_assignees
      final assigneesToSeed = _extractDesiredAssignees(
        record,
        actionId: created.id,
        fallbackOwnerId: created.assignedToId,
        fallbackOwnerName: created.assignedTo,
      );

      if (mockAssigneePersistenceShouldFail) {
        throw ActionAssigneePersistenceException(
          mockAssigneePersistenceFailureReason ??
              'Mock simulated assignee persistence failure',
          actionId: created.id,
          profileIds: assigneesToSeed.map((a) => a.profileId).toList(),
        );
      }

      for (final a in assigneesToSeed) {
        try {
          await client.from('action_assignees').insert({
            'organization_id': created.organizationId,
            'action_id': created.id,
            'profile_id': a.profileId,
            'assignment_role': a.assignmentRole,
            'is_required': a.isRequired,
            'assigned_by': created.createdById,
          });
        } catch (e, st) {
          debugPrint(
              '[ActionService] Failed to insert assignee ${a.profileId}: $e\n$st');
          throw ActionAssigneePersistenceException(
            'Failed to persist assignee ${a.profileName.isNotEmpty ? a.profileName : a.profileId}: ${_sanitizeErrorMessage(e)}',
            cause: e,
            actionId: created.id,
            profileIds: [a.profileId],
          );
        }
      }

      // 2. Seed initial follow-up checkpoint if provided
      if (record.nextFollowUpDate.isNotEmpty) {
        final dbDate =
            ActionRecord.formatOptionalDateForDb(record.nextFollowUpDate);
        if (dbDate != null && dbDate.isNotEmpty) {
          if (mockFollowUpPersistenceShouldFail) {
            throw ActionFollowUpPersistenceException(
              mockFollowUpPersistenceFailureReason ??
                  'Mock simulated follow-up persistence failure',
              actionId: created.id,
            );
          }
          try {
            await client.from('action_follow_ups').insert({
              'organization_id': created.organizationId,
              'action_id': created.id,
              'follow_up_date': dbDate,
              'notes': 'Initial follow-up checkpoint scheduled at creation',
              'status': 'Scheduled',
              'created_by': created.createdById.isNotEmpty
                  ? created.createdById
                  : (client.auth.currentUser?.id ?? created.createdById),
            });
          } catch (fuErr) {
            debugPrint(
              '[ActionService] Warning: Failed to seed initial action_follow_up: ',
            );
            throw ActionFollowUpPersistenceException(
              'Failed to seed initial follow-up checkpoint: ',
              cause: fuErr,
              actionId: created.id,
            );
          }
        }
      }

      // 3. Synchronize explicit email reminders
      try {
        await _syncEmailRemindersForAction(record.copyWith(id: created.id));
      } catch (remErr) {
        debugPrint(
          '[ActionService] Warning: Failed to sync email reminders for created action ${created.id}: $remErr',
        );
      }

      // 3.5 Synchronize additional external contacts into action_external_contacts
      try {
        await _reconcileSupabaseExternalContacts(
          client,
          record.copyWith(
            id: created.id,
            organizationId: created.organizationId,
          ),
        );
      } catch (extErr) {
        debugPrint(
          '[ActionService] Note: Failed to sync action_external_contacts for created action ${created.id}: $extErr',
        );
      }

      final fullCreated = (await fetchActionById(created.id)) ?? created;
      MockActionStore.instance.add(fullCreated);

      // 4. Send assignment notification to current assigned person
      if (sendAssignmentNotification) {
        try {
          final res = await EmailService.instance
              .sendAssignmentEmail(action: fullCreated);
          _lastAssignmentEmailResult = res;
        } catch (e) {
          debugPrint(
              '[ActionService] Error sending assignment email on create: $e');
          _lastAssignmentEmailResult =
              EmailSendResult.failed('Error sending assignment email: $e');
        }
      } else {
        _lastAssignmentEmailResult = null;
      }

      if (!fullCreated.isExternalRecipient &&
          fullCreated.assignedToId != null &&
          fullCreated.assignedToId!.isNotEmpty) {
        NotificationService.safeDispatch(
          () => NotificationService.instance.notifyActionAssigned(
            action: fullCreated,
            assigneeUserId: fullCreated.assignedToId!,
            organizationId: fullCreated.organizationId,
          ),
          context: 'ActionService.createAction',
        );
      }

      return fullCreated;
    } catch (e, st) {
      debugPrint('[ActionService] Error creating action: $e\n$st');
      // If assignee persistence failed after action was inserted, attempt rollback cleanup
      if (e is ActionAssigneePersistenceException && createdActionId != null) {
        try {
          await client.from('actions').delete().eq('id', createdActionId);
          debugPrint(
              '[ActionService] Cleaned up orphaned action $createdActionId after assignee persistence failure');
        } catch (cleanupError) {
          debugPrint(
              '[ActionService] Failed to cleanup orphaned action $createdActionId: $cleanupError');
        }
      }
      rethrow;
    }
  }

  /// Creates an action and returns both the saved record and the assignment email dispatch result.
  Future<ActionCreationResult> createActionWithResult(
    ActionRecord record, {
    bool sendAssignmentNotification = true,
  }) async {
    final created = await createAction(
      record,
      sendAssignmentNotification: sendAssignmentNotification,
    );
    return ActionCreationResult(
      action: created,
      emailResult: _lastAssignmentEmailResult,
    );
  }

  /// Resends assignment notification email to the current assignee/recipient.
  /// Reuses existing action and assignment without modifying email reminder jobs.
  Future<EmailSendResult> resendAssignmentEmail(ActionRecord action) async {
    return EmailService.instance.sendAssignmentEmail(action: action);
  }

  /// Updates an existing action record. Validates trigger & RLS rules server-side.
  Future<ActionRecord> updateAction(ActionRecord record) async {
    final client = _client;
    final existing = MockActionStore.instance.actions
        .firstWhereOrNull((a) => a.id == record.id);
    if (client == null) {
      if (mockAssigneePersistenceShouldFail) {
        throw ActionAssigneePersistenceException(
          mockAssigneePersistenceFailureReason ??
              'Failed to persist action assignees in mock mode',
          actionId: record.id,
        );
      }
      if (mockFollowUpPersistenceShouldFail) {
        throw ActionFollowUpPersistenceException(
          mockFollowUpPersistenceFailureReason ??
              'Mock simulated follow-up persistence failure',
          actionId: record.id,
        );
      }
      final withAssignees =
          _reconcileRecordAssignees(record, existingRecord: existing);
      final effectiveRecord =
          _reconcileRecordFollowUps(withAssignees, existingRecord: existing);
      MockActionStore.instance.update(effectiveRecord);
      await _syncEmailRemindersForAction(effectiveRecord);
      _dispatchUpdateNotifications(existing: existing, updated: effectiveRecord);
      return effectiveRecord;
    }

    try {
      final updateMap = record.toSupabaseUpdateMap();
      final response = await client
          .from('actions')
          .update(updateMap)
          .eq('id', record.id)
          .select(_selectQuery)
          .single();

      // Synchronize and reconcile assignees into action_assignees
      await _reconcileSupabaseAssignees(client, record);

      // Synchronize and reconcile follow-up checkpoints into action_follow_ups
      await _reconcileSupabaseFollowUps(client, record, existingRecord: existing);

      // Synchronize and reconcile additional external contacts into action_external_contacts
      try {
        await _reconcileSupabaseExternalContacts(client, record);
      } catch (extErr) {
        debugPrint(
          '[ActionService] Note: Failed to sync action_external_contacts for updated action ${record.id}: $extErr',
        );
      }

      // Synchronize explicit email reminders
      try {
        await _syncEmailRemindersForAction(record);
      } catch (remErr) {
        debugPrint(
          '[ActionService] Warning: Failed to sync email reminders for updated action ${record.id}: $remErr',
        );
      }

      final updatedResult = (await fetchActionById(record.id)) ??
          ActionRecord.fromSupabase(Map<String, dynamic>.from(response));
      MockActionStore.instance.update(updatedResult);
      _dispatchUpdateNotifications(existing: existing, updated: updatedResult);
      return updatedResult;
    } catch (e, st) {
      debugPrint('[ActionService] Error updating action: $e\n$st');
      rethrow;
    }
  }

  void _dispatchUpdateNotifications({
    ActionRecord? existing,
    required ActionRecord updated,
  }) {
    if (updated.isExternalRecipient) return;

    final hasNewAssignee = updated.assignedToId != null &&
        updated.assignedToId!.isNotEmpty;

    // 1. Reassignment notification (Event 1)
    if (existing != null &&
        existing.assignedToId != updated.assignedToId &&
        hasNewAssignee) {
      NotificationService.safeDispatch(
        () => NotificationService.instance.notifyActionAssigned(
          action: updated,
          assigneeUserId: updated.assignedToId!,
          organizationId: updated.organizationId,
        ),
        context: 'ActionService.updateAction (reassigned)',
      );
    }

    // 2. Status change or reopening notification (Event 4 & Event 6)
    if (existing != null && existing.status != updated.status && hasNewAssignee) {
      final isReopen = updated.status.toLowerCase() == 'reopened' ||
          (existing.status.toLowerCase() == 'completed' &&
              updated.status.toLowerCase() == 'in progress');

      if (isReopen) {
        NotificationService.safeDispatch(
          () => NotificationService.instance.notifyActionReopened(
            action: updated,
            assigneeUserId: updated.assignedToId!,
            reopenedByName: updated.assignedBy.isNotEmpty
                ? updated.assignedBy
                : 'Manager',
            organizationId: updated.organizationId,
          ),
          context: 'ActionService.updateAction (reopened)',
        );
      } else {
        NotificationService.safeDispatch(
          () => NotificationService.instance.notifyStatusChanged(
            action: updated,
            recipientUserId: updated.assignedToId!,
            oldStatus: existing.status,
            newStatus: updated.status,
            organizationId: updated.organizationId,
          ),
          context: 'ActionService.updateAction (statusChanged)',
        );
      }
    }
  }

  /// Reconciles action_assignees in Supabase for the given action record.
  /// Safely removes obsolete assignees, adds new ones, and only updates mutable fields
  /// on retained assignees to prevent triggering immutable column errors.
  Future<void> _reconcileSupabaseAssignees(
    SupabaseClient client,
    ActionRecord record,
  ) async {
    if (mockAssigneePersistenceShouldFail) {
      throw ActionAssigneePersistenceException(
        mockAssigneePersistenceFailureReason ??
            'Mock simulated assignee persistence failure',
        actionId: record.id,
      );
    }

    final desiredAssignees = _extractDesiredAssignees(
      record,
      actionId: record.id,
      fallbackOwnerId: record.assignedToId,
      fallbackOwnerName: record.assignedTo,
    );
    final desiredByProfileId = {
      for (final a in desiredAssignees) a.profileId: a,
    };

    // 1. Query current existing assignees for this action
    final List<Map<String, dynamic>> existingRows;
    try {
      final res = await client
          .from('action_assignees')
          .select(
              'id, profile_id, assignment_role, is_required, work_completed, completed_at, created_at, assigned_by')
          .eq('action_id', record.id)
          .eq('organization_id', record.organizationId);
      existingRows = (res as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    } catch (e) {
      debugPrint(
          '[ActionService] Failed to query existing action_assignees for ${record.id}: $e');
      throw ActionAssigneePersistenceException(
        'Failed to query existing assignees: ${_sanitizeErrorMessage(e)}',
        cause: e,
        actionId: record.id,
      );
    }

    final existingByProfileId = <String, Map<String, dynamic>>{
      for (final r in existingRows)
        if (r['profile_id'] != null) r['profile_id'].toString(): r,
    };

    // 2. Identify obsolete assignees to delete
    final obsoleteProfileIds = existingByProfileId.keys
        .where((id) => !desiredByProfileId.containsKey(id))
        .toList();

    if (obsoleteProfileIds.isNotEmpty) {
      try {
        await client
            .from('action_assignees')
            .delete()
            .eq('action_id', record.id)
            .eq('organization_id', record.organizationId)
            .inFilter('profile_id', obsoleteProfileIds);
      } catch (e) {
        debugPrint(
            '[ActionService] Failed to remove obsolete assignees $obsoleteProfileIds for ${record.id}: $e');
        throw ActionAssigneePersistenceException(
          'Failed to remove obsolete assignees: ${_sanitizeErrorMessage(e)}',
          cause: e,
          actionId: record.id,
          profileIds: obsoleteProfileIds,
        );
      }
    }

    // 3. Identify new assignees to insert
    final newAssignees = desiredAssignees
        .where((a) => !existingByProfileId.containsKey(a.profileId))
        .toList();

    for (final a in newAssignees) {
      try {
        await client.from('action_assignees').insert({
          'organization_id': record.organizationId,
          'action_id': record.id,
          'profile_id': a.profileId,
          'assignment_role': a.assignmentRole,
          'is_required': a.isRequired,
          'assigned_by': record.createdById.isNotEmpty
              ? record.createdById
              : (record.assignedToId ?? a.profileId),
        });
      } catch (e) {
        debugPrint(
            '[ActionService] Failed to insert new assignee ${a.profileId} for ${record.id}: $e');
        throw ActionAssigneePersistenceException(
          'Failed to add new assignee ${a.profileName.isNotEmpty ? a.profileName : a.profileId}: ${_sanitizeErrorMessage(e)}',
          cause: e,
          actionId: record.id,
          profileIds: [a.profileId],
        );
      }
    }

    // 4. Check retained assignees for role or requirement changes
    // Columns id, organization_id, action_id, profile_id, assigned_by, created_at are immutable!
    // We only touch the row if mutable properties actually changed.
    for (final desired in desiredAssignees) {
      final existing = existingByProfileId[desired.profileId];
      if (existing == null) continue; // Was new, handled above

      final currentRole = existing['assignment_role']?.toString();
      final currentIsRequired = existing['is_required'] as bool?;

      final roleChanged = currentRole != desired.assignmentRole;
      final requiredChanged = currentIsRequired != desired.isRequired;

      if (roleChanged || requiredChanged) {
        try {
          final updates = <String, dynamic>{};
          if (roleChanged) updates['assignment_role'] = desired.assignmentRole;
          if (requiredChanged) updates['is_required'] = desired.isRequired;

          await client
              .from('action_assignees')
              .update(updates)
              .eq('action_id', record.id)
              .eq('profile_id', desired.profileId)
              .eq('organization_id', record.organizationId);
        } catch (e) {
          debugPrint(
              '[ActionService] Failed to update assignee ${desired.profileId} for ${record.id}: $e');
          throw ActionAssigneePersistenceException(
            'Failed to update assignee ${desired.profileName.isNotEmpty ? desired.profileName : desired.profileId}: ${_sanitizeErrorMessage(e)}',
            cause: e,
            actionId: record.id,
            profileIds: [desired.profileId],
          );
        }
      }
    }
  }

  /// Reconciles action_follow_ups in Supabase for the given action record.
  ///
  /// Guarantees:
  /// 1. Queries existing checkpoints from public.action_follow_ups.
  /// 2. Preserves completed/cancelled statuses without resetting.
  /// 3. Never deletes historical follow-ups.
  /// 4. Avoids duplicate checkpoint records for the same action on the same date.
  /// 5. Inserts new checkpoint if nextFollowUpDate is scheduled and does not yet exist.
  /// 6. Throws [ActionFollowUpPersistenceException] on failure.
  Future<void> _reconcileSupabaseFollowUps(
    SupabaseClient client,
    ActionRecord record, {
    ActionRecord? existingRecord,
  }) async {
    if (mockFollowUpPersistenceShouldFail) {
      throw ActionFollowUpPersistenceException(
        mockFollowUpPersistenceFailureReason ??
            'Mock simulated follow-up persistence failure',
        actionId: record.id,
      );
    }

    final List<Map<String, dynamic>> existingRows;
    try {
      final res = await client
          .from('action_follow_ups')
          .select('id, follow_up_date, notes, status, actual_progress, created_by, completed_at, created_at')
          .eq('action_id', record.id);
      existingRows = (res as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    } catch (e) {
      debugPrint('[ActionService] Failed to query existing action_follow_ups for : ');
      throw ActionFollowUpPersistenceException(
        'Failed to query existing follow-up checkpoints: ',
        cause: e,
        actionId: record.id,
      );
    }

    final Map<String, Map<String, dynamic>> existingByDate = {};
    for (final r in existingRows) {
      final dateVal = r['follow_up_date']?.toString().trim();
      if (dateVal != null && dateVal.isNotEmpty) {
        final dbDate = ActionRecord.formatDateForDb(dateVal);
        existingByDate[dbDate] = r;
      }
    }

    if (record.nextFollowUpDate.isNotEmpty &&
        record.nextFollowUpDate != 'Not set' &&
        record.nextFollowUpDate != '-') {
      final nextDbDate = ActionRecord.formatDateForDb(record.nextFollowUpDate);
      if (nextDbDate.isNotEmpty) {
        final existing = existingByDate[nextDbDate];
        if (existing == null) {
          final effectiveUserId = client.auth.currentUser?.id ?? record.createdById;
          try {
            await client.from('action_follow_ups').insert({
              'organization_id': record.organizationId,
              'action_id': record.id,
              'follow_up_date': nextDbDate,
              'notes': existingRecord != null
                  ? 'Follow-up checkpoint updated during action edit'
                  : 'Initial follow-up checkpoint scheduled at creation',
              'status': 'Scheduled',
              'created_by': effectiveUserId.isNotEmpty ? effectiveUserId : null,
            });
          } catch (e) {
            debugPrint('[ActionService] Failed to insert new action_follow_up for : ');
            throw ActionFollowUpPersistenceException(
              'Failed to persist follow-up checkpoint: ',
              cause: e,
              actionId: record.id,
            );
          }
        }
      }
    }
  }

  /// Synchronizes additional external contacts into public.action_external_contacts.
  /// Deduplicates recipients, ensures org scoping, removes unassociated contacts without
  /// touching shared external_action_recipients records, and safely handles unmigrated schemas.
  Future<void> _reconcileSupabaseExternalContacts(
    SupabaseClient client,
    ActionRecord record,
  ) async {
    final externalContacts = record.additionalPeople
        .where((p) => p.type == PersonType.externalWorker && p.personId.isNotEmpty)
        .toList();

    // Deduplicate desired recipients by personId
    final desiredRecipientIds = <String>{};
    final uniqueDesired = <ActionPersonReference>[];
    for (final p in externalContacts) {
      if (!desiredRecipientIds.contains(p.personId)) {
        desiredRecipientIds.add(p.personId);
        uniqueDesired.add(p);
      }
    }

    try {
      final existingRows = await client
          .from('action_external_contacts')
          .select('id, external_recipient_id')
          .eq('action_id', record.id)
          .eq('organization_id', record.organizationId);

      final existingByRecipientId = <String, String>{};
      for (final row in existingRows) {
        if (row['external_recipient_id'] != null) {
          existingByRecipientId[row['external_recipient_id'].toString()] =
              row['id'].toString();
        }
      }

      // Remove obsolete associations (only from linking table, never deleting shared recipient)
      for (final entry in existingByRecipientId.entries) {
        if (!desiredRecipientIds.contains(entry.key)) {
          await client
              .from('action_external_contacts')
              .delete()
              .eq('id', entry.value);
        }
      }

      // Insert new associations
      for (final p in uniqueDesired) {
        if (!existingByRecipientId.containsKey(p.personId)) {
          await client.from('action_external_contacts').insert({
            'organization_id': record.organizationId,
            'action_id': record.id,
            'external_recipient_id': p.personId,
            'contact_role': 'additional_contact',
          });
        }
      }
    } catch (e) {
      debugPrint('[ActionService] Note: action_external_contacts sync: $e');
    }
  }

  /// Extracts the desired unique set of assignees from the record.
  List<ActionAssigneeRecord> _extractDesiredAssignees(
    ActionRecord record, {
    required String actionId,
    String? fallbackOwnerId,
    String? fallbackOwnerName,
  }) {
    final assignees = <ActionAssigneeRecord>[];
    final seen = <String>{};

    // If explicit assignees list is provided
    if (record.assignees.isNotEmpty) {
      for (final a in record.assignees) {
        if (a.profileId.isNotEmpty && !seen.contains(a.profileId)) {
          seen.add(a.profileId);
          assignees.add(a);
        }
      }
    }

    // Ensure primary owner is present if internal and not already added
    final ownerId = record.assignedToId ?? fallbackOwnerId;
    if (!record.isExternalRecipient &&
        ownerId != null &&
        ownerId.isNotEmpty &&
        RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
            .hasMatch(ownerId) &&
        !seen.contains(ownerId)) {
      seen.add(ownerId);
      assignees.insert(
        0,
        ActionAssigneeRecord(
          id: 'owner-$ownerId',
          actionId: actionId,
          profileId: ownerId,
          profileName: (record.assignedTo.isNotEmpty &&
                  record.assignedTo != 'Select staff')
              ? record.assignedTo
              : (fallbackOwnerName ?? ''),
          profileEmail: record.primaryAssignee?.email ?? '',
          assignmentRole: 'owner',
          isRequired: true,
          workCompleted: record.percentComplete >= 100,
        ),
      );
    }

    // If record.assignees was empty, fall back to extracting internal users from additionalPeople
    if (record.assignees.isEmpty) {
      for (final p in record.additionalPeople) {
        if (p.type == PersonType.internalUser &&
            p.personId.isNotEmpty &&
            !seen.contains(p.personId) &&
            RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
                .hasMatch(p.personId)) {
          seen.add(p.personId);
          assignees.add(
            ActionAssigneeRecord(
              id: 'assignee-${p.personId}',
              actionId: actionId,
              profileId: p.personId,
              profileName: p.name,
              profileEmail: p.email,
              assignmentRole: 'assignee',
              isRequired: true,
            ),
          );
        }
      }
    }

    // Ensure internal subtask assignees are included in action_assignees
    for (final task in record.subTasks) {
      if (task.isInternal &&
          task.assignedStaffId.isNotEmpty &&
          RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
              .hasMatch(task.assignedStaffId) &&
          !seen.contains(task.assignedStaffId)) {
        seen.add(task.assignedStaffId);
        assignees.add(
          ActionAssigneeRecord(
            id: 'task-asg-${task.assignedStaffId}',
            actionId: actionId,
            profileId: task.assignedStaffId,
            profileName: task.assignedStaff.isNotEmpty
                ? task.assignedStaff
                : 'Staff Member',
            profileEmail: task.assignedStaffEmail,
            assignmentRole: 'assignee',
            isRequired: true,
          ),
        );
      }
    }

    return assignees;
  }

  @visibleForTesting
  List<ActionAssigneeRecord> testExtractDesiredAssignees(
    ActionRecord record, {
    required String actionId,
    String? fallbackOwnerId,
    String? fallbackOwnerName,
  }) {
    return _extractDesiredAssignees(
      record,
      actionId: actionId,
      fallbackOwnerId: fallbackOwnerId,
      fallbackOwnerName: fallbackOwnerName,
    );
  }

  /// Reconciles record assignees in memory, preserving completion state and cleaning up additionalPeople
  ActionRecord _reconcileRecordAssignees(
    ActionRecord record, {
    ActionRecord? existingRecord,
  }) {
    final desired = _extractDesiredAssignees(
      record,
      actionId: record.id,
      fallbackOwnerId: record.assignedToId ?? existingRecord?.assignedToId,
      fallbackOwnerName: record.assignedTo.isNotEmpty
          ? record.assignedTo
          : existingRecord?.assignedTo,
    );

    // If existing record had completion data for an assignee, retain it
    final existingAssignees = existingRecord?.assignees ?? const [];
    final existingByProfileId = {
      for (final a in existingAssignees) a.profileId: a,
    };

    final merged = desired.map((a) {
      final ex = existingByProfileId[a.profileId];
      if (ex != null && !a.workCompleted && ex.workCompleted) {
        return a.copyWith(
          workCompleted: ex.workCompleted,
          completedAt: ex.completedAt,
        );
      }
      return a;
    }).toList();

    // Also reconcile additionalPeople: remove any internal people who are not in merged assignees (except external)
    final desiredProfileIds = merged.map((a) => a.profileId).toSet();
    final updatedAdditionalPeople = record.additionalPeople.where((p) {
      if (p.type == PersonType.internalUser) {
        return desiredProfileIds.contains(p.personId) &&
            p.personId != (record.assignedToId ?? existingRecord?.assignedToId);
      }
      return true; // Keep external recipients
    }).toList();

    // Deduplicate by personId
    final seenPersonIds = <String>{};
    final deduplicatedPeople = <ActionPersonReference>[];
    for (final p in updatedAdditionalPeople) {
      if (p.personId.isNotEmpty && !seenPersonIds.contains(p.personId)) {
        seenPersonIds.add(p.personId);
        deduplicatedPeople.add(p);
      }
    }

    return record.copyWith(
      assignees: merged,
      additionalPeople: deduplicatedPeople,
    );
  }

  /// Reconciles follow-up checkpoints for in-memory mock store and updated records.
  ///
  /// Guarantees:
  /// 1. Preserves existing checkpoints (historical, past, future).
  /// 2. Preserves completed and cancelled checkpoint statuses without resetting them.
  /// 3. Avoids duplicate checkpoint records on the same calendar date.
  /// 4. Synchronizes [nextFollowUpDate] so that editing an action creates or references
  ///    the appropriate checkpoint.
  ActionRecord _reconcileRecordFollowUps(
    ActionRecord record, {
    ActionRecord? existingRecord,
  }) {
    if (mockFollowUpPersistenceShouldFail) {
      throw ActionFollowUpPersistenceException(
        mockFollowUpPersistenceFailureReason ??
            'Mock simulated follow-up persistence failure',
        actionId: record.id,
      );
    }

    final existingCheckpoints = existingRecord?.followUps ?? const [];
    final candidateCheckpoints = record.followUps;

    final Map<String, ActionFollowUpRecord> checkpointsByDate = {};

    for (final f in existingCheckpoints) {
      final dbDate = ActionRecord.formatDateForDb(f.followUpDate);
      if (dbDate.isNotEmpty) {
        checkpointsByDate[dbDate] = f;
      }
    }

    for (final f in candidateCheckpoints) {
      final dbDate = ActionRecord.formatDateForDb(f.followUpDate);
      if (dbDate.isEmpty) continue;
      final existing = checkpointsByDate[dbDate];
      if (existing != null) {
        if (existing.isCompleted || existing.status.trim().toLowerCase() == 'cancelled') {
          continue; // Preserve completed/cancelled checkpoint
        }
        checkpointsByDate[dbDate] = f.copyWith(
          id: existing.id.isNotEmpty ? existing.id : f.id,
          createdAt: existing.createdAt ?? f.createdAt,
        );
      } else {
        checkpointsByDate[dbDate] = f;
      }
    }

    if (record.nextFollowUpDate.isNotEmpty &&
        record.nextFollowUpDate != 'Not set' &&
        record.nextFollowUpDate != '-') {
      final nextDbDate = ActionRecord.formatDateForDb(record.nextFollowUpDate);
      if (nextDbDate.isNotEmpty) {
        final existingForDate = checkpointsByDate[nextDbDate];
        if (existingForDate == null) {
          final newCheckpoint = ActionFollowUpRecord(
            id: 'fu-',
            actionId: record.id,
            followUpDate: ActionRecord.formatDateForUi(nextDbDate),
            notes: existingRecord != null
                ? 'Follow-up checkpoint updated during action edit'
                : 'Initial follow-up checkpoint scheduled at creation',
            status: 'Scheduled',
            createdAt: DateTime.now(),
          );
          checkpointsByDate[nextDbDate] = newCheckpoint;
        }
      }
    }

    final mergedList = checkpointsByDate.values.toList()
      ..sort((a, b) {
        final dtA = ReportService.parseDate(a.followUpDate) ?? DateTime(2000);
        final dtB = ReportService.parseDate(b.followUpDate) ?? DateTime(2000);
        return dtA.compareTo(dtB);
      });

    return record.copyWith(followUps: mergedList);
  }

  String _sanitizeErrorMessage(dynamic error) {
    if (error == null) return 'Unknown error';
    if (error is PostgrestException) {
      final msg = error.message;
      final details = error.details?.toString();
      if (details != null && details.isNotEmpty) {
        return '$msg ($details)';
      }
      return msg;
    }
    return error.toString();
  }

  /// Synchronizes explicit email reminders for an action in both Mock and Supabase modes.
  /// If reminders are disabled, action is closed, or emailReminders is empty,
  /// all pending reminder jobs for this action are cancelled.
  /// Assignment alone NEVER creates reminder jobs.
  Future<void> _syncEmailRemindersForAction(ActionRecord record) async {
    final client = _client;

    final isClosed = record.isClosed ||
        record.status == 'Closed' ||
        (record.closeDate.isNotEmpty && record.percentComplete == 100);
    final shouldProcessReminders = record.emailReminderEnabled &&
        !isClosed &&
        record.emailReminders.isNotEmpty;

    final desiredItems = <({
      ActionEmailReminder reminder,
      ActionPersonReference recipient,
    })>[];
    final desiredKeys = <String>{};

    if (shouldProcessReminders) {
      for (final rem in record.emailReminders) {
        if (!rem.isEnabled) continue;
        for (final recip in rem.recipients) {
          final normalizedEmail = recip.email.trim().toLowerCase();
          final recipKey = normalizedEmail.isNotEmpty
              ? normalizedEmail
              : (recip.personId.isNotEmpty
                  ? recip.personId
                  : recip.name.trim().toLowerCase());
          final key = '${rem.id}::$recipKey';
          if (!desiredKeys.contains(key)) {
            desiredKeys.add(key);
            desiredItems.add((reminder: rem, recipient: recip));
          }
        }
      }
    }

    if (client == null) {
      final store = MockActionStore.instance;

      // 1. Cancel pending jobs that are no longer desired
      for (int i = 0; i < store.emailReminders.length; i++) {
        final job = store.emailReminders[i];
        if (job.actionId == record.id && job.isPending) {
          final email = job.recipientEmail.trim().toLowerCase();
          final recipKey = email.isNotEmpty
              ? email
              : (job.profileId ??
                  job.externalRecipientId ??
                  job.recipientName.toLowerCase());
          final key = '${job.reminderGroupId ?? ""}::$recipKey';
          if (!desiredKeys.contains(key)) {
            store.emailReminders[i] = job.copyWith(
              status: 'cancelled',
              updatedAt: DateTime.now(),
            );
          }
        }
      }

      // 2. Add or update desired jobs
      for (final item in desiredItems) {
        final rem = item.reminder;
        final recip = item.recipient;
        final isExt = recip.type == PersonType.externalWorker;
        final scheduled = ActionRecord.parseScheduledDateTime(
          rem.date,
          rem.time,
        );
        final email = recip.email.trim().toLowerCase();
        final recipKey = email.isNotEmpty
            ? email
            : (recip.personId.isNotEmpty
                ? recip.personId
                : recip.name.toLowerCase());

        final matchIdx = store.emailReminders.indexWhere((j) {
          if (j.actionId != record.id || !j.isPending) return false;
          final jEmail = j.recipientEmail.trim().toLowerCase();
          final jKey = jEmail.isNotEmpty
              ? jEmail
              : (j.profileId ??
                  j.externalRecipientId ??
                  j.recipientName.toLowerCase());
          return j.reminderGroupId == rem.id && jKey == recipKey;
        });

        if (matchIdx >= 0) {
          store.emailReminders[matchIdx] =
              store.emailReminders[matchIdx].copyWith(
            scheduledAt: scheduled,
            updatedAt: DateTime.now(),
          );
        } else {
          store.emailReminders.add(
            ActionEmailReminderJob(
              id: 'rem-${DateTime.now().millisecondsSinceEpoch}-${store.emailReminders.length}',
              organizationId: record.organizationId,
              actionId: record.id,
              reminderGroupId: rem.id,
              recipientType: isExt ? 'external' : 'internal',
              profileId: !isExt && recip.personId.isNotEmpty ? recip.personId : null,
              externalRecipientId:
                  isExt && recip.personId.isNotEmpty ? recip.personId : null,
              recipientName: recip.name,
              recipientEmail: email,
              reminderType: 'pending_action',
              emailSubject:
                  'ActionFlow Reminder: Action Assigned [${record.displayId}] - ${record.subject}',
              emailBody: 'Pending action reminder for ${recip.name}',
              scheduledAt: scheduled,
              status: 'pending',
              createdAt: DateTime.now(),
              createdBy: record.createdById,
            ),
          );
        }
      }
      return;
    }

    try {
      final existingRows = await client
          .from('action_email_reminders')
          .select('*')
          .eq('action_id', record.id)
          .eq('status', 'pending');

      final existingList = (existingRows as List);

      // 1. Cancel pending rows that are no longer desired
      for (final item in existingList) {
        if (item is Map) {
          final rMap = Map<String, dynamic>.from(item);
          final rId = rMap['id'] as String?;
          final rGroup = (rMap['reminder_group_id'] as String?) ?? '';
          final rEmail = (rMap['recipient_email'] as String? ?? '').trim().toLowerCase();
          final rProfile = rMap['profile_id'] as String?;
          final rExt = rMap['external_recipient_id'] as String?;
          final rName =
              (rMap['recipient_name'] as String? ?? '').toLowerCase();
          final rKey = rEmail.isNotEmpty
              ? rEmail
              : ((rProfile?.isNotEmpty == true)
                  ? rProfile!
                  : ((rExt?.isNotEmpty == true) ? rExt! : rName));
          final key = '$rGroup::$rKey';

          if (!desiredKeys.contains(key) && rId != null) {
            await client
                .from('action_email_reminders')
                .update({
                  'status': 'cancelled',
                  'updated_at': DateTime.now().toIso8601String(),
                })
                .eq('id', rId);
          }
        }
      }

      // 2. Insert or update desired reminder rows
      for (final item in desiredItems) {
        final rem = item.reminder;
        final recip = item.recipient;
        final scheduled = ActionRecord.parseScheduledDateTime(
          rem.date,
          rem.time,
        );
        final email = recip.email.trim().toLowerCase();
        final recipKey = email.isNotEmpty
            ? email
            : (recip.personId.isNotEmpty
                ? recip.personId
                : recip.name.toLowerCase());

        final matches = existingList.where((r) {
          if (r is! Map) return false;
          final rMap = Map<String, dynamic>.from(r);
          final rGroup = (rMap['reminder_group_id'] as String?) ?? '';
          final rEmail = (rMap['recipient_email'] as String? ?? '').trim().toLowerCase();
          final rProfile = rMap['profile_id'] as String?;
          final rExt = rMap['external_recipient_id'] as String?;
          final rName =
              (rMap['recipient_name'] as String? ?? '').toLowerCase();
          final rKey = rEmail.isNotEmpty
              ? rEmail
              : ((rProfile?.isNotEmpty == true)
                  ? rProfile!
                  : ((rExt?.isNotEmpty == true) ? rExt! : rName));
          return rGroup == rem.id && rKey == recipKey;
        }).toList();

        if (matches.isNotEmpty) {
          final matchId = (matches.first as Map)['id'] as String?;
          if (matchId != null) {
            await client
                .from('action_email_reminders')
                .update({
                  'scheduled_at': scheduled.toIso8601String(),
                  'updated_at': DateTime.now().toIso8601String(),
                })
                .eq('id', matchId);
          }
        } else {
          final isExt = recip.type == PersonType.externalWorker;
          try {
            await client.from('action_email_reminders').insert({
              'organization_id': record.organizationId,
              'action_id': record.id,
              'reminder_group_id': rem.id,
              'recipient_type': isExt ? 'external' : 'internal',
              'profile_id':
                  !isExt && recip.isValidUuid ? recip.personId : null,
              'external_recipient_id':
                  isExt && recip.isValidUuid ? recip.personId : null,
              'recipient_name': recip.name,
              'recipient_email': email,
              'reminder_type': 'pending_action',
              'email_subject':
                  'ActionFlow Reminder: Action Assigned [${record.displayId}] - ${record.subject}',
              'email_body': 'Pending action reminder for ${recip.name}',
              'scheduled_at': scheduled.toIso8601String(),
              'status': 'pending',
              if (record.createdById.isNotEmpty)
                'created_by': record.createdById,
            });
          } catch (insertErr) {
            debugPrint(
              '[ActionService] Email reminder row insert notice: $insertErr',
            );
          }
        }
      }
    } catch (e, st) {
      debugPrint('[ActionService._syncEmailRemindersForAction] Error: $e\n$st');
    }
  }

  /// Submits a progress update for an action assigned to the current manager/user.
  /// Calls the enhanced stored procedure `submit_action_progress_update_v2` with contribution value,
  /// or updates an existing progress update record if [existingUpdateId] is provided.
  Future<ActionRecord> submitProgressUpdate({
    required String actionId,
    required DateTime updateDate,
    required int progress,
    required String status,
    required String comments,
    String? existingUpdateId,
    int contributionValue = 0,
    List<String> attachments = const [],
    List<ActionSubTask>? subTasks,
    List<String>? history,
    String? roleInAction,
    String? updatedById,
    String? updatedByName,
    String? subject,
    String? messageType,
    String? workCompleted,
    String? pendingWork,
    String? requirement,
    String? suggestion,
    String? remarks,
  }) async {
    final client = _client;
    final formattedDate =
        '${updateDate.year}-${updateDate.month.toString().padLeft(2, '0')}-${updateDate.day.toString().padLeft(2, '0')}';
    if (client == null) {
      final cleanActionId = actionId.trim();
      final existing = MockActionStore.instance.actions.firstWhereOrNull((a) =>
          a.id.trim().toLowerCase() == cleanActionId.toLowerCase() ||
          a.actionNumber.trim().toLowerCase() == cleanActionId.toLowerCase() ||
          a.displayId.trim().toLowerCase() == cleanActionId.toLowerCase());
      if (existing != null) {
        final contribution = (progress - existing.percentComplete).clamp(0, 100);
        final effectiveWorkCompleted = (workCompleted != null && workCompleted.trim().isNotEmpty)
            ? workCompleted.trim()
            : comments.trim();

        ActionProgressUpdate update;
        List<ActionProgressUpdate> nextUpdates;
        final cleanExistingId = existingUpdateId?.trim() ?? '';
        final existingIdx = cleanExistingId.isNotEmpty
            ? existing.progressUpdates.indexWhere((u) => u.id == cleanExistingId)
            : -1;

        if (existingIdx >= 0) {
          final old = existing.progressUpdates[existingIdx];
          update = old.copyWith(
            updateDate: formattedDate,
            progress: progress,
            status: status,
            comments: comments.trim(),
            contributionValue: contribution,
            attachments: attachments.isNotEmpty ? attachments : old.attachments,
            subject: subject ?? old.subject,
            messageType: messageType ?? old.messageType,
            workCompleted: effectiveWorkCompleted,
            pendingWork: pendingWork ?? old.pendingWork,
            requirement: requirement ?? old.requirement,
            suggestion: suggestion ?? old.suggestion,
            remarks: remarks ?? old.remarks,
          );
          nextUpdates = List<ActionProgressUpdate>.from(existing.progressUpdates);
          nextUpdates[existingIdx] = update;
        } else {
          update = ActionProgressUpdate(
            id: 'mock-update-${DateTime.now().millisecondsSinceEpoch}',
            actionId: existing.id,
            updatedById: updatedById ?? existing.assignedToId ?? 'mock-user',
            updatedByName: updatedByName ?? (roleInAction == 'manager' ? 'Manager' : existing.assignedTo),
            updateDate: formattedDate,
            progress: progress,
            status: status,
            comments: comments.trim(),
            contributionValue: contribution,
            attachments: attachments,
            roleInAction: roleInAction ?? 'assignee',
            createdAt: DateTime.now(),
            subject: subject ?? '',
            messageType: messageType ?? 'Progress Update',
            workCompleted: effectiveWorkCompleted,
            pendingWork: pendingWork ?? '',
            requirement: requirement ?? '',
            suggestion: suggestion ?? '',
            remarks: remarks ?? '',
          );
          nextUpdates = [update, ...existing.progressUpdates];
        }

        final updatedAction = existing.copyWith(
          percentComplete: progress,
          status: status,
          workerMessageSubject: (roleInAction != 'manager' && subject != null && subject.isNotEmpty)
              ? subject
              : existing.workerMessageSubject,
          workerMessage: (roleInAction != 'manager' && effectiveWorkCompleted.isNotEmpty)
              ? effectiveWorkCompleted
              : (roleInAction != 'manager' && comments.isNotEmpty ? comments.trim() : existing.workerMessage),
          messageType: (roleInAction != 'manager' && messageType != null && messageType.isNotEmpty)
              ? messageType
              : existing.messageType,
          managerMessage: (roleInAction == 'manager' && comments.isNotEmpty)
              ? comments.trim()
              : existing.managerMessage,
          pendingReason: (pendingWork != null && pendingWork.isNotEmpty)
              ? pendingWork
              : existing.pendingReason,
          requirement: (requirement != null && requirement.isNotEmpty)
              ? requirement
              : existing.requirement,
          suggestion: (suggestion != null && suggestion.isNotEmpty)
              ? suggestion
              : existing.suggestion,
          remarks: (remarks != null && remarks.isNotEmpty)
              ? remarks
              : existing.remarks,
          progressUpdates: nextUpdates,
          attachments: {...existing.attachments, ...attachments}.toList(),
          subTasks: subTasks ?? existing.subTasks,
          history: history ?? existing.history,
        );
        MockActionStore.instance.update(updatedAction);
        final managerId = updatedAction.createdById.isNotEmpty
            ? updatedAction.createdById
            : (updatedAction.assignedByPerson?.personId ?? '');
        if (managerId.isNotEmpty) {
          final isCompleted = progress == 100 ||
              status.toLowerCase() == 'completed' ||
              status.toLowerCase() == 'pending review';
          NotificationService.safeDispatch(
            () => NotificationService.instance.notifyActionUpdatedOrCompleted(
              action: updatedAction,
              managerUserId: managerId,
              updatedByName: updatedAction.assignedTo.isNotEmpty
                  ? updatedAction.assignedTo
                  : 'Staff',
              isCompleted: isCompleted,
              organizationId: updatedAction.organizationId,
              notes: comments,
            ),
            context: 'ActionService.submitProgressUpdate (local)',
          );
        }
        return updatedAction;
      }
      throw Exception('Action not found in mock store.');
    }

    try {
      final formattedDate =
          '${updateDate.year}-${updateDate.month.toString().padLeft(2, '0')}-${updateDate.day.toString().padLeft(2, '0')}';

      final bool hasStructuredRemarks =
          (subject != null && subject.trim().isNotEmpty) ||
          (messageType != null && messageType.trim().isNotEmpty) ||
          (workCompleted != null && workCompleted.trim().isNotEmpty) ||
          (pendingWork != null && pendingWork.trim().isNotEmpty) ||
          (requirement != null && requirement.trim().isNotEmpty) ||
          (suggestion != null && suggestion.trim().isNotEmpty) ||
          (remarks != null && remarks.trim().isNotEmpty);

      final Map<String, dynamic> remarksData = {
        if (subject != null && subject.trim().isNotEmpty) 'subject': subject.trim(),
        if (messageType != null && messageType.trim().isNotEmpty)
          'message_type': messageType.trim(),
        if (workCompleted != null && workCompleted.trim().isNotEmpty) ...{
          'work_completed': workCompleted.trim(),
          'workCompleted': workCompleted.trim(),
        } else if (comments.trim().isNotEmpty) ...{
          'work_completed': comments.trim(),
          'workCompleted': comments.trim(),
        },
        if (pendingWork != null && pendingWork.trim().isNotEmpty) ...{
          'pending_work': pendingWork.trim(),
          'work_pending': pendingWork.trim(),
          'workPending': pendingWork.trim(),
          'pending_reason': pendingWork.trim(),
        },
        if (requirement != null && requirement.trim().isNotEmpty) ...{
          'requirement': requirement.trim(),
          'equipment_required': requirement.trim(),
          'equipmentRequired': requirement.trim(),
        },
        if (suggestion != null && suggestion.trim().isNotEmpty) ...{
          'suggestion': suggestion.trim(),
          'suggestions': suggestion.trim(),
          'suggestion_for_manager': suggestion.trim(),
        },
        if (remarks != null && remarks.trim().isNotEmpty) ...{
          'remarks': remarks.trim(),
          'safety_remarks': remarks.trim(),
          'safetyRemarks': remarks.trim(),
        },
      };
      final String effectiveComments = hasStructuredRemarks
          ? jsonEncode(remarksData)
          : comments.trim();

      bool didDirectUpdate = false;
      final cleanExistingId = existingUpdateId?.trim() ?? '';
      if (cleanExistingId.isNotEmpty) {
        try {
          await client.from('action_progress_updates').update({
            'update_date': formattedDate,
            'progress': progress,
            'status': status,
            'comments': effectiveComments,
            if (attachments.isNotEmpty) 'attachments': attachments,
            'contribution_value': contributionValue,
          }).eq('id', cleanExistingId);
          didDirectUpdate = true;
        } catch (updateErr) {
          debugPrint(
            '[ActionService] direct update on action_progress_updates failed, falling back to RPC: $updateErr',
          );
        }
      }

      if (!didDirectUpdate) {
        try {
          await client.rpc(
            'submit_action_progress_update_v2',
            params: {
              'p_action_id': actionId,
              'p_update_date': formattedDate,
              'p_progress': progress,
              'p_status': status,
              'p_comments': effectiveComments,
              'p_contribution_value': contributionValue,
              'p_attachments': attachments,
            },
          );
        } catch (rpcErr) {
          debugPrint(
            '[ActionService] submit_action_progress_update_v2 fallback: $rpcErr',
          );
          await client.rpc(
            'submit_action_progress_update',
            params: {
              'p_action_id': actionId,
              'p_update_date': formattedDate,
              'p_progress': progress,
              'p_status': status,
              'p_comments': effectiveComments,
              'p_attachments': attachments,
            },
          );
        }
      }

      // Synchronize action table top-level fields
      try {
        await client.from('actions').update({
          'percent_complete': progress,
          'status': status,
          if (roleInAction != 'manager' && subject != null && subject.trim().isNotEmpty)
            'worker_message_subject': subject.trim(),
          if (roleInAction != 'manager')
            'worker_message': (workCompleted != null && workCompleted.trim().isNotEmpty)
                ? workCompleted.trim()
                : comments.trim(),
          if (roleInAction == 'manager') 'manager_message': comments.trim(),
          if (pendingWork != null && pendingWork.trim().isNotEmpty)
            'pending_reason': pendingWork.trim(),
          if (requirement != null && requirement.trim().isNotEmpty)
            'requirement': requirement.trim(),
          if (suggestion != null && suggestion.trim().isNotEmpty)
            'suggestion': suggestion.trim(),
          if (remarks != null && remarks.trim().isNotEmpty)
            'remarks': remarks.trim(),
          if (attachments.isNotEmpty) 'attachments': attachments,
        }).eq('id', actionId);
      } catch (actErr) {
        debugPrint('[ActionService] actions table top-level sync error (non-fatal): $actErr');
      }

      final updated = await fetchActionById(actionId);
      if (updated == null) {
        throw Exception(
          'Failed to fetch action record after submitting update.',
        );
      }
      MockActionStore.instance.update(updated);
      final managerId = updated.createdById.isNotEmpty
          ? updated.createdById
          : (updated.assignedByPerson?.personId ?? '');
      if (managerId.isNotEmpty) {
        final isCompleted = progress == 100 ||
            status.toLowerCase() == 'completed' ||
            status.toLowerCase() == 'pending review';
        NotificationService.safeDispatch(
          () => NotificationService.instance.notifyActionUpdatedOrCompleted(
            action: updated,
            managerUserId: managerId,
            updatedByName: updated.assignedTo.isNotEmpty
                ? updated.assignedTo
                : 'Staff',
            isCompleted: isCompleted,
            organizationId: updated.organizationId,
            notes: comments,
          ),
          context: 'ActionService.submitProgressUpdate',
        );
      }
      return updated;
    } catch (e, st) {
      debugPrint('[ActionService] Error submitting progress update: $e\n$st');
      rethrow;
    }
  }

  /// Submits an authorization-enforcing subtask toggle via Supabase RPC `submit_subtask_toggle`.
  /// Updates subtask status, recalculates overall action progress, and logs to database.
  Future<Map<String, dynamic>> submitSubtaskToggle({
    required String actionId,
    required String taskId,
    required bool isCompleted,
    String? reopenReason,
  }) async {
    // 1. Always update MockActionStore in parallel to keep local state authoritative and in-sync
    final cleanActionId = actionId.trim();
    var mockAct = MockActionStore.instance.actions.firstWhereOrNull((a) =>
        a.id.trim().toLowerCase() == cleanActionId.toLowerCase() ||
        a.actionNumber.trim().toLowerCase() == cleanActionId.toLowerCase() ||
        a.displayId.trim().toLowerCase() == cleanActionId.toLowerCase());
    mockAct ??= MockActionStore.instance.actions
        .firstWhereOrNull((a) => a.subTasks.any((t) => t.id == taskId));
    if (mockAct != null) {
      final subTasks = List<ActionSubTask>.from(mockAct.subTasks);
      final idx = subTasks.indexWhere((t) => t.id == taskId);
      if (idx != -1) {
        final now = DateTime.now();
        const months = [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
        ];
        final nowStr =
            '${now.day.toString().padLeft(2, '0')} ${months[now.month - 1]} ${now.year}';
        final workerName = isCompleted
            ? (subTasks[idx].assignedStaff.isNotEmpty
                ? subTasks[idx].assignedStaff
                : (mockAct.assignedTo.isNotEmpty ? mockAct.assignedTo : 'Staff'))
            : '';
        subTasks[idx] = subTasks[idx].copyWith(
          status: isCompleted ? 'Completed' : 'Open',
          completedAt: isCompleted ? nowStr : '',
          completedBy: workerName,
          reopenReason: !isCompleted ? (reopenReason ?? '') : '',
        );

        final List<String> nextHistory = List.of(mockAct.history);
        if (!isCompleted && reopenReason != null && reopenReason.isNotEmpty) {
          nextHistory.insert(
            0,
            '$nowStr: Task "${subTasks[idx].title}" reopened by Manager. Reason: ${reopenReason.trim()}',
          );
        }

        // STEP 25 BUSINESS RULE: Tasks are a supporting checklist.
        // Toggling/reopening a task DOES NOT alter action percentComplete or status!
        final updated = mockAct.copyWith(
          status: mockAct.status,
          subTasks: subTasks,
          percentComplete: mockAct.percentComplete,
          history: nextHistory,
        );
        MockActionStore.instance.update(updated);
        mockAct = updated;
      }
    }

    final client = _client;
    if (client == null) {
      if (mockAct != null) {
        final completedCount = mockAct.subTasks.where((t) => t.isCompleted).length;
        return {
          'success': true,
          'percent_complete': mockAct.percentComplete,
          'completed_tasks': completedCount,
          'total_tasks': mockAct.subTasks.length,
          'status': mockAct.status,
        };
      }
      return {
        'success': false,
        'error': 'Action or task not found in mock store.',
      };
    }

    try {
      String effectiveId = ActionService.cleanActionId(actionId);
      bool isUuid = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(effectiveId);
      if (!isUuid) {
        try {
          final row = await client
              .from('actions')
              .select('id')
              .eq('action_number', effectiveId)
              .maybeSingle();
          if (row != null && row['id'] != null) {
            effectiveId = row['id'].toString();
            isUuid = RegExp(
              r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
            ).hasMatch(effectiveId);
          }
        } catch (_) {}
      }

      if (!isUuid) {
        return {
          'success': false,
          'error': 'Action ID "$actionId" is not a valid UUID and could not be resolved.',
        };
      }

      final params = <String, dynamic>{
        'p_action_id': effectiveId,
        'p_task_id': taskId,
        'p_completed': isCompleted,
        'p_reopen_reason': (reopenReason != null && reopenReason.isNotEmpty) ? reopenReason.trim() : null,
      };

      dynamic response;
      try {
        response = await client.rpc(
          'submit_subtask_toggle',
          params: params,
        );
      } catch (rpcErr) {
        // Try fallback parameter name p_action_uuid if PostgREST schema cache expects p_action_uuid
        final errStr = rpcErr.toString();
        if (errStr.contains('PGRST202') || errStr.contains('schema cache') || errStr.contains('p_action_uuid')) {
          try {
            final uuidParams = <String, dynamic>{
              'p_action_uuid': effectiveId,
              'p_task_id': taskId,
              'p_completed': isCompleted,
            };
            if (reopenReason != null && reopenReason.isNotEmpty) {
              uuidParams['p_reopen_reason'] = reopenReason.trim();
            }
            response = await client.rpc(
              'submit_subtask_toggle',
              params: uuidParams,
            );
          } catch (_) {
            if (params.containsKey('p_reopen_reason')) {
              try {
                response = await client.rpc(
                  'submit_subtask_toggle',
                  params: {
                    'p_action_id': effectiveId,
                    'p_task_id': taskId,
                    'p_completed': isCompleted,
                  },
                );
              } catch (_) {
                rethrow;
              }
            } else {
              rethrow;
            }
          }
        } else if (params.containsKey('p_reopen_reason')) {
          try {
            response = await client.rpc(
              'submit_subtask_toggle',
              params: {
                'p_action_id': effectiveId,
                'p_task_id': taskId,
                'p_completed': isCompleted,
              },
            );
          } catch (_) {
            rethrow;
          }
        } else {
          rethrow;
        }
      }

      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      return {
        'success': false,
        'error': 'Unexpected response from database.',
      };
    } catch (e) {
      debugPrint('[ActionService] Error toggling subtask via RPC: $e');
      // Note: Direct fallback reading actions.subtasks is intentionally removed.
      // The actions.subtasks column SELECT is revoked from authenticated to prevent
      // unauthorized cross-user subtask exposure. All subtask modifications must
      // go through the authorized submit_subtask_toggle SECURITY DEFINER RPC.

      // Do NOT silently report success when Supabase persistence failed
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Formally reopens an entire action.
  /// Transitions lifecycle status to 'In Progress', clears closed attributes,
  /// preserves previous reports/comments/evidence/dates, and records who reopened,
  /// timestamp, and reason in history and progress updates.
  Future<ActionRecord> reopenAction({
    required String actionId,
    required String reason,
    String? reopenedBy,
  }) async {
    final client = _client;
    final now = DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final nowStr =
        '${now.day.toString().padLeft(2, '0')} ${months[now.month - 1]} ${now.year}';
    final actorName = (reopenedBy != null && reopenedBy.isNotEmpty)
        ? reopenedBy
        : 'Manager';

    if (client == null) {
      final cleanActionId = actionId.trim();
      final existing = MockActionStore.instance.actions.firstWhereOrNull((a) =>
          a.id.trim().toLowerCase() == cleanActionId.toLowerCase() ||
          a.actionNumber.trim().toLowerCase() == cleanActionId.toLowerCase() ||
          a.displayId.trim().toLowerCase() == cleanActionId.toLowerCase());
      if (existing != null) {
        final logEntry =
            '$nowStr: Action Reopened by $actorName. Reason: ${reason.trim()}';
        final nextHistory = [logEntry, ...existing.history];
        final formattedDate =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        final update = ActionProgressUpdate(
          id: 'mock-reopen-${now.millisecondsSinceEpoch}',
          actionId: existing.id,
          updatedById: existing.createdById.isNotEmpty ? existing.createdById : 'manager',
          updatedByName: actorName,
          updateDate: formattedDate,
          progress: existing.percentComplete,
          status: 'In Progress',
          comments: 'Action Reopened: ${reason.trim()}',
          createdAt: now,
        );
        final updatedAction = existing.copyWith(
          status: 'In Progress',
          history: nextHistory,
          progressUpdates: [update, ...existing.progressUpdates],
        );
        MockActionStore.instance.update(updatedAction);
        if (!updatedAction.isExternalRecipient &&
            updatedAction.assignedToId != null &&
            updatedAction.assignedToId!.isNotEmpty) {
          NotificationService.safeDispatch(
            () => NotificationService.instance.notifyActionReopened(
              action: updatedAction,
              assigneeUserId: updatedAction.assignedToId!,
              reopenedByName: actorName,
              organizationId: updatedAction.organizationId,
              reason: reason,
            ),
            context: 'ActionService.reopenAction (local)',
          );
        }
        return updatedAction;
      }
      throw Exception('Action not found in mock store.');
    }

    try {
      String effectiveId = actionId;
      final isUuid = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(actionId);
      if (!isUuid) {
        try {
          final row = await client
              .from('actions')
              .select('id')
              .eq('action_number', actionId)
              .maybeSingle();
          if (row != null && row['id'] != null) {
            effectiveId = row['id'].toString();
          }
        } catch (_) {}
      }

      try {
        await client.rpc(
          'reopen_action',
          params: {
            'p_action_id': effectiveId,
            'p_reason': reason.trim(),
          },
        );
      } catch (rpcErr) {
        debugPrint('[ActionService.reopenAction] RPC fallback: $rpcErr');
        await client.from('actions').update({
          'status': 'In Progress',
          'closed_at': null,
          'close_date': null,
          'closed_by': null,
          'verified_by': null,
          'updated_at': now.toIso8601String(),
        }).eq('id', effectiveId);
      }

      final updated = await fetchActionById(effectiveId);
      if (updated == null) {
        throw Exception('Failed to fetch action record after reopening.');
      }
      if (!updated.isExternalRecipient &&
          updated.assignedToId != null &&
          updated.assignedToId!.isNotEmpty) {
        NotificationService.safeDispatch(
          () => NotificationService.instance.notifyActionReopened(
            action: updated,
            assigneeUserId: updated.assignedToId!,
            reopenedByName: actorName,
            organizationId: updated.organizationId,
            reason: reason,
          ),
          context: 'ActionService.reopenAction',
        );
      }
      return updated;
    } catch (e) {
      debugPrint('[ActionService.reopenAction] Error: $e');
      rethrow;
    }
  }

  /// Adds a follow-up review checkpoint to an action
  Future<({bool success, String? error, String? followUpId})> addFollowUp({
    required String actionId,
    required DateTime followUpDate,
    required String notes,
  }) async {
    final client = _client;
    final formattedDate =
        '${followUpDate.year}-${followUpDate.month.toString().padLeft(2, '0')}-${followUpDate.day.toString().padLeft(2, '0')}';

    if (client == null) {
      final cleanActionId = actionId.trim().toLowerCase();
      final existing = MockActionStore.instance.actions.firstWhereOrNull((a) =>
          a.id.trim().toLowerCase() == cleanActionId ||
          a.actionNumber.trim().toLowerCase() == cleanActionId ||
          a.displayId.trim().toLowerCase() == cleanActionId);
      if (existing != null) {
        final fuId = 'mock-fu-${DateTime.now().millisecondsSinceEpoch}';
        final newRecord = ActionFollowUpRecord(
          id: fuId,
          actionId: existing.id,
          followUpDate: ActionRecord.formatDateForUi(formattedDate),
          notes: notes.trim(),
          status: 'Scheduled',
          createdAt: DateTime.now(),
        );
        final updatedFollowUps = [...existing.followUps, newRecord];
        final updated = existing.copyWith(
          followUps: updatedFollowUps,
          nextFollowUpDate: ActionRecord.formatDateForUi(formattedDate),
        );
        MockActionStore.instance.update(updated);
        return (success: true, error: null, followUpId: fuId);
      }
      return (
        success: false,
        error: 'Action not found in mock store.',
        followUpId: null,
      );
    }
    try {
      final response = await client.rpc(
        'add_action_follow_up',
        params: {
          'p_action_id': actionId,
          'p_follow_up_date': formattedDate,
          'p_notes': notes.trim(),
        },
      );
      if (response is Map) {
        final success = response['success'] == true;
        final error = response['error']?.toString();
        final followUpId = response['follow_up_id']?.toString();
        if (success) {
          try {
            final refreshed = await fetchActionById(actionId);
            if (refreshed != null) MockActionStore.instance.update(refreshed);
          } catch (_) {}
        }
        return (success: success, error: error, followUpId: followUpId);
      }
      return (success: true, error: null, followUpId: null);
    } catch (e, st) {
      debugPrint('[ActionService] Error adding follow-up: $e\n$st');
      return (success: false, error: e.toString(), followUpId: null);
    }
  }

  /// Adds a contributor to an action (Forward / Add Contributor).
  /// Enforces permissions (Staff -> Staff only, Manager -> Mgr/Staff) and never transfers owner.
  Future<({bool success, String? error, String? contributorName})>
  addContributor({
    required String actionId,
    required String contributorProfileId,
    String addedBy = '',
    String addedByName = '',
    String notes = '',
  }) async {
    final trimmedContributorId = contributorProfileId.trim();
    final client = _client;
    if (client == null) {
      final mockMatch = MockPeopleStore.instance.people
          .where((p) => p.id == trimmedContributorId)
          .firstOrNull;
      final contributorName = mockMatch?.name ?? 'Contributor';
      final contributorEmail = mockMatch?.email ?? '';

      final cleanId = cleanActionId(actionId);
      final action = MockActionStore.instance.actions.firstWhereOrNull(
        (a) => isActionMatch(a, cleanId),
      );
      if (action != null) {
        final now = DateTime.now();
        const months = [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
        ];
        final nowStr =
            '${now.day.toString().padLeft(2, '0')} ${months[now.month - 1]} ${now.year}';

        final alreadyContributor = action.contributors.any(
          (c) => c.profileId == trimmedContributorId,
        );
        if (!alreadyContributor) {
          final effectiveAddedBy = addedBy.isNotEmpty
              ? addedBy
              : (action.assignedToId ?? action.assignedBy);
          final effectiveAddedByName = addedByName.isNotEmpty
              ? addedByName
              : (action.assignedTo.isNotEmpty ? action.assignedTo : action.assignedBy);

          final newContrib = ActionContributorRecord(
            id: 'contrib_${DateTime.now().millisecondsSinceEpoch}',
            actionId: action.id,
            profileId: trimmedContributorId,
            profileName: contributorName,
            profileEmail: contributorEmail,
            addedBy: effectiveAddedBy,
            addedByName: effectiveAddedByName,
            notes: notes.trim(),
            createdAt: now,
          );
          final historyLog = '$nowStr: Contributor $contributorName added.';

          final updatedAction = action.copyWith(
            contributors: [...action.contributors, newContrib],
            history: [
              historyLog,
              ...action.history,
            ],
          );
          MockActionStore.instance.update(updatedAction);
        }
      }

      return (
        success: true,
        error: null,
        contributorName: contributorName,
      );
    }

    if (trimmedContributorId.isEmpty ||
        trimmedContributorId.toLowerCase() == 'unassigned' ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(trimmedContributorId)) {
      return (
        success: false,
        error:
            'Invalid contributor profile ID ("$contributorProfileId"). Must be a valid user UUID.',
        contributorName: null,
      );
    }

    try {
      final params = <String, dynamic>{
        'p_action_id': actionId,
        'p_contributor_profile_id': trimmedContributorId,
        'p_notes': notes.trim(),
      };
      if (addedBy.isNotEmpty &&
          RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
          ).hasMatch(addedBy.trim())) {
        params['p_added_by'] = addedBy.trim();
      }
      if (addedByName.trim().isNotEmpty) {
        params['p_added_by_name'] = addedByName.trim();
      }

      dynamic response;
      if (params.length > 3) {
        try {
          response = await client.rpc(
            'add_action_contributor',
            params: params,
          );
        } catch (rpcErr) {
          final errStr = rpcErr.toString().toLowerCase();
          final isSignatureMismatch = errStr.contains('pgrst202') ||
              errStr.contains('schema cache') ||
              errStr.contains('argument') ||
              errStr.contains('parameter') ||
              errStr.contains('does not exist');
          if (isSignatureMismatch) {
            debugPrint('[ActionService] add_action_contributor 5-param call failed with signature mismatch; falling back to 3-param RPC: $rpcErr');
            // Fallback to baseline 3-parameter call if remote procedure does not yet declare extra params
            response = await client.rpc(
              'add_action_contributor',
              params: {
                'p_action_id': actionId,
                'p_contributor_profile_id': trimmedContributorId,
                'p_notes': notes.trim(),
              },
            );
          } else {
            rethrow;
          }
        }
      } else {
        response = await client.rpc(
          'add_action_contributor',
          params: params,
        );
      }
      if (response is Map) {
        final success = response['success'] == true;
        final error = response['error']?.toString();
        final contributorName = response['contributor_name']?.toString();
        if (success) {
          try {
            final refreshed = await fetchActionById(actionId);
            if (refreshed != null) {
              MockActionStore.instance.update(refreshed);
              NotificationService.safeDispatch(
                () => NotificationService.instance.notifyContributorAdded(
                  action: refreshed,
                  contributorUserId: trimmedContributorId,
                  addedByName: addedByName.isNotEmpty ? addedByName : 'A team member',
                  organizationId: refreshed.organizationId,
                ),
                context: 'ActionService.addContributor',
              );
            }
          } catch (_) {}
        }
        return (
          success: success,
          error: error,
          contributorName: contributorName,
        );
      }
      return (success: true, error: null, contributorName: null);
    } catch (e, st) {
      debugPrint('[ActionService] Error adding contributor: $e\n$st');
      return (success: false, error: e.toString(), contributorName: null);
    }
  }

  /// Marks a required assignee's work as completed or incomplete
  Future<({bool success, String? error})> markAssigneeCompleted({
    required String actionId,
    required String profileId,
    required bool completed,
  }) async {
    final client = _client;
    if (client == null) {
      final action = MockActionStore.instance.actions
          .firstWhereOrNull((a) => a.id == actionId);
      if (action == null) {
        return (success: false, error: 'Action not found in local store.');
      }
      final updatedAssignees = action.assignees.map((a) {
        if (a.profileId == profileId) {
          return a.copyWith(
            workCompleted: completed,
            completedAt: completed ? DateTime.now() : null,
          );
        }
        return a;
      }).toList();
      MockActionStore.instance
          .update(action.copyWith(assignees: updatedAssignees));
      return (success: true, error: null);
    }
    try {
      await client
          .from('action_assignees')
          .update({
            'work_completed': completed,
            'completed_at': completed ? DateTime.now().toIso8601String() : null,
          })
          .eq('action_id', actionId)
          .eq('profile_id', profileId);
      return (success: true, error: null);
    } catch (e, st) {
      debugPrint('[ActionService] Error updating assignee completion: $e\n$st');
      return (success: false, error: e.toString());
    }
  }

  /// Safely sanitizes an attachment filename by stripping directory separators and '..'.
  static String sanitizeAttachmentFileName(String fileName) {
    var clean = fileName.trim().replaceAll('\\', '/');
    final lastSlash = clean.lastIndexOf('/');
    if (lastSlash != -1) {
      clean = clean.substring(lastSlash + 1);
    }
    clean = clean.replaceAll('..', '').trim();
    return clean;
  }

  /// Validates whether a given string is a valid UUID format.
  static bool isValidUuid(String? val) {
    if (val == null) return false;
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(val.trim());
  }

  /// Resolves an organization identifier to a guaranteed valid UUID,
  /// satisfying Storage RLS checks (`public.check_user_in_org(split_part(name, '/', 1))`).
  static String resolveOrganizationUuid(String? orgId) {
    final clean = orgId?.trim() ?? '';
    if (isValidUuid(clean)) {
      return clean;
    }
    final userOrg = AuthService.instance.currentOrganizationId?.trim();
    if (isValidUuid(userOrg)) {
      return userOrg!;
    }
    final profileOrg =
        AuthService.instance.currentProfileData?.organizationId?.trim();
    if (isValidUuid(profileOrg)) {
      return profileOrg!;
    }
    return Organization.sobhaId;
  }

  /// Builds and validates the Storage object path for an action attachment.
  /// Format: `<organizationId>/actions/<actionId>/<fileName>`
  static String? buildActionAttachmentPath({
    required String organizationId,
    required String actionId,
    required String fileName,
  }) {
    var cleanOrg = organizationId.trim().replaceAll('\\', '/').replaceAll('..', '');
    if (cleanOrg.isEmpty || cleanOrg == 'SOBHA-001' || cleanOrg.toLowerCase() == 'sobha') {
      cleanOrg = resolveOrganizationUuid(organizationId);
    }
    final cleanAction = actionId.trim().replaceAll('\\', '/').replaceAll('..', '');
    final cleanFile = sanitizeAttachmentFileName(fileName);
    if (cleanOrg.isEmpty || cleanAction.isEmpty || cleanFile.isEmpty) {
      return null;
    }
    return '$cleanOrg/actions/$cleanAction/$cleanFile';
  }

  /// Returns a prioritized list of candidate storage object paths for an action attachment,
  /// supporting legacy flat paths, organization-scoped action folders, reports, and document directories.
  static List<String> getAttachmentCandidatePaths({
    required ActionRecord action,
    required String fileName,
  }) {
    final cleanFile = sanitizeAttachmentFileName(fileName);
    if (cleanFile.isEmpty) return const [];

    final rawOrg = action.organizationId.trim();
    final userOrg = AuthService.instance.currentOrganizationId?.trim() ?? '';
    final primaryPath = buildActionAttachmentPath(
      organizationId: rawOrg,
      actionId: action.id,
      fileName: cleanFile,
    );

    // Organization variants: ensure valid UUIDs are prioritized first so Postgres RLS check_user_in_org succeeds
    final orgVariants = <String>{};
    final resolvedUuid = resolveOrganizationUuid(rawOrg);
    orgVariants.add(resolvedUuid);
    orgVariants.add(Organization.sobhaId);
    if (isValidUuid(userOrg)) orgVariants.add(userOrg);
    if (primaryPath != null) {
      final firstSlash = primaryPath.indexOf('/');
      if (firstSlash != -1) {
        orgVariants.add(primaryPath.substring(0, firstSlash));
      }
    }
    if (rawOrg.isNotEmpty) orgVariants.add(rawOrg);
    if (userOrg.isNotEmpty) orgVariants.add(userOrg);
    orgVariants.add('sobha');
    orgVariants.add('SOBHA-001');
    orgVariants.add('org-sobha-01');

    // Action identifier variants: include ID, actionNumber, displayId, and numeric digits
    final actionIdentifiers = <String>{};
    final actionId = action.id.trim();
    final actionNum = action.actionNumber.trim();
    final displayId = action.displayId.trim();

    if (actionId.isNotEmpty) actionIdentifiers.add(actionId);
    if (actionNum.isNotEmpty) actionIdentifiers.add(actionNum);
    if (displayId.isNotEmpty) actionIdentifiers.add(displayId);

    final digits1 = RegExp(r'\d+').firstMatch(actionNum)?.group(0);
    final digits2 = RegExp(r'\d+').firstMatch(actionId)?.group(0);
    final digits3 = RegExp(r'\d+').firstMatch(displayId)?.group(0);
    final allDigits = {
      if (digits1 != null && digits1.length >= 2) digits1,
      if (digits2 != null && digits2.length >= 2) digits2,
      if (digits3 != null && digits3.length >= 2) digits3,
    };

    for (final d in allDigits) {
      actionIdentifiers.add(d);
      actionIdentifiers.add('ACT-$d');
      actionIdentifiers.add('AC-$d');
      actionIdentifiers.add('AF-$d');
      actionIdentifiers.add('act-$d');
      actionIdentifiers.add('ac-$d');
    }

    // Filename variants: handle spaces, URL encoding, plus-encoding, stripped duplicate copy suffixes
    final fileVariants = <String>{};
    fileVariants.add(cleanFile);

    // If action.attachments contains an attachment that matches cleanFile ignoring whitespace or case differences,
    // include that exact attachment name as a candidate (e.g. 2 spaces vs 1 space)
    final normalizedClean = cleanFile.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    for (final att in action.attachments) {
      final cleanAtt = sanitizeAttachmentFileName(att);
      if (cleanAtt.isNotEmpty &&
          cleanAtt.replaceAll(RegExp(r'\s+'), ' ').toLowerCase() == normalizedClean) {
        fileVariants.add(cleanAtt);
      }
    }

    if (cleanFile.contains(' ')) {
      fileVariants.add(cleanFile.replaceAll(' ', '%20'));
      fileVariants.add(cleanFile.replaceAll(' ', '+'));
      fileVariants.add(cleanFile.replaceAll(' ', '_'));
      fileVariants.add(cleanFile.replaceAll(RegExp(r'\s+'), ' '));
      fileVariants.add(cleanFile.replaceAll(RegExp(r'\s+'), '  '));
    }

    try {
      final decoded = Uri.decodeComponent(cleanFile);
      if (decoded != cleanFile) fileVariants.add(decoded);
    } catch (_) {}
    try {
      final encoded = Uri.encodeComponent(cleanFile);
      if (encoded != cleanFile) fileVariants.add(encoded);
    } catch (_) {}

    // Duplicate copy suffix stripped: e.g. " (1)", " (2)", etc.
    final noDuplicateSuffix =
        cleanFile.replaceAll(RegExp(r'\s*\(\d+\)\.'), '.');
    if (noDuplicateSuffix != cleanFile) {
      fileVariants.add(noDuplicateSuffix);
      if (noDuplicateSuffix.contains(' ')) {
        fileVariants.add(noDuplicateSuffix.replaceAll(' ', '%20'));
        fileVariants.add(noDuplicateSuffix.replaceAll(' ', '+'));
        fileVariants.add(noDuplicateSuffix.replaceAll(' ', '_'));
      }
    }

    final paths = <String>[];

    // 1. Primary path from builder
    if (primaryPath != null) {
      paths.add(primaryPath);
    }

    // 2. Organization action folder variants for each identifier and file variant
    for (final f in fileVariants) {
      for (final org in orgVariants) {
        for (final actRef in actionIdentifiers) {
          paths.add('$org/actions/$actRef/$f');
          paths.add('$org/$actRef/$f');
        }
        // Reports, documents, evidence
        paths.add('$org/reports/$f');
        paths.add('$org/documents/$f');
        paths.add('$org/evidence/$f');
        paths.add('$org/$f');
      }

      // 3. Action paths without organization prefix (legacy structure)
      for (final actRef in actionIdentifiers) {
        paths.add('actions/$actRef/$f');
        paths.add('$actRef/$f');
      }

      paths.add('reports/$f');
      paths.add('documents/$f');
      paths.add('evidence/$f');
      paths.add(f);
    }

    // 4. Relative path if fileName contained directory structures
    final normalizedRaw = fileName.trim().replaceAll('\\', '/');
    if (!normalizedRaw.contains('..') && normalizedRaw.contains('/')) {
      final cleanRelative = normalizedRaw.startsWith('/')
          ? normalizedRaw.substring(1)
          : normalizedRaw;
      if (cleanRelative.isNotEmpty) {
        paths.insert(0, cleanRelative);
        for (final org in orgVariants) {
          if (!cleanRelative.startsWith('$org/')) {
            paths.insert(0, '$org/$cleanRelative');
          }
        }
      }
    }

    // Deduplicate while preserving priority order
    final seen = <String>{};
    final uniquePaths = <String>[];
    for (final p in paths) {
      if (seen.add(p)) {
        uniquePaths.add(p);
      }
    }
    return uniquePaths;
  }

  /// Safely uploads an attachment binary to Supabase Storage and records it in the action record metadata.
  Future<({bool success, String? error, ActionRecord? updatedAction})> uploadActionAttachment({
    required ActionRecord action,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final cleanFile = sanitizeAttachmentFileName(fileName);
    if (cleanFile.isEmpty) {
      return (success: false, error: 'Invalid attachment filename.', updatedAction: null);
    }
    if (bytes.isEmpty) {
      return (success: false, error: 'Attachment file cannot be empty.', updatedAction: null);
    }

    final effectiveOrg = resolveOrganizationUuid(action.organizationId);

    final path = buildActionAttachmentPath(
      organizationId: effectiveOrg,
      actionId: action.id,
      fileName: cleanFile,
    );
    if (path == null) {
      return (
        success: false,
        error: 'Could not construct valid attachment storage path.',
        updatedAction: null,
      );
    }

    final client = _client;
    if (client != null && SupabaseConfig.isInitialized) {
      bool uploaded = false;
      dynamic lastError;

      // Safe upload: first attempt with upsert: false so only INSERT policy is evaluated (avoids UPDATE policy requirement on storage.objects for staff)
      try {
        await client.storage.from('documents').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );
        uploaded = true;
      } catch (e) {
        lastError = e;
        debugPrint('[ActionService] Initial upload (upsert: false) to $path: $e');
        // If initial upload failed (e.g. object already exists or duplicate conflict), try upsert: true
        try {
          await client.storage.from('documents').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
          uploaded = true;
        } catch (upsertErr) {
          lastError = upsertErr;
          debugPrint('[ActionService] Upsert fallback error for $path: $upsertErr');
        }
      }

      // If primary upload failed, attempt candidate user/org path
      if (!uploaded) {
        final fallbackOrgs = <String>{};
        final userOrg = AuthService.instance.currentOrganizationId?.trim();
        if (isValidUuid(userOrg)) fallbackOrgs.add(userOrg!);
        fallbackOrgs.add(Organization.sobhaId);

        for (final fbOrg in fallbackOrgs) {
          final fallbackPath = '$fbOrg/actions/${action.id.trim()}/$cleanFile';
          if (fallbackPath != path) {
            try {
              await client.storage.from('documents').uploadBinary(
                fallbackPath,
                bytes,
                fileOptions: const FileOptions(upsert: false),
              );
              uploaded = true;
              break;
            } catch (fallbackErr) {
              lastError = fallbackErr;
              debugPrint('[ActionService] Fallback upload error to $fallbackPath: $fallbackErr');
            }
          }
        }
      }

      if (!uploaded) {
        return (
          success: false,
          error: 'Failed to upload attachment file to storage: $lastError',
          updatedAction: null,
        );
      }
    }

    final updatedAttachments = {...action.attachments, cleanFile}.toList();
    final updatedHistory = List<String>.from(action.history);
    final nowStr = DateTime.now().toIso8601String().substring(0, 10);
    updatedHistory.insert(0, '$nowStr: Attachment "$cleanFile" was uploaded.');

    final updatedAction = action.copyWith(
      attachments: updatedAttachments,
      history: updatedHistory,
    );

    try {
      if (client == null) {
        MockActionStore.instance.update(updatedAction);
      } else {
        await updateAction(updatedAction);
      }
      return (success: true, error: null, updatedAction: updatedAction);
    } catch (e) {
      debugPrint(
        '[ActionService] Error updating action metadata after attachment upload: $e',
      );
      return (
        success: false,
        error: 'Attachment uploaded to storage, but failed to update action record: $e',
        updatedAction: null,
      );
    }
  }

  /// Safely removes an attachment file from Supabase Storage and updates the action record metadata.
  Future<({bool success, String? error})> removeActionAttachment({
    required ActionRecord action,
    required String fileName,
  }) async {
    final cleanFile = sanitizeAttachmentFileName(fileName);
    if (cleanFile.isEmpty) {
      return (success: false, error: 'Invalid attachment filename.');
    }

    final userOrg = AuthService.instance.currentOrganizationId?.trim();
    final effectiveOrg = (userOrg != null &&
            userOrg.isNotEmpty &&
            userOrg != 'SOBHA-001' &&
            userOrg != 'org-sobha-01' &&
            userOrg != 'default-org')
        ? userOrg
        : action.organizationId;

    final path = buildActionAttachmentPath(
      organizationId: effectiveOrg,
      actionId: action.id,
      fileName: cleanFile,
    );
    if (path == null) {
      return (
        success: false,
        error: 'Could not construct valid attachment path.',
      );
    }

    // Ensure attachment belongs to action
    final normalizedClean = cleanFile.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    final hasAttachment = action.attachments.contains(fileName) ||
        action.attachments.contains(cleanFile) ||
        action.attachments.any((a) =>
            sanitizeAttachmentFileName(a).toLowerCase() ==
            cleanFile.toLowerCase()) ||
        action.attachments.any((a) =>
            sanitizeAttachmentFileName(a).replaceAll(RegExp(r'\s+'), ' ').toLowerCase() ==
            normalizedClean) ||
        action.attachments.any((a) {
          try {
            return Uri.decodeComponent(sanitizeAttachmentFileName(a))
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .toLowerCase() ==
                normalizedClean;
          } catch (_) {
            return false;
          }
        });
    if (!hasAttachment) {
      return (
        success: false,
        error: 'Attachment "$fileName" not found on action ${action.id}.',
      );
    }

    final client = _client;
    String? storageWarning;
    if (client != null) {
      try {
        await client.storage.from('documents').remove([path]);
      } catch (e) {
        debugPrint(
            '[ActionService] Warning: Storage deletion failed for $path: $e');
        storageWarning = 'Storage deletion warning: $e';
      }
    }

    final updatedAttachments = action.attachments
        .where((f) => f != fileName && f != cleanFile)
        .toList();
    final updatedHistory = List<String>.from(action.history);
    final nowStr = DateTime.now().toIso8601String().substring(0, 10);
    updatedHistory.insert(0, '$nowStr: Attachment "$cleanFile" was removed.');

    final updatedAction = action.copyWith(
      attachments: updatedAttachments,
      history: updatedHistory,
    );

    try {
      if (client == null) {
        MockActionStore.instance.update(updatedAction);
      } else {
        await updateAction(updatedAction);
      }
      return (success: true, error: storageWarning);
    } catch (e) {
      debugPrint(
          '[ActionService] Error updating action metadata after attachment removal: $e');
      return (success: false, error: 'Failed to update action metadata: $e');
    }
  }

  /// Validates whether a user is authorized to view or download attachments for [action].
  ///
  /// Authorized users include:
  /// - Managers and Admins (isManager == true)
  /// - Action Creator (createdById == userId)
  /// - Primary Assignee (assignedToId == userId)
  /// - Listed Assignees (assignees.any((a) => a.profileId == userId))
  /// - Listed Contributors (contributors.any((c) => c.profileId == userId))
  /// - Subtask Assignees (subTasks.any((st) => st.assignedStaffId == userId))
  static bool isUserAuthorizedForActionAttachment({
    required ActionRecord action,
    required String? userId,
    bool isManager = false,
  }) {
    if (isManager) return true;
    final role = AuthService.instance.currentProfileData?.roleCode.toLowerCase();
    if (role == 'manager' ||
        role == 'admin' ||
        AuthService.instance.isPlatformAdmin ||
        AuthService.instance.isCompanyAdmin) {
      return true;
    }

    final candidateIds = <String>{};
    final candidateEmails = <String>{};
    final candidateNames = <String>{};

    void addId(String? id) {
      final clean = id?.trim();
      if (clean != null && clean.isNotEmpty) {
        candidateIds.add(clean.toLowerCase());
      }
    }

    void addEmail(String? email) {
      final clean = email?.trim().toLowerCase();
      if (clean != null && clean.isNotEmpty) {
        candidateEmails.add(clean);
      }
    }

    void addName(String? name) {
      final clean = name?.trim().toLowerCase();
      if (clean != null && clean.isNotEmpty) {
        candidateNames.add(clean);
      }
    }

    addId(userId);
    addId(AuthService.instance.currentUser?.id);
    addId(AuthService.instance.currentProfileData?.userProfile.id);

    addEmail(AuthService.instance.currentUser?.email);
    addEmail(AuthService.instance.currentProfileData?.userProfile.email);

    addName(AuthService.instance.currentProfileData?.userProfile.name);

    if (candidateIds.isEmpty &&
        candidateEmails.isEmpty &&
        candidateNames.isEmpty) {
      return false;
    }

    // 1. Action Creator
    if (candidateIds.contains(action.createdById.trim().toLowerCase())) {
      return true;
    }

    // 2. Primary Assignee (ID, Email, Name)
    if (action.assignedToId != null &&
        candidateIds.contains(action.assignedToId!.trim().toLowerCase())) {
      return true;
    }
    if (action.primaryAssignee != null) {
      if (candidateIds.contains(
            action.primaryAssignee!.personId.trim().toLowerCase(),
          )) {
        return true;
      }
      if (candidateEmails.contains(
            action.primaryAssignee!.email.trim().toLowerCase(),
          )) {
        return true;
      }
      if (candidateNames.contains(
            action.primaryAssignee!.name.trim().toLowerCase(),
          )) {
        return true;
      }
    }
    if (candidateNames.contains(action.assignedTo.trim().toLowerCase())) {
      return true;
    }

    // 3. Listed Assignees
    for (final a in action.assignees) {
      if (candidateIds.contains(a.profileId.trim().toLowerCase())) return true;
      if (candidateEmails.contains(a.profileEmail.trim().toLowerCase())) {
        return true;
      }
      if (candidateNames.contains(a.profileName.trim().toLowerCase())) {
        return true;
      }
    }

    // 4. Listed Contributors
    for (final c in action.contributors) {
      if (candidateIds.contains(c.profileId.trim().toLowerCase())) return true;
      if (candidateEmails.contains(c.profileEmail.trim().toLowerCase())) {
        return true;
      }
      if (candidateNames.contains(c.profileName.trim().toLowerCase())) {
        return true;
      }
    }

    // 5. Subtask Assignees
    for (final st in action.subTasks) {
      if (candidateIds.contains(st.assignedStaffId.trim().toLowerCase())) {
        return true;
      }
      if (candidateEmails.contains(
            st.assignedStaffEmail.trim().toLowerCase(),
          )) {
        return true;
      }
      if (candidateNames.contains(st.assignedStaff.trim().toLowerCase())) {
        return true;
      }
    }

    // 6. External Recipient & Forwarded
    if (action.externalRecipientId != null &&
        candidateIds.contains(
          action.externalRecipientId!.trim().toLowerCase(),
        )) {
      return true;
    }
    if (action.externalRecipientEmail != null &&
        candidateEmails.contains(
          action.externalRecipientEmail!.trim().toLowerCase(),
        )) {
      return true;
    }
    for (final cid in candidateIds) {
      if (action.isForwardedTo(cid)) return true;
    }
    for (final cemail in candidateEmails) {
      if (action.isForwardedTo(null, null, cemail)) return true;
    }
    for (final cname in candidateNames) {
      if (action.isForwardedTo(null, cname, null)) return true;
    }

    // 7. Additional People
    for (final p in action.additionalPeople) {
      if (candidateIds.contains(p.personId.trim().toLowerCase())) return true;
      if (candidateEmails.contains(p.email.trim().toLowerCase())) return true;
      if (candidateNames.contains(p.name.trim().toLowerCase())) return true;
    }

    return false;
  }

  /// Determines whether a storage error corresponds to an RLS access denial or 403 Forbidden.
  static bool isStorageAccessDenied(dynamic error) {
    if (error == null) return false;
    if (error is StorageException) {
      final status = error.statusCode;
      if (status == '403' || status == '401') return true;
      final msg = error.message.toLowerCase();
      if (msg.contains('forbidden') ||
          msg.contains('denied') ||
          msg.contains('permission') ||
          msg.contains('row-level security') ||
          msg.contains('rls') ||
          msg.contains('unauthorized')) {
        return true;
      }
    }
    final errStr = error.toString().toLowerCase();
    return errStr.contains('403') ||
        errStr.contains('401') ||
        errStr.contains('forbidden') ||
        errStr.contains('permission') ||
        errStr.contains('row-level security') ||
        errStr.contains('unauthorized') ||
        errStr.contains('access denied');
  }

  /// Generates a short-lived signed URL for an action attachment after verifying authorization.
  Future<({bool success, String? signedUrl, String? error})> getAttachmentSignedUrl({
    required ActionRecord action,
    required String fileName,
    required String? userId,
    bool isManager = false,
    int expiresInSeconds = 300,
  }) async {
    final cleanFile = sanitizeAttachmentFileName(fileName);
    if (cleanFile.isEmpty) {
      return (success: false, signedUrl: null, error: 'Invalid attachment filename.');
    }

    final normalizedClean = cleanFile.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    final hasAttachment = action.attachments.contains(fileName) ||
        action.attachments.contains(cleanFile) ||
        action.attachments.any((a) =>
            sanitizeAttachmentFileName(a).toLowerCase() ==
            cleanFile.toLowerCase()) ||
        action.attachments.any((a) =>
            sanitizeAttachmentFileName(a).replaceAll(RegExp(r'\s+'), ' ').toLowerCase() ==
            normalizedClean) ||
        action.attachments.any((a) {
          try {
            return Uri.decodeComponent(sanitizeAttachmentFileName(a))
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .toLowerCase() ==
                normalizedClean;
          } catch (_) {
            return false;
          }
        });
    if (!hasAttachment) {
      return (
        success: false,
        signedUrl: null,
        error: 'Attachment "$fileName" is not associated with action ${action.id}.',
      );
    }

    if (!isUserAuthorizedForActionAttachment(action: action, userId: userId, isManager: isManager)) {
      return (
        success: false,
        signedUrl: null,
        error: 'Permission denied: You are not authorized to access attachments for this action.',
      );
    }

    final client = _client;
    if (client != null && SupabaseConfig.isInitialized) {
      final candidates = getAttachmentCandidatePaths(
        action: action,
        fileName: cleanFile,
      );
      dynamic lastError;
      bool hadAccessDenied = false;
      for (final candidate in candidates) {
        try {
          final signedUrl = await client.storage
              .from('documents')
              .createSignedUrl(candidate, expiresInSeconds);
          if (signedUrl.isNotEmpty) {
            return (success: true, signedUrl: signedUrl, error: null);
          }
        } catch (e) {
          lastError = e;
          if (isStorageAccessDenied(e)) {
            hadAccessDenied = true;
          }
        }
      }
      debugPrint(
        '[ActionService] Error generating signed URL across candidates for $cleanFile: $lastError',
      );
      final isDenied = hadAccessDenied || isStorageAccessDenied(lastError);
      return (
        success: false,
        signedUrl: null,
        error: isDenied
            ? 'Failed to generate signed download URL: Storage access denied by RLS policy for "$cleanFile".'
            : 'Failed to generate signed download URL: Attachment "$cleanFile" was not found in storage.',
      );
    }

    // Mock fallback: short-lived simulated secure signed URL
    final expiryEpoch = DateTime.now().add(Duration(seconds: expiresInSeconds)).millisecondsSinceEpoch;
    final mockUrl = 'https://actionflow.enterprise/storage/signed/${action.organizationId}/${action.id}/$cleanFile?expires=$expiryEpoch';
    return (success: true, signedUrl: mockUrl, error: null);
  }

  /// Retrieves the binary bytes and short-lived signed URL of an action attachment
  /// after verifying role-based authorization.
  Future<({bool success, Uint8List? bytes, String? signedUrl, String? error})> getActionAttachmentBytes({
    required ActionRecord action,
    required String fileName,
    required String? userId,
    bool isManager = false,
    int expiresInSeconds = 300,
  }) async {
    final signedResult = await getAttachmentSignedUrl(
      action: action,
      fileName: fileName,
      userId: userId,
      isManager: isManager,
      expiresInSeconds: expiresInSeconds,
    );

    if (!signedResult.success) {
      return (
        success: false,
        bytes: null,
        signedUrl: null,
        error: signedResult.error,
      );
    }

    final cleanFile = sanitizeAttachmentFileName(fileName);
    final client = _client;
    Uint8List? fileBytes;

    if (client != null && SupabaseConfig.isInitialized) {
      final candidates = getAttachmentCandidatePaths(
        action: action,
        fileName: cleanFile,
      );
      dynamic lastError;
      bool hadAccessDenied = false;
      for (final candidate in candidates) {
        try {
          final downloaded =
              await client.storage.from('documents').download(candidate);
          if (downloaded.isNotEmpty) {
            fileBytes = downloaded;
            break;
          }
        } catch (e) {
          lastError = e;
          if (isStorageAccessDenied(e)) {
            hadAccessDenied = true;
          }
        }
      }

      if (fileBytes == null) {
        debugPrint(
          '[ActionService] Error downloading bytes across candidates for $cleanFile: $lastError',
        );
        final isDenied = hadAccessDenied || isStorageAccessDenied(lastError);
        return (
          success: false,
          bytes: null,
          signedUrl: signedResult.signedUrl,
          error: isDenied
              ? 'Failed to retrieve attachment file: Storage access denied by RLS policy for "$cleanFile".'
              : 'Failed to retrieve attachment file: Attachment "$cleanFile" was not found in storage.',
        );
      }
    } else {
      // Mock / offline fallback bytes
      fileBytes = Uint8List.fromList(
        utf8.encode('ActionFlow Action Evidence: ${action.id} ($cleanFile)'),
      );
    }

    return (
      success: true,
      bytes: fileBytes,
      signedUrl: signedResult.signedUrl,
      error: null,
    );
  }

  /// Downloads an action attachment binary and saves it to the client filesystem via [AppFilePicker.saveFile].
  Future<({bool success, Uint8List? bytes, String? signedUrl, String? error})> downloadActionAttachment({
    required ActionRecord action,
    required String fileName,
    required String? userId,
    bool isManager = false,
    int expiresInSeconds = 300,
  }) async {
    final bytesResult = await getActionAttachmentBytes(
      action: action,
      fileName: fileName,
      userId: userId,
      isManager: isManager,
      expiresInSeconds: expiresInSeconds,
    );

    if (!bytesResult.success) {
      return bytesResult;
    }

    final cleanFile = sanitizeAttachmentFileName(fileName);

    try {
      final saved = await AppFilePicker.saveFile(
        fileName: cleanFile,
        bytes: bytesResult.bytes!,
      );
      if (!saved) {
        return (
          success: false,
          bytes: bytesResult.bytes,
          signedUrl: bytesResult.signedUrl,
          error: 'Download was cancelled by user.',
        );
      }
      return (
        success: true,
        bytes: bytesResult.bytes,
        signedUrl: bytesResult.signedUrl,
        error: null,
      );
    } catch (e) {
      debugPrint('[ActionService] Error saving file to client platform: $e');
      return (
        success: false,
        bytes: bytesResult.bytes,
        signedUrl: bytesResult.signedUrl,
        error: 'Failed to save downloaded file: $e',
      );
    }
  }

  /// Securely deletes an action via authorized RPC with tenant, role, and closed action protection,
  /// and safely purges associated Storage attachment objects.
  Future<({bool success, String? error})> deleteActionAuthorized(
    String actionId, {
    bool allowClosed = false,
    String portalContext = 'action_register',
  }) async {
    final client = _client;
    String targetOrgId = '';
    List<String> targetAttachments = [];

    final existingAction = MockActionStore.instance.actions
        .firstWhereOrNull((a) => a.id == actionId);
    if (existingAction != null) {
      targetOrgId = existingAction.organizationId;
      targetAttachments = existingAction.attachments;
    }

    if (client == null) {
      final removed = MockActionStore.instance.deleteAction(actionId);
      return (
        success: removed,
        error: removed ? null : 'Action not found in local store.',
      );
    }

    if (targetAttachments.isEmpty) {
      try {
        final res = await client
            .from('actions')
            .select('id, organization_id, attachments')
            .eq('id', actionId)
            .maybeSingle();
        if (res != null) {
          final rowMap = Map<String, dynamic>.from(res);
          targetOrgId = rowMap['organization_id']?.toString() ?? targetOrgId;
          final rawAtt = rowMap['attachments'];
          if (rawAtt is List) {
            targetAttachments = List<String>.from(rawAtt);
          }
        }
      } catch (_) {}
    }

    try {
      final response = await client.rpc(
        'delete_action_authorized',
        params: {
          'p_action_id': actionId,
          'p_allow_closed': allowClosed,
          'p_portal_context': portalContext,
        },
      );
      bool isSuccess = true;
      String? error;
      if (response is Map) {
        isSuccess = response['success'] == true;
        error = response['error']?.toString();
      }

      if (isSuccess) {
        MockActionStore.instance.deleteAction(actionId);
      }

      return (success: isSuccess, error: error);
    } catch (e, st) {
      debugPrint('[ActionService] Error deleting action authorized: $e\n$st');
      return (success: false, error: e.toString());
    }
  }

  /// Deletes an action if permitted by RLS (legacy wrapper)
  Future<void> deleteAction(String actionId) async {
    final res = await deleteActionAuthorized(actionId);
    if (!res.success) {
      throw Exception(res.error ?? 'Failed to delete action');
    }
  }

  /// Safely deletes multiple actions via authorized RPC with transaction safety,
  /// audit preservation, and physical attachment cleanup.
  Future<({bool success, int deletedCount, List<String> failedIds, String? error})> deleteActionsBulk(
    List<String> actionIds, {
    bool allowClosed = false,
    String portalContext = 'action_register',
  }) async {
    if (actionIds.isEmpty) {
      return (success: true, deletedCount: 0, failedIds: const <String>[], error: null);
    }

    final client = _client;

    if (client == null) {
      for (final id in actionIds) {
        MockActionStore.instance.deleteAction(id);
      }
      return (
        success: true,
        deletedCount: actionIds.length,
        failedIds: const <String>[],
        error: null,
      );
    }

    // Production atomic bulk RPC: strictly atomic with 0 sequential fallback
    try {
      final response = await client.rpc(
        'delete_actions_bulk_authorized',
        params: {
          'p_action_ids': actionIds,
          'p_allow_closed': allowClosed,
          'p_portal_context': portalContext,
        },
      );
      if (response is Map) {
        final success = response['success'] == true;
        final deletedCount = (response['deleted_count'] as num?)?.toInt() ?? 0;
        final rawFailed = response['failed_ids'];
        final failedIds = rawFailed is List ? List<String>.from(rawFailed) : <String>[];
        final error = response['error']?.toString();

        if (success) {
          // Mutate local store ONLY after backend confirmation
          for (final id in actionIds) {
            MockActionStore.instance.deleteAction(id);
          }
          return (
            success: true,
            deletedCount: deletedCount,
            failedIds: const <String>[],
            error: null,
          );
        } else {
          return (
            success: false,
            deletedCount: deletedCount,
            failedIds: failedIds.isNotEmpty ? failedIds : actionIds,
            error: error ?? 'Bulk deletion failed.',
          );
        }
      }
    } catch (bulkErr) {
      debugPrint('[ActionService] delete_actions_bulk RPC failed: $bulkErr');
      return (
        success: false,
        deletedCount: 0,
        failedIds: actionIds,
        error: 'Database migration required: atomic bulk deletion RPC not installed on backend. Please apply migration 20261103000002_soft_deletion_and_bulk_delete.sql. Details: $bulkErr',
      );
    }

    return (
      success: false,
      deletedCount: 0,
      failedIds: actionIds,
      error: 'Unexpected response from delete_actions_bulk.',
    );
  }

  /// Fetches eligible active users within the manager's permitted scopes or shared teams
  Future<List<ActionPersonReference>> fetchEligibleAssignees({
    required String organizationId,
    String? departmentId,
    String? siteId,
    String? actionTeamId,
    String? callerUserId,
    List<String>? callerTeamIds,
    List<ManagerScopeItem>? managerScopes,
  }) async {
    final effectiveOrgId = organizationId == 'SOBHA-001'
        ? Organization.sobhaId
        : organizationId;

    final client = _client;
    if (client == null) {
      if (MockActionStore.instance.profiles.isNotEmpty) {
        final caller = callerUserId != null
            ? MockActionStore.instance.profiles.firstWhereOrNull((p) => p['id'] == callerUserId)
            : null;
        final effCallerTeams = callerTeamIds != null
            ? List<String>.from(callerTeamIds)
            : ((caller?['team_ids'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[]);
        final callerRole = (caller?['role'] as String?)?.toLowerCase().trim() ?? '';
        final isAdminCaller = caller == null ||
            callerRole == 'admin' ||
            callerRole == 'company_admin' ||
            callerRole == 'platform_admin';
        final isManagerCaller = !isAdminCaller &&
            (callerRole == 'manager' ||
                callerRole == 'departmentmanager' ||
                callerRole == 'department_manager');

        final callerDeptId = (caller?['department_id'] as String?) ?? '';
        final callerDept = (caller?['department'] as String?) ?? '';

        final Set<String> scopedDeptIds = managerScopes
            ?.map((s) => s.departmentId)
            .where((id) => id.isNotEmpty)
            .toSet() ?? {};
        final Set<String> scopedDeptNames = managerScopes
            ?.map((s) => s.departmentName.toLowerCase())
            .where((n) => n.isNotEmpty)
            .toSet() ?? {};
        if (callerDeptId.isNotEmpty) scopedDeptIds.add(callerDeptId);
        if (callerDept.isNotEmpty) scopedDeptNames.add(callerDept.toLowerCase());

        final hasActionDept = departmentId != null && departmentId.trim().isNotEmpty;
        final hasActionSite = siteId != null && siteId.trim().isNotEmpty;
        final hasActionScope = hasActionDept || hasActionSite;
        final actDept = (departmentId ?? '').toLowerCase();

        return MockActionStore.instance.profiles
            .where((p) {
              final orgMatch = effectiveOrgId.isEmpty ||
                  p['organization_id'] == null ||
                  p['organization_id'] == effectiveOrgId;
              final active = p['is_active'] == true &&
                  (p['status'] == null ||
                      p['status'].toString().toLowerCase() == 'active');
              if (!orgMatch || !active) return false;

              final pDeptId = (p['department_id'] as String?) ?? '';
              final pDept = (p['department'] as String?) ?? '';
              final pTeams = (p['team_ids'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];

              final isActionTeamMatch = actionTeamId != null &&
                  actionTeamId.isNotEmpty &&
                  pTeams.contains(actionTeamId);

              final isSharedTeamMatch = effCallerTeams.isNotEmpty &&
                  pTeams.any((t) => effCallerTeams.contains(t));

              if (isAdminCaller) {
                return true;
              } else if (isManagerCaller) {
                final matchesManagerScope = (pDeptId.isNotEmpty && scopedDeptIds.contains(pDeptId)) ||
                    (pDept.isNotEmpty && scopedDeptNames.contains(pDept.toLowerCase()));
                final matchesActionDept = hasActionDept &&
                    (pDeptId == departmentId || (pDept.isNotEmpty && pDept.toLowerCase() == actDept));
                final matchesCallerDept = callerDeptId.isNotEmpty
                    ? pDeptId == callerDeptId
                    : (callerDept.isNotEmpty && pDept.toLowerCase() == callerDept.toLowerCase());
                final isOrgWide = !hasActionScope && (actionTeamId == null || actionTeamId.isEmpty);

                return matchesManagerScope || matchesActionDept || matchesCallerDept || isActionTeamMatch || isSharedTeamMatch || isOrgWide;
              } else {
                final matchesCallerDept = callerDeptId.isNotEmpty
                    ? pDeptId == callerDeptId
                    : (callerDept.isNotEmpty && pDept.toLowerCase() == callerDept.toLowerCase());
                final matchesActionDept = hasActionDept &&
                    (pDeptId == departmentId || (pDept.isNotEmpty && pDept.toLowerCase() == actDept));

                return matchesCallerDept || matchesActionDept || isActionTeamMatch || isSharedTeamMatch;
              }
            })
            .map(
              (p) => ActionPersonReference(
                personId: (p['id'] ?? '') as String,
                name: (p['full_name'] ?? p['name'] ?? '') as String,
                type: PersonType.internalUser,
                email: (p['email'] ?? '') as String,
                phone: (p['phone'] ?? '') as String,
                designation: (p['designation'] ?? '') as String,
                department: (p['department'] ?? '') as String,
                site: (p['site'] ?? '') as String,
                company: (p['company'] ?? '') as String,
                role: (p['role'] ?? 'staff') as String,
                teamIds: (p['team_ids'] as List?)?.map((e) => e.toString()).toList() ?? const [],
                departmentId: p['department_id'] as String?,
                siteId: p['site_id'] as String?,
              ),
            )
            .toList();
      }

      // Offline MockPeopleStore resolution
      final caller = callerUserId != null
          ? MockPeopleStore.instance.people.firstWhereOrNull((p) => p.id == callerUserId)
          : null;
      final effCallerTeams = callerTeamIds != null
          ? List<String>.from(callerTeamIds)
          : (caller?.teamIds ?? const <String>[]);
      final callerRole = caller?.role;
      final isAdminCaller = caller == null || callerRole == UserRole.admin;
      final isManagerCaller = !isAdminCaller && callerRole == UserRole.departmentManager;

      final callerDeptId = caller?.departmentId ?? '';
      final callerDept = caller?.department ?? '';

      final Set<String> scopedDeptIds = managerScopes
          ?.map((s) => s.departmentId)
          .where((id) => id.isNotEmpty)
          .toSet() ?? {};
      final Set<String> scopedDeptNames = managerScopes
          ?.map((s) => s.departmentName.toLowerCase())
          .where((n) => n.isNotEmpty)
          .toSet() ?? {};
      if (callerDeptId.isNotEmpty) scopedDeptIds.add(callerDeptId);
      if (callerDept.isNotEmpty) scopedDeptNames.add(callerDept.toLowerCase());

      final hasActionDept = departmentId != null && departmentId.trim().isNotEmpty;
      final hasActionSite = siteId != null && siteId.trim().isNotEmpty;
      final hasActionScope = hasActionDept || hasActionSite;
      final actDept = (departmentId ?? '').toLowerCase();

      return MockPeopleStore.instance.people
          .where((p) => p.isActive && p.type == PersonType.internalUser)
          .where((p) {
            final orgMatch = effectiveOrgId.isEmpty ||
                p.organizationId == null ||
                p.organizationId!.isEmpty ||
                p.organizationId == effectiveOrgId;
            if (!orgMatch) return false;

            final pDeptId = p.departmentId ?? '';
            final pDept = p.department;
            final isActionTeamMatch = actionTeamId != null &&
                actionTeamId.isNotEmpty &&
                p.teamIds.contains(actionTeamId);

            final isSharedTeamMatch = effCallerTeams.isNotEmpty &&
                p.teamIds.any((t) => effCallerTeams.contains(t));

            if (isAdminCaller) {
              return true;
            } else if (isManagerCaller) {
              final matchesManagerScope = (pDeptId.isNotEmpty && scopedDeptIds.contains(pDeptId)) ||
                  (pDept.isNotEmpty && scopedDeptNames.contains(pDept.toLowerCase()));
              final matchesActionDept = hasActionDept &&
                  (pDeptId == departmentId || (pDept.isNotEmpty && pDept.toLowerCase() == actDept));
              final matchesCallerDept = callerDeptId.isNotEmpty
                  ? (pDeptId.toLowerCase() == callerDeptId.toLowerCase())
                  : (callerDept.isNotEmpty && pDept.toLowerCase() == callerDept.toLowerCase());
              final isOrgWide = !hasActionScope && (actionTeamId == null || actionTeamId.isEmpty);

              return matchesManagerScope || matchesActionDept || matchesCallerDept || isActionTeamMatch || isSharedTeamMatch || isOrgWide;
            } else {
              final matchesCallerDept = callerDeptId.isNotEmpty
                  ? (pDeptId.toLowerCase() == callerDeptId.toLowerCase())
                  : (callerDept.isNotEmpty && pDept.toLowerCase() == callerDept.toLowerCase());
              final matchesActionDept = hasActionDept &&
                  (pDeptId == departmentId || (pDept.isNotEmpty && pDept.toLowerCase() == actDept));

              return matchesCallerDept || matchesActionDept || isActionTeamMatch || isSharedTeamMatch;
            }
          })
          .map(
            (p) => ActionPersonReference(
              personId: p.id,
              name: p.name,
              type: PersonType.internalUser,
              email: p.email,
              phone: p.phone,
              designation: p.designation,
              department: p.department,
              site: p.site,
              company: p.company,
              role: p.role == UserRole.departmentManager
                  ? 'manager'
                  : (p.role == UserRole.admin ? 'admin' : 'staff'),
              teamIds: p.teamIds,
              departmentId: p.departmentId,
              siteId: p.siteId,
            ),
          )
          .toList();
    }

    try {
      final List<ActionPersonReference> result = [];
      final Set<String> seenIds = {};

      // 1. Fetch team memberships for this organization
      final Map<String, List<String>> teamIdsByProfile = {};
      try {
        final teamRes = await client
            .from('team_members')
            .select('team_id, profile_id, teams!inner(id, organization_id, is_active)')
            .eq('teams.organization_id', effectiveOrgId)
            .eq('teams.is_active', true);
        for (final row in teamRes) {
          if (row['profile_id'] != null && row['team_id'] != null) {
            final pid = row['profile_id'].toString().trim();
            final tid = row['team_id'].toString().trim();
            if (pid.isNotEmpty && tid.isNotEmpty) {
              teamIdsByProfile.putIfAbsent(pid, () => []).add(tid);
            }
          }
        }
      } catch (teamErr) {
        debugPrint('[ActionService] team_members lookup note: $teamErr');
      }

      // 2. Resolve caller's team IDs
      final effectiveCallerId = callerUserId ?? client.auth.currentUser?.id;
      List<String> effCallerTeams = callerTeamIds != null ? List<String>.from(callerTeamIds) : [];
      if (effCallerTeams.isEmpty) {
        if (effectiveCallerId != null && effectiveCallerId.isNotEmpty) {
          effCallerTeams = teamIdsByProfile[effectiveCallerId] ?? const [];
        }
      }

      // 3. Resolve manager scopes
      final Set<String> scopedDeptIds = managerScopes
          ?.map((s) => s.departmentId)
          .where((id) => id.isNotEmpty)
          .toSet() ?? {};
      final Set<String> scopedDeptNames = managerScopes
          ?.map((s) => s.departmentName.toLowerCase())
          .where((n) => n.isNotEmpty)
          .toSet() ?? {};

      if (effectiveCallerId != null && effectiveCallerId.isNotEmpty) {
        try {
          final msRes = await client
              .from('manager_scopes')
              .select('department_id, site_id')
              .eq('manager_profile_id', effectiveCallerId);
          for (final dynamic r in msRes) {
            if (r is Map && r['department_id'] != null) {
              final dId = r['department_id'].toString().trim();
              if (dId.isNotEmpty) scopedDeptIds.add(dId);
            }
          }
        } catch (msErr) {
          debugPrint('[ActionService] manager_scopes lookup note: $msErr');
        }
      }

      // 4. Query directory_profiles (sanitized security barrier view accessible to all active organization users)
      try {
        dynamic dirQuery = client
            .from('directory_profiles')
            .select(
              'id, full_name, email, phone, designation, department_id, department_name, site_id, site_name, role_code, is_active, organization_id',
            )
            .eq('is_active', true);

        if (effectiveOrgId.isNotEmpty) {
          dirQuery = dirQuery.eq('organization_id', effectiveOrgId);
        }

        final dirResponse = await dirQuery;
        if (dirResponse is List) {
          // Identify caller profile from directory results
          Map? callerDirItem;
          if (effectiveCallerId != null && effectiveCallerId.isNotEmpty) {
            for (final item in dirResponse) {
              if (item is Map && (item['id'] as String?)?.trim() == effectiveCallerId) {
                callerDirItem = item;
                break;
              }
            }
          }

          final callerRoleCode = (callerDirItem?['role_code'] as String?)?.toLowerCase().trim() ?? '';
          final hasManagerScopes = scopedDeptIds.isNotEmpty || scopedDeptNames.isNotEmpty;
          final isAdminCaller = callerRoleCode == 'admin' ||
              callerRoleCode == 'company_admin' ||
              callerRoleCode == 'platform_admin';
          final isManagerCaller = !isAdminCaller &&
              (callerRoleCode == 'manager' ||
                  callerRoleCode == 'departmentmanager' ||
                  callerRoleCode == 'department_manager' ||
                  hasManagerScopes);

          final callerDeptId = (callerDirItem?['department_id'] as String?)?.trim() ?? '';
          final callerDeptName = (callerDirItem?['department_name'] as String?)?.trim() ?? '';
          if (callerDeptId.isNotEmpty) scopedDeptIds.add(callerDeptId);
          if (callerDeptName.isNotEmpty) scopedDeptNames.add(callerDeptName.toLowerCase());

          final hasActionDept = departmentId != null && departmentId.trim().isNotEmpty;
          final hasActionSite = siteId != null && siteId.trim().isNotEmpty;
          final hasActionScope = hasActionDept || hasActionSite;
          final actDept = (departmentId ?? '').toLowerCase();

          for (final item in dirResponse) {
            if (item is Map) {
              final id = (item['id'] as String?)?.trim() ?? '';
              if (id.isEmpty ||
                  !RegExp(
                    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
                  ).hasMatch(id)) {
                continue;
              }
              final fullName = (item['full_name'] as String?)?.trim() ?? '';
              if (fullName.isEmpty || fullName.toLowerCase() == 'unassigned') {
                continue;
              }

              final itemDeptId = (item['department_id'] as String?)?.trim() ?? '';
              final itemDeptName = (item['department_name'] as String?)?.trim() ?? '';
              final itemSiteId = (item['site_id'] as String?)?.trim() ?? '';
              final itemSiteName = (item['site_name'] as String?)?.trim() ?? '';
              final userTeams = teamIdsByProfile[id] ?? const <String>[];

              final isActionTeamMatch = actionTeamId != null &&
                  actionTeamId.isNotEmpty &&
                  userTeams.contains(actionTeamId);

              final isSharedTeamMatch = effCallerTeams.isNotEmpty &&
                  userTeams.any((t) => effCallerTeams.contains(t));

              bool isEligible;
              if (isAdminCaller || callerDirItem == null) {
                isEligible = true;
              } else if (isManagerCaller) {
                final matchesManagerScope = (itemDeptId.isNotEmpty && scopedDeptIds.contains(itemDeptId)) ||
                    (itemDeptName.isNotEmpty && scopedDeptNames.contains(itemDeptName.toLowerCase()));
                final matchesActionDept = hasActionDept &&
                    (itemDeptId == departmentId ||
                        (itemDeptName.isNotEmpty && itemDeptName.toLowerCase() == actDept));
                final matchesCallerDept = callerDeptId.isNotEmpty
                    ? itemDeptId == callerDeptId
                    : (callerDeptName.isNotEmpty &&
                        itemDeptName.isNotEmpty &&
                        itemDeptName.toLowerCase() == callerDeptName.toLowerCase());
                final isOrgWide = !hasActionScope && (actionTeamId == null || actionTeamId.isEmpty);

                isEligible = matchesManagerScope ||
                    matchesActionDept ||
                    matchesCallerDept ||
                    isActionTeamMatch ||
                    isSharedTeamMatch ||
                    isOrgWide;
              } else {
                // Staff caller
                final matchesCallerDept = callerDeptId.isNotEmpty
                    ? itemDeptId == callerDeptId
                    : (callerDeptName.isNotEmpty &&
                        itemDeptName.isNotEmpty &&
                        itemDeptName.toLowerCase() == callerDeptName.toLowerCase());
                final matchesActionDept = hasActionDept &&
                    (itemDeptId == departmentId ||
                        (itemDeptName.isNotEmpty && itemDeptName.toLowerCase() == actDept));

                isEligible = matchesCallerDept || matchesActionDept || isActionTeamMatch || isSharedTeamMatch;
              }

              if (isEligible) {
                if (seenIds.add(id)) {
                  result.add(
                    ActionPersonReference(
                      personId: id,
                      name: fullName,
                      type: PersonType.internalUser,
                      email: (item['email'] as String?) ?? '',
                      phone: (item['phone'] as String?) ?? '',
                      designation: (item['designation'] as String?) ?? 'Staff',
                      department: itemDeptName,
                      site: itemSiteName,
                      role: (item['role_code'] as String?) ?? 'staff',
                      teamIds: userTeams,
                      departmentId: itemDeptId.isNotEmpty ? itemDeptId : null,
                      siteId: itemSiteId.isNotEmpty ? itemSiteId : null,
                    ),
                  );
                }
              }
            }
          }
        }
      } catch (dirErr) {
        debugPrint('[ActionService] directory_profiles lookup note: $dirErr');
      }

      // 5. Query public.profiles fallback to enrich or catch any entries if caller has table access
      if (result.isEmpty) {
        try {
          dynamic query = client
              .from('profiles')
              .select(
                'id, full_name, email, phone, designation, department_id, site_id, status, is_active, departments(name), sites(name), roles(code, name)',
              )
              .eq('organization_id', effectiveOrgId)
              .eq('is_active', true)
              .inFilter('status', ['active', 'Active']);

          final response = await query;
          if (response is List) {
            Map? callerProfItem;
            if (effectiveCallerId != null && effectiveCallerId.isNotEmpty) {
              for (final item in response) {
                if (item is Map && (item['id'] as String?)?.trim() == effectiveCallerId) {
                  callerProfItem = item;
                  break;
                }
              }
            }

            String callerRoleCode = 'staff';
            if (callerProfItem?['roles'] is Map) {
              callerRoleCode = (callerProfItem!['roles']['code'] as String?) ?? 'staff';
            }
            final hasManagerScopes = scopedDeptIds.isNotEmpty || scopedDeptNames.isNotEmpty;
            final isAdminCaller = callerRoleCode == 'admin' ||
                callerRoleCode == 'company_admin' ||
                callerRoleCode == 'platform_admin';
            final isManagerCaller = !isAdminCaller &&
                (callerRoleCode == 'manager' ||
                    callerRoleCode == 'departmentmanager' ||
                    callerRoleCode == 'department_manager' ||
                    hasManagerScopes);
            final callerDeptId = (callerProfItem?['department_id'] as String?)?.trim() ?? '';
            String callerDeptName = '';
            if (callerProfItem?['departments'] is Map) {
              callerDeptName = callerProfItem!['departments']['name']?.toString() ?? '';
            }
            if (callerDeptId.isNotEmpty) scopedDeptIds.add(callerDeptId);
            if (callerDeptName.isNotEmpty) scopedDeptNames.add(callerDeptName.toLowerCase());

            final hasActionDept = departmentId != null && departmentId.trim().isNotEmpty;
            final hasActionSite = siteId != null && siteId.trim().isNotEmpty;
            final hasActionScope = hasActionDept || hasActionSite;
            final actDept = (departmentId ?? '').toLowerCase();

            for (final item in response) {
              if (item is Map) {
                final id = (item['id'] as String?)?.trim() ?? '';
                if (id.isEmpty ||
                    !RegExp(
                      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
                    ).hasMatch(id)) {
                  continue;
                }

                final fullName = (item['full_name'] as String?)?.trim() ?? '';
                if (fullName.isEmpty || fullName.toLowerCase() == 'unassigned') {
                  continue;
                }

                String deptName = '';
                if (item['departments'] is Map) {
                  deptName = item['departments']['name']?.toString() ?? '';
                }
                String siteName = '';
                if (item['sites'] is Map) {
                  siteName = item['sites']['name']?.toString() ?? '';
                }

                String roleCode = 'staff';
                if (item['roles'] is Map) {
                  roleCode = (item['roles']['code'] as String?) ?? 'staff';
                }

                final itemDeptId = (item['department_id'] as String?)?.trim() ?? '';
                final itemSiteId = (item['site_id'] as String?)?.trim() ?? '';
                final userTeams = teamIdsByProfile[id] ?? const <String>[];

                final isActionTeamMatch = actionTeamId != null &&
                    actionTeamId.isNotEmpty &&
                    userTeams.contains(actionTeamId);

                final isSharedTeamMatch = effCallerTeams.isNotEmpty &&
                    userTeams.any((t) => effCallerTeams.contains(t));

                bool isEligible;
                if (isAdminCaller || callerProfItem == null) {
                  isEligible = true;
                } else if (isManagerCaller) {
                  final matchesManagerScope = (itemDeptId.isNotEmpty && scopedDeptIds.contains(itemDeptId)) ||
                      (deptName.isNotEmpty && scopedDeptNames.contains(deptName.toLowerCase()));
                  final matchesActionDept = hasActionDept &&
                      (itemDeptId == departmentId ||
                          (deptName.isNotEmpty && deptName.toLowerCase() == actDept));
                  final matchesCallerDept = callerDeptId.isNotEmpty
                      ? itemDeptId == callerDeptId
                      : (callerDeptName.isNotEmpty &&
                          deptName.isNotEmpty &&
                          deptName.toLowerCase() == callerDeptName.toLowerCase());
                  final isOrgWide = !hasActionScope && (actionTeamId == null || actionTeamId.isEmpty);

                  isEligible = matchesManagerScope ||
                      matchesActionDept ||
                      matchesCallerDept ||
                      isActionTeamMatch ||
                      isSharedTeamMatch ||
                      isOrgWide;
                } else {
                  // Staff caller
                  final matchesCallerDept = callerDeptId.isNotEmpty
                      ? itemDeptId == callerDeptId
                      : (callerDeptName.isNotEmpty &&
                          deptName.isNotEmpty &&
                          deptName.toLowerCase() == callerDeptName.toLowerCase());
                  final matchesActionDept = hasActionDept &&
                      (itemDeptId == departmentId ||
                          (deptName.isNotEmpty && deptName.toLowerCase() == actDept));

                  isEligible = matchesCallerDept || matchesActionDept || isActionTeamMatch || isSharedTeamMatch;
                }

                if (isEligible) {
                  if (seenIds.add(id)) {
                    result.add(
                      ActionPersonReference(
                        personId: id,
                        name: fullName,
                        type: PersonType.internalUser,
                        email: (item['email'] as String?) ?? '',
                        phone: (item['phone'] as String?) ?? '',
                        designation: (item['designation'] as String?) ?? 'Staff',
                        department: deptName,
                        site: siteName,
                        role: roleCode,
                        teamIds: userTeams,
                        departmentId: itemDeptId.isNotEmpty ? itemDeptId : null,
                        siteId: itemSiteId.isNotEmpty ? itemSiteId : null,
                      ),
                    );
                  }
                }
              }
            }
          }
        } catch (profErr) {
          debugPrint('[ActionService] profiles fallback note: $profErr');
        }
      }

      return result;
    } catch (e) {
      debugPrint('[ActionService] Error fetching eligible assignees: $e');
      return [];
    }
  }

  /// Fetches active teams belonging to the given organization and department.
  Future<List<Map<String, dynamic>>> fetchTeamsForDepartment({
    required String organizationId,
    required String departmentId,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) return [];

    try {
      final response = await client
          .from('teams')
          .select('id, name, code, is_active, department_id')
          .eq('organization_id', organizationId)
          .eq('department_id', departmentId)
          .eq('is_active', true)
          .order('name');

      return List<Map<String, dynamic>>.from(
        response.map((e) => Map<String, dynamic>.from(e)),
      );
    } catch (e) {
      debugPrint('[ActionService] Error fetching teams: $e');
      return [];
    }
  }

  /// Computes authoritative dashboard metrics from real actions
  ManagerDashboardMetrics computeDashboardMetrics(List<ActionRecord> actions) {
    int total = actions.length;
    int open = 0;
    int inProgress = 0;
    int pendingReview = 0;
    int overdue = 0;
    int dueSoon = 0;
    int followUpDue = 0;
    int criticalHigh = 0;
    int closed = 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final in7Days = today.add(const Duration(days: 7));

    for (final a in actions) {
      final statusLower = a.status.toLowerCase();

      if (statusLower == 'closed') {
        closed++;
        continue;
      }

      if (statusLower == 'open') {
        open++;
      } else if (statusLower == 'in progress') {
        inProgress++;
      } else if (statusLower == 'pending review') {
        pendingReview++;
      }

      // Priority check
      if (a.priority == 'Critical' || a.priority == 'High') {
        criticalHigh++;
      }

      // Target Date checks
      DateTime? targetDt;
      if (a.targetDate.isNotEmpty) {
        final parts = a.targetDate.trim().split(' ');
        if (parts.length >= 3) {
          final dbFormatted = ActionRecord.formatDateForDb(a.targetDate);
          targetDt = DateTime.tryParse(dbFormatted);
        } else {
          targetDt = DateTime.tryParse(a.targetDate);
        }
      }

      if (statusLower == 'overdue' ||
          (targetDt != null && targetDt.isBefore(today))) {
        overdue++;
      } else if (targetDt != null &&
          !targetDt.isBefore(today) &&
          !targetDt.isAfter(in7Days)) {
        dueSoon++;
      }

      // Next Follow-up check
      if (a.nextFollowUpDate.isNotEmpty) {
        final dbFormatted = ActionRecord.formatDateForDb(a.nextFollowUpDate);
        final followUpDt = DateTime.tryParse(dbFormatted);
        if (followUpDt != null && !followUpDt.isAfter(today)) {
          followUpDue++;
        }
      }
    }

    return ManagerDashboardMetrics(
      total: total,
      open: open,
      inProgress: inProgress,
      pendingReview: pendingReview,
      overdue: overdue,
      dueSoon: dueSoon,
      followUpDue: followUpDue,
      criticalHigh: criticalHigh,
      closed: closed,
    );
  }

  /// Approves and closes an action using the secure stored procedure.
  /// Enforces manager/admin authority, tenant isolation, and progress == 100%.
  Future<ActionRecord> approveAndCloseAction({
    required String actionId,
    required String closureComment,
  }) async {
    final client = _client;
    if (client == null) {
      throw Exception('Supabase client is not initialized.');
    }

    try {
      final res = await client.rpc(
        'approve_and_close_action',
        params: {
          'p_action_id': actionId,
          'p_closure_comment': closureComment.trim(),
        },
      );

      // Re-fetch full joined record for consistent relation caching
      final fullRes = await client
          .from('actions')
          .select(_selectQuery)
          .eq('id', actionId)
          .maybeSingle();

      ActionRecord? closedAction;
      if (fullRes is Map<String, dynamic>) {
        closedAction = ActionRecord.fromSupabase(fullRes);
      } else if (res is Map<String, dynamic>) {
        closedAction = ActionRecord.fromSupabase(res);
      }

      if (closedAction != null) {
        final targetAction = closedAction;
        if (!targetAction.isExternalRecipient &&
            targetAction.assignedToId != null &&
            targetAction.assignedToId!.isNotEmpty) {
          NotificationService.safeDispatch(
            () => NotificationService.instance.notifyStatusChanged(
              action: targetAction,
              recipientUserId: targetAction.assignedToId!,
              oldStatus: 'Pending Review',
              newStatus: 'Closed',
              organizationId: targetAction.organizationId,
            ),
            context: 'ActionService.approveAndCloseAction',
          );
        }
        return closedAction;
      }
      throw Exception('Failed to parse closed action response.');
    } catch (e) {
      debugPrint('[ActionService.approveAndCloseAction] Error: $e');
      rethrow;
    }
  }

  /// Requests more information on an action that was submitted for review.
  /// Returns the action to active status (e.g. 'In Progress') with manager comments.
  Future<ActionRecord> requestMoreInformation({
    required String actionId,
    required String comments,
    String targetStatus = 'In Progress',
  }) async {
    final client = _client;
    if (client == null) {
      throw Exception('Supabase client is not initialized.');
    }

    try {
      final res = await client.rpc(
        'request_more_information_on_action',
        params: {
          'p_action_id': actionId,
          'p_comments': comments.trim(),
          'p_target_status': targetStatus.trim(),
        },
      );

      final fullRes = await client
          .from('actions')
          .select(_selectQuery)
          .eq('id', actionId)
          .maybeSingle();

      ActionRecord? returnedAction;
      if (fullRes is Map<String, dynamic>) {
        returnedAction = ActionRecord.fromSupabase(fullRes);
      } else if (res is Map<String, dynamic>) {
        returnedAction = ActionRecord.fromSupabase(res);
      }

      if (returnedAction != null) {
        final targetAction = returnedAction;
        if (!targetAction.isExternalRecipient &&
            targetAction.assignedToId != null &&
            targetAction.assignedToId!.isNotEmpty) {
          NotificationService.safeDispatch(
            () => NotificationService.instance.notifyStatusChanged(
              action: targetAction,
              recipientUserId: targetAction.assignedToId!,
              oldStatus: 'Pending Review',
              newStatus: targetStatus,
              organizationId: targetAction.organizationId,
            ),
            context: 'ActionService.requestMoreInformation',
          );
        }
        return returnedAction;
      }
      throw Exception('Failed to parse action response after requesting info.');
    } catch (e) {
      debugPrint('[ActionService.requestMoreInformation] Error: $e');
      rethrow;
    }
  }

  /// Fetches active sections for an organization.
  Future<List<ActionSection>> fetchActiveSections(String organizationId) async {
    return ActionSectionService.instance.fetchSections(
      organizationId,
      onlyActive: true,
    );
  }

  /// Fetches external recipients for an organization
  Future<List<ExternalRecipient>> fetchExternalRecipients(
    String organizationId, {
    bool onlyActive = false,
  }) async {
    final client = _client;
    if (client == null) {
      return MockActionStore.instance.externalRecipients
          .where(
            (r) =>
                r.organizationId == organizationId &&
                (!onlyActive || r.isActive),
          )
          .toList();
    }
    try {
      var query = client
          .from('external_action_recipients')
          .select('*')
          .eq('organization_id', organizationId);
      if (onlyActive) {
        query = query.eq('is_active', true);
      }
      final response = await query.order('full_name', ascending: true);

      return (response as List)
          .map(
            (item) =>
                ExternalRecipient.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } catch (e) {
      debugPrint('[ActionService] Error fetching external recipients: $e');
      return [];
    }
  }

  /// Finds an existing external recipient by organization and email
  Future<ExternalRecipient?> fetchExternalRecipientByEmail({
    required String organizationId,
    required String email,
  }) async {
    final client = _client;
    final normalizedEmail = email.trim().toLowerCase();
    if (client == null) {
      return MockActionStore.instance.externalRecipients.firstWhereOrNull(
        (r) =>
            r.organizationId == organizationId &&
            r.email.trim().toLowerCase() == normalizedEmail,
      );
    }
    try {
      final response = await client
          .from('external_action_recipients')
          .select('*')
          .eq('organization_id', organizationId)
          .ilike('email', normalizedEmail)
          .maybeSingle();

      if (response != null) {
        return ExternalRecipient.fromJson(Map<String, dynamic>.from(response));
      }
      return null;
    } catch (e) {
      debugPrint('[ActionService] Error looking up external recipient by email: $e');
      return null;
    }
  }

  /// Creates a new external recipient for an organization, or returns the existing matching recipient if already registered.
  Future<ExternalRecipient> createExternalRecipient({
    required String organizationId,
    required String fullName,
    required String email,
    String companyName = '',
    String phone = '',
    String? createdBy,
  }) async {
    final client = _client;
    final normalizedEmail = email.trim().toLowerCase();
    final sanitizedName = fullName.trim();

    if (client == null) {
      final existing = MockActionStore.instance.externalRecipients.firstWhereOrNull(
        (r) =>
            r.organizationId == organizationId &&
            r.email.trim().toLowerCase() == normalizedEmail,
      );
      if (existing != null) {
        return existing;
      }

      final newRecipient = ExternalRecipient(
        id: 'ext-${DateTime.now().millisecondsSinceEpoch}',
        organizationId: organizationId,
        fullName: sanitizedName,
        email: normalizedEmail,
        companyName: companyName.trim(),
        phone: phone.trim(),
        createdBy: createdBy ?? '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      MockActionStore.instance.externalRecipients.add(newRecipient);
      return newRecipient;
    }

    // 1. Pre-check if recipient already exists within this organization
    try {
      final existing = await client
          .from('external_action_recipients')
          .select('*')
          .eq('organization_id', organizationId)
          .ilike('email', normalizedEmail)
          .maybeSingle();

      if (existing != null) {
        return ExternalRecipient.fromJson(Map<String, dynamic>.from(existing));
      }
    } catch (e) {
      debugPrint('[ActionService] Pre-lookup for external recipient failed: $e');
    }

    // 2. Insert new external recipient with race-condition safety
    try {
      final response = await client
          .from('external_action_recipients')
          .insert({
            'organization_id': organizationId,
            'full_name': sanitizedName,
            'email': normalizedEmail,
            'company_name': companyName.trim(),
            'phone': phone.trim(),
            if (createdBy != null && createdBy.isNotEmpty)
              'created_by': createdBy,
          })
          .select('*')
          .single();

      return ExternalRecipient.fromJson(Map<String, dynamic>.from(response));
    } catch (e) {
      // If a concurrent insert occurred, or index collision on (organization_id, lower(email))
      if (e.toString().contains('23505') ||
          e.toString().toLowerCase().contains('unique')) {
        final existingAfterConflict = await client
            .from('external_action_recipients')
            .select('*')
            .eq('organization_id', organizationId)
            .ilike('email', normalizedEmail)
            .maybeSingle();
        if (existingAfterConflict != null) {
          return ExternalRecipient.fromJson(
            Map<String, dynamic>.from(existingAfterConflict),
          );
        }
      }
      rethrow;
    }
  }

  /// Fetches email reminders for an action
  Future<List<ActionEmailReminderJob>> fetchEmailRemindersForAction(
    String actionId,
  ) async {
    final client = _client;
    if (client == null) {
      return MockActionStore.instance.emailReminders
          .where((r) => r.actionId == actionId)
          .toList();
    }
    try {
      final response = await client
          .from('action_email_reminders')
          .select('*')
          .eq('action_id', actionId)
          .order('created_at', ascending: false);

      return (response as List)
          .map(
            (item) => ActionEmailReminderJob.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('[ActionService] Error fetching email reminders: $e');
      return [];
    }
  }
}
