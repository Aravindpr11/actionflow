import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const orgId = Organization.sobhaId;
  const staffId = 'staff-bulk-uuid-1111';
  const managerId = 'manager-bulk-uuid-2222';

  final staffProfile = UserProfile(
    id: staffId,
    name: 'A. Worker',
    email: 'worker@sobha.com',
    phone: '+971 50 111 2222',
    designation: 'HSE Officer',
    role: 'staff',
    organizationId: orgId,
    department: 'HSE',
    site: 'Downtown Tower',
  );

  final managerProfile = UserProfile(
    id: managerId,
    name: 'M. Manager',
    email: 'manager@sobha.com',
    phone: '+971 50 333 4444',
    designation: 'HSE Manager',
    role: 'manager',
    organizationId: orgId,
    department: 'HSE',
    site: 'Downtown Tower',
  );

  final now = DateTime.now();
  String fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  ActionRecord createAction({
    required String id,
    required String actionNumber,
    required String subject,
    String status = 'Open',
    int percentComplete = 0,
    String? createdById,
    String? assignedTo,
    String? assignedToId,
    List<ActionAssigneeRecord> assignees = const [],
    List<ActionContributorRecord> contributors = const [],
    DateTime? createdAt,
  }) {
    final created = createdAt ?? now;
    return ActionRecord(
      id: id,
      actionNumber: actionNumber,
      organizationId: orgId,
      departmentId: 'dept-hse',
      department: 'HSE',
      siteId: 'site-dt',
      site: 'Downtown Tower',
      division: 'Construction',
      section: 'Safety',
      subject: subject,
      description: 'Test description for $subject',
      actionRequired: 'Test action required',
      priority: 'High',
      status: status,
      percentComplete: percentComplete,
      assignedTo: assignedTo ?? 'A. Worker',
      assignedToId: assignedToId ?? staffId,
      assignedBy: 'M. Manager',
      createdById: createdById ?? managerId,
      dateRaised: fmt(created),
      targetDate: fmt(created.add(const Duration(days: 7))),
      createdAt: created,
      assignees: assignees,
      contributors: contributors,
    );
  }

  group('Safe Soft Deletion & Model Logic', () {
    test('ActionRecord.isDeleted correctly identifies deleted actions', () {
      final activeAction = createAction(
        id: 'act-live',
        actionNumber: 'ACT-9001',
        subject: 'Live Action',
        status: 'Open',
      );
      final deletedAction = createAction(
        id: 'act-dead',
        actionNumber: 'ACT-9002',
        subject: 'Soft Deleted Action',
        status: 'Deleted',
      );
      final lowercaseDeleted = createAction(
        id: 'act-dead-lower',
        actionNumber: 'ACT-9003',
        subject: 'Soft Deleted Action Lowercase',
        status: 'deleted',
      );

      expect(activeAction.isDeleted, isFalse);
      expect(deletedAction.isDeleted, isTrue);
      expect(lowercaseDeleted.isDeleted, isTrue);
    });

    test('ActionService.deleteActionsBulk soft-deletes actions in MockActionStore', () async {
      final store = MockActionStore.instance;
      final a1 = createAction(id: 'del-1', actionNumber: 'ACT-8001', subject: 'Delete 1');
      final a2 = createAction(id: 'del-2', actionNumber: 'ACT-8002', subject: 'Delete 2');
      final a3 = createAction(id: 'keep-1', actionNumber: 'ACT-8003', subject: 'Keep 1');

      store.actions.clear();
      store.actions.addAll([a1, a2, a3]);

      final res = await ActionService.instance.deleteActionsBulk(['del-1', 'del-2']);

      expect(res.success, isTrue);
      expect(res.deletedCount, equals(2));
      expect(res.failedIds, isEmpty);
      expect(store.actions.any((a) => a.id == 'del-1'), isFalse);
      expect(store.actions.any((a) => a.id == 'del-2'), isFalse);
      expect(store.actions.any((a) => a.id == 'keep-1'), isTrue);
    });
  });

  group('Manager Action Register - Bulk Deletion Toolbar & Confirmation', () {
    testWidgets('Manager Portal shows Delete Selected button and confirmation dialog', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final a1 = createAction(id: 'mgr-del-1', actionNumber: 'ACT-7001', subject: 'Manager Action 1');
      final a2 = createAction(id: 'mgr-del-2', actionNumber: 'ACT-7002', subject: 'Manager Action 2');

      final store = MockActionStore.instance;
      store.actions.clear();
      store.actions.addAll([a1, a2]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ManagerDashboardScreen(
              userProfile: managerProfile,
              initialActions: [a1, a2],
              initialMyActions: const [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Action Register (Nav index 1)
      final actionRegisterNav = find.text('Action Register');
      expect(actionRegisterNav, findsWidgets);
      await tester.tap(actionRegisterNav.first);
      await tester.pumpAndSettle();

      // Initially no toolbar
      expect(find.text('Delete Selected'), findsNothing);

      // Select row 1 checkbox
      final checkboxes = find.byType(Checkbox);
      expect(checkboxes, findsWidgets);
      // Tap row 1 checkbox (index 1, as index 0 is select all header)
      await tester.tap(checkboxes.at(1));
      await tester.pumpAndSettle();

      // Selection toolbar appears with Delete Selected button
      expect(find.text('1 action selected'), findsOneWidget);
      expect(find.text('Delete Selected'), findsOneWidget);
      expect(find.text('Deselect All'), findsOneWidget);

      // Tap Delete Selected to trigger confirmation dialog
      await tester.tap(find.text('Delete Selected'));
      await tester.pumpAndSettle();

      // Verify dialog message
      expect(find.text('Delete Selected Actions'), findsOneWidget);
      expect(
        find.textContaining('removed from active views. Their audit history will be retained.'),
        findsOneWidget,
      );

      // Tap Cancel in dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog dismisses and action remains
      expect(find.text('Delete Selected Actions'), findsNothing);
      expect(find.text('ACT-7001'), findsOneWidget);
    });
  });

  group('Staff My Actions - Bulk Delete, Permissions & Guarding', () {
    testWidgets('Staff can select own action but cannot select forwarded action for deletion', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Staff created action (allowed)
      final ownAction = createAction(
        id: 'stf-own-1',
        actionNumber: 'ACT-6001',
        subject: 'Own Staff Action',
        createdById: staffId,
      );

      // Forwarded action (forbidden to delete)
      final forwardedAction = createAction(
        id: 'stf-fwd-1',
        actionNumber: 'ACT-6002',
        subject: 'Forwarded Action To Staff',
        createdById: 'someone-else-id',
        assignedTo: 'Other Assignee',
        assignedToId: 'other-staff-id',
        createdAt: now.subtract(const Duration(hours: 2)),
        contributors: [
          ActionContributorRecord(
            id: 'cont-1',
            actionId: 'stf-fwd-1',
            profileId: staffId,
            profileName: 'A. Worker',
            profileEmail: 'worker@sobha.com',
            notes: 'Supporting inspector',
            createdAt: now.subtract(const Duration(hours: 1)),
          ),
        ],
      );

      final store = MockActionStore.instance;
      store.actions.clear();
      store.actions.addAll([ownAction, forwardedAction]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkerDashboardScreen(
              userProfile: staffProfile,
              initialNavIndex: 1, // My Actions tab
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify actions exist in table
      expect(find.text('ACT-6001'), findsOneWidget);
      expect(find.text('ACT-6002'), findsOneWidget);

      // Own action has Delete button
      expect(find.widgetWithText(OutlinedButton, 'Delete'), findsOneWidget);

      final checkboxes = find.byType(Checkbox);
      expect(checkboxes, findsWidgets);

      // Try selecting forwarded action ACT-6002 (index 2: 0 is select-all, 1 is ACT-6001, 2 is ACT-6002)
      await tester.tap(checkboxes.at(2));
      await tester.pumpAndSettle();

      // Guard blocks selection and shows warning SnackBar
      expect(
        find.textContaining('Forwarded actions cannot be selected for deletion.'),
        findsOneWidget,
      );
      expect(find.text('1 action selected'), findsNothing);

      // Now select own action ACT-6001 (index 1)
      await tester.tap(checkboxes.at(1));
      await tester.pumpAndSettle();

      // Toolbar appears with Delete Selected button
      expect(find.text('1 action selected'), findsOneWidget);
      expect(find.text('Delete Selected'), findsOneWidget);
      expect(find.text('Deselect All'), findsOneWidget);

      // Click Delete Selected
      await tester.tap(find.text('Delete Selected'));
      await tester.pumpAndSettle();

      // Verify confirmation dialog
      expect(find.text('Delete Selected Actions'), findsOneWidget);
      expect(
        find.textContaining('removed from active views. Their audit history will be retained.'),
        findsOneWidget,
      );

      // Confirm deletion
      await tester.tap(find.text('Delete 1 Actions'));
      await tester.pumpAndSettle();

      // Action is deleted and removed from view
      expect(find.text('ACT-6001'), findsNothing);
      expect(find.text('Successfully deleted 1 action.'), findsOneWidget);
    });
  });

  group('Staff Pending Updates - UI Alignment & Responsive Layout', () {
    testWidgets('Staff Pending Updates displays DataTable on desktop (>=768px)', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final pending1 = createAction(
        id: 'pend-1',
        actionNumber: 'ACT-5001',
        subject: 'Pending Update High Priority',
        status: 'In Progress',
        percentComplete: 45,
      );
      final pending2 = createAction(
        id: 'pend-2',
        actionNumber: 'ACT-5002',
        subject: 'Awaiting Manager Review Action',
        status: 'Pending Review',
        percentComplete: 100,
      );

      final store = MockActionStore.instance;
      store.actions.clear();
      store.actions.addAll([pending1, pending2]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkerDashboardScreen(
              userProfile: staffProfile,
              initialNavIndex: 3, // Pending Updates tab
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // On desktop, Pending Updates renders a DataTable
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('Action ID'), findsOneWidget);
      expect(find.text('Project / Site'), findsOneWidget);
      expect(find.text('Priority'), findsOneWidget);
      expect(find.text('% Complete'), findsOneWidget);
      expect(find.text('Next Follow-up'), findsOneWidget);

      // Verify row items
      expect(find.text('ACT-5001'), findsOneWidget);
      expect(find.text('ACT-5002'), findsOneWidget);

      // Verify buttons: Details is present on both
      expect(find.widgetWithText(OutlinedButton, 'Details'), findsNWidgets(2));

      // ACT-5001 has Submit Update
      expect(find.widgetWithText(ElevatedButton, 'Submit Update'), findsOneWidget);

      // ACT-5002 is awaiting review, has View Status
      expect(find.widgetWithText(OutlinedButton, 'View Status'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);
    });

    testWidgets('Staff Pending Updates displays responsive cards on mobile (<768px)', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final pending1 = createAction(
        id: 'pend-mob-1',
        actionNumber: 'ACT-5003',
        subject: 'Mobile Card Pending Action',
        status: 'In Progress',
        percentComplete: 60,
      );

      final store = MockActionStore.instance;
      store.actions.clear();
      store.actions.addAll([pending1]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkerDashboardScreen(
              userProfile: staffProfile,
              initialNavIndex: 3, // Pending Updates tab
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // On mobile, DataTable is NOT rendered; responsive cards are rendered
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('ACT-5003'), findsOneWidget);
      expect(find.text('Mobile Card Pending Action'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Details'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Submit Update'), findsOneWidget);
    });
  });
}
