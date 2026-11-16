import 'dart:convert';
import 'package:action_flow/features/requests/widgets/request_filter_bar.dart';
import 'package:action_flow/services/document_service.dart';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _buildZip(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return ZipEncoder().encode(archive)!;
}

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
      expect(DocumentService.resolveMimeType('contract.rtf'), equals('application/rtf'));
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

      // 1. Genuine DOCX package (contains [Content_Types].xml with WordprocessingML, word/document.xml, and _rels/.rels)
      final genuineDocxBytes = _buildZip({
        '[Content_Types].xml':
            '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
        'word/document.xml': '<?xml version="1.0" encoding="UTF-8"?><w:document></w:document>',
        '_rels/.rels':
            '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
      });
      expect(
        DocumentService.validateFile(
          fileName: 'hsse_policy.docx',
          fileSize: genuineDocxBytes.length,
          fileBytes: genuineDocxBytes,
        ),
        isNull,
        reason: 'Genuine DOCX package must be accepted.',
      );

      // 2. Genuine XLSX package (contains [Content_Types].xml with SpreadsheetML, xl/workbook.xml, and _rels/.rels)
      final genuineXlsxBytes = _buildZip({
        '[Content_Types].xml':
            '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/></Types>',
        'xl/workbook.xml': '<?xml version="1.0" encoding="UTF-8"?><workbook></workbook>',
        '_rels/.rels':
            '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
      });
      expect(
        DocumentService.validateFile(
          fileName: 'incident_metrics.xlsx',
          fileSize: genuineXlsxBytes.length,
          fileBytes: genuineXlsxBytes,
        ),
        isNull,
        reason: 'Genuine XLSX package must be accepted.',
      );

      // 3. DOCX renamed as XLSX (contains word/ but no xl/)
      final docxRenamedAsXlsx = DocumentService.validateFile(
        fileName: 'audit_report.xlsx',
        fileSize: genuineDocxBytes.length,
        fileBytes: genuineDocxBytes,
      );
      expect(
        docxRenamedAsXlsx,
        contains('Content is a Word document (.docx) renamed as an Excel (.xlsx) spreadsheet.'),
      );

      // 4. XLSX renamed as DOCX (contains xl/ but no word/)
      final xlsxRenamedAsDocx = DocumentService.validateFile(
        fileName: 'summary.docx',
        fileSize: genuineXlsxBytes.length,
        fileBytes: genuineXlsxBytes,
      );
      expect(
        xlsxRenamedAsDocx,
        contains('Content is an Excel spreadsheet (.xlsx) renamed as a Word (.docx) document.'),
      );

      // 5. Generic ZIP renamed as DOCX (valid ZIP but no word/ and no [Content_Types].xml)
      final genericZipBytes = _buildZip({'notes.txt': 'Standard uncompressed notes file'});
      final genericDocxResult = DocumentService.validateFile(
        fileName: 'report.docx',
        fileSize: genericZipBytes.length,
        fileBytes: genericZipBytes,
      );
      expect(genericDocxResult, contains('generic ZIP archive, not a valid Word (.docx) document'));

      // 5b. Generic ZIP containing [Content_Types].xml alone without word/ must NOT be accepted as DOCX
      final zipWithContentTypesOnly = _buildZip({
        '[Content_Types].xml': '<?xml version="1.0"?><Types></Types>',
        'generic.txt': 'hello',
      });
      final contentTypesOnlyDocx = DocumentService.validateFile(
        fileName: 'fake.docx',
        fileSize: zipWithContentTypesOnly.length,
        fileBytes: zipWithContentTypesOnly,
      );
      expect(contentTypesOnlyDocx, contains('not a valid Word (.docx) document'));

      // 6. Generic ZIP renamed as XLSX (valid ZIP but no xl/)
      final genericXlsxResult = DocumentService.validateFile(
        fileName: 'audit.xlsx',
        fileSize: genericZipBytes.length,
        fileBytes: genericZipBytes,
      );
      expect(genericXlsxResult, contains('generic ZIP archive, not a valid Excel (.xlsx) spreadsheet'));

      // 6b. Generic ZIP containing [Content_Types].xml alone without xl/ must NOT be accepted as XLSX
      final contentTypesOnlyXlsx = DocumentService.validateFile(
        fileName: 'fake.xlsx',
        fileSize: zipWithContentTypesOnly.length,
        fileBytes: zipWithContentTypesOnly,
      );
      expect(contentTypesOnlyXlsx, contains('not a valid Excel (.xlsx) spreadsheet'));

      // 7. Malformed ZIP (starts with PK\x03\x04 but truncated/corrupt)
      final malformedZipBytes = [0x50, 0x4B, 0x03, 0x04, 0xFF, 0xFE, 0x00, 0x00];
      final malformedDocx = DocumentService.validateFile(
        fileName: 'corrupt.docx',
        fileSize: malformedZipBytes.length,
        fileBytes: malformedZipBytes,
      );
      expect(malformedDocx, contains('Corrupt or malformed ZIP container for .docx file.'));

      final malformedXlsx = DocumentService.validateFile(
        fileName: 'corrupt.xlsx',
        fileSize: malformedZipBytes.length,
        fileBytes: malformedZipBytes,
      );
      expect(malformedXlsx, contains('Corrupt or malformed ZIP container for .xlsx file.'));

      // 8. Executable renamed as an Office document
      final exeAsDocx = DocumentService.validateFile(
        fileName: 'payload.docx',
        fileSize: disguisedExeBytes.length,
        fileBytes: disguisedExeBytes,
      );
      expect(exeAsDocx, contains('Security Violation: Executable file disguised as .docx is not permitted.'));

      final exeAsXlsx = DocumentService.validateFile(
        fileName: 'payload.xlsx',
        fileSize: disguisedExeBytes.length,
        fileBytes: disguisedExeBytes,
      );
      expect(exeAsXlsx, contains('Security Violation: Executable file disguised as .xlsx is not permitted.'));

      // 9. Legacy Office: Distinguishing DOC from XLS, and Strict RTF Separation
      // Genuine Word .doc (OLE CFB with WordDocument stream)
      final genuineDocBytes = <int>[
        0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1,
        ...utf8.encode('WordDocument'),
      ];
      expect(
        DocumentService.validateFile(
          fileName: 'legacy_charter.doc',
          fileSize: genuineDocBytes.length,
          fileBytes: genuineDocBytes,
        ),
        isNull,
      );

      // RTF disguised under .doc MUST be rejected with explicit redirect error
      final genuineRtfBytes = utf8.encode(r'{\rtf1\ansi\deff0 Test RTF Word Document}');
      final rtfUnderDocResult = DocumentService.validateFile(
        fileName: 'legacy_procedure.doc',
        fileSize: genuineRtfBytes.length,
        fileBytes: genuineRtfBytes,
      );
      expect(
        rtfUnderDocResult,
        contains('RTF content disguised as legacy Word (.doc) document is not permitted. Please use the .rtf extension.'),
      );

      // Genuine RTF under .rtf MUST be accepted
      expect(
        DocumentService.validateFile(
          fileName: 'agreement.rtf',
          fileSize: genuineRtfBytes.length,
          fileBytes: genuineRtfBytes,
        ),
        isNull,
      );

      // Non-RTF disguised under .rtf MUST be rejected
      final fakeRtfResult = DocumentService.validateFile(
        fileName: 'fake.rtf',
        fileSize: genuineDocBytes.length,
        fileBytes: genuineDocBytes,
      );
      expect(fakeRtfResult, contains('Content does not match expected RTF signature'));

      // Genuine Excel .xls (OLE CFB with Workbook stream)
      final genuineXlsBytes = <int>[
        0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1,
        ...utf8.encode('Workbook'),
      ];
      expect(
        DocumentService.validateFile(
          fileName: 'legacy_register.xls',
          fileSize: genuineXlsBytes.length,
          fileBytes: genuineXlsBytes,
        ),
        isNull,
      );

      // Genuine Excel .xls (BIFF8 BOF record)
      final genuineBiffBytes = <int>[0x09, 0x08, 0x08, 0x00, 0x00, 0x05, 0x05, 0x20];
      expect(
        DocumentService.validateFile(
          fileName: 'legacy_biff.xls',
          fileSize: genuineBiffBytes.length,
          fileBytes: genuineBiffBytes,
        ),
        isNull,
      );

      // Word .doc renamed as Excel .xls (OLE CFB contains WordDocument but no Workbook)
      final docRenamedAsXls = DocumentService.validateFile(
        fileName: 'mislabeled.xls',
        fileSize: genuineDocBytes.length,
        fileBytes: genuineDocBytes,
      );
      expect(
        docRenamedAsXls,
        contains('Content is a Word document (.doc) renamed as an Excel (.xls) spreadsheet.'),
      );

      // Excel .xls renamed as Word .doc (OLE CFB contains Workbook but no WordDocument)
      final xlsRenamedAsDoc = DocumentService.validateFile(
        fileName: 'mislabeled.doc',
        fileSize: genuineXlsBytes.length,
        fileBytes: genuineXlsBytes,
      );
      expect(
        xlsRenamedAsDoc,
        contains('Content is an Excel spreadsheet (.xls) renamed as a Word (.doc) document.'),
      );

      // Generic ZIP disguised as legacy .doc or .xls
      final zipAsDoc = DocumentService.validateFile(
        fileName: 'archive.doc',
        fileSize: genericZipBytes.length,
        fileBytes: genericZipBytes,
      );
      expect(zipAsDoc, contains('ZIP archive or OpenXML file disguised as legacy Word (.doc) document'));

      final zipAsXls = DocumentService.validateFile(
        fileName: 'archive.xls',
        fileSize: genericZipBytes.length,
        fileBytes: genericZipBytes,
      );
      expect(zipAsXls, contains('ZIP archive or OpenXML file disguised as legacy Excel (.xls) spreadsheet'));

      // 10. Advanced ZIP Archive Security (ZIP Bomb, Path Traversal, Entry Limits)
      // a) ZIP Bomb: Excessive entries (> 1000 entries)
      final excessiveEntriesArchive = Archive();
      excessiveEntriesArchive.addFile(ArchiveFile('[Content_Types].xml', 10, utf8.encode('<Types/>')));
      excessiveEntriesArchive.addFile(ArchiveFile('word/document.xml', 10, utf8.encode('<doc/>')));
      for (int i = 0; i < 1005; i++) {
        excessiveEntriesArchive.addFile(ArchiveFile('word/dummy_$i.xml', 1, const [0x20]));
      }
      final excessiveZipBytes = ZipEncoder().encode(excessiveEntriesArchive)!;
      final excessiveResult = DocumentService.validateFile(
        fileName: 'bomb.docx',
        fileSize: excessiveZipBytes.length,
        fileBytes: excessiveZipBytes,
      );
      expect(excessiveResult, contains('possible zip bomb'));

      // b) ZIP Bomb: Single entry exceeding 50 MB
      final hugeFileEntry = ArchiveFile.bytes('word/huge.xml', const [0x00]);
      hugeFileEntry.size = 60 * 1024 * 1024; // 60 MB uncompressed size
      final hugeArchive = Archive();
      hugeArchive.addFile(ArchiveFile('[Content_Types].xml', 10, utf8.encode('<Types/>')));
      hugeArchive.addFile(ArchiveFile('word/document.xml', 10, utf8.encode('<doc/>')));
      hugeArchive.addFile(hugeFileEntry);
      final hugeZipBytes = ZipEncoder().encode(hugeArchive)!;
      final hugeResult = DocumentService.validateFile(
        fileName: 'huge_entry.docx',
        fileSize: hugeZipBytes.length,
        fileBytes: hugeZipBytes,
      );
      expect(hugeResult, contains('uncompressed size exceeds safety limit'));

      // c) ZIP Bomb: Total decompressed size exceeding 100 MB
      final totalBombArchive = Archive();
      totalBombArchive.addFile(ArchiveFile('[Content_Types].xml', 10, utf8.encode('<Types/>')));
      totalBombArchive.addFile(ArchiveFile('word/document.xml', 10, utf8.encode('<doc/>')));
      for (int i = 0; i < 3; i++) {
        final f = ArchiveFile.bytes('word/part_$i.xml', const [0x00]);
        f.size = 40 * 1024 * 1024; // 3 * 40MB = 120 MB > 100 MB
        totalBombArchive.addFile(f);
      }
      final totalBombZipBytes = ZipEncoder().encode(totalBombArchive)!;
      final totalBombResult = DocumentService.validateFile(
        fileName: 'total_bomb.docx',
        fileSize: totalBombZipBytes.length,
        fileBytes: totalBombZipBytes,
      );
      expect(totalBombResult, contains('total uncompressed size exceeds safety limit'));

      // d) Path Traversal: relative sequence in entry name (../../etc/passwd)
      final relativeTraversalArchive = Archive();
      relativeTraversalArchive.addFile(ArchiveFile('[Content_Types].xml', 10, utf8.encode('<Types/>')));
      relativeTraversalArchive.addFile(ArchiveFile('word/document.xml', 10, utf8.encode('<doc/>')));
      relativeTraversalArchive.addFile(ArchiveFile('../../etc/passwd', 10, utf8.encode('root:x:0:0')));
      final relTraversalZipBytes = ZipEncoder().encode(relativeTraversalArchive)!;
      final relTraversalResult = DocumentService.validateFile(
        fileName: 'malicious_rel.docx',
        fileSize: relTraversalZipBytes.length,
        fileBytes: relTraversalZipBytes,
      );
      expect(relTraversalResult, contains('Path traversal sequence detected in ZIP entry'));

      // e) Path Traversal: absolute path in entry name (/root/exploit.sh)
      final absTraversalArchive = Archive();
      absTraversalArchive.addFile(ArchiveFile('[Content_Types].xml', 10, utf8.encode('<Types/>')));
      absTraversalArchive.addFile(ArchiveFile('word/document.xml', 10, utf8.encode('<doc/>')));
      absTraversalArchive.addFile(ArchiveFile('/root/exploit.sh', 10, utf8.encode('#!/bin/sh')));
      final absTraversalZipBytes = ZipEncoder().encode(absTraversalArchive)!;
      final absTraversalResult = DocumentService.validateFile(
        fileName: 'malicious_abs.docx',
        fileSize: absTraversalZipBytes.length,
        fileBytes: absTraversalZipBytes,
      );
      expect(absTraversalResult, contains('Path traversal sequence detected in ZIP entry'));

      // f) Content-Types XML verification: DOCX package containing spreadsheetml ContentType
      final xlsxContentInDocxArchive = _buildZip({
        '[Content_Types].xml': '<Types><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/></Types>',
        '_rels/.rels':
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
        'xl/workbook.xml': '<workbook/>',
      });
      final xlsxInDocxResult = DocumentService.validateFile(
        fileName: 'disguised.docx',
        fileSize: xlsxContentInDocxArchive.length,
        fileBytes: xlsxContentInDocxArchive,
      );
      expect(xlsxInDocxResult, contains('Content is an Excel spreadsheet (.xlsx) renamed as a Word (.docx) document.'));

      // g) Conflicting Word and Excel package structures
      final conflictingArchive = _buildZip({
        '[Content_Types].xml':
            '<Types><Override PartName="/word/doc.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/xl/sheet.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/></Types>',
        '_rels/.rels':
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
        'word/document.xml': '<w:document/>',
        'xl/workbook.xml': '<workbook/>',
      });
      final conflictResult = DocumentService.validateFile(
        fileName: 'conflict.docx',
        fileSize: conflictingArchive.length,
        fileBytes: conflictingArchive,
      );
      expect(conflictResult, contains('Archive contains conflicting Word and Excel package structures.'));

      // h) Corrupt Office package: corrupted [Content_Types].xml
      final corruptOfficeZip = _buildZip({
        '[Content_Types].xml': '',
        '_rels/.rels':
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
        'word/document.xml': '<w:document/>',
      });
      final corruptPackageResult = DocumentService.validateFile(
        fileName: 'corrupt.docx',
        fileSize: corruptOfficeZip.length,
        fileBytes: corruptOfficeZip,
      );
      expect(corruptPackageResult, contains('is empty or corrupt'));

      // i) ZIP Bomb Sample: [Content_Types].xml declared size forged small (200 bytes) but decompresses to > 512 KB
      final largeContentXml = '<?xml version="1.0"?><Types>' + ('<!-- padding -->' * 40000) + '</Types>';
      final largeBytes = utf8.encode(largeContentXml);
      final bombEntry = ArchiveFile.bytes('[Content_Types].xml', largeBytes);
      bombEntry.size = 200; // Forged declared size passes declared size check
      final bombArchive = Archive();
      bombArchive.addFile(bombEntry);
      bombArchive.addFile(ArchiveFile.bytes('_rels/.rels', utf8.encode('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')));
      bombArchive.addFile(ArchiveFile.bytes('word/document.xml', utf8.encode('<w:document/>')));
      final bombZipBytes = ZipEncoder().encode(bombArchive)!;
      final bombResult = DocumentService.validateFile(
        fileName: 'decompression_bomb.docx',
        fileSize: bombZipBytes.length,
        fileBytes: bombZipBytes,
      );
      expect(bombResult, contains('ZIP decompression limit exceeded during processing, possible zip bomb.'));

      // j) Specific document entry verification: DOCX missing word/document.xml
      final docxMissingDocXml = _buildZip({
        '[Content_Types].xml':
            '<?xml version="1.0"?><Types><Override PartName="/word/other.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
        'word/other.xml': '<other/>',
        '_rels/.rels':
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/other.xml"/></Relationships>',
      });
      final missingDocXmlResult = DocumentService.validateFile(
        fileName: 'missing_doc.docx',
        fileSize: docxMissingDocXml.length,
        fileBytes: docxMissingDocXml,
      );
      expect(missingDocXmlResult, contains('generic ZIP archive, not a valid Word (.docx) document'));

      // k) Specific workbook entry verification: XLSX missing xl/workbook.xml
      final xlsxMissingWbXml = _buildZip({
        '[Content_Types].xml':
            '<?xml version="1.0"?><Types><Override PartName="/xl/other.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/></Types>',
        'xl/other.xml': '<other/>',
        '_rels/.rels':
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/other.xml"/></Relationships>',
      });
      final missingWbXmlResult = DocumentService.validateFile(
        fileName: 'missing_wb.xlsx',
        fileSize: xlsxMissingWbXml.length,
        fileBytes: xlsxMissingWbXml,
      );
      expect(missingWbXmlResult, contains('generic ZIP archive, not a valid Excel (.xlsx) spreadsheet'));

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

  group('OpenXML Root Relationship & Package Integrity Tests (SEC-04)', () {
    // 1. Correct OPC namespace with default declaration: ACCEPT
    test('1. Correct OPC namespace with default declaration is accepted', () {
      final docxRel = _buildZip({
        '[Content_Types].xml':
            '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
        'word/document.xml': '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"/>',
        '_rels/.rels':
            '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
      });
      expect(
        DocumentService.validateFile(
          fileName: 'policy.docx',
          fileSize: docxRel.length,
          fileBytes: docxRel,
        ),
        isNull,
      );

      // Leading slash variant (/word/document.xml)
      final docxSlashRel = _buildZip({
        '[Content_Types].xml':
            '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
        'word/document.xml': '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"/>',
        '_rels/.rels':
            '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="/word/document.xml"/></Relationships>',
      });
      expect(
        DocumentService.validateFile(
          fileName: 'policy_slash.docx',
          fileSize: docxSlashRel.length,
          fileBytes: docxSlashRel,
        ),
        isNull,
      );
    });

    // 2. Correct OPC namespace with prefixed declaration: ACCEPT
    test('2. Correct OPC namespace with prefixed declaration (pkg:) is accepted', () {
      final docxPrefixed = _buildZip({
        '[Content_Types].xml':
            '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
        'word/document.xml': '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"/>',
        '_rels/.rels':
            '<?xml version="1.0" encoding="UTF-8"?><pkg:Relationships xmlns:pkg="http://schemas.openxmlformats.org/package/2006/relationships"><pkg:Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></pkg:Relationships>',
      });
      expect(
        DocumentService.validateFile(
          fileName: 'prefixed.docx',
          fileSize: docxPrefixed.length,
          fileBytes: docxPrefixed,
        ),
        isNull,
      );
    });

    // 3. Incorrect root namespace: REJECT
    test('3. Incorrect root namespace in _rels/.rels is rejected', () {
      final docxWrongNs = _buildZip({
        '[Content_Types].xml':
            '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
        'word/document.xml': '<w:document/>',
        '_rels/.rels':
            '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/other"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
      });
      final res = DocumentService.validateFile(
        fileName: 'wrong_ns.docx',
        fileSize: docxWrongNs.length,
        fileBytes: docxWrongNs,
      );
      expect(res, contains('root element has invalid or missing OPC namespace'));
    });

    // 4. Missing root namespace: REJECT
    test('4. Missing root namespace in _rels/.rels is rejected', () {
      final docxNoNs = _buildZip({
        '[Content_Types].xml':
            '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
        'word/document.xml': '<w:document/>',
        '_rels/.rels':
            '<?xml version="1.0" encoding="UTF-8"?><Relationships><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
      });
      final res = DocumentService.validateFile(
        fileName: 'no_ns.docx',
        fileSize: docxNoNs.length,
        fileBytes: docxNoNs,
      );
      expect(res, contains('root element has invalid or missing OPC namespace'));
    });

    // 5. Incorrect child relationship namespace: REJECT
    test('5. Incorrect child relationship namespace is rejected', () {
      final docxWrongChildNs = _buildZip({
        '[Content_Types].xml':
            '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
        'word/document.xml': '<w:document/>',
        '_rels/.rels':
            '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><other:Relationship xmlns:other="http://schemas.openxmlformats.org/package/2006/other" Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
      });
      final res = DocumentService.validateFile(
        fileName: 'wrong_child_ns.docx',
        fileSize: docxWrongChildNs.length,
        fileBytes: docxWrongChildNs,
      );
      expect(res, contains('child relationship element has invalid namespace'));
    });

    // 6. Missing Id: REJECT
    test('6. Missing Id attribute on relationship is rejected', () {
      final docxNoId = _buildZip({
        '[Content_Types].xml':
            '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
        'word/document.xml': '<w:document/>',
        '_rels/.rels':
            '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
      });
      final res = DocumentService.validateFile(
        fileName: 'no_id.docx',
        fileSize: docxNoId.length,
        fileBytes: docxNoId,
      );
      expect(res, contains('missing or empty Id attribute'));
    });

    // 7. Empty Id: REJECT
    test('7. Empty or whitespace-only Id attribute is rejected', () {
      final docxEmptyId = _buildZip({
        '[Content_Types].xml':
            '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
        'word/document.xml': '<w:document/>',
        '_rels/.rels':
            '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="   " Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
      });
      final res = DocumentService.validateFile(
        fileName: 'empty_id.docx',
        fileSize: docxEmptyId.length,
        fileBytes: docxEmptyId,
      );
      expect(res, contains('missing or empty Id attribute'));
    });

    // 8. Duplicate Id: REJECT
    test('8. Duplicate Id values within _rels/.rels are rejected', () {
      final docxDupId = _buildZip({
        '[Content_Types].xml':
            '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
        'word/document.xml': '<w:document/>',
        'docProps/core.xml': '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"/>',
        '_rels/.rels':
            '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>',
      });
      final res = DocumentService.validateFile(
        fileName: 'dup_id.docx',
        fileSize: docxDupId.length,
        fileBytes: docxDupId,
      );
      expect(res, contains('duplicate relationship Id (rId1)'));
    });

    // 9. Distinct relationship IDs: ACCEPT
    test('9. Distinct relationship IDs are accepted', () {
      final docxDistinctIds = _buildZip({
        '[Content_Types].xml':
            '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/></Types>',
        'word/document.xml': '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"/>',
        'docProps/core.xml': '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"/>',
        '_rels/.rels':
            '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>',
      });
      expect(
        DocumentService.validateFile(
          fileName: 'distinct_ids.docx',
          fileSize: docxDistinctIds.length,
          fileBytes: docxDistinctIds,
        ),
        isNull,
      );
    });

    // 10. Valid DOCX with unrelated relationships: ACCEPT
    test('10. Valid DOCX with unrelated relationships (core, app, external hyperlink) is accepted', () {
      final docxWithMultipleRels = _buildZip({
        '[Content_Types].xml': '''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>''',
        'word/document.xml': '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"/>',
        'docProps/core.xml': '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"/>',
        'docProps/app.xml': '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"/>',
        '_rels/.rels': '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
  <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="https://actionflow.cc/faq?lang=en#section2" TargetMode="External"/>
</Relationships>''',
      });
      expect(
        DocumentService.validateFile(
          fileName: 'standard_office.docx',
          fileSize: docxWithMultipleRels.length,
          fileBytes: docxWithMultipleRels,
        ),
        isNull,
      );
    });

    // 11. Valid XLSX with unrelated relationships: ACCEPT
    test('11. Valid XLSX with unrelated relationships is accepted', () {
      final xlsxWithMultipleRels = _buildZip({
        '[Content_Types].xml': '''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>''',
        'xl/workbook.xml': '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"/>',
        'docProps/core.xml': '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"/>',
        'docProps/app.xml': '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"/>',
        '_rels/.rels': '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>''',
      });
      expect(
        DocumentService.validateFile(
          fileName: 'metrics_full.xlsx',
          fileSize: xlsxWithMultipleRels.length,
          fileBytes: xlsxWithMultipleRels,
        ),
        isNull,
      );
    });

    // 12. Existing DOCX/XLSX compatibility and attack protections remain intact
    test('12. Existing DOCX/XLSX compatibility and attack protections remain intact', () {
      // 12a. Missing _rels/.rels
      final docxNoRels = _buildZip({
        '[Content_Types].xml':
            '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
        'word/document.xml': '<w:document/>',
      });
      expect(
        DocumentService.validateFile(
          fileName: 'norels.docx',
          fileSize: docxNoRels.length,
          fileBytes: docxNoRels,
        ),
        contains('missing required root relationships (_rels/.rels)'),
      );

      // 12b. Malformed relationship XML
      final brokenXmlDocx = _buildZip({
        '[Content_Types].xml':
            '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
        'word/document.xml': '<w:document/>',
        '_rels/.rels': '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><broken-element attr="unclosed',
      });
      expect(
        DocumentService.validateFile(
          fileName: 'broken.docx',
          fileSize: brokenXmlDocx.length,
          fileBytes: brokenXmlDocx,
        ),
        contains('_rels/.rels contains malformed or invalid XML'),
      );

      // 12c. DOCX relationship pointing to an incorrect target
      final badTargetDocx = _buildZip({
        '[Content_Types].xml':
            '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
        'word/document.xml': '<w:document/>',
        '_rels/.rels':
            '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/other.xml"/></Relationships>',
      });
      expect(
        DocumentService.validateFile(
          fileName: 'bad_target.docx',
          fileSize: badTargetDocx.length,
          fileBytes: badTargetDocx,
        ),
        contains('document relationship target does not point to word/document.xml'),
      );

      // 12d. XLSX relationship pointing to an incorrect target
      final badTargetXlsx = _buildZip({
        '[Content_Types].xml':
            '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/></Types>',
        'xl/workbook.xml': '<workbook/>',
        '_rels/.rels':
            '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/other.xml"/></Relationships>',
      });
      expect(
        DocumentService.validateFile(
          fileName: 'bad_target.xlsx',
          fileSize: badTargetXlsx.length,
          fileBytes: badTargetXlsx,
        ),
        contains('workbook relationship target does not point to xl/workbook.xml'),
      );

      // 12e. Path traversal in relationship targets
      final traversalDocx = _buildZip({
        '[Content_Types].xml':
            '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
        'word/document.xml': '<w:document/>',
        '_rels/.rels':
            '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="../word/document.xml"/></Relationships>',
      });
      expect(
        DocumentService.validateFile(
          fileName: 'traversal.docx',
          fileSize: traversalDocx.length,
          fileBytes: traversalDocx,
        ),
        contains('Path traversal sequence detected in relationship target'),
      );

      // 12f. External relationship target for main document
      final externalDocx = _buildZip({
        '[Content_Types].xml':
            '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
        'word/document.xml': '<w:document/>',
        '_rels/.rels':
            '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="http://evil.com/payload.xml" TargetMode="External"/></Relationships>',
      });
      expect(
        DocumentService.validateFile(
          fileName: 'external.docx',
          fileSize: externalDocx.length,
          fileBytes: externalDocx,
        ),
        contains('Primary officeDocument relationship cannot specify TargetMode="External"'),
      );

      // 12g. Duplicate or conflicting root primary relationships
      final duplicateDocx = _buildZip({
        '[Content_Types].xml':
            '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
        'word/document.xml': '<w:document/>',
        '_rels/.rels':
            '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document2.xml"/></Relationships>',
      });
      expect(
        DocumentService.validateFile(
          fileName: 'duplicate.docx',
          fileSize: duplicateDocx.length,
          fileBytes: duplicateDocx,
        ),
        contains('contains duplicate or conflicting primary officeDocument relationships'),
      );

      // 12h. Oversized relationship XML exceeding decompression limit
      final largeRelsXml = '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
          ('<!-- padding -->' * 40000) +
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>';
      final largeBytes = utf8.encode(largeRelsXml);
      final relsBombEntry = ArchiveFile.bytes('_rels/.rels', largeBytes);
      relsBombEntry.size = 200; // Forged declared size passes header check
      final archive = Archive();
      archive.addFile(relsBombEntry);
      archive.addFile(ArchiveFile.bytes('[Content_Types].xml', utf8.encode('<?xml version="1.0"?><Types><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>')));
      archive.addFile(ArchiveFile.bytes('word/document.xml', utf8.encode('<w:document/>')));
      final zipBytes = ZipEncoder().encode(archive)!;
      expect(
        DocumentService.validateFile(
          fileName: 'rels_bomb.docx',
          fileSize: zipBytes.length,
          fileBytes: zipBytes,
        ),
        contains('ZIP decompression limit exceeded during processing, possible zip bomb.'),
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
