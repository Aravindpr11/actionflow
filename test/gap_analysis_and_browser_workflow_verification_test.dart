import 'package:action_flow/features/auth/models/manager_scope_item.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/models/organization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const orgId = Organization.sobhaId;
  const managerId = 'mgr-uuid-001';
  const staffId = 'staff-uuid-002';

  final managerProfile = UserProfile(
    id: managerId,
    name: 'Safety Manager',
    email: 'manager@sobha.com',
    phone: '+971 50 123 4567',
    role: 'manager',
    designation: 'HSE Manager',
    organizationId: orgId,
    department: 'HSE / Safety',
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
        departmentName: 'HSE / Safety',
        siteId: 'site-np',
        siteName: 'North Plant',
      ),
    ],
  );

  final staffProfile = UserProfile(
    id: staffId,
    name: 'Test Staff',
    email: 'staff@sobha.com',
    phone: '+971 50 234 5678',
    role: 'staff',
    designation: 'Safety Officer',
    organizationId: orgId,
    department: 'HSE / Safety',
    site: 'North Plant',
  );

  setUp(() {
    MockActionStore.instance.actions.clear();
  });

  group('Issue 1: Manager Action Register Strict Isolation', () {
    test('1.1 ActionRecord resolves createdById from creator and profile maps', () {
      final json1 = {
        'id': 'a1',
        'action_number': 'ACT-101',
        'title': 'Test Action 1',
        'description': 'Desc',
        'priority': 'High',
        'status': 'Open',
        'created_by': 'user-123',
      };
      final rec1 = ActionRecord.fromSupabase(json1);
      expect(rec1.createdById, 'user-123');

      final json2 = {
        'id': 'a2',
        'action_number': 'ACT-102',
        'title': 'Test Action 2',
        'description': 'Desc',
        'priority': 'Medium',
        'status': 'Open',
        'created_by': null,
        'creator': {
          'id': 'user-456',
          'full_name': 'Creator Person',
          'email': 'creator@example.com',
        },
      };
      final rec2 = ActionRecord.fromSupabase(json2);
      expect(rec2.createdById, 'user-456');

      final json3 = {
        'id': 'a3',
        'action_number': 'ACT-103',
        'title': 'Test Action 3',
        'description': 'Desc',
        'priority': 'Low',
        'status': 'Open',
        'created_by': '',
        'created_by_profile': {
          'id': 'user-789',
          'full_name': 'Profile Creator',
        },
      };
      final rec3 = ActionRecord.fromSupabase(json3);
      expect(rec3.createdById, 'user-789');
    });

    testWidgets('1.2 Manager Action Register strictly excludes unknown creator and Staff-created actions',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mgrAction = ActionRecord(
        id: 'act-mgr-1',
        actionNumber: 'ACT-MGR-01',
        subject: 'Manager Created Action',
        actionRequired: 'Safety audit by manager',
        division: 'Operations',
        status: 'Open',
        priority: 'High',
        createdById: managerId,
        createdByName: 'Safety Manager',
        assignedToId: staffId,
        assignedTo: 'Test Staff',
      );

      final staffAction = ActionRecord(
        id: 'act-staff-1',
        actionNumber: 'ACT-STF-01',
        subject: 'Staff Created Action',
        actionRequired: 'Observation by staff',
        division: 'Operations',
        status: 'Open',
        priority: 'Medium',
        createdById: staffId,
        createdByName: 'Test Staff',
        assignedToId: staffId,
        assignedTo: 'Test Staff',
      );

      final unknownAction = ActionRecord(
        id: 'act-unk-1',
        actionNumber: 'ACT-UNK-01',
        subject: 'Unknown Creator Action',
        actionRequired: 'Unknown author',
        division: 'Operations',
        status: 'Open',
        priority: 'Low',
        createdById: '',
        createdByName: '',
        assignedToId: staffId,
        assignedTo: 'Test Staff',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ManagerDashboardScreen(
              userProfile: managerProfile,
              managerContext: managerContext,
              initialActions: [mgrAction, staffAction, unknownAction],
              initialMyActions: const [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Action Register
      await tester.tap(find.byKey(const ValueKey('sidebar_item_Action Register')));
      await tester.pumpAndSettle();

      // Manager-created action must be visible
      expect(find.text('Manager Created Action'), findsOneWidget);

      // Staff-created action must be strictly EXCLUDED
      expect(find.text('Staff Created Action'), findsNothing);

      // Unknown-creator action must be strictly EXCLUDED
      expect(find.text('Unknown Creator Action'), findsNothing);
    });
  });

  group('Issue 2: Closed Action Delete Button in Staff My Actions', () {
    testWidgets('2.1 Closed assigned action displays Delete button, Open action does not',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final closedAction = ActionRecord(
        id: 'act-closed-1',
        actionNumber: 'ACT-CLS-01',
        subject: 'Closed Task for Staff',
        actionRequired: 'Completed inspection',
        division: 'Operations',
        status: 'Closed',
        priority: 'Medium',
        createdById: managerId,
        createdByName: 'Safety Manager',
        assignedToId: staffId,
        assignedTo: 'Test Staff',
        primaryAssignee: ActionPersonReference(
          personId: staffId,
          name: 'Test Staff',
          email: 'staff@sobha.com',
          type: PersonType.internalUser,
        ),
      );

      final openAction = ActionRecord(
        id: 'act-open-1',
        actionNumber: 'ACT-OPN-01',
        subject: 'Open Task for Staff',
        actionRequired: 'Pending task',
        division: 'Operations',
        status: 'Open',
        priority: 'High',
        createdById: managerId,
        createdByName: 'Safety Manager',
        assignedToId: staffId,
        assignedTo: 'Test Staff',
        primaryAssignee: ActionPersonReference(
          personId: staffId,
          name: 'Test Staff',
          email: 'staff@sobha.com',
          type: PersonType.internalUser,
        ),
      );

      MockActionStore.instance.add(closedAction);
      MockActionStore.instance.add(openAction);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkerDashboardScreen(
              userProfile: staffProfile,
              initialNavIndex: 1, // My Actions
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Both actions should be in My Actions
      expect(find.text('Closed Task for Staff'), findsOneWidget);
      expect(find.text('Open Task for Staff'), findsOneWidget);

      // Delete button must exist ONLY for closed action
      final deleteButtons = find.widgetWithText(OutlinedButton, 'Delete');
      expect(deleteButtons, findsOneWidget);
    });

    testWidgets('2.2 Creator-only match does NOT grant delete permission through My Actions',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Staff created this action, but assigned it to another staff member (not assigned to self)
      final createdByStaffAssignedToOther = ActionRecord(
        id: 'act-creator-other-1',
        actionNumber: 'ACT-CR-01',
        subject: 'Staff Created Action Assigned to Other',
        actionRequired: 'Task for colleague',
        division: 'Operations',
        status: 'Closed',
        priority: 'Medium',
        createdById: staffId,
        createdByName: 'Test Staff',
        assignedToId: 'colleague-staff-uuid',
        assignedTo: 'Colleague Staff',
        primaryAssignee: ActionPersonReference(
          personId: 'colleague-staff-uuid',
          name: 'Colleague Staff',
          email: 'colleague@sobha.com',
          type: PersonType.internalUser,
        ),
      );

      MockActionStore.instance.add(createdByStaffAssignedToOther);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkerDashboardScreen(
              userProfile: staffProfile,
              initialNavIndex: 1, // My Actions
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // In My Actions, this action is not assigned to staff, so Delete button must NOT appear
      final deleteButtons = find.widgetWithText(OutlinedButton, 'Delete');
      expect(deleteButtons, findsNothing);
    });
  });

  group('Issue 3: Action Register Selection and Soft-Delete', () {
    testWidgets('3.1 Checkboxes select items cleanly and Select All selects visible actions',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final actionA = ActionRecord(
        id: 'act-a',
        actionNumber: 'ACT-A-01',
        subject: 'Staff Action Alpha',
        actionRequired: 'Alpha observation',
        division: 'Operations',
        status: 'Closed',
        priority: 'High',
        createdById: staffId,
        createdByName: 'Test Staff',
        assignedToId: staffId,
        assignedTo: 'Test Staff',
      );

      final actionB = ActionRecord(
        id: 'act-b',
        actionNumber: 'ACT-B-01',
        subject: 'Staff Action Beta',
        actionRequired: 'Beta observation',
        division: 'Operations',
        status: 'Closed',
        priority: 'Medium',
        createdById: staffId,
        createdByName: 'Test Staff',
        assignedToId: staffId,
        assignedTo: 'Test Staff',
      );

      MockActionStore.instance.add(actionA);
      MockActionStore.instance.add(actionB);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkerDashboardScreen(
              userProfile: staffProfile,
              initialNavIndex: 12, // Staff Action Register
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Staff Action Alpha'), findsOneWidget);
      expect(find.text('Staff Action Beta'), findsOneWidget);

      // Initially no banner
      expect(find.textContaining('selected'), findsNothing);

      // Checkboxes exist in table
      final rowCheckboxes = find.byType(Checkbox);
      expect(rowCheckboxes, findsWidgets);

      // Tap on the checkbox for the first action (index 1 is first row, index 0 is header select all)
      await tester.tap(rowCheckboxes.at(1));
      await tester.pumpAndSettle();

      // Selection banner should show 1 action selected
      expect(find.text('1 action selected'), findsOneWidget);
      expect(find.text('Delete Selected'), findsOneWidget);

      // Tap Select All checkbox (header checkbox)
      await tester.tap(rowCheckboxes.first);
      await tester.pumpAndSettle();

      expect(find.text('2 actions selected'), findsOneWidget);

      // Click Delete Selected
      await tester.tap(find.text('Delete Selected'));
      await tester.pumpAndSettle();

      // Confirmation dialog must appear
      expect(find.text('Delete Selected Actions'), findsOneWidget);
      expect(find.text('Delete 2 Actions'), findsOneWidget);

      // Confirm deletion
      await tester.tap(find.text('Delete 2 Actions'));
      await tester.pumpAndSettle();

      // Successfully deleted banner
      expect(find.text('Successfully deleted 2 actions.'), findsOneWidget);
    });
  });
}
