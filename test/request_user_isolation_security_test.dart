import 'package:action_flow/features/requests/models/request_models.dart';
import 'package:action_flow/features/requests/services/request_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    RequestService.useMockOnly = true;
    RequestService.instance.clearMockStore();
  });

  tearDown(() {
    RequestService.instance.clearMockStore();
    RequestService.useMockOnly = false;
  });

  group('Request Section User Isolation & Access Control Security Tests', () {
    test('Requirement 1: Requester sees only requests they created in My Requests', () async {
      final service = RequestService.instance;

      // Seed Request 1 by User A
      service.seedMockRequest(
        RequestRecord(
          id: 'req-1',
          displayId: 'REQ-1001',
          organizationId: 'org-sobha',
          title: 'User A PTW Request',
          description: 'Hot work permit',
          requestType: 'Permit to Work (PTW)',
          priority: 'High',
          requiredByDate: '2026-11-15',
          status: 'Approved',
          createdBy: 'user-a',
          createdByName: 'User A',
          createdByRole: 'Staff',
          approvers: const [
            RequestApproverRecord(
              id: 'appr-1',
              requestId: 'req-1',
              approverId: 'approver-1',
              approverName: 'Approver 1',
              approverRole: 'Staff',
              stepOrder: 1,
              status: 'Approved',
            ),
          ],
        ),
      );

      // Seed Request 2 by User B
      service.seedMockRequest(
        RequestRecord(
          id: 'req-2',
          displayId: 'REQ-1002',
          organizationId: 'org-sobha',
          title: 'User B Equipment Request',
          description: 'Crane equipment request',
          requestType: 'Equipment',
          priority: 'Medium',
          requiredByDate: '2026-11-16',
          status: 'Approved',
          createdBy: 'user-b',
          createdByName: 'User B',
          createdByRole: 'Staff',
          approvers: const [
            RequestApproverRecord(
              id: 'appr-2',
              requestId: 'req-2',
              approverId: 'approver-2',
              approverName: 'Approver 2',
              approverRole: 'Staff',
              stepOrder: 1,
              status: 'Approved',
            ),
          ],
        ),
      );

      // User A queries My Requests
      final resA = await service.getMyRequests(
        userId: 'user-a',
        organizationId: 'org-sobha',
      );
      expect(resA.items.length, equals(1));
      expect(resA.items.first.id, equals('req-1'));

      // User B queries My Requests
      final resB = await service.getMyRequests(
        userId: 'user-b',
        organizationId: 'org-sobha',
      );
      expect(resB.items.length, equals(1));
      expect(resB.items.first.id, equals('req-2'));
    });

    test('Requirement 2 & 3: Designated approver sees assigned requests; Unrelated staff gets 0 rows', () async {
      final service = RequestService.instance;

      service.seedMockRequest(
        RequestRecord(
          id: 'req-assigned-1',
          displayId: 'REQ-2001',
          organizationId: 'org-sobha',
          title: 'Chemical Handling Authorization',
          description: 'Solvent handling in lab',
          requestType: 'Permit to Work (PTW)',
          priority: 'Critical',
          requiredByDate: '2026-11-20',
          status: 'Pending',
          createdBy: 'staff-submitter',
          createdByName: 'Staff Submitter',
          createdByRole: 'Staff',
          approvers: const [
            RequestApproverRecord(
              id: 'appr-assign-1',
              requestId: 'req-assigned-1',
              approverId: 'designated-approver-x',
              approverName: 'Approver X',
              approverRole: 'Staff',
              stepOrder: 1,
              status: 'Pending',
            ),
          ],
        ),
      );

      // Designated approver queries approval queue
      final approverInbox = await service.getApprovalRequests(
        userId: 'designated-approver-x',
        organizationId: 'org-sobha',
        isManager: false,
      );
      expect(approverInbox.items.length, equals(1));
      expect(approverInbox.items.first.id, equals('req-assigned-1'));

      // Unrelated staff (not designated approver) queries approval queue
      final unrelatedStaffInbox = await service.getApprovalRequests(
        userId: 'unrelated-staff-y',
        organizationId: 'org-sobha',
        isManager: false,
      );
      expect(unrelatedStaffInbox.items, isEmpty);
      expect(unrelatedStaffInbox.totalCount, equals(0));
    });

    test('Requirement 4 & 5: Approval does NOT broadcast request to unrelated staff or newly registered users', () async {
      final service = RequestService.instance;

      // Seed an APPROVED request
      service.seedMockRequest(
        RequestRecord(
          id: 'req-approved-1002',
          displayId: 'REQ-1002',
          organizationId: 'org-sobha',
          title: 'test',
          description: 'test description',
          requestType: 'Permit to Work (PTW)',
          priority: 'Medium',
          requiredByDate: '2026-11-12',
          status: 'Approved',
          departmentName: 'Sobha Infra',
          siteName: 'Sobha Infra',
          createdBy: 'creator-manager',
          createdByName: 'Manager',
          createdByRole: 'Manager',
          approvers: const [
            RequestApproverRecord(
              id: 'appr-step-1',
              requestId: 'req-approved-1002',
              approverId: 'approver-staff',
              approverName: 'test staff',
              approverRole: 'Staff',
              stepOrder: 1,
              status: 'Approved',
            ),
          ],
        ),
      );

      // 1. Designated approver who approved it sees it in their history
      final approverHistory = await service.getApprovalRequests(
        userId: 'approver-staff',
        organizationId: 'org-sobha',
        isManager: false,
        tabIndex: 2, // Approved tab
      );
      expect(approverHistory.items.any((r) => r.id == 'req-approved-1002'), isTrue);

      // 2. Newly registered employee (zero involvement) MUST NOT see it
      final newHireRequests = await service.getMyRequests(
        userId: 'new-employee-z',
        organizationId: 'org-sobha',
      );
      expect(newHireRequests.items, isEmpty);

      final newHireApprovals = await service.getApprovalRequests(
        userId: 'new-employee-z',
        organizationId: 'org-sobha',
        isManager: false,
        tabIndex: 2,
      );
      expect(newHireApprovals.items, isEmpty);

      // 3. New hire dashboard counts must be zero
      final newHireCounts = await service.getStaffRequestOverviewCounts(
        userId: 'new-employee-z',
        organizationId: 'org-sobha',
        hasApprovalAuthority: false,
      );
      expect(newHireCounts.mySubmittedTotal, equals(0));
      expect(newHireCounts.approved, equals(0));
      expect(newHireCounts.pendingApproval, equals(0));
    });

    test('Requirement 6: Manager scope isolation - In-scope vs Out-of-scope manager access', () async {
      final service = RequestService.instance;

      // Seed Request in Sobha Infra (Dept D1, Site S1)
      service.seedMockRequest(
        RequestRecord(
          id: 'req-infra-1',
          displayId: 'REQ-3001',
          organizationId: 'org-sobha',
          title: 'Excavation Permit',
          description: 'Foundation trenching',
          requestType: 'Permit to Work (PTW)',
          priority: 'High',
          departmentId: 'dept-infra-id',
          departmentName: 'Sobha Infra',
          siteId: 'site-infra-id',
          siteName: 'Sobha Infra',
          requiredByDate: '2026-11-25',
          status: 'Pending',
          createdBy: 'staff-infra',
          createdByName: 'Infra Worker',
          createdByRole: 'Staff',
          approvers: const [
            RequestApproverRecord(
              id: 'appr-infra-1',
              requestId: 'req-infra-1',
              approverId: 'mgr-infra',
              approverName: 'Infra Manager',
              approverRole: 'Manager',
              stepOrder: 1,
              status: 'Pending',
            ),
          ],
        ),
      );

      // In-scope manager (Sobha Infra) receives the overview count
      final inScopeCounts = await service.getManagerRequestOverviewCounts(
        userId: 'mgr-infra',
        organizationId: 'org-sobha',
        scopedDepartmentIds: const {'dept-infra-id'},
        scopedSiteIds: const {'site-infra-id'},
        isCompanyAdmin: false,
      );
      expect(inScopeCounts.total, equals(1));
      expect(inScopeCounts.pendingMyApproval, equals(1));

      // Out-of-scope manager (Sobha MEP: Dept D2, Site S2) receives 0 counts
      final outOfScopeCounts = await service.getManagerRequestOverviewCounts(
        userId: 'mgr-mep',
        organizationId: 'org-sobha',
        scopedDepartmentIds: const {'dept-mep-id'},
        scopedSiteIds: const {'site-mep-id'},
        isCompanyAdmin: false,
      );
      expect(outOfScopeCounts.total, equals(0));
      expect(outOfScopeCounts.pendingMyApproval, equals(0));

      // Company Admin receives full organization-wide aggregation
      final adminCounts = await service.getManagerRequestOverviewCounts(
        userId: 'admin-1',
        organizationId: 'org-sobha',
        isCompanyAdmin: true,
      );
      expect(adminCounts.total, equals(1));
    });

    test('Requirement 7: Unauthorized users cannot record decisions or complete requests', () async {
      final service = RequestService.instance;

      final req = RequestRecord(
        id: 'req-protected',
        displayId: 'REQ-4001',
        organizationId: 'org-sobha',
        title: 'Confidential Access Request',
        description: 'Server room entry',
        requestType: 'Access',
        priority: 'High',
        requiredByDate: '2026-11-18',
        status: 'Pending',
        createdBy: 'staff-requester',
        createdByName: 'Staff Requester',
        createdByRole: 'Staff',
        approvers: const [
          RequestApproverRecord(
            id: 'appr-auth-1',
            requestId: 'req-protected',
            approverId: 'legitimate-approver',
            approverName: 'Authorized Approver',
            approverRole: 'Staff',
            stepOrder: 1,
            status: 'Pending',
          ),
        ],
      );

      service.seedMockRequest(req);

      // Unauthorized user attempts approval decision -> throws StateError
      expect(
        () => service.recordApprovalDecision(
          requestId: 'req-protected',
          decision: 'Approved',
          currentUserId: 'intruder-user',
          currentUserName: 'Intruder',
          currentUserRole: 'Staff',
        ),
        throwsA(isA<StateError>()),
      );

      // Legitimate approver records decision -> succeeds
      final approved = await service.recordApprovalDecision(
        requestId: 'req-protected',
        decision: 'Approved',
        currentUserId: 'legitimate-approver',
        currentUserName: 'Authorized Approver',
        currentUserRole: 'Staff',
      );
      expect(approved.status, equals('Approved'));
      expect(approved.isApproved, isTrue);

      // Approver cannot complete request (only requester or admin/scoped manager can complete)
      expect(
        approved.canUserComplete(
          'legitimate-approver',
          isManager: false,
          isCompanyAdmin: false,
        ),
        isFalse,
      );

      // Requester can complete request
      expect(
        approved.canUserComplete(
          'staff-requester',
          isManager: false,
          isCompanyAdmin: false,
        ),
        isTrue,
      );

      // Complete the request via service
      final completed = await service.completeRequest(
        requestId: 'req-protected',
        currentUserId: 'staff-requester',
        currentUserName: 'Staff Requester',
        currentUserRole: 'Staff',
      );
      expect(completed.status, equals('Completed'));
      expect(completed.isCompleted, isTrue);
    });
  });
}
