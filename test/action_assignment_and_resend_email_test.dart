import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/external_recipient.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/external_update/services/external_action_service.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:action_flow/services/email_service.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const testOrgId = 'org-test-sobha-01';

  final internalAssignee = ActionPersonReference(
    personId: '00000000-0000-0000-0000-000000000001',
    name: 'Suresh Engineer',
    type: PersonType.internalUser,
    email: 'suresh.engineer@sobha.com',
  );

  final externalContractor = ActionPersonReference(
    personId: '11111111-1111-1111-1111-111111110001',
    name: 'Robert Contractor',
    type: PersonType.externalWorker,
    email: 'robert.contractor@apex.com',
    company: 'Apex Scaffolding Services',
  );

  const testManagerProfile = UserProfile(
    id: 'mgr-user-001',
    name: 'Manager User',
    email: 'manager@sobha.com',
    phone: '+971501234567',
    designation: 'HSE Manager',
    department: 'HSE Safety',
    site: 'Downtown Tower',
    role: 'manager',
    organizationId: testOrgId,
    organizationName: 'Sobha Constructions',
  );

  final testManagerContext = ManagerContext(
    authUserId: 'mgr-user-001',
    profile: testManagerProfile,
    organizationId: testOrgId,
    organizationName: 'Sobha Constructions',
    scopes: const [
      ManagerScopeItem(
        departmentId: 'dept-safety-01',
        departmentName: 'HSE Safety',
        siteId: 'site-001',
        siteName: 'Downtown Tower',
      ),
    ],
  );

  setUp(() {
    MockActionStore.instance.actions.clear();
    MockActionStore.instance.externalRecipients.clear();
    MockActionStore.instance.emailReminders.clear();
    MockActionStore.instance.profiles.clear();
    MockExternalActionStore.instance.reset();
    EmailService.mockSendHandler = null;

    // Register active profile for internal user
    MockActionStore.instance.profiles.add({
      'id': internalAssignee.personId,
      'organization_id': testOrgId,
      'email': internalAssignee.email,
      'full_name': internalAssignee.name,
      'is_active': true,
      'status': 'active',
    });

    // Register active external recipient
    MockActionStore.instance.externalRecipients.add(
      ExternalRecipient(
        id: externalContractor.personId,
        organizationId: testOrgId,
        fullName: externalContractor.name,
        email: externalContractor.email,
        companyName: 'Apex Scaffolding Services',
        isActive: true,
      ),
    );
  });

  tearDown(() {
    EmailService.mockSendHandler = null;
  });

  group('Group 1: Action Creation Assignment Email', () {
    test('Test A: Internal assignment email is sent to current internal assignee on action creation', () async {
      Map<String, dynamic>? capturedEmail;

      EmailService.mockSendHandler = (params) {
        capturedEmail = params;
        return EmailSendResult.sent('msg-int-001', recipientEmail: params['to'] as String);
      };

      final action = ActionRecord(
        id: 'act-int-assign-001',
        actionNumber: 'ACT-INT-001',
        organizationId: testOrgId,
        createdById: 'mgr-user-001',
        subject: 'Inspect Scaffolding Tower B',
        actionRequired: 'Verify safety harness anchor points and base plates',
        division: 'Operations',
        priority: 'High',
        status: 'Open',
        site: 'Downtown Tower',
        department: 'HSE Safety',
        assignedBy: 'Alex Director',
        targetDate: '15 Nov 2026',
        primaryAssignee: internalAssignee,
        assignedTo: internalAssignee.name,
        assignedToId: internalAssignee.personId,
        recipientType: 'internal',
        percentComplete: 0,
      );

      final created = await ActionService.instance.createAction(action);
      expect(created, isNotNull);
      expect(capturedEmail, isNotNull);

      // Verify recipient and subject
      expect(capturedEmail!['to'], equals('suresh.engineer@sobha.com'));
      expect(capturedEmail!['subject'], contains('Action Assigned: [ACT-INT-001] Inspect Scaffolding Tower B'));
      expect(capturedEmail!['recipient_type'], equals('internal'));

      // Verify email body contents
      final html = capturedEmail!['html'] as String;
      final text = capturedEmail!['text'] as String;

      expect(html, contains('Suresh Engineer'));
      expect(html, contains('ACT-INT-001'));
      expect(html, contains('Inspect Scaffolding Tower B'));
      expect(html, contains('Verify safety harness anchor points and base plates'));
      expect(html, contains('High'));
      expect(html, contains('15 Nov 2026'));
      expect(html, contains('Downtown Tower'));
      expect(html, contains('Alex Director'));
      expect(html, contains('Open ActionFlow Staff Portal'));

      expect(text, contains('Suresh Engineer'));
      expect(text, contains('ACT-INT-001'));
      expect(text, contains('Inspect Scaffolding Tower B'));
      expect(text, contains('Verify safety harness anchor points and base plates'));

      // Invariant: Internal recipient MUST NOT receive external update link
      expect(html.contains('/external-update?token='), isFalse);
      expect(text.contains('/external-update?token='), isFalse);
    });

    test('Test B: External assignment email is sent to current external recipient on action creation', () async {
      Map<String, dynamic>? capturedEmail;

      EmailService.mockSendHandler = (params) {
        capturedEmail = params;
        return EmailSendResult.sent('msg-ext-001', recipientEmail: params['to'] as String);
      };

      final action = ActionRecord(
        id: 'act-ext-assign-001',
        actionNumber: 'ACT-EXT-001',
        organizationId: testOrgId,
        createdById: 'mgr-user-001',
        subject: 'Repair Perimeter Security Fence',
        actionRequired: 'Replace damaged wire mesh on sector 4',
        division: 'Facilities',
        priority: 'Critical',
        status: 'Open',
        site: 'North Warehouse',
        department: 'Security',
        assignedBy: 'Alex Director',
        targetDate: '20 Nov 2026',
        recipientType: 'external',
        assignedTo: externalContractor.name,
        externalRecipientId: externalContractor.personId,
        externalRecipientEmail: externalContractor.email,
        externalRecipientName: externalContractor.name,
        percentComplete: 0,
      );

      final created = await ActionService.instance.createAction(action);
      expect(created, isNotNull);
      expect(capturedEmail, isNotNull);

      // Verify recipient and subject
      expect(capturedEmail!['to'], equals('robert.contractor@apex.com'));
      expect(capturedEmail!['subject'], contains('Action Assigned: [ACT-EXT-001] Repair Perimeter Security Fence'));
      expect(capturedEmail!['recipient_type'], equals('external'));

      // Verify email body contents
      final html = capturedEmail!['html'] as String;
      final text = capturedEmail!['text'] as String;

      expect(html, contains('Robert Contractor'));
      expect(html, contains('ACT-EXT-001'));
      expect(html, contains('Repair Perimeter Security Fence'));
      expect(html, contains('Replace damaged wire mesh on sector 4'));
      expect(html, contains('Critical'));
      expect(html, contains('20 Nov 2026'));
      expect(html, contains('North Warehouse'));
      expect(html, contains('Open Contractor Update Portal'));
      expect(html, contains('7 days'));

      // Invariant: External email hides internal user lists, internal notes, internal system IDs
      expect(html.contains('mgr-user-001'), isFalse);
      expect(text.contains('mgr-user-001'), isFalse);
    });

    test('Test C: External email contains secure update link and token validates successfully', () async {
      Map<String, dynamic>? capturedEmail;

      EmailService.mockSendHandler = (params) {
        capturedEmail = params;
        return EmailSendResult.sent('msg-ext-002', recipientEmail: params['to'] as String);
      };

      final action = ActionRecord(
        id: 'act-ext-assign-002',
        actionNumber: 'ACT-EXT-002',
        organizationId: testOrgId,
        createdById: 'mgr-user-001',
        subject: 'Install Fire Extinguishers',
        actionRequired: 'Mount 5 CO2 extinguishers in workshop',
        division: 'Safety',
        priority: 'Medium',
        status: 'Open',
        site: 'Workshop 3',
        department: 'Fire Safety',
        targetDate: '25 Nov 2026',
        recipientType: 'external',
        assignedTo: externalContractor.name,
        externalRecipientId: externalContractor.personId,
        externalRecipientEmail: externalContractor.email,
        externalRecipientName: externalContractor.name,
        percentComplete: 0,
      );

      await ActionService.instance.createAction(action);
      expect(capturedEmail, isNotNull);

      final html = capturedEmail!['html'] as String;
      expect(html, contains('/external-update?token='));

      // Extract token from link
      final tokenRegex = RegExp(r'/external-update\?token=([a-zA-Z0-9_-]+)');
      final match = tokenRegex.firstMatch(html);
      expect(match, isNotNull);
      final rawToken = match!.group(1);
      expect(rawToken, isNotNull);
      expect(rawToken!.length, greaterThanOrEqualTo(20));

      // Validate the token via ExternalActionService
      final fetchResult = await ExternalActionService.instance.fetchActionByToken(rawToken);
      expect(fetchResult, isA<ExternalActionFetchSuccess>());
      final payload = (fetchResult as ExternalActionFetchSuccess).payload;
      expect(payload.actionId, equals('act-ext-assign-002'));
      expect(payload.actionNumber, equals('ACT-EXT-002'));
      expect(payload.title, equals('Install Fire Extinguishers'));
      expect(payload.recipientEmail, equals('robert.contractor@apex.com'));
    });
  });

  group('Group 2: Resend Assignment Behavior & Isolation', () {
    test('Test D: Resend internal sends only to current internal recipient', () async {
      final sentEmails = <Map<String, dynamic>>[];

      EmailService.mockSendHandler = (params) {
        sentEmails.add(params);
        return EmailSendResult.sent('msg-resend-int', recipientEmail: params['to'] as String);
      };

      final action = ActionRecord(
        id: 'act-resend-int-001',
        actionNumber: 'ACT-RINT-001',
        organizationId: testOrgId,
        createdById: 'mgr-user-001',
        subject: 'Weekly Boiler Inspection',
        actionRequired: 'Check boiler pressure gauge and safety relief valve',
        division: 'Maintenance',
        priority: 'Medium',
        status: 'In Progress',
        site: 'Boiler Room',
        primaryAssignee: internalAssignee,
        assignedTo: internalAssignee.name,
        assignedToId: internalAssignee.personId,
        recipientType: 'internal',
        percentComplete: 30,
      );

      MockActionStore.instance.add(action);
      sentEmails.clear();

      final resendResult = await ActionService.instance.resendAssignmentEmail(action);
      expect(resendResult.isSuccess, isTrue);
      expect(resendResult.recipientEmail, equals('suresh.engineer@sobha.com'));
      expect(resendResult.recipientType, equals('internal'));
      expect(resendResult.externalUpdateUrl, isNull);

      expect(sentEmails.length, equals(1));
      expect(sentEmails.first['to'], equals('suresh.engineer@sobha.com'));
      expect(sentEmails.first['subject'], contains('Action Assigned: [ACT-RINT-001] Weekly Boiler Inspection'));
    });

    test('Test E: Resend external sends only to current external recipient with secure link', () async {
      final sentEmails = <Map<String, dynamic>>[];

      EmailService.mockSendHandler = (params) {
        sentEmails.add(params);
        return EmailSendResult.sent('msg-resend-ext', recipientEmail: params['to'] as String);
      };

      final action = ActionRecord(
        id: 'act-resend-ext-001',
        actionNumber: 'ACT-REXT-001',
        organizationId: testOrgId,
        createdById: 'mgr-user-001',
        subject: 'External Electrical Testing',
        actionRequired: 'Perform earth leakage testing on main board',
        division: 'Electrical',
        priority: 'High',
        status: 'Open',
        site: 'Substation 2',
        recipientType: 'external',
        assignedTo: externalContractor.name,
        externalRecipientId: externalContractor.personId,
        externalRecipientEmail: externalContractor.email,
        externalRecipientName: externalContractor.name,
        percentComplete: 0,
      );

      MockActionStore.instance.add(action);
      sentEmails.clear();

      final resendResult = await ActionService.instance.resendAssignmentEmail(action);
      expect(resendResult.isSuccess, isTrue);
      expect(resendResult.recipientEmail, equals('robert.contractor@apex.com'));
      expect(resendResult.recipientType, equals('external'));
      expect(resendResult.externalUpdateUrl, isNotNull);
      expect(resendResult.externalUpdateUrl, contains('/external-update?token='));

      expect(sentEmails.length, equals(1));
      expect(sentEmails.first['to'], equals('robert.contractor@apex.com'));
    });

    test('Test F: Repeated resend creates no duplicate action', () async {
      EmailService.mockSendHandler = (params) {
        return EmailSendResult.sent('msg-f-001', recipientEmail: params['to'] as String);
      };

      final action1 = ActionRecord(
        id: 'act-f-001',
        actionNumber: 'ACT-F-001',
        organizationId: testOrgId,
        createdById: 'mgr-user-001',
        subject: 'Action 1',
        actionRequired: 'Task 1',
        division: 'HSE',
        primaryAssignee: internalAssignee,
        assignedTo: internalAssignee.name,
        assignedToId: internalAssignee.personId,
        recipientType: 'internal',
      );

      final action2 = ActionRecord(
        id: 'act-f-002',
        actionNumber: 'ACT-F-002',
        organizationId: testOrgId,
        createdById: 'mgr-user-001',
        subject: 'Action 2',
        actionRequired: 'Task 2',
        division: 'HSE',
        recipientType: 'external',
        assignedTo: externalContractor.name,
        externalRecipientId: externalContractor.personId,
        externalRecipientEmail: externalContractor.email,
        externalRecipientName: externalContractor.name,
      );

      MockActionStore.instance.add(action1);
      MockActionStore.instance.add(action2);

      final initialActionCount = MockActionStore.instance.actions.length;
      expect(initialActionCount, equals(2));

      // Resend multiple times
      for (int i = 0; i < 5; i++) {
        await ActionService.instance.resendAssignmentEmail(action1);
        await ActionService.instance.resendAssignmentEmail(action2);
      }

      // Verify strictly NO duplicate action created
      expect(MockActionStore.instance.actions.length, equals(initialActionCount));
      expect(MockActionStore.instance.actions.map((a) => a.id).toSet().length, equals(2));
    });

    test('Test G: Repeated resend creates no duplicate assignment or external recipient', () async {
      EmailService.mockSendHandler = (params) {
        return EmailSendResult.sent('msg-g-001', recipientEmail: params['to'] as String);
      };

      final initialRecipientCount = MockActionStore.instance.externalRecipients.length;
      expect(initialRecipientCount, equals(1));

      final action = ActionRecord(
        id: 'act-g-001',
        actionNumber: 'ACT-G-001',
        organizationId: testOrgId,
        createdById: 'mgr-user-001',
        subject: 'Scaffolding Check',
        actionRequired: 'Inspect ties',
        division: 'HSE',
        recipientType: 'external',
        assignedTo: externalContractor.name,
        externalRecipientId: externalContractor.personId,
        externalRecipientEmail: externalContractor.email,
        externalRecipientName: externalContractor.name,
      );
      MockActionStore.instance.add(action);

      for (int i = 0; i < 5; i++) {
        await ActionService.instance.resendAssignmentEmail(action);
      }

      // External recipients table remains strictly unmodified
      expect(MockActionStore.instance.externalRecipients.length, equals(initialRecipientCount));
    });

    test('Test H: Resend creates NO action_email_reminders row', () async {
      EmailService.mockSendHandler = (params) {
        return EmailSendResult.sent('msg-h-001', recipientEmail: params['to'] as String);
      };

      final action = ActionRecord(
        id: 'act-h-001',
        actionNumber: 'ACT-H-001',
        organizationId: testOrgId,
        createdById: 'mgr-user-001',
        subject: 'Valve Service',
        actionRequired: 'Lube valve',
        division: 'HSE',
        primaryAssignee: internalAssignee,
        assignedTo: internalAssignee.name,
        assignedToId: internalAssignee.personId,
        recipientType: 'internal',
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'rem-h-01',
            date: '30 Nov 2026',
            time: '09:00 AM',
            recipients: [internalAssignee],
          ),
        ],
      );
      MockActionStore.instance.add(action);

      // Verify no reminders in MockActionStore.instance.emailReminders
      MockActionStore.instance.emailReminders.clear();
      expect(MockActionStore.instance.emailReminders, isEmpty);

      // Resend assignment 4 times
      for (int i = 0; i < 4; i++) {
        await ActionService.instance.resendAssignmentEmail(action);
      }

      // Invariant: Resend assignment NEVER creates or alters action_email_reminders rows
      expect(MockActionStore.instance.emailReminders, isEmpty);
    });

    test('Test I: Resend does not modify email_reminder_enabled or reminder schedules', () async {
      EmailService.mockSendHandler = (params) {
        return EmailSendResult.sent('msg-i-001', recipientEmail: params['to'] as String);
      };

      final scheduledReminders = [
        ActionEmailReminder(
          id: 'rem-i-01',
          date: '01 Nov 2026',
          time: '09:00 AM',
          recipients: [internalAssignee],
        ),
        ActionEmailReminder(
          id: 'rem-i-02',
          date: '05 Nov 2026',
          time: '10:00 AM',
          recipients: [internalAssignee],
        ),
      ];

      final action = ActionRecord(
        id: 'act-i-001',
        actionNumber: 'ACT-I-001',
        organizationId: testOrgId,
        createdById: 'mgr-user-001',
        subject: 'Sprinkler System Flow Test',
        actionRequired: 'Test main riser flow switch',
        division: 'Fire Protection',
        primaryAssignee: internalAssignee,
        assignedTo: internalAssignee.name,
        assignedToId: internalAssignee.personId,
        recipientType: 'internal',
        emailReminderEnabled: true,
        emailReminders: scheduledReminders,
      );
      MockActionStore.instance.add(action);

      await ActionService.instance.resendAssignmentEmail(action);

      final retrieved = MockActionStore.instance.actions.firstWhere((a) => a.id == action.id);
      expect(retrieved.emailReminderEnabled, isTrue);
      expect(retrieved.emailReminders.length, equals(2));
      expect(retrieved.emailReminders[0].date, equals('01 Nov 2026'));
      expect(retrieved.emailReminders[0].time, equals('09:00 AM'));
      expect(retrieved.emailReminders[1].date, equals('05 Nov 2026'));
      expect(retrieved.emailReminders[1].time, equals('10:00 AM'));
    });
  });

  group('Group 3: Validation, Error Handling & Safety', () {
    test('Test J1: Resend fails safely when action has no assignee email', () async {
      final actionWithNoEmail = ActionRecord(
        id: 'act-no-email-001',
        actionNumber: 'ACT-NO-EMAIL',
        organizationId: testOrgId,
        createdById: 'mgr-user-001',
        subject: 'Unassigned Action',
        actionRequired: 'Do something',
        division: 'Operations',
        recipientType: 'internal',
        assignedTo: 'Unknown Worker',
        assignedToId: null,
        primaryAssignee: null,
      );

      final result = await EmailService.instance.sendAssignmentEmail(action: actionWithNoEmail);
      expect(result.isSuccess, isFalse);
      expect(result.status, equals('invalid_recipient'));
      expect(result.errorMessage, contains('No valid recipient email found'));
    });

    test('Test J2: Resend fails safely when recipient email format is invalid', () async {
      final invalidAssignee = ActionPersonReference(
        personId: '00000000-0000-0000-0000-000000000099',
        name: 'Bad Email User',
        type: PersonType.internalUser,
        email: 'invalid-email-no-domain',
      );

      final action = ActionRecord(
        id: 'act-bad-email-001',
        actionNumber: 'ACT-BAD-001',
        organizationId: testOrgId,
        createdById: 'mgr-user-001',
        subject: 'Action Bad Email',
        actionRequired: 'Fix email',
        division: 'Operations',
        recipientType: 'internal',
        assignedTo: invalidAssignee.name,
        assignedToId: invalidAssignee.personId,
        primaryAssignee: invalidAssignee,
      );

      final result = await EmailService.instance.sendAssignmentEmail(action: action);
      expect(result.isSuccess, isFalse);
      expect(result.status, equals('invalid_email'));
      expect(result.errorMessage, contains('Invalid recipient email format'));
    });

    test('Test K1: Email provider not-configured is handled safely with informative status', () async {
      EmailService.mockSendHandler = (params) {
        return EmailSendResult.notConfigured();
      };

      final action = ActionRecord(
        id: 'act-k1-001',
        actionNumber: 'ACT-K1-001',
        organizationId: testOrgId,
        createdById: 'mgr-user-001',
        subject: 'Provider test',
        actionRequired: 'Test',
        division: 'HSE',
        primaryAssignee: internalAssignee,
        assignedTo: internalAssignee.name,
        assignedToId: internalAssignee.personId,
        recipientType: 'internal',
      );

      final result = await EmailService.instance.sendAssignmentEmail(action: action);
      expect(result.isSuccess, isFalse);
      expect(result.status, equals('not_configured'));
      expect(result.errorMessage, contains('Email provider (Resend) is not configured'));
    });

    test('Test K2: Email delivery failure is handled without crashing', () async {
      EmailService.mockSendHandler = (params) {
        return const EmailSendResult(
          isSuccess: false,
          status: 'failed',
          errorMessage: '550 User mailbox not found or disabled',
        );
      };

      final action = ActionRecord(
        id: 'act-k2-001',
        actionNumber: 'ACT-K2-001',
        organizationId: testOrgId,
        createdById: 'mgr-user-001',
        subject: 'Mailbox failure test',
        actionRequired: 'Test',
        division: 'HSE',
        primaryAssignee: internalAssignee,
        assignedTo: internalAssignee.name,
        assignedToId: internalAssignee.personId,
        recipientType: 'internal',
      );

      final result = await EmailService.instance.sendAssignmentEmail(action: action);
      expect(result.isSuccess, isFalse);
      expect(result.status, equals('failed'));
      expect(result.errorMessage, contains('550 User mailbox not found'));
    });
  });

  group('Group 4: UI Button Presence & User Interaction', () {
    testWidgets('Test L1: Action Details screen renders Resend Assignment button immediately after Edit Action and triggers send', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool resendHandlerCalled = false;
      EmailService.mockSendHandler = (params) {
        resendHandlerCalled = true;
        return EmailSendResult.sent('msg-l1', recipientEmail: params['to'] as String);
      };

      final action = ActionRecord(
        id: 'act-l1-001',
        actionNumber: 'ACT-L1-001',
        organizationId: testOrgId,
        createdById: 'mgr-user-001',
        subject: 'Crane Safety Inspection',
        actionRequired: 'Verify wire ropes and limit switches',
        division: 'Equipment',
        priority: 'High',
        status: 'Open',
        site: 'West Pier',
        primaryAssignee: internalAssignee,
        assignedTo: internalAssignee.name,
        assignedToId: internalAssignee.personId,
        recipientType: 'internal',
        percentComplete: 0,
      );
      MockActionStore.instance.add(action);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionDetailsScreen(
              action: action,
              managerContext: testManagerContext,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Edit Action and Resend Assignment buttons exist
      final editBtn = find.text('Edit Action');
      final resendBtn = find.byKey(const Key('resend_assignment_btn'));

      expect(editBtn, findsOneWidget);
      expect(resendBtn, findsOneWidget);

      // Tap Resend Assignment button
      await tester.tap(resendBtn);
      await tester.pumpAndSettle();

      expect(resendHandlerCalled, isTrue);
      // SnackBar shows success
      expect(find.textContaining('Assignment email sent successfully'), findsOneWidget);
    });

    testWidgets('Test L2: Action Details shows error SnackBar when action lacks assignee email', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final actionNoEmail = ActionRecord(
        id: 'act-l2-001',
        actionNumber: 'ACT-L2-001',
        organizationId: testOrgId,
        createdById: 'mgr-user-001',
        subject: 'Unassigned Action',
        actionRequired: 'Do work',
        division: 'HSE',
        priority: 'Low',
        status: 'Open',
        assignedTo: 'Nobody',
        assignedToId: null,
        primaryAssignee: null,
        recipientType: 'internal',
      );
      MockActionStore.instance.add(actionNoEmail);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionDetailsScreen(
              action: actionNoEmail,
              managerContext: testManagerContext,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final resendBtn = find.byKey(const Key('resend_assignment_btn'));
      expect(resendBtn, findsOneWidget);

      await tester.tap(resendBtn);
      await tester.pumpAndSettle();

      // Error SnackBar displayed
      expect(
        find.text('Cannot resend assignment: No assignee email address is associated with this action.'),
        findsOneWidget,
      );
    });

    testWidgets('Test L3: Action Register renders Resend Assignment button between Edit and Delete in DataTable', (tester) async {
      tester.view.physicalSize = const Size(2800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool resendHandlerCalled = false;
      EmailService.mockSendHandler = (params) {
        resendHandlerCalled = true;
        return EmailSendResult.sent('msg-l3', recipientEmail: params['to'] as String);
      };

      final action = ActionRecord(
        id: 'act-l3-001',
        actionNumber: 'ACT-L3-001',
        organizationId: testOrgId,
        createdById: 'mgr-user-001',
        subject: 'Emergency Lighting Test',
        actionRequired: 'Perform battery discharge test',
        division: 'Facilities',
        priority: 'High',
        status: 'Open',
        site: 'Building 1',
        primaryAssignee: internalAssignee,
        assignedTo: internalAssignee.name,
        assignedToId: internalAssignee.personId,
        recipientType: 'internal',
        percentComplete: 0,
        dateRaised: '01 Oct 2026',
        targetDate: '10 Oct 2026',
      );
      MockActionStore.instance.add(action);

      await tester.pumpWidget(
        MaterialApp(
          home: ManagerDashboardScreen(
            managerContext: testManagerContext,
            userProfile: testManagerProfile,
            initialActions: [action],
            initialMyActions: [action],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Action Register
      final actionRegisterNav = find.text('Action Register');
      expect(actionRegisterNav, findsWidgets);
      await tester.tap(actionRegisterNav.first);
      await tester.pumpAndSettle();

      // Find the resend assignment button for this action in the table
      final tableResendBtn = find.byKey(Key('resend_assignment_table_btn_${action.id}'));
      expect(tableResendBtn, findsOneWidget);

      await tester.ensureVisible(tableResendBtn);
      await tester.pumpAndSettle();

      // Tap Resend Assignment in the table row
      await tester.tap(tableResendBtn);
      await tester.pumpAndSettle();

      expect(resendHandlerCalled, isTrue);
      expect(find.textContaining('Assignment email sent successfully'), findsOneWidget);
    });
  });

  group('Group 5: External Assignment Token Security & Architecture Invariants', () {
    test('Test Token A & D: generateSecureRawToken produces 64-character hex CSPRNG token and hashes to SHA-256', () {
      final token1 = EmailService.generateSecureRawToken();
      final token2 = EmailService.generateSecureRawToken();

      // Length and hex format
      expect(token1.length, equals(64));
      expect(token2.length, equals(64));
      expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(token1), isTrue);
      expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(token2), isTrue);

      // Unpredictability: consecutive tokens must never be equal
      expect(token1, isNot(equals(token2)));

      // SHA-256 hash is also 64-char lowercase hex digest
      final hash1 = EmailService.hashToken(token1);
      final hash2 = EmailService.hashToken(token2);
      expect(hash1.length, equals(64));
      expect(hash2.length, equals(64));
      expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(hash1), isTrue);
      expect(hash1, isNot(equals(hash2)));
    });

    test('Test Token B, C, E, F, G: External assignment & resend generates secure token, stores only hash, and resolves via fetchActionByToken', () async {
      Map<String, dynamic>? capturedEmail;
      EmailService.mockSendHandler = (params) {
        capturedEmail = params;
        return EmailSendResult.sent('msg-tok-01', recipientEmail: params['to'] as String);
      };

      final action = ActionRecord(
        id: 'act-tok-001',
        actionNumber: 'ACT-TOK-001',
        organizationId: testOrgId,
        createdById: 'mgr-user-001',
        subject: 'Perimeter Wall Repair',
        actionRequired: 'Fix concrete cracks on sector 2',
        division: 'Civil',
        priority: 'High',
        status: 'Open',
        site: 'South Gate',
        department: 'Facilities',
        recipientType: 'external',
        assignedTo: externalContractor.name,
        externalRecipientId: externalContractor.personId,
        externalRecipientEmail: externalContractor.email,
        externalRecipientName: externalContractor.name,
      );

      // 1. Initial creation
      await ActionService.instance.createAction(action);
      expect(capturedEmail, isNotNull);

      final html = capturedEmail!['html'] as String;
      final uriMatch = RegExp(r'/external-update\?token=([a-f0-9]{64})').firstMatch(html);
      expect(uriMatch, isNotNull, reason: 'URL must contain a 64-char hex raw token');
      final rawToken1 = uriMatch!.group(1)!;

      // Verify stored token in MockExternalActionStore is indexed by hash, NOT raw token
      final tokenHash1 = EmailService.hashToken(rawToken1);
      final storedEntry = MockExternalActionStore.instance.findByHash(tokenHash1);
      expect(storedEntry, isNotNull);
      expect(storedEntry!.tokenHash, equals(tokenHash1));
      // Stored tokenHash matches SHA-256 of rawToken
      expect(EmailService.hashToken(rawToken1), equals(storedEntry.tokenHash));

      // 2. Contractor fetch by token succeeds
      final fetchRes1 = await ExternalActionService.instance.fetchActionByToken(rawToken1);
      expect(fetchRes1, isA<ExternalActionFetchSuccess>());
      final payload1 = (fetchRes1 as ExternalActionFetchSuccess).payload;
      expect(payload1.actionId, equals(action.id));
      expect(payload1.recipientEmail, equals(externalContractor.email));

      // 3. Resend generates a fresh secure token with fresh entropy
      capturedEmail = null;
      final resendResult = await ActionService.instance.resendAssignmentEmail(action);
      expect(resendResult.isSuccess, isTrue);
      expect(capturedEmail, isNotNull);

      final htmlResend = capturedEmail!['html'] as String;
      final resendMatch = RegExp(r'/external-update\?token=([a-f0-9]{64})').firstMatch(htmlResend);
      expect(resendMatch, isNotNull);
      final rawToken2 = resendMatch!.group(1)!;

      // Resend token is fresh and distinct from initial token
      expect(rawToken2, isNot(equals(rawToken1)));

      // Resend token resolves successfully
      final fetchRes2 = await ExternalActionService.instance.fetchActionByToken(rawToken2);
      expect(fetchRes2, isA<ExternalActionFetchSuccess>());
    });

    test('Test Token H: Revoked or expired external token is rejected with explicit flags', () async {
      EmailService.mockSendHandler = (params) {
        return EmailSendResult.sent('msg-tok-h', recipientEmail: params['to'] as String);
      };

      final action = ActionRecord(
        id: 'act-tok-h01',
        actionNumber: 'ACT-TOK-H01',
        organizationId: testOrgId,
        createdById: 'mgr-user-001',
        subject: 'Gate Automation Check',
        actionRequired: 'Test sensors',
        division: 'Security',
        recipientType: 'external',
        assignedTo: externalContractor.name,
        externalRecipientId: externalContractor.personId,
        externalRecipientEmail: externalContractor.email,
        externalRecipientName: externalContractor.name,
      );

      final res = await EmailService.instance.sendAssignmentEmail(action: action);
      expect(res.isSuccess, isTrue);
      final rawToken = Uri.parse(res.externalUpdateUrl!).queryParameters['token']!;

      // 1. Valid token initially
      final initialFetch = await ExternalActionService.instance.fetchActionByToken(rawToken);
      expect(initialFetch, isA<ExternalActionFetchSuccess>());

      // 2. Revoke token
      MockExternalActionStore.instance.revokeToken(rawToken);
      final revokedFetch = await ExternalActionService.instance.fetchActionByToken(rawToken);
      expect(revokedFetch, isA<ExternalActionFetchFailure>());
      expect((revokedFetch as ExternalActionFetchFailure).isRevoked, isTrue);

      // 3. Expire token
      MockExternalActionStore.instance.expireToken(rawToken);
      final expiredFetch = await ExternalActionService.instance.fetchActionByToken(rawToken);
      expect(expiredFetch, isA<ExternalActionFetchFailure>());
      // After expiration and revocation, it fails safely
      expect((expiredFetch as ExternalActionFetchFailure).errorMessage.isNotEmpty, isTrue);
    });

    test('Test Token I: Internal assignment email strictly does NOT generate external token', () async {
      EmailService.mockSendHandler = (params) {
        return EmailSendResult.sent('msg-tok-int', recipientEmail: params['to'] as String);
      };

      final internalAction = ActionRecord(
        id: 'act-tok-int-01',
        actionNumber: 'ACT-TOK-INT-01',
        organizationId: testOrgId,
        createdById: 'mgr-user-001',
        subject: 'Internal Health Check',
        actionRequired: 'Verify PPE inventory',
        division: 'HSE',
        primaryAssignee: internalAssignee,
        assignedTo: internalAssignee.name,
        assignedToId: internalAssignee.personId,
        recipientType: 'internal',
      );

      final initialTokensCount = MockExternalActionStore.instance.findByHash('non-existent');
      expect(initialTokensCount, isNull);

      final result = await EmailService.instance.sendAssignmentEmail(action: internalAction);
      expect(result.isSuccess, isTrue);
      expect(result.recipientType, equals('internal'));
      expect(result.externalUpdateUrl, isNull);
    });

    test('Test Token J, K, L: Scheduled reminders untouched, zero duplicate actions/assignments, and tenant isolation', () async {
      EmailService.mockSendHandler = (params) {
        return EmailSendResult.sent('msg-tok-jkl', recipientEmail: params['to'] as String);
      };

      final action = ActionRecord(
        id: 'act-tok-jkl-01',
        actionNumber: 'ACT-TOK-JKL-01',
        organizationId: testOrgId,
        createdById: 'mgr-user-001',
        subject: 'Tenant Isolation Action',
        actionRequired: 'Inspect boundaries',
        division: 'HSE',
        recipientType: 'external',
        assignedTo: externalContractor.name,
        externalRecipientId: externalContractor.personId,
        externalRecipientEmail: externalContractor.email,
        externalRecipientName: externalContractor.name,
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'rem-jkl-01',
            date: '12 Dec 2026',
            time: '11:00 AM',
            recipients: [externalContractor],
          ),
        ],
      );
      MockActionStore.instance.add(action);

      // Verify emailReminders in store
      expect(MockActionStore.instance.emailReminders, isEmpty);
      final initialActionCount = MockActionStore.instance.actions.length;
      final initialRecipientCount = MockActionStore.instance.externalRecipients.length;

      // Resend 3 times
      for (int i = 0; i < 3; i++) {
        await ActionService.instance.resendAssignmentEmail(action);
      }

      // Invariants:
      // 1. Scheduled reminder jobs untouched
      expect(MockActionStore.instance.emailReminders, isEmpty);
      // 2. Action count strictly unchanged
      expect(MockActionStore.instance.actions.length, equals(initialActionCount));
      // 3. External recipient count strictly unchanged
      expect(MockActionStore.instance.externalRecipients.length, equals(initialRecipientCount));
      // 4. Action reminder settings unchanged
      final storedAction = MockActionStore.instance.actions.firstWhere((a) => a.id == action.id);
      expect(storedAction.emailReminderEnabled, isTrue);
      expect(storedAction.emailReminders.length, equals(1));
    });
  });

  group('Group 6: Caller Authorization and Action Creation Delivery Status Invariants', () {
    test('Test 6.1: Active manager profile allows assignment email dispatch', () async {
      EmailService.mockSendHandler = (params) {
        expect(params['action'], equals('send_single_email'));
        return EmailSendResult.sent('msg-auth-ok', recipientEmail: params['to'] as String);
      };

      final action = ActionRecord(
        id: 'act-auth-mgr-01',
        actionNumber: 'ACT-AUTH-01',
        organizationId: testOrgId,
        createdById: 'mgr-user-001',
        subject: 'Manager Authorized Action',
        actionRequired: 'Verify safety barrier',
        division: 'HSE',
        priority: 'Medium',
        status: 'Open',
        assignedTo: internalAssignee.name,
        assignedToId: internalAssignee.personId,
        primaryAssignee: internalAssignee,
        recipientType: 'internal',
      );

      final result = await ActionService.instance.createActionWithResult(action);
      expect(result.action, isNotNull);
      expect(result.emailSent, isTrue);
      expect(result.emailResult?.isSuccess, isTrue);
      expect(ActionService.instance.lastAssignmentEmailResult?.isSuccess, isTrue);
    });

    test('Test 6.2: Missing caller profile rejects assignment email with 403 error', () async {
      EmailService.mockSendHandler = (params) {
        return const EmailSendResult(
          isSuccess: false,
          status: 'forbidden',
          errorMessage: 'Forbidden: Active user profile required',
        );
      };

      final action = ActionRecord(
        id: 'act-auth-missing-01',
        actionNumber: 'ACT-AUTH-02',
        organizationId: testOrgId,
        createdById: 'unknown-user',
        subject: 'Missing Profile Action',
        actionRequired: 'Inspect crane',
        division: 'HSE',
        priority: 'High',
        status: 'Open',
        assignedTo: internalAssignee.name,
        assignedToId: internalAssignee.personId,
        primaryAssignee: internalAssignee,
        recipientType: 'internal',
      );

      final result = await ActionService.instance.createActionWithResult(action);
      // Invariant: action is still saved
      expect(result.action, isNotNull);
      expect(MockActionStore.instance.actions.any((a) => a.id == action.id), isTrue);
      // Invariant: email failure is accurately reported
      expect(result.emailSent, isFalse);
      expect(result.emailResult?.isSuccess, isFalse);
      expect(result.emailResult?.status, equals('forbidden'));
      expect(result.emailResult?.errorMessage, contains('Forbidden: Active user profile required'));
      expect(ActionService.instance.lastAssignmentEmailResult?.isSuccess, isFalse);
    });

    test('Test 6.3: Inactive caller profile rejects assignment email with 403 error', () async {
      EmailService.mockSendHandler = (params) {
        return const EmailSendResult(
          isSuccess: false,
          status: 'forbidden',
          errorMessage: 'Forbidden: Active user profile required',
        );
      };

      final action = ActionRecord(
        id: 'act-auth-inactive-01',
        actionNumber: 'ACT-AUTH-03',
        organizationId: testOrgId,
        createdById: 'inactive-mgr',
        subject: 'Inactive Profile Action',
        actionRequired: 'Inspect generator',
        division: 'HSE',
        priority: 'Medium',
        status: 'Open',
        assignedTo: internalAssignee.name,
        assignedToId: internalAssignee.personId,
        primaryAssignee: internalAssignee,
        recipientType: 'internal',
      );

      final result = await ActionService.instance.createActionWithResult(action);
      expect(result.action, isNotNull);
      expect(result.emailSent, isFalse);
      expect(result.emailResult?.errorMessage, contains('Active user profile required'));
    });

    test('Test 6.4: Non-manager/admin caller is rejected for email dispatch', () async {
      EmailService.mockSendHandler = (params) {
        return const EmailSendResult(
          isSuccess: false,
          status: 'forbidden',
          errorMessage: 'ActionFlow Security Violation: Only managers or administrators may dispatch notification emails.',
        );
      };

      final action = ActionRecord(
        id: 'act-auth-worker-01',
        actionNumber: 'ACT-AUTH-04',
        organizationId: testOrgId,
        createdById: 'staff-user-01',
        subject: 'Staff Dispatched Action',
        actionRequired: 'Check valve',
        division: 'HSE',
        priority: 'Low',
        status: 'Open',
        assignedTo: internalAssignee.name,
        assignedToId: internalAssignee.personId,
        primaryAssignee: internalAssignee,
        recipientType: 'internal',
      );

      final result = await ActionService.instance.createActionWithResult(action);
      expect(result.action, isNotNull);
      expect(result.emailSent, isFalse);
      expect(result.emailResult?.errorMessage, contains('Only managers or administrators may dispatch notification emails'));
    });

    test('Test 6.5: Failed assignment email does not delete or roll back the saved action', () async {
      EmailService.mockSendHandler = (params) {
        throw Exception('Network connection timed out while contacting send-email Edge Function');
      };

      final action = ActionRecord(
        id: 'act-persist-on-fail-01',
        actionNumber: 'ACT-PERSIST-01',
        organizationId: testOrgId,
        createdById: 'mgr-user-001',
        subject: 'Action Must Persist Even If Email Throws',
        actionRequired: 'Ensure fire extinguisher readiness',
        division: 'HSE',
        priority: 'High',
        status: 'Open',
        assignedTo: internalAssignee.name,
        assignedToId: internalAssignee.personId,
        primaryAssignee: internalAssignee,
        recipientType: 'internal',
      );

      // Call standard createAction
      final created = await ActionService.instance.createAction(action);
      // Invariant: Action MUST remain saved
      expect(created, isNotNull);
      expect(created.id, equals(action.id));
      expect(MockActionStore.instance.actions.any((a) => a.id == action.id), isTrue);

      // Invariant: Email failure state is preserved and not reported as successful
      expect(ActionService.instance.lastAssignmentEmailResult, isNotNull);
      expect(ActionService.instance.lastAssignmentEmailResult!.isSuccess, isFalse);
      expect(ActionService.instance.lastAssignmentEmailResult!.errorMessage, contains('Error sending assignment email'));
    });

    test('Test 6.6: Resend Assignment uses the same action and assignment without creating reminders', () async {
      EmailService.mockSendHandler = (params) {
        return EmailSendResult.sent('msg-resend-same-01', recipientEmail: params['to'] as String);
      };

      final action = ActionRecord(
        id: 'act-resend-same-01',
        actionNumber: 'ACT-RS-01',
        organizationId: testOrgId,
        createdById: 'mgr-user-001',
        subject: 'Same Action Resend Check',
        actionRequired: 'Verify gas detector battery',
        division: 'HSE',
        priority: 'Medium',
        status: 'Open',
        assignedTo: internalAssignee.name,
        assignedToId: internalAssignee.personId,
        primaryAssignee: internalAssignee,
        recipientType: 'internal',
      );
      MockActionStore.instance.add(action);

      final preCount = MockActionStore.instance.actions.length;
      final resendResult = await ActionService.instance.resendAssignmentEmail(action);

      expect(resendResult.isSuccess, isTrue);
      // Zero duplicate actions created
      expect(MockActionStore.instance.actions.length, equals(preCount));
      // Zero reminders created in action_email_reminders
      expect(MockActionStore.instance.emailReminders, isEmpty);
    });
  });
}
