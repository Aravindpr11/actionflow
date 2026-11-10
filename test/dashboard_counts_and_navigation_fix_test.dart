import 'package:action_flow/features/calendar/models/calendar_task.dart';
import 'package:action_flow/features/calendar/widgets/calendar_view.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/widgets/dashboard_followups_dialog.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/requests/models/request_models.dart';
import 'package:action_flow/features/requests/screens/request_approval_screen.dart';
import 'package:action_flow/features/requests/services/request_service.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/calendar_task_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const orgId = Organization.sobhaId;
  const managerId = 'mgr-test-fix-uuid';
  const staffId = 'staff-test-fix-uuid';

  final managerProfile = UserProfile(
    id: managerId,
    name: 'Sarah Connor',
    email: 'sarah.c@sobha.com',
    phone: '+971 50 999 8888',
    role: 'manager',
    designation: 'HSE Manager',
    organizationId: orgId,
    department: 'HSE',
    site: 'Downtown Tower',
  );

  final staffProfile = UserProfile(
    id: staffId,
    name: 'John Staff',
    email: 'john.s@sobha.com',
    phone: '+971 50 123 4567',
    role: 'staff',
    designation: 'Safety Officer',
    organizationId: orgId,
    department: 'HSE',
    site: 'Downtown Tower',
  );

  setUp(() {
    RequestService.useMockOnly = true;
    RequestService.instance.clearMockStore();
    CalendarTaskService.useMockOnly = true;
    MockCalendarTaskStore.instance.clearForUser(managerId);
    MockCalendarTaskStore.instance.clearForUser(staffId);
  });

  group('Issue 1: Request Approval Independent Summary Counts', () {
    testWidgets('Summary cards show independent counts and do not change across tab switches', (tester) async {
      // Seed 1 request requiring manager action (Pending)
      RequestService.instance.seedMockRequest(
        RequestRecord(
          id: 'req-1',
          displayId: 'REQ-101',
          organizationId: orgId,
          title: 'Pending Action Request',
          description: 'Requires manager approval',
          requestType: RequestType.equipment,
          priority: RequestPriority.high,
          requiredByDate: '2026-11-20',
          status: RequestStatus.underReview,
          departmentName: 'HSE',
          siteName: 'Downtown Tower',
          createdBy: staffId,
          createdByName: 'John Staff',
          createdByRole: 'Staff',
          approvers: [
            RequestApproverRecord(
              id: 'appr-1',
              requestId: 'req-1',
              approverId: managerId,
              approverName: 'Sarah Connor',
              approverRole: 'Manager',
              stepOrder: 1,
              status: RequestStatus.pending,
            ),
          ],
        ),
      );

      // Seed 2 Approved requests
      RequestService.instance.seedMockRequest(
        RequestRecord(
          id: 'req-2',
          displayId: 'REQ-102',
          organizationId: orgId,
          title: 'Approved Request 1',
          description: 'Already approved',
          requestType: RequestType.material,
          priority: RequestPriority.medium,
          requiredByDate: '2026-11-21',
          status: RequestStatus.approved,
          departmentName: 'HSE',
          siteName: 'Downtown Tower',
          createdBy: staffId,
          createdByName: 'John Staff',
          createdByRole: 'Staff',
          approvers: [
            RequestApproverRecord(
              id: 'appr-2',
              requestId: 'req-2',
              approverId: managerId,
              approverName: 'Sarah Connor',
              approverRole: 'Manager',
              stepOrder: 1,
              status: RequestStatus.approved,
            ),
          ],
        ),
      );

      RequestService.instance.seedMockRequest(
        RequestRecord(
          id: 'req-3',
          displayId: 'REQ-103',
          organizationId: orgId,
          title: 'Approved Request 2',
          description: 'Second approved item',
          requestType: RequestType.access,
          priority: RequestPriority.low,
          requiredByDate: '2026-11-22',
          status: RequestStatus.approved,
          departmentName: 'HSE',
          siteName: 'Downtown Tower',
          createdBy: staffId,
          createdByName: 'John Staff',
          createdByRole: 'Staff',
          approvers: [
            RequestApproverRecord(
              id: 'appr-3',
              requestId: 'req-3',
              approverId: managerId,
              approverName: 'Sarah Connor',
              approverRole: 'Manager',
              stepOrder: 1,
              status: RequestStatus.approved,
            ),
          ],
        ),
      );

      // Seed 1 Rejected request
      RequestService.instance.seedMockRequest(
        RequestRecord(
          id: 'req-4',
          displayId: 'REQ-104',
          organizationId: orgId,
          title: 'Rejected Request',
          description: 'Rejected item',
          requestType: RequestType.other,
          priority: RequestPriority.low,
          requiredByDate: '2026-11-23',
          status: RequestStatus.rejected,
          departmentName: 'HSE',
          siteName: 'Downtown Tower',
          createdBy: staffId,
          createdByName: 'John Staff',
          createdByRole: 'Staff',
          approvers: [
            RequestApproverRecord(
              id: 'appr-4',
              requestId: 'req-4',
              approverId: managerId,
              approverName: 'Sarah Connor',
              approverRole: 'Manager',
              stepOrder: 1,
              status: RequestStatus.rejected,
            ),
          ],
        ),
      );

      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RequestApprovalScreen(
                currentUserId: managerId,
                currentUserName: 'Sarah Connor',
                currentUserRole: 'manager',
                organizationId: orgId,
                isManager: true,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Initial Summary Counts on Default Tab ('Pending My Action')
      expect(find.text('My Action Required'), findsOneWidget);
      expect(find.text('Total In Scope'), findsOneWidget);
      expect(find.text('Approved'), findsWidgets);
      expect(find.text('Rejected'), findsWidgets);

      // Check card counts
      Finder metricCardVal(String val) => find.byWidgetPredicate(
        (w) => w is Text && w.data == val && (w.style?.fontSize == 20),
      );

      expect(metricCardVal('4'), findsOneWidget); // Total In Scope = 4
      expect(metricCardVal('2'), findsOneWidget); // Approved = 2
      expect(metricCardVal('1'), findsNWidgets(2)); // My Action (1) and Rejected (1)

      // Now switch tab to 'Approved'
      final approvedTab = find.widgetWithText(Tab, 'Approved');
      expect(approvedTab, findsOneWidget);
      await tester.tap(approvedTab);
      await tester.pumpAndSettle();

      // Verify that summary counts REMAIN CONSTANT after switching to Approved tab
      expect(metricCardVal('4'), findsOneWidget); // Total In Scope is still 4
      expect(metricCardVal('2'), findsOneWidget); // Approved is still 2
      expect(metricCardVal('1'), findsNWidgets(2)); // My Action (1) and Rejected (1) still intact

      // Now switch tab to 'Rejected'
      final rejectedTab = find.widgetWithText(Tab, 'Rejected');
      expect(rejectedTab, findsOneWidget);
      await tester.tap(rejectedTab);
      await tester.pumpAndSettle();

      // Counts must still remain independent and constant
      expect(metricCardVal('4'), findsOneWidget);
      expect(metricCardVal('2'), findsOneWidget);
      expect(metricCardVal('1'), findsNWidgets(2));

      // Now switch tab to 'All Requests'
      final allTab = find.textContaining('All Requests');
      expect(allTab, findsOneWidget);
      await tester.tap(allTab);
      await tester.pumpAndSettle();

      // Counts must still remain independent and constant
      expect(metricCardVal('4'), findsOneWidget);
      expect(metricCardVal('2'), findsOneWidget);
      expect(metricCardVal('1'), findsNWidgets(2));
    });
  });

  group('Issue 2: Staff Portal Follow-ups KPI and Dialog', () {
    testWidgets('WorkerDashboardScreen displays Follow-ups count and opens DashboardFollowupsDialog', (tester) async {
      final now = DateTime.now();
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final todayStr = '${now.day.toString().padLeft(2, '0')} ${months[now.month - 1]} ${now.year}';

      final staffAction = ActionRecord(
        id: 'act-staff-1',
        actionNumber: 'ACT-001',
        subject: 'Scaffolding Safety Inspection',
        actionRequired: 'Inspect area and ensure harness clips',
        division: 'Construction',
        description: 'Verify scaffolding clips',
        status: 'Open',
        assignedTo: 'John Staff',
        assignedToId: staffId,
        department: 'HSE',
        site: 'Downtown Tower',
        organizationId: orgId,
        nextFollowUpDate: todayStr,
        followUps: [
          ActionFollowUpRecord(
            id: 'fu-1',
            actionId: 'act-staff-1',
            followUpDate: todayStr,
            notes: 'Check harness tags with foreman',
            createdAt: now,
          ),
        ],
      );

      MockActionStore.instance.actions.clear();
      MockActionStore.instance.actions.add(staffAction);

      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: WorkerDashboardScreen(
            userProfile: staffProfile,
            initialNavIndex: 0,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify that DashboardKpiCards shows Follow-ups
      expect(find.text('Follow-ups'), findsOneWidget);
      expect(find.text('1 due today'), findsOneWidget);

      // Tap on the Follow-ups card
      await tester.tap(find.text('Follow-ups'));
      await tester.pumpAndSettle();

      // Verify DashboardFollowupsDialog opens and shows the follow-up note
      expect(find.byType(DashboardFollowupsDialog), findsOneWidget);
      expect(find.text('Follow-ups Overview & Schedule'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DashboardFollowupsDialog),
          matching: find.text('Check harness tags with foreman'),
        ),
        findsOneWidget,
      );

      // Close dialog
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardFollowupsDialog), findsNothing);
    });
  });

  group('Issue 3: Personal Tasks Count & Dynamic Refresh', () {
    testWidgets('Staff and Manager portals query and display active personal tasks count', (tester) async {
      final now = DateTime.now();
      // Seed 2 personal tasks for staff: 1 active, 1 completed
      MockCalendarTaskStore.instance.createTask(
        CalendarTask(
          id: 'task-1',
          userId: staffId,
          organizationId: orgId,
          title: 'Review PPE stock',
          dueDate: now,
          isCompleted: false,
        ),
      );
      MockCalendarTaskStore.instance.createTask(
        CalendarTask(
          id: 'task-2',
          userId: staffId,
          organizationId: orgId,
          title: 'Submit daily HSE log',
          dueDate: now,
          isCompleted: true,
        ),
      );

      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: WorkerDashboardScreen(
            userProfile: staffProfile,
            initialNavIndex: 0,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Personal Tasks count should be 1 (only active, uncompleted task)
      expect(find.text('Personal Tasks'), findsOneWidget);
      expect(find.text('1 due today'), findsOneWidget);
    });
  });

  group('Issue 4: Personal Tasks to Calendar Navigation with Filter', () {
    testWidgets('Clicking Personal Tasks card navigates to Calendar with personalTasksOnly filter in Worker Portal', (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: WorkerDashboardScreen(
            userProfile: staffProfile,
            initialNavIndex: 0,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on Personal Tasks card
      final personalTasksCard = find.text('Personal Tasks');
      expect(personalTasksCard, findsOneWidget);
      await tester.ensureVisible(personalTasksCard);
      await tester.tap(personalTasksCard);
      await tester.pumpAndSettle();

      // Verify we navigated to ActionFlowCalendarView
      expect(find.byType(ActionFlowCalendarView), findsOneWidget);

      // Verify the calendar view has Personal Tasks filter selected
      final calendarViewFinder = find.byType(ActionFlowCalendarView);
      final calendarView = tester.widget<ActionFlowCalendarView>(calendarViewFinder);
      expect(calendarView.initialTypeFilter, CalendarItemTypeFilter.personalTasksOnly);

      // The Personal Tasks filter chip should be selected
      final personalTasksChip = find.byKey(const Key('filter_type_personal_tasks'));
      expect(personalTasksChip, findsOneWidget);
    });

    testWidgets('Clicking Personal Tasks card navigates to Calendar with personalTasksOnly filter in Manager Portal', (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: ManagerDashboardScreen(
            userProfile: managerProfile,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on Personal Tasks card
      final personalTasksCard = find.text('Personal Tasks');
      expect(personalTasksCard, findsOneWidget);
      await tester.ensureVisible(personalTasksCard);
      await tester.tap(personalTasksCard);
      await tester.pumpAndSettle();

      // Verify we navigated to ActionFlowCalendarView
      expect(find.byType(ActionFlowCalendarView), findsOneWidget);

      final calendarViewFinder = find.byType(ActionFlowCalendarView);
      final calendarView = tester.widget<ActionFlowCalendarView>(calendarViewFinder);
      expect(calendarView.initialTypeFilter, CalendarItemTypeFilter.personalTasksOnly);
    });
  });
}
