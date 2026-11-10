import 'dart:convert';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:action_flow/services/app_file_picker_service.dart';
import 'package:action_flow/widgets/document_preview/action_attachment_preview_dialog.dart';
import 'package:action_flow/widgets/document_preview/pdf_view.dart';
import 'package:excel_plus/excel_plus.dart' hide Border;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testAction = ActionRecord(
    id: 'act-uuid-1027',
    actionNumber: 'ACT-1027',
    organizationId: Organization.sobhaId,
    subject: 'Safety Audit Quarterly Review',
    actionRequired: 'Verify PPE inspections and update risk register',
    priority: 'High',
    status: 'In Progress',
    percentComplete: 45,
    department: 'Safety',
    division: 'Operations',
    site: 'Site Alpha',
    dateRaised: '2026-09-20',
    targetDate: '2026-10-30',
    createdById: 'user-manager-001',
    assignedTo: 'John Staff',
    assignedToId: 'user-staff-001',
    attachments: [
      'ActionFlow_Manager_Report_2026-09-23T19-25-52.xlsx',
      'Safety_Protocol_V2.pdf',
      'Site_Inspection_Hazard.png',
      'Audit_Notes.txt',
      'Vendor_Agreement.docx',
    ],
  );

  Uint8List buildSampleExcelBytes() {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    excel.rename(defaultSheet, 'Summary');

    final summarySheet = excel['Summary'];
    summarySheet.appendRow([
      TextCellValue('Action ID'),
      TextCellValue('Title'),
      TextCellValue('Status'),
      TextCellValue('Progress %'),
    ]);
    summarySheet.appendRow([
      TextCellValue('ACT-1027'),
      TextCellValue('Safety Audit Quarterly Review'),
      TextCellValue('In Progress'),
      IntCellValue(45),
    ]);

    // Add a second sheet to test sheet tabs
    final auditSheet = excel['Audit Evidence'];
    auditSheet.appendRow([
      TextCellValue('Checklist Item'),
      TextCellValue('Result'),
      TextCellValue('Auditor'),
    ]);
    auditSheet.appendRow([
      TextCellValue('Fire Extinguishers Charged'),
      TextCellValue('Compliant'),
      TextCellValue('Auditor Jane'),
    ]);

    return Uint8List.fromList(excel.save()!);
  }

  group('Document Preview and Download Acceptance Tests', () {
    testWidgets('1. XLSX Preview: Decodes valid Excel workbook and renders interactive table with sheet chips', (tester) async {
      final excelBytes = buildSampleExcelBytes();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionAttachmentPreviewDialog(
              action: testAction,
              fileName: 'ActionFlow_Manager_Report_2026-09-23T19-25-52.xlsx',
              currentUserId: 'user-manager-001',
              isWorker: false,
              initialBytes: excelBytes,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Excel container and table
      expect(find.byKey(const Key('action_preview_excel_container')), findsOneWidget);
      expect(find.byKey(const Key('action_preview_excel_table')), findsOneWidget);

      // Verify both sheet chips exist
      expect(find.byKey(const Key('excel_sheet_chip_Summary')), findsOneWidget);
      expect(find.byKey(const Key('excel_sheet_chip_Audit Evidence')), findsOneWidget);

      // Verify cell content on default sheet
      expect(find.text('ACT-1027'), findsOneWidget);
      expect(find.text('Safety Audit Quarterly Review'), findsWidgets);
      expect(find.text('In Progress'), findsOneWidget);

      // Switch to second sheet
      await tester.tap(find.byKey(const Key('excel_sheet_chip_Audit Evidence')));
      await tester.pumpAndSettle();

      // Verify content of second sheet
      expect(find.text('Fire Extinguishers Charged'), findsOneWidget);
      expect(find.text('Compliant'), findsOneWidget);
      expect(find.text('Auditor Jane'), findsOneWidget);

      // Verify Download button is present and accessible
      expect(find.byKey(const Key('action_preview_dialog_download_btn')), findsOneWidget);
    });

    testWidgets('2. XLSX Fallback: Corrupt or non-OOXML bytes gracefully falls back to Office card with download button', (tester) async {
      final invalidBytes = Uint8List.fromList(utf8.encode('Not a valid excel binary file'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionAttachmentPreviewDialog(
              action: testAction,
              fileName: 'Corrupted_Spreadsheet.xlsx',
              currentUserId: 'user-manager-001',
              isWorker: false,
              initialBytes: invalidBytes,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('In-App Preview Unavailable'), findsOneWidget);
      expect(find.textContaining('In-app preview is not supported for .XLSX files'), findsOneWidget);
      expect(find.textContaining('Download'), findsWidgets);
    });

    testWidgets('3. Word Preview (.docx): Renders clean Office notice with download button', (tester) async {
      final wordBytes = Uint8List.fromList(utf8.encode('Word document bytes'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionAttachmentPreviewDialog(
              action: testAction,
              fileName: 'Vendor_Agreement.docx',
              currentUserId: 'user-manager-001',
              isWorker: false,
              initialBytes: wordBytes,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('In-App Preview Unavailable'), findsOneWidget);
      expect(find.textContaining('In-app preview is not supported for .DOCX files'), findsOneWidget);
      expect(find.byKey(const Key('action_preview_dialog_download_btn')), findsOneWidget);
    });

    testWidgets('4. PDF Preview (.pdf): Renders PdfViewWidget', (tester) async {
      final pdfBytes = Uint8List.fromList(utf8.encode('%PDF-1.4 sample content'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionAttachmentPreviewDialog(
              action: testAction,
              fileName: 'Safety_Protocol_V2.pdf',
              currentUserId: 'user-manager-001',
              isWorker: false,
              initialBytes: pdfBytes,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PdfViewWidget), findsOneWidget);
      expect(find.text('Safety_Protocol_V2.pdf'), findsWidgets);
    });

    testWidgets('5. Image Preview (.png): Renders InteractiveViewer with image', (tester) async {
      // 1x1 transparent PNG bytes
      final pngBytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
        0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionAttachmentPreviewDialog(
              action: testAction,
              fileName: 'Site_Inspection_Hazard.png',
              currentUserId: 'user-manager-001',
              isWorker: false,
              initialBytes: pngBytes,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('6. Text/CSV Preview: Renders selectable monospace text', (tester) async {
      const text = 'Column1,Column2,Column3\nVal1,Val2,Val3\nRow2A,Row2B,Row2C';
      final textBytes = Uint8List.fromList(utf8.encode(text));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionAttachmentPreviewDialog(
              action: testAction,
              fileName: 'Audit_Notes.txt',
              currentUserId: 'user-manager-001',
              isWorker: false,
              initialBytes: textBytes,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.text(text), findsOneWidget);
    });

    testWidgets('7. Download action invokes AppFilePicker.saveFile preserving filename, extension and bytes', (tester) async {
      String? savedFileName;
      Uint8List? savedBytes;

      AppFilePicker.saveTestOverride = ({required String fileName, required Uint8List bytes, String mimeType = 'application/octet-stream'}) async {
        savedFileName = fileName;
        savedBytes = bytes;
        return true;
      };

      final result = await ActionService.instance.downloadActionAttachment(
        action: testAction,
        fileName: 'ActionFlow_Manager_Report_2026-09-23T19-25-52.xlsx',
        userId: 'user-manager-001',
        isManager: true,
      );

      expect(result.success, isTrue);
      expect(savedFileName, equals('ActionFlow_Manager_Report_2026-09-23T19-25-52.xlsx'));
      expect(savedBytes, isNotNull);
      expect(savedBytes!.isNotEmpty, isTrue);

      AppFilePicker.saveTestOverride = null;
    });

    test('8. Candidate paths include canonical, org-scoped, reports, and relative paths', () {
      final candidates = ActionService.getAttachmentCandidatePaths(
        action: testAction,
        fileName: 'ActionFlow_Manager_Report_2026-09-23T19-25-52.xlsx',
      );

      expect(candidates, contains('${Organization.sobhaId}/actions/act-uuid-1027/ActionFlow_Manager_Report_2026-09-23T19-25-52.xlsx'));
      expect(candidates, contains('${Organization.sobhaId}/actions/ACT-1027/ActionFlow_Manager_Report_2026-09-23T19-25-52.xlsx'));
      expect(candidates, contains('actions/act-uuid-1027/ActionFlow_Manager_Report_2026-09-23T19-25-52.xlsx'));
      expect(candidates, contains('actions/ACT-1027/ActionFlow_Manager_Report_2026-09-23T19-25-52.xlsx'));
      expect(candidates, contains('${Organization.sobhaId}/reports/ActionFlow_Manager_Report_2026-09-23T19-25-52.xlsx'));
      expect(candidates, contains('reports/ActionFlow_Manager_Report_2026-09-23T19-25-52.xlsx'));
      expect(candidates, contains('ActionFlow_Manager_Report_2026-09-23T19-25-52.xlsx'));
    });

    test('9. Candidate paths handle pre-formatted relative paths cleanly', () {
      final candidates = ActionService.getAttachmentCandidatePaths(
        action: testAction,
        fileName: 'reports/ActionFlow_Manager_Report_2026-09-23T19-25-52.xlsx',
      );

      expect(candidates.first, contains('ActionFlow_Manager_Report_2026-09-23T19-25-52.xlsx'));
      expect(candidates, contains('${Organization.sobhaId}/reports/ActionFlow_Manager_Report_2026-09-23T19-25-52.xlsx'));
      expect(candidates, contains('reports/ActionFlow_Manager_Report_2026-09-23T19-25-52.xlsx'));
    });

    test('10. Storage RLS vs 404 discrimination: isStorageAccessDenied correctly identifies 403 Forbidden', () {
      // 403 StorageException
      final rlsException = StorageException('new row violates row-level security policy', statusCode: '403');
      expect(ActionService.isStorageAccessDenied(rlsException), isTrue);

      // Permission error string
      expect(ActionService.isStorageAccessDenied('Storage permission denied by tenant RLS policy'), isTrue);
      expect(ActionService.isStorageAccessDenied('403 Forbidden: Access Denied'), isTrue);

      // 404 Not Found error
      final notFoundException = StorageException('Object not found', statusCode: '404');
      expect(ActionService.isStorageAccessDenied(notFoundException), isFalse);
      expect(ActionService.isStorageAccessDenied('Object does not exist'), isFalse);
    });

    test('11. Security & Authorization: Unauthorized user is rejected before fetching bytes', () async {
      final res = await ActionService.instance.getActionAttachmentBytes(
        action: testAction,
        fileName: 'ActionFlow_Manager_Report_2026-09-23T19-25-52.xlsx',
        userId: 'unauthorized-stranger-id',
        isManager: false,
      );

      expect(res.success, isFalse);
      expect(res.bytes, isNull);
      expect(res.error, contains('Permission denied'));
    });

    test('12. Security & Authorization: Authorized staff assignee has full access', () async {
      final res = await ActionService.instance.getActionAttachmentBytes(
        action: testAction,
        fileName: 'ActionFlow_Manager_Report_2026-09-23T19-25-52.xlsx',
        userId: 'user-staff-001',
        isManager: false,
      );

      expect(res.success, isTrue);
      expect(res.bytes, isNotNull);
      expect(res.error, isNull);
    });
  });
}
