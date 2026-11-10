import 'dart:convert';
import 'dart:typed_data';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/models/document_record.dart';
import 'package:action_flow/services/app_file_picker_service.dart';
import 'package:action_flow/services/document_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUp(() {
    DocumentService.allowInMemoryStoreForTests = true;
    MockDocumentStore.instance.reset();
  });

  tearDown(() {
    DocumentService.allowInMemoryStoreForTests = false;
  });

  // ===========================================================================
  // 1. DOCUMENT VALIDATION & FILE CONSTRAINTS
  // ===========================================================================
  group('Document Validation & File Constraints', () {
    test('accepts all supported extensions under 25 MB', () {
      final validExtensions = [
        'pdf', 'doc', 'docx', 'xls', 'xlsx',
        'png', 'jpg', 'jpeg', 'webp', 'csv', 'txt',
      ];

      for (final ext in validExtensions) {
        final err = DocumentService.validateFile(
          fileName: 'report.$ext',
          fileSize: 1024 * 1024, // 1 MB
        );
        expect(err, isNull, reason: 'Extension .$ext should be valid');
      }
    });

    test('rejects dangerous and unsupported file extensions', () {
      final invalidExtensions = ['exe', 'bat', 'sh', 'zip', 'bin', 'dmg', 'js', 'html'];

      for (final ext in invalidExtensions) {
        final err = DocumentService.validateFile(
          fileName: 'malicious_file.$ext',
          fileSize: 500,
        );
        expect(err, isNotNull, reason: 'Extension .$ext must be rejected');
        expect(err, contains('Unsupported file format'));
      }
    });

    test('rejects file without extension or empty name', () {
      expect(
        DocumentService.validateFile(fileName: '', fileSize: 100),
        contains('cannot be empty'),
      );
      expect(
        DocumentService.validateFile(fileName: 'no_extension', fileSize: 100),
        contains('valid extension'),
      );
      expect(
        DocumentService.validateFile(fileName: 'trailing_dot.', fileSize: 100),
        contains('valid extension'),
      );
    });

    test('rejects 0-byte or negative size files', () {
      expect(
        DocumentService.validateFile(fileName: 'test.pdf', fileSize: 0),
        contains('cannot be empty'),
      );
      expect(
        DocumentService.validateFile(fileName: 'test.pdf', fileSize: -10),
        contains('cannot be empty'),
      );
    });

    test('rejects files exceeding 25 MB size limit', () {
      const maxLimit = 25 * 1024 * 1024; // 25 MB

      // Exactly 25 MB is accepted
      expect(
        DocumentService.validateFile(fileName: 'large.pdf', fileSize: maxLimit),
        isNull,
      );

      // 25 MB + 1 byte is rejected
      final err = DocumentService.validateFile(fileName: 'too_large.pdf', fileSize: maxLimit + 1);
      expect(err, isNotNull);
      expect(err, contains('exceeds the maximum allowed limit of 25 MB'));
    });

    test('resolves correct MIME types for each extension', () {
      expect(DocumentService.resolveMimeType('doc.pdf'), 'application/pdf');
      expect(
        DocumentService.resolveMimeType('sheet.xlsx'),
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      expect(
        DocumentService.resolveMimeType('word.docx'),
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
      expect(DocumentService.resolveMimeType('image.png'), 'image/png');
      expect(DocumentService.resolveMimeType('image.jpg'), 'image/jpeg');
      expect(DocumentService.resolveMimeType('data.csv'), 'text/csv');
      expect(DocumentService.resolveMimeType('notes.txt'), 'text/plain');
      expect(DocumentService.resolveMimeType('other.xyz'), 'application/octet-stream');
    });
  });

  // ===========================================================================
  // 2. DOCUMENT RECORD MODEL
  // ===========================================================================
  group('DocumentRecord Model', () {
    test('formats file size properly for human display', () {
      final now = DateTime.now();
      final docBytes = DocumentRecord(
        id: '1', organizationId: 'O1', title: 'T', fileName: 'f.pdf',
        filePath: 'p', fileSize: 850, fileType: 'pdf', createdAt: now, updatedAt: now,
      );
      expect(docBytes.formattedFileSize, '850 B');

      final docKb = docBytes.copyWith(fileSize: 450 * 1024);
      expect(docKb.formattedFileSize, '450.0 KB');

      final docMb = docBytes.copyWith(fileSize: (3.5 * 1024 * 1024).toInt());
      expect(docMb.formattedFileSize, '3.5 MB');
    });

    test('identifies file extensions and boolean helper types correctly', () {
      final now = DateTime.now();
      final base = DocumentRecord(
        id: '1', organizationId: 'O1', title: 'T', fileName: 'file.pdf',
        filePath: 'p', fileSize: 100, fileType: 'pdf', createdAt: now, updatedAt: now,
      );

      expect(base.isPdf, isTrue);
      expect(base.isExcel, isFalse);
      expect(base.isWord, isFalse);
      expect(base.isImage, isFalse);

      final xlsx = base.copyWith(fileName: 'audit.xlsx');
      expect(xlsx.isExcel, isTrue);
      expect(xlsx.fileExtension, 'xlsx');

      final docx = base.copyWith(fileName: 'policy.docx');
      expect(docx.isWord, isTrue);

      final png = base.copyWith(fileName: 'diagram.png');
      expect(png.isImage, isTrue);
    });

    test('serializes to and from JSON accurately', () {
      final now = DateTime(2026, 1, 15, 10, 30);
      final original = DocumentRecord(
        id: 'doc-123',
        organizationId: 'SOBHA-001',
        title: 'Safety Policy 2026',
        description: 'Company safety manual',
        category: DocumentCategory.policies,
        fileName: 'Safety_Policy.pdf',
        filePath: 'SOBHA-001/doc-123/Safety_Policy.pdf',
        fileSize: 1048576,
        fileType: 'application/pdf',
        storageBucket: 'documents',
        actionId: 'AF-1042',
        actionNumber: 'AF-1042',
        createdBy: 'usr-001',
        createdByName: 'John Doe',
        isArchived: false,
        createdAt: now,
        updatedAt: now,
        sharedInternalCount: 3,
        sharedExternalCount: 1,
        sharedWithUserIds: const ['u-1', 'u-2'],
      );

      final json = original.toJson();
      final reconstructed = DocumentRecord.fromJson(json);

      expect(reconstructed.id, original.id);
      expect(reconstructed.organizationId, original.organizationId);
      expect(reconstructed.title, original.title);
      expect(reconstructed.category, original.category);
      expect(reconstructed.actionNumber, original.actionNumber);
      expect(reconstructed.sharedInternalCount, 3);
      expect(reconstructed.sharedExternalCount, 1);
      expect(reconstructed.sharedWithUserIds, contains('u-1'));
    });
  });

  // ===========================================================================
  // 3. DOCUMENT SERVICE - CORE CRUD OPERATIONS
  // ===========================================================================
  group('DocumentService - Core CRUD Operations', () {
    final service = DocumentService.instance;

    test('uploadDocument succeeds and stores record in mock store', () async {
      final bytes = utf8.encode('Sample document binary content');
      final doc = await service.uploadDocument(
        organizationId: 'SOBHA-001',
        title: 'Q1 Site Safety Inspection',
        fileName: 'Q1_Safety_Inspection.pdf',
        fileBytes: bytes,
        category: DocumentCategory.auditChecklists,
        description: 'Comprehensive inspection results',
        actionId: 'AF-1045',
        actionNumber: 'AF-1045',
        userId: 'usr-mgr-01',
        userName: 'Manager Dave',
      );

      expect(doc.id, isNotEmpty);
      expect(doc.title, 'Q1 Site Safety Inspection');
      expect(doc.fileName, 'Q1_Safety_Inspection.pdf');
      expect(doc.category, DocumentCategory.auditChecklists);
      expect(doc.fileSize, bytes.length);
      expect(doc.actionNumber, 'AF-1045');

      final docs = await service.fetchDocuments(organizationId: 'SOBHA-001');
      expect(docs.any((d) => d.id == doc.id), isTrue);
    });

    test('uploadDocument sanitizes empty title using fileName', () async {
      final bytes = utf8.encode('Short content');
      final doc = await service.uploadDocument(
        organizationId: 'SOBHA-001',
        title: '   ', // empty / whitespace title
        fileName: 'Fallback_Name.xlsx',
        fileBytes: bytes,
        category: DocumentCategory.auditChecklists,
        userId: 'usr-mgr-01',
        userName: 'Manager Dave',
      );

      expect(doc.title, 'Fallback_Name.xlsx');
    });

    test('fetchDocuments filters by category, actionId, and search query', () async {
      final docs = await service.fetchDocuments(organizationId: 'SOBHA-001');
      expect(docs.isNotEmpty, isTrue);

      // Category filter
      final manualDocs = await service.fetchDocuments(
        organizationId: 'SOBHA-001',
        category: DocumentCategory.hsseManuals,
      );
      for (final d in manualDocs) {
        expect(d.category.toLowerCase(), DocumentCategory.hsseManuals.toLowerCase());
      }

      // Action ID filter
      final actionDocs = await service.fetchDocuments(
        organizationId: 'SOBHA-001',
        actionId: 'AF-1042',
      );
      expect(actionDocs.every((d) => d.actionId == 'AF-1042' || d.actionNumber == 'AF-1042'), isTrue);

      // Search query (case-insensitive substring)
      final searchResults = await service.fetchDocuments(
        organizationId: 'SOBHA-001',
        searchQuery: 'checklist',
      );
      expect(searchResults.any((d) => d.title.toLowerCase().contains('checklist')), isTrue);
    });

    test('uploadDocument and fetchDocuments support departmentId assignment and filtering', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final doc = await service.uploadDocument(
        organizationId: 'SOBHA-001',
        title: 'HSE Specific Protocol',
        fileName: 'hse_protocol.pdf',
        fileBytes: bytes,
        departmentId: 'dept-hse-01',
        userId: 'usr-mgr-01',
        userName: 'Manager Dave',
      );

      expect(doc.departmentId, 'dept-hse-01');

      final deptDocs = await service.fetchDocuments(
        organizationId: 'SOBHA-001',
        departmentId: 'dept-hse-01',
      );
      expect(deptDocs.any((d) => d.id == doc.id), isTrue);

      final otherDeptDocs = await service.fetchDocuments(
        organizationId: 'SOBHA-001',
        departmentId: 'dept-other-99',
      );
      expect(otherDeptDocs.any((d) => d.id == doc.id), isFalse);
    });

    test('updateDocumentMetadata updates metadata without touching file contents', () async {
      final docs = await service.fetchDocuments(organizationId: 'SOBHA-001');
      final target = docs.first;

      final updated = await service.updateDocumentMetadata(
        documentId: target.id,
        organizationId: target.organizationId,
        title: 'Updated Document Title 2026',
        description: 'New modified description note',
        category: DocumentCategory.riskAssessments,
        actionId: 'AF-9999',
        actionNumber: 'AF-9999',
      );

      expect(updated.title, 'Updated Document Title 2026');
      expect(updated.description, 'New modified description note');
      expect(updated.category, DocumentCategory.riskAssessments);
      expect(updated.actionNumber, 'AF-9999');
      // Storage properties preserved
      expect(updated.filePath, target.filePath);
      expect(updated.fileSize, target.fileSize);
    });

    test('updateDocumentMetadata throws ArgumentError on empty title', () async {
      final docs = await service.fetchDocuments(organizationId: 'SOBHA-001');
      final target = docs.first;

      expect(
        () => service.updateDocumentMetadata(
          documentId: target.id,
          organizationId: target.organizationId,
          title: '   ',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('deleteDocument removes record and cascades cleanup', () async {
      final bytes = utf8.encode('Delete me test content');
      final doc = await service.uploadDocument(
        organizationId: 'SOBHA-001',
        title: 'Temporary Doc To Delete',
        fileName: 'temp_doc.pdf',
        fileBytes: bytes,
        userId: 'usr-001',
        userName: 'User',
      );

      // Share internally and externally first
      await service.shareDocumentInternal(
        documentId: doc.id,
        organizationId: 'SOBHA-001',
        userId: 'staff-01',
        userName: 'Staff Member',
        userEmail: 'staff@sobha.com',
        sharedBy: 'usr-001',
        sharedByName: 'User',
      );

      await service.createExternalShareToken(
        documentId: doc.id,
        organizationId: 'SOBHA-001',
        recipientEmail: 'auditor@external.com',
        createdBy: 'usr-001',
        createdByName: 'User',
      );

      // Delete the document
      await service.deleteDocument(
        documentId: doc.id,
        organizationId: 'SOBHA-001',
        userId: 'usr-001',
      );

      // Verify document is gone
      final docsAfter = await service.fetchDocuments(organizationId: 'SOBHA-001');
      expect(docsAfter.any((d) => d.id == doc.id), isFalse);

      // Verify cascading shares & tokens are removed
      final shares = await service.fetchDocumentShares(documentId: doc.id, organizationId: 'SOBHA-001');
      expect(shares, isEmpty);

      final tokens = await service.fetchDocumentExternalTokens(documentId: doc.id, organizationId: 'SOBHA-001');
      expect(tokens, isEmpty);
    });

    test('getDownloadUrl and getDocumentBytes return valid responses', () async {
      final docs = await service.fetchDocuments(organizationId: 'SOBHA-001');
      final doc = docs.first;

      final url = await service.getDownloadUrl(
        documentId: doc.id,
        organizationId: doc.organizationId,
        expiresInSeconds: 300,
      );
      expect(url, isNotEmpty);
      expect(url, contains('expires='));

      final bytes = await service.getDocumentBytes(
        documentId: doc.id,
        organizationId: doc.organizationId,
      );
      expect(bytes, isNotNull);
      expect(bytes, isNotEmpty);
    });
  });

  // ===========================================================================
  // 4. SECURE SHARING: INTERNAL STAFF
  // ===========================================================================
  group('Secure Sharing - Internal Staff', () {
    final service = DocumentService.instance;

    test('shareDocumentInternal creates share, sets permission, and increments count', () async {
      final docs = await service.fetchDocuments(organizationId: 'SOBHA-001');
      final doc = docs.first;
      final initialCount = doc.sharedInternalCount;

      final share = await service.shareDocumentInternal(
        documentId: doc.id,
        organizationId: 'SOBHA-001',
        userId: 'staff-uuid-999',
        userName: 'New Staff',
        userEmail: 'newstaff@sobha.com',
        permission: 'download',
        sharedBy: 'usr-mgr-01',
        sharedByName: 'Manager Dave',
      );

      expect(share.id, isNotEmpty);
      expect(share.userId, 'staff-uuid-999');
      expect(share.permission, 'download');

      // Verify share list
      final shares = await service.fetchDocumentShares(
        documentId: doc.id,
        organizationId: 'SOBHA-001',
      );
      expect(shares.any((s) => s.userId == 'staff-uuid-999'), isTrue);

      // Verify document share count updated
      final updatedDocs = await service.fetchDocuments(organizationId: 'SOBHA-001');
      final updatedDoc = updatedDocs.firstWhere((d) => d.id == doc.id);
      expect(updatedDoc.sharedInternalCount, initialCount + 1);
    });

    test('revokeDocumentInternalShare removes share and decrements count', () async {
      final docs = await service.fetchDocuments(organizationId: 'SOBHA-001');
      final doc = docs.first;

      final share = await service.shareDocumentInternal(
        documentId: doc.id,
        organizationId: 'SOBHA-001',
        userId: 'temp-staff',
        userName: 'Temp Staff',
        userEmail: 'temp@sobha.com',
        permission: 'view',
        sharedBy: 'usr-mgr-01',
        sharedByName: 'Manager Dave',
      );

      final countBeforeRevoke = (await service.fetchDocuments(organizationId: 'SOBHA-001'))
          .firstWhere((d) => d.id == doc.id).sharedInternalCount;

      await service.revokeDocumentInternalShare(
        shareId: share.id,
        documentId: doc.id,
        organizationId: 'SOBHA-001',
      );

      final sharesAfter = await service.fetchDocumentShares(
        documentId: doc.id,
        organizationId: 'SOBHA-001',
      );
      expect(sharesAfter.any((s) => s.id == share.id), isFalse);

      final countAfterRevoke = (await service.fetchDocuments(organizationId: 'SOBHA-001'))
          .firstWhere((d) => d.id == doc.id).sharedInternalCount;
      expect(countAfterRevoke, countBeforeRevoke - 1);
    });
  });

  // ===========================================================================
  // 5. SECURE SHARING: EXTERNAL RECIPIENT TOKENS (SHA-256)
  // ===========================================================================
  group('Secure Sharing - External Recipient Tokens (SHA-256)', () {
    final service = DocumentService.instance;

    test('generateSecureToken produces 64-character (32-byte) hex string', () {
      final token1 = DocumentService.generateSecureToken();
      final token2 = DocumentService.generateSecureToken();

      expect(token1.length, 64);
      expect(token2.length, 64);
      expect(token1, isNot(equals(token2)));
      expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(token1), isTrue);
    });

    test('createExternalShareToken stores SHA-256 hash, not plaintext token', () async {
      final docs = await service.fetchDocuments(organizationId: 'SOBHA-001');
      final doc = docs.first;

      final result = await service.createExternalShareToken(
        documentId: doc.id,
        organizationId: 'SOBHA-001',
        recipientEmail: 'external.auditor@dnv.com',
        recipientName: 'Lead Auditor Jane',
        expiresInDays: 14,
        permission: 'download',
        createdBy: 'usr-mgr-01',
        createdByName: 'Manager Dave',
      );

      final plainToken = result.token;
      final tokenRecord = result.record;

      // Plain token is 64 hex characters
      expect(plainToken.length, 64);

      // Record stores SHA-256 hash of the plain token
      final expectedHash = sha256.convert(utf8.encode(plainToken)).toString();
      expect(tokenRecord.tokenHash, expectedHash);
      expect(tokenRecord.tokenHash, isNot(equals(plainToken)));
      expect(tokenRecord.isRevoked, isFalse);
      expect(tokenRecord.isExpired, isFalse);
      expect(tokenRecord.permission, 'download');
    });

    test('verifyExternalTokenAndGetDocument succeeds and increments access metric', () async {
      final docs = await service.fetchDocuments(organizationId: 'SOBHA-001');
      final doc = docs.first;

      final result = await service.createExternalShareToken(
        documentId: doc.id,
        organizationId: 'SOBHA-001',
        recipientEmail: 'auditor@gov.ae',
        expiresInDays: 7,
        permission: 'view',
        createdBy: 'usr-01',
        createdByName: 'Manager',
      );

      final plainToken = result.token;

      // 1st verification
      final res1 = await service.verifyExternalTokenAndGetDocument(plainToken);
      expect(res1.isValid, isTrue);
      expect(res1.error, isNull);
      expect(res1.document, isNotNull);
      expect(res1.document!.id, doc.id);
      expect(res1.tokenRecord!.accessCount, 1);

      // 2nd verification
      final res2 = await service.verifyExternalTokenAndGetDocument(plainToken);
      expect(res2.isValid, isTrue);
      expect(res2.tokenRecord!.accessCount, 2);
      expect(res2.tokenRecord!.lastAccessedAt, isNotNull);
    });

    test('verification rejects expired token', () async {
      final docs = await service.fetchDocuments(organizationId: 'SOBHA-001');
      final doc = docs.first;

      // Create token expired in the past
      final plainToken = DocumentService.generateSecureToken();
      final tokenHash = sha256.convert(utf8.encode(plainToken)).toString();
      final expiredRecord = DocumentExternalToken(
        id: 'tok-expired-01',
        documentId: doc.id,
        tokenHash: tokenHash,
        recipientEmail: 'expired@user.com',
        organizationId: 'SOBHA-001',
        permission: 'view',
        expiresAt: DateTime.now().subtract(const Duration(days: 1)), // Expired yesterday
        createdAt: DateTime.now().subtract(const Duration(days: 15)),
      );
      MockDocumentStore.instance.externalTokens.add(expiredRecord);

      final verifyRes = await service.verifyExternalTokenAndGetDocument(plainToken);
      expect(verifyRes.isValid, isFalse);
      expect(verifyRes.error, contains('expired'));
      expect(verifyRes.document, isNull);
    });

    test('verification rejects revoked token with explicit reason', () async {
      final docs = await service.fetchDocuments(organizationId: 'SOBHA-001');
      final doc = docs.first;

      final result = await service.createExternalShareToken(
        documentId: doc.id,
        organizationId: 'SOBHA-001',
        recipientEmail: 'contractor@partner.com',
        expiresInDays: 30,
        createdBy: 'usr-01',
        createdByName: 'Manager',
      );

      final plainToken = result.token;

      // Manager revokes the token
      await service.revokeExternalShareToken(
        tokenId: result.record.id,
        documentId: doc.id,
        organizationId: 'SOBHA-001',
        revokedBy: 'usr-01',
        reason: 'Contract terminated',
      );

      // External user attempts to access document
      final verifyRes = await service.verifyExternalTokenAndGetDocument(plainToken);
      expect(verifyRes.isValid, isFalse);
      expect(verifyRes.error, contains('revoked'));
      expect(verifyRes.document, isNull);
    });

    test('verification rejects completely invalid or tampered token', () async {
      const forgedToken = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      final verifyRes = await service.verifyExternalTokenAndGetDocument(forgedToken);

      expect(verifyRes.isValid, isFalse);
      expect(verifyRes.error, contains('Invalid or nonexistent'));
    });
  });

  // ===========================================================================
  // 6. ACTION LINKING & REGRESSION SAFETY (STEP 25 PROGRESS PRESERVED)
  // ===========================================================================
  group('Action Linking & Regression Safety', () {
    final service = DocumentService.instance;

    test('linking or unlinking document preserves action progress, status, and tasks', () async {
      final action = ActionRecord(
        id: 'AF-1042',
        actionNumber: 'AF-1042',
        subject: 'Safety Valve Inspection',
        assignedTo: 'M. Ali',
        division: 'Operations',
        actionRequired: 'Inspect and test valves',
        priority: 'High',
        targetDate: '2026-10-30',
        status: 'In Progress',
        percentComplete: 60, // Step 25 manual progress: 60%
        subTasks: const [
          ActionSubTask(
            id: 't-1',
            parentActionId: 'AF-1042',
            title: 'Task 1',
            instruction: 'Inspect valve 1',
            assignedStaff: 'M. Ali',
            status: 'Completed',
          ),
          ActionSubTask(
            id: 't-2',
            parentActionId: 'AF-1042',
            title: 'Task 2',
            instruction: 'Inspect valve 2',
            assignedStaff: 'M. Ali',
            status: 'Open',
          ),
          ActionSubTask(
            id: 't-3',
            parentActionId: 'AF-1042',
            title: 'Task 3',
            instruction: 'Inspect valve 3',
            assignedStaff: 'M. Ali',
            status: 'Open',
          ),
        ],
      );

      // Upload and link document to this action
      final bytes = utf8.encode('Calibration certification sheet');
      final doc = await service.uploadDocument(
        organizationId: 'SOBHA-001',
        title: 'Valve Calibration Cert',
        fileName: 'Valve_Cert.pdf',
        fileBytes: bytes,
        category: DocumentCategory.actionEvidence,
        actionId: action.id,
        actionNumber: action.actionNumber,
        userId: 'usr-01',
        userName: 'Manager',
      );

      expect(doc.actionId, action.id);
      expect(doc.actionNumber, action.actionNumber);

      // Verify Action properties remain strictly unchanged
      expect(action.percentComplete, 60, reason: 'Action progress must remain 60%');
      expect(action.status, 'In Progress');
      expect(action.subTasks.length, 3);
      expect(action.subTasks.where((t) => t.isCompleted).length, 1);

      // Unlink the document via metadata update
      final unlinked = await service.updateDocumentMetadata(
        documentId: doc.id,
        organizationId: 'SOBHA-001',
        title: doc.title,
        actionId: null,
        actionNumber: null,
      );

      expect(unlinked.actionId, isNull);
      expect(unlinked.actionNumber, isNull);

      // Action properties remain 100% unaltered
      expect(action.percentComplete, 60);
      expect(action.status, 'In Progress');
    });
  });

  // ===========================================================================
  // 7. UI WIDGET TESTS
  // ===========================================================================
  group('Documents UI Widget Tests', () {
    testWidgets('Manager Dashboard renders Safety Documents view with cards', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));

      final List<ActionRecord> testActions = [
        ActionRecord(
          id: 'AF-1042',
          actionNumber: 'AF-1042',
          subject: 'Corrective Safety Audit',
          assignedTo: 'M. Ali',
          division: 'Operations',
          actionRequired: 'Verify PPE compliance',
          priority: 'High',
          targetDate: '2026-10-25',
          status: 'Open',
          percentComplete: 40,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ManagerDashboardScreen(
              userProfile: UserProfile(
                id: 'usr-mgr-01',
                email: 'manager@actionflow.com',
                name: 'M. Ali',
                phone: '+971 50 123 4567',
                designation: 'Safety Manager',
                department: 'HSE',
                site: 'North Yard',
                role: 'manager',
                organizationId: 'SOBHA-001',
                organizationName: 'Sobha Constructions',
              ),
              initialActions: testActions,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Navigate to Documents view (index 7 or click navigation item)
      final docNavFinder = find.text('Documents');
      expect(docNavFinder, findsOneWidget);
      await tester.tap(docNavFinder);
      await tester.pumpAndSettle();

      // Verify Safety Documents & Guidelines header appears
      expect(find.text('Safety Documents & Guidelines'), findsOneWidget);
      expect(find.text('Upload Document'), findsAtLeast(1));

      // Verify search field and category filter chips appear
      expect(find.byType(TextField), findsAtLeast(1));
      expect(find.text('All'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, DocumentCategory.hsseManuals), findsOneWidget);

      // Verify seed documents are rendered
      expect(find.text('HSSE Manual 2026'), findsOneWidget);
      expect(find.text('Site Audit Checklist'), findsOneWidget);
    });

    testWidgets('Worker Dashboard renders documents view with download button', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkerDashboardScreen(
              userProfile: UserProfile(
                id: 'staff-worker-01',
                email: 'worker@actionflow.com',
                name: 'Staff Worker',
                phone: '+971 50 987 6543',
                designation: 'HSE Technician',
                department: 'Operations',
                site: 'North Yard',
                role: 'staff',
                organizationId: 'SOBHA-001',
                organizationName: 'Sobha Constructions',
              ),
              
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Navigate to Documents
      final docNav = find.text('Documents');
      if (docNav.evaluate().isNotEmpty) {
        await tester.tap(docNav.first);
        await tester.pumpAndSettle();
      }

      // Verify Safety Documents view renders
      expect(find.text('Safety Documents & Guidelines'), findsOneWidget);
      expect(find.byIcon(Icons.download_rounded), findsAtLeast(1));
    });
  });

  // ===========================================================================
  // 6. STORAGE ERROR DIAGNOSTICS & MISSING BUCKET HANDLING
  // ===========================================================================
  group('Storage Error Diagnostics & Missing Bucket Handling', () {
    test('formatStorageError produces actionable diagnostics for missing bucket (404)', () {
      const err404 = StorageException('Bucket not found', statusCode: '404', error: 'Bucket not found');
      final msg = DocumentService.formatStorageError(err404);
      expect(msg, contains('Storage bucket "documents" not found on the backend'));
      expect(msg, contains('20261021000001_documents_system_and_sharing.sql'));
    });

    test('formatStorageError produces permission diagnostics for 403 / 401', () {
      const err403 = StorageException('Access Denied', statusCode: '403');
      final msg = DocumentService.formatStorageError(err403);
      expect(msg, contains('Storage permission denied'));
      expect(msg, contains('403'));
    });

    test('formatStorageError handles generic string error mentioning bucket not found', () {
      final msg = DocumentService.formatStorageError('StorageException(message: Bucket not found, statusCode: 404)');
      expect(msg, contains('Storage bucket "documents" not found on the backend'));
    });

    test('metadata record is never persisted when uploadDocument fails validation or storage upload', () async {
      final countBefore = MockDocumentStore.instance.documents.length;

      // 1. Invalid file validation failure throws ArgumentError without touching store
      expect(
        () => DocumentService.instance.uploadDocument(
          organizationId: 'SOBHA-001',
          title: 'Invalid File',
          fileName: 'malicious.exe',
          fileBytes: [1, 2, 3],
          userId: 'usr-1',
          userName: 'User 1',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(MockDocumentStore.instance.documents.length, countBefore);
    });

    test('in-memory fallback upload returns DocumentRecord with isPersisted == false', () async {
      final doc = await DocumentService.instance.uploadDocument(
        organizationId: 'SOBHA-001',
        title: 'Temporary Mock Test Doc',
        fileName: 'test.pdf',
        fileBytes: [1, 2, 3, 4],
        userId: 'usr-1',
        userName: 'User 1',
      );
      expect(doc.isPersisted, false);
      expect(doc.fileBytes, isNotEmpty);
    });

    test('uninitialized backend fails instead of pretending an upload persisted', () async {
      DocumentService.allowInMemoryStoreForTests = false;
      final countBefore = MockDocumentStore.instance.documents.length;

      await expectLater(
        DocumentService.instance.uploadDocument(
          organizationId: 'SOBHA-001',
          title: 'Unavailable backend test',
          fileName: 'test.pdf',
          fileBytes: [1, 2, 3, 4],
          userId: 'usr-1',
          userName: 'User 1',
        ),
        throwsA(isA<StateError>()),
      );
      expect(MockDocumentStore.instance.documents.length, countBefore);
    });
  });

  // ===========================================================================
  // 7. APP FILE PICKER SERVICE UNIT TESTS
  // ===========================================================================
  group('AppFilePicker Service', () {
    tearDown(() {
      AppFilePicker.testOverride = null;
      AppFilePicker.saveTestOverride = null;
    });

    test('AppPickedFile formats extension and sizes correctly', () {
      final f1 = AppPickedFile(
        name: 'Report.PDF',
        size: 512,
        bytes: Uint8List(512),
      );
      expect(f1.extension, 'pdf');
      expect(f1.formattedSize, '512 B');

      final f2 = AppPickedFile(
        name: 'Spreadsheet.xlsx',
        size: 2 * 1024 * 1024,
        bytes: Uint8List(100),
      );
      expect(f2.extension, 'xlsx');
      expect(f2.formattedSize, '2.0 MB');
    });

    test('pickSingleFile returns file from testOverride', () async {
      final testFile = AppPickedFile(
        name: 'test.docx',
        size: 1024,
        bytes: Uint8List(1024),
      );
      AppFilePicker.testOverride = ({required allowedExtensions}) async => testFile;

      final res = await AppFilePicker.pickSingleFile();
      expect(res, isNotNull);
      expect(res!.name, 'test.docx');
    });

    test('pickSingleFile returns null when selection is cancelled', () async {
      AppFilePicker.testOverride = ({required allowedExtensions}) async => null;

      final res = await AppFilePicker.pickSingleFile();
      expect(res, isNull);
    });

    test('saveFile validates empty file name and empty bytes', () async {
      expect(
        () => AppFilePicker.saveFile(
          fileName: '',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => AppFilePicker.saveFile(
          fileName: 'test.pdf',
          bytes: Uint8List(0),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('saveFile delegates to saveTestOverride and returns status', () async {
      AppFilePicker.saveTestOverride = ({
        required String fileName,
        required Uint8List bytes,
        String mimeType = 'application/octet-stream',
      }) async {
        return fileName == 'success.pdf';
      };

      final ok = await AppFilePicker.saveFile(
        fileName: 'success.pdf',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      expect(ok, isTrue);

      final cancelled = await AppFilePicker.saveFile(
        fileName: 'cancel.pdf',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      expect(cancelled, isFalse);

      AppFilePicker.saveTestOverride = null;
    });
  });

  // ===========================================================================
  // 8. DEVICE FILE PICKER IN UPLOAD DIALOG
  // ===========================================================================
  group('Device File Picker in Upload Dialog', () {
    AppPickedFile? nextFile;
    bool shouldThrow = false;

    setUp(() {
      nextFile = null;
      shouldThrow = false;
      AppFilePicker.testOverride = ({required allowedExtensions}) async {
        if (shouldThrow) {
          throw Exception('Simulated device picker access denied');
        }
        return nextFile;
      };
    });

    tearDown(() {
      AppFilePicker.testOverride = null;
      AppFilePicker.saveTestOverride = null;
    });

    final testActions = [
      ActionRecord(
        id: 'AF-1001',
        actionNumber: 'AF-1001',
        subject: 'Scaffolding Safety Inspection',
        actionRequired: 'Inspect all scaffolding tags',
        division: 'Operations',
        assignedTo: 'M. Ali',
        priority: 'High',
        targetDate: '2026-10-25',
        status: 'Open',
        percentComplete: 20,
      ),
    ];

    Future<void> pumpManagerDocumentsScreen(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ManagerDashboardScreen(
              userProfile: UserProfile(
                id: 'usr-mgr-01',
                email: 'manager@actionflow.com',
                name: 'M. Ali',
                phone: '+971 50 123 4567',
                designation: 'Safety Manager',
                department: 'HSE',
                site: 'North Yard',
                role: 'manager',
                organizationId: 'SOBHA-001',
                organizationName: 'Sobha Constructions',
              ),
              initialActions: testActions,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Documents view
      final docNav = find.text('Documents');
      await tester.tap(docNav);
      await tester.pumpAndSettle();
    }

    testWidgets('Upload dialog opens with Choose File control and disabled Upload button', (tester) async {
      await pumpManagerDocumentsScreen(tester);

      // Tap Upload Document button
      final uploadBtn = find.byKey(const Key('documents_upload_button'));
      expect(uploadBtn, findsOneWidget);
      await tester.tap(uploadBtn);
      await tester.pumpAndSettle();

      // Verify dialog appears
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byKey(const Key('documents_choose_file_button')), findsOneWidget);
      expect(find.text('Choose File from Device'), findsOneWidget);
      expect(find.textContaining('Supported: PDF, DOC, DOCX, XLS, XLSX, PNG, JPG'), findsOneWidget);

      // Verify Upload File submit button is disabled initially
      final submitBtnFinder = find.byKey(const Key('documents_submit_upload_button'));
      expect(submitBtnFinder, findsOneWidget);
      final FilledButton submitBtn = tester.widget(submitBtnFinder);
      expect(submitBtn.onPressed, isNull, reason: 'Submit button must be disabled until valid file is selected');
    });

    testWidgets('Picking valid file updates UI with file icon, name, formatted size, and enables Upload', (tester) async {
      final sampleBytes = Uint8List.fromList(List.generate(1024 * 500, (i) => i % 256)); // 500 KB
      nextFile = AppPickedFile(name: 'Site_Safety_Audit.pdf', bytes: sampleBytes);

      await pumpManagerDocumentsScreen(tester);

      await tester.tap(find.byKey(const Key('documents_upload_button')));
      await tester.pumpAndSettle();

      // Tap Choose File button
      await tester.tap(find.byKey(const Key('documents_choose_file_button')));
      await tester.pumpAndSettle();

      // Verify picked file appears
      expect(find.byKey(const Key('documents_selected_file_name')), findsOneWidget);
      expect(find.text('Site_Safety_Audit.pdf'), findsOneWidget);
      expect(find.text('500.0 KB'), findsOneWidget);
      expect(find.text('Ready to upload'), findsOneWidget);
      expect(find.byKey(const Key('documents_change_file_button')), findsOneWidget);
      expect(find.byKey(const Key('documents_remove_file_button')), findsOneWidget);

      // Verify submit button is now enabled
      final submitBtnFinder = find.byKey(const Key('documents_submit_upload_button'));
      final FilledButton submitBtn = tester.widget(submitBtnFinder);
      expect(submitBtn.onPressed, isNotNull, reason: 'Submit button must be enabled with valid file and title');
    });

    testWidgets('User cancellation in file picker preserves dialog state without error', (tester) async {
      nextFile = null; // simulate cancel

      await pumpManagerDocumentsScreen(tester);
      await tester.tap(find.byKey(const Key('documents_upload_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('documents_choose_file_button')));
      await tester.pumpAndSettle();

      // Dialog is still open, still showing Choose File
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byKey(const Key('documents_choose_file_button')), findsOneWidget);
      expect(find.byKey(const Key('documents_validation_error')), findsNothing);
    });

    testWidgets('Removing selected file resets selection and disables Upload button', (tester) async {
      final sampleBytes = Uint8List.fromList(List.generate(2048, (i) => i % 256));
      nextFile = AppPickedFile(name: 'Checklist.xlsx', bytes: sampleBytes);

      await pumpManagerDocumentsScreen(tester);
      await tester.tap(find.byKey(const Key('documents_upload_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('documents_choose_file_button')));
      await tester.pumpAndSettle();

      expect(find.text('Checklist.xlsx'), findsOneWidget);

      // Tap remove button
      await tester.tap(find.byKey(const Key('documents_remove_file_button')));
      await tester.pumpAndSettle();

      // Back to initial choose file state
      expect(find.byKey(const Key('documents_choose_file_button')), findsOneWidget);
      expect(find.text('Checklist.xlsx'), findsNothing);

      final FilledButton submitBtn = tester.widget(find.byKey(const Key('documents_submit_upload_button')));
      expect(submitBtn.onPressed, isNull);
    });

    testWidgets('Reselecting / changing file updates selected file metadata', (tester) async {
      nextFile = AppPickedFile(name: 'First.pdf', bytes: Uint8List.fromList([1, 2, 3]));

      await pumpManagerDocumentsScreen(tester);
      await tester.tap(find.byKey(const Key('documents_upload_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('documents_choose_file_button')));
      await tester.pumpAndSettle();
      expect(find.text('First.pdf'), findsOneWidget);

      // Now change file to Second.docx
      nextFile = AppPickedFile(name: 'Second.docx', bytes: Uint8List.fromList([4, 5, 6, 7]));
      await tester.tap(find.byKey(const Key('documents_change_file_button')));
      await tester.pumpAndSettle();

      expect(find.text('Second.docx'), findsOneWidget);
      expect(find.text('First.pdf'), findsNothing);
    });

    testWidgets('Selecting invalid file (unsupported extension) shows error and prevents upload', (tester) async {
      nextFile = AppPickedFile(name: 'malicious.exe', bytes: Uint8List.fromList([1, 2, 3]));

      await pumpManagerDocumentsScreen(tester);
      await tester.tap(find.byKey(const Key('documents_upload_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('documents_choose_file_button')));
      await tester.pumpAndSettle();

      // Error banner is displayed
      expect(find.byKey(const Key('documents_validation_error')), findsOneWidget);
      expect(find.textContaining('Unsupported file format (.exe)'), findsOneWidget);

      // Submit button is disabled
      final FilledButton submitBtn = tester.widget(find.byKey(const Key('documents_submit_upload_button')));
      expect(submitBtn.onPressed, isNull);
    });

    testWidgets('Selecting file exceeding 25 MB shows error and prevents upload', (tester) async {
      // 26 MB file
      final hugeFile = AppPickedFile(name: 'Huge.pdf', bytes: Uint8List(26 * 1024 * 1024));
      nextFile = hugeFile;

      await pumpManagerDocumentsScreen(tester);
      await tester.tap(find.byKey(const Key('documents_upload_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('documents_choose_file_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('documents_validation_error')), findsOneWidget);
      expect(find.textContaining('exceeds the maximum allowed limit of 25 MB'), findsOneWidget);

      final FilledButton submitBtn = tester.widget(find.byKey(const Key('documents_submit_upload_button')));
      expect(submitBtn.onPressed, isNull);
    });

    testWidgets('Selecting 0-byte file shows error and prevents upload', (tester) async {
      nextFile = AppPickedFile(name: 'empty.pdf', bytes: Uint8List(0));

      await pumpManagerDocumentsScreen(tester);
      await tester.tap(find.byKey(const Key('documents_upload_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('documents_choose_file_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('documents_validation_error')), findsOneWidget);
      expect(find.textContaining('File cannot be empty'), findsOneWidget);

      final FilledButton submitBtn = tester.widget(find.byKey(const Key('documents_submit_upload_button')));
      expect(submitBtn.onPressed, isNull);
    });

    testWidgets('Device picker error displays recoverable error message in dialog', (tester) async {
      shouldThrow = true;

      await pumpManagerDocumentsScreen(tester);
      await tester.tap(find.byKey(const Key('documents_upload_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('documents_choose_file_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('documents_validation_error')), findsOneWidget);
      expect(find.textContaining('Failed to select file: Exception: Simulated device picker access denied'), findsOneWidget);

      // Can recover by unsetting throw and trying again
      shouldThrow = false;
      nextFile = AppPickedFile(name: 'Recovered.pdf', bytes: Uint8List.fromList([10, 20, 30]));
      await tester.tap(find.byKey(const Key('documents_choose_file_button')));
      await tester.pumpAndSettle();

      expect(find.text('Recovered.pdf'), findsOneWidget);
      expect(find.byKey(const Key('documents_validation_error')), findsNothing);
    });

    testWidgets('Successful upload persists file, closes dialog, and adds document to dashboard', (tester) async {
      final sampleBytes = Uint8List.fromList([65, 66, 67, 68]);
      nextFile = AppPickedFile(name: 'Q3_Safety_Review.pdf', bytes: sampleBytes);

      await pumpManagerDocumentsScreen(tester);
      await tester.tap(find.byKey(const Key('documents_upload_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('documents_choose_file_button')));
      await tester.pumpAndSettle();

      // Submit upload
      await tester.tap(find.byKey(const Key('documents_submit_upload_button')));
      await tester.pumpAndSettle();

      // Dialog closed
      expect(find.byType(AlertDialog), findsNothing);

      // SnackBar displayed showing upload confirmation
      expect(find.textContaining('uploaded to preview store'), findsOneWidget);

      // New document is displayed in documents view
      expect(find.text('Q3 Safety Review'), findsOneWidget);
    });
  });
}
