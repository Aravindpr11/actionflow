import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/models/team.dart';
import 'package:action_flow/models/document_record.dart';
import 'package:action_flow/services/document_service.dart';
import 'package:action_flow/services/email_service.dart';
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
    EmailService.mockSendHandler = null;
  });

  group('Staff Portal Document Sharing — Admin Hiding & Recipient Eligibility', () {
    const orgId = '00000000-0000-0000-0000-000000000001';
    const deptHse = 'dept-hse-001';
    const deptMaintenance = 'dept-maint-001';

    final staffCaller = Person(
      id: 'staff-caller-01',
      name: 'John Maintenance',
      email: 'john.maint@sobha.demo',
      phone: '+91 90000 00001',
      type: PersonType.internalUser,
      designation: 'Maintenance Technician',
      department: 'Maintenance',
      departmentId: deptMaintenance,
      isActive: true,
      role: UserRole.actionOwnerWorker,
      organizationId: orgId,
    );

    final sameDeptColleague = Person(
      id: 'staff-colleague-01',
      name: 'Maintenance Colleague',
      email: 'colleague.maint@sobha.demo',
      phone: '+91 90000 00002',
      type: PersonType.internalUser,
      designation: 'Electrician',
      department: 'Maintenance',
      departmentId: deptMaintenance,
      isActive: true,
      role: UserRole.actionOwnerWorker,
      organizationId: orgId,
    );

    final crossDeptStaff = Person(
      id: 'staff-hse-01',
      name: 'HSE Safety Officer',
      email: 'officer.hse@sobha.demo',
      phone: '+91 90000 00003',
      type: PersonType.internalUser,
      designation: 'Safety Officer',
      department: 'HSE',
      departmentId: deptHse,
      isActive: true,
      role: UserRole.actionOwnerWorker,
      organizationId: orgId,
    );

    final deptManager = Person(
      id: 'mgr-hse-01',
      name: 'HSE Department Manager',
      email: 'manager.hse@sobha.demo',
      phone: '+91 90000 00004',
      type: PersonType.internalUser,
      designation: 'HSE Manager',
      department: 'HSE',
      departmentId: deptHse,
      isActive: true,
      role: UserRole.departmentManager,
      organizationId: orgId,
    );

    final systemAdmin = Person(
      id: 'admin-sys-01',
      name: 'Sobha Admin',
      email: 'sobha.admin@sobha.demo',
      phone: '+91 90000 00005',
      type: PersonType.internalUser,
      designation: 'Infra Head',
      department: '',
      departmentId: null,
      isActive: true,
      role: UserRole.admin,
      organizationId: orgId,
    );

    final companyAdmin = Person(
      id: 'admin-co-01',
      name: 'Company Admin User',
      email: 'co.admin@sobha.demo',
      phone: '+91 90000 00006',
      type: PersonType.internalUser,
      designation: 'Company Administrator',
      department: 'Corporate',
      departmentId: 'dept-corp',
      isActive: true,
      role: UserRole.admin,
      organizationId: orgId,
    );

    final platformAdmin = Person(
      id: 'admin-plat-01',
      name: 'Platform Administrator',
      email: 'plat.admin@sobha.demo',
      phone: '+91 90000 00007',
      type: PersonType.internalUser,
      designation: 'Platform Admin',
      department: '',
      departmentId: null,
      isActive: true,
      role: UserRole.admin,
      organizationId: orgId,
    );

    final inactiveManager = Person(
      id: 'mgr-inactive-01',
      name: 'Former HSE Manager',
      email: 'former.mgr@sobha.demo',
      phone: '+91 90000 00008',
      type: PersonType.internalUser,
      designation: 'Former Manager',
      department: 'HSE',
      departmentId: deptHse,
      isActive: false,
      role: UserRole.departmentManager,
      organizationId: orgId,
    );

    testWidgets('Staff Portal share dialog strictly hides admin-portal accounts while keeping department managers and same-department colleagues', (tester) async {
      MockPeopleStore.instance.people
        ..clear()
        ..addAll([
          staffCaller,
          sameDeptColleague,
          crossDeptStaff,
          deptManager,
          systemAdmin,
          companyAdmin,
          platformAdmin,
          inactiveManager,
        ]);

      final doc = DocumentRecord(
        id: 'doc-maint-01',
        organizationId: orgId,
        title: 'Maintenance SOP Guide',
        fileName: 'maint_sop.pdf',
        filePath: '$orgId/doc-maint-01/maint_sop.pdf',
        fileSize: 1024,
        fileType: 'application/pdf',
        createdBy: staffCaller.id,
        createdByName: staffCaller.name,
        departmentId: deptMaintenance,
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
              currentUserId: staffCaller.id,
              currentUserName: staffCaller.name,
              currentUserRole: 'staff',
              currentUserDepartment: 'Maintenance',
              currentUserDepartmentId: deptMaintenance,
              onSharesUpdated: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Dropdown should be loaded with eligible recipients
      expect(find.text('Select Colleague / Manager'), findsOneWidget);
      expect(find.text('No eligible recipients found'), findsNothing);

      // Open the dropdown
      await tester.tap(find.text('Select Colleague / Manager'));
      await tester.pumpAndSettle();

      // 1. ELIGIBLE Department Manager across departments must be visible
      expect(find.textContaining('HSE Department Manager'), findsWidgets);

      // 2. ELIGIBLE same-department colleague must be visible
      expect(find.textContaining('Maintenance Colleague'), findsWidgets);

      // 3. ADMIN PORTAL USERS MUST BE STRICTLY HIDDEN
      expect(find.textContaining('Sobha Admin'), findsNothing);
      expect(find.textContaining('Company Admin User'), findsNothing);
      expect(find.textContaining('Platform Administrator'), findsNothing);

      // 4. CROSS-DEPARTMENT STAFF MUST BE EXCLUDED
      expect(find.textContaining('HSE Safety Officer'), findsNothing);

      // 5. INACTIVE USERS & SELF MUST BE EXCLUDED
      expect(find.textContaining('Former HSE Manager'), findsNothing);
      expect(find.textContaining('John Maintenance'), findsNothing);
    });
  });

  group('External Document Sharing — Automated Email Delivery', () {
    const orgId = '00000000-0000-0000-0000-000000000001';
    const managerId = '878d9145-7764-411f-8d26-f30f01e99e79';

    final managerUser = Person(
      id: managerId,
      name: 'Manager',
      email: 'manager@sobha.demo',
      phone: '+91 90000 00001',
      type: PersonType.internalUser,
      designation: 'Operations Manager',
      department: 'HSE',
      departmentId: 'dept-hse',
      isActive: true,
      role: UserRole.departmentManager,
      organizationId: orgId,
    );

    final generalDoc = DocumentRecord(
      id: 'doc-general-01',
      organizationId: orgId,
      title: 'Site Safety Rules 2026',
      fileName: 'safety_rules.pdf',
      filePath: '$orgId/doc-general-01/safety_rules.pdf',
      fileSize: 2048,
      fileType: 'application/pdf',
      createdBy: managerId,
      createdByName: 'Manager',
      category: 'Guidelines',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    test('EmailService.sendExternalDocumentShareEmail generates valid payload and includes link, expiry, and notice', () async {
      Map<String, dynamic>? interceptedPayload;
      EmailService.mockSendHandler = (params) {
        interceptedPayload = params;
        return const EmailSendResult(
          isSuccess: true,
          status: 'sent',
          messageId: 'msg-ext-doc-999',
        );
      };

      final expires = DateTime.now().add(const Duration(days: 7));
      final result = await EmailService.instance.sendExternalDocumentShareEmail(
        recipientEmail: 'contractor@external-partner.com',
        recipientName: 'Alex Contractor',
        documentTitle: 'Site Safety Rules 2026',
        documentCategory: 'Guidelines',
        accessUrl: 'https://actionflow.enterprise/doc-access?token=sampleRawToken12345',
        expiresAt: expires,
        permission: 'view',
        senderName: 'Manager',
        organizationName: 'Sobha Constructions',
      );

      expect(result.isSuccess, isTrue);
      expect(result.status, equals('sent'));
      expect(result.messageId, equals('msg-ext-doc-999'));

      expect(interceptedPayload, isNotNull);
      expect(interceptedPayload!['to'], equals('contractor@external-partner.com'));
      expect(interceptedPayload!['subject'], contains('Site Safety Rules 2026'));
      expect(interceptedPayload!['recipient_type'], equals('external'));

      final html = interceptedPayload!['html'] as String;
      expect(html, contains('Alex Contractor'));
      expect(html, contains('Site Safety Rules 2026'));
      expect(html, contains('Guidelines'));
      expect(html, contains('View Only'));
      expect(html, contains('https://actionflow.enterprise/doc-access?token=sampleRawToken12345'));
      expect(html, contains('Security Notice'));

      final text = interceptedPayload!['text'] as String;
      expect(text, contains('https://actionflow.enterprise/doc-access?token=sampleRawToken12345'));
      expect(text, contains('Security Notice'));
    });

    testWidgets('Manager Portal Generate Link automatically emails external recipient and displays success state', (tester) async {
      MockPeopleStore.instance.people
        ..clear()
        ..add(managerUser);

      Map<String, dynamic>? sentEmailParams;
      EmailService.mockSendHandler = (params) {
        sentEmailParams = params;
        return const EmailSendResult(
          isSuccess: true,
          status: 'sent',
          messageId: 'msg-doc-share-001',
        );
      };

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DocumentShareDialog(
              document: generalDoc,
              organizationId: orgId,
              currentUserId: managerId,
              currentUserName: 'Manager',
              currentUserRole: 'manager',
              onSharesUpdated: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to External tab
      await tester.tap(find.text('External Links'));
      await tester.pumpAndSettle();

      // Enter recipient email
      final emailField = find.widgetWithText(TextField, 'Recipient Email *');
      expect(emailField, findsOneWidget);
      await tester.enterText(emailField, 'contractor.hse@external.demo');

      // Click Generate Secure Link
      final generateBtn = find.text('Generate Secure Link');
      expect(generateBtn, findsOneWidget);
      await tester.tap(generateBtn);
      await tester.pumpAndSettle();

      // Email service must have received the send request
      expect(sentEmailParams, isNotNull);
      expect(sentEmailParams!['to'], equals('contractor.hse@external.demo'));
      expect(sentEmailParams!['subject'], contains('Site Safety Rules 2026'));

      // UI must show the green success state indicating the link was emailed
      expect(find.textContaining('Secure Link Generated & Emailed to contractor.hse@external.demo'), findsOneWidget);
      expect(find.text('Copy Link'), findsOneWidget);

      // Verify token in store is hashed, and only 1 active token exists
      expect(MockDocumentStore.instance.externalTokens.length, equals(1));
      final createdToken = MockDocumentStore.instance.externalTokens.first;
      expect(createdToken.recipientEmail, equals('contractor.hse@external.demo'));
      expect(createdToken.tokenHash.length, equals(64));
    });

    testWidgets('When email delivery fails, UI shows explicit failure state and Retry button without creating duplicate tokens', (tester) async {
      MockPeopleStore.instance.people
        ..clear()
        ..add(managerUser);

      int emailAttemptCount = 0;
      EmailService.mockSendHandler = (params) {
        emailAttemptCount++;
        if (emailAttemptCount == 1) {
          // Simulate provider outage / API failure on first attempt
          return const EmailSendResult(
            isSuccess: false,
            status: 'failed',
            errorMessage: 'Resend API rate limit exceeded',
          );
        } else {
          // Succeed on retry
          return const EmailSendResult(
            isSuccess: true,
            status: 'sent',
            messageId: 'msg-retry-success-123',
          );
        }
      };

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DocumentShareDialog(
              document: generalDoc,
              organizationId: orgId,
              currentUserId: managerId,
              currentUserName: 'Manager',
              currentUserRole: 'manager',
              onSharesUpdated: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to External tab
      await tester.tap(find.text('External Links'));
      await tester.pumpAndSettle();

      // Enter recipient email
      final emailField = find.widgetWithText(TextField, 'Recipient Email *');
      await tester.enterText(emailField, 'contractor.audit@external.demo');

      // Click Generate Secure Link
      await tester.tap(find.text('Generate Secure Link'));
      await tester.pumpAndSettle();

      // First attempt failed: UI MUST show explicit failure state, NOT a success message
      expect(find.textContaining('Secure Link Generated (Email Delivery Failed)'), findsOneWidget);
      expect(find.textContaining('Resend API rate limit exceeded'), findsWidgets);
      expect(find.text('Retry Sending Email'), findsOneWidget);

      // Exactly 1 token was stored in the store
      expect(MockDocumentStore.instance.externalTokens.length, equals(1));

      // Dismiss previous SnackBar and scroll into view if needed
      ScaffoldMessenger.of(tester.element(find.byType(DocumentShareDialog))).clearSnackBars();
      await tester.pumpAndSettle();

      final retryBtn = find.text('Retry Sending Email');
      await tester.ensureVisible(retryBtn);
      await tester.pumpAndSettle();

      // Click Retry Sending Email
      await tester.tap(retryBtn, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Second email attempt executed
      expect(emailAttemptCount, equals(2));

      // UI switches to success state
      expect(find.textContaining('Secure Link Generated & Emailed to contractor.audit@external.demo'), findsOneWidget);

      // CRITICAL: Retrying must NOT have generated a second or duplicate token
      expect(MockDocumentStore.instance.externalTokens.length, equals(1));
    });
  });
}
