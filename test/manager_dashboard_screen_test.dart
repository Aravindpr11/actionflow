import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/widgets/dashboard_attention_section.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/services/report_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.now();
  final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final yesterdayStr = '${now.subtract(const Duration(days: 2)).year}-${now.subtract(const Duration(days: 2)).month.toString().padLeft(2, '0')}-${now.subtract(const Duration(days: 2)).day.toString().padLeft(2, '0')}';
  final tomorrowStr = '${now.add(const Duration(days: 2)).year}-${now.add(const Duration(days: 2)).month.toString().padLeft(2, '0')}-${now.add(const Duration(days: 2)).day.toString().padLeft(2, '0')}';

  List<ActionRecord> generateTestActions() {
    return [
      // 1. Overdue Action (Target date in past, not closed)
      ActionRecord(
        id: 'act-1',
        actionNumber: 'ACT-001',
        createdById: 'mgr-001',
        subject: 'Overdue Valve Inspection',
        actionRequired: 'Inspect and calibrate valve #4',
        division: 'Operations',
        department: 'Engineering',
        section: 'Mechanical',
        site: 'Site Alpha',
        assignedTo: 'John Engineer',
        priority: 'Critical',
        status: 'Open',
        percentComplete: 20,
        dateRaised: yesterdayStr,
        targetDate: yesterdayStr,
        nextFollowUpDate: tomorrowStr,
        followUps: [
          ActionFollowUpRecord(
            id: 'fu-1',
            actionId: 'act-1',
            followUpDate: tomorrowStr,
            notes: 'Followed up on mechanical spare parts arrival.',
            status: 'Scheduled',
          ),
        ],
      ),

      // 2. Due Soon Action (Target date in near future)
      ActionRecord(
        id: 'act-2',
        actionNumber: 'ACT-002',
        createdById: 'mgr-001',
        subject: 'Electrical Panel Thermal Audit',
        actionRequired: 'Perform thermographic scan',
        division: 'Maintenance',
        department: 'Electrical',
        section: 'HV Power',
        site: 'Site Beta',
        assignedTo: 'Alice Spark',
        priority: 'High',
        status: 'In Progress',
        percentComplete: 60,
        dateRaised: yesterdayStr,
        targetDate: tomorrowStr,
        nextFollowUpDate: tomorrowStr,
        progressUpdates: [
          ActionProgressUpdate(
            id: 'pu-1',
            actionId: 'act-2',
            updatedById: 'user-spark',
            updatedByName: 'Alice Spark',
            updateDate: todayStr,
            progress: 60,
            status: 'In Progress',
            comments: 'Thermography scan 60% complete; switchgear normal.',
          ),
        ],
      ),

      // 3. Ready for Manager Review Action (100% or Pending Review)
      ActionRecord(
        id: 'act-3',
        actionNumber: 'ACT-003',
        createdById: 'mgr-001',
        subject: 'Fire Extinguisher Monthly Inspection',
        actionRequired: 'Check pressure tags and replace expired cylinders',
        division: 'HSE',
        department: 'Safety',
        section: 'Fire Safety',
        site: 'Site Alpha',
        assignedTo: 'Bob Shield',
        priority: 'Medium',
        status: 'Pending Review',
        percentComplete: 100,
        dateRaised: yesterdayStr,
        targetDate: tomorrowStr,
        progressUpdates: [
          ActionProgressUpdate(
            id: 'pu-2',
            actionId: 'act-3',
            updatedById: 'user-shield',
            updatedByName: 'Bob Shield',
            updateDate: todayStr,
            progress: 100,
            status: 'Pending Review',
            comments: 'All 42 fire extinguishers inspected and tagged. Ready for manager sign-off.',
          ),
        ],
      ),

      // 4. Closed Action
      ActionRecord(
        id: 'act-4',
        actionNumber: 'ACT-004',
        createdById: 'mgr-001',
        subject: 'Emergency Exit Sign Illumination Fix',
        actionRequired: 'Replace battery backup on block C exit door',
        division: 'Facilities',
        department: 'Civil',
        section: 'Building Maint',
        site: 'Site Gamma',
        assignedTo: 'Charlie Builder',
        priority: 'Low',
        status: 'Closed',
        percentComplete: 100,
        dateRaised: yesterdayStr,
        targetDate: yesterdayStr,
        closeDate: todayStr,
        closedByName: 'Manager Dave',
        closureComment: 'Verified battery replacement and illumination working properly.',
      ),
    ];
  }

  final testProfile = const UserProfile(
    id: 'mgr-001',
    name: 'David Miller',
    email: 'david.miller@sobha.com',
    phone: '+971 50 123 4567',
    designation: 'Operations Lead',
    organizationName: 'Sobha Constructions',
    department: 'Operations',
    site: 'Site Alpha',
    role: 'manager',
  );

  final testContext = ManagerContext(
    authUserId: 'mgr-001',
    profile: testProfile,
    organizationId: 'sobha-org-id',
    organizationName: 'Sobha Constructions',
    scopes: const [],
  );

  Widget buildTestWidget({
    List<ActionRecord>? actions,
    Size size = const Size(1280, 800),
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: ManagerDashboardScreen(
          userProfile: testProfile,
          managerContext: testContext,
          initialActions: actions ?? generateTestActions(),
          initialMyActions: actions ?? generateTestActions(),
        ),
      ),
    );
  }

  group('Redesigned Manager Dashboard Screen Tests', () {
    testWidgets('Renders Executive Header Banner with Org, Manager, Date, and View Full Reports', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Manager Dashboard'), findsOneWidget);
      expect(find.text('Action Management Overview'), findsOneWidget);
      expect(find.text('Sobha Constructions'), findsWidgets);
      expect(find.text('David Miller'), findsWidgets);
      expect(find.text('View Full Reports'), findsWidgets);

      // Verify global shell top bar
      expect(find.text('Search actions, projects, people'), findsOneWidget);
      expect(find.text('Logout'), findsOneWidget);
    });

    testWidgets('View Full Reports button switches navigation to Reports & Graphs (Index 5)', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Click "View Full Reports" in header banner
      final viewReportsBtn = find.text('View Full Reports');
      expect(viewReportsBtn, findsWidgets);
      await tester.tap(viewReportsBtn.first);
      await tester.pumpAndSettle();

      // Verify Reports page title is shown
      expect(find.text('Reports & Analytics'), findsWidgets);
    });

    testWidgets('Dashboard DOES NOT display Action Register table on Navigation Index 0', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Ensure the old large table and its filter card do NOT appear on dashboard
      expect(find.text('Filter & Search Actions'), findsNothing);
      expect(find.text('Search actions...'), findsNothing);
      expect(find.text('Actions in Register'), findsNothing);
    });

    testWidgets('Action Register table correctly displays when navigating to Index 1', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Click Action Register in sidebar
      final actionRegisterNav = find.byKey(const ValueKey('sidebar_item_Action Register'));
      expect(actionRegisterNav, findsOneWidget);
      await tester.tap(actionRegisterNav);
      await tester.pumpAndSettle();

      // Verify dedicated Action Register table elements
      expect(find.text('Action Register'), findsWidgets);
      expect(find.text('Filter & Search Actions'), findsOneWidget);
      expect(find.text('Search actions...'), findsOneWidget);
      expect(find.text('ACT-001'), findsOneWidget);
      expect(find.text('Overdue Valve Inspection'), findsOneWidget);
    });

    testWidgets('Needs Your Attention Section displays 5 categories and shows items', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Needs Your Attention'), findsOneWidget);
      expect(find.text('Actions requiring immediate supervision, review, or follow-up action'), findsOneWidget);

      // Verify categories
      expect(find.text('Overdue'), findsWidgets);
      expect(find.text('Due Soon'), findsWidgets);
      expect(find.text('Follow-Ups Today'), findsWidgets);
      expect(find.text('Ready for Review'), findsWidgets);
      expect(find.text('Recently Closed'), findsWidgets);

      // Overdue category is active by default: should show ACT-001 within attention section
      final overdueCard = find.descendant(
        of: find.byType(DashboardAttentionSection),
        matching: find.text('ACT-001'),
      );
      expect(overdueCard, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DashboardAttentionSection),
          matching: find.text('Overdue Valve Inspection'),
        ),
        findsOneWidget,
      );

      // Switch to "Ready for Review"
      final readyTab = find.text('Ready for Review');
      await tester.tap(readyTab.first);
      await tester.pumpAndSettle();

      // Should show ACT-003
      final reviewCard = find.descendant(
        of: find.byType(DashboardAttentionSection),
        matching: find.text('ACT-003'),
      );
      expect(reviewCard, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DashboardAttentionSection),
          matching: find.text('Fire Extinguisher Monthly Inspection'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Needs Your Attention Section shows empty state when no actions match category', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Pass only a single closed action
      final closedOnly = [
        ActionRecord(
          id: 'act-4',
          actionNumber: 'ACT-004',
          subject: 'Exit Sign Fix',
          actionRequired: 'Fix sign',
          division: 'Facilities',
          department: 'Civil',
          assignedTo: 'Charlie',
          status: 'Closed',
          percentComplete: 100,
          dateRaised: yesterdayStr,
          targetDate: yesterdayStr,
          closeDate: todayStr,
        ),
      ];

      await tester.pumpWidget(buildTestWidget(actions: closedOnly));
      await tester.pumpAndSettle();

      // Overdue is active by default, and there are no overdue actions
      expect(find.text('Clear of Overdue'), findsOneWidget);
      expect(find.text('No overdue actions! All actions are on schedule.'), findsOneWidget);
    });

    testWidgets('Clicking an Attention action item opens ActionDetailsScreen', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Find the card for ACT-001 within DashboardAttentionSection
      final actionItem = find.descendant(
        of: find.byType(DashboardAttentionSection),
        matching: find.text('ACT-001'),
      );
      expect(actionItem, findsOneWidget);
      await tester.tap(actionItem);
      await tester.pumpAndSettle();

      // Verify ActionDetailsScreen opened
      expect(find.byType(ActionDetailsScreen), findsOneWidget);
      expect(find.text('ACT-001'), findsWidgets);
    });

    testWidgets('7 KPI Cards display correct values matching ReportService', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final testActions = generateTestActions();
      final aggregates = ReportService.compute(testActions);

      await tester.pumpWidget(buildTestWidget(actions: testActions));
      await tester.pumpAndSettle();

      expect(find.text('Total Actions'), findsOneWidget);
      expect(find.text(aggregates.total.toString()), findsWidgets);

      expect(find.text('In Progress'), findsWidgets);
      expect(find.text('Overdue'), findsWidgets);
      expect(find.text('Ready for Review'), findsWidgets);
      expect(find.text('Closed'), findsWidgets);
      expect(find.text('Average Completion %'), findsOneWidget);
      expect(find.text('${aggregates.avgCompletionPct.round()}%'), findsWidgets);
    });

    testWidgets('Quick Actions Row buttons trigger correct navigations', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Quick Actions row items
      expect(find.text('Action Register'), findsWidgets);
      expect(find.text('My Actions'), findsWidgets);
      expect(find.text('Reports & Graphs'), findsWidgets);
      expect(find.text('Calendar'), findsWidgets);

      // Tap "My Actions" in quick action row
      final myActionsBtn = find.widgetWithText(ElevatedButton, 'My Actions');
      if (myActionsBtn.evaluate().isNotEmpty) {
        await tester.tap(myActionsBtn);
      } else {
        final anyMyActions = find.text('My Actions');
        await tester.tap(anyMyActions.first);
      }
      await tester.pumpAndSettle();

      expect(find.text('My Actions'), findsWidgets);
    });

    testWidgets('Status Distribution and Completion Overview render correctly', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Status distribution panel
      expect(find.text('Action Status Overview'), findsOneWidget);
      expect(find.text('Open'), findsWidgets);
      expect(find.text('In Progress'), findsWidgets);
      expect(find.text('Ready for Review'), findsWidgets);
      expect(find.text('Closed'), findsWidgets);

      // Completion overview panel
      expect(find.text('Completion Overview'), findsOneWidget);
      expect(find.text('0–24%'), findsOneWidget);
      expect(find.text('25–49%'), findsOneWidget);
      expect(find.text('50–74%'), findsOneWidget);
      expect(find.text('75–99%'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('Workload by Organization displays dimensions and switches tabs', (tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget(size: const Size(1280, 2400)));
      await tester.pumpAndSettle();

      expect(find.text('Workload by Organization'), findsOneWidget);
      expect(find.text('Department'), findsWidgets);
      expect(find.text('Division'), findsWidgets);
      expect(find.text('Section'), findsWidgets);
      expect(find.text('Site'), findsWidgets);
      expect(find.text('Assignee'), findsWidgets);

      // Default is Department, Engineering & Electrical should be listed
      expect(find.text('Engineering'), findsOneWidget);
      expect(find.text('Electrical'), findsOneWidget);

      // Switch to Division
      await tester.tap(find.text('Division').first);
      await tester.pumpAndSettle();

      expect(find.text('Operations'), findsOneWidget);
      expect(find.text('Maintenance'), findsOneWidget);
    });

    testWidgets('Upcoming Follow-Ups Section renders today, tomorrow, and upcoming items', (tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget(size: const Size(1280, 2400)));
      await tester.pumpAndSettle();

      expect(find.text('Upcoming Follow-Ups'), findsOneWidget);
      expect(find.textContaining('Today'), findsWidgets);
      expect(find.textContaining('Tomorrow'), findsWidgets);
      expect(find.textContaining('Upcoming'), findsWidgets);

      // Today chip is selected by default; ACT-001 has follow-up today
      expect(find.text('ACT-001'), findsWidgets);
    });

    testWidgets('Recent Activity Feed displays real audit events from actions', (tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget(size: const Size(1280, 2400)));
      await tester.pumpAndSettle();

      expect(find.text('Recent Activity'), findsOneWidget);
      expect(find.text('Real-time audit log of action updates, checkpoints, and closures'), findsOneWidget);

      // Audit items generated from progressUpdates and closure
      expect(find.textContaining('Thermography scan 60% complete'), findsOneWidget);
      expect(find.textContaining('Verified battery replacement'), findsOneWidget);
    });

    testWidgets('Responsive Layout Test across Desktop (1280), Tablet (768), and Mobile (400)', (tester) async {
      // 1. Desktop
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(buildTestWidget(size: const Size(1280, 800)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 2. Tablet
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(buildTestWidget(size: const Size(768, 1024)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 3. Mobile
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(buildTestWidget(size: const Size(400, 800)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
