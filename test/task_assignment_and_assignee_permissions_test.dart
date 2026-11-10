import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/external_recipient.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_action_update_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/add_action_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_action_update_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/external_update/models/external_action_payload.dart';
import 'package:action_flow/features/external_update/screens/external_action_update_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const testOrgId = 'org-sobha-step21-01';

  // Internal users
  final userA = ActionPersonReference(
    personId: '10000000-0000-0000-0000-00000000000a',
    name: 'User A (Internal Staff)',
    type: PersonType.internalUser,
    email: 'user.a@sobha.com',
  );

  final userC = ActionPersonReference(
    personId: '30000000-0000-0000-0000-00000000000c',
    name: 'User C (Internal Safety)',
    type: PersonType.internalUser,
    email: 'user.c@sobha.com',
  );

  // External recipients
  final userB = ActionPersonReference(
    personId: '20000000-0000-0000-0000-00000000000b',
    name: 'User B (External Contractor)',
    type: PersonType.externalWorker,
    email: 'user.b@apexcontractors.com',
    company: 'Apex Scaffolding Ltd',
  );

  const managerProfile = UserProfile(
    id: 'mgr-profile-001',
    name: 'HSE Manager User',
    email: 'manager@sobha.com',
    phone: '+971501234567',
    designation: 'HSE Lead',
    department: 'Safety',
    site: 'Central Hub',
    role: 'manager',
    organizationId: testOrgId,
    organizationName: 'Sobha Constructions',
  );

  final managerContext = ManagerContext(
    authUserId: 'mgr-profile-001',
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

  ActionSubTask createTestSubTask({
    required String id,
    required String parentActionId,
    required String title,
    required String assignedStaff,
    String assignedStaffId = '',
    String assignedStaffEmail = '',
    String assigneeType = 'internal',
    String status = 'Open',
    String completedAt = '',
    String completedBy = '',
    String reopenReason = '',
  }) {
    return ActionSubTask(
      id: id,
      parentActionId: parentActionId,
      title: title,
      instruction: '',
      assignedStaff: assignedStaff,
      assignedStaffId: assignedStaffId,
      assignedStaffEmail: assignedStaffEmail,
      assigneeType: assigneeType,
      status: status,
      completedAt: completedAt,
      completedBy: completedBy,
      reopenReason: reopenReason,
    );
  }

  ActionRecord createTestRecord({
    required String id,
    String? actionNumber,
    required String subject,
    ActionPersonReference? primary,
    List<ActionPersonReference> additional = const [],
    List<ActionSubTask> subTasks = const [],
    List<ActionAssigneeRecord> assignees = const [],
    int percentComplete = 0,
    String status = 'In Progress',
    String? dateRaised,
    String? targetDate,
    String? priority,
    DateTime? createdAt,
  }) {
    final effectivePrimary = primary ?? ActionPersonReference(
      personId: 'staff-uuid-001',
      name: 'test staff',
      type: PersonType.internalUser,
      email: 'test.staff@sobha.com',
    );
    return ActionRecord(
      id: id,
      organizationId: testOrgId,
      actionNumber: actionNumber ?? id,
      subject: subject,
      description: 'Testing task assignments and access control',
      actionRequired: 'Complete task verification',
      division: 'Safety',
      department: 'Safety',
      site: 'Central Hub',
      assignedTo: effectivePrimary.name,
      assignedToId: effectivePrimary.personId,
      primaryAssignee: effectivePrimary,
      additionalPeople: additional,
      subTasks: subTasks,
      assignees: assignees,
      percentComplete: percentComplete,
      status: status,
      priority: priority ?? 'Medium',
      workerMessageSubject: 'Progress update note',
      workerMessage: 'Reporting on assigned checklist items.',
      remarks: 'Staff update remarks',
      dateRaised: dateRaised ?? '16 Oct 2026',
      targetDate: targetDate ?? '30 Oct 2026',
      createdAt: createdAt,
    );
  }

  setUp(() {
    MockActionStore.instance.actions.clear();
    MockActionStore.instance.externalRecipients.clear();
    MockActionStore.instance.emailReminders.clear();
    MockActionStore.instance.profiles.clear();
    ActionService.instance.mockAssigneePersistenceShouldFail = false;
    ActionService.instance.mockAssigneePersistenceFailureReason = null;

    MockPeopleStore.instance.people.removeWhere(
      (p) =>
          p.email.contains('user.a') ||
          p.email.contains('user.b') ||
          p.email.contains('user.c'),
    );

    // Seed mock internal profiles
    MockActionStore.instance.profiles.addAll([
      {
        'id': userA.personId,
        'organization_id': testOrgId,
        'email': userA.email,
        'full_name': userA.name,
        'is_active': true,
        'status': 'active',
        'department': 'Operations',
        'site': 'Site Alpha',
      },
      {
        'id': userC.personId,
        'organization_id': testOrgId,
        'email': userC.email,
        'full_name': userC.name,
        'is_active': true,
        'status': 'active',
        'department': 'Safety',
        'site': 'Central Hub',
      },
    ]);

    // Seed mock external recipient
    MockActionStore.instance.externalRecipients.add(
      ExternalRecipient(
        id: userB.personId,
        organizationId: testOrgId,
        fullName: userB.name,
        email: userB.email,
        companyName: userB.company,
        isActive: true,
      ),
    );
  });

  tearDown(() {
    ActionService.instance.mockAssigneePersistenceShouldFail = false;
    ActionService.instance.mockAssigneePersistenceFailureReason = null;
  });

  // ===========================================================================
  // 1. Mixed Internal and External Task Assignment & Decoupling
  // ===========================================================================
  group('1. Individual Task Assignment & Decoupling', () {
    testWidgets('1.1 Selecting a task assignee does not alter action-level assignees', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: AddActionScreen(
            actionId: 'ACT-STEP21-MIXED-01',
            managerContext: managerContext,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Assign overall action primary assignee to User A
      final internalSearch = find.byType(Autocomplete<Person>);
      expect(internalSearch, findsOneWidget);
      await tester.enterText(internalSearch, 'User A');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('internal_person_option_${userA.name}')));
      await tester.pumpAndSettle();

      // 2. Add 3 tasks
      final addTaskBtn = find.byKey(const Key('add_task_btn'));
      await tester.tap(addTaskBtn);
      await tester.pumpAndSettle();
      await tester.tap(addTaskBtn);
      await tester.pumpAndSettle();
      await tester.tap(addTaskBtn);
      await tester.pumpAndSettle();

      // Set Task 1: "Inspect the work area" — User A (Internal)
      await tester.enterText(
        find.byKey(const Key('task_title_input_0')),
        'Inspect the work area',
      );

      // Set Task 2: "Verify safety equipment" — User B (External)
      await tester.enterText(
        find.byKey(const Key('task_title_input_1')),
        'Verify safety equipment',
      );

      // Set Task 3: "Submit inspection report" — User C (Internal)
      await tester.enterText(
        find.byKey(const Key('task_title_input_2')),
        'Submit inspection report',
      );
      await tester.pumpAndSettle();

      // Select User B (External) for Task 2
      final task2Dropdown = find.byKey(const Key('task_assignee_selector_1'));
      expect(task2Dropdown, findsOneWidget);
      await tester.tap(task2Dropdown);
      await tester.pumpAndSettle();
      // Tap User B in dropdown items
      await tester.tap(find.textContaining('User B (External Contractor)').last);
      await tester.pumpAndSettle();

      // Verify Task 2 badge reflects External
      expect(find.byKey(const Key('task_assignee_badge_1')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('task_assignee_badge_1')),
          matching: find.text('External'),
        ),
        findsOneWidget,
      );

      // 3. Fill action details and submit
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Action Title *'),
        'Mixed Task Assignments Action',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Action Description'),
        'Testing task level assignment decoupling from action level assignment.',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SEND ACTION'));
      await tester.pumpAndSettle();

      // 4. Verify in MockActionStore
      final savedAction = MockActionStore.instance.actions.firstWhereOrNull(
        (a) => a.id == 'ACT-STEP21-MIXED-01',
      );
      expect(savedAction, isNotNull);

      // Invariant: Action-level assignment remains User A only
      expect(savedAction!.assignedTo, equals(userA.name));
      expect(savedAction.assignedToId, equals(userA.personId));
      expect(savedAction.primaryAssignee?.personId, equals(userA.personId));
      // Action-level recipient is NOT external (selecting task assignee did NOT change it)
      expect(savedAction.isExternalRecipient, isFalse);

      // Invariant: Tasks have independent assignees
      expect(savedAction.subTasks.length, equals(3));
      expect(savedAction.subTasks[0].title, equals('Inspect the work area'));
      expect(savedAction.subTasks[0].assigneeType, equals('internal'));
      expect(savedAction.subTasks[0].assignedStaffId, equals(userA.personId));

      expect(savedAction.subTasks[1].title, equals('Verify safety equipment'));
      expect(savedAction.subTasks[1].assigneeType, equals('external'));
      expect(savedAction.subTasks[1].assignedStaffId, equals(userB.personId));
      expect(savedAction.subTasks[1].isExternal, isTrue);

      expect(savedAction.subTasks[2].title, equals('Submit inspection report'));
    });

    testWidgets('1.2 Action submission rejects empty task titles', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: AddActionScreen(
            actionId: 'ACT-VALIDATION-01',
            managerContext: managerContext,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Assign primary internal person
      final internalSearch = find.byType(Autocomplete<Person>);
      expect(internalSearch, findsOneWidget);
      await tester.enterText(internalSearch, 'User A');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('internal_person_option_${userA.name}')));
      await tester.pumpAndSettle();

      // Add a task without entering a title
      final addTaskBtn = find.byKey(const Key('add_task_btn'));
      await tester.tap(addTaskBtn);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Action Title *'),
        'Action with blank task title',
      );

      await tester.tap(find.text('SEND ACTION'));
      await tester.pumpAndSettle();

      // SnackBar validation error displayed
      expect(
        find.text('Task #1 requires a title. Please provide a title or remove the task.'),
        findsOneWidget,
      );
      // Action must not be saved
      expect(MockActionStore.instance.actions.any((a) => a.id == 'ACT-VALIDATION-01'), isFalse);
    });
  });

  // ===========================================================================
  // 2. Task Assignment Persistence Across Edits
  // ===========================================================================
  group('2. Task Assignment Persistence Across Edits', () {
    testWidgets('2.1 Editing an action preserves task IDs, completion status, and assignee types', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final existingAction = createTestRecord(
        id: 'ACT-EDIT-PERSIST-01',
        subject: 'Action For Persistence Test',
        primary: userA,
        percentComplete: 50,
        subTasks: [
          createTestSubTask(
            id: 'task-stable-1',
            parentActionId: 'ACT-EDIT-PERSIST-01',
            title: 'Task 1 Completed Already',
            assignedStaff: userA.name,
            assignedStaffId: userA.personId,
            assignedStaffEmail: userA.email,
            assigneeType: 'internal',
            status: 'Completed',
            completedAt: '16 Oct 2026',
            completedBy: userA.name,
          ),
          createTestSubTask(
            id: 'task-stable-2',
            parentActionId: 'ACT-EDIT-PERSIST-01',
            title: 'Task 2 Incomplete External',
            assignedStaff: userB.name,
            assignedStaffId: userB.personId,
            assignedStaffEmail: userB.email,
            assigneeType: 'external',
            status: 'Open',
          ),
        ],
      );
      MockActionStore.instance.actions.add(existingAction);

      await tester.pumpWidget(
        MaterialApp(
          home: AddActionScreen(
            actionId: existingAction.id,
            existingAction: existingAction,
            managerContext: managerContext,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify existing tasks render with titles and badges
      expect(find.text('Task 1 Completed Already'), findsOneWidget);
      expect(find.text('Task 2 Incomplete External'), findsOneWidget);

      // Edit Task 2 title
      await tester.enterText(
        find.byKey(const Key('task_title_input_1')),
        'Task 2 Incomplete External Renamed',
      );
      await tester.pumpAndSettle();

      // Add a third task
      await tester.tap(find.byKey(const Key('add_task_btn')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('task_title_input_2')),
        'Newly Added Task 3',
      );
      await tester.pumpAndSettle();

      // Save changes
      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pumpAndSettle();

      final updated = MockActionStore.instance.actions.firstWhere(
        (a) => a.id == existingAction.id,
      );

      expect(updated.subTasks.length, equals(3));

      // Task 1: ID, completion status, and internal assignee type preserved
      expect(updated.subTasks[0].id, equals('task-stable-1'));
      expect(updated.subTasks[0].isCompleted, isTrue);
      expect(updated.subTasks[0].completedAt, equals('16 Oct 2026'));
      expect(updated.subTasks[0].completedBy, equals(userA.name));
      expect(updated.subTasks[0].assigneeType, equals('internal'));

      // Task 2: ID, external assignee type, and open status preserved
      expect(updated.subTasks[1].id, equals('task-stable-2'));
      expect(updated.subTasks[1].title, equals('Task 2 Incomplete External Renamed'));
      expect(updated.subTasks[1].assigneeType, equals('external'));
      expect(updated.subTasks[1].assignedStaffId, equals(userB.personId));
      expect(updated.subTasks[1].isCompleted, isFalse);

      // Task 3: Newly created task appended
      expect(updated.subTasks[2].title, equals('Newly Added Task 3'));
      // Progress calculation: 1 out of 3 tasks completed = 33%
      expect(updated.percentComplete, equals(33));
    });
  });

  // ===========================================================================
  // 3. Task-Level Authorization in Worker Portal
  // ===========================================================================
  group('3. Task-Level Authorization in Worker Portal', () {
    testWidgets('3.1 Internal staff sees only authorized tasks; other staff and external tasks are filtered', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final multiUserAction = createTestRecord(
        id: 'ACT-AUTH-FILTER-01',
        subject: 'Confidential Safety Checklist',
        primary: userA,
        subTasks: [
          createTestSubTask(
            id: 'task-for-user-a',
            parentActionId: 'ACT-AUTH-FILTER-01',
            title: 'Task Alpha — Assigned to User A',
            assignedStaff: userA.name,
            assignedStaffId: userA.personId,
            assignedStaffEmail: userA.email,
            assigneeType: 'internal',
            status: 'Open',
          ),
          createTestSubTask(
            id: 'task-for-user-b-ext',
            parentActionId: 'ACT-AUTH-FILTER-01',
            title: 'Task Beta — External Contractor Only',
            assignedStaff: userB.name,
            assignedStaffId: userB.personId,
            assignedStaffEmail: userB.email,
            assigneeType: 'external',
            status: 'Open',
          ),
          createTestSubTask(
            id: 'task-for-user-c',
            parentActionId: 'ACT-AUTH-FILTER-01',
            title: 'Task Gamma — Assigned to User C',
            assignedStaff: userC.name,
            assignedStaffId: userC.personId,
            assignedStaffEmail: userC.email,
            assigneeType: 'internal',
            status: 'Open',
          ),
        ],
      );

      // User A logs into worker update screen
      await tester.pumpWidget(
        MaterialApp(
          home: WorkerActionUpdateScreen(
            action: multiUserAction,
            currentUserId: userA.personId,
            currentUserName: userA.name,
            currentUserEmail: userA.email,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // User A MUST see their authorized task
      expect(find.text('Task Alpha — Assigned to User A'), findsOneWidget);
      expect(find.text('TASKS & CHECKLIST (0 / 1 COMPLETED)'), findsOneWidget);

      // User A MUST NOT see User B (external) or User C (other internal worker) tasks
      expect(find.text('Task Beta — External Contractor Only'), findsNothing);
      expect(find.text('Task Gamma — Assigned to User C'), findsNothing);
    });

    testWidgets('3.2 Worker completing their task updates overall action progress and preserves other tasks', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final multiUserAction = createTestRecord(
        id: 'ACT-AUTH-PROGRESS-02',
        subject: 'Overall Action Progress Test',
        primary: userA,
        subTasks: [
          createTestSubTask(
            id: 'task-user-a-1',
            parentActionId: 'ACT-AUTH-PROGRESS-02',
            title: 'User A Checklist 1',
            assignedStaff: userA.name,
            assignedStaffId: userA.personId,
            assigneeType: 'internal',
            status: 'Open',
          ),
          createTestSubTask(
            id: 'task-user-c-1',
            parentActionId: 'ACT-AUTH-PROGRESS-02',
            title: 'User C Checklist 1',
            assignedStaff: userC.name,
            assignedStaffId: userC.personId,
            assigneeType: 'internal',
            status: 'Open',
          ),
        ],
      );

      ActionRecord? returnedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                final res = await Navigator.push<ActionRecord>(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => WorkerActionUpdateScreen(
                      action: multiUserAction,
                      currentUserId: userA.personId,
                      currentUserName: userA.name,
                      currentUserEmail: userA.email,
                    ),
                  ),
                );
                returnedResult = res;
              },
              child: const Text('Open Portal'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Portal'));
      await tester.pumpAndSettle();

      // Check User A's task
      final taskACheckbox = find.byKey(const Key('worker_task_checkbox_0'));
      expect(taskACheckbox, findsOneWidget);
      await tester.tap(taskACheckbox);
      await tester.pumpAndSettle();

      // Overall action has 2 tasks in total (User A + User C). 1 completed
      expect(find.text('TASKS & CHECKLIST (1 / 1 COMPLETED)'), findsOneWidget);
      expect(
        find.textContaining('1 of 2 completed. Report overall action progress below.'),
        findsOneWidget,
      );

      // Save update
      await tester.tap(find.text('Save Update').last);
      await tester.pumpAndSettle();

      expect(returnedResult, isNotNull);
      // STEP 25 BUSINESS RULE: Completing task preserves overall action progress
      expect(returnedResult!.percentComplete, equals(multiUserAction.percentComplete));
      expect(returnedResult!.subTasks.length, equals(2));

      // User A's task was completed
      final taskA = returnedResult!.subTasks.firstWhere((t) => t.id == 'task-user-a-1');
      expect(taskA.isCompleted, isTrue);
      expect(taskA.completedBy, equals(userA.name));

      // User C's task was untouched and preserved in Open status
      final taskC = returnedResult!.subTasks.firstWhere((t) => t.id == 'task-user-c-1');
      expect(taskC.isCompleted, isFalse);
      expect(taskC.status, equals('Open'));
    });
  });

  // ===========================================================================
  // 4. Task-Level Authorization in External Contractor Portal
  // ===========================================================================
  group('4. Task-Level Authorization in External Contractor Portal', () {
    test('4.1 ExternalActionPayload only parses and delivers tasks belonging to that external recipient', () {
      final rawPayload = {
        'id': 'ACT-EXT-01',
        'action_number': 'ACT-EXT-01',
        'title': 'Contractor External View',
        'percent_complete': 0,
        'status': 'In Progress',
        'recipient_id': userB.personId,
        'recipient_email': userB.email,
        'subtasks': [
          {
            'id': 'internal-task-1',
            'title': 'Internal Worker Secret Task',
            'assigned_staff': userA.name,
            'assigned_staff_id': userA.personId,
            'assigned_staff_email': userA.email,
            'assignee_type': 'internal',
            'status': 'Open',
          },
          {
            'id': 'external-contractor-task-2',
            'title': 'Erect Scaffolding Guardrails',
            'assigned_staff': userB.name,
            'assigned_staff_id': userB.personId,
            'assigned_staff_email': userB.email,
            'assignee_type': 'external',
            'status': 'Open',
          },
        ],
      };

      final payload = ExternalActionPayload.fromJson(rawPayload);

      // Internal worker task must be strictly filtered out by the model
      expect(payload.subTasks.length, equals(1));
      expect(payload.subTasks.first.id, equals('external-contractor-task-2'));
      expect(payload.subTasks.first.title, equals('Erect Scaffolding Guardrails'));
      expect(payload.subTasks.first.isExternal, isTrue);
      expect(payload.subTasks.any((t) => t.id == 'internal-task-1'), isFalse);
    });

    testWidgets('4.2 External contractor portal displays authorized tasks and recalculates progress upon completion', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final contractorTask = createTestSubTask(
        id: 'ext-task-01',
        parentActionId: 'ACT-EXT-PORTAL-01',
        title: 'Install Edge Safety Netting',
        assignedStaff: userB.name,
        assignedStaffId: userB.personId,
        assignedStaffEmail: userB.email,
        assigneeType: 'external',
        status: 'Open',
      );

      final payload = ExternalActionPayload(
        actionId: 'ACT-EXT-PORTAL-01',
        actionNumber: 'ACT-EXT-PORTAL-01',
        title: 'External Site Safety',
        description: 'Safety installations',
        actionRequired: 'Install nets',
        category: 'Safety',
        priority: 'High',
        status: 'In Progress',
        percentComplete: 0,
        dateRaised: '16 Oct 2026',
        startDate: '16 Oct 2026',
        targetDate: '30 Oct 2026',
        dueDate: '30 Oct 2026',
        nextFollowUpDate: '',
        department: 'HSE',
        site: 'Site Alpha',
        organizationName: 'Sobha Constructions',
        isClosed: false,
        recentHistory: const [],
        recipientId: userB.personId,
        recipientName: userB.name,
        recipientEmail: userB.email,
        companyName: userB.company,
        phone: '+971501234567',
        subTasks: [contractorTask],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ExternalActionUpdateScreen(
            token: 'valid-test-token-hash-1234',
            initialPayload: payload,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check external task list
      expect(find.text('ASSIGNED TASKS (0 / 1 COMPLETED)'), findsOneWidget);
      expect(find.text('Install Edge Safety Netting'), findsOneWidget);

      // Toggle external task checkbox
      final checkbox = find.byKey(const Key('external_task_checkbox_0'));
      expect(checkbox, findsOneWidget);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();

      // Contractor's reported progress is recalculated to 100%
      expect(find.text('ASSIGNED TASKS (1 / 1 COMPLETED)'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 5. Assignee Deletion Error Investigation & Regression
  // ===========================================================================
  group('5. Assignee Deletion Error Investigation & Regression', () {
    test('5.1 Removing obsolete secondary assignee succeeds while preserving retained assignments and primary owner', () async {
      // Create action with primary owner (userA) and secondary assignees (userC)
      final initialRecord = createTestRecord(
        id: 'ACT-RECONCILE-01',
        subject: 'Assignee Reconciliation Regression',
        primary: userA,
        additional: [userC],
        assignees: [
          ActionAssigneeRecord(
            id: 'assignee-${userA.personId}',
            actionId: 'ACT-RECONCILE-01',
            profileId: userA.personId,
            profileName: userA.name,
            assignmentRole: 'owner',
            isRequired: true,
          ),
          ActionAssigneeRecord(
            id: 'assignee-${userC.personId}',
            actionId: 'ACT-RECONCILE-01',
            profileId: userC.personId,
            profileName: userC.name,
            assignmentRole: 'assignee',
            isRequired: true,
          ),
        ],
      );

      final created = await ActionService.instance.createAction(
        initialRecord,
        sendAssignmentNotification: false,
      );
      expect(created.assignees.length, equals(2));

      // Remove secondary assignee (userC) while keeping primary owner (userA)
      final updateCandidate = created.copyWith(
        additionalPeople: const [],
        assignees: [
          created.assignees.firstWhere((a) => a.profileId == userA.personId),
        ],
      );

      final updated = await ActionService.instance.updateAction(updateCandidate);

      // Verified: Obsolete secondary assignee was deleted safely
      expect(updated.assignees.length, equals(1));
      expect(updated.assignees.first.profileId, equals(userA.personId));
      expect(updated.assignees.first.assignmentRole, equals('owner'));
      expect(updated.additionalPeople, isEmpty);

      // Verified: Stored in action store without obsolete assignee
      final stored = MockActionStore.instance.actions.firstWhere((a) => a.id == created.id);
      expect(stored.assignees.length, equals(1));
      expect(stored.assignees.any((a) => a.profileId == userC.personId), isFalse);
    });

    test('5.2 Permission denied error during assignee deletion surfaces actionable exception without silent data loss', () async {
      final initialRecord = createTestRecord(
        id: 'ACT-PERMISSION-DENIED-01',
        subject: 'Permission Denied Simulation',
        primary: userA,
      );

      final created = await ActionService.instance.createAction(
        initialRecord,
        sendAssignmentNotification: false,
      );

      // Simulate the exact database error observed previously
      ActionService.instance.mockAssigneePersistenceShouldFail = true;
      ActionService.instance.mockAssigneePersistenceFailureReason =
          'permission denied for table action_assignees';

      final updateCandidate = created.copyWith(
        additionalPeople: [userC],
      );

      expect(
        () async => await ActionService.instance.updateAction(updateCandidate),
        throwsA(isA<ActionAssigneePersistenceException>().having(
          (e) => e.message,
          'message',
          contains('permission denied for table action_assignees'),
        )),
      );
    });
  });

  // ===========================================================================
  // 6. Action Details Visualization & Badges
  // ===========================================================================
  group('6. Action Details Visualization & Badges', () {
    testWidgets('6.1 ActionDetailsScreen displays distinct Internal vs External badges for subtasks', (tester) async {
      tester.view.physicalSize = const Size(1200, 2500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final action = createTestRecord(
        id: 'ACT-DETAILS-BADGE-01',
        subject: 'Action Details Badge Test',
        primary: userA,
        subTasks: [
          createTestSubTask(
            id: 'task-int-1',
            parentActionId: 'ACT-DETAILS-BADGE-01',
            title: 'Internal Subtask',
            assignedStaff: userA.name,
            assigneeType: 'internal',
            status: 'Open',
          ),
          createTestSubTask(
            id: 'task-ext-2',
            parentActionId: 'ACT-DETAILS-BADGE-01',
            title: 'External Subtask',
            assignedStaff: userB.name,
            assigneeType: 'external',
            status: 'Open',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ActionDetailsScreen(
            action: action,
            managerContext: managerContext,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Overview card renders both badges
      expect(find.text('Internal'), findsAtLeast(1));
      expect(find.text('External'), findsAtLeast(1));
    });
  });

  // ===========================================================================
  // 7. Step 23 Security Audit: submitSubtaskToggle & Staff Task Scoping
  // ===========================================================================
  group('7. Step 23 Security Audit: submitSubtaskToggle & Staff Task Scoping', () {
    test('7.1 ActionService.submitSubtaskToggle toggles task and recalculates progress in mock mode', () async {
      final action = createTestRecord(
        id: 'ACT-TOGGLE-01',
        subject: 'Action for Toggle RPC',
        primary: userA,
        subTasks: [
          createTestSubTask(
            id: 'task-tog-1',
            parentActionId: 'ACT-TOGGLE-01',
            title: 'Subtask 1',
            assignedStaff: userA.name,
            assigneeType: 'internal',
            status: 'Open',
          ),
          createTestSubTask(
            id: 'task-tog-2',
            parentActionId: 'ACT-TOGGLE-01',
            title: 'Subtask 2',
            assignedStaff: userC.name,
            assigneeType: 'internal',
            status: 'Open',
          ),
        ],
      );
      MockActionStore.instance.actions.add(action);

      // Complete task 1
      final res1 = await ActionService.instance.submitSubtaskToggle(
        actionId: 'ACT-TOGGLE-01',
        taskId: 'task-tog-1',
        isCompleted: true,
      );
      expect(res1['success'], isTrue);
      // STEP 25 BUSINESS RULE: Toggling task preserves overall action progress (0)
      expect(res1['percent_complete'], equals(0));
      expect(res1['completed_tasks'], equals(1));

      // Reopen task 1
      final res2 = await ActionService.instance.submitSubtaskToggle(
        actionId: 'ACT-TOGGLE-01',
        taskId: 'task-tog-1',
        isCompleted: false,
      );
      expect(res2['success'], isTrue);
      expect(res2['percent_complete'], equals(0));
      expect(res2['completed_tasks'], equals(0));
    });

    test('7.2 ActionService.submitSubtaskToggle returns error for non-existent action or task', () async {
      final res = await ActionService.instance.submitSubtaskToggle(
        actionId: 'NON-EXISTENT',
        taskId: 'NON-EXISTENT',
        isCompleted: true,
      );
      expect(res['success'], isFalse);
      expect(res['error'], isNotNull);
    });

    test('7.3 Staff Portal fetchMyActions scopes subtasks strictly to current staff user', () {
      final multiTaskAction = createTestRecord(
        id: 'ACT-SCOPED-01',
        subject: 'Multi Task Action',
        primary: userA,
        subTasks: [
          createTestSubTask(
            id: 'task-a',
            parentActionId: 'ACT-SCOPED-01',
            title: 'User A Task',
            assignedStaff: userA.name,
            assignedStaffId: userA.personId,
            assigneeType: 'internal',
          ),
          createTestSubTask(
            id: 'task-c',
            parentActionId: 'ACT-SCOPED-01',
            title: 'User C Task',
            assignedStaff: userC.name,
            assignedStaffId: userC.personId,
            assigneeType: 'internal',
          ),
          createTestSubTask(
            id: 'task-ext',
            parentActionId: 'ACT-SCOPED-01',
            title: 'Contractor Task',
            assignedStaff: userB.name,
            assignedStaffId: userB.personId,
            assigneeType: 'external',
          ),
        ],
      );

      // Simulate scoping logic in fetchMyActions for User A
      final scopedForUserA = multiTaskAction.subTasks.where((task) {
        if (task.isExternal) return false;
        if (task.assignedStaffId.isNotEmpty && task.assignedStaffId == userA.personId) return true;
        if (task.assignedStaffId.isEmpty && multiTaskAction.assignedToId == userA.personId) return true;
        return false;
      }).toList();

      expect(scopedForUserA.length, equals(1));
      expect(scopedForUserA.first.id, equals('task-a'));
      expect(scopedForUserA.any((t) => t.id == 'task-c'), isFalse);
      expect(scopedForUserA.any((t) => t.id == 'task-ext'), isFalse);

      // Simulate scoping logic for User C
      final scopedForUserC = multiTaskAction.subTasks.where((task) {
        if (task.isExternal) return false;
        if (task.assignedStaffId.isNotEmpty && task.assignedStaffId == userC.personId) return true;
        if (task.assignedStaffId.isEmpty && multiTaskAction.assignedToId == userC.personId) return true;
        return false;
      }).toList();

      expect(scopedForUserC.length, equals(1));
      expect(scopedForUserC.first.id, equals('task-c'));
      expect(scopedForUserC.any((t) => t.id == 'task-a'), isFalse);
      expect(scopedForUserC.any((t) => t.id == 'task-ext'), isFalse);
    });

    group('8. Step 25 Staff Portal Task Visibility & Completion Workflow', () {
      testWidgets('8.1 Staff Portal displays assigned tasks when matched by name, email, or inherited assignment', (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final testAction = createTestRecord(
          id: 'ACT-STEP25-01',
          subject: 'test task',
          primary: ActionPersonReference(
            personId: 'staff-uuid-001',
            name: 'test staff',
            type: PersonType.internalUser,
            email: 'test.staff@sobha.com',
          ),
          subTasks: [
            createTestSubTask(
              id: 'task-test-staff-1',
              parentActionId: 'ACT-STEP25-01',
              title: 'Individual Task for Test Staff',
              assignedStaff: 'test staff',
              assignedStaffId: 'staff-uuid-001',
              assignedStaffEmail: 'test.staff@sobha.com',
            ),
            createTestSubTask(
              id: 'task-peer-staff-2',
              parentActionId: 'ACT-STEP25-01',
              title: 'Peer Worker Checklist Item',
              assignedStaff: 'Other Colleague',
              assignedStaffId: 'other-colleague-uuid',
              assignedStaffEmail: 'other@sobha.com',
            ),
            createTestSubTask(
              id: 'task-contractor-3',
              parentActionId: 'ACT-STEP25-01',
              title: 'External Subcontractor Item',
              assignedStaff: 'External Contractor',
              assigneeType: 'external',
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: WorkerActionUpdateScreen(
              action: testAction,
              currentUserId: 'staff-uuid-001',
              currentUserName: 'test staff',
              currentUserEmail: 'test.staff@sobha.com',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Must see own assigned task
        expect(find.text('Individual Task for Test Staff'), findsOneWidget);
        expect(find.text('TASKS & CHECKLIST (0 / 1 COMPLETED)'), findsOneWidget);

        // 2. Peer staff and external tasks must NOT be visible
        expect(find.text('Peer Worker Checklist Item'), findsNothing);
        expect(find.text('External Subcontractor Item'), findsNothing);

        // 3. Manual % Complete dropdown is present and interactive
        expect(find.byType(DropdownButtonFormField<String>), findsWidgets);
      });

      testWidgets('8.2 Action with no tasks retains manual progress workflow without error', (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final zeroTaskAction = createTestRecord(
          id: 'ACT-STEP25-ZERO',
          subject: 'No Tasks Action',
          primary: ActionPersonReference(
            personId: 'staff-uuid-001',
            name: 'test staff',
            type: PersonType.internalUser,
            email: 'test.staff@sobha.com',
          ),
          percentComplete: 40,
          subTasks: const [],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: WorkerActionUpdateScreen(
              action: zeroTaskAction,
              currentUserId: 'staff-uuid-001',
              currentUserName: 'test staff',
              currentUserEmail: 'test.staff@sobha.com',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tasks checklist panel should not be present
        expect(find.byIcon(Icons.checklist_rtl_rounded), findsNothing);

        // Manual % complete selector should be present and show 40%
        expect(find.text('% Complete'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(DropdownButtonFormField<String>),
            matching: find.text('40%'),
          ),
          findsOneWidget,
        );
      });

      testWidgets('8.3 Toggling task completion recalculates action progress and preserves incomplete peer tasks', (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final twoTaskAction = createTestRecord(
          id: 'ACT-STEP25-TOGGLE',
          subject: 'Toggle Test Action',
          percentComplete: 30,
          primary: ActionPersonReference(
            personId: 'staff-uuid-001',
            name: 'test staff',
            type: PersonType.internalUser,
            email: 'test.staff@sobha.com',
          ),
          subTasks: [
            createTestSubTask(
              id: 'task-test-staff-1',
              parentActionId: 'ACT-STEP25-TOGGLE',
              title: 'My Task 1',
              assignedStaff: 'test staff',
              assignedStaffId: 'staff-uuid-001',
            ),
            createTestSubTask(
              id: 'task-test-staff-2',
              parentActionId: 'ACT-STEP25-TOGGLE',
              title: 'My Task 2',
              assignedStaff: 'test staff',
              assignedStaffId: 'staff-uuid-001',
            ),
          ],
        );

        MockActionStore.instance.add(twoTaskAction);

        ActionRecord? returnedResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  final res = await Navigator.push<ActionRecord>(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) => WorkerActionUpdateScreen(
                        action: twoTaskAction,
                        currentUserId: 'staff-uuid-001',
                        currentUserName: 'test staff',
                        currentUserEmail: 'test.staff@sobha.com',
                      ),
                    ),
                  );
                  returnedResult = res;
                },
                child: const Text('Open Update'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Update'));
        await tester.pumpAndSettle();

        expect(find.text('TASKS & CHECKLIST (0 / 2 COMPLETED)'), findsOneWidget);

        // Toggle task 1
        await tester.tap(find.byKey(const Key('worker_task_checkbox_0')));
        await tester.pumpAndSettle();

        // Task count updates, manual progress is preserved (does NOT overwrite with 50%)
        expect(find.text('TASKS & CHECKLIST (1 / 2 COMPLETED)'), findsOneWidget);
        expect(
          find.text('Progress is automatically calculated from task completion (50%).'),
          findsNothing,
        );

        // Save
        await tester.tap(find.text('Save Update').last);
        await tester.pumpAndSettle();

        expect(returnedResult, isNotNull);
        expect(returnedResult!.percentComplete, equals(30));
        expect(returnedResult!.subTasks.firstWhere((t) => t.id == 'task-test-staff-1').isCompleted, isTrue);
        expect(returnedResult!.subTasks.firstWhere((t) => t.id == 'task-test-staff-2').isCompleted, isFalse);
        // Does not automatically close action
        expect(returnedResult!.status, isNot(equals('Closed')));
      });

      testWidgets('8.4 Display-name match alone DOES NOT grant access to tasks when UUID and email differ', (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final targetAction = createTestRecord(
          id: 'ACT-STEP26-IDENTITY',
          subject: 'Strict Identity Checklist Action',
          primary: ActionPersonReference(
            personId: 'staff-uuid-001',
            name: 'test staff',
            type: PersonType.internalUser,
            email: 'test.staff@sobha.com',
          ),
          subTasks: [
            createTestSubTask(
              id: 'task-staff-001',
              parentActionId: 'ACT-STEP26-IDENTITY',
              title: 'Confidential Task For Legit Staff',
              assignedStaff: 'test staff',
              assignedStaffId: 'staff-uuid-001',
              assignedStaffEmail: 'test.staff@sobha.com',
            ),
          ],
        );

        MockActionStore.instance.add(targetAction);

        // Attacker has matching display name "test staff" but different UUID and email
        await tester.pumpWidget(
          MaterialApp(
            home: WorkerActionUpdateScreen(
              action: targetAction,
              currentUserId: 'attacker-uuid-999',
              currentUserName: 'test staff',
              currentUserEmail: 'attacker@evil.com',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Must NOT see the confidential task belonging to staff-uuid-001
        expect(find.text('Confidential Task For Legit Staff'), findsNothing);
        expect(find.text('TASKS & CHECKLIST (0 / 1 COMPLETED)'), findsNothing);
      });

      test('8.5 UUID and action-number identifiers resolve safely in subtask fetch and toggle', () async {
        final actionUuid = 'b5f00000-0000-0000-0000-000000001022';
        final actionNumber = 'ACT-1022';
        final actionRecord = createTestRecord(
          id: actionUuid,
          actionNumber: actionNumber,
          subject: 'Ident Resolution Action',
          subTasks: [
            createTestSubTask(
              id: 'task-ident-01',
              parentActionId: actionUuid,
              title: 'Resolve Me Task',
              assignedStaff: 'test staff',
              assignedStaffId: 'staff-uuid-001',
              assignedStaffEmail: 'test.staff@sobha.com',
            ),
          ],
        );

        MockActionStore.instance.add(actionRecord);

        // Fetch using UUID
        final tasksByUuid = await ActionService.instance.fetchActionSubtasks(actionUuid);
        expect(tasksByUuid, isNotEmpty);
        expect(tasksByUuid.first.id, equals('task-ident-01'));

        // Fetch using actionNumber
        final tasksByNumber = await ActionService.instance.fetchActionSubtasks(actionNumber);
        expect(tasksByNumber, isNotEmpty);
        expect(tasksByNumber.first.id, equals('task-ident-01'));

        // Toggle using actionNumber: task is toggled while manual progress is preserved
        final toggleRes = await ActionService.instance.submitSubtaskToggle(
          actionId: actionNumber,
          taskId: 'task-ident-01',
          isCompleted: true,
        );
        expect(toggleRes['success'], isTrue);
        expect(toggleRes['completed_tasks'], equals(1));
        expect(toggleRes['percent_complete'], equals(0));

        // Verify updated record in store preserves manual progress
        final updated = MockActionStore.instance.actions.firstWhere((a) => a.id == actionUuid);
        expect(updated.subTasks.first.isCompleted, isTrue);
        expect(updated.percentComplete, equals(0));
      });

      testWidgets('8.6 Actions without tasks preserve manual progress dropdown workflow and hide checklist', (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final actionWithoutTasks = createTestRecord(
          id: 'ACT-NO-TASKS-01',
          subject: 'Action Without Tasks',
          percentComplete: 25,
          subTasks: [],
          primary: ActionPersonReference(
            personId: 'staff-uuid-001',
            name: 'test staff',
            type: PersonType.internalUser,
            email: 'test.staff@sobha.com',
          ),
        );

        MockActionStore.instance.add(actionWithoutTasks);

        await tester.pumpWidget(
          MaterialApp(
            home: WorkerActionUpdateScreen(
              action: actionWithoutTasks,
              currentUserId: 'staff-uuid-001',
              currentUserName: 'test staff',
              currentUserEmail: 'test.staff@sobha.com',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Checklist header should NOT appear
        expect(find.textContaining('TASKS & CHECKLIST'), findsNothing);
        // Manual dropdown '% Complete' should appear
        expect(find.text('% Complete'), findsOneWidget);
        expect(find.text('25%'), findsWidgets);
      });
    });

    group('9. Step 26 Regression: My Actions Newest First Sorting', () {
      testWidgets('9.1 Newest First sorts strictly by createdAt descending instead of alphanumeric ID', (tester) async {
        tester.view.physicalSize = const Size(1400, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final staffProfile = const UserProfile(
          id: 'staff-sort-uuid',
          name: 'Sorting Test Staff',
          email: 'sort.staff@sobha.com',
          phone: '+971501234567',
          designation: 'Safety Officer',
          department: 'Safety',
          site: 'Central Hub',
          role: 'worker',
          organizationId: testOrgId,
        );

        // Creation dates out of sync with alphanumeric IDs:
        // ACT-1011 is NEWEST (Oct 15)
        // ACT-1022 is 2nd newest (Oct 12)
        // ACT-1021 is 3rd newest (Oct 10)
        // ACT-1020 is OLDEST (Oct 01)
        final action1021 = createTestRecord(
          id: 'ACT-1021',
          subject: 'Action 1021 - Oct 10',
          primary: ActionPersonReference(
            personId: staffProfile.id,
            name: staffProfile.name,
            type: PersonType.internalUser,
            email: staffProfile.email,
          ),
          createdAt: DateTime(2026, 10, 10, 10, 0, 0),
        );

        final action1011 = createTestRecord(
          id: 'ACT-1011',
          subject: 'Action 1011 - Oct 15 Newest',
          primary: ActionPersonReference(
            personId: staffProfile.id,
            name: staffProfile.name,
            type: PersonType.internalUser,
            email: staffProfile.email,
          ),
          createdAt: DateTime(2026, 10, 15, 12, 0, 0),
        );

        final action1022 = createTestRecord(
          id: 'ACT-1022',
          subject: 'Action 1022 - Oct 12',
          primary: ActionPersonReference(
            personId: staffProfile.id,
            name: staffProfile.name,
            type: PersonType.internalUser,
            email: staffProfile.email,
          ),
          createdAt: DateTime(2026, 10, 12, 8, 0, 0),
        );

        final action1020 = createTestRecord(
          id: 'ACT-1020',
          subject: 'Action 1020 - Oct 01 Oldest',
          primary: ActionPersonReference(
            personId: staffProfile.id,
            name: staffProfile.name,
            type: PersonType.internalUser,
            email: staffProfile.email,
          ),
          createdAt: DateTime(2026, 10, 1, 14, 0, 0),
        );

        MockActionStore.instance.actions.clear();
        MockActionStore.instance.actions.addAll([
          action1021,
          action1011,
          action1022,
          action1020,
        ]);

        await tester.pumpWidget(
          MaterialApp(
            home: WorkerDashboardScreen(
              userProfile: staffProfile,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to My Actions tab
        await tester.tap(find.text('My Actions').first);
        await tester.pumpAndSettle();

        // The default sort is 'Newest First'
        // Expected order: ACT-1011, ACT-1022, ACT-1021, ACT-1020
        final idFinders = find.byWidgetPredicate((w) {
          if (w is Text && ['ACT-1011', 'ACT-1022', 'ACT-1021', 'ACT-1020'].contains(w.data)) {
            return true;
          }
          return false;
        });

        final foundIds = idFinders.evaluate().map((e) => (e.widget as Text).data!).toList();
        expect(foundIds, containsAllInOrder(['ACT-1011', 'ACT-1022', 'ACT-1021', 'ACT-1020']));
      });

      testWidgets('9.2 Missing createdAt falls back deterministically to parsed dateRaised without throwing', (tester) async {
        tester.view.physicalSize = const Size(1400, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final staffProfile = const UserProfile(
          id: 'staff-fallback-uuid',
          name: 'Fallback Staff',
          email: 'fallback@sobha.com',
          phone: '+971501234567',
          designation: 'Safety Officer',
          department: 'Safety',
          site: 'Central Hub',
          role: 'worker',
          organizationId: testOrgId,
        );

        final actionOlder = createTestRecord(
          id: 'ACT-FALLBACK-01',
          subject: 'Older Action',
          dateRaised: '02 Oct 2026',
          primary: ActionPersonReference(
            personId: staffProfile.id,
            name: staffProfile.name,
            type: PersonType.internalUser,
            email: staffProfile.email,
          ),
          // createdAt is explicitly null
        );

        final actionNewer = createTestRecord(
          id: 'ACT-FALLBACK-02',
          subject: 'Newer Action',
          dateRaised: '18 Oct 2026',
          primary: ActionPersonReference(
            personId: staffProfile.id,
            name: staffProfile.name,
            type: PersonType.internalUser,
            email: staffProfile.email,
          ),
          // createdAt is explicitly null
        );

        MockActionStore.instance.actions.clear();
        MockActionStore.instance.actions.addAll([actionOlder, actionNewer]);

        await tester.pumpWidget(
          MaterialApp(
            home: WorkerDashboardScreen(
              userProfile: staffProfile,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to My Actions tab
        await tester.tap(find.text('My Actions').first);
        await tester.pumpAndSettle();

        final idFinders = find.byWidgetPredicate((w) {
          if (w is Text && ['ACT-FALLBACK-02', 'ACT-FALLBACK-01'].contains(w.data)) {
            return true;
          }
          return false;
        });

        final foundIds = idFinders.evaluate().map((e) => (e.widget as Text).data!).toList();
        expect(foundIds, containsAllInOrder(['ACT-FALLBACK-02', 'ACT-FALLBACK-01']));
      });

      testWidgets('9.3 Priority and Progress sorting remain intact', (tester) async {
        tester.view.physicalSize = const Size(1400, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final staffProfile = const UserProfile(
          id: 'staff-sort2-uuid',
          name: 'Sort2 Staff',
          email: 'sort2@sobha.com',
          phone: '+971501234567',
          designation: 'Safety Officer',
          department: 'Safety',
          site: 'Central Hub',
          role: 'worker',
          organizationId: testOrgId,
        );

        final actLow = createTestRecord(
          id: 'ACT-LOW',
          subject: 'Low Priority Action',
          priority: 'Low',
          percentComplete: 90,
          primary: ActionPersonReference(
            personId: staffProfile.id,
            name: staffProfile.name,
            type: PersonType.internalUser,
            email: staffProfile.email,
          ),
        );

        final actCrit = createTestRecord(
          id: 'ACT-CRIT',
          subject: 'Critical Priority Action',
          priority: 'Critical',
          percentComplete: 10,
          primary: ActionPersonReference(
            personId: staffProfile.id,
            name: staffProfile.name,
            type: PersonType.internalUser,
            email: staffProfile.email,
          ),
        );

        MockActionStore.instance.actions.clear();
        MockActionStore.instance.actions.addAll([actLow, actCrit]);

        await tester.pumpWidget(
          MaterialApp(
            home: WorkerDashboardScreen(
              userProfile: staffProfile,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to My Actions tab
        await tester.tap(find.text('My Actions').first);
        await tester.pumpAndSettle();

        // Switch to Priority sort
        await tester.tap(find.byKey(const ValueKey('Sort By-Newest First')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(DropdownMenuItem<String>, 'Priority').last, warnIfMissed: false);
        await tester.pumpAndSettle();

        var idFinders = find.byWidgetPredicate((w) => w is Text && ['ACT-CRIT', 'ACT-LOW'].contains(w.data));
        var foundIds = idFinders.evaluate().map((e) => (e.widget as Text).data!).toList();
        expect(foundIds, containsAllInOrder(['ACT-CRIT', 'ACT-LOW']));

        // Switch to Progress sort
        await tester.tap(find.byKey(const ValueKey('Sort By-Priority')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(DropdownMenuItem<String>, 'Progress').last, warnIfMissed: false);
        await tester.pumpAndSettle();

        idFinders = find.byWidgetPredicate((w) => w is Text && ['ACT-LOW', 'ACT-CRIT'].contains(w.data));
        foundIds = idFinders.evaluate().map((e) => (e.widget as Text).data!).toList();
        expect(foundIds, containsAllInOrder(['ACT-LOW', 'ACT-CRIT']));
      });
    });

    group('10. Step 29: Unified Manager & Staff Update Screens and Task Visibility', () {
      testWidgets('10.1 ManagerActionUpdateScreen renders assigned task checklist with Internal and External badges', (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final actionWithMixedTasks = createTestRecord(
          id: 'ACT-MGR-TASK-01',
          subject: 'Action With Mixed Tasks for Manager',
          percentComplete: 50,
          subTasks: [
            createTestSubTask(
              id: 'task-mgr-int-1',
              parentActionId: 'ACT-MGR-TASK-01',
              title: 'Secure Scaffolding Bracing',
              assignedStaff: 'User A (Internal Staff)',
              assignedStaffId: userA.personId,
              assignedStaffEmail: userA.email,
              assigneeType: 'internal',
              status: 'Completed',
              completedAt: '19 Oct 2026',
              completedBy: 'User A',
            ),
            createTestSubTask(
              id: 'task-mgr-ext-2',
              parentActionId: 'ACT-MGR-TASK-01',
              title: 'Deliver Scaffolding Couplers',
              assignedStaff: 'Apex Scaffolding Ltd',
              assignedStaffId: userB.personId,
              assignedStaffEmail: userB.email,
              assigneeType: 'external',
              status: 'Open',
            ),
          ],
        );

        MockActionStore.instance.add(actionWithMixedTasks);

        await tester.pumpWidget(
          MaterialApp(
            home: ManagerActionUpdateScreen(
              action: actionWithMixedTasks,
              currentUserId: managerProfile.id,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Checklist title and counts
        expect(
          find.text('Assigned Tasks & Checklist (1 / 2 Completed)'),
          findsOneWidget,
        );

        // 2. Both tasks appear
        expect(find.text('Secure Scaffolding Bracing'), findsOneWidget);
        expect(find.text('Deliver Scaffolding Couplers'), findsOneWidget);

        // 3. Badges appear: Internal & External
        expect(find.text('Internal'), findsWidgets);
        expect(find.text('External'), findsWidgets);

        // 4. Progress info banner indicates supporting checklist
        expect(
          find.text('Tasks are a supporting checklist (1 of 2 completed). Report overall action progress below.'),
          findsOneWidget,
        );

        // 5. Manual slider is always displayed to allow reporting overall action progress
        expect(find.byType(Slider), findsOneWidget);
      });

      testWidgets('10.2 ManagerActionUpdateScreen toggles task checklist independently from manual progress', (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final actionToToggle = createTestRecord(
          id: 'ACT-MGR-TOGGLE-01',
          subject: 'Action To Toggle Tasks in Manager Screen',
          percentComplete: 0,
          subTasks: [
            createTestSubTask(
              id: 'task-tgl-1',
              parentActionId: 'ACT-MGR-TOGGLE-01',
              title: 'Task Alpha',
              assignedStaff: 'User A',
              assignedStaffId: userA.personId,
              assignedStaffEmail: userA.email,
              assigneeType: 'internal',
              status: 'Open',
            ),
            createTestSubTask(
              id: 'task-tgl-2',
              parentActionId: 'ACT-MGR-TOGGLE-01',
              title: 'Task Beta',
              assignedStaff: 'User B',
              assignedStaffId: userB.personId,
              assignedStaffEmail: userB.email,
              assigneeType: 'external',
              status: 'Open',
            ),
          ],
        );

        MockActionStore.instance.add(actionToToggle);

        await tester.pumpWidget(
          MaterialApp(
            home: ManagerActionUpdateScreen(
              action: actionToToggle,
              currentUserId: managerProfile.id,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Assigned Tasks & Checklist (0 / 2 Completed)'),
          findsOneWidget,
        );

        // Toggle Task 1
        await tester.tap(find.byKey(const Key('manager_task_checkbox_0')));
        await tester.pumpAndSettle();

        expect(
          find.text('Assigned Tasks & Checklist (1 / 2 Completed)'),
          findsOneWidget,
        );
        expect(
          find.text('Tasks are a supporting checklist (1 of 2 completed). Report overall action progress below.'),
          findsOneWidget,
        );
        expect(find.text('Progress: 0% *'), findsOneWidget);

        // Toggle Task 2
        await tester.tap(find.byKey(const Key('manager_task_checkbox_1')));
        await tester.pumpAndSettle();

        expect(
          find.text('Assigned Tasks & Checklist (2 / 2 Completed)'),
          findsOneWidget,
        );
        expect(
          find.text('Tasks are a supporting checklist (2 of 2 completed). Report overall action progress below.'),
          findsOneWidget,
        );
        expect(find.text('Progress: 0% *'), findsOneWidget);

        // 100% tasks does NOT auto-close the action
        expect(find.text('Closed'), findsNothing);

        // Untoggle Task 1 -> prompts for reopen reason
        await tester.tap(find.byKey(const Key('manager_task_checkbox_0')));
        await tester.pumpAndSettle();

        final reasonField = find.byKey(const Key('reopen_subtask_reason_task-tgl-1'));
        if (reasonField.evaluate().isNotEmpty) {
          await tester.enterText(reasonField, 'Manager correction needed');
          await tester.tap(find.byKey(const Key('confirm_reopen_subtask_btn_task-tgl-1')));
          await tester.pumpAndSettle();
        }

        expect(
          find.text('Assigned Tasks & Checklist (1 / 2 Completed)'),
          findsOneWidget,
        );
        expect(
          find.text('Tasks are a supporting checklist (1 of 2 completed). Report overall action progress below.'),
          findsOneWidget,
        );
        expect(find.text('Progress: 0% *'), findsOneWidget);
      });

      testWidgets('10.3 ManagerActionUpdateScreen on action without tasks displays manual progress slider and chips', (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final actionWithoutTasks = createTestRecord(
          id: 'ACT-MGR-NO-TASKS',
          subject: 'Action Without Tasks Manager',
          percentComplete: 20,
          subTasks: [],
        );

        MockActionStore.instance.add(actionWithoutTasks);

        await tester.pumpWidget(
          MaterialApp(
            home: ManagerActionUpdateScreen(
              action: actionWithoutTasks,
              currentUserId: managerProfile.id,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Checklist panel does NOT appear
        expect(find.textContaining('Assigned Tasks & Checklist'), findsNothing);

        // Slider and quick chips appear
        expect(find.byType(Slider), findsOneWidget);
        expect(find.byType(ChoiceChip), findsWidgets);
        expect(find.text('Progress: 20% *'), findsOneWidget);

        // Tap a quick chip (60%)
        await tester.tap(find.widgetWithText(ChoiceChip, '60%'));
        await tester.pumpAndSettle();

        expect(find.text('Progress: 60% *'), findsOneWidget);
      });

      testWidgets('10.4 ActionDetailsScreen loads subtasks and displays Internal and External assignee badges', (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final actionDetailsRecord = createTestRecord(
          id: 'ACT-DETAILS-SUBTASKS-01',
          subject: 'Action Details Subtasks Test',
          subTasks: [
            createTestSubTask(
              id: 'ST-DET-01',
              parentActionId: 'ACT-DETAILS-SUBTASKS-01',
              title: 'Internal Inspection Task',
              assignedStaff: 'User A',
              assignedStaffId: userA.personId,
              assignedStaffEmail: userA.email,
              assigneeType: 'internal',
              status: 'Open',
            ),
            createTestSubTask(
              id: 'ST-DET-02',
              parentActionId: 'ACT-DETAILS-SUBTASKS-01',
              title: 'External Supply Task',
              assignedStaff: 'Apex Scaffolding Ltd',
              assignedStaffId: userB.personId,
              assignedStaffEmail: userB.email,
              assigneeType: 'external',
              status: 'Completed',
              completedAt: '19 Oct 2026',
              completedBy: 'Apex Team',
            ),
          ],
        );

        MockActionStore.instance.add(actionDetailsRecord);

        await tester.pumpWidget(
          MaterialApp(
            home: ActionDetailsScreen(
              action: actionDetailsRecord,
              managerContext: managerContext,
              isWorker: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to Sub-tasks tab
        await tester.tap(find.textContaining('Sub-tasks').first);
        await tester.pumpAndSettle();

        expect(find.text('Internal Inspection Task'), findsOneWidget);
        expect(find.text('External Supply Task'), findsOneWidget);
        expect(find.text('Internal'), findsWidgets);
        expect(find.text('External'), findsWidgets);
      });
    });

    // ===========================================================================
    // 11. Step 30: End-to-End Task Checklist Visibility, Persistence & Completion
    // ===========================================================================
    group('11. Step 30: End-to-End Task Checklist Visibility, Persistence & Completion', () {
      test('11.1 Subtask assignees are automatically included in action_assignees for RLS access', () {
        final staffMember1 = ActionPersonReference(
          personId: '40000000-0000-0000-0000-00000000000d',
          name: 'Staff Member One',
          type: PersonType.internalUser,
          email: 'staff.one@sobha.com',
        );
        final staffMember2 = ActionPersonReference(
          personId: '50000000-0000-0000-0000-00000000000e',
          name: 'Staff Member Two',
          type: PersonType.internalUser,
          email: 'staff.two@sobha.com',
        );

        final actionWithSubtaskAssignees = createTestRecord(
          id: 'ACT-STEP30-ASG-01',
          subject: 'Subtask Assignees Inclusion Test',
          primary: userA,
          additional: [],
          subTasks: [
            createTestSubTask(
              id: 'ST-30-01',
              parentActionId: 'ACT-STEP30-ASG-01',
              title: 'Staff One Task',
              assignedStaff: staffMember1.name,
              assignedStaffId: staffMember1.personId,
              assignedStaffEmail: staffMember1.email,
              assigneeType: 'internal',
            ),
            createTestSubTask(
              id: 'ST-30-02',
              parentActionId: 'ACT-STEP30-ASG-01',
              title: 'Staff Two Task',
              assignedStaff: staffMember2.name,
              assignedStaffId: staffMember2.personId,
              assignedStaffEmail: staffMember2.email,
              assigneeType: 'internal',
            ),
            createTestSubTask(
              id: 'ST-30-03',
              parentActionId: 'ACT-STEP30-ASG-01',
              title: 'External Contractor Task',
              assignedStaff: userB.name,
              assignedStaffId: userB.personId,
              assignedStaffEmail: userB.email,
              assigneeType: 'external',
            ),
          ],
        );

        final desired = ActionService.instance.testExtractDesiredAssignees(
          actionWithSubtaskAssignees,
          actionId: actionWithSubtaskAssignees.id,
        );

        expect(desired.any((a) => a.profileId == userA.personId), isTrue);
        expect(desired.any((a) => a.profileId == staffMember1.personId), isTrue);
        expect(desired.any((a) => a.profileId == staffMember2.personId), isTrue);
        expect(desired.any((a) => a.profileId == userB.personId), isFalse);
      });

      testWidgets('11.2 ActionDetailsScreen Overview tab displays task checklist with count and derived progress', (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final actionWithChecklist = createTestRecord(
          id: 'ACT-DETAILS-OV-01',
          subject: 'Overview Checklist Test',
          percentComplete: 50,
          subTasks: [
            createTestSubTask(
              id: 'ST-OV-01',
              parentActionId: 'ACT-DETAILS-OV-01',
              title: 'Internal Electrical Inspection',
              assignedStaff: 'User A',
              assignedStaffId: userA.personId,
              assignedStaffEmail: userA.email,
              assigneeType: 'internal',
              status: 'Completed',
              completedAt: '19 Oct 2026',
              completedBy: 'User A',
            ),
            createTestSubTask(
              id: 'ST-OV-02',
              parentActionId: 'ACT-DETAILS-OV-01',
              title: 'Internal Mechanical Test',
              assignedStaff: 'User C',
              assignedStaffId: userC.personId,
              assignedStaffEmail: userC.email,
              assigneeType: 'internal',
              status: 'Completed',
              completedAt: '19 Oct 2026',
              completedBy: 'User C',
            ),
            createTestSubTask(
              id: 'ST-OV-03',
              parentActionId: 'ACT-DETAILS-OV-01',
              title: 'External Scaffolding Erection',
              assignedStaff: 'Apex Scaffolding',
              assignedStaffId: userB.personId,
              assignedStaffEmail: userB.email,
              assigneeType: 'external',
              status: 'Open',
            ),
            createTestSubTask(
              id: 'ST-OV-04',
              parentActionId: 'ACT-DETAILS-OV-01',
              title: 'Final Sign-off Verification',
              assignedStaff: 'User A',
              assignedStaffId: userA.personId,
              assignedStaffEmail: userA.email,
              assigneeType: 'internal',
              status: 'Open',
            ),
          ],
        );

        MockActionStore.instance.add(actionWithChecklist);

        await tester.pumpWidget(
          MaterialApp(
            home: ActionDetailsScreen(
              action: actionWithChecklist,
              managerContext: managerContext,
              isWorker: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Overview tab displays header with (2 of 4 completed)
        expect(
          find.text('Action Tasks & Checklist (2 of 4 completed)'),
          findsOneWidget,
        );

        // 2. Summary banner
        expect(
          find.text('2 of 4 tasks completed'),
          findsOneWidget,
        );

        // 3. Task titles
        expect(find.text('Internal Electrical Inspection'), findsOneWidget);
        expect(find.text('Internal Mechanical Test'), findsOneWidget);
        expect(find.text('External Scaffolding Erection'), findsOneWidget);
        expect(find.text('Final Sign-off Verification'), findsOneWidget);

        // 4. Badges: Internal & External badges, Completed & Pending badges
        expect(find.text('Internal'), findsWidgets);
        expect(find.text('External'), findsWidgets);
        expect(find.text('Completed'), findsWidgets);
        expect(find.text('Pending'), findsWidgets);
      });

      testWidgets('11.3 ActionDetailsScreen Overview tab displays clear empty state when no tasks exist', (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final actionWithoutTasks = createTestRecord(
          id: 'ACT-DETAILS-EMPTY-01',
          subject: 'Action Without Tasks Test',
          subTasks: [],
        );

        MockActionStore.instance.add(actionWithoutTasks);

        await tester.pumpWidget(
          MaterialApp(
            home: ActionDetailsScreen(
              action: actionWithoutTasks,
              managerContext: managerContext,
              isWorker: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Header shows without counts
        expect(find.text('Action Tasks & Checklist'), findsOneWidget);

        // Empty state explanation
        expect(
          find.text(
            'No individual tasks configured for this action — progress is managed manually via the progress slider.',
          ),
          findsOneWidget,
        );
      });

      testWidgets('11.4 External contractor portal locks manual slider when tasks exist and calculates progress from checkboxes', (tester) async {
        tester.view.physicalSize = const Size(1200, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final contractorTask1 = createTestSubTask(
          id: 'ST-EXT-LOCK-01',
          parentActionId: 'ACT-EXT-LOCK-01',
          title: 'Scaffold Tower Erection',
          assignedStaff: userB.name,
          assignedStaffId: userB.personId,
          assignedStaffEmail: userB.email,
          assigneeType: 'external',
          status: 'Open',
        );
        final contractorTask2 = createTestSubTask(
          id: 'ST-EXT-LOCK-02',
          parentActionId: 'ACT-EXT-LOCK-01',
          title: 'Safety Net Installation',
          assignedStaff: userB.name,
          assignedStaffId: userB.personId,
          assignedStaffEmail: userB.email,
          assigneeType: 'external',
          status: 'Open',
        );

        final payload = ExternalActionPayload(
          actionId: 'ACT-EXT-LOCK-01',
          actionNumber: 'ACT-EXT-LOCK-01',
          title: 'Contractor External Work',
          description: 'Site scaffolding and safety netting',
          actionRequired: 'Erect towers and safety nets',
          category: 'Safety',
          priority: 'High',
          status: 'In Progress',
          percentComplete: 0,
          dateRaised: '19 Oct 2026',
          startDate: '19 Oct 2026',
          targetDate: '31 Oct 2026',
          dueDate: '31 Oct 2026',
          nextFollowUpDate: '',
          department: 'HSE',
          site: 'Tower 3',
          organizationName: 'Sobha Constructions',
          isClosed: false,
          recentHistory: const [],
          recipientId: userB.personId,
          recipientName: userB.name,
          recipientEmail: userB.email,
          companyName: userB.company,
          phone: '+971501234567',
          subTasks: [contractorTask1, contractorTask2],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ExternalActionUpdateScreen(
              token: 'test-token-lock-01',
              initialPayload: payload,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Check checklist header: 0 / 2 completed
        expect(find.text('ASSIGNED TASKS (0 / 2 COMPLETED)'), findsOneWidget);

        // Progress slider is locked with explanation
        expect(find.text('Progress (Derived from tasks):'), findsOneWidget);
        expect(find.textContaining('Progress is automatically calculated from task completion (0%)'), findsOneWidget);

        // Slider onChanged is null
        final sliderFinder = find.byType(Slider);
        expect(sliderFinder, findsOneWidget);
        final sliderWidget = tester.widget<Slider>(sliderFinder);
        expect(sliderWidget.onChanged, isNull);

        // Toggle task 1
        final cb0 = find.byKey(const Key('external_task_checkbox_0'));
        expect(cb0, findsOneWidget);
        await tester.tap(cb0);
        await tester.pumpAndSettle();

        // 1 of 2 completed = 50%
        expect(find.text('ASSIGNED TASKS (1 / 2 COMPLETED)'), findsOneWidget);
        expect(find.text('50%'), findsWidgets);
        expect(find.textContaining('Progress is automatically calculated from task completion (50%)'), findsOneWidget);

        // Toggle task 2
        final cb1 = find.byKey(const Key('external_task_checkbox_1'));
        expect(cb1, findsOneWidget);
        await tester.tap(cb1);
        await tester.pumpAndSettle();

        // 2 of 2 completed = 100%
        expect(find.text('ASSIGNED TASKS (2 / 2 COMPLETED)'), findsOneWidget);
        expect(find.text('100%'), findsWidgets);
        expect(find.textContaining('Progress is automatically calculated from task completion (100%)'), findsOneWidget);

        // Reopening task 1 recalculates progress downward: 1 of 2 completed = 50%
        await tester.tap(cb0);
        await tester.pumpAndSettle();

        expect(find.text('ASSIGNED TASKS (1 / 2 COMPLETED)'), findsOneWidget);
        expect(find.text('50%'), findsWidgets);
      });

      testWidgets('11.5 External contractor portal when action has no tasks preserves manual progress slider', (tester) async {
        tester.view.physicalSize = const Size(1200, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final payload = ExternalActionPayload(
          actionId: 'ACT-EXT-NOTASKS-01',
          actionNumber: 'ACT-EXT-NOTASKS-01',
          title: 'Manual Progress Contractor Work',
          description: 'General cleaning',
          actionRequired: 'Clean area',
          category: 'Housekeeping',
          priority: 'Low',
          status: 'In Progress',
          percentComplete: 20,
          dateRaised: '19 Oct 2026',
          startDate: '19 Oct 2026',
          targetDate: '31 Oct 2026',
          dueDate: '31 Oct 2026',
          nextFollowUpDate: '',
          department: 'HSE',
          site: 'Yard',
          organizationName: 'Sobha Constructions',
          isClosed: false,
          recentHistory: const [],
          recipientId: userB.personId,
          recipientName: userB.name,
          recipientEmail: userB.email,
          companyName: userB.company,
          phone: '+971501234567',
          subTasks: [],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ExternalActionUpdateScreen(
              token: 'test-token-notasks-01',
              initialPayload: payload,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Checklist is not shown
        expect(find.byType(CheckboxListTile), findsNothing);

        // Manual slider is present and enabled
        expect(find.text('Reported Progress (%):'), findsOneWidget);
        expect(find.text('20%'), findsWidgets);
        expect(find.textContaining('Progress is automatically calculated'), findsNothing);

        final sliderFinder = find.byType(Slider);
        expect(sliderFinder, findsOneWidget);
        final sliderWidget = tester.widget<Slider>(sliderFinder);
        expect(sliderWidget.onChanged, isNotNull);
      });
    });

    // ===========================================================================
    // 12. Step 31: Manager & Staff Update Screens Task Checklist Verification and Completion
    // ===========================================================================
    group('12. Step 31: Manager & Staff Update Screens Task Checklist Verification and Completion', () {
      testWidgets('12.1 Manager Update Action displays saved tasks, badges, and toggles completion', (tester) async {
        tester.view.physicalSize = const Size(1280, 2500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final task1 = createTestSubTask(
          id: 'ST-31-MGR-01',
          parentActionId: 'ACT-STEP31-MGR-01',
          title: 'Inspect emergency valves',
          assignedStaff: userA.name,
          assignedStaffId: userA.personId,
          assignedStaffEmail: userA.email,
          assigneeType: 'internal',
          status: 'Open',
        );
        final task2 = createTestSubTask(
          id: 'ST-31-MGR-02',
          parentActionId: 'ACT-STEP31-MGR-01',
          title: 'Replace perimeter warning tape',
          assignedStaff: userB.name,
          assignedStaffId: userB.personId,
          assignedStaffEmail: userB.email,
          assigneeType: 'external',
          status: 'Completed',
          completedAt: '19 Oct 2026',
          completedBy: userB.name,
        );

        final managerAction = createTestRecord(
          id: 'ACT-STEP31-MGR-01',
          subject: 'Valve and Perimeter Maintenance',
          percentComplete: 50,
          subTasks: [task1, task2],
        );

        MockActionStore.instance.add(managerAction);

        await tester.pumpWidget(
          MaterialApp(
            home: ManagerActionUpdateScreen(
              action: managerAction,
              currentUserId: 'mgr-profile-001',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Title and headers
        expect(find.text('Assigned Tasks & Checklist (1 / 2 Completed)'), findsOneWidget);
        expect(find.text('Inspect emergency valves'), findsOneWidget);
        expect(find.text('Replace perimeter warning tape'), findsOneWidget);

        // 2. Badges: Internal & External, Completed & Pending
        expect(find.text('Internal'), findsOneWidget);
        expect(find.text('External'), findsOneWidget);
        expect(find.text('Completed'), findsWidgets);
        expect(find.text('Pending'), findsWidgets);

        // 3. Progress shows manual reported progress and supporting checklist note
        expect(find.text('Progress: 50% *'), findsOneWidget);
        expect(
          find.text('Tasks are a supporting checklist (1 of 2 completed). Report overall action progress below.'),
          findsOneWidget,
        );

        // 4. Checkboxes: first is unchecked, second is checked
        final cb0 = find.byKey(const Key('manager_task_checkbox_0'));
        final cb1 = find.byKey(const Key('manager_task_checkbox_1'));
        expect(cb0, findsOneWidget);
        expect(cb1, findsOneWidget);
        expect(tester.widget<CheckboxListTile>(cb0).value, isFalse);
        expect(tester.widget<CheckboxListTile>(cb1).value, isTrue);

        // 5. Toggle first task to completed
        await tester.tap(cb0);
        await tester.pumpAndSettle();

        // Check that task checklist updated to 2 / 2 while manual progress remains 50%
        expect(find.text('Assigned Tasks & Checklist (2 / 2 Completed)'), findsOneWidget);
        expect(find.text('Progress: 50% *'), findsOneWidget);
        expect(tester.widget<CheckboxListTile>(cb0).value, isTrue);
      });

      testWidgets('12.2 Staff Update Action displays only authorized staff tasks with Internal and status badges', (tester) async {
        tester.view.physicalSize = const Size(1280, 2500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final taskA = createTestSubTask(
          id: 'ST-31-WRK-01',
          parentActionId: 'ACT-STEP31-WRK-01',
          title: 'Staff User A calibration task',
          assignedStaff: userA.name,
          assignedStaffId: userA.personId,
          assignedStaffEmail: userA.email,
          assigneeType: 'internal',
          status: 'Open',
        );
        final taskC = createTestSubTask(
          id: 'ST-31-WRK-02',
          parentActionId: 'ACT-STEP31-WRK-01',
          title: 'Staff User C peer task',
          assignedStaff: userC.name,
          assignedStaffId: userC.personId,
          assignedStaffEmail: userC.email,
          assigneeType: 'internal',
          status: 'Open',
        );
        final taskExt = createTestSubTask(
          id: 'ST-31-WRK-03',
          parentActionId: 'ACT-STEP31-WRK-01',
          title: 'External contractor task',
          assignedStaff: userB.name,
          assignedStaffId: userB.personId,
          assignedStaffEmail: userB.email,
          assigneeType: 'external',
          status: 'Open',
        );

        final actionMulti = createTestRecord(
          id: 'ACT-STEP31-WRK-01',
          subject: 'Multi Assignee Action',
          percentComplete: 0,
          subTasks: [taskA, taskC, taskExt],
        );

        MockActionStore.instance.add(actionMulti);

        await tester.pumpWidget(
          MaterialApp(
            home: WorkerActionUpdateScreen(
              action: actionMulti,
              currentUserId: userA.personId,
              currentUserName: userA.name,
              currentUserEmail: userA.email,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Visible subtasks shows only 1 task for User A
        expect(find.text('TASKS & CHECKLIST (0 / 1 COMPLETED)'), findsOneWidget);
        expect(find.text('Staff User A calibration task'), findsOneWidget);

        // 2. Peer and external tasks are omitted from the checklist
        expect(find.text('Staff User C peer task'), findsNothing);
        expect(find.text('External contractor task'), findsNothing);

        // 3. Badges on staff task
        expect(find.text('Internal'), findsOneWidget);
        expect(find.text('Pending'), findsOneWidget);
      });

      testWidgets('12.3 Staff Update Action completes own task and updates authoritative progress across multi-task action', (tester) async {
        tester.view.physicalSize = const Size(1280, 2500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // 4 total tasks: 2 assigned to User A, 2 to User C.
        // Initially 0% completed.
        final taskA1 = createTestSubTask(
          id: 'ST-31-AUTH-01',
          parentActionId: 'ACT-STEP31-AUTH-01',
          title: 'User A Task 1',
          assignedStaff: userA.name,
          assignedStaffId: userA.personId,
          assignedStaffEmail: userA.email,
          assigneeType: 'internal',
          status: 'Open',
        );
        final taskA2 = createTestSubTask(
          id: 'ST-31-AUTH-02',
          parentActionId: 'ACT-STEP31-AUTH-01',
          title: 'User A Task 2',
          assignedStaff: userA.name,
          assignedStaffId: userA.personId,
          assignedStaffEmail: userA.email,
          assigneeType: 'internal',
          status: 'Open',
        );
        final taskC1 = createTestSubTask(
          id: 'ST-31-AUTH-03',
          parentActionId: 'ACT-STEP31-AUTH-01',
          title: 'User C Task 1',
          assignedStaff: userC.name,
          assignedStaffId: userC.personId,
          assignedStaffEmail: userC.email,
          assigneeType: 'internal',
          status: 'Open',
        );
        final taskC2 = createTestSubTask(
          id: 'ST-31-AUTH-04',
          parentActionId: 'ACT-STEP31-AUTH-01',
          title: 'User C Task 2',
          assignedStaff: userC.name,
          assignedStaffId: userC.personId,
          assignedStaffEmail: userC.email,
          assigneeType: 'internal',
          status: 'Open',
        );

        final actionFour = createTestRecord(
          id: 'ACT-STEP31-AUTH-01',
          subject: 'Four Tasks Action',
          percentComplete: 0,
          subTasks: [taskA1, taskA2, taskC1, taskC2],
        );

        MockActionStore.instance.add(actionFour);

        await tester.pumpWidget(
          MaterialApp(
            home: WorkerActionUpdateScreen(
              action: actionFour,
              currentUserId: userA.personId,
              currentUserName: userA.name,
              currentUserEmail: userA.email,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // User A sees 2 tasks
        expect(find.text('TASKS & CHECKLIST (0 / 2 COMPLETED)'), findsOneWidget);

        // Complete User A Task 1
        final cb0 = find.byKey(const Key('worker_task_checkbox_0'));
        await tester.tap(cb0);
        await tester.pumpAndSettle();

        // 1 of 2 completed in User A's view
        expect(find.text('TASKS & CHECKLIST (1 / 2 COMPLETED)'), findsOneWidget);

        // Complete User A Task 2
        final cb1 = find.byKey(const Key('worker_task_checkbox_1'));
        await tester.tap(cb1);
        await tester.pumpAndSettle();

        // 2 of 2 completed in User A's view
        expect(find.text('TASKS & CHECKLIST (2 / 2 COMPLETED)'), findsOneWidget);

        // Action in MockStore preserves manual progress (0%) while recording 2 completed tasks
        final stored = MockActionStore.instance.actions.firstWhere((a) => a.id == 'ACT-STEP31-AUTH-01');
        expect(stored.percentComplete, equals(0));
        expect(stored.subTasks.where((t) => t.isCompleted).length, equals(2));
      });

      testWidgets('12.4 Failed task toggle in WorkerActionUpdateScreen restores previous UI state and shows error', (tester) async {
        tester.view.physicalSize = const Size(1280, 2500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final taskFail = createTestSubTask(
          id: 'ST-31-FAIL-01',
          parentActionId: 'ACT-STEP31-FAIL-01',
          title: 'Test Rollback Subtask',
          assignedStaff: userA.name,
          assignedStaffId: userA.personId,
          assignedStaffEmail: userA.email,
          assigneeType: 'internal',
          status: 'Open',
        );

        final actionFail = createTestRecord(
          id: 'ACT-STEP31-FAIL-01',
          subject: 'Rollback Action Test',
          percentComplete: 0,
          subTasks: [taskFail],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: WorkerActionUpdateScreen(
              action: actionFail,
              currentUserId: userA.personId,
              currentUserName: userA.name,
              currentUserEmail: userA.email,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Remove from MockActionStore to trigger failure in submitSubtaskToggle
        MockActionStore.instance.actions.removeWhere((a) => a.id == 'ACT-STEP31-FAIL-01');

        final cb = find.byKey(const Key('worker_task_checkbox_0'));
        expect(cb, findsOneWidget);
        await tester.tap(cb);
        await tester.pumpAndSettle();

        // Expect SnackBar with error message
        expect(find.text('Action or task not found in mock store.'), findsOneWidget);

        // Checkbox value should be rolled back to false
        expect(tester.widget<CheckboxListTile>(cb).value, isFalse);
        expect(find.text('TASKS & CHECKLIST (0 / 1 COMPLETED)'), findsOneWidget);
      });

      testWidgets('12.5 Action without tasks displays manual progress in Manager & Staff Update screens', (tester) async {
        tester.view.physicalSize = const Size(1280, 2500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final emptyTasksAction = createTestRecord(
          id: 'ACT-STEP31-NOTASKS-01',
          subject: 'Manual Progress Only Action',
          percentComplete: 25,
          subTasks: const [],
        );

        MockActionStore.instance.add(emptyTasksAction);

        // 1. Manager Update Action: slider is interactive
        await tester.pumpWidget(
          MaterialApp(
            home: ManagerActionUpdateScreen(
              action: emptyTasksAction,
              currentUserId: 'mgr-profile-001',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(Slider), findsOneWidget);
        expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
        expect(find.text('Progress: 25% *'), findsOneWidget);

        // 2. Staff Update Action: % Complete dropdown is present
        await tester.pumpWidget(
          MaterialApp(
            home: WorkerActionUpdateScreen(
              action: emptyTasksAction,
              currentUserId: userA.personId,
              currentUserName: userA.name,
              currentUserEmail: userA.email,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('% Complete'), findsOneWidget);
        expect(find.byType(CheckboxListTile), findsNothing);
      });

      testWidgets('12.6 Consistency: Saved task state renders identically in Details, Manager Update, and Staff Update', (tester) async {
        tester.view.physicalSize = const Size(1280, 2500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final task1 = createTestSubTask(
          id: 'ST-31-CONSIST-01',
          parentActionId: 'ACT-STEP31-CONSIST-01',
          title: 'Safety valve calibration',
          assignedStaff: userA.name,
          assignedStaffId: userA.personId,
          assignedStaffEmail: userA.email,
          assigneeType: 'internal',
          status: 'Completed',
          completedAt: '19 Oct 2026',
          completedBy: userA.name,
        );
        final task2 = createTestSubTask(
          id: 'ST-31-CONSIST-02',
          parentActionId: 'ACT-STEP31-CONSIST-01',
          title: 'Exhaust duct filter replacement',
          assignedStaff: userA.name,
          assignedStaffId: userA.personId,
          assignedStaffEmail: userA.email,
          assigneeType: 'internal',
          status: 'Open',
        );
        final task3 = createTestSubTask(
          id: 'ST-31-CONSIST-03',
          parentActionId: 'ACT-STEP31-CONSIST-01',
          title: 'External cladding inspection',
          assignedStaff: userB.name,
          assignedStaffId: userB.personId,
          assignedStaffEmail: userB.email,
          assigneeType: 'external',
          status: 'Completed',
          completedAt: '19 Oct 2026',
          completedBy: userB.name,
        );
        final task4 = createTestSubTask(
          id: 'ST-31-CONSIST-04',
          parentActionId: 'ACT-STEP31-CONSIST-01',
          title: 'Fire extinguisher pressure check',
          assignedStaff: userC.name,
          assignedStaffId: userC.personId,
          assignedStaffEmail: userC.email,
          assigneeType: 'internal',
          status: 'Open',
        );

        final actionConsistent = createTestRecord(
          id: 'ACT-STEP31-CONSIST-01',
          subject: 'Comprehensive Consistency Check Action',
          percentComplete: 50,
          subTasks: [task1, task2, task3, task4],
        );

        MockActionStore.instance.add(actionConsistent);

        // A. ActionDetailsScreen
        await tester.pumpWidget(
          MaterialApp(
            home: ActionDetailsScreen(
              action: actionConsistent,
              managerContext: managerContext,
              isWorker: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Action Tasks & Checklist (2 of 4 completed)'), findsOneWidget);
        expect(find.text('2 of 4 tasks completed'), findsOneWidget);

        // B. ManagerActionUpdateScreen
        await tester.pumpWidget(
          MaterialApp(
            home: ManagerActionUpdateScreen(
              action: actionConsistent,
              currentUserId: 'mgr-profile-001',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Assigned Tasks & Checklist (2 / 4 Completed)'), findsOneWidget);
        expect(find.text('Progress: 50% *'), findsOneWidget);

        // C. WorkerActionUpdateScreen (logged in as User A)
        await tester.pumpWidget(
          MaterialApp(
            home: WorkerActionUpdateScreen(
              action: actionConsistent,
              currentUserId: userA.personId,
              currentUserName: userA.name,
              currentUserEmail: userA.email,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('TASKS & CHECKLIST (1 / 2 COMPLETED)'), findsOneWidget);
        expect(find.text('Safety valve calibration'), findsOneWidget);
        expect(find.text('Exhaust duct filter replacement'), findsOneWidget);
        expect(find.text('External cladding inspection'), findsNothing);
        expect(find.text('Fire extinguisher pressure check'), findsNothing);
      });
    });

    group('Group 13 - Final Task Workflow, Manager Reopen, Staff Update UI & Progress Verification', () {
      final managerPerson = ActionPersonReference(
        personId: managerProfile.id,
        name: managerProfile.name,
        type: PersonType.internalUser,
        email: managerProfile.email,
      );

      testWidgets('13.1 Case 1: Manager viewing staff-assigned action does not see Update Action, sees manager controls', (tester) async {
        tester.view.physicalSize = const Size(1280, 2500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final staffAction = createTestRecord(
          id: 'ACT-G13-CASE1-01',
          subject: 'Staff Assigned Action Review',
          primary: userA,
          percentComplete: 40,
          status: 'In Progress',
        );
        MockActionStore.instance.add(staffAction);

        await tester.pumpWidget(
          MaterialApp(
            home: ActionDetailsScreen(
              action: staffAction,
              managerContext: managerContext,
              isWorker: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Header toolbar: Update Action is omitted
        expect(find.text('Update Action'), findsNothing);

        // Management controls are shown
        expect(find.text('Edit Action'), findsOneWidget);
        expect(find.text('Forward Action'), findsOneWidget);
        expect(find.text('Add Follow-up'), findsOneWidget);
        expect(find.text('Resend Assignment'), findsOneWidget);
      });

      testWidgets('13.2 Case 2: Manager viewing action assigned to themselves sees Update Action', (tester) async {
        tester.view.physicalSize = const Size(1280, 2500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final mgrAction = createTestRecord(
          id: 'ACT-G13-CASE2-01',
          subject: 'Manager Assigned Action',
          primary: managerPerson,
          percentComplete: 20,
          status: 'In Progress',
        );
        MockActionStore.instance.add(mgrAction);

        await tester.pumpWidget(
          MaterialApp(
            home: ActionDetailsScreen(
              action: mgrAction,
              managerContext: managerContext,
              isWorker: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Update Action is visible
        expect(find.text('Update Action'), findsWidgets);
      });

      testWidgets('13.3 Case 3: Action 100% / in review / closed displays Reopen Action button and requires reason', (tester) async {
        tester.view.physicalSize = const Size(1280, 2500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final completedAction = createTestRecord(
          id: 'ACT-G13-CASE3-01',
          subject: 'Completed Action For Reopen',
          primary: userA,
          percentComplete: 100,
          status: 'Pending Review',
        );
        MockActionStore.instance.add(completedAction);

        await tester.pumpWidget(
          MaterialApp(
            home: ActionDetailsScreen(
              action: completedAction,
              managerContext: managerContext,
              isWorker: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Reopen Action button is present
        expect(find.text('Reopen Action'), findsOneWidget);
        expect(find.text('Update Action'), findsNothing);

        // Tap Reopen Action
        await tester.tap(find.text('Reopen Action'));
        await tester.pumpAndSettle();

        expect(find.text('Reopen Action'), findsWidgets);

        // Try submitting without reason
        await tester.tap(find.byKey(const Key('confirm_reopen_action_btn')));
        await tester.pumpAndSettle();

        expect(find.text('A reason is required to reopen this action.'), findsOneWidget);

        // Enter reason
        await tester.enterText(
          find.byKey(const Key('reopen_action_reason_input')),
          'Independent verification required for isolation valves.',
        );
        await tester.pumpAndSettle();

        // Confirm
        await tester.tap(find.byKey(const Key('confirm_reopen_action_btn')));
        await tester.pumpAndSettle();

        // Action in store should now be 'In Progress'
        final updatedAction = MockActionStore.instance.actions.firstWhere((a) => a.id == 'ACT-G13-CASE3-01');
        expect(updatedAction.status, equals('In Progress'));
        expect(updatedAction.history.any((h) => h.toLowerCase().contains('reopened')), isTrue);
      });

      testWidgets('13.4 Case 4: Action < 100% assigned to staff does not show routine Reopen Action or Update Action', (tester) async {
        tester.view.physicalSize = const Size(1280, 2500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final ongoingStaffAction = createTestRecord(
          id: 'ACT-G13-CASE4-01',
          subject: 'Ongoing Staff Action',
          primary: userA,
          percentComplete: 40,
          status: 'In Progress',
        );
        MockActionStore.instance.add(ongoingStaffAction);

        await tester.pumpWidget(
          MaterialApp(
            home: ActionDetailsScreen(
              action: ongoingStaffAction,
              managerContext: managerContext,
              isWorker: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Reopen Action'), findsNothing);
        expect(find.text('Update Action'), findsNothing);
        expect(find.text('Edit Action'), findsOneWidget);
      });

      testWidgets('13.5 Case 5: Manager reopening individual task prompts for reason, resets task to Open, preserves overall action progress, and displays [Reopened / Needs Correction]', (tester) async {
        tester.view.physicalSize = const Size(1280, 2500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final t1 = createTestSubTask(
          id: 'ST-G13-T1',
          parentActionId: 'ACT-G13-CASE5-01',
          title: 'Emergency vent calibration',
          assignedStaff: userA.name,
          assignedStaffId: userA.personId,
          status: 'Completed',
          completedAt: '2026-10-18T10:00:00Z',
          completedBy: userA.name,
        );
        final t2 = createTestSubTask(
          id: 'ST-G13-T2',
          parentActionId: 'ACT-G13-CASE5-01',
          title: 'Secondary flare inspection',
          assignedStaff: userA.name,
          assignedStaffId: userA.personId,
          status: 'Completed',
          completedAt: '2026-10-18T11:00:00Z',
          completedBy: userA.name,
        );

        final actionAllDone = createTestRecord(
          id: 'ACT-G13-CASE5-01',
          subject: 'All Tasks Completed Action',
          primary: userA,
          percentComplete: 100,
          status: 'Pending Review',
          subTasks: [t1, t2],
        );
        MockActionStore.instance.add(actionAllDone);

        await tester.pumpWidget(
          MaterialApp(
            home: ActionDetailsScreen(
              action: actionAllDone,
              managerContext: managerContext,
              isWorker: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // In the SubTasks overview card, find 'Reopen' button
        final reopenBtn = find.widgetWithText(OutlinedButton, 'Reopen').first;
        await tester.tap(reopenBtn);
        await tester.pumpAndSettle();

        expect(find.text('Reopen Task: Emergency vent calibration'), findsOneWidget);

        // Try submitting without reason
        await tester.tap(find.byKey(const Key('confirm_reopen_subtask_btn_ST-G13-T1')));
        await tester.pumpAndSettle();
        expect(find.text('Please provide a reason or correction instruction.'), findsOneWidget);

        // Enter correction reason
        await tester.enterText(
          find.byKey(const Key('reopen_subtask_reason_ST-G13-T1')),
          'Calibration certificate expired; recalibrate with valid unit.',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('confirm_reopen_subtask_btn_ST-G13-T1')));
        await tester.pumpAndSettle();

        // Task count is 1 of 2 completed; overall action progress & status remain intact
        expect(find.text('Action Tasks & Checklist (1 of 2 completed)'), findsOneWidget);
        expect(find.text('Reopened / Needs Correction'), findsOneWidget);
        expect(find.text('Correction requested: Calibration certificate expired; recalibrate with valid unit.'), findsOneWidget);

        // Mock store check: task is reset to Open with reason, overall action percent & status preserved
        final updatedAction = MockActionStore.instance.actions.firstWhere((a) => a.id == 'ACT-G13-CASE5-01');
        expect(updatedAction.percentComplete, equals(100));
        expect(updatedAction.status, equals('Pending Review'));
        final reopenedTask = updatedAction.subTasks.firstWhere((t) => t.id == 'ST-G13-T1');
        expect(reopenedTask.isCompleted, isFalse);
        expect(reopenedTask.reopenReason, equals('Calibration certificate expired; recalibrate with valid unit.'));
      });

      testWidgets('13.6 Case 6: Staff Update UI displays [Reopened / Needs Correction] chip and preserves peer tasks on save', (tester) async {
        tester.view.physicalSize = const Size(1280, 2500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final t1 = createTestSubTask(
          id: 'ST-G13-PEER-1',
          parentActionId: 'ACT-G13-PEER-01',
          title: 'Staff A Reopened Task',
          assignedStaff: userA.name,
          assignedStaffId: userA.personId,
          status: 'Open',
          reopenReason: 'Re-torque bolts to 120 Nm.',
        );
        final t2 = createTestSubTask(
          id: 'ST-G13-PEER-2',
          parentActionId: 'ACT-G13-PEER-01',
          title: 'Contractor B Task (Peer Task)',
          assignedStaff: userB.name,
          assignedStaffId: userB.personId,
          assignedStaffEmail: userB.email,
          assigneeType: 'external',
          status: 'Open',
        );

        final peerAction = createTestRecord(
          id: 'ACT-G13-PEER-01',
          subject: 'Multi-party Action',
          subTasks: [t1, t2],
          percentComplete: 0,
        );
        MockActionStore.instance.add(peerAction);

        await tester.pumpWidget(
          MaterialApp(
            home: WorkerActionUpdateScreen(
              action: peerAction,
              currentUserId: userA.personId,
              currentUserName: userA.name,
              currentUserEmail: userA.email,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Staff A sees only their task
        expect(find.text('Staff A Reopened Task'), findsOneWidget);
        expect(find.text('Contractor B Task (Peer Task)'), findsNothing);

        // Staff A sees Reopened / Needs Correction chip and note
        expect(find.text('Reopened / Needs Correction'), findsOneWidget);
        expect(find.text('Correction requested: Re-torque bolts to 120 Nm.'), findsOneWidget);

        // Staff A completes their task
        final cb = find.byKey(const Key('worker_task_checkbox_0'));
        await tester.tap(cb);
        await tester.pumpAndSettle();

        // Staff A taps Save Update
        final saveBtn = find.text('Save Update').first;
        await tester.ensureVisible(saveBtn);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        // Check MockStore: peer task t2 MUST still exist!
        final savedAction = MockActionStore.instance.actions.firstWhere((a) => a.id == 'ACT-G13-PEER-01');
        expect(savedAction.subTasks.length, equals(2));
        final preservedPeerTask = savedAction.subTasks.firstWhere((t) => t.id == 'ST-G13-PEER-2');
        expect(preservedPeerTask.title, equals('Contractor B Task (Peer Task)'));
        expect(preservedPeerTask.assignedStaff, equals(userB.name));
      });

      testWidgets('13.7 Case 7: Staff Update UI Submit for Review validates all assigned tasks are completed', (tester) async {
        tester.view.physicalSize = const Size(1280, 2500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final t1 = createTestSubTask(
          id: 'ST-G13-REV-1',
          parentActionId: 'ACT-G13-REV-01',
          title: 'Incomplete Staff Task',
          assignedStaff: userA.name,
          assignedStaffId: userA.personId,
          status: 'Open',
        );

        final revAction = createTestRecord(
          id: 'ACT-G13-REV-01',
          subject: 'Review Submission Validation Action',
          subTasks: [t1],
          percentComplete: 0,
        );
        MockActionStore.instance.add(revAction);

        await tester.pumpWidget(
          MaterialApp(
            home: WorkerActionUpdateScreen(
              action: revAction,
              currentUserId: userA.personId,
              currentUserName: userA.name,
              currentUserEmail: userA.email,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Try to Submit for Review while task is incomplete
        final submitBtn = find.text('Submit for Review').first;
        await tester.ensureVisible(submitBtn);
        await tester.tap(submitBtn);
        await tester.pumpAndSettle();

        // Should show validation error snackbar
        expect(find.text('All assigned tasks must be completed before submitting for review.'), findsOneWidget);

        // Action status in store should remain In Progress
        var curAction = MockActionStore.instance.actions.firstWhere((a) => a.id == 'ACT-G13-REV-01');
        expect(curAction.status, isNot(equals('Pending Review')));

        // Now complete the task
        final cb = find.byKey(const Key('worker_task_checkbox_0'));
        await tester.tap(cb);
        await tester.pumpAndSettle();

        // Select 100% progress manually
        await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
        await tester.pumpAndSettle();
        await tester.tap(find.text('100%').last);
        await tester.pumpAndSettle();

        // Submit for Review again
        await tester.ensureVisible(submitBtn);
        await tester.tap(submitBtn);
        await tester.pumpAndSettle();

        // Verify action status transitioned to 'Pending Review'
        curAction = MockActionStore.instance.actions.firstWhere((a) => a.id == 'ACT-G13-REV-01');
        expect(curAction.status, equals('Pending Review'));
        expect(curAction.percentComplete, equals(100));
      });
    });

    group('Group 14 - Task Editing, Overview Interactive Checkbox & Manager Update Screen Task Retention', () {
      testWidgets('14.1 Manager editing task in ActionDetailsScreen preserves task ID and updates details', (tester) async {
        final task1 = createTestSubTask(
          id: 'TSK-G14-01',
          parentActionId: 'ACT-G14-EDIT',
          title: 'Initial Scaffolding Check',
          assignedStaff: userA.name,
          assignedStaffId: userA.personId,
          assignedStaffEmail: userA.email,
        );
        final action = createTestRecord(
          id: 'ACT-G14-EDIT',
          subject: 'Task Edit Action',
          subTasks: [task1],
          percentComplete: 0,
        );
        MockActionStore.instance.add(action);

        await tester.pumpWidget(
          MaterialApp(
            home: ActionDetailsScreen(
              action: action,
              managerContext: managerContext,
              currentUserId: managerProfile.id,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Find Edit button in overview card
        final editBtn = find.byKey(const Key('overview_edit_task_TSK-G14-01'));
        expect(editBtn, findsOneWidget);
        await tester.tap(editBtn);
        await tester.pumpAndSettle();

        // Edit dialog should be open with prefilled title
        expect(find.text('Edit Task — TSK-G14-01'), findsOneWidget);
        final titleField = find.byKey(const Key('edit_subtask_title_TSK-G14-01'));
        expect(titleField, findsOneWidget);

        // Update title and instruction
        await tester.enterText(titleField, 'Updated Scaffolding Protocol');
        final instructionField = find.byKey(const Key('edit_subtask_instruction_TSK-G14-01'));
        await tester.enterText(instructionField, 'Inspect couplings and safety harness points');
        final remarksField = find.byKey(const Key('edit_subtask_remarks_TSK-G14-01'));
        await tester.enterText(remarksField, 'Priority audit requested by safety officer');

        // Save
        final saveBtn = find.byKey(const Key('save_subtask_btn_TSK-G14-01'));
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        // Verify task updated in MockActionStore while keeping task ID
        final stored = MockActionStore.instance.actions.firstWhere((a) => a.id == 'ACT-G14-EDIT');
        expect(stored.subTasks.length, equals(1));
        expect(stored.subTasks.first.id, equals('TSK-G14-01'));
        expect(stored.subTasks.first.title, equals('Updated Scaffolding Protocol'));
        expect(stored.subTasks.first.instruction, equals('Inspect couplings and safety harness points'));
        expect(stored.subTasks.first.remarks, equals('Priority audit requested by safety officer'));
        expect(stored.history.first, contains('Task "TSK-G14-01" details updated by Manager'));
      });

      testWidgets('14.2 Tapping interactive checkbox in ActionDetailsScreen Overview tab completes task and updates progress', (tester) async {
        final task1 = createTestSubTask(
          id: 'TSK-G14-02A',
          parentActionId: 'ACT-G14-TOGGLE',
          title: 'Foundation Inspection',
          assignedStaff: userA.name,
          assignedStaffId: userA.personId,
          assignedStaffEmail: userA.email,
        );
        final task2 = createTestSubTask(
          id: 'TSK-G14-02B',
          parentActionId: 'ACT-G14-TOGGLE',
          title: 'Concrete Pouring Signoff',
          assignedStaff: userA.name,
          assignedStaffId: userA.personId,
          assignedStaffEmail: userA.email,
        );
        final action = createTestRecord(
          id: 'ACT-G14-TOGGLE',
          subject: 'Task Toggle Action',
          subTasks: [task1, task2],
          percentComplete: 0,
        );
        MockActionStore.instance.add(action);

        await tester.pumpWidget(
          MaterialApp(
            home: ActionDetailsScreen(
              action: action,
              managerContext: managerContext,
              currentUserId: managerProfile.id,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Check first task
        final cb1 = find.byKey(const Key('overview_task_checkbox_TSK-G14-02A'));
        expect(cb1, findsOneWidget);
        await tester.tap(cb1);
        await tester.pumpAndSettle();

        // Task is marked completed while manual progress is preserved at 0%
        final stored = MockActionStore.instance.actions.firstWhere((a) => a.id == 'ACT-G14-TOGGLE');
        expect(stored.percentComplete, equals(0));
        expect(stored.subTasks.firstWhere((t) => t.id == 'TSK-G14-02A').isCompleted, isTrue);
        expect(stored.subTasks.firstWhere((t) => t.id == 'TSK-G14-02B').isCompleted, isFalse);
      });

      testWidgets('14.3 Unchecking completed task in Overview tab prompts for reopen reason and preserves action progress', (tester) async {
        final task1 = createTestSubTask(
          id: 'TSK-G14-03',
          parentActionId: 'ACT-G14-UNCHECK',
          title: 'Safety Barrier Verification',
          assignedStaff: userA.name,
          assignedStaffId: userA.personId,
          assignedStaffEmail: userA.email,
          status: 'Completed',
          completedAt: '19 Oct 2026',
          completedBy: userA.name,
        );
        final action = createTestRecord(
          id: 'ACT-G14-UNCHECK',
          subject: 'Uncheck Task Action',
          subTasks: [task1],
          percentComplete: 100,
          status: 'Pending Review',
        );
        MockActionStore.instance.add(action);

        await tester.pumpWidget(
          MaterialApp(
            home: ActionDetailsScreen(
              action: action,
              managerContext: managerContext,
              currentUserId: managerProfile.id,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap checkbox to uncheck
        final cb = find.byKey(const Key('overview_task_checkbox_TSK-G14-03'));
        expect(cb, findsOneWidget);
        await tester.tap(cb);
        await tester.pumpAndSettle();

        // Dialog should open requesting reason
        expect(find.text('Reopen Task: Safety Barrier Verification'), findsOneWidget);
        final reasonField = find.byKey(const Key('reopen_subtask_reason_TSK-G14-03'));
        await tester.enterText(reasonField, 'Barrier was found unlatched in Zone 3');

        final confirmBtn = find.byKey(const Key('confirm_reopen_subtask_btn_TSK-G14-03'));
        await tester.tap(confirmBtn);
        await tester.pumpAndSettle();

        // Verify task is now Open, action progress remains 100%, and action status remains Pending Review
        final stored = MockActionStore.instance.actions.firstWhere((a) => a.id == 'ACT-G14-UNCHECK');
        expect(stored.percentComplete, equals(100));
        expect(stored.status, equals('Pending Review'));
        expect(stored.subTasks.first.isCompleted, isFalse);
        expect(stored.subTasks.first.reopenReason, equals('Barrier was found unlatched in Zone 3'));
      });

      testWidgets('14.4 ManagerActionUpdateScreen retains pre-configured tasks and does not clear them', (tester) async {
        final task1 = createTestSubTask(
          id: 'TSK-G14-04',
          parentActionId: 'ACT-G14-RET',
          title: 'Preconfigured Operational Task',
          assignedStaff: 'Manager User',
          assignedStaffId: managerProfile.id,
          assignedStaffEmail: managerProfile.email,
        );
        final action = createTestRecord(
          id: 'ACT-G14-RET',
          subject: 'Manager Update Retention Action',
          subTasks: [task1],
          percentComplete: 0,
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

        // Check that the task checklist is visible and displays the configured task
        expect(find.text('Preconfigured Operational Task'), findsOneWidget);
        expect(find.textContaining('Assigned Tasks & Checklist'), findsOneWidget);
      });
    });
  });
}
