import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/models/team.dart';
import 'package:action_flow/models/document_record.dart';
import 'package:action_flow/services/document_service.dart';
import 'package:action_flow/services/user_service.dart';
import 'package:action_flow/widgets/documents/document_share_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const orgId = '00000000-0000-0000-0000-000000000001';
  const otherOrgId = '00000000-0000-0000-0000-000000000002';

  const staffAuthorId = 'staff-author-01';
  const managerAuthorId = 'manager-author-01';
  const deptHseId = 'dept-hse-001';
  const deptOpsId = 'dept-ops-001';

  late Person newlyCreatedManager;
  late Person newlyCreatedStaffSameDept;
  late Person newlyCreatedStaffOtherDept;
  late Person crossOrgUser;
  late Person inactiveStaff;
  late Person adminPortalUser;

  setUp(() {
    DocumentService.allowInMemoryStoreForTests = true;
    MockDocumentStore.instance.reset();
    UserService.instance.invalidateCache();

    newlyCreatedManager = Person(
      id: 'new-mgr-01',
      name: 'Newly Created Manager',
      email: 'new.mgr@sobha.test',
      phone: '+1 555-0101',
      type: PersonType.internalUser,
      designation: 'Operations Lead Manager',
      department: 'Operations',
      departmentId: deptOpsId,
      site: 'Site Alpha',
      siteId: 'site-a',
      isActive: true,
      role: UserRole.departmentManager,
      organizationId: orgId,
    );

    newlyCreatedStaffSameDept = Person(
      id: 'new-staff-same-dept',
      name: 'Newly Created Same Dept Staff',
      email: 'new.staff.hse@sobha.test',
      phone: '+1 555-0102',
      type: PersonType.internalUser,
      designation: 'Safety Inspector',
      department: 'HSE',
      departmentId: deptHseId,
      site: 'Site Alpha',
      siteId: 'site-a',
      isActive: true,
      role: UserRole.actionOwnerWorker,
      organizationId: orgId,
    );

    newlyCreatedStaffOtherDept = Person(
      id: 'new-staff-other-dept',
      name: 'Newly Created Other Dept Staff',
      email: 'new.staff.ops@sobha.test',
      phone: '+1 555-0103',
      type: PersonType.internalUser,
      designation: 'Plant Operator',
      department: 'Operations',
      departmentId: deptOpsId,
      site: 'Site Alpha',
      siteId: 'site-a',
      isActive: true,
      role: UserRole.actionOwnerWorker,
      organizationId: orgId,
    );

    crossOrgUser = Person(
      id: 'cross-org-user-01',
      name: 'Tenant 2 External Staff',
      email: 'external@tenant2.test',
      phone: '+1 555-0104',
      type: PersonType.internalUser,
      designation: 'Worker',
      department: 'HSE',
      departmentId: deptHseId,
      site: 'Site Beta',
      siteId: 'site-b',
      isActive: true,
      role: UserRole.actionOwnerWorker,
      organizationId: otherOrgId,
    );

    inactiveStaff = Person(
      id: 'inactive-staff-01',
      name: 'Deactivated Employee',
      email: 'inactive@sobha.test',
      phone: '+1 555-0105',
      type: PersonType.internalUser,
      designation: 'Field Worker',
      department: 'HSE',
      departmentId: deptHseId,
      site: 'Site Alpha',
      siteId: 'site-a',
      isActive: false,
      role: UserRole.actionOwnerWorker,
      organizationId: orgId,
    );

    adminPortalUser = Person(
      id: 'admin-portal-01',
      name: 'Company System Administrator',
      email: 'admin@sobha.test',
      phone: '+1 555-0106',
      type: PersonType.internalUser,
      designation: 'System Administrator',
      department: 'Executive',
      departmentId: 'dept-exec',
      site: 'HQ',
      siteId: 'site-hq',
      isActive: true,
      role: UserRole.admin,
      organizationId: orgId,
    );
  });

  tearDown(() {
    DocumentService.allowInMemoryStoreForTests = false;
  });

  group('Global User Directory & Document Sharing Integration Tests', () {
    testWidgets('1. Staff Author: Newly created Manager and Same-Dept Staff appear; Cross-org, Inactive, Admin & Other-Dept Staff excluded', (tester) async {
      MockPeopleStore.instance.people
        ..clear()
        ..addAll([
          newlyCreatedManager,
          newlyCreatedStaffSameDept,
          newlyCreatedStaffOtherDept,
          crossOrgUser,
          inactiveStaff,
          adminPortalUser,
        ]);

      final staffDoc = DocumentRecord(
        id: 'doc-staff-hse-01',
        organizationId: orgId,
        title: 'Safety Inspection Log',
        fileName: 'safety_log.pdf',
        filePath: '$orgId/doc-staff-hse-01/safety_log.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        createdBy: staffAuthorId,
        createdByName: 'John Staff Author',
        departmentId: deptHseId,
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
              currentUserId: staffAuthorId,
              currentUserName: 'John Staff Author',
              currentUserRole: 'staff',
              currentUserDepartment: 'HSE',
              currentUserDepartmentId: deptHseId,
              onSharesUpdated: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open user dropdown
      expect(find.text('Select Colleague / Manager'), findsOneWidget);
      await tester.tap(find.text('Select Colleague / Manager'));
      await tester.pumpAndSettle();

      // 1. Newly created Manager appears
      expect(find.textContaining('Newly Created Manager'), findsWidgets);

      // 2. Newly created Staff in same department appears
      expect(find.textContaining('Newly Created Same Dept Staff'), findsWidgets);

      // 3. Cross-department staff excluded for staff author
      expect(find.textContaining('Newly Created Other Dept Staff'), findsNothing);

      // 4. Cross-org user excluded
      expect(find.textContaining('Tenant 2 External Staff'), findsNothing);

      // 5. Inactive staff excluded
      expect(find.textContaining('Deactivated Employee'), findsNothing);

      // 6. Admin Portal user excluded from staff sharing
      expect(find.textContaining('Company System Administrator'), findsNothing);
    });

    testWidgets('2. Manager Author: Newly created Manager and Staff appear according to Manager scopes; Cross-org and Inactive excluded', (tester) async {
      MockPeopleStore.instance.people
        ..clear()
        ..addAll([
          newlyCreatedManager,
          newlyCreatedStaffSameDept,
          newlyCreatedStaffOtherDept,
          crossOrgUser,
          inactiveStaff,
          adminPortalUser,
        ]);

      final managerDoc = DocumentRecord(
        id: 'doc-mgr-01',
        organizationId: orgId,
        title: 'Operational Guidelines',
        fileName: 'ops_guidelines.pdf',
        filePath: '$orgId/doc-mgr-01/ops_guidelines.pdf',
        fileSize: 2048,
        fileType: 'application/pdf',
        createdBy: managerAuthorId,
        createdByName: 'Jane Manager Author',
        departmentId: deptOpsId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DocumentShareDialog(
              document: managerDoc,
              organizationId: orgId,
              currentUserId: managerAuthorId,
              currentUserName: 'Jane Manager Author',
              currentUserRole: 'manager',
              currentUserDepartment: 'Operations',
              currentUserDepartmentId: deptOpsId,
              allowedDepartmentIds: {deptHseId, deptOpsId},
              onSharesUpdated: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open user dropdown
      expect(find.text('Select Colleague / Manager'), findsOneWidget);
      await tester.tap(find.text('Select Colleague / Manager'));
      await tester.pumpAndSettle();

      // Newly created manager appears
      expect(find.textContaining('Newly Created Manager'), findsWidgets);

      // Newly created staff in scoped departments appear
      expect(find.textContaining('Newly Created Same Dept Staff'), findsWidgets);
      expect(find.textContaining('Newly Created Other Dept Staff'), findsWidgets);

      // Cross-organization user strictly excluded
      expect(find.textContaining('Tenant 2 External Staff'), findsNothing);

      // Inactive user strictly excluded
      expect(find.textContaining('Deactivated Employee'), findsNothing);
    });

    testWidgets('3. Newly created user added dynamically appears upon cache invalidation without re-login', (tester) async {
      MockPeopleStore.instance.people
        ..clear()
        ..add(newlyCreatedManager);

      final doc = DocumentRecord(
        id: 'doc-dynamic-01',
        organizationId: orgId,
        title: 'Dynamic Test Document',
        fileName: 'dynamic.pdf',
        filePath: '$orgId/doc-dynamic-01/dynamic.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        createdBy: staffAuthorId,
        createdByName: 'John Staff Author',
        departmentId: deptHseId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DocumentShareDialog(
              document: doc,
              organizationId: orgId,
              currentUserId: staffAuthorId,
              currentUserName: 'John Staff Author',
              currentUserRole: 'staff',
              currentUserDepartment: 'HSE',
              currentUserDepartmentId: deptHseId,
              onSharesUpdated: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open dropdown and verify newlyCreatedSameDeptStaff is NOT present initially
      await tester.tap(find.text('Select Colleague / Manager'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Newly Created Same Dept Staff'), findsNothing);

      // Close dropdown
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Add user dynamically to store
      MockPeopleStore.instance.people.add(newlyCreatedStaffSameDept);

      // Re-mount dialog to simulate reopening
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DocumentShareDialog(
              key: const ValueKey('dialog_second_mount'),
              document: doc,
              organizationId: orgId,
              currentUserId: staffAuthorId,
              currentUserName: 'John Staff Author',
              currentUserRole: 'staff',
              currentUserDepartment: 'HSE',
              currentUserDepartmentId: deptHseId,
              onSharesUpdated: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select Colleague / Manager'));
      await tester.pumpAndSettle();

      // Newly created user is now present!
      expect(find.textContaining('Newly Created Same Dept Staff'), findsWidgets);

      // Clean up dropdown
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    });

    testWidgets('4. Internal share adding and revocation updates active shares list', (tester) async {
      MockPeopleStore.instance.people
        ..clear()
        ..addAll([newlyCreatedManager, newlyCreatedStaffSameDept]);

      final doc = DocumentRecord(
        id: 'doc-share-action-01',
        organizationId: orgId,
        title: 'Actionable Document',
        fileName: 'actionable.pdf',
        filePath: '$orgId/doc-share-action-01/actionable.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        createdBy: staffAuthorId,
        createdByName: 'John Staff Author',
        departmentId: deptHseId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DocumentShareDialog(
              document: doc,
              organizationId: orgId,
              currentUserId: staffAuthorId,
              currentUserName: 'John Staff Author',
              currentUserRole: 'staff',
              currentUserDepartment: 'HSE',
              currentUserDepartmentId: deptHseId,
              onSharesUpdated: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initial active shares count should be 0
      expect(find.text('Active Shares (0)'), findsOneWidget);
      expect(find.text('This document is not currently shared with any individual user.'), findsOneWidget);

      // Select newlyCreatedStaffSameDept
      await tester.tap(find.text('Select Colleague / Manager'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Newly Created Same Dept Staff').last);
      await tester.pumpAndSettle();

      // Tap 'Share' button
      final shareButton = find.byKey(const Key('documents_confirm_share_button'));
      expect(shareButton, findsOneWidget);
      await tester.tap(shareButton);
      await tester.pumpAndSettle();

      // Verify that the user now appears under "Active Shares (1)"
      expect(find.text('Active Shares (1)'), findsOneWidget);
      expect(find.textContaining('Newly Created Same Dept Staff'), findsWidgets);

      // Verify revocation
      final revokeButton = find.widgetWithText(TextButton, 'Revoke').first;
      await tester.tap(revokeButton);
      await tester.pumpAndSettle();

      // Active shares now back to 0
      expect(find.text('Active Shares (0)'), findsOneWidget);
      expect(find.text('This document is not currently shared with any individual user.'), findsOneWidget);
    });

    testWidgets('5. External share tokens remain strictly separate from internal directory', (tester) async {
      MockPeopleStore.instance.people
        ..clear()
        ..addAll([newlyCreatedManager]);

      final doc = DocumentRecord(
        id: 'doc-ext-token-01',
        organizationId: orgId,
        title: 'External Share Doc',
        fileName: 'external.pdf',
        filePath: '$orgId/doc-ext-token-01/external.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        createdBy: managerAuthorId,
        createdByName: 'Jane Manager Author',
        departmentId: deptOpsId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DocumentShareDialog(
              document: doc,
              organizationId: orgId,
              currentUserId: managerAuthorId,
              currentUserName: 'Jane Manager Author',
              currentUserRole: 'manager',
              currentUserDepartment: 'Operations',
              currentUserDepartmentId: deptOpsId,
              allowedDepartmentIds: {deptOpsId},
              onSharesUpdated: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to "External Links" tab
      final externalTab = find.text('External Links');
      expect(externalTab, findsOneWidget);
      await tester.tap(externalTab);
      await tester.pumpAndSettle();

      // Verify external recipient fields are present and internal directory picker is hidden
      expect(find.text('Recipient Email *'), findsOneWidget);
      expect(find.text('Select Colleague / Manager'), findsNothing);
    });
  });
}
