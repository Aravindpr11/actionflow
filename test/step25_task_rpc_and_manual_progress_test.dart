import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_action_update_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_action_update_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testOrgId = 'SOBHA-001';

  const managerProfile = UserProfile(
    id: 'mgr-step25-01',
    name: 'Manager User',
    email: 'manager@sobha.com',
    phone: '+971501234567',
    designation: 'Safety Manager',
    department: 'Safety',
    site: 'Central Hub',
    role: 'manager',
    organizationId: testOrgId,
    organizationName: 'Sobha Constructions',
  );

  final staffUser = ActionPersonReference(
    personId: 'staff-step25-01',
    name: 'Staff Alice',
    type: PersonType.internalUser,
    email: 'alice@sobha.com',
  );

  final managerPerson = ActionPersonReference(
    personId: managerProfile.id,
    name: managerProfile.name,
    type: PersonType.internalUser,
    email: managerProfile.email,
  );

  final managerContext = ManagerContext(
    authUserId: managerProfile.id,
    profile: managerProfile,
    organizationId: testOrgId,
    organizationName: 'Sobha Constructions',
    scopes: const [
      ManagerScopeItem(
        departmentId: 'dept-safety-01',
        departmentName: 'Safety',
        siteId: 'site-hub-01',
        siteName: 'Central Hub',
      ),
    ],
  );

  ActionSubTask createSubTask({
    required String id,
    required String parentActionId,
    required String title,
    String assignedStaff = 'Staff Alice',
    String assignedStaffId = 'staff-step25-01',
    String assignedStaffEmail = 'alice@sobha.com',
    String assigneeType = 'internal',
    String status = 'Open',
    String reopenReason = '',
    String completedAt = '',
    String completedBy = '',
  }) {
    return ActionSubTask(
      id: id,
      parentActionId: parentActionId,
      title: title,
      instruction: 'Follow SOP',
      assignedStaff: assignedStaff,
      assignedStaffId: assignedStaffId,
      assignedStaffEmail: assignedStaffEmail,
      assigneeType: assigneeType,
      status: status,
      reopenReason: reopenReason,
      completedAt: completedAt,
      completedBy: completedBy,
    );
  }

  ActionRecord createAction({
    required String id,
    required String subject,
    required ActionPersonReference primary,
    int percentComplete = 60,
    String status = 'In Progress',
    List<ActionSubTask> subTasks = const [],
    List<String> history = const [],
  }) {
    return ActionRecord(
      id: id,
      organizationId: testOrgId,
      actionNumber: id,
      subject: subject,
      description: 'Test description',
      actionRequired: 'Verify safety compliance',
      division: 'Safety',
      department: 'Safety',
      site: 'Central Hub',
      priority: 'High',
      status: status,
      percentComplete: percentComplete,
      dateRaised: '20 Oct 2026',
      targetDate: '25 Oct 2026',
      assignedTo: primary.name,
      assignedToId: primary.personId,
      primaryAssignee: primary,
      subTasks: subTasks,
      history: history.isNotEmpty ? history : ['20 Oct 2026: Created'],
    );
  }

  setUp(() {
    MockActionStore.instance.actions.clear();
    MockActionStore.instance.profiles.clear();
    MockActionStore.instance.externalRecipients.clear();
    MockActionStore.instance.emailReminders.clear();
  });

  group('Step 25: Task RPC, Manual Progress Rules, and Reopen Workflow', () {
    test('1. ActionService.submitSubtaskToggle uses exact matching parameters and returns structured result', () async {
      final task1 = createSubTask(
        id: 'task-rpc-01',
        parentActionId: 'ACT-RPC-01',
        title: 'Calibrate gas detector',
      );
      final action = createAction(
        id: 'ACT-RPC-01',
        subject: 'Gas Detection Audit',
        primary: staffUser,
        percentComplete: 60,
        subTasks: [task1],
      );
      MockActionStore.instance.add(action);

      // Call submitSubtaskToggle with exact parameter names
      final res = await ActionService.instance.submitSubtaskToggle(
        actionId: 'ACT-RPC-01',
        taskId: 'task-rpc-01',
        isCompleted: true,
        reopenReason: '',
      );

      expect(res['success'], isTrue);
      expect(res['completed_tasks'], equals(1));
      expect(res['total_tasks'], equals(1));
      // Overall action progress must remain 60%
      expect(res['percent_complete'], equals(60));

      final updated = MockActionStore.instance.actions.firstWhere((a) => a.id == 'ACT-RPC-01');
      expect(updated.subTasks.first.isCompleted, isTrue);
      expect(updated.percentComplete, equals(60));
    });

    test('2. ActionService.submitSubtaskToggle returns meaningful error on non-existent action/task without silent failure', () async {
      final res = await ActionService.instance.submitSubtaskToggle(
        actionId: 'NON-EXISTENT-ACT',
        taskId: 'NON-EXISTENT-TASK',
        isCompleted: true,
      );

      expect(res['success'], isFalse);
      expect(res['error'], isNotNull);
      expect(res['error'].toString(), contains('not found'));
    });

    test('3. Progress Model: Completing a task does NOT overwrite manual progress (60% remains 60%)', () async {
      final t1 = createSubTask(id: 't-1', parentActionId: 'ACT-PROG-01', title: 'Task 1');
      final t2 = createSubTask(id: 't-2', parentActionId: 'ACT-PROG-01', title: 'Task 2');
      final t3 = createSubTask(id: 't-3', parentActionId: 'ACT-PROG-01', title: 'Task 3');
      final t4 = createSubTask(id: 't-4', parentActionId: 'ACT-PROG-01', title: 'Task 4');

      final action = createAction(
        id: 'ACT-PROG-01',
        subject: 'Multi-Task Progress Integrity',
        primary: staffUser,
        percentComplete: 60, // Manually reported progress
        subTasks: [t1, t2, t3, t4],
      );
      MockActionStore.instance.add(action);

      // Complete 1 of 4 tasks
      final res = await ActionService.instance.submitSubtaskToggle(
        actionId: 'ACT-PROG-01',
        taskId: 't-1',
        isCompleted: true,
      );

      expect(res['success'], isTrue);
      expect(res['completed_tasks'], equals(1));
      expect(res['total_tasks'], equals(4));
      // NOT 25%! Must preserve 60%
      expect(res['percent_complete'], equals(60));

      final stored = MockActionStore.instance.actions.firstWhere((a) => a.id == 'ACT-PROG-01');
      expect(stored.percentComplete, equals(60));
      expect(stored.subTasks.firstWhere((t) => t.id == 't-1').isCompleted, isTrue);
      expect(stored.subTasks.firstWhere((t) => t.id == 't-2').isCompleted, isFalse);
    });

    test('4. Task Reopening: Manager reopening a task sets task to Open with reason and preserves overall action progress & status', () async {
      final t1 = createSubTask(
        id: 't-reopen-1',
        parentActionId: 'ACT-REOPEN-TASK-01',
        title: 'Check fire extinguishers',
        status: 'Completed',
        completedAt: '20 Oct 2026',
        completedBy: 'Staff Alice',
      );
      final action = createAction(
        id: 'ACT-REOPEN-TASK-01',
        subject: 'Fire Safety Inspection',
        primary: staffUser,
        percentComplete: 75,
        status: 'Pending Review',
        subTasks: [t1],
      );
      MockActionStore.instance.add(action);

      // Manager unchecks/reopens task with correction reason
      final res = await ActionService.instance.submitSubtaskToggle(
        actionId: 'ACT-REOPEN-TASK-01',
        taskId: 't-reopen-1',
        isCompleted: false,
        reopenReason: 'Gauge needle in red zone on unit 4',
      );

      expect(res['success'], isTrue);
      expect(res['completed_tasks'], equals(0));
      // Action progress remains 75%
      expect(res['percent_complete'], equals(75));

      final stored = MockActionStore.instance.actions.firstWhere((a) => a.id == 'ACT-REOPEN-TASK-01');
      expect(stored.percentComplete, equals(75));
      // Action status remains Pending Review (does NOT automatically change to In Progress)
      expect(stored.status, equals('Pending Review'));

      final task = stored.subTasks.first;
      expect(task.isCompleted, isFalse);
      expect(task.status, equals('Open'));
      expect(task.reopenReason, equals('Gauge needle in red zone on unit 4'));
    });

    testWidgets('5. ManagerActionUpdateScreen displays independent checklist count and retains interactive manual progress slider', (tester) async {
      tester.view.physicalSize = const Size(1280, 2500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final t1 = createSubTask(id: 'm-t1', parentActionId: 'ACT-MGR-SCR-01', title: 'Task 1', status: 'Completed');
      final t2 = createSubTask(id: 'm-t2', parentActionId: 'ACT-MGR-SCR-01', title: 'Task 2', status: 'Open');
      final action = createAction(
        id: 'ACT-MGR-SCR-01',
        subject: 'Manager Update Screen Checklist',
        primary: managerPerson,
        percentComplete: 60,
        subTasks: [t1, t2],
      );
      MockActionStore.instance.add(action);

      await tester.pumpWidget(
        MaterialApp(
          home: ManagerActionUpdateScreen(
            action: action,
            currentUserId: managerProfile.id,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Independent checklist title
      expect(find.text('Assigned Tasks & Checklist (1 / 2 Completed)'), findsOneWidget);

      // Section title shows supporting checklist subtitle
      expect(
        find.text('Tasks are a supporting checklist (1 of 2 completed). Report overall action progress below.'),
        findsOneWidget,
      );

      // Manual slider is present and set to 60%
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('Progress: 60% *'), findsOneWidget);

      // Toggle Task 2 to completed
      final cb2 = find.byKey(const Key('manager_task_checkbox_1'));
      await tester.tap(cb2);
      await tester.pumpAndSettle();

      // Checklist count updates to 2 / 2 completed
      expect(find.text('Assigned Tasks & Checklist (2 / 2 Completed)'), findsOneWidget);
      // Manual reported progress remains 60%
      expect(find.text('Progress: 60% *'), findsOneWidget);
    });

    testWidgets('6. WorkerActionUpdateScreen displays independent checklist count and retains interactive manual % Complete dropdown', (tester) async {
      tester.view.physicalSize = const Size(1280, 2500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final t1 = createSubTask(id: 'w-t1', parentActionId: 'ACT-WRK-SCR-01', title: 'Worker Task 1');
      final t2 = createSubTask(id: 'w-t2', parentActionId: 'ACT-WRK-SCR-01', title: 'Worker Task 2');
      final action = createAction(
        id: 'ACT-WRK-SCR-01',
        subject: 'Worker Update Screen Checklist',
        primary: staffUser,
        percentComplete: 40,
        subTasks: [t1, t2],
      );
      MockActionStore.instance.add(action);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkerActionUpdateScreen(
            action: action,
            currentUserId: staffUser.personId,
            currentUserName: staffUser.name,
            currentUserEmail: staffUser.email,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Checklist title
      expect(find.text('TASKS & CHECKLIST (0 / 2 COMPLETED)'), findsOneWidget);

      // % Complete dropdown is present and displays 40%
      expect(find.byType(DropdownButtonFormField<String>), findsWidgets);
      expect(find.text('40%'), findsWidgets);

      // Toggle Task 1
      final cb = find.byKey(const Key('worker_task_checkbox_0'));
      await tester.tap(cb);
      await tester.pumpAndSettle();

      // Checklist title updates to 1 / 2 completed
      expect(find.text('TASKS & CHECKLIST (1 / 2 COMPLETED)'), findsOneWidget);
      // Dynamic progress calculated from subtasks: 1 of 2 = 50%
      expect(find.text('50%'), findsWidgets);
    });

    testWidgets('7. Actions without tasks preserve existing manual progress workflow without error', (tester) async {
      tester.view.physicalSize = const Size(1280, 2500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final action = createAction(
        id: 'ACT-NO-TASKS-01',
        subject: 'No Tasks Action',
        primary: managerPerson,
        percentComplete: 20,
        subTasks: const [],
      );
      MockActionStore.instance.add(action);

      await tester.pumpWidget(
        MaterialApp(
          home: ManagerActionUpdateScreen(
            action: action,
            currentUserId: managerProfile.id,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No checklist section
      expect(find.text('Assigned Tasks & Checklist'), findsNothing);
      // Manual progress slider is present
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('Progress: 20% *'), findsOneWidget);
    });

    testWidgets('8. Role-Based Controls: Manager viewing staff-assigned action hides Update Action button', (tester) async {
      tester.view.physicalSize = const Size(1280, 2500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final staffAssigned = createAction(
        id: 'ACT-STAFF-ROLE-01',
        subject: 'Staff Handled Action',
        primary: staffUser,
        percentComplete: 50,
        status: 'In Progress',
      );
      MockActionStore.instance.add(staffAssigned);

      await tester.pumpWidget(
        MaterialApp(
          home: ActionDetailsScreen(
            action: staffAssigned,
            managerContext: managerContext,
            isWorker: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Manager should NOT see routine Update Action button for staff-assigned action
      expect(find.widgetWithText(FilledButton, 'Update Action'), findsNothing);
      // Manager should see Edit Action
      expect(find.text('Edit Action'), findsOneWidget);
    });

    testWidgets('9. Role-Based Controls: Manager viewing manager-assigned action sees Update Action button', (tester) async {
      tester.view.physicalSize = const Size(1280, 2500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final managerAssigned = createAction(
        id: 'ACT-MGR-ROLE-01',
        subject: 'Manager Responsible Action',
        primary: managerPerson,
        percentComplete: 30,
        status: 'In Progress',
      );
      MockActionStore.instance.add(managerAssigned);

      await tester.pumpWidget(
        MaterialApp(
          home: ActionDetailsScreen(
            action: managerAssigned,
            managerContext: managerContext,
            isWorker: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Manager assigned action DOES show Update Action
      expect(find.text('Update Action'), findsWidgets);
    });

    testWidgets('10. Whole-Action Reopen: Hidden for active < 100% action assigned to staff', (tester) async {
      tester.view.physicalSize = const Size(1280, 2500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final activeAction = createAction(
        id: 'ACT-ACTIVE-STAFF-01',
        subject: 'Active Staff Action',
        primary: staffUser,
        percentComplete: 60,
        status: 'In Progress',
      );
      MockActionStore.instance.add(activeAction);

      await tester.pumpWidget(
        MaterialApp(
          home: ActionDetailsScreen(
            action: activeAction,
            managerContext: managerContext,
            isWorker: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Reopen Action button must NOT appear
      expect(find.text('Reopen Action'), findsNothing);
    });

    testWidgets('11. Whole-Action Reopen: Visible for Pending Review / 100% action, requires reason, transitions to In Progress, preserves tasks', (tester) async {
      tester.view.physicalSize = const Size(1280, 2500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final t1 = createSubTask(
        id: 't-whole-1',
        parentActionId: 'ACT-REVIEW-01',
        title: 'Task Alpha',
        status: 'Completed',
      );
      final reviewAction = createAction(
        id: 'ACT-REVIEW-01',
        subject: 'Completed Work For Review',
        primary: staffUser,
        percentComplete: 100,
        status: 'Pending Review',
        subTasks: [t1],
      );
      MockActionStore.instance.add(reviewAction);

      await tester.pumpWidget(
        MaterialApp(
          home: ActionDetailsScreen(
            action: reviewAction,
            managerContext: managerContext,
            isWorker: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Whole-action Reopen Action button must appear
      final reopenBtn = find.text('Reopen Action').first;
      expect(reopenBtn, findsOneWidget);
      await tester.tap(reopenBtn);
      await tester.pumpAndSettle();

      // Reopen dialog opens
      expect(find.byKey(const Key('reopen_action_reason_input')), findsOneWidget);

      // Attempt submit without reason
      await tester.tap(find.byKey(const Key('confirm_reopen_action_btn')));
      await tester.pumpAndSettle();
      expect(find.text('A reason is required to reopen this action.'), findsOneWidget);

      // Enter valid reason
      await tester.enterText(
        find.byKey(const Key('reopen_action_reason_input')),
        'Comprehensive re-audit required following client inspection',
      );
      await tester.tap(find.byKey(const Key('confirm_reopen_action_btn')));
      await tester.pumpAndSettle();

      // Action transitioned to In Progress and history recorded
      final updated = MockActionStore.instance.actions.firstWhere((a) => a.id == 'ACT-REVIEW-01');
      expect(updated.status, equals('In Progress'));
      expect(updated.history.any((h) => h.contains('re-audit required')), isTrue);
      // Tasks are NOT unchecked or wiped
      expect(updated.subTasks.first.isCompleted, isTrue);
    });

    testWidgets('12. ActionDetailsScreen displays independent task count without derived percentage in Overview card', (tester) async {
      tester.view.physicalSize = const Size(1280, 2500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final t1 = createSubTask(id: 't-ov-1', parentActionId: 'ACT-OV-01', title: 'Task 1', status: 'Completed');
      final t2 = createSubTask(id: 't-ov-2', parentActionId: 'ACT-OV-01', title: 'Task 2', status: 'Open');
      final action = createAction(
        id: 'ACT-OV-01',
        subject: 'Overview Card Test',
        primary: staffUser,
        percentComplete: 60,
        subTasks: [t1, t2],
      );
      MockActionStore.instance.add(action);

      await tester.pumpWidget(
        MaterialApp(
          home: ActionDetailsScreen(
            action: action,
            managerContext: managerContext,
            isWorker: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Overview card title shows "1 of 2 completed" without derived percent
      expect(find.text('Action Tasks & Checklist (1 of 2 completed)'), findsOneWidget);
      expect(find.text('1 of 2 tasks completed'), findsOneWidget);
      // Action-level progress badge displays manual progress (60%)
      expect(find.text('60%'), findsWidgets);
    });

    testWidgets('13. Navigation Round-Trip: Navigating to Manager Update, modifying tasks and manual progress, persists accurately', (tester) async {
      tester.view.physicalSize = const Size(1280, 2500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final t1 = createSubTask(id: 't-nav-1', parentActionId: 'ACT-NAV-01', title: 'Task 1', status: 'Open');
      final action = createAction(
        id: 'ACT-NAV-01',
        subject: 'Navigation Roundtrip Test',
        primary: managerPerson,
        percentComplete: 20,
        subTasks: [t1],
      );
      MockActionStore.instance.add(action);

      ActionRecord? navResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                final res = await Navigator.push<ActionRecord>(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => ManagerActionUpdateScreen(
                      action: action,
                      currentUserId: managerProfile.id,
                    ),
                  ),
                );
                navResult = res;
              },
              child: const Text('Open Update Screen'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Update Screen'));
      await tester.pumpAndSettle();

      // Check task
      final cb = find.byKey(const Key('manager_task_checkbox_0'));
      await tester.tap(cb);
      await tester.pumpAndSettle();

      // Change progress slider from 20% to 50%
      final slider = find.byType(Slider);
      await tester.drag(slider, const Offset(60, 0));
      await tester.pumpAndSettle();

      // Enter mandatory update comments
      await tester.enterText(find.byType(TextFormField).first, 'Completed task 1 and updated progress');
      await tester.pumpAndSettle();

      // Save update
      await tester.tap(find.text('Save Update').first);
      await tester.pumpAndSettle();

      expect(navResult, isNotNull);
      expect(navResult!.subTasks.first.isCompleted, isTrue);
      expect(navResult!.percentComplete, isNot(equals(20)));
    });
  });
}
