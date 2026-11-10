import 'dart:convert';
import 'dart:typed_data';

import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/services/app_file_picker_service.dart';
import 'package:action_flow/widgets/document_preview/action_attachment_preview_dialog.dart';
import 'package:action_flow/widgets/document_preview/pdf_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testAction = ActionRecord(
    id: 'ACT-2026-PREV',
    actionNumber: 'ACT-2026-PREV',
    organizationId: 'org-test-preview',
    departmentId: 'dept-01',
    siteId: 'site-01',
    subject: 'Safety Audit Evidence Verification',
    actionRequired: 'Verify attachment preview formats',
    status: 'In Progress',
    priority: 'High',
    createdById: 'user-creator',
    assignedToId: 'user-assignee',
    assignedTo: 'Assignee User',
    division: 'HSE',
    attachments: const [
      'Site_Audit_Report.pdf',
      'Defect_Inspection.png',
      'Checklist_Notes.txt',
      'Contractor_Spreadsheet.xlsx',
      'Operating_Manual.docx',
    ],
  );

  Widget buildTestableWidget(Widget child, {Size size = const Size(1280, 900)}) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(body: child),
      ),
    );
  }

  group('Action Attachment In-App Preview Tests', () {
    testWidgets('1. PDF Preview: Renders PdfViewWidget with PDF header and badges', (tester) async {
      final pdfBytes = Uint8List.fromList(utf8.encode('%PDF-1.4 Mock PDF Stream Data'));

      await tester.pumpWidget(
        buildTestableWidget(
          ActionAttachmentPreviewDialog(
            action: testAction,
            fileName: 'Site_Audit_Report.pdf',
            currentUserId: 'user-creator',
            initialBytes: pdfBytes,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Header details (appears in modal header and inside PDF view)
      expect(find.text('Site_Audit_Report.pdf'), findsWidgets);
      expect(find.text('Action: ACT-2026-PREV • Verified HSSE Evidence'), findsOneWidget);

      // PDF viewer widget is rendered
      expect(find.byType(PdfViewWidget), findsOneWidget);

      // Format and Division badges
      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('HSE'), findsOneWidget);
    });

    testWidgets('2. Image Preview: Renders InteractiveViewer for PNG/JPG/WEBP images', (tester) async {
      // 1x1 transparent PNG binary bytes
      final pngBytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
        0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
      ]);

      await tester.pumpWidget(
        buildTestableWidget(
          ActionAttachmentPreviewDialog(
            action: testAction,
            fileName: 'Defect_Inspection.png',
            currentUserId: 'user-assignee',
            initialBytes: pngBytes,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Defect_Inspection.png'), findsOneWidget);
      // InteractiveViewer with zoom & pan is rendered for image
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('PNG'), findsOneWidget);
    });

    testWidgets('3. Plain Text & CSV: Renders SelectableText in monospace scroll view', (tester) async {
      const textSample = 'Item 1: Scaffolding checked OK\nItem 2: Hardhats inspected';
      final textBytes = Uint8List.fromList(utf8.encode(textSample));

      await tester.pumpWidget(
        buildTestableWidget(
          ActionAttachmentPreviewDialog(
            action: testAction,
            fileName: 'Checklist_Notes.txt',
            currentUserId: 'user-creator',
            initialBytes: textBytes,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Checklist_Notes.txt'), findsOneWidget);
      expect(find.text(textSample), findsOneWidget);
      expect(find.text('TXT'), findsOneWidget);
    });

    testWidgets('4. Unsupported Office Formats (DOCX, XLSX): Displays message and working download button', (tester) async {
      final excelBytes = Uint8List.fromList(utf8.encode('PK Mock Excel File Stream'));

      String? downloadedFileName;
      AppFilePicker.saveTestOverride = ({
        required String fileName,
        required Uint8List bytes,
        String mimeType = 'application/octet-stream',
      }) async {
        downloadedFileName = fileName;
        return true;
      };

      addTearDown(() {
        AppFilePicker.saveTestOverride = null;
      });

      await tester.pumpWidget(
        buildTestableWidget(
          ActionAttachmentPreviewDialog(
            action: testAction,
            fileName: 'Contractor_Spreadsheet.xlsx',
            currentUserId: 'user-creator',
            initialBytes: excelBytes,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Informative message
      expect(find.text('In-App Preview Unavailable'), findsOneWidget);
      expect(
        find.textContaining('In-app preview is not supported for .XLSX files.'),
        findsOneWidget,
      );

      // Working download button in dialog body
      final downloadBodyBtn = find.text('Download Contractor_Spreadsheet.xlsx');
      expect(downloadBodyBtn, findsOneWidget);
      await tester.tap(downloadBodyBtn);
      await tester.pumpAndSettle();

      expect(downloadedFileName, equals('Contractor_Spreadsheet.xlsx'));
    });

    testWidgets('5. Permission Denial: Unrelated user is denied preview with security message', (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          ActionAttachmentPreviewDialog(
            action: testAction,
            fileName: 'Site_Audit_Report.pdf',
            currentUserId: 'unrelated-user-999',
            isWorker: true,
            // No initialBytes -> triggers ActionService auth check
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Access lock error is displayed
      expect(find.text('Unable to preview attachment'), findsOneWidget);
      expect(
        find.textContaining('Permission denied: You are not authorized to access attachments'),
        findsOneWidget,
      );
    });

    testWidgets('6. ActionDetailsScreen Integration: Clicking preview icon or title opens preview modal', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestableWidget(
          ActionDetailsScreen(
            action: testAction,
            currentUserId: 'user-creator',
            isWorker: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Evidence & Attachments tab
      final evidenceTab = find.text('Evidence & Attachments');
      expect(evidenceTab, findsWidgets);
      await tester.tap(evidenceTab.first);
      await tester.pumpAndSettle();

      // Verify Preview button exists for Site_Audit_Report.pdf
      final previewBtn = find.byKey(const Key('preview_attachment_Site_Audit_Report.pdf_btn'));
      expect(previewBtn, findsOneWidget);

      // Verify Download button also exists
      final downloadBtn = find.byKey(const Key('download_attachment_Site_Audit_Report.pdf_btn'));
      expect(downloadBtn, findsOneWidget);

      // Tap preview button
      await tester.tap(previewBtn);
      await tester.pumpAndSettle();

      // ActionAttachmentPreviewDialog opens
      expect(find.byType(ActionAttachmentPreviewDialog), findsOneWidget);
      expect(find.text('Site_Audit_Report.pdf'), findsWidgets);

      // Close dialog
      final closeBtn = find.byKey(const Key('action_preview_dialog_close_btn'));
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();

      // Dialog is dismissed
      expect(find.byType(ActionAttachmentPreviewDialog), findsNothing);
    });

    testWidgets('7. Closed action immutability: Preview and Download remain accessible while delete is hidden', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final closedAction = testAction.copyWith(
        status: 'Closed',
        percentComplete: 100,
        closeDate: '01 Oct 2026',
      );

      await tester.pumpWidget(
        buildTestableWidget(
          ActionDetailsScreen(
            action: closedAction,
            currentUserId: 'user-creator',
            isWorker: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Evidence tab
      await tester.tap(find.text('Evidence & Attachments').first);
      await tester.pumpAndSettle();

      // Preview button is visible
      expect(find.byKey(const Key('preview_attachment_Site_Audit_Report.pdf_btn')), findsOneWidget);
      // Download button is visible
      expect(find.byKey(const Key('download_attachment_Site_Audit_Report.pdf_btn')), findsOneWidget);
      // Remove button is strictly hidden on closed actions
      expect(find.byKey(const Key('remove_attachment_Site_Audit_Report.pdf_btn')), findsNothing);
    });
  });
}
