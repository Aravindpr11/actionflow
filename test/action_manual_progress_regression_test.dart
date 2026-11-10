import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testOrgId = 'ORG-TEST-001';

  const managerProfile = UserProfile(
    id: 'mgr-reg-01',
    name: 'Safety Manager',
    email: 'manager@test.com',
    phone: '+971501234567',
    designation: 'Safety Manager',
    department: 'HSE',
    site: 'Site Alpha',
    role: 'manager',
    organizationId: testOrgId,
    organizationName: 'Test Organization',
  );

  final staffUser = ActionPersonReference(
    personId: 'staff-reg-01',
    name: 'Staff Worker',
    type: PersonType.internalUser,
    email: 'worker@test.com',
  );

  final managerContext = ManagerContext(
    authUserId: managerProfile.id,
    profile: managerProfile,
    organizationId: testOrgId,
    organizationName: 'Test Organization',
    scopes: const [
      ManagerScopeItem(
        departmentId: 'dept-01',
        departmentName: 'HSE',
        siteId: 'site-01',
        siteName: 'Site Alpha',
      ),
    ],
  );

  setUp(() {
    MockActionStore.instance.actions.clear();
  });

  tearDown(() {
    MockActionStore.instance.actions.clear();
  });

  ActionSubTask createSubTask({
    required String id,
    required String parentActionId,
    required String title,
    String status = 'Open',
    bool isCompleted = false,
  }) {
    return ActionSubTask(
      id: id,
      parentActionId: parentActionId,
      title: title,
      instruction: 'Complete the safety check',
      assignedStaff: 'Staff Worker',
      assignedStaffId: 'staff-reg-01',
      assignedStaffEmail: 'worker@test.com',
      status: status,
      completedAt: isCompleted ? '2026-10-30' : '',
      completedBy: isCompleted ? 'Staff Worker' : '',
    );
  }

  ActionRecord createActionWithProgress({
    required String id,
    required int percentComplete,
    required List<ActionSubTask> subTasks,
  }) {
    return ActionRecord(
      id: id,
      actionNumber: 'ACT-$id',
      organizationId: testOrgId,
      departmentId: 'dept-01',
      siteId: 'site-01',
      subject: 'Manual Progress Test Action',
      actionRequired: 'Verify progress preservation',
      category: 'Inspection',
      source: 'Direct Action',
      priority: 'High',
      status: 'In Progress',
      percentComplete: percentComplete,
      dateRaised: '01 Jan 2026',
      targetDate: '15 Jan 2026',
      assignedTo: staffUser.name,
      assignedToId: staffUser.personId,
      primaryAssignee: staffUser,
      subTasks: subTasks,
      division: 'Safety',
    );
  }

  testWidgets(
      'Defect 1 Fix: Overall progress manually set to 45% is preserved when editing task details',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final t1 = createSubTask(
      id: 'task-45-1',
      parentActionId: 'ACT-45',
      title: 'Initial Task Title',
      status: 'Open',
    );
    final t2 = createSubTask(
      id: 'task-45-2',
      parentActionId: 'ACT-45',
      title: 'Second Task',
      status: 'Completed',
      isCompleted: true,
    );

    // Initial manual progress is 45% (different from task ratio 1/2 = 50%)
    final action = createActionWithProgress(
      id: 'ACT-45',
      percentComplete: 45,
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

    // Verify initial 45% is rendered in overview
    expect(find.text('Completion: 45%'), findsOneWidget);

    // Open edit dialog for task-45-1
    final editTaskBtn = find.byKey(Key('overview_edit_task_${t1.id}'));
    expect(editTaskBtn, findsOneWidget);
    await tester.scrollUntilVisible(
      editTaskBtn,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(editTaskBtn);
    await tester.pumpAndSettle();

    // Change task title in dialog
    final titleInput = find.byKey(Key('edit_subtask_title_${t1.id}'));
    expect(titleInput, findsOneWidget);
    await tester.enterText(titleInput, 'Updated Task Title By Manager');

    // Click Save Changes
    final saveBtn = find.text('Save Changes');
    expect(saveBtn, findsOneWidget);
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    // VERIFY: Overall completion percentage MUST STILL BE 45%, NOT overwritten to 50%!
    expect(find.text('Completion: 45%'), findsOneWidget);

    // Verify stored action in store also preserved 45%
    final stored = MockActionStore.instance.actions.firstWhere((a) => a.id == 'ACT-45');
    expect(stored.percentComplete, equals(45));
    expect(stored.subTasks.firstWhere((t) => t.id == t1.id).title,
        equals('Updated Task Title By Manager'));
  });

  testWidgets(
      'Defect 1 Fix: Overall progress manually set to 70% is preserved when editing another task',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final t1 = createSubTask(
      id: 'task-70-1',
      parentActionId: 'ACT-70',
      title: 'Task A',
      status: 'Open',
    );
    final t2 = createSubTask(
      id: 'task-70-2',
      parentActionId: 'ACT-70',
      title: 'Task B',
      status: 'Open',
    );
    final t3 = createSubTask(
      id: 'task-70-3',
      parentActionId: 'ACT-70',
      title: 'Task C',
      status: 'Completed',
      isCompleted: true,
    );

    // Initial manual progress is 70% (task ratio is 1/3 = 33%)
    final action = createActionWithProgress(
      id: 'ACT-70',
      percentComplete: 70,
      subTasks: [t1, t2, t3],
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

    expect(find.text('Completion: 70%'), findsOneWidget);

    // Edit task-70-2
    final editTaskBtn = find.byKey(Key('overview_edit_task_${t2.id}'));
    expect(editTaskBtn, findsOneWidget);
    await tester.scrollUntilVisible(
      editTaskBtn,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(editTaskBtn);
    await tester.pumpAndSettle();

    final titleInput = find.byKey(Key('edit_subtask_title_${t2.id}'));
    await tester.enterText(titleInput, 'Task B - High Priority Revision');

    final saveBtn = find.text('Save Changes');
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    // VERIFY: Still 70%
    expect(find.text('Completion: 70%'), findsOneWidget);
    final stored = MockActionStore.instance.actions.firstWhere((a) => a.id == 'ACT-70');
    expect(stored.percentComplete, equals(70));
  });

  test(
      'Subtask completion toggle via ActionService continues to preserve manual progress per Step 25',
      () async {
    final t1 = createSubTask(
      id: 'sub-toggle-1',
      parentActionId: 'ACT-TOGGLE-1',
      title: 'Subtask 1',
      status: 'Open',
    );
    final action = createActionWithProgress(
      id: 'ACT-TOGGLE-1',
      percentComplete: 45,
      subTasks: [t1],
    );
    MockActionStore.instance.add(action);

    final result = await ActionService.instance.submitSubtaskToggle(
      actionId: 'ACT-TOGGLE-1',
      taskId: 'sub-toggle-1',
      isCompleted: true,
    );

    expect(result['success'], isTrue);
    expect(result['percent_complete'], equals(45)); // Must stay 45%

    final refreshed = await ActionService.instance.fetchActionById('ACT-TOGGLE-1');
    expect(refreshed?.percentComplete, equals(45));
    expect(refreshed?.subTasks.first.isCompleted, isTrue);
  });

  test('Saving and reopening an action preserves the intended overall percentage',
      () async {
    final t1 = createSubTask(
      id: 'sub-reopen-1',
      parentActionId: 'ACT-SAVE-REOPEN',
      title: 'Subtask 1',
      status: 'Open',
    );
    final action = createActionWithProgress(
      id: 'ACT-SAVE-REOPEN',
      percentComplete: 85,
      subTasks: [t1],
    );
    await ActionService.instance.createAction(action);

    // Fetch as if page reloaded
    final loaded = await ActionService.instance.fetchActionById('ACT-SAVE-REOPEN');
    expect(loaded, isNotNull);
    expect(loaded!.percentComplete, equals(85));

    // Update title without changing percent
    final updated = loaded.copyWith(subject: 'Updated Subject');
    await ActionService.instance.updateAction(updated);

    final reloaded = await ActionService.instance.fetchActionById('ACT-SAVE-REOPEN');
    expect(reloaded!.percentComplete, equals(85));
    expect(reloaded.subject, equals('Updated Subject'));
  });
}
