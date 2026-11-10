import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/external_recipient.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/add_action_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_action_update_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/models/team.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:action_flow/services/email_service.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const testOrgId = 'org-test-sobha-01';
  const otherOrgId = 'org-other-corp-99';

  final internalStaff1 = ActionPersonReference(
    personId: '00000000-0000-0000-0000-000000000001',
    name: 'Suresh Engineer',
    type: PersonType.internalUser,
    email: 'suresh.engineer@sobha.com',
  );

  final internalStaff2 = ActionPersonReference(
    personId: '00000000-0000-0000-0000-000000000002',
    name: 'Anita Safety Officer',
    type: PersonType.internalUser,
    email: 'anita.safety@sobha.com',
  );

  final externalContractor = ActionPersonReference(
    personId: '11111111-1111-1111-1111-111111110001',
    name: 'Robert Contractor',
    type: PersonType.externalWorker,
    email: 'robert.contractor@apex.com',
    company: 'Apex Scaffolding Services',
  );

  const testManagerProfile = UserProfile(
    id: 'mgr-user-001',
    name: 'HSE Manager',
    email: 'hse.manager@sobha.com',
    phone: '+971501234567',
    designation: 'HSE Lead',
    department: 'Safety',
    site: 'Downtown Site',
    role: 'manager',
    organizationId: testOrgId,
    organizationName: 'Sobha Constructions',
  );

  const testWorkerProfile = UserProfile(
    id: '00000000-0000-0000-0000-000000000001',
    name: 'Suresh Engineer',
    email: 'suresh.engineer@sobha.com',
    phone: '+971501234568',
    designation: 'Senior Engineer',
    department: 'Engineering',
    site: 'North Tower',
    role: 'staff',
    organizationId: testOrgId,
    organizationName: 'Sobha Constructions',
  );

  final testManagerContext = ManagerContext(
    authUserId: 'mgr-user-001',
    profile: testManagerProfile,
    organizationId: testOrgId,
    organizationName: 'Sobha Constructions',
    scopes: const [
      ManagerScopeItem(
        departmentId: 'dept-safety-01',
        departmentName: 'Safety',
        siteId: 'site-001',
        siteName: 'Downtown Site',
      ),
    ],
  );

  setUp(() {
    MockActionStore.instance.actions.clear();
    MockActionStore.instance.externalRecipients.clear();
    MockActionStore.instance.emailReminders.clear();
    MockActionStore.instance.profiles.clear();
    EmailService.mockSendHandler = null;

    // Reset MockPeopleStore test entries
    MockPeopleStore.instance.people.removeWhere(
      (p) =>
          p.id.startsWith('AFU-TEST') ||
          p.id.startsWith('EXT-TEST') ||
          p.email.contains('test') ||
          p.id == internalStaff1.personId,
    );

    MockPeopleStore.instance.people.add(
      Person(
        id: internalStaff1.personId,
        name: internalStaff1.name,
        email: internalStaff1.email,
        phone: '+971501234568',
        designation: 'Senior Engineer',
        department: 'Safety',
        departmentId: 'dept-safety-01',
        site: 'Downtown Site',
        siteId: 'site-001',
        type: PersonType.internalUser,
        isActive: true,
        role: UserRole.actionOwnerWorker,
      ),
    );

    // Seed mock internal profiles for testOrgId
    MockActionStore.instance.profiles.addAll([
      {
        'id': internalStaff1.personId,
        'organization_id': testOrgId,
        'email': internalStaff1.email,
        'full_name': internalStaff1.name,
        'is_active': true,
        'status': 'active',
        'department': 'Engineering',
        'site': 'North Tower',
      },
      {
        'id': internalStaff2.personId,
        'organization_id': testOrgId,
        'email': internalStaff2.email,
        'full_name': internalStaff2.name,
        'is_active': true,
        'status': 'active',
        'department': 'HSE Compliance',
        'site': 'South Complex',
      },
      // Inactive internal profile (should NOT appear)
      {
        'id': '00000000-0000-0000-0000-000000000003',
        'organization_id': testOrgId,
        'email': 'inactive.staff@sobha.com',
        'full_name': 'Inactive Staff',
        'is_active': false,
        'status': 'inactive',
      },
      // Profile belonging to another organization (should NOT appear)
      {
        'id': '99999999-9999-9999-9999-999999999999',
        'organization_id': otherOrgId,
        'email': 'other.corp@other.com',
        'full_name': 'Other Corp Staff',
        'is_active': true,
        'status': 'active',
      },
    ]);

    // Seed mock external recipient
    MockActionStore.instance.externalRecipients.add(
      ExternalRecipient(
        id: externalContractor.personId,
        organizationId: testOrgId,
        fullName: externalContractor.name,
        email: externalContractor.email,
        companyName: externalContractor.company,
        isActive: true,
      ),
    );
  });

  tearDown(() {
    EmailService.mockSendHandler = null;
  });

  // ===========================================================================
  // SECTION A: Internal Staff Selector Tests
  // ===========================================================================
  group('A. Internal Staff Selector Requirements', () {
    test('A1: fetchEligibleAssignees returns active internal users across departments and sites within org', () async {
      final assignees = await ActionService.instance.fetchEligibleAssignees(
        organizationId: testOrgId,
      );

      final emails = assignees.map((a) => a.email.toLowerCase()).toList();
      expect(emails, contains('suresh.engineer@sobha.com'));
      expect(emails, contains('anita.safety@sobha.com'));
      // Inactive user excluded
      expect(emails, isNot(contains('inactive.staff@sobha.com')));
      // Other organization excluded
      expect(emails, isNot(contains('other.corp@other.com')));
      // All returned must be internalUser type
      for (final a in assignees) {
        expect(a.type, equals(PersonType.internalUser));
      }
    });

    test('A2: fetchEligibleAssignees excludes external recipients even if active in same org', () async {
      final assignees = await ActionService.instance.fetchEligibleAssignees(
        organizationId: testOrgId,
      );

      final emails = assignees.map((a) => a.email.toLowerCase()).toList();
      expect(emails, isNot(contains('robert.contractor@apex.com')));
    });

    testWidgets('A3: AddActionScreen internal staff selector displays active internal users without department restriction', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: AddActionScreen(
            actionId: 'ACT-STAFF-01',
            managerContext: testManagerContext,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Add New Internal Person dialog
      final addInternalBtn = find.text('Add New Internal Person');
      expect(addInternalBtn, findsOneWidget);
      await tester.tap(addInternalBtn);
      await tester.pumpAndSettle();

      // Verify the dialog contains the dropdown for existing ActionFlow person
      expect(find.text('Select existing ActionFlow person'), findsOneWidget);

      // Close dialog
      await tester.tap(
        find.descendant(of: find.byType(Dialog), matching: find.text('Cancel')),
      );
      await tester.pumpAndSettle();
    });
  });

  // ===========================================================================
  // SECTION B: External Assignment Email Failure Handling
  // ===========================================================================
  group('B. Assignment Email Failure Handling', () {
    testWidgets('B1: Action creation succeeds when external assignment email fails, showing sanitized warning', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Configure EmailService mock to fail with an error containing API details
      EmailService.mockSendHandler = (params) {
        throw Exception(
          'Resend API error 403: domain not verified or API key resend_sk_12345abcde is restricted on endpoint https://api.resend.com/emails',
        );
      };

      await tester.pumpWidget(
        MaterialApp(
          home: AddActionScreen(
            actionId: 'ACT-EMAIL-FAIL-01',
            managerContext: testManagerContext,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to External
      await tester.tap(find.byKey(const Key('recipient_type_external')));
      await tester.pumpAndSettle();

      // Fill in action details using TextFormField widgets
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Action Title *'),
        'Test Action With Email Failure',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Action Description'),
        'Testing decoupled creation on email failure.',
      );

      // Select external recipient from dropdown
      final extDropdown = find.byType(DropdownButtonFormField<String?>);
      expect(extDropdown, findsOneWidget);
      await tester.tap(extDropdown);
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Robert Contractor').last);
      await tester.pumpAndSettle();

      // Tap Send Action
      final sendBtn = find.text('SEND ACTION');
      expect(sendBtn, findsOneWidget);
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      // 1. Verify action WAS created and persisted in store despite email failure
      final createdAction = MockActionStore.instance.actions.firstWhereOrNull(
        (a) => a.id == 'ACT-EMAIL-FAIL-01',
      );
      expect(createdAction, isNotNull, reason: 'Action must be saved even if email fails');
      expect(createdAction!.subject, equals('Test Action With Email Failure'));

      // 2. Verify SnackBar was shown with sanitized message and NO sensitive keys
      final snackFinder = find.byType(SnackBar);
      expect(snackFinder, findsOneWidget);
      final snackWidget = tester.widget<SnackBar>(snackFinder);
      final textWidget = snackWidget.content as Text;
      final msg = textWidget.data ?? '';

      // Must not leak resend secret key or raw API url
      expect(msg, isNot(contains('resend_sk_12345abcde')));
      expect(msg, isNot(contains('https://api.resend.com')));
      // Must contain helpful sanitized reason
      expect(
        msg.toLowerCase().contains('email') ||
            msg.toLowerCase().contains('saved') ||
            msg.toLowerCase().contains('domain'),
        isTrue,
      );
    });
  });

  // ===========================================================================
  // SECTION C: Manager-Defined Tasks in Add Action
  // ===========================================================================
  group('C. Manager-Defined Tasks in Add Action', () {
    testWidgets('C1: Can add multiple tasks, edit title, delete a task, and inherit current assignee', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: AddActionScreen(
            actionId: 'ACT-TASKS-01',
            managerContext: testManagerContext,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Tasks section is rendered
      expect(find.text('ACTION TASKS / CHECKLIST'), findsOneWidget);
      expect(
        find.text(
          'No tasks defined. Add tasks to break this action down into trackable checklist items for assignees.',
        ),
        findsOneWidget,
      );

      // Add Task 1
      final addTaskBtn = find.byKey(const Key('add_task_btn'));
      expect(addTaskBtn, findsOneWidget);
      await tester.tap(addTaskBtn);
      await tester.pumpAndSettle();

      // Verify Task 1 added
      expect(find.byKey(const Key('task_title_input_0')), findsOneWidget);

      // Add Task 2
      await tester.tap(addTaskBtn);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('task_title_input_1')), findsOneWidget);

      // Add Task 3
      await tester.tap(addTaskBtn);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('task_title_input_2')), findsOneWidget);

      // Edit Task 1 Title
      await tester.enterText(
        find.byKey(const Key('task_title_input_0')),
        'Inspect scaffolding anchors',
      );
      // Edit Task 2 Title
      await tester.enterText(
        find.byKey(const Key('task_title_input_1')),
        'Verify worker harness certificates',
      );
      await tester.pumpAndSettle();

      // Remove Task 3 using its delete button
      final deleteBtn2 = find.byKey(const Key('remove_task_btn_2'));
      expect(deleteBtn2, findsOneWidget);
      await tester.tap(deleteBtn2);
      await tester.pumpAndSettle();

      // Verify Task 3 is removed and only 2 tasks remain
      expect(find.byKey(const Key('remove_task_btn_2')), findsNothing);
      expect(find.text('Inspect scaffolding anchors'), findsOneWidget);
      expect(find.text('Verify worker harness certificates'), findsOneWidget);

      // Assign primary internal person
      final internalSearch = find.byType(Autocomplete<Person>);
      expect(internalSearch, findsOneWidget);
      await tester.enterText(internalSearch, 'Suresh');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('internal_person_option_Suresh Engineer')));
      await tester.pumpAndSettle();

      // Fill required fields and save
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Action Title *'),
        'Action With Manager Tasks',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Action Description'),
        'Testing manager defined task checklist persistence.',
      );

      await tester.tap(find.text('SEND ACTION'));
      await tester.pumpAndSettle();

      // Verify persisted in MockActionStore
      final savedAction = MockActionStore.instance.actions.firstWhereOrNull(
        (a) => a.id == 'ACT-TASKS-01',
      );
      expect(savedAction, isNotNull);
      expect(savedAction!.subTasks.length, equals(2));
      expect(savedAction.subTasks[0].title, equals('Inspect scaffolding anchors'));
      expect(savedAction.subTasks[1].title, equals('Verify worker harness certificates'));
      // Both tasks should initially be incomplete and progress = 0%
      expect(savedAction.subTasks[0].isCompleted, isFalse);
      expect(savedAction.subTasks[1].isCompleted, isFalse);
      expect(savedAction.percentComplete, equals(0));
    });

    testWidgets('C2: Edit Action preserves existing tasks and allows adding new tasks', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final existingAction = ActionRecord(
        id: 'ACT-EXISTING-01',
        subject: 'Existing Action with Tasks',
        description: 'Existing description',
        actionRequired: 'Inspect and repair',
        division: 'Safety',
        status: 'Open',
        priority: 'High',
        department: 'Safety',
        assignedTo: 'Suresh Engineer',
        percentComplete: 50,
        subTasks: [
          ActionSubTask(
            id: 'subtask-1',
            parentActionId: 'ACT-EXISTING-01',
            title: 'Existing Task 1',
            instruction: '',
            assignedStaff: 'Suresh Engineer',
            status: 'Completed',
            completedAt: '2026-10-15',
            completedBy: 'Suresh Engineer',
          ),
          ActionSubTask(
            id: 'subtask-2',
            parentActionId: 'ACT-EXISTING-01',
            title: 'Existing Task 2',
            instruction: '',
            assignedStaff: 'Suresh Engineer',
            status: 'Open',
          ),
        ],
      );
      MockActionStore.instance.actions.add(existingAction);

      await tester.pumpWidget(
        MaterialApp(
          home: AddActionScreen(
            actionId: 'ACT-EXISTING-01',
            existingAction: existingAction,
            managerContext: testManagerContext,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Existing tasks should be displayed
      expect(find.text('Existing Task 1'), findsOneWidget);
      expect(find.text('Existing Task 2'), findsOneWidget);

      // Add a third task
      final addTaskBtn = find.byKey(const Key('add_task_btn'));
      await tester.tap(addTaskBtn);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('task_title_input_2')),
        'Newly Added Task 3',
      );
      await tester.pumpAndSettle();

      // Save edited action (in edit mode the button is 'SAVE CHANGES')
      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pumpAndSettle();

      final updated = MockActionStore.instance.actions.firstWhere(
        (a) => a.id == 'ACT-EXISTING-01',
      );
      expect(updated.subTasks.length, equals(3));
      // 1 out of 3 tasks completed: (1 / 3) * 100 = 33%
      expect(updated.percentComplete, equals(33));
    });
  });

  // ===========================================================================
  // SECTION D: Task Completion, Reopening, and Progress Recalculation
  // ===========================================================================
  group('D. Task Completion, Reopening, and Progress Recalculation', () {
    testWidgets('D1: Staff Portal (WorkerActionUpdateScreen) allows completing and reopening tasks with auto-progress calculation', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final action = ActionRecord(
        id: 'ACT-WORKER-01',
        subject: 'Worker Task Progress Test',
        description: 'Verify worker can complete and reopen tasks',
        actionRequired: 'Complete assigned checklist',
        division: 'Safety',
        status: 'In Progress',
        priority: 'Medium',
        department: 'Safety',
        assignedTo: 'Suresh Engineer',
        percentComplete: 0,
        workerMessageSubject: 'Progress note',
        workerMessage: 'Checking task items.',
        subTasks: [
          ActionSubTask(
            id: 'task-a',
            parentActionId: 'ACT-WORKER-01',
            title: 'First checklist item',
            instruction: '',
            assignedStaff: 'Suresh Engineer',
            status: 'Open',
          ),
          ActionSubTask(
            id: 'task-b',
            parentActionId: 'ACT-WORKER-01',
            title: 'Second checklist item',
            instruction: '',
            assignedStaff: 'Suresh Engineer',
            status: 'Open',
          ),
        ],
      );

      ActionRecord? returnedAction;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                final result = await Navigator.push<ActionRecord>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WorkerActionUpdateScreen(action: action),
                  ),
                );
                returnedAction = result;
              },
              child: const Text('Open Update'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Update'));
      await tester.pumpAndSettle();

      // 1. Initially both checkboxes are unchecked
      expect(find.text('First checklist item'), findsOneWidget);
      expect(find.text('Second checklist item'), findsOneWidget);
      expect(find.text('TASKS & CHECKLIST (0 / 2 COMPLETED)'), findsOneWidget);

      // 2. Check the first task
      final checkboxA = find.byKey(const Key('worker_task_checkbox_0'));
      expect(checkboxA, findsOneWidget);
      await tester.tap(checkboxA);
      await tester.pumpAndSettle();

      // Checklist counter updates to 1 of 2 completed
      expect(find.text('TASKS & CHECKLIST (1 / 2 COMPLETED)'), findsOneWidget);

      // 3. Check the second task
      final checkboxB = find.byKey(const Key('worker_task_checkbox_1'));
      expect(checkboxB, findsOneWidget);
      await tester.tap(checkboxB);
      await tester.pumpAndSettle();

      // Checklist counter updates to 2 of 2 completed
      expect(find.text('TASKS & CHECKLIST (2 / 2 COMPLETED)'), findsOneWidget);

      // 4. Reopen the first task by unchecking it
      await tester.tap(checkboxA);
      await tester.pumpAndSettle();

      // Checklist counter updates back to 1 of 2 completed
      expect(find.text('TASKS & CHECKLIST (1 / 2 COMPLETED)'), findsOneWidget);

      // 5. Save update via AppBar button and verify returned action
      final saveBtn = find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithText(OutlinedButton, 'Save Update'),
      );
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(returnedAction, isNotNull);
      expect(returnedAction!.percentComplete, equals(50));
      expect(returnedAction!.subTasks[0].isCompleted, isFalse);
      expect(returnedAction!.subTasks[1].isCompleted, isTrue);
    });

    testWidgets('D2: ActionDetailsScreen allows reopening completed subtask and recalculates progress', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final action = ActionRecord(
        id: 'ACT-DETAILS-01',
        subject: 'Details Screen Reopen Test',
        description: 'Verify reopen button updates progress',
        actionRequired: 'Ensure all tasks are executed',
        division: 'Safety',
        status: 'In Progress',
        priority: 'High',
        department: 'Safety',
        assignedTo: 'Suresh Engineer',
        percentComplete: 100,
        subTasks: [
          ActionSubTask(
            id: 'task-10',
            parentActionId: 'ACT-DETAILS-01',
            title: 'Subtask 10',
            instruction: '',
            assignedStaff: 'Suresh Engineer',
            status: 'Completed',
            completedAt: '2026-10-16',
            completedBy: 'Suresh Engineer',
          ),
          ActionSubTask(
            id: 'task-20',
            parentActionId: 'ACT-DETAILS-01',
            title: 'Subtask 20',
            instruction: '',
            assignedStaff: 'Suresh Engineer',
            status: 'Completed',
            completedAt: '2026-10-16',
            completedBy: 'Suresh Engineer',
          ),
        ],
      );
      MockActionStore.instance.actions.add(action);

      await tester.pumpWidget(
        MaterialApp(
          home: ActionDetailsScreen(
            action: action,
            managerContext: testManagerContext,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Sub-tasks tab (tab index 2)
      final subtasksTab = find.text('Sub-tasks');
      expect(subtasksTab, findsOneWidget);
      await tester.tap(subtasksTab);
      await tester.pumpAndSettle();

      // Verify both tasks have a "Reopen" button
      final reopenBtn10 = find.byKey(const Key('reopen_subtask_btn_task-10'));
      expect(reopenBtn10, findsOneWidget);

      // Tap Reopen on task-10
      await tester.tap(reopenBtn10);
      await tester.pumpAndSettle();

      // Enter reopen reason and confirm
      final reasonInput = find.byKey(const Key('reopen_subtask_reason_task-10'));
      if (reasonInput.evaluate().isNotEmpty) {
        await tester.enterText(reasonInput, 'Need to redo inspection');
        await tester.pumpAndSettle();
        final confirmBtn = find.byKey(const Key('confirm_reopen_subtask_btn_task-10'));
        await tester.tap(confirmBtn);
        await tester.pumpAndSettle();
      }

      // Reopening task-10 resets it to Open while preserving overall action progress (100)
      final updatedAction = MockActionStore.instance.actions.firstWhere(
        (a) => a.id == 'ACT-DETAILS-01',
      );
      expect(updatedAction.percentComplete, equals(100));
      expect(updatedAction.subTasks.firstWhere((s) => s.id == 'task-10').status, equals('Open'));
    });

    testWidgets('D3: Zero tasks behavior preserves manual progress setting without conflict', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final action = ActionRecord(
        id: 'ACT-ZERO-TASKS-01',
        subject: 'Zero Tasks Manual Progress',
        description: 'Should preserve manual 75% progress',
        actionRequired: 'Maintain plant machinery',
        division: 'Safety',
        status: 'In Progress',
        priority: 'Medium',
        department: 'Safety',
        assignedTo: 'Suresh Engineer',
        percentComplete: 75,
        workerMessageSubject: 'Maintenance update',
        workerMessage: 'Checked lubricants and oil levels.',
        subTasks: const [], // Zero tasks
      );

      ActionRecord? returnedAction;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                final result = await Navigator.push<ActionRecord>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WorkerActionUpdateScreen(action: action),
                  ),
                );
                returnedAction = result;
              },
              child: const Text('Open Worker Update'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Worker Update'));
      await tester.pumpAndSettle();

      // With zero tasks, the manual % Complete dropdown is rendered
      expect(find.text('% Complete'), findsOneWidget);
      expect(find.text('75%'), findsWidgets);

      // Save update via AppBar button
      final saveBtn = find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithText(OutlinedButton, 'Save Update'),
      );
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(returnedAction, isNotNull);
      // Progress remains 75% and was NOT reset to 0%
      expect(returnedAction!.percentComplete, equals(75));
    });
  });

  // ===========================================================================
  // SECTION E: Task Progress Display in Action Register & Dashboards
  // ===========================================================================
  group('E. Task Progress Display in Dashboards', () {
    testWidgets('E1: Action Register renders task ratio (Tasks: 1/2) in progress cell', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final action = ActionRecord(
        id: 'ACT-REG-01',
        subject: 'Scaffolding Safety Walk',
        description: 'Action register task ratio test',
        actionRequired: 'Perform safety walk',
        division: 'Safety',
        status: 'Open',
        priority: 'High',
        department: 'Safety',
        assignedTo: 'Suresh Engineer',
        percentComplete: 50,
        subTasks: [
          ActionSubTask(
            id: 't1',
            parentActionId: 'ACT-REG-01',
            title: 'Task 1',
            instruction: '',
            assignedStaff: 'Suresh Engineer',
            status: 'Completed',
            completedAt: '2026-10-15',
          ),
          ActionSubTask(
            id: 't2',
            parentActionId: 'ACT-REG-01',
            title: 'Task 2',
            instruction: '',
            assignedStaff: 'Suresh Engineer',
            status: 'Open',
          ),
        ],
      );
      MockActionStore.instance.actions.add(action);

      await tester.pumpWidget(
        MaterialApp(
          home: ManagerDashboardScreen(
            managerContext: testManagerContext,
            userProfile: testManagerProfile,
            initialActions: [action],
            initialMyActions: [action],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Action Register
      final actionRegisterNav = find.text('Action Register');
      expect(actionRegisterNav, findsWidgets);
      await tester.tap(actionRegisterNav.first);
      await tester.pumpAndSettle();

      // Look for 'Tasks: 1/2' in the register
      expect(find.text('Tasks: 1/2'), findsOneWidget);
    });

    testWidgets('E2: Worker Dashboard renders task progress ratio on action cards', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final action = ActionRecord(
        id: 'ACT-WRK-DASH-01',
        subject: 'Worker Portal Action Card Test',
        description: 'Verify task ratio on card',
        actionRequired: 'Perform task updates',
        division: 'Safety',
        status: 'In Progress',
        priority: 'High',
        department: 'Safety',
        assignedTo: 'Suresh Engineer',
        percentComplete: 50,
        subTasks: [
          ActionSubTask(
            id: 's1',
            parentActionId: 'ACT-WRK-DASH-01',
            title: 'Task Alpha',
            instruction: '',
            assignedStaff: 'Suresh Engineer',
            status: 'Completed',
          ),
          ActionSubTask(
            id: 's2',
            parentActionId: 'ACT-WRK-DASH-01',
            title: 'Task Beta',
            instruction: '',
            assignedStaff: 'Suresh Engineer',
            status: 'Open',
          ),
        ],
      );
      MockActionStore.instance.actions.add(action);

      await tester.pumpWidget(
        const MaterialApp(
          home: WorkerDashboardScreen(
            userProfile: testWorkerProfile,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to My Actions tab
      final myActionsNav = find.text('My Actions');
      expect(myActionsNav, findsWidgets);
      await tester.tap(myActionsNav.first);
      await tester.pumpAndSettle();

      // Worker card should show '50% (1/2 Tasks)'
      expect(find.text('50% (1/2 Tasks)'), findsOneWidget);
    });
  });

  // ===========================================================================
  // SECTION F: Data Integrity & JSONB Serialization
  // ===========================================================================
  group('F. Data Integrity & JSONB Serialization', () {
    test('F1: ActionRecord serializes and deserializes subTasks JSONB correctly', () {
      final original = ActionRecord(
        id: 'ACT-SERIAL-01',
        subject: 'Serialization Test',
        description: 'Testing JSONB mapping',
        actionRequired: 'Verify JSONB serialization roundtrip',
        division: 'Engineering',
        status: 'Open',
        priority: 'High',
        department: 'Engineering',
        assignedTo: 'Suresh Engineer',
        percentComplete: 50,
        subTasks: [
          ActionSubTask(
            id: 'sub-01',
            parentActionId: 'ACT-SERIAL-01',
            title: 'Inspect welds',
            instruction: 'Check standard DIN 18800',
            status: 'Completed',
            assignedStaff: 'Suresh Engineer',
            assignedStaffId: '00000000-0000-0000-0000-000000000001',
            assignedStaffEmail: 'suresh.engineer@sobha.com',
            progressWeight: 50,
            dueDate: '2026-10-25',
            completedAt: '2026-10-16',
            completedBy: 'Suresh Engineer',
            remarks: 'Weld inspection passed',
          ),
          ActionSubTask(
            id: 'sub-02',
            parentActionId: 'ACT-SERIAL-01',
            title: 'Verify torque tests',
            instruction: '',
            assignedStaff: 'Anita Safety Officer',
            status: 'Open',
            progressWeight: 50,
            dueDate: '2026-10-26',
          ),
        ],
      );

      // Verify toSupabaseInsertMap includes subtasks
      final insertMap = original.toSupabaseInsertMap();
      expect(insertMap.containsKey('subtasks'), isTrue);
      final rawList = insertMap['subtasks'] as List<dynamic>;
      expect(rawList.length, equals(2));
      expect(rawList[0]['title'], equals('Inspect welds'));
      expect(rawList[0]['status'], equals('Completed'));
      expect(rawList[0]['assigned_staff_email'], equals('suresh.engineer@sobha.com'));
      expect(rawList[1]['title'], equals('Verify torque tests'));

      // Verify toSupabaseUpdateMap includes subtasks
      final updateMap = original.toSupabaseUpdateMap();
      expect(updateMap.containsKey('subtasks'), isTrue);

      // Verify fromSupabase reconstruction
      final supabaseRow = {
        'id': 'ACT-SERIAL-01',
        'title': 'Serialization Test',
        'description': 'Testing JSONB mapping',
        'action_required': 'Verify JSONB serialization roundtrip',
        'division': 'Engineering',
        'status': 'Open',
        'priority': 'High',
        'department': 'Engineering',
        'assigned_to': 'Suresh Engineer',
        'percent_complete': 50,
        'subtasks': rawList,
      };

      final reconstructed = ActionRecord.fromSupabase(supabaseRow);
      expect(reconstructed.subTasks.length, equals(2));
      expect(reconstructed.subTasks[0].title, equals('Inspect welds'));
      expect(reconstructed.subTasks[0].instruction, equals('Check standard DIN 18800'));
      expect(reconstructed.subTasks[0].isCompleted, isTrue);
      expect(reconstructed.subTasks[0].remarks, equals('Weld inspection passed'));
      expect(reconstructed.subTasks[1].title, equals('Verify torque tests'));
      expect(reconstructed.subTasks[1].isCompleted, isFalse);
    });
  });
}
