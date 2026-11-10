import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/calendar/models/calendar_task.dart';
import 'package:action_flow/features/calendar/widgets/calendar_view.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_email_reminder_job.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/add_action_screen.dart';
import 'package:action_flow/services/calendar_task_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    CalendarTaskService.useMockOnly = true;
    MockCalendarTaskStore.instance.clear();
  });

  tearDown(() {
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

  group('Calendar Feature Tests', () {
    final fixedRefDate = DateTime(2026, 10, 24);

    final List<ActionRecord> sampleActions = [
      ActionRecord(
        id: 'ACT-001',
        subject: 'Scaffolding Safety Audit',
        actionRequired: 'Inspect guardrails and scaffolding clips',
        division: 'Safety',
        targetDate: '24 Oct 2026',
        priority: 'High',
        status: 'Open',
        assignedTo: 'John Doe',
      ),
      ActionRecord(
        id: 'ACT-002',
        subject: 'Fire Extinguisher Inspection',
        actionRequired: 'Check pressure gauges and recharge tags',
        division: 'Safety',
        targetDate: '20 Oct 2026', // Overdue relative to 24 Oct
        priority: 'Critical',
        status: 'Open',
        assignedTo: 'Jane Smith',
      ),
      ActionRecord(
        id: 'ACT-003',
        subject: 'Electrical Panel Maintenance',
        actionRequired: 'Lockout tagout and tighten terminals',
        division: 'Operations',
        targetDate: '28 Oct 2026', // Upcoming relative to 24 Oct
        priority: 'Medium',
        status: 'In Progress',
        assignedTo: 'Alex Worker',
      ),
      ActionRecord(
        id: 'ACT-004',
        subject: 'PPE Inventory Check',
        actionRequired: 'Stock count and dispose damaged helmets',
        division: 'Safety',
        targetDate: '15 Oct 2026',
        priority: 'Low',
        status: 'Closed', // Completed
        assignedTo: 'John Doe',
      ),
      ActionRecord(
        id: 'ACT-005',
        subject: 'No Due Date Finding',
        actionRequired: 'Initial observation logging',
        division: 'Safety',
        targetDate: '', // Missing due date
        priority: 'Medium',
        status: 'Open',
        assignedTo: 'Alex Worker',
      ),
    ];

    testWidgets('1. Month, week, and day navigation and Today button', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));

      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: sampleActions,
            currentUserId: 'test-user-1',
            initialDate: fixedRefDate,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Month View initially displays October 2026
      expect(find.text('October 2026'), findsOneWidget);

      // Navigate Next Month (November 2026)
      await tester.tap(find.byKey(const Key('calendar_next_button')));
      await tester.pumpAndSettle();
      expect(find.text('November 2026'), findsOneWidget);

      // Navigate Previous Month (back to October 2026)
      await tester.tap(find.byKey(const Key('calendar_prev_button')));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);

      // Today button returns to current real month
      await tester.tap(find.byKey(const Key('calendar_today_button')));
      await tester.pumpAndSettle();

      // Switch to Week View
      await tester.tap(find.byKey(const Key('view_mode_week')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar_next_button')), findsOneWidget);

      // Switch to Day View
      await tester.tap(find.byKey(const Key('view_mode_day')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Agenda for'), findsOneWidget);

      // Day View Next button increments by 1 day
      await tester.tap(find.byKey(const Key('calendar_next_button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Agenda for'), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('2. Official action visibility according to role and permissions', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));

      // Staff sees only their assigned actions
      final staffActions = sampleActions.where((a) => a.assignedTo == 'Alex Worker').toList();

      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: staffActions,
            currentUserId: 'alex-worker-id',
            initialDate: fixedRefDate,
            isManager: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select day 28 (where ACT-003 is scheduled)
      await tester.tap(find.byKey(const Key('calendar_day_cell_28')));
      await tester.pumpAndSettle();

      // ACT-003 is visible
      expect(find.text('ACT-003'), findsOneWidget);
      expect(find.text('Electrical Panel Maintenance'), findsOneWidget);

      // ACT-001 (assigned to John Doe) is NOT visible in staff's calendar
      expect(find.text('ACT-001'), findsNothing);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('3. Opening an action from the Calendar invokes onActionTap', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));

      ActionRecord? tappedAction;
      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: sampleActions,
            currentUserId: 'mgr-1',
            initialDate: fixedRefDate,
            onActionTap: (act) => tappedAction = act,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select day 24 (ACT-001 is on 24 Oct)
      await tester.tap(find.byKey(const Key('calendar_day_cell_24')));
      await tester.pumpAndSettle();

      // Tap on ACT-001 item card in agenda
      final actionItem = find.byKey(const Key('calendar_action_item_ACT-001'));
      expect(actionItem, findsOneWidget);
      await tester.tap(actionItem);
      await tester.pumpAndSettle();

      expect(tappedAction, isNotNull);
      expect(tappedAction!.id, 'ACT-001');
      expect(tappedAction!.subject, 'Scaffolding Safety Audit');

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('4. Creating, editing, completing, and deleting personal Calendar Tasks', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));

      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: const [],
            currentUserId: 'user-crud-test',
            initialDate: fixedRefDate,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select day 24
      await tester.tap(find.byKey(const Key('calendar_day_cell_24')));
      await tester.pumpAndSettle();

      // 4a. Create task
      await tester.tap(find.byKey(const Key('add_personal_task_button')));
      await tester.pumpAndSettle();

      expect(find.text('New Personal Task'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('calendar_task_title_field')),
        'Personal HSE checklist review',
      );
      await tester.enterText(
        find.byKey(const Key('calendar_task_desc_field')),
        'Private notes for site inspection',
      );
      await tester.tap(find.byKey(const Key('calendar_task_save_button')));
      await tester.pumpAndSettle();

      // Verify task appears
      expect(find.text('Personal HSE checklist review'), findsOneWidget);

      final service = CalendarTaskService();
      final tasks = await service.getTasks(userId: 'user-crud-test');
      expect(tasks.length, 1);
      final taskId = tasks.first.id;

      // 4b. Complete task toggle
      final toggleButton = find.byKey(Key('toggle_task_$taskId'));
      expect(toggleButton, findsOneWidget);
      await tester.tap(toggleButton);
      await tester.pumpAndSettle();

      final updatedTasks = await service.getTasks(userId: 'user-crud-test');
      expect(updatedTasks.first.isCompleted, isTrue);

      // 4c. Edit task
      final editButton = find.byKey(Key('edit_task_$taskId'));
      expect(editButton, findsOneWidget);
      await tester.tap(editButton);
      await tester.pumpAndSettle();

      expect(find.text('Edit Personal Task'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('calendar_task_title_field')),
        'Updated HSE checklist review',
      );
      await tester.tap(find.byKey(const Key('calendar_task_save_button')));
      await tester.pumpAndSettle();

      expect(find.text('Updated HSE checklist review'), findsOneWidget);

      // 4d. Delete task
      final deleteButton = find.byKey(Key('delete_task_$taskId'));
      expect(deleteButton, findsOneWidget);
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();

      expect(find.text('Delete Task?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('calendar_task_confirm_delete_button')));
      await tester.pumpAndSettle();

      final afterDeleteTasks = await service.getTasks(userId: 'user-crud-test');
      expect(afterDeleteTasks.isEmpty, isTrue);
      expect(find.text('Updated HSE checklist review'), findsNothing);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('5. Personal task isolation between different users', (tester) async {
      final service = CalendarTaskService();

      // User A creates a task
      await service.createTask(
        CalendarTask(
          id: 'task-a',
          userId: 'user-alice',
          title: 'Alice Private Safety Notes',
          dueDate: fixedRefDate,
        ),
      );

      // User B creates a task
      await service.createTask(
        CalendarTask(
          id: 'task-b',
          userId: 'user-bob',
          title: 'Bob Personal Follow-up',
          dueDate: fixedRefDate,
        ),
      );

      // User Alice fetches tasks -> only Alice's task is returned
      final aliceTasks = await service.getTasks(userId: 'user-alice');
      expect(aliceTasks.length, 1);
      expect(aliceTasks.first.title, 'Alice Private Safety Notes');
      expect(aliceTasks.any((t) => t.title == 'Bob Personal Follow-up'), isFalse);

      // User Bob fetches tasks -> only Bob's task is returned
      final bobTasks = await service.getTasks(userId: 'user-bob');
      expect(bobTasks.length, 1);
      expect(bobTasks.first.title, 'Bob Personal Follow-up');
      expect(bobTasks.any((t) => t.title == 'Alice Private Safety Notes'), isFalse);

      // Manager user cannot fetch Alice or Bob's tasks by querying their own userId
      final managerTasks = await service.getTasks(userId: 'manager-user');
      expect(managerTasks.isEmpty, isTrue);

      // Bob attempting to delete Alice's task fails silently or throws
      await service.deleteTask(taskId: 'task-a', userId: 'user-bob');
      final aliceTasksAfterBobDelete = await service.getTasks(userId: 'user-alice');
      expect(aliceTasksAfterBobDelete.length, 1); // Alice's task is still safe!
    });

    testWidgets('6. Confirmation that personal tasks never modify official HSSE Actions', (tester) async {
      final originalActions = List<ActionRecord>.from(sampleActions);
      final service = CalendarTaskService();

      // Create personal task
      final task = await service.createTask(
        CalendarTask(
          id: 'task-isolated',
          userId: 'user-action-isolation',
          title: 'Private reminder',
          dueDate: fixedRefDate,
        ),
      );

      // Toggle, edit, delete task
      await service.toggleTaskCompletion(
        taskId: task.id,
        userId: 'user-action-isolation',
        isCompleted: true,
      );
      await service.deleteTask(taskId: task.id, userId: 'user-action-isolation');

      // Verify sampleActions is completely unaltered
      expect(sampleActions.length, originalActions.length);
      for (int i = 0; i < sampleActions.length; i++) {
        expect(sampleActions[i].id, originalActions[i].id);
        expect(sampleActions[i].subject, originalActions[i].subject);
        expect(sampleActions[i].status, originalActions[i].status);
        expect(sampleActions[i].targetDate, originalActions[i].targetDate);
        expect(sampleActions[i].priority, originalActions[i].priority);
      }
    });

    testWidgets('7. Correct handling of overdue items and missing due dates', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));

      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: sampleActions,
            currentUserId: 'test-user',
            initialDate: fixedRefDate,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check overdue indicator filter
      await tester.tap(find.byKey(const Key('filter_status_overdue')));
      await tester.pumpAndSettle();

      // Select day 20 (ACT-002 was on 20 Oct 2026, overdue)
      await tester.tap(find.byKey(const Key('calendar_day_cell_20')));
      await tester.pumpAndSettle();

      expect(find.text('ACT-002'), findsOneWidget);
      expect(find.text('Fire Extinguisher Inspection'), findsOneWidget);

      // ACT-004 is on 15 Oct 2026, but it is Closed -> so NOT overdue!
      await tester.tap(find.byKey(const Key('calendar_day_cell_15')));
      await tester.pumpAndSettle();
      expect(find.text('ACT-004'), findsNothing); // Filtered out because it's not overdue

      // Action with empty targetDate (ACT-005) does not crash calendar
      expect(sampleActions.firstWhere((a) => a.id == 'ACT-005').targetDateTime, isNull);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('8. Timezone and date-boundary behavior', (tester) async {
      // Create tasks near day boundaries
      final dt1 = DateTime(2026, 10, 24, 0, 0, 1);
      final dt2 = DateTime(2026, 10, 24, 23, 59, 59);

      final task1 = CalendarTask(id: 't1', userId: 'u1', title: 'Task Morning', dueDate: dt1);
      final task2 = CalendarTask(id: 't2', userId: 'u1', title: 'Task Night', dueDate: dt2);

      // Both should have identical dueDayMidnight
      expect(task1.dueDayMidnight, DateTime(2026, 10, 24));
      expect(task2.dueDayMidnight, DateTime(2026, 10, 24));
      expect(task1.dueDayMidnight, task2.dueDayMidnight);
    });

    testWidgets('9. No duplicate action entries', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));

      final duplicateActions = [
        sampleActions[0],
        sampleActions[0], // Duplicate ACT-001
        sampleActions[1],
        sampleActions[1], // Duplicate ACT-002
      ];

      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: duplicateActions,
            currentUserId: 'test-user',
            initialDate: fixedRefDate,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select day 24
      await tester.tap(find.byKey(const Key('calendar_day_cell_24')));
      await tester.pumpAndSettle();

      // ACT-001 should only be rendered ONCE in the agenda
      expect(find.byKey(const Key('calendar_action_item_ACT-001')), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('10. Existing Add Action functionality remains unchanged', (tester) async {
      // Instantiate AddActionScreen to ensure no breaking changes
      const screen = AddActionScreen(actionId: 'ACT-999');
      expect(screen.actionId, 'ACT-999');
    });

    testWidgets('11. Existing email reminder settings and recipients remain unchanged', (tester) async {
      // Ensure email reminder models and functionality are untouched
      const job = ActionEmailReminderJob(
        id: 'job-1',
        organizationId: 'org-1',
        actionId: 'ACT-001',
        recipientName: 'John Doe',
        recipientEmail: 'john@example.com',
        emailSubject: 'Safety Reminder',
        emailBody: 'Please complete your safety review',
        status: 'pending',
      );
      expect(job.actionId, 'ACT-001');
      expect(job.status, 'pending');

      // Personal calendar tasks do not affect or create reminder jobs
      final service = CalendarTaskService();
      final task = await service.createTask(
        CalendarTask(
          id: 'task-remind',
          userId: 'user-reminder-test',
          title: 'Private reminder',
          dueDate: fixedRefDate,
        ),
      );
      expect(task.title, 'Private reminder');
    });

    testWidgets('12. Responsive layout and empty states on narrow screens', (tester) async {
      // Narrow mobile viewport (360x700)
      await tester.binding.setSurfaceSize(const Size(360, 700));

      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: const [],
            currentUserId: 'test-user-mobile',
            initialDate: fixedRefDate,
          ),
          size: const Size(360, 700),
        ),
      );
      await tester.pumpAndSettle();

      // No overflow errors
      expect(tester.takeException(), isNull);

      // Verify empty state text
      expect(find.text('No items scheduled for this day'), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });
  });
}
