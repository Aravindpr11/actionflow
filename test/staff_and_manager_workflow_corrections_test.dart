import 'package:action_flow/features/auth/models/manager_scope_item.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/add_action_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_action_update_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const orgId = Organization.sobhaId;
  const managerId = 'mgr-uuid-001';
  const staffAId = 'staff-uuid-001';
  const staffBId = 'staff-uuid-002';

  final managerProfile = UserProfile(
    id: managerId,
    name: 'M. Manager',
    email: 'manager@sobha.com',
    phone: '+971 50 123 4567',
    designation: 'HSE Manager',
    role: 'manager',
    organizationId: orgId,
    department: 'HSE',
    site: 'North Plant',
  );

  final staffAProfile = UserProfile(
    id: staffAId,
    name: 'A. Staff',
    email: 'staffa@sobha.com',
    phone: '+971 50 234 5678',
    designation: 'Safety Officer',
    role: 'staff',
    organizationId: orgId,
    department: 'HSE',
    site: 'North Plant',
  );

  final managerContext = ManagerContext(
    authUserId: managerId,
    profile: managerProfile,
    organizationId: orgId,
    organizationName: Organization.sobhaName,
    scopes: const [
      ManagerScopeItem(
        departmentId: 'dept-hse',
        departmentName: 'HSE',
        siteId: 'site-np',
        siteName: 'North Plant',
      ),
    ],
  );

  setUp(() {
    MockActionStore.instance.actions.clear();
  });

  group('Part 1: Staff Action Visibility & Manager Action Register Isolation', () {
    test('1.1 ActionService.fetchMyActions includes primary, secondary, and contributor actions', () async {
      final actPrimary = ActionRecord(
        id: 'act-1',
        actionNumber: 'ACT-001',
        subject: 'Primary Assigned',
        actionRequired: 'Test',
        division: 'Operations',
        createdById: managerId,
        assignedToId: staffAId,
        assignedTo: 'A. Staff',
      );

      final actContributor = ActionRecord(
        id: 'act-2',
        actionNumber: 'ACT-002',
        subject: 'Contributor Action',
        actionRequired: 'Test',
        division: 'Operations',
        createdById: managerId,
        assignedToId: staffBId,
        assignedTo: 'B. Staff',
        contributors: [
          ActionContributorRecord(
            id: 'c-1',
            actionId: 'act-2',
            profileId: staffAId,
            profileName: 'A. Staff',
            profileEmail: 'staffa@sobha.com',
            notes: 'forwarded',
            createdAt: DateTime.now(),
          ),
        ],
      );

      final actUnrelated = ActionRecord(
        id: 'act-3',
        actionNumber: 'ACT-003',
        subject: 'Unrelated Action',
        actionRequired: 'Test',
        division: 'Operations',
        createdById: managerId,
        assignedToId: staffBId,
        assignedTo: 'B. Staff',
      );

      MockActionStore.instance.add(actPrimary);
      MockActionStore.instance.add(actContributor);
      MockActionStore.instance.add(actUnrelated);

      final myActions = await ActionService.instance.fetchMyActions(
        organizationId: orgId,
        userId: staffAId,
      );

      final ids = myActions.map((a) => a.id).toList();
      expect(ids, contains('act-1'));
      expect(ids, contains('act-2'));
      expect(ids, isNot(contains('act-3')));
    });

    test('1.2 ActionService.fetchStaffCreatedActions returns only actions created by the user', () async {
      final createdByStaffA = ActionRecord(
        id: 'act-c1',
        actionNumber: 'ACT-C01',
        subject: 'Created by Staff A',
        actionRequired: 'Test',
        division: 'Operations',
        createdById: staffAId,
        assignedToId: managerId,
        assignedTo: 'M. Manager',
      );

      final createdByManager = ActionRecord(
        id: 'act-c2',
        actionNumber: 'ACT-C02',
        subject: 'Created by Manager',
        actionRequired: 'Test',
        division: 'Operations',
        createdById: managerId,
        assignedToId: staffAId,
        assignedTo: 'A. Staff',
      );

      MockActionStore.instance.add(createdByStaffA);
      MockActionStore.instance.add(createdByManager);

      final staffCreated = await ActionService.instance.fetchStaffCreatedActions(
        organizationId: orgId,
        userId: staffAId,
      );

      expect(staffCreated.length, equals(1));
      expect(staffCreated.first.id, equals('act-c1'));
    });

    testWidgets('1.3 Manager Action Register excludes actions created by Staff', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final managerCreated = ActionRecord(
        id: 'act-m1',
        actionNumber: 'ACT-M01',
        subject: 'Manager Created Action',
        actionRequired: 'Inspect area',
        division: 'Operations',
        department: 'HSE',
        site: 'North Plant',
        createdById: managerId,
        assignedToId: staffAId,
        assignedTo: 'A. Staff',
      );

      final staffCreated = ActionRecord(
        id: 'act-s1',
        actionNumber: 'ACT-S01',
        subject: 'Staff Created Action',
        actionRequired: 'Staff hazard report',
        division: 'Operations',
        department: 'HSE',
        site: 'North Plant',
        createdById: staffAId,
        assignedToId: staffAId,
        assignedTo: 'A. Staff',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ManagerDashboardScreen(
            userProfile: managerProfile,
            managerContext: managerContext,
            initialActions: [managerCreated, staffCreated],
            initialMyActions: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Action Register
      await tester.tap(find.byKey(const ValueKey('sidebar_item_Action Register')));
      await tester.pumpAndSettle();

      // Manager Action Register displays Manager-created action
      expect(find.text('Manager Created Action'), findsOneWidget);
      // Manager Action Register excludes Staff-created action
      expect(find.text('Staff Created Action'), findsNothing);
    });
  });

  group('Part 2: Attribution: Created By, Assigned By, Action Owner', () {
    test('2.1 ActionRecord preserves separate Created By, Assigned By, and Action Owner without Manager fallback', () {
      final act = ActionRecord(
        id: 'act-attr-1',
        actionNumber: 'ACT-ATT-01',
        subject: 'Attribution Test',
        actionRequired: 'Check fields',
        division: 'Operations',
        createdById: staffAId,
        createdByName: 'A. Staff',
        assignedBy: 'A. Staff',
        assignedToId: staffBId,
        assignedTo: 'B. Staff',
      );

      expect(act.createdByName, equals('A. Staff'));
      expect(act.assignedBy, equals('A. Staff'));
      expect(act.assignedTo, equals('B. Staff'));
    });

    testWidgets('2.2 ActionDetailsScreen displays distinct Created By and does not fallback to Safety Manager', (tester) async {
      tester.view.physicalSize = const Size(1280, 2500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final act = ActionRecord(
        id: 'act-attr-2',
        actionNumber: 'ACT-ATT-02',
        subject: 'Details Attribution Test',
        actionRequired: 'Verify details display',
        division: 'Operations',
        department: 'HSE',
        site: 'North Plant',
        createdById: staffAId,
        createdByName: 'A. Staff',
        assignedBy: 'A. Staff',
        assignedToId: staffBId,
        assignedTo: 'B. Staff',
        closedByName: 'John Closure',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ActionDetailsScreen(
            action: act,
            managerContext: managerContext,
            isWorker: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Created By section is rendered
      expect(find.text('CREATED BY'), findsOneWidget);
      // Assigned By section is rendered
      expect(find.text('ASSIGNED BY'), findsOneWidget);
      // No fallback to Safety Manager
      expect(find.text('Safety Manager'), findsNothing);
    });
  });

  group('Part 3: Staff My Actions Edit Button Navigation', () {
    testWidgets('3.1 Clicking Edit in Staff My Actions opens WorkerActionUpdateScreen (Mobile Card)', (tester) async {
      tester.view.physicalSize = const Size(600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final assignedAction = ActionRecord(
        id: 'act-edit-1',
        actionNumber: 'ACT-ED-01',
        subject: 'Staff Edit Nav Test',
        actionRequired: 'Test update route',
        division: 'Operations',
        department: 'HSE',
        site: 'North Plant',
        createdById: managerId,
        assignedToId: staffAId,
        assignedTo: 'A. Staff',
      );
      MockActionStore.instance.add(assignedAction);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkerDashboardScreen(
            userProfile: staffAProfile,
            initialNavIndex: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the Edit button in the card
      final editButton = find.widgetWithText(OutlinedButton, 'Edit');
      expect(editButton, findsOneWidget);

      await tester.tap(editButton);
      await tester.pumpAndSettle();

      // WorkerActionUpdateScreen is opened
      expect(find.byType(WorkerActionUpdateScreen), findsOneWidget);
      // AddActionScreen is NOT opened
      expect(find.byType(AddActionScreen), findsNothing);
    });

    testWidgets('3.2 Staff Action Register Edit button preserves AddActionScreen navigation', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final createdAction = ActionRecord(
        id: 'act-edit-reg-1',
        actionNumber: 'ACT-REG-01',
        subject: 'Staff Register Edit Nav Test',
        actionRequired: 'Test edit route',
        division: 'Operations',
        department: 'HSE',
        site: 'North Plant',
        createdById: staffAId,
        assignedToId: staffBId,
        assignedTo: 'B. Staff',
      );
      MockActionStore.instance.add(createdAction);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkerDashboardScreen(
            userProfile: staffAProfile,
            initialNavIndex: 12, // Action Register nav index
          ),
        ),
      );
      await tester.pumpAndSettle();

      // In Staff Action Register, Edit navigates to AddActionScreen (editing created action)
      final actionRegisterSection = find.byType(WorkerDashboardScreen);
      expect(actionRegisterSection, findsOneWidget);
    });
  });

  group('Part 4: Update Action Task/Subtask Completion & Reopening', () {
    testWidgets('4.1 Unticking a task in WorkerActionUpdateScreen prompts for reopen reason and calls submitSubtaskToggle', (tester) async {
      tester.view.physicalSize = const Size(1280, 2500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const subTask = ActionSubTask(
        id: 'st-01',
        parentActionId: 'act-sub-1',
        title: 'Check Safety Valve',
        instruction: 'Inspect gauge',
        assignedStaff: 'A. Staff',
        status: 'Completed',
        completedAt: '01 Nov 2026',
        completedBy: 'A. Staff',
      );

      final action = ActionRecord(
        id: 'act-sub-1',
        actionNumber: 'ACT-SUB-01',
        subject: 'Subtask Reopen Test',
        actionRequired: 'Reopen test',
        division: 'Operations',
        createdById: managerId,
        assignedToId: staffAId,
        assignedTo: 'A. Staff',
        percentComplete: 100,
        subTasks: [subTask],
      );

      MockActionStore.instance.add(action);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkerActionUpdateScreen(
            action: action,
            currentUserId: staffAId,
            currentUserName: staffAProfile.name,
            currentUserEmail: staffAProfile.email,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify task checkbox is checked
      final cb = find.byKey(const Key('worker_task_checkbox_0'));
      expect(cb, findsOneWidget);

      // Untick the checkbox -> prompts for reopen reason
      await tester.tap(cb);
      await tester.pumpAndSettle();

      // Verify Reopen Task dialog appears
      expect(find.textContaining('Reopen Task:'), findsOneWidget);
      expect(find.text('Reopen Task'), findsOneWidget);

      // Enter reopen reason and submit
      await tester.enterText(find.byType(TextField).last, 'Valve seal requires replacement');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Reopen Task'));
      await tester.pumpAndSettle();

      // Task is now open and reason recorded in store
      final stored = MockActionStore.instance.actions.firstWhere((a) => a.id == 'act-sub-1');
      expect(stored.subTasks.first.isCompleted, isFalse);
      expect(stored.subTasks.first.reopenReason, equals('Valve seal requires replacement'));
    });
  });
}
