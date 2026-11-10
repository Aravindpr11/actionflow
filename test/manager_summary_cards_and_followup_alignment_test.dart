import 'package:action_flow/features/calendar/models/calendar_task.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/widgets/dashboard_attention_section.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/widgets/dashboard_followups_dialog.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/widgets/dashboard_kpi_cards.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/widgets/dashboard_upcoming_followups.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/models/organization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const orgId = Organization.sobhaId;
  const managerId = 'mgr-uuid-summary-cards';

  final managerProfile = UserProfile(
    id: managerId,
    name: 'Sarah Connor',
    email: 'sarah.c@sobha.com',
    phone: '+971 50 999 8888',
    designation: 'HSSE Manager',
    role: 'manager',
    organizationId: orgId,
    department: 'HSE',
    site: 'Downtown Tower',
  );

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final tomorrow = today.add(const Duration(days: 1));
  final inThreeDays = today.add(const Duration(days: 3));

  String fmt(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final d = dt.day.toString().padLeft(2, '0');
    return '$d ${months[dt.month - 1]} ${dt.year}';
  }

  ActionRecord makeAction({
    required String id,
    required String actionNumber,
    required String subject,
    String status = 'Open',
    int percentComplete = 10,
    String targetDate = '15 Dec 2026',
    String nextFollowUpDate = '',
    List<ActionFollowUpRecord> followUps = const [],
    String assignedTo = 'John Staff',
  }) {
    return ActionRecord(
      id: id,
      actionNumber: actionNumber,
      subject: subject,
      actionRequired: 'Test action details',
      division: 'Construction',
      status: status,
      priority: 'High',
      department: 'Safety',
      site: 'Downtown Tower',
      targetDate: targetDate,
      nextFollowUpDate: nextFollowUpDate,
      followUps: followUps,
      assignedTo: assignedTo,
      organizationId: orgId,
      createdById: managerId,
      percentComplete: percentComplete,
    );
  }

  group('Manager Dashboard Summary Cards (9 KPI Cards)', () {
    testWidgets('DashboardKpiCards renders all 9 summary cards with proper values and subtexts',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final actions = [
        makeAction(
          id: 'act-1',
          actionNumber: 'ACT-101',
          subject: 'Crane Inspection',
          status: 'Open',
          percentComplete: 0,
        ),
        makeAction(
          id: 'act-2',
          actionNumber: 'ACT-102',
          subject: 'Scaffolding Audit',
          status: 'In Progress',
          percentComplete: 40,
        ),
        makeAction(
          id: 'act-3',
          actionNumber: 'ACT-103',
          subject: 'Electrical Hazard',
          status: 'Overdue',
          targetDate: fmt(yesterday),
          percentComplete: 20,
        ),
        makeAction(
          id: 'act-4',
          actionNumber: 'ACT-104',
          subject: 'Fire Exit Clearance',
          status: 'Ready for Review',
          percentComplete: 100,
        ),
        makeAction(
          id: 'act-5',
          actionNumber: 'ACT-105',
          subject: 'Chemical Storage Protocol',
          status: 'Closed',
          percentComplete: 100,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DashboardKpiCards(
                actions: actions,
                followUpCount: 4,
                followUpSubtext: '2 due today',
                personalTaskCount: 7,
                personalTaskSubtext: '3 due today',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check all 9 card labels
      expect(find.text('Total Actions'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('In Progress'), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Ready for Review'), findsOneWidget);
      expect(find.text('Closed'), findsOneWidget);
      expect(find.text('Average Completion %'), findsOneWidget);
      expect(find.text('Follow-ups'), findsOneWidget);
      expect(find.text('Personal Tasks'), findsOneWidget);

      // Verify custom values
      expect(find.text('4'), findsOneWidget); // Follow-up count
      expect(find.text('2 due today'), findsOneWidget); // Follow-up subtext
      expect(find.text('7'), findsOneWidget); // Personal Task count
      expect(find.text('3 due today'), findsOneWidget); // Personal Task subtext
    });

    testWidgets('Tapping Follow-ups card triggers onKpiTap callback', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      String? tappedKpi;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardKpiCards(
              actions: const [],
              followUpCount: 5,
              personalTaskCount: 3,
              onKpiTap: (label) => tappedKpi = label,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Follow-ups'));
      await tester.pumpAndSettle();

      expect(tappedKpi, equals('Follow-ups'));
    });

    testWidgets('Tapping Personal Tasks card triggers onKpiTap callback', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      String? tappedKpi;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardKpiCards(
              actions: const [],
              followUpCount: 5,
              personalTaskCount: 3,
              onKpiTap: (label) => tappedKpi = label,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Personal Tasks'));
      await tester.pumpAndSettle();

      expect(tappedKpi, equals('Personal Tasks'));
    });
  });

  group('Follow-ups Computation & Follow-ups Today Bug Fix', () {
    testWidgets('Action with overdue target date but scheduled follow-up today is counted in Follow-ups Today',
        (tester) async {
      final overdueActionWithFollowUpToday = makeAction(
        id: 'act-overdue-today',
        actionNumber: 'ACT-900',
        subject: 'Overdue Action with Follow-up Today',
        status: 'Overdue',
        targetDate: fmt(yesterday), // Target date was yesterday
        followUps: [
          ActionFollowUpRecord(
            id: 'fu-1',
            actionId: 'act-overdue-today',
            followUpDate: fmt(today), // Follow-up scheduled for TODAY
            notes: 'Check containment progress',
            status: 'Scheduled',
          ),
        ],
      );

      final normalActionWithFutureFollowUp = makeAction(
        id: 'act-normal-future',
        actionNumber: 'ACT-901',
        subject: 'Normal Action with Future Follow-up',
        status: 'In Progress',
        targetDate: fmt(inThreeDays),
        nextFollowUpDate: fmt(tomorrow),
      );

      final actions = [
        overdueActionWithFollowUpToday,
        normalActionWithFutureFollowUp,
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DashboardAttentionSection(
                actions: actions,
                onActionTap: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the Follow-Ups Today pill
      expect(find.text('Follow-Ups Today'), findsOneWidget);

      // Tap on Follow-Ups Today category in Attention section
      await tester.tap(find.text('Follow-Ups Today'));
      await tester.pumpAndSettle();

      // ACT-900 MUST appear because its follow-up is today, even though targetDate is overdue!
      expect(find.text('ACT-900'), findsWidgets);
      expect(find.text('Overdue Action with Follow-up Today'), findsWidgets);
    });

    testWidgets('Upcoming Follow-ups does NOT silently fall back to all entries when today is empty',
        (tester) async {
      // Only has tomorrow follow-up, 0 today
      final actionWithTomorrowFollowUp = makeAction(
        id: 'act-tomorrow',
        actionNumber: 'ACT-902',
        subject: 'Action for Tomorrow',
        status: 'Open',
        followUps: [
          ActionFollowUpRecord(
            id: 'fu-tom',
            actionId: 'act-tomorrow',
            followUpDate: fmt(tomorrow),
            status: 'Scheduled',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardUpcomingFollowups(
              actions: [actionWithTomorrowFollowUp],
              onActionTap: (_) {},
              onOpenCalendar: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Today count is 0, Tomorrow count is 1
      expect(find.text('Today (0)'), findsOneWidget);
      expect(find.text('Tomorrow (1)'), findsOneWidget);

      // Since today is selected by default and has 0 entries, it MUST show empty state, NOT tomorrow's item!
      expect(find.text('No scheduled follow-ups'), findsOneWidget);
      expect(find.text('ACT-902'), findsNothing);

      // Now tap Tomorrow tab
      await tester.tap(find.text('Tomorrow (1)'));
      await tester.pumpAndSettle();

      // Now ACT-902 must be visible under Tomorrow
      expect(find.text('ACT-902'), findsOneWidget);
      expect(find.text('Action for Tomorrow'), findsOneWidget);
    });
  });

  group('Dashboard Follow-ups Overview Dialog', () {
    testWidgets('Displays all pending follow-ups with classification, date, action ID, and assignee',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final overdueItem = makeAction(
        id: 'act-ov',
        actionNumber: 'ACT-201',
        subject: 'Overdue Follow-up Task',
        status: 'In Progress',
        assignedTo: 'Alice Engineer',
        followUps: [
          ActionFollowUpRecord(
            id: 'fu-ov',
            actionId: 'act-ov',
            followUpDate: fmt(yesterday),
            status: 'Scheduled',
            notes: 'Requires site manager approval',
          ),
        ],
      );

      final todayItem = makeAction(
        id: 'act-td',
        actionNumber: 'ACT-202',
        subject: 'Today Follow-up Task',
        status: 'Open',
        assignedTo: 'Bob Specialist',
        nextFollowUpDate: fmt(today),
      );

      final upcomingItem = makeAction(
        id: 'act-up',
        actionNumber: 'ACT-203',
        subject: 'Upcoming Follow-up Task',
        status: 'Open',
        assignedTo: 'Charlie Inspector',
        followUps: [
          ActionFollowUpRecord(
            id: 'fu-up',
            actionId: 'act-up',
            followUpDate: fmt(inThreeDays),
            status: 'Scheduled',
          ),
        ],
      );

      ActionRecord? clickedAction;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  DashboardFollowupsDialog.show(
                    ctx,
                    actions: [overdueItem, todayItem, upcomingItem],
                    onActionTap: (a) => clickedAction = a,
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify dialog header & tabs
      expect(find.text('Follow-ups Overview & Schedule'), findsOneWidget);
      expect(find.text('All (3)'), findsOneWidget);
      expect(find.text('Overdue (1)'), findsOneWidget);
      expect(find.text('Due Today (1)'), findsOneWidget);
      expect(find.text('Upcoming (1)'), findsOneWidget);

      // Verify list content
      expect(find.text('ACT-201'), findsOneWidget);
      expect(find.text('ACT-202'), findsOneWidget);
      expect(find.text('ACT-203'), findsOneWidget);
      expect(find.text('Alice Engineer'), findsOneWidget);
      expect(find.text('Bob Specialist'), findsOneWidget);
      expect(find.text('Charlie Inspector'), findsOneWidget);

      // Tap View Action for ACT-202
      final viewButtons = find.text('View Action');
      expect(viewButtons, findsNWidgets(3));
      await tester.tap(viewButtons.at(1));
      await tester.pumpAndSettle();

      // Dialog closed and clickedAction received
      expect(find.text('Follow-ups Overview & Schedule'), findsNothing);
      expect(clickedAction?.id, equals('act-td'));
    });
  });

  group('Manager Dashboard Screen Full Integration', () {
    testWidgets('Tapping Follow-ups KPI opens Follow-ups Dialog; Tapping Personal Tasks switches to Calendar',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final actions = [
        makeAction(
          id: 'act-m1',
          actionNumber: 'ACT-301',
          subject: 'Weekly Plant Inspection',
          status: 'In Progress',
          nextFollowUpDate: fmt(today),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: ManagerDashboardScreen(
            userProfile: managerProfile,
            initialActions: actions,
            initialMyActions: actions,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Follow-ups and Personal Tasks cards exist
      expect(find.text('Follow-ups'), findsOneWidget);
      expect(find.text('Personal Tasks'), findsOneWidget);

      // Tap Follow-ups card
      await tester.tap(find.text('Follow-ups'));
      await tester.pumpAndSettle();

      // Follow-ups dialog is displayed
      expect(find.text('Follow-ups Overview & Schedule'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DashboardFollowupsDialog),
          matching: find.text('ACT-301'),
        ),
        findsOneWidget,
      );

      // Close dialog
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Follow-ups Overview & Schedule'), findsNothing);

      // Tap Personal Tasks card
      await tester.tap(find.text('Personal Tasks'));
      await tester.pumpAndSettle();

      // Verify Calendar view is loaded (title: 'Action Calendar & Due Dates')
      expect(find.text('Action Calendar & Due Dates'), findsOneWidget);
    });
  });
}
