import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:action_flow/features/requests/models/request_models.dart';
import 'package:action_flow/features/requests/screens/my_requests_screen.dart';
import 'package:action_flow/features/requests/screens/request_approval_screen.dart';
import 'package:action_flow/features/requests/screens/request_details_screen.dart';
import 'package:action_flow/features/requests/services/request_service.dart';
import 'package:action_flow/models/organization.dart';

void main() {
  const orgId = Organization.sobhaId;
  const requesterStaffId = 'staff-requester-uuid';
  const scopedManagerId = 'manager-scoped-uuid';
  const outOfScopeManagerId = 'manager-out-of-scope-uuid';
  const unrelatedStaffId = 'staff-unrelated-uuid';
  const adminId = 'admin-uuid';

  final approvedRequest = RequestRecord(
    id: 'req-approved-1',
    displayId: 'REQ-2001',
    organizationId: orgId,
    title: 'Approved Tower Crane Mobilization',
    description: 'All safety signatures completed',
    requestType: RequestType.equipment,
    priority: RequestPriority.high,
    requiredByDate: '2026-11-20',
    status: RequestStatus.approved,
    departmentId: 'dept-1',
    departmentName: 'Civil Engineering',
    siteId: 'site-1',
    siteName: 'Site Alpha',
    createdBy: requesterStaffId,
    createdByName: 'John Staff',
    createdByRole: 'Staff',
    approvers: const [
      RequestApproverRecord(
        id: 'appr-1',
        requestId: 'req-approved-1',
        approverId: scopedManagerId,
        approverName: 'Sarah Connor',
        approverRole: 'Manager',
        stepOrder: 1,
        status: RequestStatus.approved,
      ),
    ],
  );

  final pendingRequest = RequestRecord(
    id: 'req-pending-1',
    displayId: 'REQ-2002',
    organizationId: orgId,
    title: 'Pending Hot Work Permit',
    description: 'Awaiting review',
    requestType: RequestType.ptw,
    priority: RequestPriority.medium,
    requiredByDate: '2026-11-21',
    status: RequestStatus.pending,
    departmentId: 'dept-1',
    departmentName: 'Civil Engineering',
    siteId: 'site-1',
    siteName: 'Site Alpha',
    createdBy: requesterStaffId,
    createdByName: 'John Staff',
    createdByRole: 'Staff',
  );

  final rejectedRequest = RequestRecord(
    id: 'req-rejected-1',
    displayId: 'REQ-2003',
    organizationId: orgId,
    title: 'Rejected Electrical Access',
    description: 'Documentation missing',
    requestType: RequestType.ptw,
    priority: RequestPriority.low,
    requiredByDate: '2026-11-22',
    status: RequestStatus.rejected,
    departmentId: 'dept-1',
    departmentName: 'Civil Engineering',
    siteId: 'site-1',
    siteName: 'Site Alpha',
    createdBy: requesterStaffId,
    createdByName: 'John Staff',
    createdByRole: 'Staff',
  );

  group('RequestRecord.canUserDelete Authorization & Status Unit Tests', () {
    test('Only Approved requests can be deleted', () {
      expect(approvedRequest.canUserDelete(requesterStaffId), isTrue);
      expect(pendingRequest.canUserDelete(requesterStaffId), isFalse);
      expect(rejectedRequest.canUserDelete(requesterStaffId), isFalse);
    });

    test('Requester (Staff or Manager) who authored the request can delete', () {
      expect(approvedRequest.canUserDelete(requesterStaffId), isTrue);
      // Even if not manager or admin
      expect(approvedRequest.canUserDelete(requesterStaffId, isManager: false, isCompanyAdmin: false), isTrue);
    });

    test('Scoped Manager can delete in-scope Approved request', () {
      expect(approvedRequest.canUserDelete(scopedManagerId, isManager: true, isScoped: true), isTrue);
    });

    test('Out-of-scope Manager CANNOT delete Approved request', () {
      expect(approvedRequest.canUserDelete(outOfScopeManagerId, isManager: true, isScoped: false), isFalse);
    });

    test('Unrelated Staff CANNOT delete Approved request', () {
      expect(approvedRequest.canUserDelete(unrelatedStaffId, isManager: false, isScoped: false), isFalse);
    });

    test('Company Administrator can delete Approved request', () {
      expect(approvedRequest.canUserDelete(adminId, isCompanyAdmin: true), isTrue);
    });

    test('RequestDeletionResult parses JSON response with queued storage files accurately', () {
      final json = {
        'success': true,
        'deleted_request_id': 'req-123',
        'deleted_display_id': 'REQ-123',
        'queued_storage_files_count': 2,
        'deleted_notifications_count': 3,
        'storage_cleanup_status': 'queued',
      };
      final res = RequestDeletionResult.fromJson(json);
      expect(res.success, isTrue);
      expect(res.requestId, 'req-123');
      expect(res.displayId, 'REQ-123');
      expect(res.queuedStorageFilesCount, 2);
      expect(res.deletedNotificationsCount, 3);
      expect(res.storageCleanupStatus, 'queued');
      expect(res.isStorageQueued, isTrue);
      expect(res.isStorageCleanedUp, isFalse);
    });
  });

  group('RequestDetailsScreen Permanent Deletion Widget Tests', () {
    setUp(() {
      RequestService.useMockOnly = true;
      RequestService.instance.clearMockStore();
      RequestService.instance.seedMockRequest(approvedRequest);
    });

    tearDown(() {
      RequestService.instance.clearMockStore();
      RequestService.useMockOnly = false;
    });

    testWidgets('Delete button appears for authorized scoped manager and cancelling dialog preserves request', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RequestDetailsScreen(
              requestId: approvedRequest.id,
              initialRequest: approvedRequest,
              currentUserId: scopedManagerId,
              currentUserName: 'Sarah Connor',
              currentUserRole: 'manager',
              currentUserEmail: 'sarah.c@sobha.com',
              organizationId: orgId,
              isManager: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find Delete Request button
      final deleteBtn = find.byKey(const Key('delete_request_button'));
      expect(deleteBtn, findsOneWidget);

      // Tap Delete Request
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      // Verify permanent confirmation dialog is displayed
      expect(find.text('Permanently Delete Request?'), findsOneWidget);
      expect(find.textContaining('This action is permanent and cannot be undone'), findsOneWidget);
      expect(find.byKey(const Key('confirm_delete_request_button')), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Verify dialog dismissed and request still exists
      expect(find.text('Permanently Delete Request?'), findsNothing);
      expect(RequestService.instance.mockRequests.length, 1);
    });

    testWidgets('Confirming permanent delete executes deletion, shows SnackBar and pops screen', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool popped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                key: const Key('open_details_btn'),
                onPressed: () {
                  Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => RequestDetailsScreen(
                        requestId: approvedRequest.id,
                        initialRequest: approvedRequest,
                        currentUserId: requesterStaffId,
                        currentUserName: 'John Staff',
                        currentUserRole: 'staff',
                        currentUserEmail: 'john.s@sobha.com',
                        organizationId: orgId,
                        isManager: false,
                      ),
                    ),
                  ).then((res) {
                    if (res == true) popped = true;
                  });
                },
                child: const Text('Open Details'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open RequestDetailsScreen
      await tester.tap(find.byKey(const Key('open_details_btn')));
      await tester.pumpAndSettle();

      // Tap Delete Request
      await tester.tap(find.byKey(const Key('delete_request_button')));
      await tester.pumpAndSettle();

      // Tap Permanently Delete
      await tester.tap(find.byKey(const Key('confirm_delete_request_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify SnackBar and deletion
      expect(find.text('Request REQ-2001 has been permanently deleted.'), findsOneWidget);
      expect(RequestService.instance.mockRequests.isEmpty, isTrue);
      expect(popped, isTrue);
    });
  });

  group('RequestApprovalScreen & MyRequestsScreen Card Deletion & Count Refresh Tests', () {
    setUp(() {
      RequestService.useMockOnly = true;
      RequestService.instance.clearMockStore();
      RequestService.instance.seedMockRequest(approvedRequest);
      RequestService.instance.seedMockRequest(pendingRequest);
      RequestService.instance.seedMockRequest(rejectedRequest);
    });

    tearDown(() {
      RequestService.instance.clearMockStore();
      RequestService.useMockOnly = false;
    });

    testWidgets('RequestApprovalScreen deletes card, refreshes list and recalculates tab counts', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RequestApprovalScreen(
              currentUserId: scopedManagerId,
              currentUserName: 'Sarah Connor',
              currentUserRole: 'manager',
              currentUserEmail: 'sarah.c@sobha.com',
              organizationId: orgId,
              isManager: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial counts: Approved (1), All Requests (3)
      final approvedTabFinder = find.ancestor(
        of: find.text('Approved'),
        matching: find.byType(Tab),
      );
      expect(find.descendant(of: approvedTabFinder, matching: find.text('1')), findsOneWidget);

      final allRequestsTabFinder = find.ancestor(
        of: find.text('All Requests'),
        matching: find.byType(Tab),
      );
      expect(find.descendant(of: allRequestsTabFinder, matching: find.text('3')), findsOneWidget);

      // Switch to Approved tab
      await tester.tap(find.widgetWithText(Tab, 'Approved'));
      await tester.pumpAndSettle();

      // Find Delete button on REQ-2001 card
      final deleteCardBtn = find.byKey(Key('delete_request_${approvedRequest.id}'));
      expect(deleteCardBtn, findsOneWidget);

      // Tap Delete
      await tester.tap(deleteCardBtn);
      await tester.pumpAndSettle();

      // Confirm deletion in dialog
      await tester.tap(find.byKey(const Key('confirm_delete_request_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify request removed from mock store
      expect(RequestService.instance.mockRequests.any((r) => r.id == approvedRequest.id), isFalse);

      // Recalculated counts: Approved (0), All Requests (2)
      expect(find.descendant(of: approvedTabFinder, matching: find.text('0')), findsOneWidget);
      expect(find.descendant(of: allRequestsTabFinder, matching: find.text('2')), findsOneWidget);
      expect(find.text('Request REQ-2001 has been permanently deleted.'), findsOneWidget);
    });

    testWidgets('MyRequestsScreen deletes card and refreshes personal list for staff', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MyRequestsScreen(
                currentUserId: requesterStaffId,
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

      // Find Delete button on My Requests screen for REQ-2001
      final deleteMyReqBtn = find.byKey(Key('delete_my_request_${approvedRequest.id}'));
      expect(deleteMyReqBtn, findsOneWidget);

      // Tap Delete
      await tester.tap(deleteMyReqBtn);
      await tester.pumpAndSettle();

      // Confirm in dialog
      await tester.tap(find.byKey(const Key('confirm_delete_request_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verified deleted
      expect(find.text('Request REQ-2001 has been permanently deleted.'), findsOneWidget);
      expect(RequestService.instance.mockRequests.any((r) => r.id == approvedRequest.id), isFalse);
    });
  });
}
