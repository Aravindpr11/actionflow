import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/models/team.dart';
import 'package:action_flow/models/document_record.dart';
import 'package:action_flow/services/document_service.dart';
import 'package:action_flow/widgets/documents/document_share_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DocumentService.allowInMemoryStoreForTests = true;
    MockDocumentStore.instance.reset();
  });

  tearDown(() {
    DocumentService.allowInMemoryStoreForTests = false;
  });

  group('Manager Portal & Staff Document Sharing Scope Regression Tests', () {
    const orgId = '00000000-0000-0000-0000-000000000001';
    const managerId = '878d9145-7764-411f-8d26-f30f01e99e79';
    const deptHse = 'f0ad05aa-c85a-40e5-b309-19f1e6629e7a';
    const deptTest = '6000544e-dfe7-4911-b2cc-4c4bebead468';
    const deptAccounts = '6a8ce19a-3694-4743-8f54-96d57929de73';
    const deptMaintenance = 'dept-maint-001';

    // Staff in manager's authorized scope (deptTest)
    final staffInTestScope = Person(
      id: '0438e1ed-03ac-4aba-ba59-6a6579e2d874',
      name: 'Test Staff',
      email: 'test.staff@sobha.demo',
      phone: '+91 90000 00001',
      type: PersonType.internalUser,
      designation: 'HSE',
      department: 'test',
      departmentId: deptTest,
      site: 'test',
      siteId: 'site-test-1',
      isActive: true,
      role: UserRole.actionOwnerWorker,
      organizationId: orgId,
    );

    // Staff in manager's primary department (deptHse)
    final staffInHseScope = Person(
      id: 'staff-hse-01',
      name: 'HSE Colleague',
      email: 'hse.colleague@sobha.demo',
      phone: '+91 90000 00002',
      type: PersonType.internalUser,
      designation: 'Safety Officer',
      department: 'HSE / Safety',
      departmentId: deptHse,
      site: 'test',
      siteId: 'site-test-1',
      isActive: true,
      role: UserRole.actionOwnerWorker,
      organizationId: orgId,
    );

    // Staff in unscoped department (Maintenance)
    final staffInUnscopedDept = Person(
      id: 'staff-maint-01',
      name: 'Maintenance Staff',
      email: 'maint.staff@sobha.demo',
      phone: '+91 90000 00003',
      type: PersonType.internalUser,
      designation: 'Technician',
      department: 'Maintenance',
      departmentId: deptMaintenance,
      site: 'test',
      siteId: 'site-test-1',
      isActive: true,
      role: UserRole.actionOwnerWorker,
      organizationId: orgId,
    );

    // Inactive staff in manager scope
    final inactiveStaff = Person(
      id: 'staff-inactive-01',
      name: 'Inactive Staff',
      email: 'inactive@sobha.demo',
      phone: '+91 90000 00004',
      type: PersonType.internalUser,
      designation: 'Worker',
      department: 'test',
      departmentId: deptTest,
      site: 'test',
      siteId: 'site-test-1',
      isActive: false,
      role: UserRole.actionOwnerWorker,
      organizationId: orgId,
    );

    // Manager in the same organization
    final peerManager = Person(
      id: 'peer-mgr-01',
      name: 'Operations Manager',
      email: 'ops.mgr@sobha.demo',
      phone: '+91 90000 00005',
      type: PersonType.internalUser,
      designation: 'Operations Manager',
      department: 'Operations',
      departmentId: 'dept-ops-001',
      site: 'North Plant',
      siteId: 'site-np-1',
      isActive: true,
      role: UserRole.departmentManager,
      organizationId: orgId,
    );

    // Company Admin
    final companyAdmin = Person(
      id: 'admin-01',
      name: 'Sobha Admin',
      email: 'admin@sobha.demo',
      phone: '+91 90000 00006',
      type: PersonType.internalUser,
      designation: 'Administrator',
      department: 'Corporate',
      departmentId: 'dept-corp-001',
      site: 'HQ',
      siteId: 'site-hq-1',
      isActive: true,
      role: UserRole.admin,
      organizationId: orgId,
    );

    test('1. DocumentService.uploadDocument preserves departmentId = NULL for general repository documents', () async {
      final docService = DocumentService.instance;
      final doc = await docService.uploadDocument(
        organizationId: orgId,
        title: 'General HSSE Guideline 2026',
        fileName: 'guideline.pdf',
        fileBytes: [1, 2, 3, 4],
        category: DocumentCategory.general,
        actionId: null,
        departmentId: null, // Genuinely general document
        userId: managerId,
        userName: 'Manager',
      );

      expect(doc.departmentId, isNull);
      expect(doc.actionId, isNull);
    });

    test('2. DocumentService.uploadDocument applies action departmentId for action-linked documents', () async {
      final docService = DocumentService.instance;
      final doc = await docService.uploadDocument(
        organizationId: orgId,
        title: 'Rig 4 Inspection Evidence',
        fileName: 'evidence.pdf',
        fileBytes: [1, 2, 3, 4],
        category: DocumentCategory.general,
        actionId: 'act-test-01',
        actionNumber: 'ACT-1004',
        departmentId: deptTest, // Linked action's department
        userId: managerId,
        userName: 'Manager',
      );

      expect(doc.departmentId, equals(deptTest));
      expect(doc.actionId, equals('act-test-01'));
    });

    test('3. DocumentService.shareDocumentInternal allows sharing general document (departmentId = NULL) with scoped staff', () async {
      final docService = DocumentService.instance;
      final doc = await docService.uploadDocument(
        organizationId: orgId,
        title: 'Annual Company Policy',
        fileName: 'policy.pdf',
        fileBytes: [1, 2, 3],
        category: DocumentCategory.policies,
        departmentId: null,
        userId: managerId,
        userName: 'Manager',
      );

      // Share with staff in test department
      final share = await docService.shareDocumentInternal(
        documentId: doc.id,
        organizationId: orgId,
        userId: staffInTestScope.id,
        userName: staffInTestScope.name,
        userEmail: staffInTestScope.email,
        permission: 'view',
        sharedBy: managerId,
        sharedByName: 'Manager',
        callerRole: 'manager',
        allowedDepartmentIds: {deptHse, deptTest, deptAccounts},
        recipientDepartmentId: staffInTestScope.departmentId,
        recipientRole: staffInTestScope.roleLabel,
        recipientIsActive: staffInTestScope.isActive,
        recipientOrganizationId: staffInTestScope.organizationId,
      );

      expect(share, isNotNull);
      final shares = await docService.fetchDocumentShares(documentId: doc.id, organizationId: orgId);
      expect(shares.length, equals(1));
      expect(shares.first.userId, equals(staffInTestScope.id));
    });

    test('4. DocumentService.shareDocumentInternal allows sharing department document with staff in matching department', () async {
      final docService = DocumentService.instance;
      final doc = await docService.uploadDocument(
        organizationId: orgId,
        title: 'Test Department SOP',
        fileName: 'test_sop.pdf',
        fileBytes: [1, 2, 3],
        category: DocumentCategory.policies,
        departmentId: deptTest,
        userId: managerId,
        userName: 'Manager',
      );

      // Share with staff in matching department (deptTest)
      final share = await docService.shareDocumentInternal(
        documentId: doc.id,
        organizationId: orgId,
        userId: staffInTestScope.id,
        userName: staffInTestScope.name,
        userEmail: staffInTestScope.email,
        permission: 'view',
        sharedBy: managerId,
        sharedByName: 'Manager',
        callerRole: 'manager',
        recipientDepartmentId: staffInTestScope.departmentId,
        recipientRole: staffInTestScope.roleLabel,
        recipientIsActive: staffInTestScope.isActive,
        recipientOrganizationId: staffInTestScope.organizationId,
      );

      expect(share, isNotNull);
      final shares = await docService.fetchDocumentShares(documentId: doc.id, organizationId: orgId);
      expect(shares.length, equals(1));
      expect(shares.first.userId, equals(staffInTestScope.id));
    });

    test('5. DocumentService.shareDocumentInternal rejects sharing department document with staff outside department', () async {
      final docService = DocumentService.instance;
      final doc = await docService.uploadDocument(
        organizationId: orgId,
        title: 'HSE Isolated Checklist',
        fileName: 'hse_checklist.pdf',
        fileBytes: [1, 2, 3],
        category: DocumentCategory.auditChecklists,
        departmentId: deptHse, // Scoped to HSE / Safety
        userId: managerId,
        userName: 'Manager',
      );

      // Attempt to share with staff in department 'test' (violates department isolation trigger)
      expect(
        () async => await docService.shareDocumentInternal(
          documentId: doc.id,
          organizationId: orgId,
          userId: staffInTestScope.id,
          userName: staffInTestScope.name,
          userEmail: staffInTestScope.email,
          permission: 'view',
          sharedBy: managerId,
          sharedByName: 'Manager',
          callerRole: 'manager',
          recipientDepartmentId: staffInTestScope.departmentId, // deptTest != deptHse
          recipientRole: staffInTestScope.roleLabel,
          recipientIsActive: staffInTestScope.isActive,
          recipientOrganizationId: staffInTestScope.organizationId,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Department Isolation Violation'),
        )),
      );
    });

    test('6. DocumentService.shareDocumentInternal allows sharing department document with manager/admin across departments', () async {
      final docService = DocumentService.instance;
      final doc = await docService.uploadDocument(
        organizationId: orgId,
        title: 'HSE Department Audit',
        fileName: 'audit.pdf',
        fileBytes: [1, 2, 3],
        category: DocumentCategory.auditChecklists,
        departmentId: deptHse,
        userId: managerId,
        userName: 'Manager',
      );

      // Share with peer manager in Operations department
      final share = await docService.shareDocumentInternal(
        documentId: doc.id,
        organizationId: orgId,
        userId: peerManager.id,
        userName: peerManager.name,
        userEmail: peerManager.email,
        permission: 'download',
        sharedBy: managerId,
        sharedByName: 'Manager',
        callerRole: 'manager',
        recipientDepartmentId: peerManager.departmentId,
        recipientRole: peerManager.roleLabel,
        recipientIsActive: peerManager.isActive,
        recipientOrganizationId: peerManager.organizationId,
      );

      expect(share, isNotNull);
      final shares = await docService.fetchDocumentShares(documentId: doc.id, organizationId: orgId);
      expect(shares.length, equals(1));
      expect(shares.first.userId, equals(peerManager.id));
    });

    testWidgets('7. Manager Portal sharing modal shows scoped staff & managers for general document, hides unscoped and inactive staff', (tester) async {
      final List<Person> allCandidateUsers = [
        staffInTestScope,     // Scoped staff (deptTest) -> SHOULD BE VISIBLE
        staffInHseScope,      // Primary dept staff (deptHse) -> SHOULD BE VISIBLE
        staffInUnscopedDept,  // Unscoped staff (Maintenance) -> MUST BE HIDDEN
        inactiveStaff,        // Inactive staff -> MUST BE HIDDEN
        peerManager,          // Manager -> SHOULD BE VISIBLE
        companyAdmin,         // Admin -> SHOULD BE VISIBLE
      ];

      MockPeopleStore.instance.people
        ..clear()
        ..addAll(allCandidateUsers);

      final generalDoc = DocumentRecord(
        id: 'doc-gen-99',
        organizationId: orgId,
        title: 'General Company Safety Manual',
        fileName: 'safety_manual.pdf',
        filePath: '$orgId/doc-gen-99/safety_manual.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        createdBy: managerId,
        createdByName: 'Manager',
        departmentId: null, // Genuinely general
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Manager has authorized scopes for deptHse and deptTest
      final managerAllowedScopes = {deptHse, deptTest, deptAccounts};

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                return ElevatedButton(
                  key: const Key('open_share_button'),
                  onPressed: () {
                    showDialog(
                      context: ctx,
                      builder: (modalCtx) {
                        return DocumentShareDialog(
                          document: generalDoc,
                          organizationId: orgId,
                          currentUserId: managerId,
                          currentUserName: 'Manager',
                          allowedDepartmentIds: managerAllowedScopes,
                          onSharesUpdated: () {},
                        );
                      },
                    );
                  },
                  child: const Text('Open Share'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open_share_button')));
      await tester.pumpAndSettle();

      // Modal should be open
      expect(find.text('Select colleagues or managers in your organization:'), findsOneWidget);

      // Staff dropdown should show 'Select Colleague / Manager' (not 'No eligible recipients found')
      expect(find.text('Select Colleague / Manager'), findsOneWidget);
      expect(find.text('No eligible recipients found'), findsNothing);

      // Tap dropdown to verify available items
      await tester.tap(find.text('Select Colleague / Manager'));
      await tester.pumpAndSettle();

      // Verify scoped staff are present
      expect(find.textContaining('Test Staff'), findsWidgets);
      expect(find.textContaining('HSE Colleague'), findsWidgets);

      // Verify managers and admins are present
      expect(find.textContaining('Operations Manager'), findsWidgets);
      expect(find.textContaining('Sobha Admin'), findsWidgets);

      // Verify unscoped and inactive staff are strictly excluded
      expect(find.textContaining('Maintenance Staff'), findsNothing);
      expect(find.textContaining('Inactive Staff'), findsNothing);
    });

    testWidgets('8. Staff Portal sharing (DocumentShareDialog) preserves staff department isolation and manager discovery', (tester) async {
      final List<Person> allCandidateUsers = [
        staffInTestScope,     // Same department staff (deptTest) -> VISIBLE
        staffInHseScope,      // Cross-department staff (deptHse) -> EXCLUDED
        staffInUnscopedDept,  // Cross-department staff (deptMaintenance) -> EXCLUDED
        peerManager,          // Manager -> VISIBLE
        companyAdmin,         // Admin -> VISIBLE
        inactiveStaff,        // Inactive -> EXCLUDED
      ];

      MockPeopleStore.instance.people
        ..clear()
        ..addAll(allCandidateUsers);

      final staffDoc = DocumentRecord(
        id: 'doc-staff-01',
        organizationId: orgId,
        title: 'Toolbox Meeting Minutes',
        fileName: 'minutes.pdf',
        filePath: '$orgId/doc-staff-01/minutes.pdf',
        fileSize: 512,
        fileType: 'application/pdf',
        createdBy: staffInTestScope.id,
        createdByName: staffInTestScope.name,
        departmentId: deptTest,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DocumentShareDialog(
              document: staffDoc,
              organizationId: orgId,
              currentUserId: staffInTestScope.id,
              currentUserName: staffInTestScope.name,
              currentUserRole: 'staff',
              currentUserDepartment: 'test',
              currentUserDepartmentId: deptTest,
              onSharesUpdated: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Staff share dialog should open and find eligible recipients
      expect(find.text('Select Colleague / Manager'), findsOneWidget);
      expect(find.text('No eligible recipients found'), findsNothing);

      // Tap dropdown to verify items
      await tester.tap(find.text('Select Colleague / Manager'));
      await tester.pumpAndSettle();

      // Eligible Department Managers remain visible across departments
      expect(find.textContaining('Operations Manager'), findsWidgets);

      // Admin Portal accounts (System Administrator / Admin) are strictly hidden from Staff Portal sharing
      expect(find.textContaining('Sobha Admin'), findsNothing);

      // Cross-department staff are hidden
      expect(find.textContaining('HSE Colleague'), findsNothing);
      expect(find.textContaining('Maintenance Staff'), findsNothing);
      expect(find.textContaining('Inactive Staff'), findsNothing);
    });
  });
}

