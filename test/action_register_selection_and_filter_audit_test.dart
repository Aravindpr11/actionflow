import 'package:action_flow/features/auth/models/manager_scope_item.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/models/organization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const orgId = Organization.sobhaId;
  const managerId = 'mgr-test-uuid-1111';

  final managerProfile = UserProfile(
    id: managerId,
    name: 'A. Operations Manager',
    email: 'manager@sobha.com',
    phone: '+971 50 111 2222',
    designation: 'Operations Manager',
    role: 'manager',
    organizationId: orgId,
    department: 'Operations',
    site: 'North Plant',
  );

  final managerContext = ManagerContext(
    authUserId: managerId,
    profile: managerProfile,
    organizationId: orgId,
    organizationName: Organization.sobhaName,
    scopes: const [
      ManagerScopeItem(
        departmentId: 'dept-ops',
        departmentName: 'Operations',
        siteId: 'site-np',
        siteName: 'North Plant',
      ),
      ManagerScopeItem(
        departmentId: 'dept-hse',
        departmentName: 'HSE',
        siteId: 'site-wh',
        siteName: 'Warehouse B',
      ),
    ],
  );

  final now = DateTime.now();
  final yesterday = now.subtract(const Duration(days: 1));
  final lastWeek = now.subtract(const Duration(days: 7));
  final futureWeek = now.add(const Duration(days: 7));

  String fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  final sampleActions = [
    // 1. Open action, Critical priority, North Plant, Operations
    ActionRecord(
      id: 'act-001',
      actionNumber: 'ACT-1001',
      organizationId: orgId,
      departmentId: 'dept-ops',
      department: 'Operations',
      siteId: 'site-np',
      site: 'North Plant',
      division: 'Commercial',
      section: 'Zone 1',
      subject: 'Scaffolding safety inspection in Zone 1',
      description: 'Critical scaffolding defect needing immediate attention',
      actionRequired: 'Inspect and replace damaged scaffold couplings',
      priority: 'Critical',
      status: 'Open',
      percentComplete: 10,
      assignedTo: 'John Doe',
      assignedToId: 'usr-jd-01',
      assignedBy: 'A. Operations Manager',
      dateRaised: fmt(yesterday),
      targetDate: fmt(futureWeek),
      createdAt: yesterday,
    ),
    // 2. In Progress action, High priority, Warehouse B, HSE, Overdue by target date
    ActionRecord(
      id: 'act-002',
      actionNumber: 'ACT-1002',
      organizationId: orgId,
      departmentId: 'dept-hse',
      department: 'HSE',
      siteId: 'site-wh',
      site: 'Warehouse B',
      division: 'Residential',
      section: 'Dock 2',
      subject: 'Fire extinguisher pressure check',
      description: 'Monthly inspection overdue',
      actionRequired: 'Re-certify all pressure gauges',
      priority: 'High',
      status: 'In Progress',
      percentComplete: 60,
      assignedTo: 'Jane Smith',
      assignedToId: 'usr-js-02',
      assignedBy: 'A. Operations Manager',
      dateRaised: fmt(lastWeek),
      targetDate: fmt(yesterday), // Overdue!
      createdAt: lastWeek,
    ),
    // 3. Pending Review action, 100% complete, North Plant, Operations
    ActionRecord(
      id: 'act-003',
      actionNumber: 'ACT-1003',
      organizationId: orgId,
      departmentId: 'dept-ops',
      department: 'Operations',
      siteId: 'site-np',
      site: 'North Plant',
      division: 'Commercial',
      section: 'Turbine Hall',
      subject: 'Emergency lighting system upgrade',
      description: 'Installed new battery backups',
      actionRequired: 'Verify illumination levels during blackout simulation',
      priority: 'Medium',
      status: 'Pending Review',
      percentComplete: 100,
      assignedTo: 'Bob Worker',
      assignedToId: 'usr-bw-03',
      assignedBy: 'A. Operations Manager',
      dateRaised: fmt(yesterday),
      targetDate: fmt(now),
      createdAt: yesterday,
    ),
    // 4. Closed action, Low priority, Warehouse B, HSE
    ActionRecord(
      id: 'act-004',
      actionNumber: 'ACT-1004',
      organizationId: orgId,
      departmentId: 'dept-hse',
      department: 'HSE',
      siteId: 'site-wh',
      site: 'Warehouse B',
      division: 'Commercial',
      section: 'Pallet Racks',
      subject: 'Forklift operator refresher training',
      description: 'Completed refresher module for warehouse operators',
      actionRequired: 'Certificates issued and verified',
      priority: 'Low',
      status: 'Closed',
      percentComplete: 100,
      assignedTo: 'Alice Green',
      assignedToId: 'usr-ag-04',
      assignedBy: 'A. Operations Manager',
      dateRaised: fmt(lastWeek),
      targetDate: fmt(yesterday),
      closeDate: fmt(now),
      closedAt: now,
      createdAt: lastWeek,
    ),
    // 5. Forwarded action: Manager forwarded to contributor
    ActionRecord(
      id: 'act-005',
      actionNumber: 'ACT-1005',
      organizationId: orgId,
      departmentId: 'dept-ops',
      department: 'Operations',
      siteId: 'site-np',
      site: 'North Plant',
      division: 'Commercial',
      section: 'Substation B',
      subject: 'Electrical panel thermography survey',
      description: 'Thermal imaging scan required for transformers',
      actionRequired: 'Forwarded to electrical specialist for scanning',
      priority: 'Critical',
      status: 'In Progress',
      percentComplete: 40,
      assignedTo: 'A. Operations Manager',
      assignedToId: managerId,
      assignedBy: 'HSE Director',
      dateRaised: fmt(now),
      targetDate: fmt(futureWeek),
      createdAt: now,
      contributors: [
        ActionContributorRecord(
          id: 'contrib-01',
          actionId: 'act-005',
          profileId: 'usr-elec-99',
          profileName: 'Farhan Electrical',
          profileEmail: 'farhan@sobha.com',
          addedBy: managerId,
          addedByName: 'A. Operations Manager',
          notes: 'Assigned thermal scanning',
        ),
      ],
    ),
  ];

  Widget buildManagerDashboard({
    Size size = const Size(1400, 900),
    List<ActionRecord>? actions,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: ManagerDashboardScreen(
            userProfile: managerProfile,
            managerContext: managerContext,
            initialActions: actions ?? sampleActions,
            initialMyActions: (actions ?? sampleActions)
                .where((a) =>
                    a.assignedToId == managerId ||
                    a.contributors.any((c) => c.profileId == managerId))
                .toList(),
          ),
        ),
      ),
    );
  }

  group('Action Register Selection & Checkbox Tests', () {
    testWidgets('Renders checkbox column and handles individual selection', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildManagerDashboard());
      await tester.pumpAndSettle();

      // Navigate to Action Register (Nav index 1)
      final actionRegisterNav = find.text('Action Register');
      expect(actionRegisterNav, findsWidgets);
      await tester.tap(actionRegisterNav.first);
      await tester.pumpAndSettle();

      // Checkboxes exist in the table
      final checkboxes = find.byType(Checkbox);
      expect(checkboxes, findsWidgets);

      // Initially no selection banner
      expect(find.textContaining('selected'), findsNothing);

      // Select first row checkbox (index 1, since index 0 is header checkbox)
      await tester.tap(checkboxes.at(1));
      await tester.pumpAndSettle();

      // Selection banner appears showing 1 action selected
      expect(find.text('1 action selected'), findsOneWidget);
      expect(find.text('Deselect All'), findsOneWidget);
      expect(find.text('Export Selected'), findsOneWidget);

      // Select second row checkbox
      await tester.tap(checkboxes.at(2));
      await tester.pumpAndSettle();

      // Shows 2 actions selected
      expect(find.text('2 actions selected'), findsOneWidget);

      // Deselect second row checkbox
      await tester.tap(checkboxes.at(2));
      await tester.pumpAndSettle();
      expect(find.text('1 action selected'), findsOneWidget);

      // Tap Deselect All button
      await tester.tap(find.text('Deselect All'));
      await tester.pumpAndSettle();

      // Selection banner dismissed
      expect(find.textContaining('selected'), findsNothing);
    });

    testWidgets('Header checkbox Select All and Deselect All for visible actions', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildManagerDashboard());
      await tester.pumpAndSettle();

      // Navigate to Action Register
      await tester.tap(find.text('Action Register').first);
      await tester.pumpAndSettle();

      // Header checkbox is the first Checkbox widget
      final headerCheckbox = find.byType(Checkbox).first;

      // Tap Header checkbox -> selects all 5 visible actions
      await tester.tap(headerCheckbox);
      await tester.pumpAndSettle();

      expect(find.text('5 actions selected'), findsOneWidget);

      // Tap Header checkbox again -> deselects all visible actions
      await tester.tap(headerCheckbox);
      await tester.pumpAndSettle();

      expect(find.textContaining('actions selected'), findsNothing);
    });

    testWidgets('Selection is retained across filter and search changes', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildManagerDashboard());
      await tester.pumpAndSettle();

      // Navigate to Action Register
      await tester.tap(find.text('Action Register').first);
      await tester.pumpAndSettle();

      // Select ACT-1001 (row 1)
      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.pumpAndSettle();
      expect(find.text('1 action selected'), findsOneWidget);

      // Now filter by search query "Scaffolding"
      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'Scaffolding');
      await tester.pumpAndSettle();

      // ACT-1001 is still selected and visible
      expect(find.text('1 action selected'), findsOneWidget);
      expect(find.text('ACT-1001'), findsOneWidget);

      // Clear search query
      await tester.enterText(searchField, '');
      await tester.pumpAndSettle();

      // ACT-1001 remains selected
      expect(find.text('1 action selected'), findsOneWidget);
    });
  });

  group('Action Register Filter Audit Tests', () {
    testWidgets('Search query matches ID, subject, and description', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildManagerDashboard());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Action Register').first);
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField).first;

      // 1. Search by ID
      await tester.enterText(searchField, '1002');
      await tester.pumpAndSettle();
      expect(find.text('ACT-1002'), findsOneWidget);
      expect(find.text('ACT-1001'), findsNothing);

      // 2. Search by subject keyword
      await tester.enterText(searchField, 'lighting');
      await tester.pumpAndSettle();
      expect(find.text('ACT-1003'), findsOneWidget);
      expect(find.text('ACT-1002'), findsNothing);

      // 3. Search by description keyword
      await tester.enterText(searchField, 'couplings');
      await tester.pumpAndSettle();
      expect(find.text('ACT-1001'), findsOneWidget);

      // Clear search
      await tester.enterText(searchField, '');
      await tester.pumpAndSettle();
      expect(find.text('ACT-1001'), findsOneWidget);
      expect(find.text('ACT-1002'), findsOneWidget);
    });

    testWidgets('Status filter handles Overdue, Closed, Open, Pending Review', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildManagerDashboard());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Action Register').first);
      await tester.pumpAndSettle();

      // Find Status dropdown
      final statusDropdown = find.text('All Status');
      expect(statusDropdown, findsWidgets);
      await tester.tap(statusDropdown.first);
      await tester.pumpAndSettle();

      // Filter by Overdue (ACT-1002 is overdue because targetDate was yesterday)
      await tester.tap(find.text('Overdue').last);
      await tester.pumpAndSettle();

      expect(find.text('ACT-1002'), findsOneWidget);
      expect(find.text('ACT-1001'), findsNothing);

      // Filter by Closed
      await tester.tap(find.text('Overdue').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Closed').last);
      await tester.pumpAndSettle();

      expect(find.text('ACT-1004'), findsOneWidget);
      expect(find.text('ACT-1002'), findsNothing);

      // Filter by Pending Review
      await tester.tap(find.text('Closed').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pending Review').last);
      await tester.pumpAndSettle();

      expect(find.text('ACT-1003'), findsOneWidget);
      expect(find.text('ACT-1004'), findsNothing);
    });

    testWidgets('Forwarded filter: Forwarded Only vs Direct Only vs Forwarded by Me', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildManagerDashboard());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Action Register').first);
      await tester.pumpAndSettle();

      // Forwarded filter dropdown
      final fwdDropdown = find.text('All Actions');
      expect(fwdDropdown, findsWidgets);
      await tester.tap(fwdDropdown.first);
      await tester.pumpAndSettle();

      // Forwarded Only (only ACT-1005 has contributors)
      await tester.tap(find.text('Forwarded Only').last);
      await tester.pumpAndSettle();

      expect(find.text('ACT-1005'), findsOneWidget);
      expect(find.text('ACT-1001'), findsNothing);

      // Direct Only
      await tester.tap(find.text('Forwarded Only').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Direct Only').last);
      await tester.pumpAndSettle();

      expect(find.text('ACT-1001'), findsOneWidget);
      expect(find.text('ACT-1005'), findsNothing);
    });

    testWidgets('Combined filters: Priority Critical + Site North Plant', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildManagerDashboard());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Action Register').first);
      await tester.pumpAndSettle();

      // Filter Priority = Critical
      await tester.tap(find.text('All Priority').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Critical').last);
      await tester.pumpAndSettle();

      // Should show ACT-1001 and ACT-1005 (both are Critical)
      expect(find.text('ACT-1001'), findsOneWidget);
      expect(find.text('ACT-1005'), findsOneWidget);
      expect(find.text('ACT-1002'), findsNothing);

      // Filter Site = Warehouse B (neither ACT-1001 nor ACT-1005 is Warehouse B)
      await tester.tap(find.text('All Sites').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Warehouse B').last);
      await tester.pumpAndSettle();

      // Zero actions matching both Critical and Warehouse B
      expect(find.text('No actions matching the selected filters'), findsOneWidget);

      // Tap Clear All in active filter summary
      final clearAllBtn = find.text('Clear All');
      expect(clearAllBtn, findsOneWidget);
      await tester.tap(clearAllBtn);
      await tester.pumpAndSettle();

      // All 5 actions are restored
      expect(find.text('ACT-1001'), findsOneWidget);
      expect(find.text('ACT-1002'), findsOneWidget);
      expect(find.text('ACT-1003'), findsOneWidget);
    });
  });
}

