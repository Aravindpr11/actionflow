import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:action_flow/features/requests/models/request_models.dart';
import 'package:action_flow/features/requests/services/request_service.dart';
import 'package:action_flow/features/requests/screens/my_requests_screen.dart';
import 'package:action_flow/features/requests/screens/request_approval_screen.dart';
import 'package:action_flow/features/requests/screens/request_details_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/requests/screens/new_request_screen.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/models/team.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';

void main() {
  setUp(() {
    RequestService.useMockOnly = true;
    RequestService.instance.clearMockStore();
  });

  tearDown(() {
    RequestService.instance.clearMockStore();
    RequestService.useMockOnly = false;
  });

  group('Request Management — Model & Service Validation Tests', () {
    test('submitRequest fails when required fields are missing', () async {
      final service = RequestService.instance;

      expect(
        () => service.submitRequest(
          title: '',
          description: 'Valid description',
          requestType: RequestType.ptw,
          priority: RequestPriority.high,
          requiredByDate: '2026-12-01',
          approvers: [
            const RequestApproverRecord(
              id: '1',
              requestId: '',
              approverId: 'approver-1',
              approverName: 'Alice Manager',
              approverRole: 'HSE Manager',
            ),
          ],
          organizationId: 'org-1',
          currentUserId: 'user-1',
          currentUserName: 'Bob Staff',
          currentUserRole: 'Worker',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => service.submitRequest(
          title: 'PTW for Hot Work',
          description: '',
          requestType: RequestType.ptw,
          priority: RequestPriority.high,
          requiredByDate: '2026-12-01',
          approvers: [
            const RequestApproverRecord(
              id: '1',
              requestId: '',
              approverId: 'approver-1',
              approverName: 'Alice Manager',
              approverRole: 'HSE Manager',
            ),
          ],
          organizationId: 'org-1',
          currentUserId: 'user-1',
          currentUserName: 'Bob Staff',
          currentUserRole: 'Worker',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => service.submitRequest(
          title: 'Equipment Request',
          description: 'Need safety harness and gas detector',
          requestType: RequestType.equipment,
          priority: RequestPriority.medium,
          requiredByDate: '2026-12-01',
          approvers: const [], // No approvers
          organizationId: 'org-1',
          currentUserId: 'user-1',
          currentUserName: 'Bob Staff',
          currentUserRole: 'Worker',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('submitRequest creates a valid RequestRecord with approvers, attachments and history', () async {
      final service = RequestService.instance;

      final req = await service.submitRequest(
        title: 'Hot Work Permit - Phase 2 Boiler Room',
        description: 'Requires oxy-acetylene torch cutting and spark containment.',
        requestType: RequestType.ptw,
        priority: RequestPriority.critical,
        departmentName: 'Health, Safety & Environment',
        siteName: 'Main Fabrication Facility',
        requiredByDate: '2026-11-10',
        requiredByTime: '08:30 AM',
        approvalType: ApprovalType.sequential,
        additionalNotes: 'Fire watch watcher assigned.',
        approvers: [
          const RequestApproverRecord(
            id: 'app-1',
            requestId: '',
            approverId: 'user-approver-1',
            approverName: 'HSE Lead John',
            approverRole: 'HSE Lead',
            approverDepartment: 'HSE',
            stepOrder: 1,
          ),
          const RequestApproverRecord(
            id: 'app-2',
            requestId: '',
            approverId: 'user-approver-2',
            approverName: 'Site Director Sarah',
            approverRole: 'Site Director',
            approverDepartment: 'Operations',
            stepOrder: 2,
          ),
        ],
        rawAttachments: [
          {
            'name': 'risk_assessment.pdf',
            'size': 204800,
            'contentType': 'application/pdf',
          },
        ],
        organizationId: 'org-sobha',
        currentUserId: 'staff-worker-1',
        currentUserName: 'Ahmed Staff',
        currentUserRole: 'Safety Officer',
        currentUserEmail: 'ahmed@sobha.test',
      );

      expect(req.id, isNotEmpty);
      expect(req.displayId, startsWith('REQ-'));
      expect(req.title, equals('Hot Work Permit - Phase 2 Boiler Room'));
      expect(req.status, equals(RequestStatus.pending));
      expect(req.approvers.length, equals(2));
      expect(req.approvers[0].stepOrder, equals(1));
      expect(req.approvers[1].stepOrder, equals(2));
      expect(req.attachments.length, equals(1));
      expect(req.attachments.first.fileName, equals('risk_assessment.pdf'));
      expect(req.history.length, equals(1));
      expect(req.history.first.action, equals('Submitted'));
    });
  });

  group('Request Management — Sequential Approval Workflow', () {
    test('Sequential approval strictly enforces step order', () async {
      final service = RequestService.instance;

      final req = await service.submitRequest(
        title: 'Excavation Access Request',
        description: 'Underground conduit trenching near substation',
        requestType: RequestType.access,
        priority: RequestPriority.high,
        requiredByDate: '2026-11-15',
        approvalType: ApprovalType.sequential,
        approvers: [
          const RequestApproverRecord(
            id: 'a1',
            requestId: '',
            approverId: 'approver-step-1',
            approverName: 'Civil Supervisor',
            approverRole: 'Supervisor',
            stepOrder: 1,
          ),
          const RequestApproverRecord(
            id: 'a2',
            requestId: '',
            approverId: 'approver-step-2',
            approverName: 'Operations Manager',
            approverRole: 'Manager',
            stepOrder: 2,
          ),
        ],
        organizationId: 'org-sobha',
        currentUserId: 'staff-worker-1',
        currentUserName: 'Ahmed Staff',
        currentUserRole: 'Worker',
      );

      // 1. Initial State: Step 1 can approve, Step 2 CANNOT approve yet
      expect(req.canUserApprove('approver-step-1'), isTrue);
      expect(req.canUserApprove('approver-step-2'), isFalse);
      expect(req.pendingApproversSummary, equals('Civil Supervisor'));

      // 2. Approver 1 approves
      final afterStep1 = await service.recordApprovalDecision(
        requestId: req.id,
        decision: 'Approved',
        comments: 'Civil conditions verified.',
        currentUserId: 'approver-step-1',
        currentUserName: 'Civil Supervisor',
        currentUserRole: 'Supervisor',
      );

      expect(afterStep1.status, equals(RequestStatus.underReview));
      expect(afterStep1.approvers[0].isApproved, isTrue);
      expect(afterStep1.approvers[1].isPending, isTrue);
      expect(afterStep1.canUserApprove('approver-step-1'), isFalse);
      expect(afterStep1.canUserApprove('approver-step-2'), isTrue);
      expect(afterStep1.pendingApproversSummary, equals('Operations Manager'));

      // 3. Approver 2 approves
      final afterStep2 = await service.recordApprovalDecision(
        requestId: req.id,
        decision: 'Approved',
        comments: 'Approved for commencement.',
        currentUserId: 'approver-step-2',
        currentUserName: 'Operations Manager',
        currentUserRole: 'Manager',
      );

      expect(afterStep2.status, equals(RequestStatus.approved));
      expect(afterStep2.approvedCount, equals(2));
      expect(afterStep2.approvalProgress, equals('2 of 2 Approved'));
      expect(afterStep2.isApproved, isTrue);
      expect(afterStep2.approvedAt, isNotNull);
      expect(afterStep2.canUserApprove('approver-step-2'), isFalse);
    });
  });

  group('Request Management — Parallel Approval Workflow', () {
    test('Parallel approval allows independent concurrent sign-off', () async {
      final service = RequestService.instance;

      final req = await service.submitRequest(
        title: 'Material Clearance - Hazmat Solvents',
        description: 'Incoming shipment of industrial degreasers',
        requestType: RequestType.material,
        priority: RequestPriority.medium,
        requiredByDate: '2026-11-20',
        approvalType: ApprovalType.parallel,
        approvers: [
          const RequestApproverRecord(
            id: 'p1',
            requestId: '',
            approverId: 'hazmat-officer',
            approverName: 'Hazmat Officer',
            approverRole: 'Specialist',
          ),
          const RequestApproverRecord(
            id: 'p2',
            requestId: '',
            approverId: 'warehouse-manager',
            approverName: 'Warehouse Manager',
            approverRole: 'Manager',
          ),
        ],
        organizationId: 'org-sobha',
        currentUserId: 'staff-worker-1',
        currentUserName: 'Ahmed Staff',
        currentUserRole: 'Worker',
      );

      // In parallel mode, both can approve simultaneously
      expect(req.canUserApprove('hazmat-officer'), isTrue);
      expect(req.canUserApprove('warehouse-manager'), isTrue);

      // Warehouse Manager approves first
      final stepA = await service.recordApprovalDecision(
        requestId: req.id,
        decision: 'Approved',
        comments: 'Storage bay designated.',
        currentUserId: 'warehouse-manager',
        currentUserName: 'Warehouse Manager',
        currentUserRole: 'Manager',
      );

      expect(stepA.status, equals(RequestStatus.underReview));
      expect(stepA.approvedCount, equals(1));
      expect(stepA.canUserApprove('warehouse-manager'), isFalse);
      expect(stepA.canUserApprove('hazmat-officer'), isTrue);

      // Hazmat Officer approves second
      final stepB = await service.recordApprovalDecision(
        requestId: req.id,
        decision: 'Approved',
        comments: 'MSDS documentation verified.',
        currentUserId: 'hazmat-officer',
        currentUserName: 'Hazmat Officer',
        currentUserRole: 'Specialist',
      );

      expect(stepB.status, equals(RequestStatus.approved));
      expect(stepB.approvedCount, equals(2));
      expect(stepB.approvalProgress, equals('2 of 2 Approved'));
    });
  });

  group('Request Management — Rejection & Completion Workflows', () {
    test('Rejection requires reason, marks request Rejected, and halts workflow', () async {
      final service = RequestService.instance;

      final req = await service.submitRequest(
        title: 'Confined Space Entry',
        description: 'Vessel cleaning without gas testing certificate',
        requestType: RequestType.ptw,
        priority: RequestPriority.critical,
        requiredByDate: '2026-11-05',
        approvalType: ApprovalType.sequential,
        approvers: [
          const RequestApproverRecord(
            id: 'r1',
            requestId: '',
            approverId: 'hse-manager-1',
            approverName: 'HSE Manager',
            approverRole: 'Manager',
          ),
        ],
        organizationId: 'org-sobha',
        currentUserId: 'staff-worker-1',
        currentUserName: 'Ahmed Staff',
        currentUserRole: 'Worker',
      );

      // Attempting rejection without comment throws ArgumentError
      expect(
        () => service.recordApprovalDecision(
          requestId: req.id,
          decision: 'Rejected',
          comments: '', // empty!
          currentUserId: 'hse-manager-1',
          currentUserName: 'HSE Manager',
          currentUserRole: 'Manager',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Rejecting with valid comment
      final rejected = await service.recordApprovalDecision(
        requestId: req.id,
        decision: 'Rejected',
        comments: 'Mandatory 4-gas atmosphere calibration missing.',
        currentUserId: 'hse-manager-1',
        currentUserName: 'HSE Manager',
        currentUserRole: 'Manager',
      );

      expect(rejected.status, equals(RequestStatus.rejected));
      expect(rejected.rejectionReason, equals('Mandatory 4-gas atmosphere calibration missing.'));
      expect(rejected.rejectedBy, equals('hse-manager-1'));
      expect(rejected.isRejected, isTrue);

      // Cannot approve or change decision once rejected
      expect(
        () => service.recordApprovalDecision(
          requestId: req.id,
          decision: 'Approved',
          currentUserId: 'hse-manager-1',
          currentUserName: 'HSE Manager',
          currentUserRole: 'Manager',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('Forwarding appends forward record and audit event without altering request ID', () async {
      final service = RequestService.instance;

      final req = await service.submitRequest(
        title: 'Roof Access Work',
        description: 'HVAC fan maintenance on rooftop',
        requestType: RequestType.access,
        priority: RequestPriority.medium,
        requiredByDate: '2026-11-12',
        approvers: [
          const RequestApproverRecord(
            id: 'a1',
            requestId: '',
            approverId: 'm1',
            approverName: 'Building Manager',
            approverRole: 'Manager',
          ),
        ],
        organizationId: 'org-sobha',
        currentUserId: 'staff-1',
        currentUserName: 'Worker Mike',
        currentUserRole: 'Worker',
      );

      final forwarded = await service.forwardRequest(
        requestId: req.id,
        toUserId: 'lead-consultant-1',
        toUserName: 'Structural Consultant Peter',
        notes: 'Please review structural anchor points before final sign-off.',
        currentUserId: 'staff-1',
        currentUserName: 'Worker Mike',
        currentUserRole: 'Worker',
      );

      expect(forwarded.id, equals(req.id));
      expect(forwarded.forwards.length, equals(1));
      expect(forwarded.forwards.first.toUserName, equals('Structural Consultant Peter'));
      expect(forwarded.forwards.first.notes, contains('structural anchor points'));
      expect(forwarded.history.any((h) => h.action == 'Forwarded'), isTrue);
    });

    test('completeRequest transitions Approved request to Completed with timestamp', () async {
      final service = RequestService.instance;

      final req = await service.submitRequest(
        title: 'Heavy Crane Lift Clearance',
        description: 'Mobile crane setup in loading zone',
        requestType: RequestType.ptw,
        priority: RequestPriority.high,
        requiredByDate: '2026-11-06',
        approvers: [
          const RequestApproverRecord(
            id: 'a1',
            requestId: '',
            approverId: 'crane-lead',
            approverName: 'Rigging Superintendent',
            approverRole: 'Superintendent',
          ),
        ],
        organizationId: 'org-sobha',
        currentUserId: 'staff-1',
        currentUserName: 'Worker Mike',
        currentUserRole: 'Worker',
      );

      // Cannot complete while pending
      expect(
        () => service.completeRequest(
          requestId: req.id,
          currentUserId: 'staff-1',
          currentUserName: 'Worker Mike',
          currentUserRole: 'Worker',
        ),
        throwsA(isA<StateError>()),
      );

      // Approve first
      await service.recordApprovalDecision(
        requestId: req.id,
        decision: 'Approved',
        comments: 'Lift plan verified.',
        currentUserId: 'crane-lead',
        currentUserName: 'Rigging Superintendent',
        currentUserRole: 'Superintendent',
      );

      // Mark completed
      final completed = await service.completeRequest(
        requestId: req.id,
        notes: 'Lift finished safely without incidents.',
        currentUserId: 'staff-1',
        currentUserName: 'Worker Mike',
        currentUserRole: 'Worker',
      );

      expect(completed.status, equals(RequestStatus.completed));
      expect(completed.isCompleted, isTrue);
      expect(completed.completedAt, isNotNull);
      expect(completed.history.any((h) => h.action == 'Completed'), isTrue);
    });
  });

  group('Request Management — Staff Authority & Scope Isolation', () {
    test('Staff members only see requests where they are designated approvers', () async {
      final service = RequestService.instance;

      // Request 1: Designated approver is staff-approver-A
      await service.submitRequest(
        title: 'Electrical Isolation - Panel 4',
        description: 'LOTO lockout tagout required',
        requestType: RequestType.ptw,
        priority: RequestPriority.high,
        requiredByDate: '2026-11-08',
        approvers: [
          const RequestApproverRecord(
            id: 'app-a',
            requestId: '',
            approverId: 'staff-approver-A',
            approverName: 'Senior Electrician David',
            approverRole: 'Staff',
          ),
        ],
        organizationId: 'org-sobha',
        currentUserId: 'worker-1',
        currentUserName: 'John Worker',
        currentUserRole: 'Worker',
      );

      // Request 2: Designated approver is manager-only
      await service.submitRequest(
        title: 'Scaffold Dismantling - Tower B',
        description: 'Third party scaffolding strike',
        requestType: RequestType.ptw,
        priority: RequestPriority.medium,
        requiredByDate: '2026-11-09',
        approvers: [
          const RequestApproverRecord(
            id: 'app-m',
            requestId: '',
            approverId: 'manager-1',
            approverName: 'Safety Director',
            approverRole: 'Manager',
          ),
        ],
        organizationId: 'org-sobha',
        currentUserId: 'worker-2',
        currentUserName: 'Sam Worker',
        currentUserRole: 'Worker',
      );

      // Check authority for staff-approver-A -> true
      final hasAuthA = await service.hasStaffApprovalAuthority(
        userId: 'staff-approver-A',
        organizationId: 'org-sobha',
      );
      expect(hasAuthA, isTrue);

      // Check authority for unauthorized staff-B -> false
      final hasAuthB = await service.hasStaffApprovalAuthority(
        userId: 'staff-unauthorized-B',
        organizationId: 'org-sobha',
      );
      expect(hasAuthB, isFalse);

      // When staff-approver-A queries their approval inbox, they get ONLY Request 1
      final staffAInbox = await service.getApprovalRequests(
        userId: 'staff-approver-A',
        organizationId: 'org-sobha',
        isManager: false,
      );
      expect(staffAInbox.items.length, equals(1));
      expect(staffAInbox.items.first.title, contains('Electrical Isolation'));

      // Unauthorized staff gets 0 approval requests
      final staffBInbox = await service.getApprovalRequests(
        userId: 'staff-unauthorized-B',
        organizationId: 'org-sobha',
        isManager: false,
      );
      expect(staffBInbox.items, isEmpty);

      // Manager gets all in scope
      final managerInbox = await service.getApprovalRequests(
        userId: 'manager-1',
        organizationId: 'org-sobha',
        isManager: true,
      );
      expect(managerInbox.items.length, equals(2));
    });
  });

  group('Request Management — Widget & Screen Smoke Tests', () {
    testWidgets('MyRequestsScreen renders empty state, metrics, and list of user requests', (tester) async {
      final service = RequestService.instance;

      // Seed mock request
      await service.submitRequest(
        title: 'Safety Eyewash Inspection',
        description: 'Monthly functional check of eye wash stations',
        requestType: RequestType.equipment,
        priority: RequestPriority.low,
        requiredByDate: '2026-11-25',
        approvers: [
          const RequestApproverRecord(
            id: 'a1',
            requestId: '',
            approverId: 'mgr-1',
            approverName: 'Facility Manager',
            approverRole: 'Manager',
          ),
        ],
        organizationId: 'org-sobha',
        currentUserId: 'user-tester-1',
        currentUserName: 'Tester User',
        currentUserRole: 'Staff',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MyRequestsScreen(
                currentUserId: 'user-tester-1',
                currentUserName: 'Tester User',
                currentUserRole: 'Staff',
                organizationId: 'org-sobha',
                isManager: false,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Header & Metrics
      expect(find.text('My Requests'), findsOneWidget);
      expect(find.text('Total Submitted'), findsOneWidget);
      expect(find.text('Safety Eyewash Inspection'), findsOneWidget);
      expect(find.text('View Details'), findsOneWidget);
      expect(find.text('Forward'), findsOneWidget);
    });

    testWidgets('RequestApprovalScreen renders approval queue and allows reviewing requests', (tester) async {
      final service = RequestService.instance;

      await service.submitRequest(
        title: 'Excavation Permit Trench A',
        description: 'Shallow trench for optical fiber',
        requestType: RequestType.access,
        priority: RequestPriority.high,
        requiredByDate: '2026-11-30',
        approvers: [
          const RequestApproverRecord(
            id: 'app-mgr-1',
            requestId: '',
            approverId: 'approver-lead-1',
            approverName: 'Approver Lead',
            approverRole: 'Manager',
          ),
        ],
        organizationId: 'org-sobha',
        currentUserId: 'creator-1',
        currentUserName: 'Creator Person',
        currentUserRole: 'Staff',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RequestApprovalScreen(
                currentUserId: 'approver-lead-1',
                currentUserName: 'Approver Lead',
                currentUserRole: 'Manager',
                organizationId: 'org-sobha',
                isManager: true,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Request Approval'), findsOneWidget);
      expect(find.text('Excavation Permit Trench A'), findsOneWidget);
      expect(find.text('Your Decision Needed'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
    });

    testWidgets('RequestDetailsScreen renders request overview, workflow stepper, and history', (tester) async {
      final service = RequestService.instance;

      final req = await service.submitRequest(
        title: 'Deep Trenching Permit',
        description: 'Deep excavation exceeding 1.5m with trench box shoring',
        requestType: RequestType.ptw,
        priority: RequestPriority.critical,
        departmentName: 'Civil Engineering',
        siteName: 'Tower 4 Basement',
        requiredByDate: '2026-11-14',
        requiredByTime: '10:00 AM',
        approvers: [
          const RequestApproverRecord(
            id: 'a1',
            requestId: '',
            approverId: 'approver-lead-1',
            approverName: 'Geotech Engineer',
            approverRole: 'Engineer',
            stepOrder: 1,
          ),
        ],
        rawAttachments: [
          {
            'name': 'shoring_calculation.pdf',
            'size': 1048576,
            'contentType': 'application/pdf',
          },
        ],
        organizationId: 'org-sobha',
        currentUserId: 'creator-1',
        currentUserName: 'Creator Person',
        currentUserRole: 'Staff',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RequestDetailsScreen(
            requestId: req.id,
            initialRequest: req,
            currentUserId: 'approver-lead-1',
            currentUserName: 'Approver Lead',
            currentUserRole: 'Engineer',
            organizationId: 'org-sobha',
            isManager: true,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Deep Trenching Permit'), findsWidgets);
      expect(find.textContaining('Geotech Engineer'), findsOneWidget);
      expect(find.text('DETAILED DESCRIPTION'), findsOneWidget);
      expect(find.text('Approval Chain'), findsOneWidget);
      expect(find.text('Audit Trail & History'), findsOneWidget);
      expect(find.text('shoring_calculation.pdf'), findsOneWidget);
    });
  });

  group('Request Management — Navigation Integration in Portals', () {
    testWidgets('Manager Portal sidebar displays New Request, Request Approval, and My Requests', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final managerProfile = UserProfile.mockManager().copyWith(
        id: 'mgr-portal-user',
        name: 'Manager Alice',
        email: 'alice@sobha.test',
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

      expect(find.byKey(const ValueKey('sidebar_item_New Request')), findsOneWidget);
      expect(find.byKey(const ValueKey('sidebar_item_Request Approval')), findsOneWidget);
      expect(find.byKey(const ValueKey('sidebar_item_My Requests')), findsOneWidget);
    });

    testWidgets('Worker Portal sidebar always shows Request Approval for Staff B (no assignments), displays empty list and zero counts, and rejects unauthorized decision', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = RequestService.instance;
      // Seed a request where another user is the approver
      final seedReq = await service.submitRequest(
        title: 'Safety Valve Check',
        description: 'Assigned to manager',
        requestType: RequestType.ptw,
        priority: RequestPriority.high,
        requiredByDate: '2026-12-01',
        approvers: [
          const RequestApproverRecord(
            id: 'app-seed-other',
            requestId: '',
            approverId: 'other-approver-mgr',
            approverName: 'Manager Other',
            approverRole: 'Manager',
          ),
        ],
        organizationId: 'org-sobha',
        currentUserId: 'creator-worker',
        currentUserName: 'Creator Worker',
        currentUserRole: 'Worker',
      );

      final staffProfileB = UserProfile.mockStaff().copyWith(
        id: 'staff-portal-unauth-user-b',
        name: 'Worker Charlie',
        email: 'charlie@sobha.test',
        role: 'worker',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: WorkerDashboardScreen(
            userProfile: staffProfileB,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('worker_sidebar_item_New Request')), findsOneWidget);
      expect(find.byKey(const ValueKey('worker_sidebar_item_My Requests')), findsOneWidget);
      // Standardized: Request Approval MUST be visible for all staff users
      expect(find.byKey(const ValueKey('worker_sidebar_item_Request Approval')), findsOneWidget);

      // Verify empty approval list and zero counts for Staff B
      final counts = await service.getApprovalSummaryCounts(
        userId: staffProfileB.id,
        organizationId: 'org-sobha',
        isManager: false,
      );
      expect(counts.myActionRequired, equals(0));
      expect(counts.totalInScope, equals(0));
      expect(counts.approved, equals(0));
      expect(counts.rejected, equals(0));

      final inboxB = await service.getApprovalRequests(
        userId: staffProfileB.id,
        organizationId: 'org-sobha',
        isManager: false,
      );
      expect(inboxB.items, isEmpty);
      expect(inboxB.totalCount, equals(0));

      // Direct unauthorized approval attempt by Staff B is rejected
      expect(
        () => service.recordApprovalDecision(
          requestId: seedReq.id,
          decision: 'Approved',
          currentUserId: staffProfileB.id,
          currentUserName: staffProfileB.name,
          currentUserRole: 'Worker',
        ),
        throwsA(isA<StateError>()),
      );
    });

    testWidgets('Worker Portal sidebar displays Request Approval for Staff A (with assignments), displays assigned requests, and allows authorized decision', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = RequestService.instance;
      // Seed a request where this staff member IS an approver
      final req = await service.submitRequest(
        title: 'Safety Isolation Sign-off',
        description: 'Assigned to authorized staff',
        requestType: RequestType.ptw,
        priority: RequestPriority.high,
        requiredByDate: '2026-12-01',
        approvers: [
          const RequestApproverRecord(
            id: 'app-auth-1',
            requestId: '',
            approverId: 'staff-portal-auth-user-a',
            approverName: 'Senior Technician David',
            approverRole: 'Staff',
          ),
        ],
        organizationId: 'org-sobha',
        currentUserId: 'creator-other',
        currentUserName: 'Other Worker',
        currentUserRole: 'Worker',
      );

      final authStaffProfileA = UserProfile.mockStaff().copyWith(
        id: 'staff-portal-auth-user-a',
        name: 'Senior Technician David',
        email: 'david@sobha.test',
        role: 'worker',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: WorkerDashboardScreen(
            userProfile: authStaffProfileA,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('worker_sidebar_item_New Request')), findsOneWidget);
      expect(find.byKey(const ValueKey('worker_sidebar_item_My Requests')), findsOneWidget);
      expect(find.byKey(const ValueKey('worker_sidebar_item_Request Approval')), findsOneWidget);

      // Verify assigned request in inbox for Staff A
      final inboxA = await service.getApprovalRequests(
        userId: authStaffProfileA.id,
        organizationId: 'org-sobha',
        isManager: false,
      );
      expect(inboxA.items.any((r) => r.id == req.id), isTrue);

      // Authorized approval decision by Staff A works
      final approved = await service.recordApprovalDecision(
        requestId: req.id,
        decision: 'Approved',
        comments: 'Verified electrical isolation.',
        currentUserId: authStaffProfileA.id,
        currentUserName: authStaffProfileA.name,
        currentUserRole: 'Worker',
      );
      expect(approved.isApproved, isTrue);
    });
  });

  group('Request Management — Security Hardening & Functional Corrections Tests', () {
    test('getAttachmentDownloadUrl returns mock URL and throws on empty path', () async {
      final service = RequestService.instance;
      expect(() => service.getAttachmentDownloadUrl(''), throwsA(isA<ArgumentError>()));

      final url = await service.getAttachmentDownloadUrl('org-1/requests/123_doc.pdf');
      expect(url, contains('mock-storage.actionflow.local/org-1/requests/123_doc.pdf'));
    });

    test('completeRequest enforces strict authorization rules', () async {
      final service = RequestService.instance;

      // Seed an approved request
      final req = await service.submitRequest(
        title: 'Roof Access Permit',
        description: 'Need roof access for antenna repair',
        requestType: RequestType.ptw,
        priority: RequestPriority.medium,
        requiredByDate: '2026-12-10',
        approvers: [
          const RequestApproverRecord(
            id: 'app-comp-1',
            requestId: '',
            approverId: 'approver-lead-1',
            approverName: 'Lead Engineer',
            approverRole: 'Staff',
          ),
        ],
        organizationId: 'org-sobha',
        currentUserId: 'submitter-bob',
        currentUserName: 'Bob Staff',
        currentUserRole: 'Worker',
      );

      // Attempt to complete while Pending (MUST FAIL)
      expect(
        () => service.completeRequest(
          requestId: req.id,
          currentUserId: 'submitter-bob',
          currentUserName: 'Bob Staff',
          currentUserRole: 'Worker',
        ),
        throwsA(isA<StateError>()),
      );

      // Approve the request
      await service.recordApprovalDecision(
        requestId: req.id,
        decision: 'Approved',
        comments: 'Ready for execution',
        currentUserId: 'approver-lead-1',
        currentUserName: 'Lead Engineer',
        currentUserRole: 'Staff',
      );

      // Unauthorized unrelated staff member tries to complete (MUST FAIL)
      expect(
        () => service.completeRequest(
          requestId: req.id,
          currentUserId: 'malicious-intruder',
          currentUserName: 'Intruder',
          currentUserRole: 'Worker',
        ),
        throwsA(isA<StateError>()),
      );

      // Authorized submitter completes request (MUST SUCCEED)
      final completed = await service.completeRequest(
        requestId: req.id,
        notes: 'Work done successfully',
        currentUserId: 'submitter-bob',
        currentUserName: 'Bob Staff',
        currentUserRole: 'Worker',
      );

      expect(completed.isCompleted, isTrue);
      expect(completed.completedBy, equals('submitter-bob'));

      // Duplicate completion must fail
      expect(
        () => service.completeRequest(
          requestId: req.id,
          currentUserId: 'submitter-bob',
          currentUserName: 'Bob Staff',
          currentUserRole: 'Worker',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('forwardRequest blocks self-forwarding and unauthorized forwarding', () async {
      final service = RequestService.instance;

      final req = await service.submitRequest(
        title: 'Hot Work Permit - Phase 3',
        description: 'Cutting torch work',
        requestType: RequestType.ptw,
        priority: RequestPriority.high,
        requiredByDate: '2026-12-12',
        approvers: [
          const RequestApproverRecord(
            id: 'app-fwd-1',
            requestId: '',
            approverId: 'approver-sam',
            approverName: 'Sam Approver',
            approverRole: 'Staff',
          ),
        ],
        organizationId: 'org-sobha',
        currentUserId: 'requester-alice',
        currentUserName: 'Alice Worker',
        currentUserRole: 'Worker',
      );

      // Cannot forward to self
      expect(
        () => service.forwardRequest(
          requestId: req.id,
          toUserId: 'requester-alice',
          toUserName: 'Alice Worker',
          currentUserId: 'requester-alice',
          currentUserName: 'Alice Worker',
          currentUserRole: 'Worker',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Unauthorized staff cannot forward
      expect(
        () => service.forwardRequest(
          requestId: req.id,
          toUserId: 'target-charlie',
          toUserName: 'Charlie Staff',
          currentUserId: 'random-unrelated-user',
          currentUserName: 'Random Person',
          currentUserRole: 'Worker',
        ),
        throwsA(isA<StateError>()),
      );

      // Authorized submitter can forward
      final forwarded = await service.forwardRequest(
        requestId: req.id,
        toUserId: 'target-charlie',
        toUserName: 'Charlie Staff',
        notes: 'Please review specs',
        currentUserId: 'requester-alice',
        currentUserName: 'Alice Worker',
        currentUserRole: 'Worker',
      );

      expect(forwarded.forwards.length, equals(1));
      expect(forwarded.forwards.first.toUserId, equals('target-charlie'));
    });

    test('Dedicated Department, Site, Date-Range Filters and Pagination', () async {
      final service = RequestService.instance;

      // Seed requests across departments and sites
      await service.submitRequest(
        title: 'HSE Downtown Permit',
        description: 'Trenching',
        requestType: RequestType.ptw,
        priority: RequestPriority.high,
        departmentId: 'dept-hse',
        departmentName: 'HSE',
        siteId: 'site-downtown',
        siteName: 'Downtown Tower',
        requiredByDate: '2026-12-01',
        approvers: [
          const RequestApproverRecord(id: '1', requestId: '', approverId: 'a1', approverName: 'Appr 1', approverRole: 'Staff'),
        ],
        organizationId: 'org-1',
        currentUserId: 'user-filter-test',
        currentUserName: 'Filter Tester',
        currentUserRole: 'Worker',
      );

      await service.submitRequest(
        title: 'Civil Marina Request',
        description: 'Concrete inspection',
        requestType: RequestType.equipment,
        priority: RequestPriority.low,
        departmentId: 'dept-civil',
        departmentName: 'Civil Engineering',
        siteId: 'site-marina',
        siteName: 'Marina Wharf',
        requiredByDate: '2026-12-25',
        approvers: [
          const RequestApproverRecord(id: '2', requestId: '', approverId: 'a1', approverName: 'Appr 1', approverRole: 'Staff'),
        ],
        organizationId: 'org-1',
        currentUserId: 'user-filter-test',
        currentUserName: 'Filter Tester',
        currentUserRole: 'Worker',
      );

      // 1. Filter by Department
      final hseList = await service.getMyRequests(
        userId: 'user-filter-test',
        organizationId: 'org-1',
        departmentId: 'HSE',
      );
      expect(hseList.items.length, equals(1));
      expect(hseList.totalCount, equals(1));
      expect(hseList.items.first.title, equals('HSE Downtown Permit'));

      // 2. Filter by Site
      final marinaList = await service.getMyRequests(
        userId: 'user-filter-test',
        organizationId: 'org-1',
        siteId: 'Marina Wharf',
      );
      expect(marinaList.items.length, equals(1));
      expect(marinaList.totalCount, equals(1));
      expect(marinaList.items.first.title, equals('Civil Marina Request'));

      // 3. Filter by Date Range
      final earlyRangeList = await service.getMyRequests(
        userId: 'user-filter-test',
        organizationId: 'org-1',
        startDate: DateTime(2026, 11, 20),
        endDate: DateTime(2026, 12, 5),
      );
      expect(earlyRangeList.items.length, equals(1));
      expect(earlyRangeList.items.first.title, equals('HSE Downtown Permit'));

      // 4. Pagination
      final page1 = await service.getMyRequests(
        userId: 'user-filter-test',
        organizationId: 'org-1',
        page: 1,
        pageSize: 1,
      );
      expect(page1.items.length, equals(1));
      expect(page1.totalCount, equals(2));
      expect(page1.totalPages, equals(2));
      expect(page1.hasNextPage, isTrue);

      final page2 = await service.getMyRequests(
        userId: 'user-filter-test',
        organizationId: 'org-1',
        page: 2,
        pageSize: 1,
      );
      expect(page2.items.length, equals(1));
      expect(page2.hasNextPage, isFalse);
      expect(page2.hasPreviousPage, isTrue);
      expect(page1.items.first.id, isNot(equals(page2.items.first.id)));
    });

    test('canUserComplete correctly evaluates user authorization', () {
      final baseReq = RequestRecord(
        id: 'req-can-complete-1',
        displayId: 'REQ-9999',
        organizationId: 'org-1',
        title: 'Title',
        description: 'Desc',
        requestType: RequestType.ptw,
        priority: RequestPriority.high,
        requiredByDate: '2026-12-01',
        status: RequestStatus.approved,
        createdBy: 'requester-1',
        createdByName: 'Requester',
        createdByRole: 'Worker',
        approvers: [
          const RequestApproverRecord(
            id: 'app-1',
            requestId: 'req-can-complete-1',
            approverId: 'approver-1',
            approverName: 'Approver',
            approverRole: 'Staff',
            status: 'Approved',
          ),
        ],
      );

      // Submitter can complete
      expect(baseReq.canUserComplete('requester-1'), isTrue);

      // Designated approver CANNOT complete
      expect(baseReq.canUserComplete('approver-1'), isFalse);

      // Company admin can complete
      expect(baseReq.canUserComplete('admin-user', isCompanyAdmin: true), isTrue);

      // Scoped manager can complete
      expect(baseReq.canUserComplete('mgr-user', isManager: true, isScoped: true), isTrue);

      // Out-of-scope manager CANNOT complete
      expect(baseReq.canUserComplete('mgr-user', isManager: true, isScoped: false), isFalse);

      // Unrelated staff CANNOT complete
      expect(baseReq.canUserComplete('unrelated-user'), isFalse);

      // If status is Pending or Completed, nobody can complete
      final pendingReq = baseReq.copyWith(status: RequestStatus.pending);
      expect(pendingReq.canUserComplete('requester-1'), isFalse);

      final completedReq = baseReq.copyWith(status: RequestStatus.completed);
      expect(completedReq.canUserComplete('requester-1'), isFalse);
    });

    test('completeRequest service method denies approver and allows requester and manager', () async {
      final service = RequestService.instance;
      // Setup mock request approved
      final req = await service.submitRequest(
        title: 'Completion Auth Verification Test',
        description: 'Test description',
        requestType: RequestType.ptw,
        priority: RequestPriority.medium,
        departmentName: 'HSE',
        siteName: 'Main Site',
        requiredByDate: '2026-12-01',
        currentUserId: 'author-user',
        currentUserName: 'Author',
        currentUserRole: 'Worker',
        currentUserEmail: 'author@test.com',
        organizationId: 'org-1',
        approvers: [
          const RequestApproverRecord(
            id: 'app-test-1',
            requestId: '',
            approverId: 'approver-only',
            approverName: 'Approver Person',
            approverRole: 'Staff',
          ),
        ],
      );

      // Approve it first
      await service.recordApprovalDecision(
        requestId: req.id,
        decision: 'Approved',
        comments: 'Looks good',
        currentUserId: 'approver-only',
        currentUserName: 'Approver Person',
        currentUserRole: 'Staff',
      );

      // 1. Approver attempts to complete -> throws Access Denied
      expect(
        () => service.completeRequest(
          requestId: req.id,
          currentUserId: 'approver-only',
          currentUserName: 'Approver Person',
          currentUserRole: 'Staff',
        ),
        throwsA(isA<StateError>()),
      );

      // 2. Author (requester) completes -> succeeds
      final completed = await service.completeRequest(
        requestId: req.id,
        currentUserId: 'author-user',
        currentUserName: 'Author',
        currentUserRole: 'Worker',
      );
      expect(completed.isCompleted, isTrue);
    });
  });

  group('Request Management — Searchable Approver Selection & Strict Admin Exclusion Tests', () {
    test('submitRequest rejects approvers with Admin role in client validation', () async {
      final service = RequestService.instance;

      expect(
        () => service.submitRequest(
          title: 'Request with Admin Approver',
          description: 'This must be rejected before saving',
          requestType: RequestType.equipment,
          priority: RequestPriority.high,
          requiredByDate: '2026-12-01',
          approvers: [
            const RequestApproverRecord(
              id: 'app-admin',
              requestId: '',
              approverId: 'admin-1',
              approverName: 'Admin Person',
              approverRole: 'System Administrator',
            ),
          ],
          organizationId: 'org-1',
          currentUserId: 'user-1',
          currentUserName: 'Requester',
          currentUserRole: 'Worker',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('cannot be designated as an approver'),
          ),
        ),
      );
    });

    test('submitRequest rejects duplicate approvers in client validation', () async {
      final service = RequestService.instance;

      expect(
        () => service.submitRequest(
          title: 'Request with Duplicate Approvers',
          description: 'This must be rejected before saving',
          requestType: RequestType.material,
          priority: RequestPriority.medium,
          requiredByDate: '2026-12-01',
          approvers: [
            const RequestApproverRecord(
              id: 'app-1',
              requestId: '',
              approverId: 'manager-1',
              approverName: 'Jane Manager',
              approverRole: 'HSE Manager',
            ),
            const RequestApproverRecord(
              id: 'app-2',
              requestId: '',
              approverId: 'manager-1', // Duplicate ID
              approverName: 'Jane Manager',
              approverRole: 'HSE Manager',
            ),
          ],
          organizationId: 'org-1',
          currentUserId: 'user-1',
          currentUserName: 'Requester',
          currentUserRole: 'Worker',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Duplicate approver designated'),
          ),
        ),
      );
    });

    testWidgets('NewRequestScreen strictly excludes Admin users from available approver list', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NewRequestScreen(
              currentUserId: 'test-user-1',
              currentUserName: 'Test Staff',
              currentUserRole: 'Staff',
              organizationId: 'SOBHA-001',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the admin user in MockPeopleStore
      final adminUsers = MockPeopleStore.instance.people.where((p) => p.role == UserRole.admin).toList();
      expect(adminUsers, isNotEmpty, reason: 'MockPeopleStore should have at least one Admin user for testing');

      // The search field must exist
      expect(find.byKey(const Key('approver_search_field')), findsOneWidget);

      // Verify no DropdownMenuItem contains any admin's name
      for (final admin in adminUsers) {
        final adminItemFinder = find.descendant(
          of: find.byKey(const Key('approver_selection_dropdown')),
          matching: find.textContaining(admin.name),
        );
        expect(adminItemFinder, findsNothing);
      }
    });

    testWidgets('NewRequestScreen real-time search filters approvers and shows empty state', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NewRequestScreen(
              currentUserId: 'test-user-1',
              currentUserName: 'Test Staff',
              currentUserRole: 'Staff',
              organizationId: 'SOBHA-001',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchFieldFinder = find.byKey(const Key('approver_search_field'));
      expect(searchFieldFinder, findsOneWidget);

      // 1. Search for nonexistent approver
      await tester.enterText(searchFieldFinder, 'zzz_unknown_9999');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('no_approvers_found_state')), findsOneWidget);
      expect(find.textContaining('No eligible approvers found matching "zzz_unknown_9999"'), findsOneWidget);

      // 2. Clear search using clear button
      final clearBtnFinder = find.byKey(const Key('clear_approver_search_button'));
      expect(clearBtnFinder, findsOneWidget);
      await tester.tap(clearBtnFinder);
      await tester.pumpAndSettle();

      // Empty state is gone and dropdown is back
      expect(find.byKey(const Key('no_approvers_found_state')), findsNothing);
      expect(find.byKey(const Key('approver_selection_dropdown')), findsOneWidget);

      // 3. Search by valid query (case-insensitive)
      final eligibleNonAdmin = MockPeopleStore.instance.people
          .firstWhere((p) => p.role != UserRole.admin && !p.roleLabel.toLowerCase().contains('admin'));

      await tester.enterText(searchFieldFinder, eligibleNonAdmin.name.toLowerCase());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('no_approvers_found_state')), findsNothing);
      expect(find.byKey(const Key('approver_selection_dropdown')), findsOneWidget);
    });

    testWidgets('NewRequestScreen preserves designated approvers when search query changes', (tester) async {
      tester.view.physicalSize = const Size(1280, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NewRequestScreen(
              currentUserId: 'test-user-1',
              currentUserName: 'Test Staff',
              currentUserRole: 'Staff',
              organizationId: 'SOBHA-001',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find an eligible user
      final eligibleUsers = MockPeopleStore.instance.people
          .where((p) => p.role != UserRole.admin && !p.roleLabel.toLowerCase().contains('admin'))
          .toList();
      final user1 = eligibleUsers[0];
      final user2 = eligibleUsers[1];

      // Tap dropdown to select user1
      await tester.tap(find.byKey(const Key('approver_selection_dropdown')));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining(user1.name).last);
      await tester.pumpAndSettle();

      // Tap Add Approver
      await tester.tap(find.byKey(const Key('add_approver_button')));
      await tester.pumpAndSettle();

      // user1 is now designated as Step 1
      expect(find.text(user1.name), findsOneWidget);
      expect(find.text('Step 1'), findsOneWidget);

      // Now filter by a query that does NOT match user1 (e.g. user2's name)
      final searchFieldFinder = find.byKey(const Key('approver_search_field'));
      await tester.enterText(searchFieldFinder, user2.name);
      await tester.pumpAndSettle();

      // user1 must STILL be in the designated approvers list
      expect(find.text(user1.name), findsOneWidget);
      expect(find.text('Step 1'), findsOneWidget);

      // Clear search
      await tester.tap(find.byKey(const Key('clear_approver_search_button')));
      await tester.pumpAndSettle();

      // user1 is still in the list
      expect(find.text(user1.name), findsOneWidget);
      expect(find.text('Step 1'), findsOneWidget);
    });

    testWidgets('NewRequestScreen allows Staff/Manager with Administrator-like designations as approvers', (tester) async {
      tester.view.physicalSize = const Size(1280, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Add a test user whose designation contains 'Administrator' but canonical role is Manager
      final adminDesigManager = Person(
        id: 'user-contracts-admin',
        name: 'Sarah Connor',
        email: 'sarah.connor@test.com',
        phone: '12345',
        designation: 'Contracts Administrator',
        type: PersonType.internalUser,
        isActive: true,
        role: UserRole.departmentManager,
        department: 'Operations',
      );
      MockPeopleStore.instance.people.add(adminDesigManager);
      addTearDown(() => MockPeopleStore.instance.people.removeWhere((p) => p.id == 'user-contracts-admin'));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NewRequestScreen(
              currentUserId: 'test-user-1',
              currentUserName: 'Test Staff',
              currentUserRole: 'Staff',
              organizationId: 'SOBHA-001',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Search for 'Contracts Administrator'
      final searchFieldFinder = find.byKey(const Key('approver_search_field'));
      await tester.enterText(searchFieldFinder, 'Contracts Administrator');
      await tester.pumpAndSettle();

      // Sarah Connor should be present and selectable
      expect(find.byKey(const Key('no_approvers_found_state')), findsNothing);
      expect(find.byKey(const Key('approver_selection_dropdown')), findsOneWidget);

      await tester.tap(find.byKey(const Key('approver_selection_dropdown')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Sarah Connor'), findsWidgets);
    });
  });
}
