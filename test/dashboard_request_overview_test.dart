import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/requests/models/request_models.dart';
import 'package:action_flow/features/requests/screens/my_requests_screen.dart';
import 'package:action_flow/features/requests/screens/request_approval_screen.dart';
import 'package:action_flow/features/requests/services/request_service.dart';
import 'package:action_flow/models/organization.dart';

void main() {
  setUp(() {
    RequestService.useMockOnly = true;
    RequestService.instance.clearMockStore();

    // 1. Under Review request with sequential approvers
    RequestService.instance.seedMockRequest(
      RequestRecord(
        id: 'mock-req-1',
        displayId: 'REQ-1001',
        organizationId: Organization.sobhaId,
        title: 'Safety Eyewash Station Repair',
        description: 'Water pressure valve failure in block C',
        requestType: RequestType.equipment,
        priority: RequestPriority.high,
        requiredByDate: '2026-11-20',
        status: RequestStatus.underReview,
        approvalType: ApprovalType.sequential,
        departmentName: 'HSE',
        siteName: 'Hartland Estate',
        createdBy: 'worker-1',
        createdByName: 'Worker One',
        createdByRole: 'Staff',
        approvers: const [
          RequestApproverRecord(
            id: 'appr-1',
            requestId: 'mock-req-1',
            approverId: 'approver-mock-1',
            approverName: 'HSE Lead',
            approverRole: 'Manager',
            stepOrder: 1,
            status: RequestStatus.pending,
          ),
          RequestApproverRecord(
            id: 'appr-2',
            requestId: 'mock-req-1',
            approverId: 'approver-mock-2',
            approverName: 'VP Operations',
            approverRole: 'Director',
            stepOrder: 2,
            status: RequestStatus.pending,
          ),
        ],
      ),
    );

    // 2. Approved request
    RequestService.instance.seedMockRequest(
      RequestRecord(
        id: 'mock-req-2',
        displayId: 'REQ-1002',
        organizationId: Organization.sobhaId,
        title: 'Chemical Respirator Purchase',
        description: 'New cartridges required for paint booth',
        requestType: RequestType.material,
        priority: RequestPriority.medium,
        requiredByDate: '2026-11-22',
        status: RequestStatus.approved,
        approvalType: ApprovalType.parallel,
        departmentName: 'HSE',
        siteName: 'Hartland Estate',
        createdBy: 'worker-1',
        createdByName: 'Worker One',
        createdByRole: 'Staff',
        approvers: const [
          RequestApproverRecord(
            id: 'appr-3',
            requestId: 'mock-req-2',
            approverId: 'approver-mock-1',
            approverName: 'HSE Lead',
            approverRole: 'Manager',
            stepOrder: 1,
            status: RequestStatus.approved,
          ),
        ],
      ),
    );

    // 3. Rejected request
    RequestService.instance.seedMockRequest(
      RequestRecord(
        id: 'mock-req-3',
        displayId: 'REQ-1003',
        organizationId: Organization.sobhaId,
        title: 'Non-compliant Scaffolding Plank',
        description: 'Request for unauthorized timber plank',
        requestType: RequestType.equipment,
        priority: RequestPriority.low,
        requiredByDate: '2026-11-23',
        status: RequestStatus.rejected,
        approvalType: ApprovalType.sequential,
        departmentName: 'Construction',
        siteName: 'Creek Vistas',
        createdBy: 'worker-2',
        createdByName: 'Worker Two',
        createdByRole: 'Staff',
      ),
    );

    // 4. Completed request
    RequestService.instance.seedMockRequest(
      RequestRecord(
        id: 'mock-req-4',
        displayId: 'REQ-1004',
        organizationId: Organization.sobhaId,
        title: 'First Aid Kit Refill',
        description: 'Completed inspection and refill',
        requestType: RequestType.other,
        priority: RequestPriority.low,
        requiredByDate: '2026-11-15',
        status: RequestStatus.completed,
        approvalType: ApprovalType.sequential,
        departmentName: 'HSE',
        siteName: 'Hartland Estate',
        createdBy: 'worker-1',
        createdByName: 'Worker One',
        createdByRole: 'Staff',
      ),
    );
  });

  group('Manager Dashboard Request Overview Counts Unit Tests', () {
    test('Unscoped / Admin Manager receives all requests in scope without duplicates', () async {
      final counts = await RequestService.instance.getManagerRequestOverviewCounts(
        userId: 'manager-admin-id',
        organizationId: Organization.sobhaId,
        isCompanyAdmin: true,
      );

      expect(counts.total, equals(4));
      expect(counts.underReview, equals(1));
      expect(counts.approved, equals(1));
      expect(counts.rejected, equals(1));
      expect(counts.completed, equals(1));
      expect(counts.total, equals(counts.underReview + counts.approved + counts.rejected + counts.completed));
    });

    test('Department/Site Scoped Manager filters counts strictly within authorized scope', () async {
      final scopedCounts = await RequestService.instance.getManagerRequestOverviewCounts(
        userId: 'scoped-user',
        organizationId: Organization.sobhaId,
        isCompanyAdmin: false,
        scopedDepartmentNames: ['HSE'],
        scopedSiteNames: ['Hartland Estate'],
      );

      // Only mock-req-1, mock-req-2, mock-req-4 are HSE / Hartland Estate (3 total)
      expect(scopedCounts.total, equals(3));
      expect(scopedCounts.underReview, equals(1));
      expect(scopedCounts.approved, equals(1));
      expect(scopedCounts.completed, equals(1));
      expect(scopedCounts.rejected, equals(0)); // Construction / Creek Vistas excluded
    });

    test('Pending My Approval accurately detects pending decision for specific manager', () async {
      // Step 1 approver has a pending decision
      final approverCounts = await RequestService.instance.getManagerRequestOverviewCounts(
        userId: 'approver-mock-1',
        organizationId: Organization.sobhaId,
        isCompanyAdmin: true,
      );

      expect(approverCounts.pendingMyApproval, equals(1));

      // Step 2 approver cannot approve yet because step 1 is still pending (sequential)
      final step2Counts = await RequestService.instance.getManagerRequestOverviewCounts(
        userId: 'approver-mock-2',
        organizationId: Organization.sobhaId,
        isCompanyAdmin: true,
      );

      expect(step2Counts.pendingMyApproval, equals(0));

      // Unassigned manager has 0 pending
      final nonApproverCounts = await RequestService.instance.getManagerRequestOverviewCounts(
        userId: 'unassigned-manager-xyz',
        organizationId: Organization.sobhaId,
        isCompanyAdmin: true,
      );

      expect(nonApproverCounts.pendingMyApproval, equals(0));
    });
  });

  group('Staff Dashboard Request Overview Counts Unit Tests', () {
    test('Counts only requests created by the authenticated staff member', () async {
      // worker-1 created req-1, req-2, req-4 (3 total)
      final counts = await RequestService.instance.getStaffRequestOverviewCounts(
        userId: 'worker-1',
        organizationId: Organization.sobhaId,
        hasApprovalAuthority: false,
      );

      expect(counts.mySubmittedTotal, equals(3));
      expect(counts.underReview, equals(1));
      expect(counts.approved, equals(1));
      expect(counts.completed, equals(1));
      expect(counts.rejected, equals(0));
      expect(counts.pendingMyApproval, isNull);
    });

    test('Designated staff approver receives non-null pendingMyApproval count', () async {
      final counts = await RequestService.instance.getStaffRequestOverviewCounts(
        userId: 'approver-mock-1',
        organizationId: Organization.sobhaId,
        hasApprovalAuthority: true,
      );

      expect(counts.pendingMyApproval, isNotNull);
      expect(counts.pendingMyApproval, equals(1));
    });

    test('Staff without approval authority receives null pendingMyApproval', () async {
      final counts = await RequestService.instance.getStaffRequestOverviewCounts(
        userId: 'worker-normal',
        organizationId: Organization.sobhaId,
        hasApprovalAuthority: false,
      );

      expect(counts.pendingMyApproval, isNull);
    });
  });

  group('Manager Dashboard Screen Request Overview Widget Tests', () {
    testWidgets('Renders Request Overview section and 6 KPI cards', (tester) async {
      tester.view.physicalSize = const Size(1440, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final managerProfile = UserProfile.mockManager().copyWith(
        id: 'manager-test-overview',
        name: 'Manager Bob',
        email: 'bob@sobha.test',
        role: 'manager',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ManagerDashboardScreen(
            userProfile: managerProfile,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Request Overview'), findsOneWidget);
      expect(find.text('Total Requests'), findsOneWidget);
      expect(find.text('Pending My Approval'), findsOneWidget);
      expect(find.text('Under Review'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('View All Requests'), findsOneWidget);
    });

    testWidgets('Tapping Pending My Approval navigates to Request Approval screen at tab 0', (tester) async {
      tester.view.physicalSize = const Size(1440, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final managerProfile = UserProfile.mockManager().copyWith(
        id: 'manager-test-overview',
        name: 'Manager Bob',
        email: 'bob@sobha.test',
        role: 'manager',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ManagerDashboardScreen(
            userProfile: managerProfile,
          ),
        ),
      );

      await tester.pumpAndSettle();

      final pendingCard = find.text('Pending My Approval');
      expect(pendingCard, findsOneWidget);
      await tester.tap(pendingCard);
      await tester.pumpAndSettle();

      // Should have navigated to Request Approval Screen
      expect(find.byType(RequestApprovalScreen), findsOneWidget);
      expect(find.text('Pending My Action'), findsOneWidget);
    });
  });

  group('Worker Dashboard Screen Request Overview Widget Tests', () {
    testWidgets('Non-approver staff sees 6 status cards and NOT Pending My Approval', (tester) async {
      tester.view.physicalSize = const Size(1440, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final staffProfile = UserProfile.mockStaff().copyWith(
        id: 'worker-normal-staff',
        name: 'Worker Dave',
        email: 'dave@sobha.test',
        role: 'worker',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: WorkerDashboardScreen(
            userProfile: staffProfile,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('My Request Overview'), findsOneWidget);
      expect(find.text('My Submitted Requests'), findsOneWidget);
      expect(find.text('Pending Approval'), findsOneWidget);
      expect(find.text('Under Review'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Pending My Approval'), findsNothing);
    });

    testWidgets('Tapping My Submitted Requests navigates to My Requests screen', (tester) async {
      tester.view.physicalSize = const Size(1440, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final staffProfile = UserProfile.mockStaff().copyWith(
        id: 'worker-1',
        name: 'Worker One',
        email: 'worker1@sobha.test',
        role: 'worker',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: WorkerDashboardScreen(
            userProfile: staffProfile,
          ),
        ),
      );

      await tester.pumpAndSettle();

      final myRequestsCard = find.text('My Submitted Requests');
      expect(myRequestsCard, findsOneWidget);
      await tester.tap(myRequestsCard);
      await tester.pumpAndSettle();

      // Navigates to MyRequestsScreen
      expect(find.byType(MyRequestsScreen), findsOneWidget);
    });
  });
}
