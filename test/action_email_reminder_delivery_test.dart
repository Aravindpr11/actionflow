import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_email_reminder_job.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/external_recipient.dart';
import 'package:action_flow/features/external_update/services/external_action_service.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:action_flow/services/email_service.dart';
import 'package:action_flow/services/notification_service.dart';
import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const orgId1 = 'org-test-sobha-01';
  const orgId2 = 'org-test-other-02';

  final internalAlice = ActionPersonReference(
    personId: '00000000-0000-0000-0000-000000000001',
    name: 'Alice Internal',
    type: PersonType.internalUser,
    email: 'alice@sobha.com',
  );

  final internalBob = ActionPersonReference(
    personId: '00000000-0000-0000-0000-000000000002',
    name: 'Bob Internal',
    type: PersonType.internalUser,
    email: 'bob@sobha.com',
  );

  final externalCharlie = ActionPersonReference(
    personId: '11111111-1111-1111-1111-111111110001',
    name: 'Charlie Contractor',
    type: PersonType.externalWorker,
    email: 'charlie@contractor.com',
    company: 'Apex Safety',
  );

  final externalDan = ActionPersonReference(
    personId: '11111111-1111-1111-1111-111111110002',
    name: 'Dan Contractor',
    type: PersonType.externalWorker,
    email: 'dan@contractor.com',
    company: 'Apex Safety',
  );

  setUp(() {
    MockActionStore.instance.actions.clear();
    MockActionStore.instance.externalRecipients.clear();
    MockActionStore.instance.emailReminders.clear();
    MockActionStore.instance.profiles.clear();
    MockExternalActionStore.instance.reset();
    EmailService.mockSendHandler = null;

    // Register active profiles for org 1
    MockActionStore.instance.profiles.addAll([
      {
        'id': internalAlice.personId,
        'organization_id': orgId1,
        'email': internalAlice.email,
        'full_name': internalAlice.name,
        'is_active': true,
        'status': 'active',
      },
      {
        'id': internalBob.personId,
        'organization_id': orgId1,
        'email': internalBob.email,
        'full_name': internalBob.name,
        'is_active': true,
        'status': 'active',
      },
      {
        'id': '00000000-0000-0000-0000-000000000009',
        'organization_id': orgId2, // Cross-tenant profile
        'email': 'mallory@other.com',
        'full_name': 'Mallory OtherOrg',
        'is_active': true,
        'status': 'active',
      },
      {
        'id': '00000000-0000-0000-0000-000000000008',
        'organization_id': orgId1,
        'email': 'eve.inactive@sobha.com',
        'full_name': 'Eve Inactive',
        'is_active': false,
        'status': 'inactive',
      },
    ]);

    // Register active external recipients for org 1
    MockActionStore.instance.externalRecipients.addAll([
      ExternalRecipient(
        id: externalCharlie.personId,
        organizationId: orgId1,
        fullName: externalCharlie.name,
        email: externalCharlie.email,
        companyName: 'Apex Safety',
        isActive: true,
      ),
      ExternalRecipient(
        id: externalDan.personId,
        organizationId: orgId1,
        fullName: externalDan.name,
        email: externalDan.email,
        companyName: 'Apex Safety',
        isActive: true,
      ),
      ExternalRecipient(
        id: '11111111-1111-1111-1111-111111110009',
        organizationId: orgId2, // Cross-tenant external recipient
        fullName: 'Oscar OtherOrg',
        email: 'oscar@other.com',
        companyName: 'Other Org Co',
        isActive: true,
      ),
      ExternalRecipient(
        id: '11111111-1111-1111-1111-111111110008',
        organizationId: orgId1,
        fullName: 'Frank Inactive',
        email: 'frank.inactive@contractor.com',
        companyName: 'Apex Safety',
        isActive: false,
      ),
    ]);
  });

  group('Phase M: Step 2 Email Reminder Delivery Security & Invariants', () {
    test('1. Internal selected recipient receives reminder', () async {
      final action = ActionRecord(
        id: 'act-deliv-001',
        actionNumber: 'ACT-DELIV-001',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'HVAC Duct Inspection',
        actionRequired: 'Check air filtration units',
        division: 'Operations',
        primaryAssignee: internalBob, // Assigned to Bob
        assignedTo: internalBob.name,
        assignedToId: internalBob.personId,
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-int-1',
            date: '10 Oct 2026',
            time: '09:00 AM',
            recipients: [internalAlice], // Alice explicitly selected
          ),
        ],
      );

      await ActionService.instance.createAction(action);

      // Verify pending job exists for Alice
      final pendingJobs = MockActionStore.instance.emailReminders
          .where((j) => j.actionId == action.id && j.status == 'pending')
          .toList();
      expect(pendingJobs.length, 1);
      expect(pendingJobs.first.recipientEmail, 'alice@sobha.com');

      // Trigger delivery via EmailService
      final result = await EmailService.instance.deliverActionReminder(
        actionId: action.id,
        simulatedNow: DateTime(2026, 10, 10, 10, 0),
      );

      expect(result.isSuccess, isTrue);
      expect(result.status, 'sent');
      expect(result.recipientEmail, 'alice@sobha.com');
      expect(result.recipientType, 'internal');

      // Job status updated to sent
      final updatedJob = MockActionStore.instance.emailReminders
          .firstWhere((j) => j.id == pendingJobs.first.id);
      expect(updatedJob.status, 'sent');
      expect(updatedJob.sentAt, isNotNull);
    });

    test('2. External selected recipient receives reminder', () async {
      final action = ActionRecord(
        id: 'act-deliv-002',
        actionNumber: 'ACT-DELIV-002',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'Scaffolding Certification',
        actionRequired: 'Inspect Tower A scaffolding',
        division: 'Operations',
        primaryAssignee: internalAlice,
        assignedTo: internalAlice.name,
        assignedToId: internalAlice.personId,
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-ext-1',
            date: '10 Oct 2026',
            time: '10:00 AM',
            recipients: [externalCharlie], // Charlie explicitly selected
          ),
        ],
      );

      await ActionService.instance.createAction(action);

      final result = await EmailService.instance.deliverActionReminder(
        actionId: action.id,
        simulatedNow: DateTime(2026, 10, 10, 11, 0),
      );

      expect(result.isSuccess, isTrue);
      expect(result.status, 'sent');
      expect(result.recipientEmail, 'charlie@contractor.com');
      expect(result.recipientType, 'external');
      expect(result.externalUpdateUrl, isNotNull);
      expect(result.externalUpdateUrl, contains('/external-update?token='));
    });

    test('3. Unselected assigned user does NOT receive reminder', () async {
      final action = ActionRecord(
        id: 'act-deliv-003',
        actionNumber: 'ACT-DELIV-003',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'Chemical Store Audit',
        actionRequired: 'Verify bunding',
        division: 'Operations',
        primaryAssignee: internalBob, // Assigned to Bob
        assignedTo: internalBob.name,
        assignedToId: internalBob.personId,
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-sel-1',
            date: '10 Oct 2026',
            time: '09:00 AM',
            recipients: [internalAlice], // ONLY Alice selected, Bob is NOT selected
          ),
        ],
      );

      await ActionService.instance.createAction(action);

      // Verify NO reminder was created for Bob
      final bobJobs = MockActionStore.instance.emailReminders
          .where((j) => j.actionId == action.id && j.profileId == internalBob.personId)
          .toList();
      expect(bobJobs.isEmpty, isTrue);

      // Only Alice receives delivery
      final result = await EmailService.instance.deliverActionReminder(
        actionId: action.id,
        simulatedNow: DateTime(2026, 10, 10, 10, 0),
      );
      expect(result.recipientEmail, isNot(equals(internalBob.email)));
      expect(result.recipientEmail, equals(internalAlice.email));
    });

    test('4. Unselected external user does NOT receive reminder', () async {
      final action = ActionRecord(
        id: 'act-deliv-004',
        actionNumber: 'ACT-DELIV-004',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'Facade Cladding Check',
        actionRequired: 'Check fire stop barrier',
        division: 'Operations',
        primaryAssignee: externalCharlie,
        assignedTo: externalCharlie.name,
        assignedToId: externalCharlie.personId,
        additionalPeople: [externalDan],
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-sel-ext',
            date: '10 Oct 2026',
            time: '09:00 AM',
            recipients: [externalCharlie], // ONLY Charlie selected, Dan is NOT selected
          ),
        ],
      );

      await ActionService.instance.createAction(action);

      // Verify NO reminder was created for Dan
      final danJobs = MockActionStore.instance.emailReminders
          .where((j) => j.actionId == action.id && j.externalRecipientId == externalDan.personId)
          .toList();
      expect(danJobs.isEmpty, isTrue);

      final result = await EmailService.instance.deliverActionReminder(
        actionId: action.id,
        simulatedNow: DateTime(2026, 10, 10, 10, 0),
      );
      expect(result.recipientEmail, isNot(equals(externalDan.email)));
      expect(result.recipientEmail, equals(externalCharlie.email));
    });

    test('5. Arbitrary caller-supplied email cannot redirect delivery', () async {
      final action = ActionRecord(
        id: 'act-deliv-005',
        actionNumber: 'ACT-DELIV-005',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'Confined Space Permit Verification',
        actionRequired: 'Review gas test logs',
        division: 'Operations',
        primaryAssignee: internalAlice,
        assignedTo: internalAlice.name,
        assignedToId: internalAlice.personId,
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-anti-hijack',
            date: '10 Oct 2026',
            time: '09:00 AM',
            recipients: [internalAlice],
          ),
        ],
      );

      await ActionService.instance.createAction(action);

      // Caller attempts to pass an arbitrary attacker email override
      final result = await EmailService.instance.deliverActionReminder(
        actionId: action.id,
        callerEmailOverride: 'attacker@malicious.com',
        simulatedNow: DateTime(2026, 10, 10, 10, 0),
      );

      // Delivery strictly uses the database-resolved email
      expect(result.isSuccess, isTrue);
      expect(result.recipientEmail, equals('alice@sobha.com'));
      expect(result.recipientEmail, isNot(equals('attacker@malicious.com')));
    });

    test('6. Cross-organization reminder cannot be delivered', () async {
      final action = ActionRecord(
        id: 'act-deliv-006',
        actionNumber: 'ACT-DELIV-006',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'Emergency Lighting Test',
        actionRequired: 'Discharge test 3 hours',
        division: 'Operations',
        primaryAssignee: internalAlice,
        assignedTo: internalAlice.name,
        assignedToId: internalAlice.personId,
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-iso-1',
            date: '10 Oct 2026',
            time: '09:00 AM',
            recipients: [internalAlice],
          ),
        ],
      );

      await ActionService.instance.createAction(action);

      // Caller from a different organization attempts dispatch
      final result = await EmailService.instance.deliverActionReminder(
        actionId: action.id,
        callerOrganizationId: orgId2,
        simulatedNow: DateTime(2026, 10, 10, 10, 0),
      );

      expect(result.isSuccess, isFalse);
      expect(result.status, equals('forbidden'));
      expect(result.errorMessage, contains('Cross-organization'));
    });

    test('7. Cross-organization internal profile cannot be used', () async {
      final action = ActionRecord(
        id: 'act-deliv-007',
        actionNumber: 'ACT-DELIV-007',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'Spill Kit Maintenance',
        actionRequired: 'Replace absorbent pads',
        division: 'Operations',
        assignedTo: 'Alice',
        emailReminderEnabled: true,
      );
      MockActionStore.instance.add(action);

      // Malformed/injected reminder row pointing to an internal user from Org 2
      final injectedJob = ActionEmailReminderJob(
        id: 'job-cross-prof',
        organizationId: orgId1,
        actionId: action.id,
        recipientType: 'internal',
        profileId: '00000000-0000-0000-0000-000000000009', // Mallory from Org 2
        recipientName: 'Mallory OtherOrg',
        recipientEmail: 'mallory@other.com',
        emailSubject: 'Reminder',
        emailBody: 'Body',
        status: 'pending',
      );
      MockActionStore.instance.emailReminders.add(injectedJob);

      final result = await EmailService.instance.deliverActionReminder(
        actionId: action.id,
        reminderId: injectedJob.id,
      );

      expect(result.isSuccess, isFalse);
      expect(result.status, equals('forbidden'));
      expect(result.errorMessage, contains('Cross-organization'));

      // Job is marked failed
      final jobInStore = MockActionStore.instance.emailReminders
          .firstWhere((j) => j.id == injectedJob.id);
      expect(jobInStore.status, equals('failed'));
    });

    test('8. Cross-organization external recipient cannot be used', () async {
      final action = ActionRecord(
        id: 'act-deliv-008',
        actionNumber: 'ACT-DELIV-008',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'Crane Load Test',
        actionRequired: 'Annual certified load test',
        division: 'Operations',
        assignedTo: 'Alice',
        emailReminderEnabled: true,
      );
      MockActionStore.instance.add(action);

      // Malformed reminder pointing to an external contractor from Org 2
      final injectedJob = ActionEmailReminderJob(
        id: 'job-cross-ext',
        organizationId: orgId1,
        actionId: action.id,
        recipientType: 'external',
        externalRecipientId: '11111111-1111-1111-1111-111111110009', // Oscar from Org 2
        recipientName: 'Oscar OtherOrg',
        recipientEmail: 'oscar@other.com',
        emailSubject: 'Reminder',
        emailBody: 'Body',
        status: 'pending',
      );
      MockActionStore.instance.emailReminders.add(injectedJob);

      final result = await EmailService.instance.deliverActionReminder(
        actionId: action.id,
        reminderId: injectedJob.id,
      );

      expect(result.isSuccess, isFalse);
      expect(result.status, equals('forbidden'));
      expect(result.errorMessage, contains('Cross-organization'));

      final jobInStore = MockActionStore.instance.emailReminders
          .firstWhere((j) => j.id == injectedJob.id);
      expect(jobInStore.status, equals('failed'));
    });

    test('9. Cancelled reminder is not sent', () async {
      final action = ActionRecord(
        id: 'act-deliv-009',
        actionNumber: 'ACT-DELIV-009',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'Ear Protection Signage',
        actionRequired: 'Post high-noise warning signs',
        division: 'Operations',
        assignedTo: 'Alice',
        emailReminderEnabled: true,
      );
      MockActionStore.instance.add(action);

      final cancelledJob = ActionEmailReminderJob(
        id: 'job-cancelled-1',
        organizationId: orgId1,
        actionId: action.id,
        recipientType: 'internal',
        profileId: internalAlice.personId,
        recipientName: internalAlice.name,
        recipientEmail: internalAlice.email,
        emailSubject: 'Reminder',
        emailBody: 'Body',
        status: 'cancelled', // Already cancelled
      );
      MockActionStore.instance.emailReminders.add(cancelledJob);

      final result = await EmailService.instance.deliverActionReminder(
        actionId: action.id,
        reminderId: cancelledJob.id,
      );

      expect(result.isSuccess, isFalse);
      expect(result.status, equals('cancelled'));
      expect(result.errorMessage, contains('cancelled'));
    });

    test('10. Disabled reminder is not sent', () async {
      final action = ActionRecord(
        id: 'act-deliv-010',
        actionNumber: 'ACT-DELIV-010',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'First Aid Kit Restock',
        actionRequired: 'Replace burn dressings',
        division: 'Operations',
        assignedTo: 'Alice',
        emailReminderEnabled: false, // OFF
      );
      MockActionStore.instance.add(action);

      final result = await EmailService.instance.deliverActionReminder(
        actionId: action.id,
      );

      expect(result.isSuccess, isFalse);
      expect(result.status, equals('reminders_disabled'));
    });

    test('11. Closed action reminder is not sent', () async {
      final action = ActionRecord(
        id: 'act-deliv-011',
        actionNumber: 'ACT-DELIV-011',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'Eyewash Station Flush',
        actionRequired: 'Flush weekly',
        division: 'Operations',
        assignedTo: 'Alice',
        status: 'Closed', // Action is closed
        emailReminderEnabled: true,
      );
      MockActionStore.instance.add(action);

      final result = await EmailService.instance.deliverActionReminder(
        actionId: action.id,
      );

      expect(result.isSuccess, isFalse);
      expect(result.status, equals('action_closed'));
      expect(result.errorMessage, contains('closed'));
    });

    test('12. Future reminder is not sent early', () async {
      final futureDate = DateTime.now().add(const Duration(days: 3));

      final action = ActionRecord(
        id: 'act-deliv-012',
        actionNumber: 'ACT-DELIV-012',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'Annual Evacuation Drill',
        actionRequired: 'Schedule siren test',
        division: 'Operations',
        assignedTo: 'Alice',
        emailReminderEnabled: true,
      );
      MockActionStore.instance.add(action);

      final futureJob = ActionEmailReminderJob(
        id: 'job-future-1',
        organizationId: orgId1,
        actionId: action.id,
        recipientType: 'internal',
        profileId: internalAlice.personId,
        recipientName: internalAlice.name,
        recipientEmail: internalAlice.email,
        emailSubject: 'Future Reminder',
        emailBody: 'Body',
        scheduledAt: futureDate,
        status: 'pending',
      );
      MockActionStore.instance.emailReminders.add(futureJob);

      // 12.1 Running now: Rejected (not yet due)
      final earlyResult = await EmailService.instance.deliverActionReminder(
        actionId: action.id,
        reminderId: futureJob.id,
        simulatedNow: DateTime.now(),
      );

      expect(earlyResult.isSuccess, isFalse);
      expect(earlyResult.status, equals('scheduled_in_future'));

      // 12.2 Running when due: Delivery succeeds
      final dueResult = await EmailService.instance.deliverActionReminder(
        actionId: action.id,
        reminderId: futureJob.id,
        simulatedNow: futureDate.add(const Duration(minutes: 5)),
      );

      expect(dueResult.isSuccess, isTrue);
      expect(dueResult.status, equals('sent'));
    });

    test('13. Already-sent reminder is not sent again', () async {
      final action = ActionRecord(
        id: 'act-deliv-013',
        actionNumber: 'ACT-DELIV-013',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'Forklift Pre-use Check',
        actionRequired: 'Inspect brakes and horn',
        division: 'Operations',
        assignedTo: 'Alice',
        emailReminderEnabled: true,
      );
      MockActionStore.instance.add(action);

      final sentJob = ActionEmailReminderJob(
        id: 'job-sent-1',
        organizationId: orgId1,
        actionId: action.id,
        recipientType: 'internal',
        profileId: internalAlice.personId,
        recipientName: internalAlice.name,
        recipientEmail: internalAlice.email,
        emailSubject: 'Sent Reminder',
        emailBody: 'Body',
        status: 'sent',
        sentAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      MockActionStore.instance.emailReminders.add(sentJob);

      final result = await EmailService.instance.deliverActionReminder(
        actionId: action.id,
        reminderId: sentJob.id,
      );

      expect(result.isSuccess, isFalse);
      expect(result.status, equals('already_sent'));
    });

    test('14. Multiple recipients produce separate intended deliveries', () async {
      final action = ActionRecord(
        id: 'act-deliv-014',
        actionNumber: 'ACT-DELIV-014',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'Hot Work Permit Review',
        actionRequired: 'Inspect spark screens',
        division: 'Operations',
        assignedTo: 'Alice',
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-multi-recips',
            date: '10 Oct 2026',
            time: '09:00 AM',
            recipients: [internalAlice, externalCharlie], // Both selected
          ),
        ],
      );

      await ActionService.instance.createAction(action);

      final jobs = MockActionStore.instance.emailReminders
          .where((j) => j.actionId == action.id && j.status == 'pending')
          .toList();
      expect(jobs.length, 2);

      // Deliver first (internal)
      final res1 = await EmailService.instance.deliverActionReminder(
        actionId: action.id,
        reminderId: jobs.firstWhere((j) => j.recipientType == 'internal').id,
        simulatedNow: DateTime(2026, 10, 10, 10, 0),
      );
      expect(res1.isSuccess, isTrue);
      expect(res1.recipientEmail, 'alice@sobha.com');
      expect(res1.externalUpdateUrl, isNull);

      // Deliver second (external)
      final res2 = await EmailService.instance.deliverActionReminder(
        actionId: action.id,
        reminderId: jobs.firstWhere((j) => j.recipientType == 'external').id,
        simulatedNow: DateTime(2026, 10, 10, 10, 0),
      );
      expect(res2.isSuccess, isTrue);
      expect(res2.recipientEmail, 'charlie@contractor.com');
      expect(res2.externalUpdateUrl, isNotNull);
    });

    test('15. Multiple schedules remain independent', () async {
      final action = ActionRecord(
        id: 'act-deliv-015',
        actionNumber: 'ACT-DELIV-015',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'Daily Gas Monitoring',
        actionRequired: 'Monitor H2S levels',
        division: 'Operations',
        assignedTo: 'Alice',
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-sched-morning',
            date: '10 Oct 2026',
            time: '08:00 AM',
            recipients: [internalAlice],
          ),
          ActionEmailReminder(
            id: 'grp-sched-evening',
            date: '10 Oct 2026',
            time: '05:00 PM',
            recipients: [internalBob],
          ),
        ],
      );

      await ActionService.instance.createAction(action);

      // Deliver at 09:00 AM: Morning schedule is due, Evening schedule is NOT yet due
      final morningResult = await EmailService.instance.deliverActionReminder(
        actionId: action.id,
        simulatedNow: DateTime(2026, 10, 10, 9, 0),
      );
      expect(morningResult.isSuccess, isTrue);
      expect(morningResult.recipientEmail, 'alice@sobha.com');

      // Evening schedule remains pending
      final remainingPending = MockActionStore.instance.emailReminders
          .where((j) => j.actionId == action.id && j.status == 'pending')
          .toList();
      expect(remainingPending.length, 1);
      expect(remainingPending.first.recipientEmail, 'bob@sobha.com');
    });

    test('16. External reminder gets the existing secure update link', () async {
      final action = ActionRecord(
        id: 'act-deliv-016',
        actionNumber: 'ACT-DELIV-016',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'External Insulation Repair',
        actionRequired: 'Repair lagging on boiler feed pipe',
        division: 'Operations',
        assignedTo: 'Charlie',
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-token-test',
            date: '10 Oct 2026',
            time: '09:00 AM',
            recipients: [externalCharlie],
          ),
        ],
      );

      await ActionService.instance.createAction(action);

      final result = await EmailService.instance.deliverActionReminder(
        actionId: action.id,
        simulatedNow: DateTime(2026, 10, 10, 10, 0),
      );

      expect(result.isSuccess, isTrue);
      expect(result.externalUpdateUrl, isNotNull);
      final uri = Uri.parse(result.externalUpdateUrl!);
      final rawToken = uri.queryParameters['token'];
      expect(rawToken, isNotNull);
      expect(rawToken!.isNotEmpty, isTrue);

      // Verify the token works directly with ExternalActionService
      final fetchResult = await ExternalActionService.instance.fetchActionByToken(rawToken);
      expect(fetchResult, isA<ExternalActionFetchSuccess>());
      final payload = (fetchResult as ExternalActionFetchSuccess).payload;
      expect(payload.actionId, action.id);
      expect(payload.recipientEmail, externalCharlie.email);
    });

    test('17. Internal reminder does NOT expose external update functionality', () async {
      final action = ActionRecord(
        id: 'act-deliv-017',
        actionNumber: 'ACT-DELIV-017',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'Monthly Safety Committee Meeting',
        actionRequired: 'Review incident reports',
        division: 'Operations',
        assignedTo: 'Alice',
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-no-ext-url',
            date: '10 Oct 2026',
            time: '09:00 AM',
            recipients: [internalAlice],
          ),
        ],
      );

      await ActionService.instance.createAction(action);

      final result = await EmailService.instance.deliverActionReminder(
        actionId: action.id,
        simulatedNow: DateTime(2026, 10, 10, 10, 0),
      );

      expect(result.isSuccess, isTrue);
      expect(result.externalUpdateUrl, isNull);
    });

    test('18. Repeated worker invocation does not duplicate delivery', () async {
      final action = ActionRecord(
        id: 'act-deliv-018',
        actionNumber: 'ACT-DELIV-018',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'Boiler Blowdown Check',
        actionRequired: 'Perform weekly blowdown',
        division: 'Operations',
        assignedTo: 'Alice',
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-dedup-1',
            date: '10 Oct 2026',
            time: '09:00 AM',
            recipients: [internalAlice],
          ),
        ],
      );

      await ActionService.instance.createAction(action);

      // First worker run -> successfully delivers
      final run1 = await EmailService.instance.deliverActionReminder(
        actionId: action.id,
        simulatedNow: DateTime(2026, 10, 10, 10, 0),
      );
      expect(run1.isSuccess, isTrue);
      expect(run1.status, 'sent');

      // Second worker run immediately after -> 0 duplicate sends
      final run2 = await EmailService.instance.deliverActionReminder(
        actionId: action.id,
        simulatedNow: DateTime(2026, 10, 10, 10, 1),
      );
      expect(run2.isSuccess, isFalse);
      expect(run2.status, 'no_pending_reminders');
    });

    test('19. Failed delivery follows the existing retry/error behavior', () async {
      final action = ActionRecord(
        id: 'act-deliv-019',
        actionNumber: 'ACT-DELIV-019',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'Gas Detector Calibration',
        actionRequired: 'Calibrate multi-gas monitor',
        division: 'Operations',
        assignedTo: 'Alice',
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-fail-test',
            date: '10 Oct 2026',
            time: '09:00 AM',
            recipients: [internalAlice],
          ),
        ],
      );

      await ActionService.instance.createAction(action);

      // Simulate provider transmission failure
      final failResult = await EmailService.instance.deliverActionReminder(
        actionId: action.id,
        simulatedNow: DateTime(2026, 10, 10, 10, 0),
        simulateProviderFailure: true,
      );

      expect(failResult.isSuccess, isFalse);
      expect(failResult.status, 'failed');
      expect(failResult.errorMessage, contains('Simulated Resend API delivery error'));

      final job = MockActionStore.instance.emailReminders
          .firstWhere((j) => j.actionId == action.id);
      expect(job.status, 'failed');
      expect(job.failureReason, contains('Simulated Resend API delivery error'));
    });

    test('20. Tenant isolation remains intact', () async {
      // Create action in Org 1
      final actionOrg1 = ActionRecord(
        id: 'act-org1-020',
        actionNumber: 'ACT-ORG1-020',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'Org 1 Action',
        actionRequired: 'Work 1',
        division: 'Operations',
        assignedTo: 'Alice',
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-org1',
            date: '10 Oct 2026',
            time: '09:00 AM',
            recipients: [internalAlice],
          ),
        ],
      );
      await ActionService.instance.createAction(actionOrg1);

      // Create action in Org 2
      final actionOrg2 = ActionRecord(
        id: 'act-org2-020',
        actionNumber: 'ACT-ORG2-020',
        organizationId: orgId2,
        createdById: 'mgr-002',
        subject: 'Org 2 Action',
        actionRequired: 'Work 2',
        division: 'Operations',
        assignedTo: 'Mallory',
        emailReminderEnabled: true,
      );
      MockActionStore.instance.add(actionOrg2);
      MockActionStore.instance.emailReminders.add(
        ActionEmailReminderJob(
          id: 'job-org2-rem',
          organizationId: orgId2,
          actionId: actionOrg2.id,
          recipientType: 'internal',
          profileId: '00000000-0000-0000-0000-000000000009',
          recipientName: 'Mallory OtherOrg',
          recipientEmail: 'mallory@other.com',
          emailSubject: 'Org 2 Subject',
          emailBody: 'Org 2 Body',
          status: 'pending',
        ),
      );

      // Deliver for Org 1: Only Org 1 reminder is processed
      final resOrg1 = await EmailService.instance.deliverActionReminder(
        actionId: actionOrg1.id,
        callerOrganizationId: orgId1,
        simulatedNow: DateTime(2026, 10, 10, 10, 0),
      );
      expect(resOrg1.isSuccess, isTrue);
      expect(resOrg1.recipientEmail, 'alice@sobha.com');

      // Org 2 reminder remains untouched and pending
      final org2Job = MockActionStore.instance.emailReminders
          .firstWhere((j) => j.id == 'job-org2-rem');
      expect(org2Job.status, 'pending');

      // Cross-tenant attempt fails
      final crossRes = await EmailService.instance.deliverActionReminder(
        actionId: actionOrg2.id,
        callerOrganizationId: orgId1,
      );
      expect(crossRes.isSuccess, isFalse);
      expect(crossRes.status, 'forbidden');
    });

    test('21. processDueReminders processes due pending reminders and cancels closed actions', () async {
      // 1. Action with due reminder (open)
      final actionOpen = ActionRecord(
        id: 'act-batch-001',
        actionNumber: 'ACT-BATCH-001',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'Batch Open Action',
        actionRequired: 'Inspect pump',
        division: 'Operations',
        assignedTo: 'Alice',
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-batch-1',
            date: '10 Oct 2026',
            time: '09:00 AM',
            recipients: [internalAlice],
          ),
        ],
      );
      await ActionService.instance.createAction(actionOpen);

      // 2. Action created open, then closed
      final actionClosed = ActionRecord(
        id: 'act-batch-002',
        actionNumber: 'ACT-BATCH-002',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'Batch Closed Action',
        actionRequired: 'Replace valve',
        division: 'Operations',
        assignedTo: 'Bob',
        status: 'Open',
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-batch-2',
            date: '10 Oct 2026',
            time: '09:00 AM',
            recipients: [internalBob],
          ),
        ],
      );
      await ActionService.instance.createAction(actionClosed);

      // Directly close the action in store
      final closeIdx = MockActionStore.instance.actions
          .indexWhere((a) => a.id == actionClosed.id);
      MockActionStore.instance.actions[closeIdx] = actionClosed.copyWith(
        status: 'Closed',
        percentComplete: 100,
      );

      // Execute batch processor as of 10 Oct 2026 10:00 AM
      final batchResult = await EmailService.instance.processDueReminders(
        organizationId: orgId1,
        simulatedNow: DateTime(2026, 10, 10, 10, 0),
      );

      expect(batchResult['success'], isTrue);
      expect(batchResult['sent_count'], 1);
      expect(batchResult['cancelled_count'], 1);

      final openJob = MockActionStore.instance.emailReminders
          .firstWhere((j) => j.actionId == actionOpen.id);
      expect(openJob.status, 'sent');
      expect(openJob.sentAt, isNotNull);

      final closedJob = MockActionStore.instance.emailReminders
          .firstWhere((j) => j.actionId == actionClosed.id);
      expect(closedJob.status, 'cancelled');
    });

    test('22. processDueReminders skips future scheduled reminders', () async {
      final actionFuture = ActionRecord(
        id: 'act-batch-future',
        actionNumber: 'ACT-BATCH-FUT',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'Future Scheduled Action',
        actionRequired: 'Future check',
        division: 'Operations',
        assignedTo: 'Alice',
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-batch-future',
            date: '15 Oct 2026',
            time: '09:00 AM',
            recipients: [internalAlice],
          ),
        ],
      );
      await ActionService.instance.createAction(actionFuture);

      // Run processor on 10 Oct 2026 (5 days prior to scheduled date)
      final batchResult = await EmailService.instance.processDueReminders(
        organizationId: orgId1,
        simulatedNow: DateTime(2026, 10, 10, 10, 0),
      );

      expect(batchResult['success'], isTrue);
      expect(batchResult['processed_count'], 0);
      expect(batchResult['sent_count'], 0);

      final job = MockActionStore.instance.emailReminders
          .firstWhere((j) => j.actionId == actionFuture.id);
      expect(job.status, 'pending');
    });

    test('23. processDueReminders synchronizes matching in-app notification for internal recipients', () async {
      final actionWithNotif = ActionRecord(
        id: 'act-batch-notif',
        actionNumber: 'ACT-BATCH-NOTIF',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'Action With Notif Sync',
        actionRequired: 'Check alarm',
        division: 'Operations',
        assignedTo: 'Alice',
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-batch-notif-1',
            date: '10 Oct 2026',
            time: '09:00 AM',
            recipients: [internalAlice],
          ),
        ],
      );
      await ActionService.instance.createAction(actionWithNotif);

      // Process due reminders
      final res = await EmailService.instance.processDueReminders(
        organizationId: orgId1,
        simulatedNow: DateTime(2026, 10, 10, 10, 0),
      );
      expect(res['sent_count'], 1);

      // In-app notification was generated for Alice
      final notifs = await NotificationService.instance
          .getNotifications(userId: internalAlice.personId);
      final matchingNotif = notifs.firstWhereOrNull(
        (n) => n.userId == internalAlice.personId && n.actionId == actionWithNotif.actionNumber,
      );
      expect(matchingNotif, isNotNull);
      expect(matchingNotif!.idempotencyKey, contains('batch_rem_'));
    });

    test('24. processDueReminders re-execution is strictly idempotent (zero duplicates)', () async {
      final actionIdemp = ActionRecord(
        id: 'act-batch-idemp',
        actionNumber: 'ACT-BATCH-IDEMP',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'Idempotency Action',
        actionRequired: 'Verify safety barrier',
        division: 'Operations',
        assignedTo: 'Alice',
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-batch-idemp',
            date: '10 Oct 2026',
            time: '09:00 AM',
            recipients: [internalAlice],
          ),
        ],
      );
      await ActionService.instance.createAction(actionIdemp);

      // First run: sends 1 reminder
      final run1 = await EmailService.instance.processDueReminders(
        organizationId: orgId1,
        simulatedNow: DateTime(2026, 10, 10, 10, 0),
      );
      expect(run1['sent_count'], 1);

      // Second run immediately after: 0 sent, 0 processed
      final run2 = await EmailService.instance.processDueReminders(
        organizationId: orgId1,
        simulatedNow: DateTime(2026, 10, 10, 10, 1),
      );
      expect(run2['processed_count'], 0);
      expect(run2['sent_count'], 0);
    });

    // -------------------------------------------------------------------------
    // 25. Concurrent worker claim simulation (atomic lock)
    // -------------------------------------------------------------------------
    test('25. Concurrent worker simulation: atomic claim prevents duplicate dispatches', () async {
      final actionConcurrent = ActionRecord(
        id: 'act-batch-concurrent',
        actionNumber: 'ACT-BATCH-CONC',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'Concurrent Safety Audit',
        actionRequired: 'Verify zero double-send',
        division: 'Operations',
        assignedTo: 'Alice',
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-batch-conc',
            date: '10 Oct 2026',
            time: '09:00 AM',
            recipients: [internalAlice],
          ),
        ],
      );
      await ActionService.instance.createAction(actionConcurrent);

      // Simulate two concurrent worker executions firing simultaneously at the 15-minute mark
      final now = DateTime(2026, 10, 10, 9, 15);
      final futures = [
        EmailService.instance.processDueReminders(organizationId: orgId1, simulatedNow: now),
        EmailService.instance.processDueReminders(organizationId: orgId1, simulatedNow: now),
      ];

      final results = await Future.wait(futures);
      final totalSent = results.fold<int>(0, (sum, r) => sum + (r['sent_count'] as int));
      expect(totalSent, 1, reason: 'Exactly one worker must claim and send the reminder');
    });

    // -------------------------------------------------------------------------
    // 26. Notification table failure does not mark sent email as failed
    // -------------------------------------------------------------------------
    test('26. In-app notification synchronization failure does not mark email as failed', () async {
      final actionWithSync = ActionRecord(
        id: 'act-batch-notif-fail',
        actionNumber: 'ACT-BATCH-NFAIL',
        organizationId: orgId1,
        createdById: 'mgr-001',
        subject: 'Notification Isolation Test',
        actionRequired: 'Verify email remains sent even if notifications fail',
        division: 'Operations',
        assignedTo: 'Alice',
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-batch-nfail',
            date: '10 Oct 2026',
            time: '09:00 AM',
            recipients: [internalAlice],
          ),
        ],
      );
      await ActionService.instance.createAction(actionWithSync);

      // Simulate notification service error or unmigrated table
      NotificationService.useMockOnly = true;

      final res = await EmailService.instance.processDueReminders(
        organizationId: orgId1,
        simulatedNow: DateTime(2026, 10, 10, 10, 0),
      );

      expect(res['success'], isTrue);
      expect(res['sent_count'], 1);

      final job = MockActionStore.instance.emailReminders
          .firstWhere((j) => j.actionId == actionWithSync.id);
      expect(job.status, 'sent');
      expect(job.failureReason, isNull);
    });
  });
}
