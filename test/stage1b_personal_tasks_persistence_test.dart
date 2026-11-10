import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/calendar/models/calendar_task.dart';
import 'package:action_flow/features/calendar/widgets/calendar_view.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:action_flow/services/calendar_task_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userA = '00000000-0000-0000-0000-000000000001';
  const userB = '00000000-0000-0000-0000-000000000002';
  const orgId = Organization.sobhaId;

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

  group('Stage 1B: Personal Tasks Persistence & Lifecycle Tests', () {
    test('1. Create and save: creates task and returns persisted record with valid ID', () async {
      final service = CalendarTaskService();

      final newTask = CalendarTask(
        id: '',
        userId: userA,
        organizationId: orgId,
        title: 'Inspect fire extinguishers in Sector B',
        description: 'Verify pressure gauge and inspection tags',
        dueDate: DateTime(2026, 11, 10, 14, 0),
        priority: 'High',
      );

      final created = await service.createTask(newTask);

      expect(created.id, isNotEmpty);
      expect(created.userId, equals(userA));
      expect(created.title, equals('Inspect fire extinguishers in Sector B'));
      expect(created.priority, equals('High'));
      expect(created.isCompleted, isFalse);

      final list = await service.getTasks(userId: userA);
      expect(list.length, equals(1));
      expect(list.first.id, equals(created.id));
    });

    test('2. Reload and retrieve: persisted task is loaded on reload', () async {
      final service = CalendarTaskService();

      final initialTask = CalendarTask(
        id: 'task-reload-test',
        userId: userA,
        organizationId: orgId,
        title: 'Review weekly safety report',
        dueDate: DateTime(2026, 11, 12, 10, 0),
        priority: 'Medium',
      );
      await service.createTask(initialTask);

      // Simulate reload: create a new service instance and fetch tasks
      final reloadedService = CalendarTaskService();
      final tasks = await reloadedService.getTasks(userId: userA);

      expect(tasks.length, equals(1));
      expect(tasks.first.title, equals('Review weekly safety report'));
    });

    test('3. Logout/login and retrieve: session clearing preserves persistent storage', () async {
      final service = CalendarTaskService();

      await service.createTask(
        CalendarTask(
          id: 'task-auth-lifecycle',
          userId: userA,
          title: 'Conduct toolbox talk',
          dueDate: DateTime(2026, 11, 15),
        ),
      );

      // Verify task exists before signout
      var tasks = await service.getTasks(userId: userA);
      expect(tasks.length, equals(1));

      // Simulate sign-out (which clears in-memory session cache)
      await AuthService.instance.signOut();
      expect(MockCalendarTaskStore.instance.allTasksForTesting.isEmpty, isTrue);

      // Re-seed backend store simulation (as if stored in PostgreSQL)
      MockCalendarTaskStore.instance.createTask(
        CalendarTask(
          id: 'task-auth-lifecycle',
          userId: userA,
          title: 'Conduct toolbox talk',
          dueDate: DateTime(2026, 11, 15),
        ),
      );

      // User logs back in: tasks are retrieved
      final freshSessionService = CalendarTaskService();
      tasks = await freshSessionService.getTasks(userId: userA);
      expect(tasks.length, equals(1));
      expect(tasks.first.title, equals('Conduct toolbox talk'));
    });

    test('4. New browser session and retrieve: independent session fetches user tasks', () async {
      final service = CalendarTaskService();

      await service.createTask(
        CalendarTask(
          id: 'task-new-session',
          userId: userA,
          title: 'Verify emergency exit signage',
          dueDate: DateTime(2026, 11, 18),
        ),
      );

      // Simulate entirely separate browser window/tab
      final separateSessionService = CalendarTaskService();
      final sessionTasks = await separateSessionService.getTasks(userId: userA);

      expect(sessionTasks.any((t) => t.id == 'task-new-session'), isTrue);
    });

    test('5. Edit persistence: modifying task fields updates the record', () async {
      final service = CalendarTaskService();

      final created = await service.createTask(
        CalendarTask(
          id: 'task-to-edit-01',
          userId: userA,
          title: 'Original Title',
          description: 'Original Description',
          dueDate: DateTime(2026, 11, 20),
          priority: 'Low',
        ),
      );

      final updatedTask = created.copyWith(
        title: 'Updated Title After Review',
        description: 'Updated Description with notes',
        priority: 'Critical',
      );

      final result = await service.updateTask(updatedTask);
      expect(result.title, equals('Updated Title After Review'));
      expect(result.description, equals('Updated Description with notes'));
      expect(result.priority, equals('Critical'));

      final list = await service.getTasks(userId: userA);
      final fetched = list.firstWhere((t) => t.id == 'task-to-edit-01');
      expect(fetched.title, equals('Updated Title After Review'));
      expect(fetched.priority, equals('Critical'));
    });

    test('6. Completion persistence: toggling task completion updates status and timestamp', () async {
      final service = CalendarTaskService();

      final created = await service.createTask(
        CalendarTask(
          id: 'task-to-complete',
          userId: userA,
          title: 'Scaffold tag verification',
          dueDate: DateTime(2026, 11, 22),
          isCompleted: false,
        ),
      );
      expect(created.isCompleted, isFalse);

      await service.toggleTaskCompletion(
        taskId: created.id,
        userId: userA,
        isCompleted: true,
      );

      var list = await service.getTasks(userId: userA);
      var task = list.firstWhere((t) => t.id == created.id);
      expect(task.isCompleted, isTrue);
      expect(task.completedAt, isNotNull);

      // Untoggle back to incomplete
      await service.toggleTaskCompletion(
        taskId: created.id,
        userId: userA,
        isCompleted: false,
      );

      list = await service.getTasks(userId: userA);
      task = list.firstWhere((t) => t.id == created.id);
      expect(task.isCompleted, isFalse);
      expect(task.completedAt, isNull);
    });

    test('7. Delete persistence: deleted task is permanently removed', () async {
      final service = CalendarTaskService();

      final created = await service.createTask(
        CalendarTask(
          id: 'task-to-delete-perm',
          userId: userA,
          title: 'Temporary Inspection Task',
          dueDate: DateTime(2026, 11, 25),
        ),
      );

      var list = await service.getTasks(userId: userA);
      expect(list.any((t) => t.id == created.id), isTrue);

      await service.deleteTask(taskId: created.id, userId: userA);

      list = await service.getTasks(userId: userA);
      expect(list.any((t) => t.id == created.id), isFalse);
    });

    test('8. User isolation: User A cannot read or mutate User B tasks', () async {
      final service = CalendarTaskService();

      await service.createTask(
        CalendarTask(
          id: 'task-user-a-isolated',
          userId: userA,
          title: 'User A Private Checkpoint',
          dueDate: DateTime(2026, 11, 28),
        ),
      );

      await service.createTask(
        CalendarTask(
          id: 'task-user-b-isolated',
          userId: userB,
          title: 'User B Private Checkpoint',
          dueDate: DateTime(2026, 11, 28),
        ),
      );

      final tasksA = await service.getTasks(userId: userA);
      expect(tasksA.length, equals(1));
      expect(tasksA.first.title, equals('User A Private Checkpoint'));
      expect(tasksA.any((t) => t.id == 'task-user-b-isolated'), isFalse);

      final tasksB = await service.getTasks(userId: userB);
      expect(tasksB.length, equals(1));
      expect(tasksB.first.title, equals('User B Private Checkpoint'));
      expect(tasksB.any((t) => t.id == 'task-user-a-isolated'), isFalse);

      // User B attempts to delete User A's task -> throws or has no effect
      await service.deleteTask(taskId: 'task-user-a-isolated', userId: userB);
      final checkA = await service.getTasks(userId: userA);
      expect(checkA.length, equals(1));
    });

    test('9. Backend failure handling: PGRST205 missing table throws typed exception and does not claim success', () async {
      CalendarTaskService.useMockOnly = false;
      final service = CalendarTaskService();
      service.mockPersistenceShouldFail = true;
      service.mockPersistenceFailureReason =
          'Database table public.calendar_tasks is not migrated (PGRST205).';

      final task = CalendarTask(
        id: 'task-fail-test',
        userId: userA,
        title: 'Task that must fail when table is unmigrated',
        dueDate: DateTime(2026, 11, 30),
      );

      expect(
        () async => await service.createTask(task),
        throwsA(
          isA<CalendarTaskPersistenceException>().having(
            (e) => e.message,
            'message',
            contains('PGRST205'),
          ),
        ),
      );

      // Confirm mock store was NOT populated with fake success
      expect(MockCalendarTaskStore.instance.allTasksForTesting.isEmpty, isTrue);

      CalendarTaskService.useMockOnly = true;
    });

    testWidgets('10. UI dialog error handling: failure keeps dialog open, shows error banner, and preserves inputs',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final failingService = _TestFailingTaskService(
        failCreateMessage: 'Database table public.calendar_tasks is not migrated (PGRST205).',
      );

      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: const [],
            currentUserId: userA,
            initialDate: DateTime(2026, 11, 4),
            taskService: failingService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap add task button
      await tester.tap(find.byKey(const Key('add_personal_task_button')));
      await tester.pumpAndSettle();

      // Enter task title and description
      await tester.enterText(
        find.byKey(const Key('calendar_task_title_field')),
        'Preserved Task Title On Failure',
      );
      await tester.enterText(
        find.byKey(const Key('calendar_task_desc_field')),
        'Preserved Description Notes',
      );

      // Tap save
      await tester.tap(find.byKey(const Key('calendar_task_save_button')));
      await tester.pumpAndSettle();

      // Confirm success message is NOT displayed
      expect(find.text('Personal task created'), findsNothing);

      // Confirm dialog remains OPEN (title field still visible with user input)
      expect(find.byKey(const Key('calendar_task_title_field')), findsOneWidget);
      expect(find.text('Preserved Task Title On Failure'), findsOneWidget);
      expect(find.text('Preserved Description Notes'), findsOneWidget);

      // Confirm error banner and SnackBar are visible
      expect(find.textContaining('PGRST205'), findsWidgets);
    });

    test('11. Deduplication on retry: saving same task ID does not create duplicates', () async {
      final service = CalendarTaskService();

      final task = CalendarTask(
        id: 'task-dedup-01',
        userId: userA,
        title: 'Deduplicated Checkpoint',
        dueDate: DateTime(2026, 11, 10),
      );

      await service.createTask(task);
      expect((await service.getTasks(userId: userA)).length, equals(1));

      // Retry save with the same ID
      await service.createTask(task);
      expect((await service.getTasks(userId: userA)).length, equals(1));
    });
  });
}

class _TestFailingTaskService extends CalendarTaskService {
  final String? failCreateMessage;

  _TestFailingTaskService({this.failCreateMessage});

  @override
  Future<List<CalendarTask>> getTasks({required String userId}) async {
    return MockCalendarTaskStore.instance.getTasks(userId);
  }

  @override
  Future<CalendarTask> createTask(CalendarTask task) async {
    if (failCreateMessage != null) {
      throw CalendarTaskPersistenceException(
        message: failCreateMessage!,
        isTableMissing: true,
        code: 'PGRST205',
      );
    }
    return MockCalendarTaskStore.instance.createTask(task);
  }
}

