import 'dart:convert';
import 'dart:typed_data';

import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/models/document_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/models/team.dart';
import 'package:action_flow/services/app_file_picker_service.dart';
import 'package:action_flow/services/document_service.dart';
import 'package:action_flow/services/user_service.dart';
import 'package:action_flow/widgets/document_preview/document_preview_dialog.dart';
import 'package:action_flow/widgets/documents/document_share_dialog.dart';
import 'package:action_flow/widgets/documents/document_upload_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    DocumentService.allowInMemoryStoreForTests = true;
    MockDocumentStore.instance.reset();
    AppFilePicker.saveTestOverride = null;
  });

  tearDown(() {
    DocumentService.allowInMemoryStoreForTests = false;
    AppFilePicker.saveTestOverride = null;
  });

  group('DocumentService Download & Error Formatting', () {
    test('downloadAndSaveDocument delegates to getDocumentBytes and AppFilePicker.saveFile', () async {
      final doc = MockDocumentStore.instance.documents.first;
      String? savedFileName;
      Uint8List? savedBytes;
      String? savedMime;

      AppFilePicker.saveTestOverride = ({
        required String fileName,
        required Uint8List bytes,
        String mimeType = 'application/octet-stream',
      }) async {
        savedFileName = fileName;
        savedBytes = bytes;
        savedMime = mimeType;
        return true;
      };

      final success = await DocumentService.instance.downloadAndSaveDocument(
        doc: doc,
        organizationId: 'SOBHA-001',
      );

      expect(success, isTrue);
      expect(savedFileName, equals(doc.fileName));
      expect(savedBytes, isNotNull);
      expect(savedBytes!.isNotEmpty, isTrue);
      expect(savedMime, equals(doc.fileType));
    });

    test('formatDownloadError categorizes errors clearly for user feedback', () {
      expect(
        DocumentService.formatDownloadError('permission denied for table (code 42501)'),
        contains('Access denied'),
      );
      expect(
        DocumentService.formatDownloadError('PostgrestException: code PGRST116'),
        contains('Access denied'),
      );
      expect(
        DocumentService.formatDownloadError('Object not found in storage bucket'),
        contains('not found'),
      );
      expect(
        DocumentService.formatDownloadError('Bucket not found'),
        contains('not found'),
      );
      expect(
        DocumentService.formatDownloadError('SocketException: Failed host lookup'),
        contains('Network error'),
      );
      expect(
        DocumentService.formatDownloadError('Random unexpected failure'),
        equals('Random unexpected failure'),
      );
    });
  });

  group('In-App DocumentPreviewDialog Widget', () {
    testWidgets('renders PDF document preview with header, details, and close action', (tester) async {
      final now = DateTime.now();
      final pdfDoc = DocumentRecord(
        id: 'pdf-1',
        organizationId: 'SOBHA-001',
        title: 'Site Safety Standard Operating Procedure',
        fileName: 'site_safety_sop.pdf',
        filePath: 'SOBHA-001/site_safety_sop.pdf',
        fileSize: 1024 * 250,
        fileType: 'application/pdf',
        category: 'Safety Guidelines',
        description: 'Mandatory standard operating procedure for all field workers.',
        fileBytes: utf8.encode('%PDF-1.4 Mock PDF Content'),
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentPreviewDialog(
              document: pdfDoc,
              organizationId: 'SOBHA-001',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Header
      expect(find.text('Site Safety Standard Operating Procedure'), findsOneWidget);
      expect(find.textContaining('site_safety_sop.pdf • 250.0 KB'), findsOneWidget);
      expect(find.textContaining('250.0 KB'), findsOneWidget);

      // Verify PDF Viewer representation
      expect(find.text('In-App PDF Document Ready'), findsOneWidget);
      expect(find.byIcon(Icons.picture_as_pdf_rounded), findsWidgets);

      // Verify Download Button
      expect(find.text('Download'), findsWidgets);

      // Verify Close Button
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('renders Image document preview with InteractiveViewer', (tester) async {
      final now = DateTime.now();
      // 1x1 transparent PNG bytes
      final pngBytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
      );

      final imgDoc = DocumentRecord(
        id: 'img-1',
        organizationId: 'SOBHA-001',
        title: 'Emergency Evacuation Map',
        fileName: 'evac_map.png',
        filePath: 'SOBHA-001/evac_map.png',
        fileSize: pngBytes.length,
        fileType: 'image/png',
        category: 'Emergency',
        fileBytes: pngBytes,
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentPreviewDialog(
              document: imgDoc,
              organizationId: 'SOBHA-001',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Emergency Evacuation Map'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('renders Text document preview with scrollable content', (tester) async {
      final now = DateTime.now();
      const textContent = 'HSE Daily Briefing:\n1. Wear helmets\n2. Inspect harnesses';

      final txtDoc = DocumentRecord(
        id: 'txt-1',
        organizationId: 'SOBHA-001',
        title: 'Daily Briefing Notes',
        fileName: 'daily_notes.txt',
        filePath: 'SOBHA-001/daily_notes.txt',
        fileSize: textContent.length,
        fileType: 'text/plain',
        category: 'Briefings',
        fileBytes: utf8.encode(textContent),
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentPreviewDialog(
              document: txtDoc,
              organizationId: 'SOBHA-001',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Daily Briefing Notes'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.textContaining('Wear helmets'), findsOneWidget);
    });

    testWidgets('renders Unsupported Format card with direct download for Word & Excel', (tester) async {
      final now = DateTime.now();
      final docxDoc = DocumentRecord(
        id: 'word-1',
        organizationId: 'SOBHA-001',
        title: 'Contractor Safety Handbook',
        fileName: 'handbook.docx',
        filePath: 'SOBHA-001/handbook.docx',
        fileSize: 1024 * 500,
        fileType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        category: 'Contractor Safety',
        fileBytes: utf8.encode('PK Mock DOCX'),
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentPreviewDialog(
              document: docxDoc,
              organizationId: 'SOBHA-001',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Contractor Safety Handbook'), findsOneWidget);
      expect(find.text('In-App Preview Unavailable'), findsOneWidget);
      expect(find.textContaining('Microsoft Office'), findsOneWidget);
      expect(find.text('Download handbook.docx'), findsOneWidget);
    });

    testWidgets('triggers file save when Download is clicked inside dialog', (tester) async {
      final now = DateTime.now();
      final doc = DocumentRecord(
        id: 'pdf-dl',
        organizationId: 'SOBHA-001',
        title: 'Toolbox Talk Checklist',
        fileName: 'toolbox_talk.pdf',
        filePath: 'SOBHA-001/toolbox_talk.pdf',
        fileSize: 1024 * 10,
        fileType: 'application/pdf',
        category: 'Checklists',
        fileBytes: utf8.encode('Mock PDF'),
        createdAt: now,
        updatedAt: now,
      );

      bool downloadInvoked = false;
      AppFilePicker.saveTestOverride = ({
        required String fileName,
        required Uint8List bytes,
        String mimeType = 'application/octet-stream',
      }) async {
        downloadInvoked = true;
        return true;
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentPreviewDialog(
              document: doc,
              organizationId: 'SOBHA-001',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the download button in the header and tap it
      final downloadBtn = find.widgetWithText(FilledButton, 'Download').first;
      expect(downloadBtn, findsOneWidget);
      await tester.tap(downloadBtn);
      await tester.pumpAndSettle();

      expect(downloadInvoked, isTrue);
    });
  });

  group('Staff Portal Documents Tab & Actions', () {
    testWidgets('displays documents with Preview and Download action buttons and handles download', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool downloaded = false;
      AppFilePicker.saveTestOverride = ({
        required String fileName,
        required Uint8List bytes,
        String mimeType = 'application/octet-stream',
      }) async {
        downloaded = true;
        return true;
      };

      final staffProfile = UserProfile.mockStaff().copyWith(
        id: 'staff-worker-01',
        name: 'John Staff',
        email: 'john.staff@sobha.com',
        role: 'worker',
        department: 'Construction HSE',
        organizationId: 'SOBHA-001',
        organizationName: 'Sobha Construction',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: WorkerDashboardScreen(userProfile: staffProfile),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Documents tab in sidebar
      final docNav = find.text('Documents');
      expect(docNav, findsOneWidget);
      await tester.tap(docNav);
      await tester.pumpAndSettle();

      // Verify Safety Documents & Guidelines card is displayed
      expect(find.text('Safety Documents & Guidelines'), findsOneWidget);

      // Verify Preview and Download icons are present
      final previewIcons = find.byIcon(Icons.visibility_outlined);
      final downloadIcons = find.byIcon(Icons.download_rounded);

      expect(previewIcons, findsWidgets);
      expect(downloadIcons, findsWidgets);

      // Tap the download icon of the first document
      await tester.tap(downloadIcons.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify download was invoked
      expect(downloaded, isTrue);
      await tester.pumpAndSettle();

      // Tap the preview icon of the first document
      await tester.tap(previewIcons.first);
      await tester.pumpAndSettle();

      // Verify DocumentPreviewDialog opened
      expect(find.byType(DocumentPreviewDialog), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      // Close the preview
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(DocumentPreviewDialog), findsNothing);
    });
  });

  group('Manager Portal Document Preview Integration', () {
    testWidgets('clicking preview button opens in-app DocumentPreviewDialog', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mgrProfile = UserProfile(
        id: 'usr-mgr-01',
        email: 'manager@actionflow.com',
        name: 'M. Ali',
        phone: '+971 50 123 4567',
        designation: 'Safety Manager',
        department: 'HSE',
        division: 'Operations',
        site: 'North Yard',
        role: 'manager',
        organizationId: 'SOBHA-001',
        organizationName: 'Sobha Construction',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: ManagerDashboardScreen(userProfile: mgrProfile),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Documents view
      final docNav = find.text('Documents');
      expect(docNav, findsWidgets);
      await tester.tap(docNav.first);
      await tester.pumpAndSettle();

      // Find the preview button in documents list
      final previewButtons = find.byTooltip('Preview');
      expect(previewButtons, findsWidgets);

      // Tap Preview on first document
      await tester.tap(previewButtons.first);
      await tester.pumpAndSettle();

      // Verify DocumentPreviewDialog opened
      expect(find.byType(DocumentPreviewDialog), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      // Close preview
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(DocumentPreviewDialog), findsNothing);
    });
  });

  group('Staff Document Upload & Validation (DocumentUploadDialog)', () {
    testWidgets('rejects files larger than 25 MB with clear error message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DocumentUploadDialog(
              organizationId: 'SOBHA-001',
              userId: 'staff-01',
              userName: 'Test Staff',
              departmentName: 'HSE',
              customFilePicker: () async => AppPickedFile(
                name: 'oversized_file.pdf',
                bytes: Uint8List(26 * 1024 * 1024), // 26 MB
                size: 26 * 1024 * 1024,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chooseBtn = find.byKey(const Key('documents_choose_file_button'));
      expect(chooseBtn, findsOneWidget);
      await tester.tap(chooseBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('documents_validation_error')), findsOneWidget);
      expect(find.textContaining('exceeds the maximum allowed limit of 25 MB'), findsOneWidget);
    });

    testWidgets('rejects unsupported file extensions with error message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DocumentUploadDialog(
              organizationId: 'SOBHA-001',
              userId: 'staff-01',
              userName: 'Test Staff',
              departmentName: 'HSE',
              customFilePicker: () async => AppPickedFile(
                name: 'malicious.exe',
                bytes: utf8.encode('echo bad'),
                size: 8,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chooseBtn = find.byKey(const Key('documents_choose_file_button'));
      await tester.tap(chooseBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('documents_validation_error')), findsOneWidget);
      expect(find.textContaining('Unsupported file format'), findsOneWidget);
    });

    testWidgets('successfully uploads valid PDF with title, category, and action link', (tester) async {
      DocumentRecord? uploaded;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DocumentUploadDialog(
              organizationId: 'SOBHA-001',
              userId: 'staff-01',
              userName: 'John Staff',
              departmentName: 'HSE',
              actions: [
                ActionRecord(
                  id: 'act-101',
                  actionNumber: 'ACT-00101',
                  subject: 'Replace damaged scaffolding plank',
                  actionRequired: 'Inspect and replace',
                  division: 'Operations',
                  assignedTo: 'John Staff',
                  assignedToId: 'staff-01',
                  departmentId: 'dept-hse',
                  organizationId: 'SOBHA-001',
                ),
              ],
              customFilePicker: () async => AppPickedFile(
                name: 'scaffolding_inspection.pdf',
                bytes: utf8.encode('%PDF-1.4 Mock Scaffold Content'),
                size: 32,
              ),
              onDocumentUploaded: (doc) {
                uploaded = doc;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Pick file
      final chooseBtn = find.byKey(const Key('documents_choose_file_button'));
      await tester.tap(chooseBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('documents_selected_file_name')), findsOneWidget);

      // Enter Title
      await tester.enterText(
        find.widgetWithText(TextField, 'Document Title *'),
        'Scaffolding Inspection Report',
      );
      await tester.pumpAndSettle();

      // Submit Upload
      final submitBtn = find.byKey(const Key('documents_submit_upload_button'));
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(uploaded, isNotNull);
      expect(uploaded!.title, equals('Scaffolding Inspection Report'));
      expect(uploaded!.fileName, equals('scaffolding_inspection.pdf'));
      expect(uploaded!.createdBy, equals('staff-01'));
      expect(uploaded!.createdByName, equals('John Staff'));
      expect(uploaded!.fileBytes, isNotNull);
    });
  });

  group('Staff Portal Filtering & Badging', () {
    testWidgets('filters by All, My Uploads, Shared with Me, and Guidelines', (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final staffProfile = UserProfile.mockStaff().copyWith(
        id: 'staff-01',
        name: 'John Staff',
        department: 'HSE',
        organizationId: 'SOBHA-001',
      );

      final now = DateTime.now();
      MockDocumentStore.instance.documents.clear();
      MockDocumentStore.instance.documents.addAll([
        DocumentRecord(
          id: 'doc-my-01',
          organizationId: 'SOBHA-001',
          title: 'My HSE Daily Log',
          fileName: 'daily_log.pdf',
          filePath: 'SOBHA-001/daily_log.pdf',
          fileSize: 1024,
          fileType: 'application/pdf',
          category: 'Action Evidence',
          createdBy: 'staff-01',
          createdByName: 'John Staff',
          createdAt: now,
          updatedAt: now,
        ),
        DocumentRecord(
          id: 'doc-shared-01',
          organizationId: 'SOBHA-001',
          title: 'Shared Crane Inspection',
          fileName: 'crane_check.pdf',
          filePath: 'SOBHA-001/crane_check.pdf',
          fileSize: 2048,
          fileType: 'application/pdf',
          category: 'Audit Checklists',
          createdBy: 'mgr-01',
          createdByName: 'Safety Manager',
          sharedWithUserIds: ['staff-01'],
          sharedInternalCount: 1,
          createdAt: now,
          updatedAt: now,
        ),
        DocumentRecord(
          id: 'doc-policy-01',
          organizationId: 'SOBHA-001',
          title: 'Corporate PPE Policy 2026',
          fileName: 'ppe_policy.pdf',
          filePath: 'SOBHA-001/ppe_policy.pdf',
          fileSize: 4096,
          fileType: 'application/pdf',
          category: 'Policies & Procedures',
          createdBy: 'admin-01',
          createdByName: 'System Admin',
          createdAt: now,
          updatedAt: now,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: WorkerDashboardScreen(userProfile: staffProfile),
        ),
      );
      await tester.pumpAndSettle();

      // Go to Documents tab
      await tester.tap(find.text('Documents'));
      await tester.pumpAndSettle();

      // Verify All shows all 3
      expect(find.text('My HSE Daily Log'), findsOneWidget);
      expect(find.text('Shared Crane Inspection'), findsOneWidget);
      expect(find.text('Corporate PPE Policy 2026'), findsOneWidget);

      // Verify Badges and Chips on items
      expect(find.text('My Upload'), findsWidgets);
      expect(find.text('Shared with Me'), findsNWidgets(2)); // Filter chip + Document badge

      // Tap 'My Uploads' filter chip
      await tester.tap(find.text('My Uploads').first);
      await tester.pumpAndSettle();

      expect(find.text('My HSE Daily Log'), findsOneWidget);
      expect(find.text('Shared Crane Inspection'), findsNothing);
      expect(find.text('Corporate PPE Policy 2026'), findsNothing);

      // Tap 'Shared with Me' filter chip
      await tester.tap(find.text('Shared with Me').first);
      await tester.pumpAndSettle();

      expect(find.text('My HSE Daily Log'), findsNothing);
      expect(find.text('Shared Crane Inspection'), findsOneWidget);
      expect(find.text('Corporate PPE Policy 2026'), findsNothing);

      // Tap 'Guidelines & Policies' filter chip
      await tester.tap(find.text('Guidelines & Policies'));
      await tester.pumpAndSettle();

      expect(find.text('My HSE Daily Log'), findsNothing);
      expect(find.text('Shared Crane Inspection'), findsNothing);
      expect(find.text('Corporate PPE Policy 2026'), findsOneWidget);
    });
  });

  group('Staff Department-Level Sharing (DocumentShareDialog)', () {
    testWidgets('allows staff to open share dialog for authorized accessible document and share with department manager', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final now = DateTime.now();
      final otherDoc = DocumentRecord(
        id: 'doc-other',
        organizationId: 'SOBHA-001',
        title: 'Manager Safety Directive',
        fileName: 'directive.pdf',
        filePath: 'SOBHA-001/directive.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        createdBy: 'mgr-99',
        createdByName: 'Senior Director',
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DocumentShareDialog(
              document: otherDoc,
              organizationId: 'SOBHA-001',
              currentUserId: 'staff-01',
              currentUserName: 'John Staff',
              currentUserRole: 'staff',
              currentUserDepartment: 'HSE',
              onSharesUpdated: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Share Document'), findsOneWidget);
      expect(find.text('Manager Safety Directive'), findsOneWidget);
      expect(find.text('External Links'), findsNothing);
      expect(find.byType(DropdownButtonFormField<Person>), findsOneWidget);
    });

    testWidgets('allows author staff to view share dialog for their own document', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final now = DateTime.now();
      final myDoc = DocumentRecord(
        id: 'doc-my-02',
        organizationId: 'SOBHA-001',
        title: 'Safety Audit Checklist 2026',
        fileName: 'safety_audit.pdf',
        filePath: 'SOBHA-001/safety_audit.pdf',
        fileSize: 2048,
        fileType: 'application/pdf',
        createdBy: 'staff-01',
        createdByName: 'John Staff',
        departmentId: 'dept-hse',
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DocumentShareDialog(
              document: myDoc,
              organizationId: 'SOBHA-001',
              currentUserId: 'staff-01',
              currentUserName: 'John Staff',
              currentUserRole: 'staff',
              currentUserDepartment: 'HSE',
              currentUserDepartmentId: 'dept-hse',
              onSharesUpdated: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ensure header is present
      expect(find.text('Share Document'), findsOneWidget);
      expect(find.text('Safety Audit Checklist 2026'), findsOneWidget);

      // Verify external tab is hidden for staff
      expect(find.text('External Links'), findsNothing);

      // Verify eligible colleagues dropdown exists
      expect(find.byType(DropdownButtonFormField<Person>), findsOneWidget);
    });

    testWidgets('searching for "mana" filters recipients and finds department managers and manager-role users', (tester) async {
      final now = DateTime.now();
      final myDoc = DocumentRecord(
        id: 'doc-search-01',
        organizationId: 'SOBHA-001',
        title: 'Safety Procedures',
        fileName: 'safety.pdf',
        filePath: 'SOBHA-001/safety.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        createdBy: 'staff-01',
        createdByName: 'R. Kumar',
        departmentId: 'dept-ops-001',
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DocumentShareDialog(
              document: myDoc,
              organizationId: 'SOBHA-001',
              currentUserId: 'staff-01',
              currentUserName: 'R. Kumar',
              currentUserRole: 'staff',
              currentUserDepartment: 'Operations',
              currentUserDepartmentId: 'dept-ops-001',
              onSharesUpdated: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter search query "mana" in the recipient search field
      final searchField = find.byKey(const Key('documents_recipient_search_field'));
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'mana');
      await tester.pumpAndSettle();

      // Verify that "No eligible recipients found" is NOT shown
      expect(find.text('No eligible recipients found'), findsNothing);

      // Verify the dropdown has the label "Select Colleague / Manager"
      expect(find.text('Select Colleague / Manager'), findsOneWidget);

      // Tap the dropdown to open it and verify the matched recipients
      await tester.tap(find.byType(DropdownButtonFormField<Person>));
      await tester.pumpAndSettle();

      // "Operations Manager" and managers with role "Department Manager" should appear
      expect(find.textContaining('Operations Manager'), findsWidgets);
    });

    testWidgets('excludes colleagues from other departments while including same-department colleagues and managers', (tester) async {
      final now = DateTime.now();
      final myDoc = DocumentRecord(
        id: 'doc-isolation-01',
        organizationId: 'SOBHA-001',
        title: 'Maintenance Manual',
        fileName: 'manual.pdf',
        filePath: 'SOBHA-001/manual.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        createdBy: 'staff-01',
        createdByName: 'Staff User',
        departmentId: 'dept-maint-001',
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DocumentShareDialog(
              document: myDoc,
              organizationId: 'SOBHA-001',
              currentUserId: 'staff-01',
              currentUserName: 'Staff User',
              currentUserRole: 'staff',
              currentUserDepartment: 'Maintenance',
              currentUserDepartmentId: 'dept-maint-001',
              onSharesUpdated: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap dropdown to view options
      await tester.tap(find.byType(DropdownButtonFormField<Person>));
      await tester.pumpAndSettle();

      // S. Jones is in Projects department -> MUST BE EXCLUDED!
      expect(find.textContaining('S. Jones'), findsNothing);

      // Same department colleague R. Kumar (Maintenance) -> MUST BE ELIGIBLE!
      expect(find.textContaining('R. Kumar'), findsOneWidget);
    });

    testWidgets('excludes current user and inactive users from eligible recipients list', (tester) async {
      final now = DateTime.now();
      final myDoc = DocumentRecord(
        id: 'doc-self-01',
        organizationId: 'SOBHA-001',
        title: 'My Report',
        fileName: 'report.pdf',
        filePath: 'SOBHA-001/report.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        createdBy: 'a1000000-0000-0000-0000-000000000001', // R. Kumar's id
        createdByName: 'R. Kumar',
        departmentId: 'dept-maint-001',
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DocumentShareDialog(
              document: myDoc,
              organizationId: 'SOBHA-001',
              currentUserId: 'a1000000-0000-0000-0000-000000000001', // Current user is R. Kumar
              currentUserName: 'R. Kumar',
              currentUserRole: 'staff',
              currentUserDepartment: 'Maintenance',
              currentUserDepartmentId: 'dept-maint-001',
              onSharesUpdated: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<Person>));
      await tester.pumpAndSettle();

      // Current user R. Kumar must not appear as recipient
      expect(find.textContaining('R. Kumar (Maintenance Supervisor)'), findsNothing);

      // Inactive user T. Reed must not appear
      expect(find.textContaining('T. Reed'), findsNothing);
    });

    testWidgets('surfaces diagnostic error banner with Retry action when user loading fails', (tester) async {
      final now = DateTime.now();
      final myDoc = DocumentRecord(
        id: 'doc-err-01',
        organizationId: 'SOBHA-001',
        title: 'Incident Report',
        fileName: 'incident.pdf',
        filePath: 'SOBHA-001/incident.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        createdBy: 'staff-01',
        createdByName: 'Staff User',
        departmentId: 'dept-ops-001',
        createdAt: now,
        updatedAt: now,
      );

      final failingUserService = _FailingUserService();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DocumentShareDialog(
              document: myDoc,
              organizationId: 'SOBHA-001',
              currentUserId: 'staff-01',
              currentUserName: 'Staff User',
              currentUserRole: 'staff',
              currentUserDepartment: 'Operations',
              currentUserDepartmentId: 'dept-ops-001',
              userService: failingUserService,
              onSharesUpdated: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Error banner must be visible
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.textContaining('Simulated RLS permission error'), findsOneWidget);
      expect(find.byKey(const Key('retry_load_recipients_button')), findsOneWidget);

      // Dropdown label shows "Error loading recipients"
      expect(find.text('Error loading recipients'), findsOneWidget);
      expect(find.text('No eligible recipients found'), findsNothing);

      // Test Retry button
      failingUserService.shouldFail = false;
      await tester.tap(find.byKey(const Key('retry_load_recipients_button')));
      await tester.pumpAndSettle();

      // Error should now be gone
      expect(find.textContaining('Simulated RLS permission error'), findsNothing);
      expect(find.text('Select Colleague / Manager'), findsOneWidget);
    });

    testWidgets('disables already-shared users in recipient dropdown and prevents duplicate sharing', (tester) async {
      final now = DateTime.now();
      final myDoc = DocumentRecord(
        id: 'doc-dup-01',
        organizationId: 'SOBHA-001',
        title: 'Safety Policy 2026',
        fileName: 'policy.pdf',
        filePath: 'SOBHA-001/policy.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        createdBy: 'staff-01',
        createdByName: 'Staff User',
        departmentId: 'dept-ops-001',
        createdAt: now,
        updatedAt: now,
      );

      // Pre-seed an existing share with M. Ali
      MockDocumentStore.instance.shares.add(
        DocumentShare(
          id: 'share-pre-1',
          documentId: 'doc-dup-01',
          userId: 'a1000000-0000-0000-0000-000000000002', // M. Ali
          userName: 'M. Ali',
          userEmail: 'm.ali@actionflow.demo',
          organizationId: 'SOBHA-001',
          permission: 'view',
          sharedBy: 'staff-01',
          sharedByName: 'Staff User',
          createdAt: now,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DocumentShareDialog(
              document: myDoc,
              organizationId: 'SOBHA-001',
              currentUserId: 'staff-01',
              currentUserName: 'Staff User',
              currentUserRole: 'staff',
              currentUserDepartment: 'Operations',
              currentUserDepartmentId: 'dept-ops-001',
              onSharesUpdated: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Active share should be displayed in the list
      expect(find.text('Active Shares (1)'), findsOneWidget);
      expect(find.text('M. Ali'), findsOneWidget);
      expect(find.textContaining('m.ali@actionflow.demo'), findsOneWidget);

      // Open dropdown to inspect
      await tester.tap(find.byType(DropdownButtonFormField<Person>));
      await tester.pumpAndSettle();

      // M. Ali should have 'Already Shared' badge
      expect(find.text('Already Shared'), findsOneWidget);
    });

    testWidgets('allows staff to share with manager and revoke active share', (tester) async {
      final now = DateTime.now();
      final myDoc = DocumentRecord(
        id: 'doc-share-flow-01',
        organizationId: 'SOBHA-001',
        title: 'Audit Evidence Doc',
        fileName: 'evidence.pdf',
        filePath: 'SOBHA-001/evidence.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        createdBy: 'staff-01',
        createdByName: 'Staff User',
        departmentId: 'dept-ops-001',
        createdAt: now,
        updatedAt: now,
      );

      bool sharesUpdated = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DocumentShareDialog(
              document: myDoc,
              organizationId: 'SOBHA-001',
              currentUserId: 'staff-01',
              currentUserName: 'Staff User',
              currentUserRole: 'staff',
              currentUserDepartment: 'Operations',
              currentUserDepartmentId: 'dept-ops-001',
              onSharesUpdated: () {
                sharesUpdated = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select Operations Manager from dropdown
      await tester.tap(find.byType(DropdownButtonFormField<Person>));
      await tester.pumpAndSettle();

      final managerItem = find.textContaining('Operations Manager').last;
      await tester.tap(managerItem);
      await tester.pumpAndSettle();

      // Tap Share button
      final shareButton = find.byKey(const Key('documents_confirm_share_button'));
      expect(shareButton, findsOneWidget);
      await tester.tap(shareButton);
      await tester.pumpAndSettle();

      // Verify share is registered
      expect(sharesUpdated, isTrue);
      expect(find.text('Active Shares (1)'), findsOneWidget);
      expect(find.textContaining('Document successfully shared with Operations Manager'), findsOneWidget);

      // Tap Revoke button
      final revokeButton = find.text('Revoke');
      expect(revokeButton, findsOneWidget);
      await tester.tap(revokeButton);
      await tester.pumpAndSettle();

      // Verify access revoked
      expect(find.text('Active Shares (0)'), findsOneWidget);
      expect(
        MockDocumentStore.instance.shares
            .where((s) => s.documentId == 'doc-share-flow-01')
            .isEmpty,
        isTrue,
      );
    });

    testWidgets(
      'enforces staff directory visibility: allows same-department staff and cross-department managers, but strictly excludes cross-department staff, inactive users, cross-org users, and self',
      (tester) async {
        final now = DateTime.now();
        final myDoc = DocumentRecord(
          id: 'doc-visibility-01',
          organizationId: 'SOBHA-001',
          title: 'Electrical Safety Checklist',
          fileName: 'electrical_checklist.pdf',
          filePath: 'SOBHA-001/electrical_checklist.pdf',
          fileSize: 1024,
          fileType: 'application/pdf',
          createdBy: 'staff-caller-01',
          createdByName: 'John Maintenance',
          departmentId: 'dept-maint-001',
          createdAt: now,
          updatedAt: now,
        );

        final candidates = [
          // 1. Same-department colleague (ACTIVE) -> MUST BE ELIGIBLE
          Person(
            id: 'staff-same-dept-01',
            name: 'Same Dept Colleague',
            email: 'same.dept@sobha.com',
            phone: '+91 90000 00001',
            designation: 'Maintenance Electrician',
            department: 'Maintenance',
            departmentId: 'dept-maint-001',
            organizationId: 'SOBHA-001',
            role: UserRole.actionOwnerWorker,
            type: PersonType.internalUser,
            isActive: true,
          ),
          // 2. Cross-department Manager (ACTIVE) -> MUST BE ELIGIBLE
          Person(
            id: 'mgr-cross-dept-01',
            name: 'Cross Dept Manager',
            email: 'hse.mgr@sobha.com',
            phone: '+91 90000 00002',
            designation: 'HSE Operations Manager',
            department: 'HSE',
            departmentId: 'dept-hse-001',
            organizationId: 'SOBHA-001',
            role: UserRole.departmentManager,
            type: PersonType.internalUser,
            isActive: true,
          ),
          // 3. Organization Admin (ACTIVE) -> MUST BE EXCLUDED from Staff Portal
          Person(
            id: 'admin-org-01',
            name: 'Company Administrator',
            email: 'admin@sobha.com',
            phone: '+91 90000 00003',
            designation: 'Administrator',
            department: 'Corporate',
            departmentId: 'dept-corp-001',
            organizationId: 'SOBHA-001',
            role: UserRole.admin,
            type: PersonType.internalUser,
            isActive: true,
          ),
          // 4. Cross-department Regular Staff -> MUST BE EXCLUDED
          Person(
            id: 'staff-cross-dept-01',
            name: 'Cross Dept Staff Member',
            email: 'other.dept@sobha.com',
            phone: '+91 90000 00004',
            designation: 'Safety Inspector',
            department: 'HSE',
            departmentId: 'dept-hse-001',
            organizationId: 'SOBHA-001',
            role: UserRole.actionOwnerWorker,
            type: PersonType.internalUser,
            isActive: true,
          ),
          // 5. Inactive Manager in Same Org -> MUST BE EXCLUDED
          Person(
            id: 'mgr-inactive-01',
            name: 'Inactive Ops Manager',
            email: 'inactive.mgr@sobha.com',
            phone: '+91 90000 00005',
            designation: 'Former Manager',
            department: 'Operations',
            departmentId: 'dept-ops-001',
            organizationId: 'SOBHA-001',
            role: UserRole.departmentManager,
            type: PersonType.internalUser,
            isActive: false,
          ),
          // 6. Inactive Staff in Same Department -> MUST BE EXCLUDED
          Person(
            id: 'staff-inactive-01',
            name: 'Inactive Colleague',
            email: 'inactive.staff@sobha.com',
            phone: '+91 90000 00006',
            designation: 'Former Electrician',
            department: 'Maintenance',
            departmentId: 'dept-maint-001',
            organizationId: 'SOBHA-001',
            role: UserRole.actionOwnerWorker,
            type: PersonType.internalUser,
            isActive: false,
          ),
          // 7. Cross-Organization Manager -> MUST BE EXCLUDED
          Person(
            id: 'mgr-other-org-01',
            name: 'External Org Manager',
            email: 'other.mgr@otherorg.com',
            phone: '+91 90000 00007',
            designation: 'Operations Manager',
            department: 'Maintenance',
            departmentId: 'dept-maint-001',
            organizationId: 'OTHER-ORG-999',
            role: UserRole.departmentManager,
            type: PersonType.internalUser,
            isActive: true,
          ),
          // 8. Cross-Organization Staff -> MUST BE EXCLUDED
          Person(
            id: 'staff-other-org-01',
            name: 'External Org Staff',
            email: 'other.staff@otherorg.com',
            phone: '+91 90000 00008',
            designation: 'Technician',
            department: 'Maintenance',
            departmentId: 'dept-maint-001',
            organizationId: 'OTHER-ORG-999',
            role: UserRole.actionOwnerWorker,
            type: PersonType.internalUser,
            isActive: true,
          ),
          // 9. Current User Self -> MUST BE EXCLUDED
          Person(
            id: 'staff-caller-01',
            name: 'John Maintenance',
            email: 'john.maint@sobha.com',
            phone: '+91 90000 00009',
            designation: 'Maintenance Staff',
            department: 'Maintenance',
            departmentId: 'dept-maint-001',
            organizationId: 'SOBHA-001',
            role: UserRole.actionOwnerWorker,
            type: PersonType.internalUser,
            isActive: true,
          ),
        ];

        final customService = _StaticCandidateUserService(candidates);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: DocumentShareDialog(
                document: myDoc,
                organizationId: 'SOBHA-001',
                currentUserId: 'staff-caller-01',
                currentUserName: 'John Maintenance',
                currentUserRole: 'staff',
                currentUserDepartment: 'Maintenance',
                currentUserDepartmentId: 'dept-maint-001',
                userService: customService,
                onSharesUpdated: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Dropdown must be available with eligible candidates
        expect(find.text('Select Colleague / Manager'), findsOneWidget);
        expect(find.text('No eligible recipients found'), findsNothing);

        // Open recipient dropdown
        await tester.tap(find.byType(DropdownButtonFormField<Person>));
        await tester.pumpAndSettle();

        // POSITIVE ASSERTIONS:
        expect(find.textContaining('Same Dept Colleague'), findsOneWidget);
        expect(find.textContaining('Cross Dept Manager'), findsOneWidget);

        // NEGATIVE ASSERTIONS:
        // Admin Portal accounts (System Administrator, Company Admin) are excluded from Staff Portal
        expect(find.textContaining('Company Administrator'), findsNothing);
        expect(find.textContaining('Cross Dept Staff Member'), findsNothing);
        expect(find.textContaining('Inactive Ops Manager'), findsNothing);
        expect(find.textContaining('Inactive Colleague'), findsNothing);
        expect(find.textContaining('External Org Manager'), findsNothing);
        expect(find.textContaining('External Org Staff'), findsNothing);
        expect(find.textContaining('John Maintenance'), findsNothing);
      },
    );
  });

  group('DocumentService Department Sharing Isolation Security Rules', () {
    test('enforces that staff can only share their own authored documents', () async {
      final now = DateTime.now();
      MockDocumentStore.instance.documents.clear();
      MockDocumentStore.instance.documents.add(
        DocumentRecord(
          id: 'doc-auth-01',
          organizationId: 'SOBHA-001',
          title: 'Manager Audit Doc',
          fileName: 'audit.pdf',
          filePath: 'SOBHA-001/audit.pdf',
          fileSize: 1024,
          fileType: 'application/pdf',
          createdBy: 'mgr-01',
          createdByName: 'Manager Ali',
          departmentId: 'dept-hse',
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Non-owner staff attempting to share must be rejected
      expect(
        () => DocumentService.instance.shareDocumentInternal(
          documentId: 'doc-auth-01',
          organizationId: 'SOBHA-001',
          userId: 'colleague-02',
          userName: 'Sarah Colleague',
          userEmail: 'sarah@sobha.com',
          permission: 'view',
          sharedBy: 'staff-01',
          sharedByName: 'John Staff',
          callerRole: 'staff',
          callerDepartmentId: 'dept-hse',
          recipientDepartmentId: 'dept-hse',
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Staff members can only share documents they authored'),
        )),
      );
    });

    test('enforces that staff cannot share with colleagues in a different department', () async {
      final now = DateTime.now();
      MockDocumentStore.instance.documents.clear();
      MockDocumentStore.instance.documents.add(
        DocumentRecord(
          id: 'doc-auth-02',
          organizationId: 'SOBHA-001',
          title: 'My Field Report',
          fileName: 'field_report.pdf',
          filePath: 'SOBHA-001/field_report.pdf',
          fileSize: 1024,
          fileType: 'application/pdf',
          createdBy: 'staff-01',
          createdByName: 'John Staff',
          departmentId: 'dept-hse',
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Staff attempting to share with recipient in a different department must be rejected
      expect(
        () => DocumentService.instance.shareDocumentInternal(
          documentId: 'doc-auth-02',
          organizationId: 'SOBHA-001',
          userId: 'worker-maint-01',
          userName: 'Bob Maintenance',
          userEmail: 'bob@sobha.com',
          permission: 'view',
          sharedBy: 'staff-01',
          sharedByName: 'John Staff',
          callerRole: 'staff',
          callerDepartmentId: 'dept-hse',
          recipientDepartmentId: 'dept-maintenance',
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Department Isolation Violation'),
        )),
      );
    });

    test('allows staff to share with same-department colleague, updates count, and allows revocation', () async {
      final now = DateTime.now();
      MockDocumentStore.instance.documents.clear();
      MockDocumentStore.instance.documents.add(
        DocumentRecord(
          id: 'doc-auth-03',
          organizationId: 'SOBHA-001',
          title: 'My Safety Check',
          fileName: 'check.pdf',
          filePath: 'SOBHA-001/check.pdf',
          fileSize: 1024,
          fileType: 'application/pdf',
          createdBy: 'staff-01',
          createdByName: 'John Staff',
          departmentId: 'dept-hse',
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Share with HSE colleague
      final shareResult = await DocumentService.instance.shareDocumentInternal(
        documentId: 'doc-auth-03',
        organizationId: 'SOBHA-001',
        userId: 'colleague-hse-02',
        userName: 'Elena HSE',
        userEmail: 'elena@sobha.com',
        permission: 'view',
        sharedBy: 'staff-01',
        sharedByName: 'John Staff',
        callerRole: 'staff',
        callerDepartmentId: 'dept-hse',
        recipientDepartmentId: 'dept-hse',
      );

      expect(shareResult, isNotNull);
      expect(shareResult.userId, equals('colleague-hse-02'));

      // Check document was updated with recipient
      final updatedDoc = MockDocumentStore.instance.documents.firstWhere((d) => d.id == 'doc-auth-03');
      expect(updatedDoc.sharedWithUserIds, contains('colleague-hse-02'));
      expect(updatedDoc.sharedInternalCount, equals(1));

      // Revoke the share
      await DocumentService.instance.revokeDocumentInternalShare(
        shareId: shareResult.id,
        userId: 'colleague-hse-02',
        documentId: 'doc-auth-03',
        organizationId: 'SOBHA-001',
      );

      // Check access was revoked
      final revokedDoc = MockDocumentStore.instance.documents.firstWhere((d) => d.id == 'doc-auth-03');
      expect(revokedDoc.sharedWithUserIds, isNot(contains('colleague-hse-02')));
      expect(revokedDoc.sharedInternalCount, equals(0));
    });

    test('rejects inactive recipient with clear error matching trigger P0001', () async {
      final now = DateTime.now();
      MockDocumentStore.instance.documents.clear();
      MockDocumentStore.instance.documents.add(
        DocumentRecord(
          id: 'doc-auth-04',
          organizationId: 'SOBHA-001',
          title: 'Emergency Response Plan',
          fileName: 'erp.pdf',
          filePath: 'SOBHA-001/erp.pdf',
          fileSize: 1024,
          fileType: 'application/pdf',
          createdBy: 'staff-01',
          createdByName: 'John Staff',
          departmentId: 'dept-hse',
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(
        () => DocumentService.instance.shareDocumentInternal(
          documentId: 'doc-auth-04',
          organizationId: 'SOBHA-001',
          userId: 'inactive-user-01',
          userName: 'Inactive User',
          userEmail: 'inactive@sobha.com',
          permission: 'view',
          sharedBy: 'staff-01',
          sharedByName: 'John Staff',
          callerRole: 'staff',
          callerDepartmentId: 'dept-hse',
          recipientDepartmentId: 'dept-hse',
          recipientIsActive: false,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Share recipient is inactive or does not exist'),
        )),
      );
    });

    test('rejects empty or nonexistent recipient ID with clear error', () async {
      final now = DateTime.now();
      MockDocumentStore.instance.documents.clear();
      MockDocumentStore.instance.documents.add(
        DocumentRecord(
          id: 'doc-auth-05',
          organizationId: 'SOBHA-001',
          title: 'Site Induction Guide',
          fileName: 'guide.pdf',
          filePath: 'SOBHA-001/guide.pdf',
          fileSize: 1024,
          fileType: 'application/pdf',
          createdBy: 'staff-01',
          createdByName: 'John Staff',
          departmentId: 'dept-hse',
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(
        () => DocumentService.instance.shareDocumentInternal(
          documentId: 'doc-auth-05',
          organizationId: 'SOBHA-001',
          userId: '   ',
          userName: 'Empty ID User',
          userEmail: 'empty@sobha.com',
          permission: 'view',
          sharedBy: 'staff-01',
          sharedByName: 'John Staff',
          callerRole: 'staff',
          callerDepartmentId: 'dept-hse',
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Share recipient is inactive or does not exist'),
        )),
      );
    });

    test('rejects cross-organization recipient', () async {
      final now = DateTime.now();
      MockDocumentStore.instance.documents.clear();
      MockDocumentStore.instance.documents.add(
        DocumentRecord(
          id: 'doc-auth-06',
          organizationId: 'SOBHA-001',
          title: 'Site Access Protocol',
          fileName: 'access.pdf',
          filePath: 'SOBHA-001/access.pdf',
          fileSize: 1024,
          fileType: 'application/pdf',
          createdBy: 'staff-01',
          createdByName: 'John Staff',
          departmentId: 'dept-hse',
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(
        () => DocumentService.instance.shareDocumentInternal(
          documentId: 'doc-auth-06',
          organizationId: 'SOBHA-001',
          userId: 'other-org-user-01',
          userName: 'Other Org Colleague',
          userEmail: 'colleague@other.com',
          permission: 'view',
          sharedBy: 'staff-01',
          sharedByName: 'John Staff',
          callerRole: 'staff',
          callerDepartmentId: 'dept-hse',
          recipientDepartmentId: 'dept-hse',
          recipientOrganizationId: 'OTHER-ORG-999',
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Recipient belongs to a different organization'),
        )),
      );
    });

    test('allows sharing with manager across departments and syncs share records', () async {
      final now = DateTime.now();
      MockDocumentStore.instance.documents.clear();
      MockDocumentStore.instance.documents.add(
        DocumentRecord(
          id: 'doc-auth-07',
          organizationId: 'SOBHA-001',
          title: 'Department Safety Audit',
          fileName: 'audit_dept.pdf',
          filePath: 'SOBHA-001/audit_dept.pdf',
          fileSize: 1024,
          fileType: 'application/pdf',
          createdBy: 'staff-01',
          createdByName: 'John Staff',
          departmentId: 'dept-hse',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final share = await DocumentService.instance.shareDocumentInternal(
        documentId: 'doc-auth-07',
        organizationId: 'SOBHA-001',
        userId: 'mgr-ops-01',
        userName: 'Operations Manager',
        userEmail: 'ops.mgr@sobha.com',
        permission: 'view',
        sharedBy: 'staff-01',
        sharedByName: 'John Staff',
        callerRole: 'staff',
        callerDepartmentId: 'dept-hse',
        recipientDepartmentId: 'dept-ops',
        recipientRole: 'manager',
        recipientIsActive: true,
        recipientOrganizationId: 'SOBHA-001',
      );

      expect(share, isNotNull);
      final sharedWithIds = await DocumentService.instance.fetchDocumentIdsSharedWith(
        organizationId: 'SOBHA-001',
        userId: 'mgr-ops-01',
      );
      expect(sharedWithIds, contains('doc-auth-07'));

      final sharedByIds = await DocumentService.instance.fetchDocumentIdsSharedBy(
        organizationId: 'SOBHA-001',
        userId: 'staff-01',
      );
      expect(sharedByIds, contains('doc-auth-07'));
    });
  });

  group('Manager Portal Documents Tabs & Filter Chips', () {
    testWidgets('renders all 5 separate tabs with accurate counts and correct document segregation', (tester) async {
      final now = DateTime.now();
      MockDocumentStore.instance.reset();
      MockDocumentStore.instance.documents.clear();
      MockDocumentStore.instance.shares.clear();

      final mgrProfile = UserProfile(
        id: 'usr-mgr-test-01',
        name: 'Alex Manager',
        email: 'alex.mgr@sobha.com',
        phone: '+971 50 123 4567',
        designation: 'Safety Manager',
        department: 'HSE',
        division: 'Operations',
        site: 'North Yard',
        role: 'manager',
        organizationId: 'SOBHA-001',
        organizationName: 'Sobha Construction',
      );

      // 1. Uploaded by this manager (unshared)
      final docMine = DocumentRecord(
        id: 'doc-mgr-mine-01',
        organizationId: 'SOBHA-001',
        title: 'Manager Weekly Safety Inspection',
        fileName: 'weekly_inspection.pdf',
        filePath: 'SOBHA-001/weekly_inspection.pdf',
        fileSize: 1024 * 100,
        fileType: 'application/pdf',
        category: DocumentCategory.auditChecklists,
        createdBy: 'usr-mgr-test-01',
        createdByName: 'Alex Manager',
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now.subtract(const Duration(days: 2)),
      );

      // 2. Uploaded by this manager AND shared by this manager
      final docSharedByMe = DocumentRecord(
        id: 'doc-mgr-shared-by-me-01',
        organizationId: 'SOBHA-001',
        title: 'Site Evacuation Procedure',
        fileName: 'evac_procedure.pdf',
        filePath: 'SOBHA-001/evac_procedure.pdf',
        fileSize: 1024 * 200,
        fileType: 'application/pdf',
        category: DocumentCategory.hsseManuals,
        createdBy: 'usr-mgr-test-01',
        createdByName: 'Alex Manager',
        sharedInternalCount: 1,
        sharedWithUserIds: ['staff-worker-01'],
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now.subtract(const Duration(days: 3)),
      );

      // 3. Uploaded by ANOTHER user and shared WITH this manager
      final docSharedWithMe = DocumentRecord(
        id: 'doc-mgr-shared-with-me-01',
        organizationId: 'SOBHA-001',
        title: 'Subcontractor Incident Notice',
        fileName: 'subcontractor_incident.pdf',
        filePath: 'SOBHA-001/subcontractor_incident.pdf',
        fileSize: 1024 * 150,
        fileType: 'application/pdf',
        category: DocumentCategory.incidentReports,
        createdBy: 'staff-worker-01',
        createdByName: 'Staff Worker',
        sharedInternalCount: 1,
        sharedWithUserIds: ['usr-mgr-test-01'],
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(days: 1)),
      );

      // 4. Policy/Guideline document
      final docGuideline = DocumentRecord(
        id: 'doc-mgr-guideline-01',
        organizationId: 'SOBHA-001',
        title: 'Corporate PPE Policy Manual',
        fileName: 'ppe_manual.pdf',
        filePath: 'SOBHA-001/ppe_manual.pdf',
        fileSize: 1024 * 300,
        fileType: 'application/pdf',
        category: DocumentCategory.policies,
        createdBy: 'admin-corp-01',
        createdByName: 'Corporate Admin',
        createdAt: now.subtract(const Duration(days: 10)),
        updatedAt: now.subtract(const Duration(days: 10)),
      );

      MockDocumentStore.instance.documents.addAll([
        docMine,
        docSharedByMe,
        docSharedWithMe,
        docGuideline,
      ]);

      MockDocumentStore.instance.shares.addAll([
        DocumentShare(
          id: 'share-test-1',
          documentId: 'doc-mgr-shared-by-me-01',
          userId: 'staff-worker-01',
          userName: 'Staff Worker',
          userEmail: 'staff@sobha.com',
          organizationId: 'SOBHA-001',
          permission: 'view',
          sharedBy: 'usr-mgr-test-01',
          sharedByName: 'Alex Manager',
          createdAt: now,
        ),
        DocumentShare(
          id: 'share-test-2',
          documentId: 'doc-mgr-shared-with-me-01',
          userId: 'usr-mgr-test-01',
          userName: 'Alex Manager',
          userEmail: 'alex.mgr@sobha.com',
          organizationId: 'SOBHA-001',
          permission: 'view',
          sharedBy: 'staff-worker-01',
          sharedByName: 'Staff Worker',
          createdAt: now,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: ManagerDashboardScreen(userProfile: mgrProfile),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Documents view
      final docNav = find.text('Documents');
      expect(docNav, findsWidgets);
      await tester.tap(docNav.first);
      await tester.pumpAndSettle();

      // Verify all 5 tab chips are rendered
      expect(find.byKey(const Key('manager_doc_tab_all_documents')), findsOneWidget);
      expect(find.byKey(const Key('manager_doc_tab_my_uploads')), findsOneWidget);
      expect(find.byKey(const Key('manager_doc_tab_shared_with_me')), findsOneWidget);
      expect(find.byKey(const Key('manager_doc_tab_shared_by_me')), findsOneWidget);
      expect(find.byKey(const Key('manager_doc_tab_guidelines_&_policies')), findsOneWidget);

      // Verify counts in tab labels
      expect(find.text('All Documents (4)'), findsOneWidget);
      expect(find.text('My Uploads (2)'), findsOneWidget);
      expect(find.text('Shared with Me (1)'), findsOneWidget);
      expect(find.text('Shared by Me (1)'), findsOneWidget);
      expect(find.text('Guidelines & Policies (2)'), findsOneWidget);

      // In All Documents (default): all 4 documents are visible
      expect(find.text('Manager Weekly Safety Inspection'), findsOneWidget);
      expect(find.text('Site Evacuation Procedure'), findsOneWidget);
      expect(find.text('Subcontractor Incident Notice'), findsOneWidget);
      expect(find.text('Corporate PPE Policy Manual'), findsOneWidget);

      // Tap 'My Uploads' tab
      await tester.tap(find.byKey(const Key('manager_doc_tab_my_uploads')));
      await tester.pumpAndSettle();

      // In My Uploads: manager-authored documents appear, but shared-with-me does NOT appear
      expect(find.text('Manager Weekly Safety Inspection'), findsOneWidget);
      expect(find.text('Site Evacuation Procedure'), findsOneWidget);
      expect(find.text('Subcontractor Incident Notice'), findsNothing);
      expect(find.text('Corporate PPE Policy Manual'), findsNothing);

      // Tap 'Shared with Me' tab
      await tester.tap(find.byKey(const Key('manager_doc_tab_shared_with_me')));
      await tester.pumpAndSettle();

      // In Shared with Me: received document appears, manager's own uploads do NOT appear
      expect(find.text('Subcontractor Incident Notice'), findsOneWidget);
      expect(find.text('Manager Weekly Safety Inspection'), findsNothing);
      expect(find.text('Site Evacuation Procedure'), findsNothing);

      // Tap 'Shared by Me' tab
      await tester.tap(find.byKey(const Key('manager_doc_tab_shared_by_me')));
      await tester.pumpAndSettle();

      // In Shared by Me: only the document shared by this manager appears
      expect(find.text('Site Evacuation Procedure'), findsOneWidget);
      expect(find.text('Manager Weekly Safety Inspection'), findsNothing);
      expect(find.text('Subcontractor Incident Notice'), findsNothing);

      // Tap 'Guidelines & Policies' tab
      await tester.tap(find.byKey(const Key('manager_doc_tab_guidelines_&_policies')));
      await tester.pumpAndSettle();

      // In Guidelines & Policies: SOPs and Policies appear
      expect(find.text('Corporate PPE Policy Manual'), findsOneWidget);
      expect(find.text('Site Evacuation Procedure'), findsOneWidget);
      expect(find.text('Subcontractor Incident Notice'), findsNothing);

      // Revocation test: Revoke the share with Alex Manager on doc-mgr-shared-with-me-01
      await DocumentService.instance.revokeDocumentInternalShare(
        shareId: 'share-test-2',
        userId: 'usr-mgr-test-01',
        documentId: 'doc-mgr-shared-with-me-01',
        organizationId: 'SOBHA-001',
      );

      // Refresh documents view by tapping refresh button
      await tester.tap(find.byTooltip('Refresh Documents'));
      await tester.pumpAndSettle();

      // Tap 'Shared with Me' tab
      await tester.tap(find.byKey(const Key('manager_doc_tab_shared_with_me')));
      await tester.pumpAndSettle();

      // Revoked document must now be absent from Shared with Me
      expect(find.text('Subcontractor Incident Notice'), findsNothing);
      expect(find.text('Shared with Me (0)'), findsOneWidget);
    });
  });

  group('Staff Document Deletion & Ownership Security Rules', () {
    testWidgets('staff user can delete their own uploaded document with confirmation dialog', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final now = DateTime.now();
      MockDocumentStore.instance.documents.clear();
      MockDocumentStore.instance.documents.addAll([
        DocumentRecord(
          id: 'doc-staff-owned-01',
          organizationId: 'SOBHA-001',
          title: 'My Hazardous Waste Log',
          fileName: 'waste_log.pdf',
          filePath: 'SOBHA-001/waste_log.pdf',
          fileSize: 1024,
          fileType: 'application/pdf',
          category: 'Action Evidence',
          createdBy: 'staff-worker-01',
          createdByName: 'John Staff',
          createdAt: now,
          updatedAt: now,
        ),
        DocumentRecord(
          id: 'doc-staff-other-01',
          organizationId: 'SOBHA-001',
          title: 'Safety Guidelines Manual',
          fileName: 'guidelines.pdf',
          filePath: 'SOBHA-001/guidelines.pdf',
          fileSize: 2048,
          fileType: 'application/pdf',
          category: 'Company Policies',
          createdBy: 'mgr-01',
          createdByName: 'Safety Manager',
          createdAt: now,
          updatedAt: now,
        ),
      ]);

      final staffProfile = UserProfile.mockStaff().copyWith(
        id: 'staff-worker-01',
        name: 'John Staff',
        email: 'john.staff@sobha.com',
        role: 'worker',
        department: 'Construction HSE',
        organizationId: 'SOBHA-001',
        organizationName: 'Sobha Construction',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: WorkerDashboardScreen(userProfile: staffProfile),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Documents tab in sidebar
      await tester.tap(find.text('Documents'));
      await tester.pumpAndSettle();

      // Verify both documents are displayed
      expect(find.text('My Hazardous Waste Log'), findsOneWidget);
      expect(find.text('Safety Guidelines Manual'), findsOneWidget);

      // Verify Delete icon is present ONLY for the owned document (finds 1 delete icon)
      final deleteButtons = find.byTooltip('Delete Document');
      expect(deleteButtons, findsOneWidget);

      // Tap Delete Document icon
      await tester.tap(deleteButtons);
      await tester.pumpAndSettle();

      // Verify confirmation dialog appears with title and description
      expect(find.text('Delete Document'), findsWidgets);
      expect(
        find.textContaining('Are you sure you want to delete "My Hazardous Waste Log"?'),
        findsOneWidget,
      );

      // Tap Cancel button first
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Verify dialog is closed and document is NOT deleted
      expect(find.text('My Hazardous Waste Log'), findsOneWidget);
      expect(MockDocumentStore.instance.documents.any((d) => d.id == 'doc-staff-owned-01'), isTrue);

      // Tap Delete Document again and confirm
      await tester.tap(deleteButtons);
      await tester.pumpAndSettle();

      // Tap the 'Delete' FilledButton inside the confirmation dialog
      final confirmDeleteBtn = find.widgetWithText(FilledButton, 'Delete');
      expect(confirmDeleteBtn, findsOneWidget);
      await tester.tap(confirmDeleteBtn);
      await tester.pumpAndSettle();

      // Verify SnackBar appears and document is removed from view and mock store
      expect(find.text('Document "My Hazardous Waste Log" deleted.'), findsOneWidget);
      expect(find.text('My Hazardous Waste Log'), findsNothing);
      expect(MockDocumentStore.instance.documents.any((d) => d.id == 'doc-staff-owned-01'), isFalse);
    });

    test('DocumentService.deleteDocument rejects deletion attempt by non-owner staff member', () async {
      final now = DateTime.now();
      MockDocumentStore.instance.documents.clear();
      MockDocumentStore.instance.documents.add(
        DocumentRecord(
          id: 'doc-mgr-only-01',
          organizationId: 'SOBHA-001',
          title: 'Manager Confidential Audit',
          fileName: 'audit.pdf',
          filePath: 'SOBHA-001/audit.pdf',
          fileSize: 4096,
          fileType: 'application/pdf',
          category: 'Audit Checklists',
          createdBy: 'mgr-01',
          createdByName: 'Safety Manager',
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(
        () => DocumentService.instance.deleteDocument(
          documentId: 'doc-mgr-only-01',
          organizationId: 'SOBHA-001',
          userId: 'staff-worker-01',
          userRole: 'staff',
          userName: 'John Staff',
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Staff members can only delete documents they authored'),
        )),
      );

      // Verify document still exists in store
      expect(MockDocumentStore.instance.documents.any((d) => d.id == 'doc-mgr-only-01'), isTrue);
    });

    test('DocumentService.deleteDocument cascades to shares and external tokens upon deletion', () async {
      final now = DateTime.now();
      MockDocumentStore.instance.documents.clear();
      MockDocumentStore.instance.shares.clear();
      MockDocumentStore.instance.externalTokens.clear();

      MockDocumentStore.instance.documents.add(
        DocumentRecord(
          id: 'doc-staff-cascade-01',
          organizationId: 'SOBHA-001',
          title: 'Incident Analysis Report',
          fileName: 'incident.pdf',
          filePath: 'SOBHA-001/incident.pdf',
          fileSize: 2048,
          fileType: 'application/pdf',
          category: 'Action Evidence',
          createdBy: 'staff-worker-01',
          createdByName: 'John Staff',
          createdAt: now,
          updatedAt: now,
        ),
      );

      MockDocumentStore.instance.shares.add(
        DocumentShare(
          id: 'share-casc-01',
          documentId: 'doc-staff-cascade-01',
          userId: 'mgr-01',
          userName: 'Alex Manager',
          sharedBy: 'staff-worker-01',
          organizationId: 'SOBHA-001',
          permission: 'view',
          createdAt: now,
        ),
      );

      await DocumentService.instance.deleteDocument(
        documentId: 'doc-staff-cascade-01',
        organizationId: 'SOBHA-001',
        userId: 'staff-worker-01',
        userRole: 'staff',
        userName: 'John Staff',
      );

      expect(MockDocumentStore.instance.documents.any((d) => d.id == 'doc-staff-cascade-01'), isFalse);
      expect(MockDocumentStore.instance.shares.any((s) => s.documentId == 'doc-staff-cascade-01'), isFalse);
    });
  });

  group('Staff Recipient Discovery & Search Filtering', () {
    testWidgets('shows helpful empty state caption when search yields no matching recipients', (tester) async {
      tester.view.physicalSize = const Size(800, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final doc = DocumentRecord(
        id: 'doc-share-search-01',
        organizationId: 'SOBHA-001',
        title: 'Safety Inspection Photos',
        fileName: 'photos.pdf',
        filePath: 'SOBHA-001/photos.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        category: 'Action Evidence',
        createdBy: 'staff-01',
        createdByName: 'John Staff',
        departmentId: 'dept-hse-01',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DocumentShareDialog(
              document: doc,
              organizationId: 'SOBHA-001',
              currentUserId: 'staff-01',
              currentUserName: 'John Staff',
              currentUserRole: 'staff',
              currentUserDepartment: 'Construction HSE',
              currentUserDepartmentId: 'dept-hse-01',
              onSharesUpdated: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Search for nonexistent person
      final searchField = find.byKey(const Key('documents_recipient_search_field'));
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'NonexistentPersonXYZ');
      await tester.pumpAndSettle();

      // Verify informative caption appears
      expect(find.text('No eligible recipients match "NonexistentPersonXYZ".'), findsOneWidget);
      expect(find.text('No matching recipients found'), findsOneWidget);
    });
  });
}

class _FailingUserService extends UserService {
  bool shouldFail = true;

  @override
  Future<List<Person>> fetchUsers(
    String organizationId, {
    bool allowMockFallback = true,
  }) async {
    if (shouldFail) {
      throw Exception('Simulated RLS permission error (code 42501)');
    }
    return MockPeopleStore.instance.people;
  }
}

class _StaticCandidateUserService extends UserService {
  final List<Person> candidateList;
  _StaticCandidateUserService(this.candidateList);

  @override
  Future<List<Person>> fetchUsers(
    String organizationId, {
    bool allowMockFallback = true,
  }) async {
    return candidateList;
  }
}


