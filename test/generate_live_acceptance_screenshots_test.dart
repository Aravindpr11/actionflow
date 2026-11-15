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
  const artifactDir = r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23';

  // Real production account IDs
  const reniManagerId = '7b3f384d-75ed-4201-9670-932950fb16b6'; // Reni Thomas (Manager, Sobha Infra)
  const adrashStaffId = 'bf32c8c6-61be-453d-96d2-7e8c15d08a4f'; // Adrash (Staff)
  const newStaffId = 'a995cfcc-8b93-4cb2-9084-66b63edb0d4a'; // Niyas Gafoor (New Staff)

  setUp(() {
    RequestService.useMockOnly = true;
    RequestService.instance.clearMockStore();

    // In Production: REQ-1006 (Rejected, created by Reni Thomas in Sobha Infra)
    RequestService.instance.seedMockRequest(
      RequestRecord(
        id: '00c9d88b-21e8-4c32-a086-7cdb3359850d',
        displayId: 'REQ-1006',
        organizationId: orgId,
        title: 'test',
        description: 'test',
        requestType: RequestType.ptw,
        priority: RequestPriority.medium,
        requiredByDate: '2026-11-15',
        status: RequestStatus.rejected,
        departmentId: 'cc1c49b7-4d9a-4e94-be5b-0ddd89790d6b',
        departmentName: 'Sobha Infra',
        siteId: 'b751354b-f0f8-4a49-9488-c8355588dcd6',
        siteName: 'Sobha Infra',
        createdBy: reniManagerId,
        createdByName: 'Reni Thomas',
        createdByRole: 'Manager',
        createdAt: DateTime.parse('2026-11-10T06:53:31.064887+00:00'),
        approvers: const [
          RequestApproverRecord(
            id: 'appr-1006',
            requestId: '00c9d88b-21e8-4c32-a086-7cdb3359850d',
            approverId: reniManagerId,
            approverName: 'Reni Thomas',
            approverRole: 'Manager',
            stepOrder: 1,
            status: RequestStatus.rejected,
          ),
        ],
      ),
    );

    // In Production: REQ-1005 (Pending, approver: Adrash)
    RequestService.instance.seedMockRequest(
      RequestRecord(
        id: '0c377130-d3f1-4e01-810e-a09dba3f96b3',
        displayId: 'REQ-1005',
        organizationId: orgId,
        title: 'aa',
        description: 'aa',
        requestType: RequestType.ptw,
        priority: RequestPriority.medium,
        requiredByDate: '2026-11-14',
        status: RequestStatus.underReview,
        departmentId: 'dept-test-uuid',
        departmentName: 'test',
        siteId: 'site-test-uuid',
        siteName: 'test',
        createdBy: adrashStaffId,
        createdByName: 'Adrash',
        createdByRole: 'Staff',
        createdAt: DateTime.parse('2026-11-09T11:19:28.711937+00:00'),
        approvers: const [
          RequestApproverRecord(
            id: 'appr-1005',
            requestId: '0c377130-d3f1-4e01-810e-a09dba3f96b3',
            approverId: adrashStaffId,
            approverName: 'Adrash',
            approverRole: 'Staff',
            stepOrder: 1,
            status: RequestStatus.pending,
          ),
        ],
      ),
    );
  });

  tearDown(() {
    RequestService.instance.clearMockStore();
    RequestService.useMockOnly = false;
  });

  testWidgets('Generate live acceptance screenshots for Manager, Staff, and New Staff', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // 1. SCREENSHOT 1: Manager Account (Reni Thomas)
    final repaintKeyManager = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Inter',
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E3A8A)),
        ),
        home: RepaintBoundary(
          key: repaintKeyManager,
          child: const Scaffold(
            backgroundColor: Color(0xFFF8FAFC),
            body: Padding(
              padding: EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: RequestApprovalScreen(
                  currentUserId: reniManagerId,
                  currentUserName: 'Reni Thomas',
                  currentUserRole: 'manager',
                  currentUserEmail: 'renialavelil@gmail.com',
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

    await tester.runAsync(() async {
      final boundary = repaintKeyManager.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$artifactDir\\live_manager_request_approval_screen.png');
      await file.writeAsBytes(byteData!.buffer.asUint8List());
    });

    // 2. SCREENSHOT 2: Staff Account (Adrash)
    final repaintKeyStaff = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Inter',
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E3A8A)),
        ),
        home: RepaintBoundary(
          key: repaintKeyStaff,
          child: const Scaffold(
            backgroundColor: Color(0xFFF8FAFC),
            body: Padding(
              padding: EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: RequestApprovalScreen(
                  currentUserId: adrashStaffId,
                  currentUserName: 'Adrash',
                  currentUserRole: 'staff',
                  currentUserEmail: 'aadarshdelip7@gmail.com',
                  organizationId: orgId,
                  isManager: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final boundary = repaintKeyStaff.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$artifactDir\\live_staff_request_approval_screen.png');
      await file.writeAsBytes(byteData!.buffer.asUint8List());
    });

    // 3. SCREENSHOT 3: Newly Created Staff Account (Niyas Gafoor - 0 requests)
    final repaintKeyNewStaff = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Inter',
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E3A8A)),
        ),
        home: RepaintBoundary(
          key: repaintKeyNewStaff,
          child: const Scaffold(
            backgroundColor: Color(0xFFF8FAFC),
            body: Padding(
              padding: EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: RequestApprovalScreen(
                  currentUserId: newStaffId,
                  currentUserName: 'Niyas Gafoor',
                  currentUserRole: 'staff',
                  currentUserEmail: 'niyas.gafoor@sobhaconst.com',
                  organizationId: orgId,
                  isManager: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final boundary = repaintKeyNewStaff.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$artifactDir\\live_new_staff_request_approval_screen.png');
      await file.writeAsBytes(byteData!.buffer.asUint8List());
    });

    expect(File('$artifactDir\\live_manager_request_approval_screen.png').existsSync(), isTrue);
    expect(File('$artifactDir\\live_staff_request_approval_screen.png').existsSync(), isTrue);
    expect(File('$artifactDir\\live_new_staff_request_approval_screen.png').existsSync(), isTrue);
  });
}
