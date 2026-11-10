import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/external_recipient.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/add_action_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const orgIdA = 'org-sobha-01';
  const orgIdB = 'org-competitor-99';

  const testManagerProfile = UserProfile(
    id: 'mgr-user-uuid-101',
    name: 'David Manager',
    email: 'david.mgr@sobha.com',
    phone: '+971501234567',
    designation: 'HSE Manager',
    department: 'Safety Operations',
    site: 'North Plant',
    role: 'manager',
    organizationId: orgIdA,
    organizationName: 'Sobha Constructions',
  );

  final testManagerContext = ManagerContext(
    authUserId: 'mgr-user-uuid-101',
    profile: testManagerProfile,
    organizationId: orgIdA,
    organizationName: 'Sobha Constructions',
    scopes: const [
      ManagerScopeItem(
        departmentId: 'dept-safety-01',
        departmentName: 'Safety Operations',
        siteId: 'site-plant-01',
        siteName: 'North Plant',
      ),
    ],
  );

  setUp(() {
    MockActionStore.instance.actions.clear();
    MockActionStore.instance.externalRecipients.clear();
    MockActionStore.instance.emailReminders.clear();
  });

  group('1. External Recipient Model & Serialization', () {
    test('ExternalRecipient serialization and deserialization preserves all fields', () {
      final recipient = ExternalRecipient(
        id: 'rec-uuid-1',
        organizationId: orgIdA,
        fullName: 'Robert External',
        email: 'robert.ext@contractor.com',
        companyName: 'Apex Scaffolding',
        phone: '+971555123456',
        createdBy: 'mgr-user-uuid-101',
        isActive: true,
        createdAt: DateTime(2026, 9, 20),
      );

      final json = recipient.toJson();
      expect(json['id'], 'rec-uuid-1');
      expect(json['organization_id'], orgIdA);
      expect(json['full_name'], 'Robert External');
      expect(json['email'], 'robert.ext@contractor.com');
      expect(json['company_name'], 'Apex Scaffolding');
      expect(json['is_active'], true);

      final fromJson = ExternalRecipient.fromJson(json);
      expect(fromJson.id, recipient.id);
      expect(fromJson.fullName, recipient.fullName);
      expect(fromJson.email, recipient.email);
      expect(fromJson.organizationId, recipient.organizationId);
      expect(fromJson.companyName, recipient.companyName);
      expect(fromJson.isActive, isTrue);
    });

    test('ExternalRecipient does not require auth.users or password', () {
      final recipient = ExternalRecipient(
        id: 'rec-uuid-2',
        organizationId: orgIdA,
        fullName: 'Jane External Specialist',
        email: 'jane.specialist@external.org',
      );

      expect(recipient.id, isNotEmpty);
      expect(recipient.email, 'jane.specialist@external.org');
      // No Supabase auth or password fields exist on ExternalRecipient
      final json = recipient.toJson();
      expect(json.containsKey('password'), isFalse);
      expect(json.containsKey('auth_user_id'), isFalse);
    });
  });

  group('2. ActionRecord Database Map Rules & UUID Isolation', () {
    test('toSupabaseInsertMap strictly forces assigned_to to null for external recipient', () {
      final action = ActionRecord(
        id: 'act-ext-001',
        actionNumber: 'ACT-0001',
        organizationId: orgIdA,
        createdById: 'mgr-user-uuid-101',
        subject: 'External safety inspection',
        actionRequired: 'Inspect scaffolding safety pins',
        division: 'Operations',
        recipientType: 'external',
        assignedTo: 'Robert External',
        assignedToId: null, // Must not contain profile UUID
        externalRecipientId: 'rec-uuid-1',
        externalRecipientEmail: 'robert.ext@contractor.com',
        externalRecipientName: 'Robert External',
        emailReminderEnabled: true,
      );

      final map = action.toSupabaseInsertMap();
      expect(map['recipient_type'], 'external');
      expect(map['external_recipient_id'], 'rec-uuid-1');
      expect(map['email_reminder_enabled'], isTrue);
      // CRITICAL: Database foreign key to profiles(id) must be null
      expect(map['assigned_to'], isNull);
    });

    test('toSupabaseUpdateMap strictly forces assigned_to to null for external recipient', () {
      final action = ActionRecord(
        id: 'act-ext-002',
        actionNumber: 'ACT-0002',
        organizationId: orgIdA,
        createdById: 'mgr-user-uuid-101',
        subject: 'Update external task',
        actionRequired: 'Update details',
        division: 'Operations',
        recipientType: 'external',
        assignedTo: 'Jane Specialist',
        assignedToId: null,
        externalRecipientId: 'rec-uuid-2',
        externalRecipientEmail: 'jane.specialist@external.org',
        externalRecipientName: 'Jane Specialist',
        emailReminderEnabled: false,
      );

      final map = action.toSupabaseUpdateMap();
      expect(map['recipient_type'], 'external');
      expect(map['external_recipient_id'], 'rec-uuid-2');
      expect(map['assigned_to'], isNull);
      expect(map['email_reminder_enabled'], isFalse);
    });

    test('Internal assignment continues setting assigned_to UUID and external fields null', () {
      final internalAction = ActionRecord(
        id: 'act-int-001',
        actionNumber: 'ACT-0003',
        organizationId: orgIdA,
        createdById: 'mgr-user-uuid-101',
        subject: 'Internal electrical audit',
        actionRequired: 'Check wiring',
        division: 'Operations',
        recipientType: 'internal',
        assignedTo: 'Internal Engineer',
        assignedToId: 'profile-uuid-888',
        emailReminderEnabled: false,
      );

      final map = internalAction.toSupabaseInsertMap();
      expect(map['recipient_type'], 'internal');
      expect(map['assigned_to'], 'profile-uuid-888');
      expect(map['external_recipient_id'], isNull);
    });
  });

  group(
    '3. Email Reminder Logic: Default OFF, ON Job Creation, and Cancellation',
    () {
      test(
        'Email reminder defaults to OFF and does NOT generate reminder jobs',
        () async {
          final action = ActionRecord(
            id: 'act-ext-100',
            actionNumber: 'ACT-0100',
            organizationId: orgIdA,
            createdById: 'mgr-user-uuid-101',
            subject: 'Scaffolding check with reminder OFF',
            actionRequired: 'Check scaffolding anchors',
            division: 'Operations',
            recipientType: 'external',
            assignedTo: 'Robert External',
            externalRecipientId: 'rec-uuid-1',
            externalRecipientEmail: 'robert.ext@contractor.com',
            externalRecipientName: 'Robert External',
            emailReminderEnabled: false, // DEFAULT OFF
          );

          final created = await ActionService.instance.createAction(action);
          expect(created.emailReminderEnabled, isFalse);

          // Verify no email reminder jobs were created
          final reminders = MockActionStore.instance.emailReminders;
          expect(reminders.isEmpty, isTrue);
        },
      );

      test('Email reminder ON without explicit recipient selection produces 0 reminder jobs', () async {
        final action = ActionRecord(
          id: 'act-ext-101',
          actionNumber: 'ACT-0101',
          organizationId: orgIdA,
          createdById: 'mgr-user-uuid-101',
          subject: 'Urgent external pipeline fix',
          actionRequired: 'Repair pipeline joint',
          division: 'Operations',
          recipientType: 'external',
          assignedTo: 'Robert External',
          externalRecipientId: 'rec-uuid-1',
          externalRecipientEmail: 'robert.ext@contractor.com',
          externalRecipientName: 'Robert External',
          emailReminderEnabled: true, // ON without explicit recipients
        );

        final created = await ActionService.instance.createAction(action);
        expect(created.emailReminderEnabled, isTrue);

        final reminders = MockActionStore.instance.emailReminders
            .where((j) => j.actionId == 'act-ext-101' && j.status == 'pending')
            .toList();
        expect(reminders.isEmpty, isTrue);
      });

      test('Email reminder ON with explicit recipient generates pending reminder job with correct external email', () async {
        final externalPerson = ActionPersonReference(
          personId: 'rec-uuid-1',
          name: 'Robert External',
          type: PersonType.externalWorker,
          email: 'robert.ext@contractor.com',
        );

        final action = ActionRecord(
          id: 'act-ext-101b',
          actionNumber: 'ACT-0101B',
          organizationId: orgIdA,
          createdById: 'mgr-user-uuid-101',
          subject: 'Urgent external pipeline fix with reminder',
          actionRequired: 'Repair pipeline joint',
          division: 'Operations',
          recipientType: 'external',
          assignedTo: 'Robert External',
          externalRecipientId: 'rec-uuid-1',
          externalRecipientEmail: 'robert.ext@contractor.com',
          externalRecipientName: 'Robert External',
          emailReminderEnabled: true,
          emailReminders: [
            ActionEmailReminder(
              id: 'rem-grp-ext-101b',
              date: '15 Oct 2026',
              time: '09:00 AM',
              recipients: [externalPerson],
            ),
          ],
        );

        final created = await ActionService.instance.createAction(action);
        expect(created.emailReminderEnabled, isTrue);

        final reminders = MockActionStore.instance.emailReminders
            .where((j) => j.actionId == 'act-ext-101b' && j.status == 'pending')
            .toList();
        expect(reminders.length, 1);
        final job = reminders.first;
        expect(job.actionId, 'act-ext-101b');
        expect(job.recipientEmail, 'robert.ext@contractor.com');
        expect(job.recipientName, 'Robert External');
        expect(job.status, 'pending');
        expect(job.reminderType, 'pending_action');
        expect(job.organizationId, orgIdA);
      });

      test(
        'Turning Email Reminder OFF cancels existing pending reminder jobs',
        () async {
          final externalPerson = ActionPersonReference(
            personId: 'rec-uuid-1',
            name: 'Robert External',
            type: PersonType.externalWorker,
            email: 'robert.ext@contractor.com',
          );

          // 1. Create with reminder ON and explicit recipient
          final action = ActionRecord(
            id: 'act-ext-102',
            actionNumber: 'ACT-0102',
            organizationId: orgIdA,
            createdById: 'mgr-user-uuid-101',
            subject: 'External tank pressure test',
            actionRequired: 'Perform pressure decay measurement',
            division: 'Operations',
            recipientType: 'external',
            assignedTo: 'Robert External',
            externalRecipientId: 'rec-uuid-1',
            externalRecipientEmail: 'robert.ext@contractor.com',
            externalRecipientName: 'Robert External',
            emailReminderEnabled: true,
            emailReminders: [
              ActionEmailReminder(
                id: 'rem-grp-ext-102',
                date: '16 Oct 2026',
                time: '10:00 AM',
                recipients: [externalPerson],
              ),
            ],
          );
          await ActionService.instance.createAction(action);
          expect(
            MockActionStore.instance.emailReminders
                .where((j) => j.actionId == 'act-ext-102' && j.status == 'pending')
                .length,
            1,
          );

          // 2. Update to turn reminder OFF
          final updatedAction = action.copyWith(emailReminderEnabled: false);
          await ActionService.instance.updateAction(updatedAction);

          // Verify pending job was marked 'cancelled'
          final job = MockActionStore.instance.emailReminders
              .firstWhere((j) => j.actionId == 'act-ext-102');
          expect(job.status, 'cancelled');
          expect(job.isCancelled, isTrue);
        },
      );

      test('Editing action with reminder turning from OFF to ON without explicit recipients produces 0 reminder jobs', () async {
        // 1. Create with reminder OFF
        final action = ActionRecord(
          id: 'act-ext-103',
          actionNumber: 'ACT-0103',
          organizationId: orgIdA,
          createdById: 'mgr-user-uuid-101',
          subject: 'Crane load testing',
          actionRequired: 'Verify proof load certification',
          division: 'Operations',
          recipientType: 'external',
          assignedTo: 'Jane Specialist',
          externalRecipientId: 'rec-uuid-2',
          externalRecipientEmail: 'jane.specialist@external.org',
          externalRecipientName: 'Jane Specialist',
          emailReminderEnabled: false,
        );
        await ActionService.instance.createAction(action);
        expect(MockActionStore.instance.emailReminders.isEmpty, isTrue);

        // 2. Edit to turn ON without configuring reminder schedule/recipients
        final updatedAction = action.copyWith(emailReminderEnabled: true);
        await ActionService.instance.updateAction(updatedAction);

        final pendingJobs = MockActionStore.instance.emailReminders
            .where((j) => j.actionId == 'act-ext-103' && j.status == 'pending')
            .toList();
        expect(pendingJobs.isEmpty, isTrue);
      });

      test('Editing action with reminder turning from OFF to ON with explicit recipient creates pending reminder job', () async {
        final externalPerson = ActionPersonReference(
          personId: 'rec-uuid-2',
          name: 'Jane Specialist',
          type: PersonType.externalWorker,
          email: 'jane.specialist@external.org',
        );

        // 1. Create with reminder OFF
        final action = ActionRecord(
          id: 'act-ext-104',
          actionNumber: 'ACT-0104',
          organizationId: orgIdA,
          createdById: 'mgr-user-uuid-101',
          subject: 'Crane proof load inspection',
          actionRequired: 'Verify test certificates',
          division: 'Operations',
          recipientType: 'external',
          assignedTo: 'Jane Specialist',
          externalRecipientId: 'rec-uuid-2',
          externalRecipientEmail: 'jane.specialist@external.org',
          externalRecipientName: 'Jane Specialist',
          emailReminderEnabled: false,
        );
        await ActionService.instance.createAction(action);
        expect(
          MockActionStore.instance.emailReminders
              .where((j) => j.actionId == 'act-ext-104' && j.status == 'pending'),
          isEmpty,
        );

        // 2. Edit to turn ON with explicit recipient configured
        final updatedAction = action.copyWith(
          emailReminderEnabled: true,
          emailReminders: [
            ActionEmailReminder(
              id: 'rem-grp-ext-104',
              date: '20 Oct 2026',
              time: '02:00 PM',
              recipients: [externalPerson],
            ),
          ],
        );
        await ActionService.instance.updateAction(updatedAction);

        final pendingJobs = MockActionStore.instance.emailReminders
            .where((j) => j.actionId == 'act-ext-104' && j.status == 'pending')
            .toList();
        expect(pendingJobs.length, 1);
        final job = pendingJobs.first;
        expect(job.status, 'pending');
        expect(job.recipientEmail, 'jane.specialist@external.org');
        expect(job.recipientName, 'Jane Specialist');
      });
    },
  );

  group('4. Tenant Isolation & Email Validation', () {
    test('Cross-tenant external recipient cannot be shared across different organizations', () {
      final recipientOrgA = ExternalRecipient(
        id: 'rec-org-a-1',
        organizationId: orgIdA,
        fullName: 'Contractor Sobha',
        email: 'sobha.contractor@partner.com',
      );
      final recipientOrgB = ExternalRecipient(
        id: 'rec-org-b-1',
        organizationId: orgIdB,
        fullName: 'Contractor Competitor',
        email: 'comp.contractor@partner.com',
      );

      MockActionStore.instance.externalRecipients.addAll([
        recipientOrgA,
        recipientOrgB,
      ]);

      // Filtering for Org A
      final orgARecipients = MockActionStore.instance.externalRecipients
          .where((r) => r.organizationId == orgIdA)
          .toList();

      expect(orgARecipients.length, 1);
      expect(orgARecipients.first.fullName, 'Contractor Sobha');
      expect(orgARecipients.any((r) => r.organizationId == orgIdB), isFalse);
    });

    test(
      'Email format regex validates valid emails and rejects invalid ones',
      () {
        final emailRegex = RegExp(
          r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
        );

        expect(emailRegex.hasMatch('john.doe@example.com'), isTrue);
        expect(emailRegex.hasMatch('contractor_123@sub.domain.co.uk'), isTrue);
        expect(emailRegex.hasMatch('name+tag@test.org'), isTrue);

        expect(emailRegex.hasMatch('plainaddress'), isFalse);
        expect(emailRegex.hasMatch('missingatsign.com'), isFalse);
        expect(emailRegex.hasMatch('@missingusername.com'), isFalse);
        expect(emailRegex.hasMatch('user@nodomain'), isFalse);
        expect(emailRegex.hasMatch('user@domain.'), isFalse);
        expect(emailRegex.hasMatch('user@.com'), isFalse);
      },
    );
  });

  group('5. UI Verification: Action Details, Action Register & My Actions', () {
    testWidgets(
      'Action Details displays Dedicated External Recipient section and Reminder badge',
      (tester) async {
        final externalAction = ActionRecord(
          id: 'act-ext-201',
          actionNumber: 'ACT-0201',
          organizationId: orgIdA,
          createdById: 'mgr-user-uuid-101',
          subject: 'External Structural Audit',
          actionRequired: 'Review foundation crack measurements',
          division: 'Operations',
          department: 'Safety Operations',
          site: 'North Plant',
          priority: 'High',
          status: 'Open',
          percentComplete: 15,
          recipientType: 'external',
          assignedTo: 'Robert External',
          assignedToId: null,
          externalRecipientId: 'rec-uuid-1',
          externalRecipientEmail: 'robert.ext@contractor.com',
          externalRecipientName: 'Robert External',
          emailReminderEnabled: true,
          dateRaised: '23 Sep 2026',
          targetDate: '30 Sep 2026',
          nextFollowUpDate: '26 Sep 2026',
        );

        MockActionStore.instance.add(externalAction);

        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: ActionDetailsScreen(
              action: externalAction,
              managerContext: testManagerContext,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify External Recipient UI Card elements
        expect(find.text('EXTERNAL RECIPIENT'), findsOneWidget);
        expect(find.text('Recipient Type: External'), findsOneWidget);
        expect(find.text('Robert External'), findsWidgets);
        expect(
          find.textContaining('robert.ext@contractor.com'),
          findsOneWidget,
        );
        expect(find.text('Email Reminder: '), findsOneWidget);
        expect(find.text('ON'), findsWidgets);
      },
    );

    testWidgets(
      'Action Register displays External badge and My Actions excludes external actions',
      (tester) async {
        final externalAction = ActionRecord(
          id: 'act-ext-301',
          actionNumber: 'ACT-0301',
          organizationId: orgIdA,
          departmentId: 'dept-safety-01',
          siteId: 'site-plant-01',
          createdById: 'mgr-user-uuid-101',
          subject: 'External Valve Testing',
          actionRequired: 'Hydraulic pressure test',
          division: 'Operations',
          priority: 'Medium',
          status: 'Open',
          percentComplete: 0,
          department: 'Safety Operations',
          site: 'North Plant',
          recipientType: 'external',
          assignedTo: 'Apex Valve Contractor',
          assignedToId: null,
          externalRecipientId: 'rec-uuid-3',
          externalRecipientEmail: 'valves@apex.com',
          externalRecipientName: 'Apex Valve Contractor',
          emailReminderEnabled: false,
          dateRaised: '23 Sep 2026',
          targetDate: '28 Sep 2026',
          nextFollowUpDate: '25 Sep 2026',
        );

        final internalAction = ActionRecord(
          id: 'act-int-302',
          actionNumber: 'ACT-0302',
          organizationId: orgIdA,
          departmentId: 'dept-safety-01',
          siteId: 'site-plant-01',
          createdById: 'mgr-user-uuid-101',
          subject: 'Internal Floor Audit',
          actionRequired: 'Safety line markings check',
          division: 'Operations',
          priority: 'Low',
          status: 'Open',
          percentComplete: 10,
          department: 'Safety Operations',
          site: 'North Plant',
          recipientType: 'internal',
          assignedTo: 'David Manager',
          assignedToId: 'mgr-user-uuid-101',
          dateRaised: '23 Sep 2026',
          targetDate: '28 Sep 2026',
          nextFollowUpDate: '25 Sep 2026',
        );

        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: ManagerDashboardScreen(
              userProfile: testManagerProfile,
              managerContext: testManagerContext,
              initialActions: [externalAction, internalAction],
              initialMyActions: [externalAction, internalAction],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to Action Register
        final actionRegisterNav = find.text('Action Register');
        expect(actionRegisterNav, findsWidgets);
        await tester.tap(actionRegisterNav.first);
        await tester.pumpAndSettle();

        // In Action Register:
        // The External badge is rendered next to the external assignee
        expect(find.text('Apex Valve Contractor'), findsOneWidget);
        expect(find.text('External'), findsOneWidget);

        // Now switch to My Actions tab
        final myActionsTab = find.text('My Actions');
        expect(myActionsTab, findsOneWidget);
        await tester.tap(myActionsTab);
        await tester.pumpAndSettle();

        // In My Actions:
        // Internal action assigned to David Manager is present
        expect(find.text('Internal Floor Audit'), findsOneWidget);
        // External action must NEVER appear in My Actions
        expect(find.text('External Valve Testing'), findsNothing);
      },
    );
  });

  group('6. Multiple External Users UI & Assignment Verification', () {
    testWidgets(
      'AddActionScreen allows adding, editing, and removing multiple external users via + Add Another External User',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: AddActionScreen(
              actionId: 'ACT-MULTI-EXT-1',
              managerContext: testManagerContext,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Switch to External User tab
        final externalTab = find.text('External User (Vendor/Contractor)');
        expect(externalTab, findsOneWidget);
        await tester.tap(externalTab);
        await tester.pumpAndSettle();

        // 2. Fill Primary External User
        final nameField = find.widgetWithText(TextFormField, 'Full Name *');
        expect(nameField, findsOneWidget);
        await tester.enterText(nameField, 'Contractor Alpha');

        final emailField =
            find.widgetWithText(TextFormField, 'Email Address *');
        expect(emailField, findsOneWidget);
        await tester.enterText(emailField, 'alpha@contractor.com');
        await tester.pumpAndSettle();

        // 3. Verify + Add Another External User button is visible
        final addAnotherBtn =
            find.byKey(const Key('add_another_external_user_btn'));
        expect(addAnotherBtn, findsOneWidget);
        expect(find.text('+ Add Another External User'), findsOneWidget);

        // 4. Click + Add Another External User to open dialog
        await tester.tap(addAnotherBtn);
        await tester.pumpAndSettle();

        // Dialog should be displayed
        expect(find.text('Add Another External User'), findsOneWidget);

        // Enter second external person details
        final dialogNameField = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextFormField, 'Full Name *'),
        );
        final dialogEmailField = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextFormField, 'Email Address *'),
        );
        await tester.enterText(dialogNameField, 'Contractor Beta');
        await tester.enterText(dialogEmailField, 'beta@contractor.com');
        await tester.pumpAndSettle();

        // Tap Add External User in dialog
        final dialogSubmitBtn = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Add External User'),
        );
        await tester.tap(dialogSubmitBtn);
        await tester.pumpAndSettle();

        // 5. Verify Contractor Beta appears in the Additional External Users list
        expect(find.text('Contractor Beta'), findsOneWidget);
        expect(find.text('beta@contractor.com'), findsOneWidget);
        expect(find.text('Additional External Users (1)'), findsOneWidget);

        // 6. Test editing the additional external user
        final editBtn = find.byTooltip('Edit External User');
        expect(editBtn, findsOneWidget);
        await tester.tap(editBtn);
        await tester.pumpAndSettle();

        expect(find.text('Edit External User'), findsOneWidget);
        final editNameField = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextFormField, 'Full Name *'),
        );
        await tester.enterText(editNameField, 'Contractor Beta Updated');
        await tester.pumpAndSettle();

        final editSaveBtn = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Save Changes'),
        );
        await tester.tap(editSaveBtn);
        await tester.pumpAndSettle();

        expect(find.text('Contractor Beta Updated'), findsOneWidget);

        // 7. Test removing the additional external user
        final removeBtn = find.byTooltip('Remove');
        expect(removeBtn, findsOneWidget);
        await tester.tap(removeBtn);
        await tester.pumpAndSettle();

        // Contractor Beta Updated should be removed, Contractor Alpha remains
        expect(find.text('Contractor Beta Updated'), findsNothing);
        expect(find.text('Additional External Users (1)'), findsNothing);
        expect(find.text('Contractor Alpha'), findsOneWidget);
      },
    );

    test('Multiple external users persist correctly and reminder recipients remain unchanged unless selected', () async {
      MockActionStore.instance.actions.clear();
      MockActionStore.instance.emailReminders.clear();
      MockActionStore.instance.externalRecipients.clear();

      final primaryExt = ActionPersonReference(
        personId: 'ext-p-1',
        name: 'Prime Contractor',
        type: PersonType.externalWorker,
        email: 'prime@contractor.com',
      );
      final addlExt = ActionPersonReference(
        personId: 'ext-p-2',
        name: 'Sub Contractor',
        type: PersonType.externalWorker,
        email: 'sub@contractor.com',
      );

      final action = ActionRecord(
        id: 'act-multi-ext-1',
        actionNumber: 'ACT-MULTI-1',
        organizationId: orgIdA,
        createdById: 'mgr-user-uuid-101',
        subject: 'Multi-External Job',
        actionRequired: 'Testing multiple external assignees',
        division: 'Operations',
        primaryAssignee: primaryExt,
        assignedTo: primaryExt.name,
        assignedToId: primaryExt.personId,
        additionalPeople: [addlExt],
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'rem-multi-1',
            date: '10 Oct 2026',
            time: '09:00 AM',
            recipients: [primaryExt],
          ),
        ],
      );

      final created = await ActionService.instance.createAction(action);

      expect(created, isNotNull);
      expect(created.primaryAssignee?.name, equals('Prime Contractor'));
      expect(created.additionalPeople.length, equals(1));
      expect(created.additionalPeople.first.name, equals('Sub Contractor'));
      expect(created.additionalPeople.first.type, equals(PersonType.externalWorker));

      // Check reminder persistence
      final fetched = await ActionService.instance.fetchActionById(created.id);
      expect(fetched, isNotNull);
      expect(fetched!.emailReminders.length, equals(1));
      // Only the selected primary contractor receives a reminder, unselected sub-contractor does NOT
      expect(fetched.emailReminders.first.recipients.length, equals(1));
      expect(fetched.emailReminders.first.recipients.first.name, equals('Prime Contractor'));
      expect(fetched.emailReminders.first.recipients.any((r) => r.name == 'Sub Contractor'), isFalse);
    });
  });
}
