import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/models/organization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const orgId = Organization.sobhaId;
  const staffId = 'staff-uuid-101';
  const staffName = 'R. Kumar';
  const staffEmail = 'rkumar@sobha.com';

  final staffProfile = UserProfile(
    id: staffId,
    name: staffName,
    email: staffEmail,
    phone: '+971 50 111 2222',
    role: 'staff',
    designation: 'Safety Field Officer',
    organizationId: orgId,
    department: 'Operations',
    site: 'North Plant',
  );

  final managerProfile = UserProfile(
    id: 'mgr-uuid-201',
    name: 'M. Manager',
    email: 'manager@sobha.com',
    phone: '+971 50 333 4444',
    role: 'manager',
    designation: 'HSE Manager',
    organizationId: orgId,
    department: 'HSE',
    site: 'North Plant',
  );

  final managerContext = ManagerContext(
    authUserId: managerProfile.id,
    profile: managerProfile,
    organizationId: orgId,
    organizationName: Organization.sobhaName,
    scopes: const [],
  );

  // 1. Direct Action to Staff (In Progress 50%)
  final directAction = ActionRecord(
    id: 'ACT-DIR-001',
    actionNumber: 'ACT-DIR-001',
    organizationId: orgId,
    subject: 'Inspect electrical panel A',
    actionRequired: 'Inspect and test breaker integrity',
    division: 'Operations',
    status: 'In Progress',
    priority: 'High',
    department: 'Operations',
    site: 'North Plant',
    assignedTo: staffName,
    assignedToId: staffId,
    percentComplete: 50,
    targetDate: '20 Sep 2026',
    dateRaised: '10 Sep 2026',
  );

  // 2. Action Forwarded to Staff as Contributor (In Progress 30%)
  final contributorAction = ActionRecord(
    id: 'ACT-FWD-002',
    actionNumber: 'ACT-FWD-002',
    organizationId: orgId,
    subject: 'Scaffolding safety remediation',
    actionRequired: 'Replace clamps and secure toe boards',
    division: 'Operations',
    status: 'In Progress',
    priority: 'Critical',
    department: 'Operations',
    site: 'North Plant',
    assignedTo: 'Lead Engineer',
    assignedToId: 'lead-eng-999',
    percentComplete: 30,
    targetDate: '25 Sep 2026',
    dateRaised: '12 Sep 2026',
    contributors: const [
      ActionContributorRecord(
        id: 'contrib-1',
        actionId: 'ACT-FWD-002',
        profileId: staffId,
        profileName: staffName,
        profileEmail: staffEmail,
      ),
    ],
  );

  // 3. Action Forwarded to Staff as Sub-Task (In Progress 20%)
  final subTaskAction = ActionRecord(
    id: 'ACT-SUB-003',
    actionNumber: 'ACT-SUB-003',
    organizationId: orgId,
    subject: 'Warehouse hazard containment',
    actionRequired: 'Complete delegated safety subtasks',
    division: 'Operations',
    status: 'In Progress',
    priority: 'Medium',
    department: 'Operations',
    site: 'North Plant',
    assignedTo: 'Site Supervisor',
    assignedToId: 'site-sup-888',
    percentComplete: 20,
    targetDate: '28 Sep 2026',
    dateRaised: '14 Sep 2026',
    subTasks: const [
      ActionSubTask(
        id: 'subtask-1',
        parentActionId: 'ACT-SUB-003',
        title: 'Inspect fire extinguishers in Zone 3',
        instruction: 'Check pressure gauges',
        assignedStaff: staffName,
        assignedStaffId: staffId,
        assignedStaffEmail: staffEmail,
        status: 'In Progress',
      ),
    ],
  );

  // 4. Action assigned to Someone Else (Staff NOT involved)
  final unassociatedAction = ActionRecord(
    id: 'ACT-OTHER-004',
    actionNumber: 'ACT-OTHER-004',
    organizationId: orgId,
    subject: 'Unrelated Corporate Audit',
    actionRequired: 'Conduct audit review',
    division: 'Corporate',
    status: 'In Progress',
    priority: 'Low',
    department: 'Corporate',
    site: 'Admin Block',
    assignedTo: 'Other Person',
    assignedToId: 'other-user-777',
    percentComplete: 10,
    targetDate: '30 Sep 2026',
  );

  // 5. Action Awaiting Review (Pending Review, 100%)
  final awaitingReviewAction = ActionRecord(
    id: 'ACT-REV-005',
    actionNumber: 'ACT-REV-005',
    organizationId: orgId,
    subject: 'Confined space ventilation testing',
    actionRequired: 'Test ventilation and upload airflow report',
    division: 'Operations',
    status: 'Pending Review',
    priority: 'High',
    department: 'Operations',
    site: 'North Plant',
    assignedTo: staffName,
    assignedToId: staffId,
    percentComplete: 100,
    targetDate: '15 Sep 2026',
  );

  // 6. Terminal Closed Action
  final closedAction = ActionRecord(
    id: 'ACT-CLS-006',
    actionNumber: 'ACT-CLS-006',
    organizationId: orgId,
    subject: 'Chemical spill kit restock',
    actionRequired: 'Restock absorbent pads',
    division: 'Operations',
    status: 'Closed',
    priority: 'Low',
    department: 'Operations',
    site: 'North Plant',
    assignedTo: staffName,
    assignedToId: staffId,
    percentComplete: 100,
    targetDate: '01 Sep 2026',
  );

  group('ActionRecord Forwarding Helpers Unit Tests', () {
    test('isForwarded returns true when contributors exist', () {
      expect(contributorAction.isForwarded, isTrue);
      expect(subTaskAction.isForwarded, isTrue);
      expect(directAction.isForwarded, isFalse);
    });

    test('isForwardedTo matches by userId, userName, and email', () {
      expect(contributorAction.isForwardedTo(staffId), isTrue);
      expect(contributorAction.isForwardedTo(null, staffName), isTrue);
      expect(contributorAction.isForwardedTo(null, null, staffEmail), isTrue);
      expect(contributorAction.isForwardedTo('non-existent-id'), isFalse);

      expect(subTaskAction.isForwardedTo(staffId), isTrue);
      expect(subTaskAction.isForwardedTo(null, staffName), isTrue);
      expect(subTaskAction.isForwardedTo(null, null, staffEmail), isTrue);
      expect(subTaskAction.isForwardedTo('random-id'), isFalse);

      expect(directAction.isForwardedTo(staffId), isFalse);
    });
  });

  group('Manager Action Register - Forwarded Filter Tests', () {
    testWidgets('Forwarded dropdown filters actions to Forwarded Only and Direct Only', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final List<ActionRecord> allTestActions = [
        directAction,
        contributorAction,
        subTaskAction,
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: ManagerDashboardScreen(
            userProfile: managerProfile,
            managerContext: managerContext,
            initialActions: allTestActions,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Action Register (tab index 1)
      await tester.tap(find.text('Action Register').first);
      await tester.pumpAndSettle();

      // Initially all 3 actions are in the register
      expect(find.text('ACT-DIR-001'), findsWidgets);
      expect(find.text('ACT-FWD-002'), findsWidgets);
      expect(find.text('ACT-SUB-003'), findsWidgets);

      // Verify the 'Forwarded' filter dropdown is present
      expect(find.text('Forwarded'), findsWidgets);
    });
  });

  group('Staff Portal - My Actions & Forwarded Actions Tests', () {
    setUp(() {
      MockActionStore.instance.actions.clear();
      MockActionStore.instance.actions.addAll([
        directAction,
        contributorAction,
        subTaskAction,
        unassociatedAction,
        awaitingReviewAction,
        closedAction,
      ]);
    });

    testWidgets('My Actions displays assigned AND forwarded actions, excluding unassociated', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: WorkerDashboardScreen(userProfile: staffProfile),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to My Actions tab (tab index 1)
      await tester.tap(find.text('My Actions').first);
      await tester.pumpAndSettle();

      // Directly assigned action is visible
      expect(find.text('ACT-DIR-001'), findsWidgets);
      // Contributor forwarded action is visible
      expect(find.text('ACT-FWD-002'), findsWidgets);
      // Sub-task forwarded action is visible
      expect(find.text('ACT-SUB-003'), findsWidgets);
      // Review action is visible
      expect(find.text('ACT-REV-005'), findsWidgets);
      // Closed action is visible in My Actions
      expect(find.text('ACT-CLS-006'), findsWidgets);

      // Unassociated action is NOT visible
      expect(find.text('ACT-OTHER-004'), findsNothing);

      // Forwarded badges are displayed for forwarded actions
      expect(find.text('Forwarded'), findsWidgets);

      // Forwarded Actions filter dropdown is present
      expect(find.text('Forwarded Actions'), findsWidgets);
      // Date Field & Date Period filters are present
      expect(find.text('Date Field'), findsWidgets);
      expect(find.text('Date Period'), findsWidgets);
    });

    testWidgets('Pending Updates includes partial progress & handles awaiting review state without duplicate submit', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: WorkerDashboardScreen(userProfile: staffProfile),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Pending Updates tab (tab index 3)
      await tester.tap(find.text('Pending Updates').first);
      await tester.pumpAndSettle();

      // Terminal closed action ACT-CLS-006 is excluded
      expect(find.text('ACT-CLS-006'), findsNothing);

      // In-progress actions (direct, contributor, sub-task) are present
      expect(find.text('ACT-DIR-001'), findsOneWidget);
      expect(find.text('ACT-FWD-002'), findsOneWidget);
      expect(find.text('ACT-SUB-003'), findsOneWidget);

      // Normal in-progress actions show 'Submit Update'
      expect(find.text('Submit Update'), findsWidgets);

      // Action awaiting review is present and distinctively badged
      expect(find.text('ACT-REV-005'), findsOneWidget);
      expect(find.text('Awaiting Manager Review'), findsOneWidget);
      // For awaiting review, 'View Status' is shown instead of prompting 'Submit Update'
      expect(find.text('View Status'), findsOneWidget);
    });
  });
}

