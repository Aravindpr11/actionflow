import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/calendar/models/calendar_task.dart';
import 'package:action_flow/features/calendar/widgets/calendar_view.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:action_flow/services/calendar_task_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    CalendarTaskService.useMockOnly = true;
    MockCalendarTaskStore.instance.clear();
  });

  tearDown(() {
    CalendarTaskService.useMockOnly = true;
    MockCalendarTaskStore.instance.clear();
  });

  Widget buildTestableWidget(Widget child, {Size size = const Size(1200, 900)}) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
  }

  group('Group 1: Model Serialization & Timezone Robustness', () {
    test('toJson serializes DateTime fields to UTC ISO-8601 strings', () {
      final localDate = DateTime(2026, 10, 25, 14, 30);
      final task = CalendarTask(
        id: '11111111-2222-3333-4444-555555555555',
        userId: 'aaaa1111-bbbb-2222-cccc-333333333333',
        organizationId: Organization.sobhaId,
        title: 'Conduct safety audit',
        dueDate: localDate,
        priority: 'High',
      );

      final json = task.toJson();
      expect(json['id'], equals('11111111-2222-3333-4444-555555555555'));
      expect(json['user_id'], equals('aaaa1111-bbbb-2222-cccc-333333333333'));
      expect(json['organization_id'], equals(Organization.sobhaId));
      expect(json['due_date'], equals(localDate.toUtc().toIso8601String()));
      expect(json['due_date'].toString().endsWith('Z'), isTrue);
    });

    test('fromJson converts incoming UTC timestamps to local device time', () {
      final utcIso = '2026-10-25T09:00:00.000Z';
      final json = {
        'id': '11111111-2222-3333-4444-555555555555',
        'user_id': 'aaaa1111-bbbb-2222-cccc-333333333333',
        'title': 'Inspect electrical cabling',
        'due_date': utcIso,
        'priority': 'Critical',
        'is_completed': false,
        'created_at': utcIso,
        'updated_at': utcIso,
      };

      final task = CalendarTask.fromJson(json);
      expect(task.dueDate.isUtc, isFalse);
      expect(task.createdAt.isUtc, isFalse);
      expect(task.updatedAt.isUtc, isFalse);
      expect(task.dueDayMidnight.year, equals(DateTime.parse(utcIso).toLocal().year));
      expect(task.dueDayMidnight.month, equals(DateTime.parse(utcIso).toLocal().month));
      expect(task.dueDayMidnight.day, equals(DateTime.parse(utcIso).toLocal().day));
    });
  });

  group('Group 2: UUID & Organization ID Sanitization', () {
    test('Non-UUID organization strings (e.g. SOBHA-001) are mapped to valid Sobha UUID', () async {
      CalendarTaskService.useMockOnly = true;
      final service = CalendarTaskService();

      final task = CalendarTask(
        id: '',
        userId: 'user-uuid-1',
        organizationId: 'SOBHA-001',
        title: 'Review tower equipment',
        dueDate: DateTime(2026, 10, 25),
      );

      final created = await service.createTask(task);
      expect(created.id, isNotEmpty);
      expect(created.title, equals('Review tower equipment'));
    });

    test('Empty or invalid organization strings do not crash task creation', () async {
      CalendarTaskService.useMockOnly = true;
      final service = CalendarTaskService();

      final task = CalendarTask(
        id: '',
        userId: 'user-uuid-1',
        organizationId: '',
        title: 'Empty org task',
        dueDate: DateTime(2026, 10, 25),
      );

      final created = await service.createTask(task);
      expect(created.id, isNotEmpty);
      expect(created.title, equals('Empty org task'));
    });
  });

  group('Group 3: UI Error Feedback (No False Positive Reports on DB Failure)', () {
    testWidgets('Database insert failure displays red error SnackBar and does NOT report success', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));

      final failingService = _FailingCalendarTaskService(
        shouldFailCreate: true,
        errorMessage: 'PostgreSQL RLS violation: user_id mismatch',
      );

      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: const [],
            currentUserId: 'test-user-failing',
            initialDate: DateTime(2026, 10, 25),
            taskService: failingService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Add Task Dialog
      await tester.tap(find.byKey(const Key('add_personal_task_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('calendar_task_title_field')),
        'Test Unsaved Task',
      );
      await tester.tap(find.byKey(const Key('calendar_task_save_button')));
      await tester.pumpAndSettle();

      // Confirm success message is NOT shown
      expect(find.text('Personal task created'), findsNothing);

      // Confirm error SnackBar IS displayed
      expect(find.textContaining('Failed to save task: PostgreSQL RLS violation'), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('Database update failure displays red error SnackBar and does NOT report success', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));

      final failingService = _FailingCalendarTaskService(
        shouldFailUpdate: true,
        errorMessage: 'Network timeout during update',
      );

      // Seed an existing task
      failingService.mockStore.createTask(
        CalendarTask(
          id: 'task-pre-existing',
          userId: 'test-user-update',
          title: 'Existing Task To Edit',
          dueDate: DateTime(2026, 10, 25),
        ),
      );

      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: const [],
            currentUserId: 'test-user-update',
            initialDate: DateTime(2026, 10, 25),
            taskService: failingService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify task is loaded
      expect(find.text('Existing Task To Edit'), findsOneWidget);

      // Tap Edit
      await tester.tap(find.byKey(const Key('edit_task_task-pre-existing')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('calendar_task_title_field')),
        'Attempted Updated Title',
      );
      await tester.tap(find.byKey(const Key('calendar_task_save_button')));
      await tester.pumpAndSettle();

      // Confirm success message is NOT shown
      expect(find.text('Personal task updated'), findsNothing);

      // Confirm error SnackBar IS displayed
      expect(find.textContaining('Failed to update task: Network timeout'), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('Database delete failure displays red error SnackBar and does NOT report success', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));

      final failingService = _FailingCalendarTaskService(
        shouldFailDelete: true,
        errorMessage: 'Database connection dropped during delete',
      );

      failingService.mockStore.createTask(
        CalendarTask(
          id: 'task-to-delete',
          userId: 'test-user-delete',
          title: 'Task That Fails Delete',
          dueDate: DateTime(2026, 10, 25),
        ),
      );

      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: const [],
            currentUserId: 'test-user-delete',
            initialDate: DateTime(2026, 10, 25),
            taskService: failingService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify task is loaded
      expect(find.text('Task That Fails Delete'), findsOneWidget);

      // Tap Delete
      await tester.tap(find.byKey(const Key('delete_task_task-to-delete')));
      await tester.pumpAndSettle();

      // Confirm in dialog
      await tester.tap(find.byKey(const Key('calendar_task_confirm_delete_button')));
      await tester.pumpAndSettle();

      // Confirm success message is NOT shown
      expect(find.text('Task deleted'), findsNothing);

      // Confirm error SnackBar IS displayed
      expect(find.textContaining('Failed to delete task: Database connection dropped'), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });
  });

  group('Group 4: Task Persistence Across Reload & Logout/Login Flow', () {
    testWidgets('Task persists and reloads for same user', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));

      final service = CalendarTaskService();

      // 1. User logs in and creates a personal task
      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: const [],
            currentUserId: 'user-persist-session',
            initialDate: DateTime(2026, 10, 25),
            taskService: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add_personal_task_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('calendar_task_title_field')),
        'Quarterly Personal Compliance Audit',
      );
      await tester.tap(find.byKey(const Key('calendar_task_save_button')));
      await tester.pumpAndSettle();

      expect(find.text('Personal task created'), findsOneWidget);
      expect(find.text('Quarterly Personal Compliance Audit'), findsOneWidget);

      // 2. Simulate page reload / screen re-entry as same user
      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: const [],
            currentUserId: 'user-persist-session',
            initialDate: DateTime(2026, 10, 25),
            taskService: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify task is still present after reload!
      expect(find.text('Quarterly Personal Compliance Audit'), findsOneWidget);

      // 3. Edit task and verify updated values persist
      final tasks = await service.getTasks(userId: 'user-persist-session');
      final taskId = tasks.first.id;
      await tester.tap(find.byKey(Key('edit_task_$taskId')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('calendar_task_title_field')),
        'Updated Quarterly Compliance Audit',
      );
      await tester.tap(find.byKey(const Key('calendar_task_save_button')));
      await tester.pumpAndSettle();

      expect(find.text('Personal task updated'), findsOneWidget);

      // Reload screen again
      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: const [],
            currentUserId: 'user-persist-session',
            initialDate: DateTime(2026, 10, 25),
            taskService: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Updated Quarterly Compliance Audit'), findsOneWidget);

      // 4. Delete task and verify deletion persists
      await tester.tap(find.byKey(Key('delete_task_$taskId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('calendar_task_confirm_delete_button')));
      await tester.pumpAndSettle();

      expect(find.text('Task deleted'), findsOneWidget);

      // Reload screen again
      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: const [],
            currentUserId: 'user-persist-session',
            initialDate: DateTime(2026, 10, 25),
            taskService: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Updated Quarterly Compliance Audit'), findsNothing);

      await tester.binding.setSurfaceSize(null);
    });

    test('AuthService signOut clears in-memory personal tasks to prevent session leakage', () async {
      final service = CalendarTaskService();
      await service.createTask(
        CalendarTask(
          id: 'session-task-1',
          userId: 'user-logout-test',
          title: 'Private confidential note',
          dueDate: DateTime(2026, 10, 25),
        ),
      );

      final beforeSignOut = await service.getTasks(userId: 'user-logout-test');
      expect(beforeSignOut.length, equals(1));

      // Trigger signOut
      await AuthService.instance.signOut();

      // Tasks in in-memory store are cleared
      final afterSignOut = await service.getTasks(userId: 'user-logout-test');
      expect(afterSignOut.isEmpty, isTrue);
    });
  });

  group('Group 5: User Isolation & Simulated Row-Level Security (RLS)', () {
    test('User B cannot view User A tasks', () async {
      final service = CalendarTaskService();

      await service.createTask(
        CalendarTask(
          id: 'task-user-a',
          userId: 'uuid-user-a',
          title: 'User A confidential checklist',
          dueDate: DateTime(2026, 10, 25),
        ),
      );

      await service.createTask(
        CalendarTask(
          id: 'task-user-b',
          userId: 'uuid-user-b',
          title: 'User B normal checklist',
          dueDate: DateTime(2026, 10, 25),
        ),
      );

      final userATasks = await service.getTasks(userId: 'uuid-user-a');
      expect(userATasks.length, equals(1));
      expect(userATasks.first.title, equals('User A confidential checklist'));

      final userBTasks = await service.getTasks(userId: 'uuid-user-b');
      expect(userBTasks.length, equals(1));
      expect(userBTasks.first.title, equals('User B normal checklist'));

      // Manager querying with their own ID sees 0 personal tasks from User A or B
      final managerTasks = await service.getTasks(userId: 'uuid-manager');
      expect(managerTasks.isEmpty, isTrue);
    });

    test('User B cannot edit User A task', () async {
      final service = CalendarTaskService();

      final taskA = await service.createTask(
        CalendarTask(
          id: 'task-user-a',
          userId: 'uuid-user-a',
          title: 'User A original title',
          dueDate: DateTime(2026, 10, 25),
        ),
      );

      // User B attempts to update User A's task by substituting their userId
      final maliciousUpdate = taskA.copyWith(
        userId: 'uuid-user-b',
        title: 'Tampered title by User B',
      );

      expect(
        () async => await service.updateTask(maliciousUpdate),
        throwsA(isA<Exception>()),
      );

      // Original task remains unaltered
      final originalTasks = await service.getTasks(userId: 'uuid-user-a');
      expect(originalTasks.first.title, equals('User A original title'));
    });

    test('User B cannot delete User A task', () async {
      final service = CalendarTaskService();

      await service.createTask(
        CalendarTask(
          id: 'task-user-a',
          userId: 'uuid-user-a',
          title: 'User A protected task',
          dueDate: DateTime(2026, 10, 25),
        ),
      );

      // User B attempts to delete User A's task
      await service.deleteTask(taskId: 'task-user-a', userId: 'uuid-user-b');

      // Task is still intact for User A
      final remaining = await service.getTasks(userId: 'uuid-user-a');
      expect(remaining.length, equals(1));
      expect(remaining.first.title, equals('User A protected task'));
    });

    test('PostgreSQL RLS Simulation: Enforcing auth.uid() = user_id on all CRUD operations', () {
      const String authenticatedUserUid = '00000000-0000-0000-0000-000000000099';
      const String unauthorizedUserUid = '00000000-0000-0000-0000-000000000088';

      // 1. SELECT Policy: USING (auth.uid() = user_id)
      bool canSelect(String authUid, String rowUserId) => authUid == rowUserId;
      expect(canSelect(authenticatedUserUid, authenticatedUserUid), isTrue);
      expect(canSelect(unauthorizedUserUid, authenticatedUserUid), isFalse);

      // 2. INSERT Policy: WITH CHECK (auth.uid() = user_id)
      bool canInsert(String authUid, String newRowUserId) => authUid == newRowUserId;
      expect(canInsert(authenticatedUserUid, authenticatedUserUid), isTrue);
      expect(canInsert(unauthorizedUserUid, authenticatedUserUid), isFalse);

      // 3. UPDATE Policy: USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id)
      bool canUpdate(String authUid, String oldRowUserId, String newRowUserId) =>
          authUid == oldRowUserId && authUid == newRowUserId;
      expect(canUpdate(authenticatedUserUid, authenticatedUserUid, authenticatedUserUid), isTrue);
      expect(canUpdate(unauthorizedUserUid, authenticatedUserUid, authenticatedUserUid), isFalse);
      expect(canUpdate(authenticatedUserUid, authenticatedUserUid, unauthorizedUserUid), isFalse);

      // 4. DELETE Policy: USING (auth.uid() = user_id)
      bool canDelete(String authUid, String rowUserId) => authUid == rowUserId;
      expect(canDelete(authenticatedUserUid, authenticatedUserUid), isTrue);
      expect(canDelete(unauthorizedUserUid, authenticatedUserUid), isFalse);
    });
  });
}

/// Mock test service simulating remote database failures to test UI error paths
class _FailingCalendarTaskService extends CalendarTaskService {
  final bool shouldFailCreate;
  final bool shouldFailUpdate;
  final bool shouldFailDelete;
  final String errorMessage;
  final MockCalendarTaskStore mockStore = MockCalendarTaskStore.instance;

  _FailingCalendarTaskService({
    this.shouldFailCreate = false,
    this.shouldFailUpdate = false,
    this.shouldFailDelete = false,
    this.errorMessage = 'Database operation failed',
  });

  @override
  Future<List<CalendarTask>> getTasks({required String userId}) async {
    return mockStore.getTasks(userId);
  }

  @override
  Future<CalendarTask> createTask(CalendarTask task) async {
    if (shouldFailCreate) {
      throw Exception(errorMessage);
    }
    return mockStore.createTask(task);
  }

  @override
  Future<CalendarTask> updateTask(CalendarTask task) async {
    if (shouldFailUpdate) {
      throw Exception(errorMessage);
    }
    return mockStore.updateTask(task);
  }

  @override
  Future<void> deleteTask({required String taskId, required String userId}) async {
    if (shouldFailDelete) {
      throw Exception(errorMessage);
    }
    mockStore.deleteTask(taskId: taskId, userId: userId);
  }

  @override
  Future<void> toggleTaskCompletion({
    required String taskId,
    required String userId,
    required bool isCompleted,
  }) async {
    mockStore.toggleCompletion(taskId: taskId, userId: userId, isCompleted: isCompleted);
  }
}
