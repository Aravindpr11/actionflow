import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:action_flow/features/requests/models/request_models.dart';
import 'package:action_flow/features/requests/screens/request_approval_screen.dart';
import 'package:action_flow/features/requests/services/request_service.dart';
import 'package:action_flow/models/organization.dart';

void main() {
  const orgId = Organization.sobhaId;
  const managerId = 'mgr-tab-test-uuid';
  const staffId = 'staff-tab-test-uuid';

  setUp(() {
    RequestService.useMockOnly = true;
    RequestService.instance.clearMockStore();
  });

  tearDown(() {
    RequestService.instance.clearMockStore();
  });

  group('Request Approval Tab Counts & Simultaneous Visibility Tests', () {
    testWidgets(
      'All 5 tab counts (Pending My Action, Under Review, Approved, Rejected, All Requests) are visible simultaneously across all tab selections',
      (tester) async {
        // Seed 1 request where manager action is required (Pending/Under Review)
        RequestService.instance.seedMockRequest(
          RequestRecord(
            id: 'req-1',
            displayId: 'REQ-101',
            organizationId: orgId,
            title: 'Equipment Transfer Crane',
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
            approvers: const [
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

        // Seed 1 additional Under Review request where manager is NOT the current approver
        RequestService.instance.seedMockRequest(
          RequestRecord(
            id: 'req-2',
            displayId: 'REQ-102',
            organizationId: orgId,
            title: 'PTW Hot Work',
            description: 'Under review by safety team',
            requestType: RequestType.ptw,
            priority: RequestPriority.medium,
            requiredByDate: '2026-11-21',
            status: RequestStatus.underReview,
            departmentName: 'HSE',
            siteName: 'Downtown Tower',
            createdBy: staffId,
            createdByName: 'John Staff',
            createdByRole: 'Staff',
            approvers: const [
              RequestApproverRecord(
                id: 'appr-2',
                requestId: 'req-2',
                approverId: 'other-approver',
                approverName: 'Other Approver',
                approverRole: 'Staff',
                stepOrder: 1,
                status: RequestStatus.pending,
              ),
            ],
          ),
        );

        // Seed 2 Approved requests
        RequestService.instance.seedMockRequest(
          RequestRecord(
            id: 'req-3',
            displayId: 'REQ-103',
            organizationId: orgId,
            title: 'Approved Scaffolding Sign-off',
            description: 'Passed inspection',
            requestType: RequestType.access,
            priority: RequestPriority.low,
            requiredByDate: '2026-11-22',
            status: RequestStatus.approved,
            departmentName: 'HSE',
            siteName: 'Downtown Tower',
            createdBy: staffId,
            createdByName: 'John Staff',
            createdByRole: 'Staff',
            approvers: const [
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

        RequestService.instance.seedMockRequest(
          RequestRecord(
            id: 'req-4',
            displayId: 'REQ-104',
            organizationId: orgId,
            title: 'Approved Material Requisition',
            description: 'Safety harnesses',
            requestType: RequestType.material,
            priority: RequestPriority.medium,
            requiredByDate: '2026-11-23',
            status: RequestStatus.approved,
            departmentName: 'HSE',
            siteName: 'Downtown Tower',
            createdBy: staffId,
            createdByName: 'John Staff',
            createdByRole: 'Staff',
            approvers: const [
              RequestApproverRecord(
                id: 'appr-4',
                requestId: 'req-4',
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
            id: 'req-5',
            displayId: 'REQ-105',
            organizationId: orgId,
            title: 'Rejected Excavation Permit',
            description: 'Missing soil test report',
            requestType: RequestType.ptw,
            priority: RequestPriority.critical,
            requiredByDate: '2026-11-24',
            status: RequestStatus.rejected,
            departmentName: 'HSE',
            siteName: 'Downtown Tower',
            createdBy: staffId,
            createdByName: 'John Staff',
            createdByRole: 'Staff',
            approvers: const [
              RequestApproverRecord(
                id: 'appr-5',
                requestId: 'req-5',
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

        // Render RequestApprovalScreen
        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RequestApprovalScreen(
                  currentUserId: managerId,
                  currentUserName: 'Sarah Connor',
                  currentUserRole: 'manager',
                  currentUserEmail: 'sarah.c@sobha.com',
                  organizationId: orgId,
                  isManager: true,
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Helper to find a tab badge with a specific count inside a given Tab
        void verifyAllTabCounts({
          required int expectedPendingMyAction,
          required int expectedUnderReview,
          required int expectedApproved,
          required int expectedRejected,
          required int expectedAllRequests,
        }) {
          // Tab 0: Pending My Action
          final tab0 = find.ancestor(
            of: find.text('Pending My Action'),
            matching: find.byType(Tab),
          );
          expect(tab0, findsOneWidget);
          expect(
            find.descendant(of: tab0, matching: find.text('$expectedPendingMyAction')),
            findsOneWidget,
            reason: 'Tab 0 badge count must be $expectedPendingMyAction',
          );

          // Tab 1: Under Review
          final tab1 = find.ancestor(
            of: find.text('Under Review'),
            matching: find.byType(Tab),
          );
          expect(tab1, findsOneWidget);
          expect(
            find.descendant(of: tab1, matching: find.text('$expectedUnderReview')),
            findsOneWidget,
            reason: 'Tab 1 badge count must be $expectedUnderReview',
          );

          // Tab 2: Approved
          final tab2 = find.ancestor(
            of: find.text('Approved'),
            matching: find.byType(Tab),
          );
          expect(tab2, findsOneWidget);
          expect(
            find.descendant(of: tab2, matching: find.text('$expectedApproved')),
            findsOneWidget,
            reason: 'Tab 2 badge count must be $expectedApproved',
          );

          // Tab 3: Rejected
          final tab3 = find.ancestor(
            of: find.text('Rejected'),
            matching: find.byType(Tab),
          );
          expect(tab3, findsOneWidget);
          expect(
            find.descendant(of: tab3, matching: find.text('$expectedRejected')),
            findsOneWidget,
            reason: 'Tab 3 badge count must be $expectedRejected',
          );

          // Tab 4: All Requests
          final tab4 = find.ancestor(
            of: find.text('All Requests'),
            matching: find.byType(Tab),
          );
          expect(tab4, findsOneWidget);
          expect(
            find.descendant(of: tab4, matching: find.text('$expectedAllRequests')),
            findsOneWidget,
            reason: 'Tab 4 badge count must be $expectedAllRequests',
          );
        }

        // 1. Initial State (Tab 0: Pending My Action selected by default)
        // Expected:
        // - Pending My Action: 1
        // - Under Review: 2 (req-1 and req-2)
        // - Approved: 2 (req-3 and req-4)
        // - Rejected: 1 (req-5)
        // - All Requests: 5
        verifyAllTabCounts(
          expectedPendingMyAction: 1,
          expectedUnderReview: 2,
          expectedApproved: 2,
          expectedRejected: 1,
          expectedAllRequests: 5,
        );

        // 2. Switch to Tab 1 ('Under Review')
        final tab1 = find.widgetWithText(Tab, 'Under Review');
        await tester.tap(tab1);
        await tester.pumpAndSettle();

        // ALL 5 counts must remain simultaneously visible and unchanged
        verifyAllTabCounts(
          expectedPendingMyAction: 1,
          expectedUnderReview: 2,
          expectedApproved: 2,
          expectedRejected: 1,
          expectedAllRequests: 5,
        );

        // 3. Switch to Tab 2 ('Approved')
        final tab2 = find.widgetWithText(Tab, 'Approved');
        await tester.tap(tab2);
        await tester.pumpAndSettle();

        // ALL 5 counts must remain simultaneously visible and unchanged
        verifyAllTabCounts(
          expectedPendingMyAction: 1,
          expectedUnderReview: 2,
          expectedApproved: 2,
          expectedRejected: 1,
          expectedAllRequests: 5,
        );

        // 4. Switch to Tab 3 ('Rejected')
        final tab3 = find.widgetWithText(Tab, 'Rejected');
        await tester.tap(tab3);
        await tester.pumpAndSettle();

        // ALL 5 counts must remain simultaneously visible and unchanged
        verifyAllTabCounts(
          expectedPendingMyAction: 1,
          expectedUnderReview: 2,
          expectedApproved: 2,
          expectedRejected: 1,
          expectedAllRequests: 5,
        );

        // 5. Switch to Tab 4 ('All Requests')
        final tab4 = find.widgetWithText(Tab, 'All Requests');
        await tester.tap(tab4);
        await tester.pumpAndSettle();

        // ALL 5 counts must remain simultaneously visible and unchanged
        verifyAllTabCounts(
          expectedPendingMyAction: 1,
          expectedUnderReview: 2,
          expectedApproved: 2,
          expectedRejected: 1,
          expectedAllRequests: 5,
        );

        // 6. Return to Tab 0 and approve req-1
        final tab0 = find.widgetWithText(Tab, 'Pending My Action');
        await tester.tap(tab0);
        await tester.pumpAndSettle();

        expect(find.text('Equipment Transfer Crane'), findsOneWidget);
        expect(find.text('Approve'), findsOneWidget);

        // Tap Approve button on the card
        await tester.tap(find.text('Approve'));
        await tester.pumpAndSettle();

        // Confirm Approve in dialog
        final confirmBtn = find.widgetWithText(ElevatedButton, 'Confirm Approval');
        expect(confirmBtn, findsOneWidget);
        await tester.tap(confirmBtn);
        await tester.pumpAndSettle();

        // Verify counts after approval:
        // - Pending My Action: 0 (decreased from 1 to 0)
        // - Under Review: 1 (req-1 is now approved, only req-2 remains under review)
        // - Approved: 3 (increased from 2 to 3)
        // - Rejected: 1 (unchanged)
        // - All Requests: 5 (unchanged)
        verifyAllTabCounts(
          expectedPendingMyAction: 0,
          expectedUnderReview: 1,
          expectedApproved: 3,
          expectedRejected: 1,
          expectedAllRequests: 5,
        );
      },
    );

    testWidgets(
      'Staff view renders "All Assigned" with accurate counts respecting user scope',
      (tester) async {
        // Seed 1 request assigned to this staff member
        RequestService.instance.seedMockRequest(
          RequestRecord(
            id: 'staff-req-1',
            displayId: 'REQ-201',
            organizationId: orgId,
            title: 'Staff Assigned Request',
            description: 'Safety sign-off',
            requestType: RequestType.ptw,
            priority: RequestPriority.medium,
            requiredByDate: '2026-11-25',
            status: RequestStatus.underReview,
            departmentName: 'HSE',
            siteName: 'Downtown Tower',
            createdBy: managerId,
            createdByName: 'Sarah Connor',
            createdByRole: 'Manager',
            approvers: const [
              RequestApproverRecord(
                id: 'staff-appr-1',
                requestId: 'staff-req-1',
                approverId: staffId,
                approverName: 'John Staff',
                approverRole: 'Staff',
                stepOrder: 1,
                status: RequestStatus.pending,
              ),
            ],
          ),
        );

        // Seed 1 request NOT assigned to this staff member
        RequestService.instance.seedMockRequest(
          RequestRecord(
            id: 'staff-req-2',
            displayId: 'REQ-202',
            organizationId: orgId,
            title: 'Unassigned Request',
            description: 'Different approver',
            requestType: RequestType.equipment,
            priority: RequestPriority.low,
            requiredByDate: '2026-11-26',
            status: RequestStatus.underReview,
            departmentName: 'HSE',
            siteName: 'Downtown Tower',
            createdBy: managerId,
            createdByName: 'Sarah Connor',
            createdByRole: 'Manager',
            approvers: const [
              RequestApproverRecord(
                id: 'other-appr-2',
                requestId: 'staff-req-2',
                approverId: 'someone-else',
                approverName: 'Someone Else',
                approverRole: 'Staff',
                stepOrder: 1,
                status: RequestStatus.pending,
              ),
            ],
          ),
        );

        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RequestApprovalScreen(
                  currentUserId: staffId,
                  currentUserName: 'John Staff',
                  currentUserRole: 'staff',
                  currentUserEmail: 'john.s@sobha.com',
                  organizationId: orgId,
                  isManager: false,
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Staff sees "All Assigned" instead of "All Requests"
        final allAssignedTab = find.ancestor(
          of: find.text('All Assigned'),
          matching: find.byType(Tab),
        );
        expect(allAssignedTab, findsOneWidget);
        // Only 1 request is assigned to this staff member
        expect(
          find.descendant(of: allAssignedTab, matching: find.text('1')),
          findsOneWidget,
        );

        // Pending My Action = 1
        final tab0 = find.ancestor(
          of: find.text('Pending My Action'),
          matching: find.byType(Tab),
        );
        expect(
          find.descendant(of: tab0, matching: find.text('1')),
          findsOneWidget,
        );
      },
    );
  });
}
