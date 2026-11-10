import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/add_action_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:action_flow/widgets/document_preview/action_attachment_preview_dialog.dart';

class MockActionServiceForPreview extends ActionService {
  MockActionServiceForPreview({
    this.attachmentBytes,
    this.shouldFail = false,
    this.errorMessage,
  }) : super.forTesting();

  final Uint8List? attachmentBytes;
  final bool shouldFail;
  final String? errorMessage;
  bool downloadTriggered = false;

  @override
  Future<({bool success, Uint8List? bytes, String? signedUrl, String? error})>
      getActionAttachmentBytes({
    required ActionRecord action,
    required String fileName,
    required String? userId,
    bool isManager = false,
    int expiresInSeconds = 300,
  }) async {
    if (shouldFail) {
      return (
        success: false,
        bytes: null,
        signedUrl: null,
        error: errorMessage ?? 'Storage access denied',
      );
    }
    return (
      success: true,
      bytes: attachmentBytes ?? Uint8List.fromList([1, 2, 3, 4]),
      signedUrl: 'https://storage.supabase.co/signed/sample_url',
      error: null,
    );
  }

  @override
  Future<({bool success, Uint8List? bytes, String? signedUrl, String? error})>
      downloadActionAttachment({
    required ActionRecord action,
    required String fileName,
    required String? userId,
    bool isManager = false,
    int expiresInSeconds = 300,
  }) async {
    downloadTriggered = true;
    return (
      success: true,
      bytes: attachmentBytes ?? Uint8List.fromList([1, 2, 3, 4]),
      signedUrl: 'https://storage.supabase.co/signed/sample_url',
      error: null,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const staffUser = UserProfile(
    id: 'staff-user-001',
    name: 'Ahmed Staff',
    email: 'ahmed.staff@sobha.com',
    phone: '+971 50 111 2233',
    designation: 'Safety Officer',
    organizationName: 'Sobha Constructions',
    department: 'HSSE Operations',
    site: 'Sobha Hartland',
    role: 'staff',
  );

  const managerUser = UserProfile(
    id: 'mgr-user-001',
    name: 'David Manager',
    email: 'david.manager@sobha.com',
    phone: '+971 50 999 8877',
    designation: 'HSE Manager',
    organizationName: 'Sobha Constructions',
    department: 'HSSE Operations',
    site: 'Sobha Hartland',
    role: 'manager',
  );

  final managerContext = ManagerContext(
    authUserId: 'mgr-user-001',
    profile: managerUser,
    organizationId: '00000000-0000-0000-0000-000000000001',
    organizationName: 'Sobha Constructions',
    scopes: const [],
  );

  // Sample 1x1 transparent PNG bytes
  final samplePngBytes = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  // Sample PDF header bytes
  final samplePdfBytes = Uint8List.fromList(
    '%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF'.codeUnits,
  );

  group('REQUIREMENT 1: Evidence & Attachment Preview / Download', () {
    testWidgets('ActionAttachmentPreviewDialog renders image preview and handles download', (tester) async {
      final mockService = MockActionServiceForPreview(attachmentBytes: samplePngBytes);

      final sampleAction = ActionRecord(
        id: 'act-img-1',
        actionNumber: 'ACT-1001',
        subject: 'Image Attachment Test',
        actionRequired: 'Inspect site photo',
        division: 'Operations',
        department: 'HSSE Operations',
        site: 'Sobha Hartland',
        createdById: 'mgr-user-001',
        assignedTo: 'Ahmed Staff',
        attachments: ['safety_photo.png'],
        priority: 'Medium',
        status: 'Open',
        percentComplete: 20,
        dateRaised: '2026-11-01',
        targetDate: '2026-11-15',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionAttachmentPreviewDialog(
              action: sampleAction,
              fileName: 'safety_photo.png',
              currentUserId: staffUser.id,
              isWorker: true,
              actionService: mockService,
              initialBytes: samplePngBytes,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('safety_photo.png'), findsWidgets);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byKey(const Key('action_preview_dialog_download_btn')), findsOneWidget);

      await tester.tap(find.byKey(const Key('action_preview_dialog_download_btn')));
      await tester.pumpAndSettle();
      expect(mockService.downloadTriggered, isTrue);
    });

    testWidgets('ActionAttachmentPreviewDialog renders PDF preview mode and download', (tester) async {
      final mockService = MockActionServiceForPreview(attachmentBytes: samplePdfBytes);

      final sampleAction = ActionRecord(
        id: 'act-pdf-1',
        actionNumber: 'ACT-1002',
        subject: 'PDF Document Test',
        actionRequired: 'Review HSE Plan',
        division: 'Operations',
        department: 'HSSE Operations',
        site: 'Sobha Hartland',
        createdById: 'mgr-user-001',
        assignedTo: 'Ahmed Staff',
        attachments: ['HSE_Plan.pdf'],
        priority: 'High',
        status: 'Open',
        percentComplete: 30,
        dateRaised: '2026-11-01',
        targetDate: '2026-11-15',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionAttachmentPreviewDialog(
              action: sampleAction,
              fileName: 'HSE_Plan.pdf',
              currentUserId: staffUser.id,
              isWorker: true,
              actionService: mockService,
              initialBytes: samplePdfBytes,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('HSE_Plan.pdf'), findsWidgets);
      expect(find.byKey(const Key('action_preview_dialog_download_btn')), findsOneWidget);
    });
  });

  group('REQUIREMENT 2: Remove Division Subtitle', () {
    testWidgets('ActionDetailsScreen does NOT render Division subtitle under title or in details', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final sampleAction = ActionRecord(
        id: 'act-sub-1',
        actionNumber: 'ACT-1003',
        subject: 'Fire Door Clearance Audit',
        actionRequired: 'Ensure fire doors are unblocked',
        division: 'Corporate Operations',
        department: 'Fire Safety',
        site: 'Tower B',
        createdById: 'mgr-user-001',
        assignedTo: 'Ahmed Staff',
        priority: 'High',
        status: 'Open',
        percentComplete: 0,
        dateRaised: '2026-11-01',
        targetDate: '2026-11-15',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1200, 800)),
            child: Scaffold(
              body: ActionDetailsScreen(
                action: sampleAction,
                currentUserId: staffUser.id,
                isWorker: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Top Header: Verify "Department: Fire Safety • Site: Tower B" is shown WITHOUT "Division:"
      expect(find.textContaining('Department: Fire Safety  •  Site: Tower B'), findsWidgets);
      expect(find.textContaining('Corporate Operations'), findsNothing);

      // Detail Rows: Verify "Department" exists and "Division / Department" does NOT exist
      expect(find.text('Division / Department'), findsNothing);
      expect(find.text('Department'), findsWidgets);
    });

    testWidgets('AddActionScreen does NOT mention division in section 2 subtitle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddActionScreen(
              actionId: 'ACT-NEW-01',
              managerContext: managerContext,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Specify division, department, section, and physical location'), findsNothing);
      expect(find.text('Specify department, section, and physical location'), findsOneWidget);
    });
  });

  group('REQUIREMENT 3: Staff Action Register Status-Independent Deletion', () {
    testWidgets('Staff can delete Open, In Progress, and Closed actions they created from Action Register', (tester) async {
      final staffCreatedOpen = ActionRecord(
        id: 'staff-open-1',
        actionNumber: 'ACT-STAFF-01',
        subject: 'Staff Created Open Action',
        actionRequired: 'Investigate spill',
        division: 'Operations',
        department: 'HSSE Operations',
        site: 'Sobha Hartland',
        createdById: staffUser.id,
        assignedTo: 'Other User',
        priority: 'Medium',
        status: 'Open',
        percentComplete: 0,
        dateRaised: '2026-11-01',
        targetDate: '2026-11-15',
      );

      final staffCreatedInProgress = ActionRecord(
        id: 'staff-prog-1',
        actionNumber: 'ACT-STAFF-02',
        subject: 'Staff Created In Progress Action',
        actionRequired: 'Replace gasket',
        division: 'Operations',
        department: 'HSSE Operations',
        site: 'Sobha Hartland',
        createdById: staffUser.id,
        assignedTo: 'Other User',
        priority: 'High',
        status: 'In Progress',
        percentComplete: 50,
        dateRaised: '2026-11-01',
        targetDate: '2026-11-15',
      );

      final staffCreatedClosed = ActionRecord(
        id: 'staff-closed-1',
        actionNumber: 'ACT-STAFF-03',
        subject: 'Staff Created Closed Action',
        actionRequired: 'Signed off work',
        division: 'Operations',
        department: 'HSSE Operations',
        site: 'Sobha Hartland',
        createdById: staffUser.id,
        assignedTo: 'Other User',
        priority: 'Low',
        status: 'Closed',
        percentComplete: 100,
        dateRaised: '2026-11-01',
        targetDate: '2026-11-15',
        closeDate: '2026-11-05',
      );

      final managerCreatedOpen = ActionRecord(
        id: 'mgr-open-1',
        actionNumber: 'ACT-MGR-01',
        subject: 'Manager Created Open Action',
        actionRequired: 'Review specs',
        division: 'Operations',
        department: 'HSSE Operations',
        site: 'Sobha Hartland',
        createdById: managerUser.id,
        assignedTo: staffUser.name,
        assignedToId: staffUser.id,
        priority: 'High',
        status: 'Open',
        percentComplete: 10,
        dateRaised: '2026-11-01',
        targetDate: '2026-11-15',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkerDashboardScreen(
              userProfile: staffUser,
              initialActions: [
                staffCreatedOpen,
                staffCreatedInProgress,
                staffCreatedClosed,
                managerCreatedOpen,
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Retrieve WorkerDashboardScreen state
      final workerState = tester.state(find.byType(WorkerDashboardScreen)) as dynamic;

      // 1. Staff CAN delete Open action created by them from Action Register
      expect(workerState.canDeleteFromActionRegister(staffCreatedOpen), isTrue);

      // 2. Staff CAN delete In Progress action created by them from Action Register
      expect(workerState.canDeleteFromActionRegister(staffCreatedInProgress), isTrue);

      // 3. Staff CAN delete Closed action created by them from Action Register
      expect(workerState.canDeleteFromActionRegister(staffCreatedClosed), isTrue);

      // 4. Staff CANNOT delete action created by someone else from Action Register
      expect(workerState.canDeleteFromActionRegister(managerCreatedOpen), isFalse);

      // 5. Staff in My Actions CANNOT delete active (Open/In Progress) actions even if assigned
      expect(workerState.canDeleteFromMyActions(managerCreatedOpen), isFalse);
    });
  });

  group('REQUIREMENT 4: Complete Mobile Responsiveness Audit', () {
    final breakpoints = [
      const Size(1200, 800), // Desktop
      const Size(768, 1024), // Tablet
      const Size(400, 800),  // Mobile standard
      const Size(320, 640),  // Ultra-compact mobile
    ];

    for (final bp in breakpoints) {
      testWidgets('WorkerDashboardScreen renders with zero overflow at ${bp.width}px width', (tester) async {
        tester.view.physicalSize = bp;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(size: bp),
              child: const Scaffold(
                body: WorkerDashboardScreen(
                  userProfile: staffUser,
                  initialActions: [],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });

      testWidgets('ActionDetailsScreen renders with zero overflow at ${bp.width}px width', (tester) async {
        tester.view.physicalSize = bp;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final testAction = ActionRecord(
          id: 'act-resp-1',
          actionNumber: 'ACT-RESP-01',
          subject: 'Responsive Layout Test Action with a very long subject line to verify text wrapping',
          actionRequired: 'Ensure that all containers and text widgets wrap cleanly without overflowing boundaries.',
          division: 'Operations',
          department: 'HSSE Operations',
          site: 'Sobha Hartland',
          createdById: 'mgr-user-001',
          assignedTo: 'Ahmed Staff',
          priority: 'High',
          status: 'Open',
          percentComplete: 45,
          dateRaised: '2026-11-01',
          targetDate: '2026-11-15',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(size: bp),
              child: Scaffold(
                body: ActionDetailsScreen(
                  action: testAction,
                  currentUserId: staffUser.id,
                  isWorker: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('REQUIREMENT 5: Search Functionality across Roles', () {
    testWidgets('Worker My Actions search performs partial matching and resets cleanly', (tester) async {
      final act1 = ActionRecord(
        id: 'act-search-1',
        actionNumber: 'ACT-9001',
        subject: 'Confined Space Entry Permit Audit',
        actionRequired: 'Check gas detector calibration logs',
        division: 'Operations',
        department: 'Safety Operations',
        site: 'Site Alpha',
        createdById: staffUser.id,
        assignedTo: staffUser.name,
        assignedToId: staffUser.id,
        priority: 'Critical',
        status: 'Open',
        percentComplete: 10,
        dateRaised: '2026-11-01',
        targetDate: '2026-11-15',
      );

      final act2 = ActionRecord(
        id: 'act-search-2',
        actionNumber: 'ACT-9002',
        subject: 'Scaffolding Tagging Review',
        actionRequired: 'Verify green tags on sector 4 towers',
        division: 'Operations',
        department: 'Civil Works',
        site: 'Site Beta',
        createdById: staffUser.id,
        assignedTo: staffUser.name,
        assignedToId: staffUser.id,
        priority: 'Low',
        status: 'In Progress',
        percentComplete: 70,
        dateRaised: '2026-11-01',
        targetDate: '2026-11-15',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkerDashboardScreen(
              userProfile: staffUser,
              initialNavIndex: 1, // My Actions
              initialActions: [act1, act2],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter search query "Confined"
      final searchFields = find.byType(TextField);
      expect(searchFields, findsWidgets);
      final searchField = searchFields.first;
      await tester.enterText(searchField, 'Confined');
      await tester.pumpAndSettle();

      // Only ACT-9001 should match, ACT-9002 should be filtered out
      expect(find.text('Confined Space Entry Permit Audit'), findsOneWidget);
      expect(find.text('Scaffolding Tagging Review'), findsNothing);

      // Partial search by action number "9002"
      await tester.enterText(searchField, '9002');
      await tester.pumpAndSettle();
      expect(find.text('Confined Space Entry Permit Audit'), findsNothing);
      expect(find.text('Scaffolding Tagging Review'), findsOneWidget);

      // Clear search query
      await tester.enterText(searchField, '');
      await tester.pumpAndSettle();
      expect(find.text('Confined Space Entry Permit Audit'), findsOneWidget);
      expect(find.text('Scaffolding Tagging Review'), findsOneWidget);
    });
  });
}
