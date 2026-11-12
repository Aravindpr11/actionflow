import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:action_flow/features/requests/models/request_models.dart';
import 'package:action_flow/features/requests/screens/request_approval_screen.dart';
import 'package:action_flow/features/requests/services/request_service.dart';
import 'package:action_flow/models/organization.dart';

void main() {
  const orgId = Organization.sobhaId;
  const managerId = 'mgr-screenshot-uuid';
  const staffId = 'staff-screenshot-uuid';

  setUp(() {
    RequestService.useMockOnly = true;
    RequestService.instance.clearMockStore();

    // 1. Pending My Action
    RequestService.instance.seedMockRequest(
      RequestRecord(
        id: 'req-1',
        displayId: 'REQ-101',
        organizationId: orgId,
        title: 'Equipment Transfer Crane Permit',
        description: 'Requires manager approval for site crane mobilization',
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

    // 2. Under Review (Pending team review)
    RequestService.instance.seedMockRequest(
      RequestRecord(
        id: 'req-2',
        displayId: 'REQ-102',
        organizationId: orgId,
        title: 'PTW Hot Work - Welding Operations',
        description: 'Under review by fire safety technical team',
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
            approverId: 'other-appr',
            approverName: 'Technical Officer',
            approverRole: 'Staff',
            stepOrder: 1,
            status: RequestStatus.pending,
          ),
        ],
      ),
    );

    // 3. Approved 1
    RequestService.instance.seedMockRequest(
      RequestRecord(
        id: 'req-3',
        displayId: 'REQ-103',
        organizationId: orgId,
        title: 'Scaffolding Sign-off Tower 2',
        description: 'Third-party scaffolding inspection completed',
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

    // 4. Approved 2
    RequestService.instance.seedMockRequest(
      RequestRecord(
        id: 'req-4',
        displayId: 'REQ-104',
        organizationId: orgId,
        title: 'HSE Safety Harness Requisition',
        description: 'Fall arrest gear replenishment for high-rise team',
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

    // 5. Rejected
    RequestService.instance.seedMockRequest(
      RequestRecord(
        id: 'req-5',
        displayId: 'REQ-105',
        organizationId: orgId,
        title: 'Deep Trench Excavation Permit',
        description: 'Rejected: shoring plan incomplete and soil test expired',
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
  });

  testWidgets('Capture Request Approval Screen Tab Counts Screenshots', (tester) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final repaintKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Inter',
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E3A8A)),
        ),
        home: RepaintBoundary(
          key: repaintKey,
          child: const Scaffold(
            backgroundColor: Color(0xFFF8FAFC),
            body: Padding(
              padding: EdgeInsets.all(24),
              child: SingleChildScrollView(
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
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Capture Default Tab (Pending My Action) screenshot
    await tester.runAsync(() async {
      final boundary = repaintKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final file = File(
        r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23\request_approval_tab_counts_simultaneous.png',
      );
      await file.writeAsBytes(pngBytes);
    });

    // Switch to Tab 1 (Under Review)
    final underReviewTab = find.widgetWithText(Tab, 'Under Review');
    await tester.tap(underReviewTab);
    await tester.pumpAndSettle();

    // Capture Under Review selected tab screenshot
    await tester.runAsync(() async {
      final boundary = repaintKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final file = File(
        r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23\request_approval_tab_under_review_selected.png',
      );
      await file.writeAsBytes(pngBytes);
    });

    final file1 = File(r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23\request_approval_tab_counts_simultaneous.png');
    final file2 = File(r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23\request_approval_tab_under_review_selected.png');
    expect(file1.existsSync(), isTrue);
    expect(file2.existsSync(), isTrue);
  });
}
