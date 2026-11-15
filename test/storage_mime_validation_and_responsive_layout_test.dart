import 'dart:convert';
import 'package:action_flow/features/requests/widgets/request_filter_bar.dart';
import 'package:action_flow/services/document_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DocumentService — MIME Resolution and Pre-Upload Validation (SEC-03)', () {
    test('resolveMimeType resolves standard document and image extensions accurately', () {
      expect(DocumentService.resolveMimeType('contract.pdf'), equals('application/pdf'));
      expect(DocumentService.resolveMimeType('photo.png'), equals('image/png'));
      expect(DocumentService.resolveMimeType('photo.jpg'), equals('image/jpeg'));
      expect(DocumentService.resolveMimeType('photo.jpeg'), equals('image/jpeg'));
      expect(DocumentService.resolveMimeType('diagram.webp'), equals('image/webp'));
      expect(DocumentService.resolveMimeType('doc1.doc'), equals('application/msword'));
      expect(
        DocumentService.resolveMimeType('doc2.docx'),
        equals('application/vnd.openxmlformats-officedocument.wordprocessingml.document'),
      );
      expect(DocumentService.resolveMimeType('sheet1.xls'), equals('application/vnd.ms-excel'));
      expect(
        DocumentService.resolveMimeType('sheet2.xlsx'),
        equals('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
      );
      expect(DocumentService.resolveMimeType('data.csv'), equals('text/csv'));
      expect(DocumentService.resolveMimeType('notes.txt'), equals('text/plain'));
    });

    test('resolveMimeType falls back safely to application/octet-stream for unknown/extensionless files', () {
      expect(DocumentService.resolveMimeType('unknownfile'), equals('application/octet-stream'));
      expect(DocumentService.resolveMimeType('archive.bin'), equals('application/octet-stream'));
      expect(DocumentService.resolveMimeType('script.exe'), equals('application/octet-stream'));
    });

    test('validateFile enforces 25MB ceiling and whitelist correctly', () {
      // Valid cases
      expect(
        DocumentService.validateFile(
          fileName: 'invoice.pdf',
          fileSize: 1024,
          fileBytes: [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x35],
        ),
        isNull,
      );
      expect(
        DocumentService.validateFile(
          fileName: 'photo.png',
          fileSize: 25 * 1024 * 1024, // Exactly 25 MB
          fileBytes: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
        ),
        isNull,
      );

      // Rejects empty filename
      expect(DocumentService.validateFile(fileName: '   ', fileSize: 500), contains('cannot be empty'));

      // Rejects missing or invalid extension
      expect(DocumentService.validateFile(fileName: 'noextension', fileSize: 500), contains('valid extension'));

      // Rejects disallowed extensions
      expect(DocumentService.validateFile(fileName: 'payload.exe', fileSize: 500), contains('Unsupported file format'));
      expect(DocumentService.validateFile(fileName: 'hack.sh', fileSize: 500), contains('Unsupported file format'));
      expect(DocumentService.validateFile(fileName: 'script.js', fileSize: 500), contains('Unsupported file format'));

      // Rejects 0 or negative size
      expect(DocumentService.validateFile(fileName: 'zero.pdf', fileSize: 0), contains('cannot be empty'));

      // Rejects exceeding 25MB ceiling
      expect(
        DocumentService.validateFile(
          fileName: 'huge.pdf',
          fileSize: (25 * 1024 * 1024) + 1,
        ),
        contains('exceeds the maximum allowed limit of 25 MB'),
      );
    });

    test('validateFile inspects magic-bytes and rejects disguised executables and corrupt content', () {
      // Disguised Windows PE Executable (MZ header renamed to .pdf)
      final disguisedExeBytes = [0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00];
      final exeResult = DocumentService.validateFile(
        fileName: 'safety_report.pdf',
        fileSize: disguisedExeBytes.length,
        fileBytes: disguisedExeBytes,
      );
      expect(exeResult, contains('Security Violation: Executable file disguised'));

      // Disguised Linux ELF Binary (ELF header renamed to .png)
      final disguisedElfBytes = [0x7F, 0x45, 0x4C, 0x46, 0x02, 0x01, 0x01, 0x00];
      final elfResult = DocumentService.validateFile(
        fileName: 'badge_photo.png',
        fileSize: disguisedElfBytes.length,
        fileBytes: disguisedElfBytes,
      );
      expect(elfResult, contains('Security Violation: Executable ELF binary disguised'));

      // Mismatched / corrupt PDF signature (plain text in .pdf)
      final corruptPdfBytes = [0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x20, 0x57, 0x6F];
      final corruptResult = DocumentService.validateFile(
        fileName: 'corrupt.pdf',
        fileSize: corruptPdfBytes.length,
        fileBytes: corruptPdfBytes,
      );
      expect(corruptResult, contains('Content does not match expected PDF signature'));

      // Valid JPEG header
      final validJpgBytes = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10];
      expect(
        DocumentService.validateFile(
          fileName: 'site_photo.jpg',
          fileSize: validJpgBytes.length,
          fileBytes: validJpgBytes,
        ),
        isNull,
      );

      // Generic ZIP archive without OpenXML markers renamed to .xlsx or .docx must be REJECTED
      final genericZipBytes = [0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x08, 0x00, 0x00, 0x00];
      final genericDocxResult = DocumentService.validateFile(
        fileName: 'report.docx',
        fileSize: genericZipBytes.length,
        fileBytes: genericZipBytes,
      );
      expect(genericDocxResult, contains('generic ZIP archive, not a valid Word'));

      final genericXlsxResult = DocumentService.validateFile(
        fileName: 'audit.xlsx',
        fileSize: genericZipBytes.length,
        fileBytes: genericZipBytes,
      );
      expect(genericXlsxResult, contains('generic ZIP archive, not a valid Excel'));

      // Genuine DOCX with OpenXML markers ('PK\x03\x04' + '[Content_Types].xml' + 'word/')
      final genuineDocxBytes = <int>[
        0x50, 0x4B, 0x03, 0x04,
        ...utf8.encode('[Content_Types].xml'),
        ...utf8.encode('word/document.xml'),
      ];
      expect(
        DocumentService.validateFile(
          fileName: 'hsse_policy.docx',
          fileSize: genuineDocxBytes.length,
          fileBytes: genuineDocxBytes,
        ),
        isNull,
      );

      // Genuine XLSX with OpenXML markers ('PK\x03\x04' + 'xl/workbook.xml')
      final genuineXlsxBytes = <int>[
        0x50, 0x4B, 0x03, 0x04,
        ...utf8.encode('xl/workbook.xml'),
      ];
      expect(
        DocumentService.validateFile(
          fileName: 'incident_metrics.xlsx',
          fileSize: genuineXlsxBytes.length,
          fileBytes: genuineXlsxBytes,
        ),
        isNull,
      );

      // WebP signature validation: RIFF container with WEBP identifier
      final validWebpBytes = [
        0x52, 0x49, 0x46, 0x46, // RIFF
        0x20, 0x00, 0x00, 0x00, // length
        0x57, 0x45, 0x42, 0x50, // WEBP
      ];
      expect(
        DocumentService.validateFile(
          fileName: 'hazard_preview.webp',
          fileSize: validWebpBytes.length,
          fileBytes: validWebpBytes,
        ),
        isNull,
      );

      final invalidWebpBytes = [
        0x52, 0x49, 0x46, 0x46, // RIFF
        0x20, 0x00, 0x00, 0x00,
        0x41, 0x56, 0x49, 0x20, // AVI (not WEBP)
      ];
      expect(
        DocumentService.validateFile(
          fileName: 'fake.webp',
          fileSize: invalidWebpBytes.length,
          fileBytes: invalidWebpBytes,
        ),
        contains('RIFF container does not contain valid WEBP header'),
      );

      // Plain text and CSV validation
      final validCsvBytes = utf8.encode('ActionID,Subject,Status\nACT-1001,Inspection,Open\n');
      expect(
        DocumentService.validateFile(
          fileName: 'actions.csv',
          fileSize: validCsvBytes.length,
          fileBytes: validCsvBytes,
        ),
        isNull,
      );

      final binaryInCsvBytes = [0x50, 0x4B, 0x03, 0x04, 0x00, 0x00]; // ZIP header disguised as CSV
      expect(
        DocumentService.validateFile(
          fileName: 'data.csv',
          fileSize: binaryInCsvBytes.length,
          fileBytes: binaryInCsvBytes,
        ),
        contains('Binary file disguised as plain text / CSV is not permitted'),
      );

      final nullByteInTxtBytes = [0x41, 0x42, 0x00, 0x43]; // Contains binary null byte
      expect(
        DocumentService.validateFile(
          fileName: 'notes.txt',
          fileSize: nullByteInTxtBytes.length,
          fileBytes: nullByteInTxtBytes,
        ),
        contains('Binary control characters detected in plain text / CSV file'),
      );
    });
  });

  group('Responsive Layout Verification (320px–1280px)', () {
    testWidgets('RequestFilterBar renders cleanly at narrow mobile 360px without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool resetTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RequestFilterBar(
              searchQuery: 'leak',
              onSearchChanged: (_) {},
              selectedType: 'All Types',
              onTypeChanged: (_) {},
              selectedStatus: 'All Statuses',
              onStatusChanged: (_) {},
              selectedPriority: 'High',
              onPriorityChanged: (_) {},
              selectedSort: 'Newest First',
              onSortChanged: (_) {},
              onResetFilters: () {
                resetTapped = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ensure no exceptions or RenderFlex overflows occurred
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('request_search_field')), findsOneWidget);
      expect(find.byKey(const Key('request_reset_filters_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('request_reset_filters_button')));
      await tester.pump();
      expect(resetTapped, isTrue);
    });

    testWidgets('RequestFilterBar renders cleanly at desktop 1280px without overflow', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool resetTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RequestFilterBar(
              searchQuery: 'safety',
              onSearchChanged: (_) {},
              selectedType: 'All Types',
              onTypeChanged: (_) {},
              selectedStatus: 'All Statuses',
              onStatusChanged: (_) {},
              selectedPriority: 'Urgent',
              onPriorityChanged: (_) {},
              selectedSort: 'Newest First',
              onSortChanged: (_) {},
              onResetFilters: () {
                resetTapped = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('request_search_field')), findsOneWidget);
      expect(find.byKey(const Key('request_reset_filters_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('request_reset_filters_button')));
      await tester.pump();
      expect(resetTapped, isTrue);
    });
  });
}
