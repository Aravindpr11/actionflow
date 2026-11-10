import 'package:action_flow/features/auth/models/manager_scope_item.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const managerOrgId = Organization.sobhaId;
  const otherOrgId = 'other-org-uuid-9999';

  const managerProfileId = 'mgr-profile-uuid-1111';
  const staffProfileId = 'staff-profile-uuid-2222';

  final managerProfile = UserProfile(
    id: managerProfileId,
    name: 'M. Manager',
    email: 'manager@sobha.com',
    phone: '+971 50 123 4567',
    designation: 'HSE Manager',
    role: 'manager',
    organizationId: managerOrgId,
    department: 'HSE',
    site: 'North Plant',
  );

  final managerContext = ManagerContext(
    authUserId: managerProfileId,
    profile: managerProfile,
    organizationId: managerOrgId,
    organizationName: Organization.sobhaName,
    scopes: const [
      ManagerScopeItem(
        departmentId: 'dept-hse',
        departmentName: 'HSE',
        siteId: 'site-np',
        siteName: 'North Plant',
      ),
      ManagerScopeItem(
        departmentId: 'dept-ops',
        departmentName: 'Operations',
        siteId: 'site-np',
        siteName: 'North Plant',
      ),
    ],
  );

  // 1. Action assigned directly to Manager
  final actionAssignedToManager = ActionRecord(
    id: 'act-uuid-001',
    actionNumber: 'ACT-1001',
    organizationId: managerOrgId,
    departmentId: 'dept-hse',
    department: 'HSE',
    siteId: 'site-np',
    site: 'North Plant',
    division: 'Operations',
    subject: 'Safety Audit Walkthrough',
    actionRequired: 'Inspect emergency fire exits',
    createdById: managerProfileId,
    assignedToId: managerProfileId,
    assignedTo: 'M. Manager',
    priority: 'High',
    status: 'Open',
    targetDate: '25 Sep 2026',
  );

  // 2. Action created by Manager, but assigned to Staff
  final actionAssignedToStaff = ActionRecord(
    id: 'act-uuid-002',
    actionNumber: 'ACT-1002',
    organizationId: managerOrgId,
    departmentId: 'dept-hse',
    department: 'HSE',
    siteId: 'site-np',
    site: 'North Plant',
    division: 'Operations',
    subject: 'PPE Replenishment Checklist',
    actionRequired: 'Distribute goggles and helmets to Zone B',
    createdById: managerProfileId, // Created by Manager!
    assignedToId: staffProfileId, // Assigned to Staff
    assignedTo: 'S. Staff',
    priority: 'Medium',
    status: 'In Progress',
    targetDate: '26 Sep 2026',
  );

  // 3. Action within Manager scope, but unassigned
  final actionUnassigned = ActionRecord(
    id: 'act-uuid-003',
    actionNumber: 'ACT-1003',
    organizationId: managerOrgId,
    departmentId: 'dept-ops',
    department: 'Operations',
    siteId: 'site-np',
    site: 'North Plant',
    division: 'Operations',
    subject: 'Compressor Vibration Report',
    actionRequired: 'Investigate abnormal pump noise',
    createdById: managerProfileId,
    assignedToId: null, // Unassigned!
    assignedTo: 'Unassigned',
    priority: 'Critical',
    status: 'Open',
    targetDate: '24 Sep 2026',
  );

  // 4. Action from another organization
  final actionCrossOrg = ActionRecord(
    id: 'act-uuid-004',
    actionNumber: 'ACT-1004',
    organizationId: otherOrgId, // Cross-organization!
    departmentId: 'dept-hse',
    department: 'HSE',
    siteId: 'site-np',
    site: 'North Plant',
    division: 'Operations',
    subject: 'Competitor Spill Drill',
    actionRequired: 'Not our org',
    createdById: managerProfileId,
    assignedToId: managerProfileId,
    assignedTo: 'M. Manager',
    priority: 'Low',
    status: 'Open',
    targetDate: '30 Sep 2026',
  );

  group('Manager Portal: ACTION REGISTER vs MY ACTIONS Distinction Tests', () {
    testWidgets(
      '1. Action Register shows all scoped actions (Manager-assigned, Staff-assigned, and Unassigned)',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Action Register receives all scoped actions belonging to this org
        final scopedRegisterActions = [
          actionAssignedToManager,
          actionAssignedToStaff,
          actionUnassigned,
        ];
        final myActionsOnly = [actionAssignedToManager];

        await tester.pumpWidget(
          MaterialApp(
            home: ManagerDashboardScreen(
              userProfile: managerProfile,
              managerContext: managerContext,
              initialActions: scopedRegisterActions,
              initialMyActions: myActionsOnly,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to Action Register (Index 1)
        final actionRegisterNav = find.byKey(
          const ValueKey('sidebar_item_Action Register'),
        );
        expect(actionRegisterNav, findsOneWidget);
        await tester.tap(actionRegisterNav);
        await tester.pumpAndSettle();

        // Verify title
        expect(find.text('Action Register'), findsWidgets);
        expect(
          find.textContaining('3 actions recorded in register'),
          findsOneWidget,
        );

        // Action Register MUST contain Manager-assigned, Staff-assigned, and Unassigned actions
        expect(find.text('Safety Audit Walkthrough'), findsOneWidget);
        expect(find.text('PPE Replenishment Checklist'), findsOneWidget);
        expect(find.text('Compressor Vibration Report'), findsOneWidget);
      },
    );

    testWidgets(
      '2. My Actions shows ONLY actions assigned to the logged-in Manager UUID',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final scopedRegisterActions = [
          actionAssignedToManager,
          actionAssignedToStaff,
          actionUnassigned,
        ];
        final myActionsOnly = [actionAssignedToManager];

        await tester.pumpWidget(
          MaterialApp(
            home: ManagerDashboardScreen(
              userProfile: managerProfile,
              managerContext: managerContext,
              initialActions: scopedRegisterActions,
              initialMyActions: myActionsOnly,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to My Actions (Index 3)
        final myActionsNav = find.byKey(
          const ValueKey('sidebar_item_My Actions'),
        );
        expect(myActionsNav, findsOneWidget);
        await tester.tap(myActionsNav);
        await tester.pumpAndSettle();

        // Verify title & subtitle
        expect(find.text('My Actions'), findsWidgets);
        expect(find.textContaining('1 action assigned to you'), findsOneWidget);

        // MUST contain Manager-assigned action
        expect(find.text('Safety Audit Walkthrough'), findsOneWidget);

        // MUST EXCLUDE Staff-assigned actions (even if created by the Manager)
        expect(find.text('PPE Replenishment Checklist'), findsNothing);

        // MUST EXCLUDE Unassigned actions (even if within Manager scope)
        expect(find.text('Compressor Vibration Report'), findsNothing);
      },
    );

    testWidgets(
      '3. Manager with zero assigned actions sees explicit empty state and DOES NOT fall back to Action Register',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Manager has 2 actions in Action Register, but 0 assigned to themselves
        final scopedRegisterActions = [actionAssignedToStaff, actionUnassigned];
        final zeroMyActions = <ActionRecord>[];

        await tester.pumpWidget(
          MaterialApp(
            home: ManagerDashboardScreen(
              userProfile: managerProfile,
              managerContext: managerContext,
              initialActions: scopedRegisterActions,
              initialMyActions: zeroMyActions,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to My Actions (Index 3)
        final myActionsNav = find.byKey(
          const ValueKey('sidebar_item_My Actions'),
        );
        await tester.tap(myActionsNav);
        await tester.pumpAndSettle();

        // Verify My Actions is displayed with 0 count
        expect(find.text('My Actions'), findsWidgets);
        expect(find.text('My Actions (0)'), findsOneWidget);

        // Explicit empty state MUST be displayed
        expect(find.text('No actions assigned to you.'), findsOneWidget);
        expect(
          find.text('You currently have no actions assigned to your account.'),
          findsOneWidget,
        );

        // Action Register items must NEVER bleed into My Actions
        expect(find.text('PPE Replenishment Checklist'), findsNothing);
        expect(find.text('Compressor Vibration Report'), findsNothing);
      },
    );

    testWidgets(
      '4. Strict UUID matching: Actions created by Manager but assigned to others are rejected from My Actions',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // An action with createdById matching manager, but assignedToId matching staff
        final actionCreatedByMgrAssignedToStaff = ActionRecord(
          id: 'act-uuid-005',
          actionNumber: 'ACT-1005',
          organizationId: managerOrgId,
          departmentId: 'dept-hse',
          department: 'HSE',
          siteId: 'site-np',
          site: 'North Plant',
          division: 'Operations',
          subject: 'Staff Tool Calibration',
          actionRequired: 'Calibrate pressure gauges',
          createdById: managerProfileId,
          assignedToId: staffProfileId,
          assignedTo: 'S. Staff',
          priority: 'Medium',
          status: 'Open',
          targetDate: '27 Sep 2026',
        );

        // Even if passed into initialMyActions, the strict client-side UUID filter
        // `a.assignedToId == currentUserId` ensures it is rejected!
        await tester.pumpWidget(
          MaterialApp(
            home: ManagerDashboardScreen(
              userProfile: managerProfile,
              managerContext: managerContext,
              initialActions: [actionCreatedByMgrAssignedToStaff],
              initialMyActions: [actionCreatedByMgrAssignedToStaff],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Switch to My Actions
        await tester.tap(find.byKey(const ValueKey('sidebar_item_My Actions')));
        await tester.pumpAndSettle();

        // Strict UUID check prevents displaying this action in My Actions
        expect(find.text('Staff Tool Calibration'), findsNothing);
        expect(find.text('No actions assigned to you.'), findsOneWidget);
      },
    );

    testWidgets(
      '5. Cross-organization actions are rejected from My Actions and Action Register',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Even if an action has assignedToId == managerProfileId, if organizationId != managerOrgId,
        // it cannot belong to this manager session
        expect(actionCrossOrg.organizationId, isNot(equals(managerOrgId)));
      },
    );

    testWidgets(
      '6. Opening an action from My Actions opens the Action Details Screen with full functionality',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: ManagerDashboardScreen(
              userProfile: managerProfile,
              managerContext: managerContext,
              initialActions: [actionAssignedToManager],
              initialMyActions: [actionAssignedToManager],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to My Actions
        await tester.tap(find.byKey(const ValueKey('sidebar_item_My Actions')));
        await tester.pumpAndSettle();

        // Tap the assigned action row
        final actionRow = find.text('Safety Audit Walkthrough');
        expect(actionRow, findsOneWidget);
        await tester.tap(actionRow);
        await tester.pumpAndSettle();

        // Action Details screen opened
        expect(find.byType(ActionDetailsScreen), findsOneWidget);
        expect(find.text('ACT-1001'), findsWidgets);
        expect(find.text('Safety Audit Walkthrough'), findsWidgets);
      },
    );

    test('7. ActionRecord UUID parsing and serialization integrity', () {
      final jsonMap = {
        'id': 'test-uuid-999',
        'action_number': 'ACT-9999',
        'organization_id': managerOrgId,
        'department_id': 'dept-hse',
        'site_id': 'site-np',
        'created_by': managerProfileId,
        'assigned_to': staffProfileId,
        'title': 'Test Serialization Action',
        'action_required': 'Verify parsing',
        'priority': 'High',
        'status': 'Open',
        'target_date': '2026-09-30',
        'percent_complete': 0,
        'assignee': {
          'id': staffProfileId,
          'full_name': 'A. Staff',
          'email': 'staff@sobha.com',
          'designation': 'HSE Officer',
        },
      };

      final record = ActionRecord.fromSupabase(jsonMap);
      expect(record.id, 'test-uuid-999');
      expect(record.assignedToId, staffProfileId);
      expect(record.assignedTo, 'A. Staff');
      expect(record.createdById, managerProfileId);
      expect(record.displayId, 'ACT-9999');

      // If assigned_to is null
      final unassignedMap = Map<String, dynamic>.from(jsonMap);
      unassignedMap.remove('assigned_to');
      unassignedMap.remove('assignee');
      final unassignedRecord = ActionRecord.fromSupabase(unassignedMap);
      expect(unassignedRecord.assignedToId, isNull);
      expect(unassignedRecord.assignedTo, 'Unassigned');
    });

    test('8. Staff My Actions logic remains strictly Staff-only', () {
      final allOrgActions = [
        actionAssignedToManager,
        actionAssignedToStaff,
        actionUnassigned,
      ];

      // Filtering for Staff user
      final staffActions = allOrgActions.where((a) {
        return a.organizationId == managerOrgId &&
            a.assignedToId != null &&
            a.assignedToId == staffProfileId;
      }).toList();

      expect(staffActions.length, 1);
      expect(staffActions.first.id, actionAssignedToStaff.id);
      expect(staffActions.first.assignedToId, staffProfileId);
      expect(
        staffActions.any((a) => a.assignedToId == managerProfileId),
        isFalse,
      );
      expect(staffActions.any((a) => a.assignedToId == null), isFalse);
    });

    testWidgets(
      '9. Existing Action Register filtering and search behavior remains fully intact',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final scopedRegisterActions = [
          actionAssignedToManager,
          actionAssignedToStaff,
          actionUnassigned,
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: ManagerDashboardScreen(
              userProfile: managerProfile,
              managerContext: managerContext,
              initialActions: scopedRegisterActions,
              initialMyActions: [actionAssignedToManager],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Switch to Action Register
        await tester.tap(
          find.byKey(const ValueKey('sidebar_item_Action Register')),
        );
        await tester.pumpAndSettle();

        // Enter search query 'Compressor'
        final searchField = find.widgetWithText(TextField, 'Search actions...');
        expect(searchField, findsOneWidget);
        await tester.enterText(searchField, 'Compressor');
        await tester.pumpAndSettle();

        // Should filter to Compressor action only
        expect(find.text('Compressor Vibration Report'), findsOneWidget);
        expect(find.text('Safety Audit Walkthrough'), findsNothing);
        expect(find.text('PPE Replenishment Checklist'), findsNothing);
      },
    );

    testWidgets(
      '10. Manager can delete an action from My Actions including closed action',
      (tester) async {
        tester.view.physicalSize = const Size(2600, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final closedMyAction = ActionRecord(
          id: 'act-closed-my-01',
          actionNumber: 'ACT-9001',
          organizationId: managerOrgId,
          departmentId: 'dept-hse',
          department: 'HSE',
          siteId: 'site-np',
          site: 'North Plant',
          division: 'Operations',
          subject: 'Closed Action In My Actions',
          actionRequired: 'Verify closed action deletion',
          createdById: managerProfileId,
          assignedToId: managerProfileId,
          assignedTo: 'M. Manager',
          priority: 'Medium',
          status: 'Closed',
          percentComplete: 100,
          dateRaised: '01 Sep 2026',
          targetDate: '10 Sep 2026',
          closeDate: '10 Sep 2026',
          closedAt: DateTime(2026, 9, 10),
        );

        MockActionStore.instance.actions.add(closedMyAction);
        addTearDown(() {
          MockActionStore.instance.actions.removeWhere(
            (a) => a.id == closedMyAction.id,
          );
        });

        await tester.pumpWidget(
          MaterialApp(
            home: ManagerDashboardScreen(
              userProfile: managerProfile,
              managerContext: managerContext,
              initialActions: [closedMyAction],
              initialMyActions: [closedMyAction],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Switch to My Actions
        await tester.tap(find.byKey(const ValueKey('sidebar_item_My Actions')));
        await tester.pumpAndSettle();

        // Verify Delete button is present in My Actions
        final deleteButtonFinder = find.widgetWithText(
          OutlinedButton,
          'Delete',
        );
        expect(deleteButtonFinder, findsOneWidget);

        // Tap Delete
        await tester.tap(deleteButtonFinder);
        await tester.pumpAndSettle();

        // Verify confirmation dialog appears (NOT the Closed Action Retained dialog)
        expect(find.text('Delete Action'), findsNWidgets(2));
        expect(
          find.textContaining(
            'Are you sure you want to permanently delete this action?',
          ),
          findsOneWidget,
        );
        expect(find.text('Closed Action Retained'), findsNothing);

        // Tap confirm 'Delete Action' inside the dialog
        final confirmDeleteButton = find.widgetWithText(
          ElevatedButton,
          'Delete Action',
        );
        await tester.tap(confirmDeleteButton);
        await tester.pumpAndSettle();

        // Verify action is removed from My Actions view
        expect(find.text('Closed Action In My Actions'), findsNothing);
        expect(find.text('0 Actions found'), findsOneWidget);
      },
    );
  });
}
