import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/models/organization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const orgId = Organization.sobhaId;
  const staffId = 'staff-user-uuid-1111';
  const otherStaffId = 'staff-user-uuid-2222';

  final staffProfile = UserProfile(
    id: staffId,
    name: 'R. Kumar',
    email: 'kumar@sobha.com',
    phone: '+971 50 999 8888',
    designation: 'Safety Officer',
    role: 'staff',
    organizationId: orgId,
    department: 'Field Operations',
    site: 'North Plant',
  );

  final now = DateTime.now();
  final yesterday = now.subtract(const Duration(days: 1));
  final futureWeek = now.add(const Duration(days: 7));

  String fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // 1. Direct assignment to R. Kumar (Staff is primary assignee)
  final actionDirect = ActionRecord(
    id: 'staff-act-001',
    actionNumber: 'ACT-2001',
    organizationId: orgId,
    departmentId: 'dept-ops',
    department: 'Field Operations',
    siteId: 'site-np',
    site: 'North Plant',
    division: 'Commercial',
    section: 'Zone 4',
    subject: 'Safety netting installation in Zone 4',
    description: 'Install perimeter safety nets on Level 5',
    actionRequired: 'Secure all brackets and verify tension load',
    priority: 'Critical',
    status: 'In Progress',
    percentComplete: 50,
    assignedTo: 'R. Kumar',
    assignedToId: staffId,
    assignedBy: 'Operations Manager',
    dateRaised: fmt(yesterday),
    targetDate: fmt(futureWeek),
    createdAt: yesterday,
  );

  // 2. Action created by R. Kumar (Staff is Creator - has Edit and Delete permissions)
  final actionCreatedByStaff = ActionRecord(
    id: 'staff-act-002',
    actionNumber: 'ACT-2002',
    organizationId: orgId,
    departmentId: 'dept-ops',
    department: 'Field Operations',
    siteId: 'site-np',
    site: 'North Plant',
    division: 'Commercial',
    section: 'Zone 2',
    subject: 'Temporary ventilation duct repair',
    description: 'Flexible exhaust duct torn near welding booth',
    actionRequired: 'Replace flexible duct section and clamp securely',
    priority: 'Medium',
    status: 'Open',
    percentComplete: 0,
    assignedTo: 'R. Kumar',
    assignedToId: staffId,
    assignedBy: 'R. Kumar',
    createdById: staffId,
    dateRaised: fmt(now),
    targetDate: fmt(futureWeek),
    createdAt: now,
  );

  // 3. Action forwarded to R. Kumar as contributor (Forbidden to Delete!)
  final actionForwardedToStaff = ActionRecord(
    id: 'staff-act-003',
    actionNumber: 'ACT-2003',
    organizationId: orgId,
    departmentId: 'dept-ops',
    department: 'Field Operations',
    siteId: 'site-wh',
    site: 'Warehouse B',
    division: 'Commercial',
    section: 'Loading Dock',
    subject: 'Dock leveler hydraulic line inspection',
    description: 'Forwarded to R. Kumar for supporting inspection',
    actionRequired: 'Check for hydraulic fluid weepage under load',
    priority: 'High',
    status: 'In Progress',
    percentComplete: 25,
    assignedTo: 'S. Supervisor',
    assignedToId: otherStaffId,
    assignedBy: 'Operations Manager',
    dateRaised: fmt(yesterday),
    targetDate: fmt(futureWeek),
    createdAt: yesterday,
    contributors: [
      ActionContributorRecord(
        id: 'contrib-k-01',
        actionId: 'staff-act-003',
        profileId: staffId,
        profileName: 'R. Kumar',
        profileEmail: 'kumar@sobha.com',
        addedBy: otherStaffId,
        addedByName: 'S. Supervisor',
        notes: 'Please inspect dock leveler 3 and 4',
      ),
    ],
  );

  Widget buildStaffDashboard({
    Size size = const Size(1400, 900),
    int initialNavIndex = 1,
  }) {
    final store = MockActionStore.instance;
    store.actions.clear();
    store.actions.addAll([
      actionDirect,
      actionCreatedByStaff,
      actionForwardedToStaff,
    ]);

    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: WorkerDashboardScreen(
            userProfile: staffProfile,
            initialNavIndex: initialNavIndex,
          ),
        ),
      ),
    );
  }

  group('Staff Portal My Actions Table & Selection Tests', () {
    testWidgets(
      'Staff Portal renders DataTable on desktop with all columns and row action buttons',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildStaffDashboard(size: const Size(1400, 900)));
        await tester.pumpAndSettle();

        // On desktop (width 1400), DataTable is rendered
        expect(find.byType(DataTable), findsOneWidget);

        // Required Columns are present in DataTable header
        expect(find.text('Action ID'), findsWidgets);
        expect(find.text('Subject'), findsWidgets);
        expect(find.text('Project / Site'), findsWidgets);
        expect(find.text('Priority'), findsWidgets);
        expect(find.text('Status'), findsWidgets);
        expect(find.text('Target Date'), findsWidgets);
        expect(find.text('% Complete'), findsWidgets);
        expect(find.text('Next Follow-up'), findsWidgets);
        expect(find.text('Action'), findsWidgets);

        // Row action buttons: Details and Update are rendered
        expect(find.text('Details'), findsWidgets);
        expect(find.text('Update'), findsWidgets);

        // Edit button is rendered for actionCreatedByStaff (permitted)
        expect(find.text('Edit'), findsWidgets);

        // Delete button is rendered for actionCreatedByStaff (authorized)
        expect(find.text('Delete'), findsWidgets);
      },
    );

    testWidgets(
      'Staff Portal row checkboxes toggle selection and header checkbox selects all visible actions',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildStaffDashboard(size: const Size(1400, 900)));
        await tester.pumpAndSettle();

        // Switch to My Actions tab
        await tester.tap(find.text('My Actions').first);
        await tester.pumpAndSettle();

        final checkboxes = find.byType(Checkbox);
        expect(checkboxes, findsWidgets);

        // Initially no selection banner
        expect(find.textContaining('actions selected'), findsNothing);

        // Tap first row checkbox (index 1)
        await tester.tap(checkboxes.at(1));
        await tester.pumpAndSettle();

        // Selection banner appears
        expect(find.text('1 action selected'), findsOneWidget);
        expect(find.text('Deselect All'), findsOneWidget);

        // Tap Deselect All button
        await tester.tap(find.text('Deselect All'));
        await tester.pumpAndSettle();

        expect(find.textContaining('selected'), findsNothing);

        // Header checkbox (index 0) selects all visible
        await tester.tap(checkboxes.first);
        await tester.pumpAndSettle();

        expect(find.textContaining('actions selected'), findsOneWidget);

        // Header checkbox tap again deselects all
        await tester.tap(checkboxes.first);
        await tester.pumpAndSettle();

        expect(find.textContaining('actions selected'), findsNothing);
      },
    );

    testWidgets(
      'Staff Portal renders responsive card layout on narrow mobile screen (< 768px)',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildStaffDashboard(size: const Size(400, 800)));
        await tester.pumpAndSettle();

        // On mobile (< 768px), DataTable is not rendered; responsive cards are rendered
        expect(find.byType(DataTable), findsNothing);

        // Mobile card contains Checkbox and Action details
        expect(find.byType(Checkbox), findsWidgets);
        expect(find.text('Details'), findsWidgets);
        expect(find.text('Update Action'), findsWidgets);
      },
    );
  });
}
