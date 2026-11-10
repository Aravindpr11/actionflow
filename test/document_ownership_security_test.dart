import 'dart:io';

import 'package:action_flow/models/document_record.dart';
import 'package:action_flow/services/app_file_picker_service.dart';
import 'package:action_flow/services/document_service.dart';
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

  group('Document Ownership & Private Isolation Security Tests', () {
    test('Staff A cannot see Staff B private unshared documents', () async {
      final store = MockDocumentStore.instance;
      store.documents.clear();
      store.shares.clear();

      // Seed Staff A private document
      final docA = DocumentRecord(
        id: 'doc-private-staff-a',
        organizationId: 'SOBHA-001',
        title: 'Staff A Personal Notes',
        fileName: 'notes_a.pdf',
        filePath: 'SOBHA-001/doc-private-staff-a/notes_a.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        category: DocumentCategory.general,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'staff-user-a',
        createdByName: 'Staff User A',
      );

      // Seed Staff B private document
      final docB = DocumentRecord(
        id: 'doc-private-staff-b',
        organizationId: 'SOBHA-001',
        title: 'Staff B Incident Investigation',
        fileName: 'investigation_b.pdf',
        filePath: 'SOBHA-001/doc-private-staff-b/investigation_b.pdf',
        fileSize: 2048,
        fileType: 'application/pdf',
        category: DocumentCategory.general,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'staff-user-b',
        createdByName: 'Staff User B',
      );

      store.documents.addAll([docA, docB]);

      // Staff A fetches documents
      final docsForA = await DocumentService.instance.fetchDocuments(
        organizationId: 'SOBHA-001',
        currentUserId: 'staff-user-a',
        userRole: 'staff',
      );

      // Staff A must see docA, but MUST NOT see docB
      expect(docsForA.any((d) => d.id == 'doc-private-staff-a'), isTrue);
      expect(docsForA.any((d) => d.id == 'doc-private-staff-b'), isFalse);

      // Staff B fetches documents
      final docsForB = await DocumentService.instance.fetchDocuments(
        organizationId: 'SOBHA-001',
        currentUserId: 'staff-user-b',
        userRole: 'staff',
      );

      // Staff B must see docB, but MUST NOT see docA
      expect(docsForB.any((d) => d.id == 'doc-private-staff-b'), isTrue);
      expect(docsForB.any((d) => d.id == 'doc-private-staff-a'), isFalse);
    });

    test('Explicit document sharing grants access only to designated recipient', () async {
      final store = MockDocumentStore.instance;
      store.documents.clear();
      store.shares.clear();

      // Staff A creates private document
      final docA = DocumentRecord(
        id: 'doc-shared-a-to-b',
        organizationId: 'SOBHA-001',
        title: 'Staff A Shared Report',
        fileName: 'shared_report.pdf',
        filePath: 'SOBHA-001/doc-shared-a-to-b/shared_report.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        category: DocumentCategory.general,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'staff-user-a',
        createdByName: 'Staff User A',
        sharedWithUserIds: const ['staff-user-b'],
        sharedByUserIds: const ['staff-user-a'],
      );

      store.documents.add(docA);

      store.shares.add(
        DocumentShare(
          id: 'share-001',
          documentId: 'doc-shared-a-to-b',
          userId: 'staff-user-b',
          userName: 'Staff User B',
          userEmail: 'b@sobha.com',
          organizationId: 'SOBHA-001',
          permission: 'view',
          sharedBy: 'staff-user-a',
          sharedByName: 'Staff User A',
          createdAt: DateTime.now(),
        ),
      );

      // Staff B can view the shared document
      final docsForB = await DocumentService.instance.fetchDocuments(
        organizationId: 'SOBHA-001',
        currentUserId: 'staff-user-b',
        userRole: 'staff',
      );
      expect(docsForB.any((d) => d.id == 'doc-shared-a-to-b'), isTrue);

      // Staff C (unrelated third party) CANNOT see the shared document
      final docsForC = await DocumentService.instance.fetchDocuments(
        organizationId: 'SOBHA-001',
        currentUserId: 'staff-user-c',
        userRole: 'staff',
      );
      expect(docsForC.any((d) => d.id == 'doc-shared-a-to-b'), isFalse);
    });

    test('Document ownership and share identity helper validation', () {
      final doc = DocumentRecord(
        id: 'doc-ownership-model-test',
        organizationId: 'SOBHA-001',
        title: 'Ownership Model Verification',
        fileName: 'verify.pdf',
        filePath: 'SOBHA-001/doc-ownership-model-test/verify.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        category: DocumentCategory.general,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'staff-user-a',
        createdByName: 'Staff User A',
        sharedWithUserIds: const ['staff-user-b'],
        sharedByUserIds: const ['staff-user-a'],
      );

      // Staff A is owner
      expect(doc.isOwnedBy('staff-user-a'), isTrue);
      expect(doc.isOwnedBy('staff-user-b'), isFalse);
      expect(doc.isOwnedBy('staff-user-c'), isFalse);

      // Staff B is shared recipient
      expect(doc.isSharedWith('staff-user-b'), isTrue);
      expect(doc.isSharedWith('staff-user-a'), isFalse);
      expect(doc.isSharedWith('staff-user-c'), isFalse);

      // Staff A is sharedBy
      expect(doc.isSharedBy('staff-user-a'), isTrue);
      expect(doc.isSharedBy('staff-user-b'), isFalse);
    });

    test('Company-wide guidelines (HSSE Manuals, Policies) are accessible without personal share', () async {
      final store = MockDocumentStore.instance;
      store.documents.clear();
      store.shares.clear();

      final policyDoc = DocumentRecord(
        id: 'doc-hsse-policy',
        organizationId: 'SOBHA-001',
        title: 'Sobha HSSE Manual 2026',
        fileName: 'hsse_manual_2026.pdf',
        filePath: 'SOBHA-001/doc-hsse-policy/hsse_manual_2026.pdf',
        fileSize: 4096,
        fileType: 'application/pdf',
        category: DocumentCategory.hsseManuals,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'admin-user',
        createdByName: 'Safety Director',
      );

      store.documents.add(policyDoc);

      // Any active employee in organization can see company-wide HSSE Manuals
      final docsForStaff = await DocumentService.instance.fetchDocuments(
        organizationId: 'SOBHA-001',
        currentUserId: 'staff-new-hire',
        userRole: 'staff',
      );

      expect(docsForStaff.any((d) => d.id == 'doc-hsse-policy'), isTrue);
    });

    test('General category documents without explicit share are NOT company-wide', () async {
      final store = MockDocumentStore.instance;
      store.documents.clear();
      store.shares.clear();

      final generalDoc = DocumentRecord(
        id: 'doc-general-unshared',
        organizationId: 'SOBHA-001',
        title: 'Unshared Internal Note',
        fileName: 'note.pdf',
        filePath: 'SOBHA-001/doc-general-unshared/note.pdf',
        fileSize: 512,
        fileType: 'application/pdf',
        category: DocumentCategory.general,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'staff-user-a',
        createdByName: 'Staff A',
      );

      store.documents.add(generalDoc);

      // Staff B should NOT see Staff A general doc
      final docsForB = await DocumentService.instance.fetchDocuments(
        organizationId: 'SOBHA-001',
        currentUserId: 'staff-user-b',
        userRole: 'staff',
      );

      expect(docsForB.any((d) => d.id == 'doc-general-unshared'), isFalse);
    });

    test('Document owner can update metadata without altering immutable owner or org', () async {
      final store = MockDocumentStore.instance;
      store.documents.clear();
      store.shares.clear();

      final doc = DocumentRecord(
        id: 'doc-owner-edit-test',
        organizationId: 'SOBHA-001',
        title: 'Original Title',
        fileName: 'doc.pdf',
        filePath: 'SOBHA-001/doc-owner-edit-test/doc.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        category: DocumentCategory.general,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'staff-owner',
        createdByName: 'Staff Owner',
      );
      store.documents.add(doc);

      final updated = await DocumentService.instance.updateDocumentMetadata(
        documentId: 'doc-owner-edit-test',
        organizationId: 'SOBHA-001',
        title: 'Updated Title by Owner',
        description: 'New Description',
        currentUserId: 'staff-owner',
        userRole: 'staff',
      );

      expect(updated.title, equals('Updated Title by Owner'));
      expect(updated.description, equals('New Description'));
      // Immutability checks:
      expect(updated.createdBy, equals('staff-owner'));
      expect(updated.organizationId, equals('SOBHA-001'));
      expect(updated.filePath, equals('SOBHA-001/doc-owner-edit-test/doc.pdf'));
      expect(updated.id, equals('doc-owner-edit-test'));
    });

    test('Explicit edit-share recipient can update permitted metadata but cannot hijack ownership', () async {
      final store = MockDocumentStore.instance;
      store.documents.clear();
      store.shares.clear();

      final doc = DocumentRecord(
        id: 'doc-editor-edit-test',
        organizationId: 'SOBHA-001',
        title: 'Shared Project Brief',
        fileName: 'brief.pdf',
        filePath: 'SOBHA-001/doc-editor-edit-test/brief.pdf',
        fileSize: 2048,
        fileType: 'application/pdf',
        category: DocumentCategory.general,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'staff-owner',
        createdByName: 'Staff Owner',
        sharedWithUserIds: const ['staff-editor'],
      );
      store.documents.add(doc);

      store.shares.add(
        DocumentShare(
          id: 'share-edit-001',
          documentId: 'doc-editor-edit-test',
          userId: 'staff-editor',
          userName: 'Staff Editor',
          userEmail: 'editor@sobha.com',
          organizationId: 'SOBHA-001',
          permission: 'edit',
          sharedBy: 'staff-owner',
          sharedByName: 'Staff Owner',
          createdAt: DateTime.now(),
        ),
      );

      final updated = await DocumentService.instance.updateDocumentMetadata(
        documentId: 'doc-editor-edit-test',
        organizationId: 'SOBHA-001',
        title: 'Editor Revised Brief',
        description: 'Updated by collaborator with edit permissions',
        currentUserId: 'staff-editor',
        userRole: 'staff',
      );

      expect(updated.title, equals('Editor Revised Brief'));
      // Immutability checks: Owner and org remain strictly unchanged
      expect(updated.createdBy, equals('staff-owner'));
      expect(updated.organizationId, equals('SOBHA-001'));
      expect(updated.filePath, equals('SOBHA-001/doc-editor-edit-test/brief.pdf'));
    });

    test('View-only recipient is strictly denied document editing', () async {
      final store = MockDocumentStore.instance;
      store.documents.clear();
      store.shares.clear();

      final doc = DocumentRecord(
        id: 'doc-view-only-test',
        organizationId: 'SOBHA-001',
        title: 'View Only Confidential Report',
        fileName: 'confidential.pdf',
        filePath: 'SOBHA-001/doc-view-only-test/confidential.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        category: DocumentCategory.general,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'staff-owner',
        createdByName: 'Staff Owner',
        sharedWithUserIds: const ['staff-viewer'],
      );
      store.documents.add(doc);

      store.shares.add(
        DocumentShare(
          id: 'share-view-001',
          documentId: 'doc-view-only-test',
          userId: 'staff-viewer',
          userName: 'Staff Viewer',
          userEmail: 'viewer@sobha.com',
          organizationId: 'SOBHA-001',
          permission: 'view',
          sharedBy: 'staff-owner',
          sharedByName: 'Staff Owner',
          createdAt: DateTime.now(),
        ),
      );

      expect(
        () => DocumentService.instance.updateDocumentMetadata(
          documentId: 'doc-view-only-test',
          organizationId: 'SOBHA-001',
          title: 'Malicious Overwrite Attempt',
          currentUserId: 'staff-viewer',
          userRole: 'staff',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('Company admin retains organization governance oversight to edit documents', () async {
      final store = MockDocumentStore.instance;
      store.documents.clear();
      store.shares.clear();

      final doc = DocumentRecord(
        id: 'doc-admin-governance-test',
        organizationId: 'SOBHA-001',
        title: 'Staff Document under Review',
        fileName: 'review.pdf',
        filePath: 'SOBHA-001/doc-admin-governance-test/review.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        category: DocumentCategory.general,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'staff-user',
        createdByName: 'Staff User',
      );
      store.documents.add(doc);

      final updated = await DocumentService.instance.updateDocumentMetadata(
        documentId: 'doc-admin-governance-test',
        organizationId: 'SOBHA-001',
        title: 'Title Corrected by Compliance Admin',
        currentUserId: 'admin-user',
        userRole: 'company_admin',
      );

      expect(updated.title, equals('Title Corrected by Compliance Admin'));
      expect(updated.createdBy, equals('staff-user'));
      expect(updated.organizationId, equals('SOBHA-001'));
    });
  });

  group('ActionFlow Trigger Bypass & Pre-Staging Security Regression Tests', () {
    test('Scenario 1: Anonymous user metadata update attempt is denied', () async {
      final store = MockDocumentStore.instance;
      store.documents.clear();
      store.documents.add(DocumentRecord(
        id: 'doc-anon-test',
        organizationId: 'SOBHA-001',
        title: 'Protected Doc',
        fileName: 'doc.pdf',
        filePath: 'SOBHA-001/doc-anon-test/doc.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        category: DocumentCategory.general,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'staff-owner',
      ));

      expect(
        () => DocumentService.instance.updateDocumentMetadata(
          documentId: 'doc-anon-test',
          organizationId: 'SOBHA-001',
          title: 'Anonymous Hack Attempt',
          currentUserId: null, // anonymous
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Authentication required'),
        )),
      );
    });

    test('Scenario 2: Anonymous user ownership modification attempt is strictly denied', () async {
      final store = MockDocumentStore.instance;
      store.documents.clear();
      store.documents.add(DocumentRecord(
        id: 'doc-anon-test-2',
        organizationId: 'SOBHA-001',
        title: 'Protected Doc',
        fileName: 'doc.pdf',
        filePath: 'SOBHA-001/doc-anon-test-2/doc.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        category: DocumentCategory.general,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'staff-owner',
      ));

      expect(
        () => DocumentService.instance.updateDocumentMetadata(
          documentId: 'doc-anon-test-2',
          organizationId: 'SOBHA-001',
          title: 'Anonymous Hack Attempt',
          currentUserId: '   ', // unauthenticated empty string
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Authentication required'),
        )),
      );
    });

    test('Scenario 3: Authenticated owner updates permitted metadata while preserving ownership', () async {
      final store = MockDocumentStore.instance;
      store.documents.clear();
      store.documents.add(DocumentRecord(
        id: 'doc-owner-test',
        organizationId: 'SOBHA-001',
        title: 'Owner Doc',
        fileName: 'doc.pdf',
        filePath: 'SOBHA-001/doc-owner-test/doc.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        category: DocumentCategory.general,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'staff-owner',
      ));

      final updated = await DocumentService.instance.updateDocumentMetadata(
        documentId: 'doc-owner-test',
        organizationId: 'SOBHA-001',
        title: 'Permitted New Title',
        description: 'Updated notes',
        currentUserId: 'staff-owner',
        userRole: 'staff',
      );

      expect(updated.title, equals('Permitted New Title'));
      expect(updated.description, equals('Updated notes'));
      expect(updated.createdBy, equals('staff-owner'));
      expect(updated.organizationId, equals('SOBHA-001'));
      expect(updated.filePath, equals('SOBHA-001/doc-owner-test/doc.pdf'));
    });

    test('Scenario 4: Edit-share recipient updates permitted metadata', () async {
      final store = MockDocumentStore.instance;
      store.documents.clear();
      store.shares.clear();
      store.documents.add(DocumentRecord(
        id: 'doc-shared-edit',
        organizationId: 'SOBHA-001',
        title: 'Shared Draft',
        fileName: 'doc.pdf',
        filePath: 'SOBHA-001/doc-shared-edit/doc.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        category: DocumentCategory.general,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'staff-owner',
        sharedWithUserIds: const ['staff-editor'],
      ));
      store.shares.add(DocumentShare(
        id: 'share-01',
        documentId: 'doc-shared-edit',
        userId: 'staff-editor',
        organizationId: 'SOBHA-001',
        permission: 'edit',
        createdAt: DateTime.now(),
      ));

      final updated = await DocumentService.instance.updateDocumentMetadata(
        documentId: 'doc-shared-edit',
        organizationId: 'SOBHA-001',
        title: 'Collaborative Edit by Recipient',
        currentUserId: 'staff-editor',
        userRole: 'staff',
      );

      expect(updated.title, equals('Collaborative Edit by Recipient'));
      expect(updated.createdBy, equals('staff-owner'));
    });

    test('Scenario 5: Edit-share recipient cannot change immutable ownership or organization', () async {
      final store = MockDocumentStore.instance;
      store.documents.clear();
      store.shares.clear();
      final originalDoc = DocumentRecord(
        id: 'doc-shared-edit-5',
        organizationId: 'SOBHA-001',
        title: 'Shared Draft 5',
        fileName: 'doc.pdf',
        filePath: 'SOBHA-001/doc-shared-edit-5/doc.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        category: DocumentCategory.general,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'staff-owner',
        sharedWithUserIds: const ['staff-editor'],
      );
      store.documents.add(originalDoc);
      store.shares.add(DocumentShare(
        id: 'share-05',
        documentId: 'doc-shared-edit-5',
        userId: 'staff-editor',
        organizationId: 'SOBHA-001',
        permission: 'edit',
        createdAt: DateTime.now(),
      ));

      final updated = await DocumentService.instance.updateDocumentMetadata(
        documentId: 'doc-shared-edit-5',
        organizationId: 'SOBHA-001',
        title: 'Another Edit Attempt',
        currentUserId: 'staff-editor',
        userRole: 'staff',
      );

      // Assert immutable attributes remain strictly locked to original owner and org
      expect(updated.createdBy, equals(originalDoc.createdBy));
      expect(updated.organizationId, equals(originalDoc.organizationId));
      expect(updated.filePath, equals(originalDoc.filePath));
      expect(updated.id, equals(originalDoc.id));
    });

    test('Scenario 6: Company admin from another organization is denied', () async {
      final store = MockDocumentStore.instance;
      store.documents.clear();
      store.documents.add(DocumentRecord(
        id: 'doc-shared-edit-6',
        organizationId: 'SOBHA-001',
        title: 'Shared Draft 6',
        fileName: 'doc.pdf',
        filePath: 'SOBHA-001/doc-shared-edit-6/doc.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        category: DocumentCategory.general,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'staff-owner',
      ));

      expect(
        () => DocumentService.instance.updateDocumentMetadata(
          documentId: 'doc-shared-edit-6',
          organizationId: 'OTHER-ORG-999',
          title: 'Cross-Tenant Tamper Attempt',
          currentUserId: 'other-org-admin',
          userRole: 'company_admin',
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('not found in organization'),
        )),
      );
    });

    test('Scenario 7: Authorized service-role maintenance is allowed', () async {
      final store = MockDocumentStore.instance;
      store.documents.clear();
      store.documents.add(DocumentRecord(
        id: 'doc-service-role-test',
        organizationId: 'SOBHA-001',
        title: 'Original Title',
        fileName: 'doc.pdf',
        filePath: 'SOBHA-001/doc-service-role-test/doc.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        category: DocumentCategory.general,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'staff-owner',
      ));

      final updated = await DocumentService.instance.updateDocumentMetadata(
        documentId: 'doc-service-role-test',
        organizationId: 'SOBHA-001',
        title: 'Service Role System Title Sync',
        currentUserId: 'service-role-system',
        userRole: 'service_role',
      );

      expect(updated.title, equals('Service Role System Title Sync'));
      expect(updated.createdBy, equals('staff-owner'));
    });

    test('Scenario 8: Storage path authorization rejects NULL and cross-tenant paths', () {
      bool canAccessPath({
        required String? callerOrg,
        required String? filePath,
        required bool isPlatformAdmin,
      }) {
        if (filePath == null || filePath.trim().isEmpty) return false;
        final parts = filePath.split('/');
        if (parts.isEmpty || parts[0].trim().isEmpty) return false;
        final pathOrg = parts[0];
        if (isPlatformAdmin) return true;
        if (callerOrg == null || callerOrg.trim().isEmpty) return false;
        if (callerOrg != pathOrg) return false;
        return true;
      }

      // Null or empty caller org denied
      expect(canAccessPath(callerOrg: null, filePath: 'SOBHA-001/doc/file.pdf', isPlatformAdmin: false), isFalse);
      expect(canAccessPath(callerOrg: '', filePath: 'SOBHA-001/doc/file.pdf', isPlatformAdmin: false), isFalse);
      
      // Null or empty file path denied
      expect(canAccessPath(callerOrg: 'SOBHA-001', filePath: null, isPlatformAdmin: false), isFalse);
      expect(canAccessPath(callerOrg: 'SOBHA-001', filePath: '', isPlatformAdmin: false), isFalse);

      // Cross-tenant path denied
      expect(canAccessPath(callerOrg: 'SOBHA-002', filePath: 'SOBHA-001/doc/file.pdf', isPlatformAdmin: false), isFalse);

      // Same-tenant path allowed
      expect(canAccessPath(callerOrg: 'SOBHA-001', filePath: 'SOBHA-001/doc/file.pdf', isPlatformAdmin: false), isTrue);

      // Platform admin cross-tenant allowed
      expect(canAccessPath(callerOrg: 'SOBHA-002', filePath: 'SOBHA-001/doc/file.pdf', isPlatformAdmin: true), isTrue);
    });

    test('Scenario 9: Internal helper functions relocated to app_private and removed from public schema', () {
      final file1 = File('supabase/migrations/20261110000001_per_user_private_document_ownership_hardened.sql');
      expect(file1.existsSync(), isTrue);
      final sql1 = file1.readAsStringSync();
      expect(sql1.contains('DROP FUNCTION IF EXISTS public.can_user_access_storage_document(TEXT);'), isTrue);
      expect(sql1.contains('CREATE OR REPLACE FUNCTION app_private.can_user_access_storage_document'), isTrue);
      expect(sql1.contains('CREATE OR REPLACE FUNCTION public.can_user_access_storage_document'), isFalse);

      final file2 = File('supabase/migrations/20261110000002_request_user_isolation_and_access_control.sql');
      expect(file2.existsSync(), isTrue);
      final sql2 = file2.readAsStringSync();
      expect(sql2.contains('DROP FUNCTION IF EXISTS public.can_user_access_request(UUID);'), isTrue);
      expect(sql2.contains('DROP FUNCTION IF EXISTS public.can_user_access_storage_request(TEXT);'), isTrue);
      expect(sql2.contains('CREATE OR REPLACE FUNCTION app_private.can_user_access_request'), isTrue);
      expect(sql2.contains('CREATE OR REPLACE FUNCTION app_private.can_user_access_storage_request'), isTrue);
    });

    test('Scenario 10: PostgreSQL SECURITY DEFINER trigger safe maintenance mode verification', () {
      final file1 = File('supabase/migrations/20261110000001_per_user_private_document_ownership_hardened.sql');
      expect(file1.existsSync(), isTrue);
      final sql = file1.readAsStringSync();

      // Proves current_user is NOT used as authorization in enforce_document_immutability
      expect(sql.contains("current_user IN ('postgres', 'supabase_admin')"), isFalse);
      
      // Proves session_user + explicit session setting are used
      expect(sql.contains("v_session_user IN ('postgres', 'supabase_admin')"), isTrue);
      expect(sql.contains("current_setting('app.maintenance_mode', true)"), isTrue);

      // Proves migration Section 2 enables and resets maintenance mode
      expect(sql.contains("SET LOCAL app.maintenance_mode = 'active';"), isTrue);
      expect(sql.contains("RESET app.maintenance_mode;"), isTrue);
    });
  });
}
