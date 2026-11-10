import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const orgId = 'org-test-sobha-01';

  final internalPerson1 = ActionPersonReference(
    personId: '00000000-0000-0000-0000-000000000001',
    name: 'Alice Internal',
    type: PersonType.internalUser,
    email: 'alice@sobha.com',
  );

  final internalPerson2 = ActionPersonReference(
    personId: '00000000-0000-0000-0000-000000000002',
    name: 'Bob Internal',
    type: PersonType.internalUser,
    email: 'bob@sobha.com',
  );

  final externalPerson1 = ActionPersonReference(
    personId: '11111111-1111-1111-1111-111111110001',
    name: 'Charlie Contractor',
    type: PersonType.externalWorker,
    email: 'charlie@contractor.com',
    company: 'Apex Safety',
  );

  setUp(() {
    MockActionStore.instance.actions.clear();
    MockActionStore.instance.externalRecipients.clear();
    MockActionStore.instance.emailReminders.clear();
  });

  group('Step 1: Action Email Reminder Persistence & Reconciliation', () {
    test('1. Reminder OFF by default produces 0 pending reminder jobs', () async {
      final action = ActionRecord(
        id: 'act-persist-001',
        actionNumber: 'ACT-001',
        organizationId: orgId,
        createdById: 'mgr-001',
        subject: 'Audit fire extinguishers',
        actionRequired: 'Inspect pressure gauges',
        division: 'Operations',
        primaryAssignee: internalPerson1,
        assignedTo: internalPerson1.name,
        assignedToId: internalPerson1.personId,
        emailReminderEnabled: false, // Default OFF
        emailReminders: [
          ActionEmailReminder(
            id: 'rem-grp-1',
            date: '10 Oct 2026',
            time: '09:00 AM',
            recipients: [internalPerson1],
          ),
        ],
      );

      final created = await ActionService.instance.createAction(action);
      expect(created.emailReminderEnabled, isFalse);

      final jobs = MockActionStore.instance.emailReminders
          .where((j) => j.actionId == action.id && j.status == 'pending')
          .toList();
      expect(jobs.isEmpty, isTrue);
    });

    test('2. Single internal recipient persists with profileId and recipientType=internal', () async {
      final action = ActionRecord(
        id: 'act-persist-002',
        actionNumber: 'ACT-002',
        organizationId: orgId,
        createdById: 'mgr-001',
        subject: 'Internal safety check',
        actionRequired: 'Check exit doors',
        division: 'Operations',
        primaryAssignee: internalPerson1,
        assignedTo: internalPerson1.name,
        assignedToId: internalPerson1.personId,
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'rem-grp-int',
            date: '12 Oct 2026',
            time: '10:30 AM',
            recipients: [internalPerson1],
          ),
        ],
      );

      await ActionService.instance.createAction(action);

      final jobs = MockActionStore.instance.emailReminders
          .where((j) => j.actionId == action.id && j.status == 'pending')
          .toList();

      expect(jobs.length, 1);
      final job = jobs.first;
      expect(job.reminderGroupId, 'rem-grp-int');
      expect(job.profileId, internalPerson1.personId);
      expect(job.externalRecipientId, isNull);
      expect(job.recipientType, 'internal');
      expect(job.recipientName, 'Alice Internal');
      expect(job.recipientEmail, 'alice@sobha.com');
      expect(job.isInternal, isTrue);
      expect(job.isExternal, isFalse);
    });

    test('3. Single external recipient persists with externalRecipientId and recipientType=external', () async {
      final action = ActionRecord(
        id: 'act-persist-003',
        actionNumber: 'ACT-003',
        organizationId: orgId,
        createdById: 'mgr-001',
        subject: 'Scaffolding load check',
        actionRequired: 'Certify joint couplers',
        division: 'Operations',
        recipientType: 'external',
        primaryAssignee: externalPerson1,
        assignedTo: externalPerson1.name,
        externalRecipientId: externalPerson1.personId,
        externalRecipientEmail: externalPerson1.email,
        externalRecipientName: externalPerson1.name,
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'rem-grp-ext',
            date: '15 Oct 2026',
            time: '02:00 PM',
            recipients: [externalPerson1],
          ),
        ],
      );

      await ActionService.instance.createAction(action);

      final jobs = MockActionStore.instance.emailReminders
          .where((j) => j.actionId == action.id && j.status == 'pending')
          .toList();

      expect(jobs.length, 1);
      final job = jobs.first;
      expect(job.reminderGroupId, 'rem-grp-ext');
      expect(job.externalRecipientId, externalPerson1.personId);
      expect(job.profileId, isNull);
      expect(job.recipientType, 'external');
      expect(job.recipientName, 'Charlie Contractor');
      expect(job.recipientEmail, 'charlie@contractor.com');
      expect(job.isExternal, isTrue);
      expect(job.isInternal, isFalse);
    });

    test('4. Multiple recipients under one schedule share reminderGroupId', () async {
      final action = ActionRecord(
        id: 'act-persist-004',
        actionNumber: 'ACT-004',
        organizationId: orgId,
        createdById: 'mgr-001',
        subject: 'Joint team hazard inspection',
        actionRequired: 'Joint inspection',
        division: 'Operations',
        primaryAssignee: internalPerson1,
        assignedTo: internalPerson1.name,
        additionalPeople: [externalPerson1],
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-joint-schedule-1',
            date: '18 Oct 2026',
            time: '09:00 AM',
            recipients: [internalPerson1, externalPerson1],
          ),
        ],
      );

      await ActionService.instance.createAction(action);

      final jobs = MockActionStore.instance.emailReminders
          .where((j) => j.actionId == action.id && j.status == 'pending')
          .toList();

      expect(jobs.length, 2);
      expect(jobs[0].reminderGroupId, 'grp-joint-schedule-1');
      expect(jobs[1].reminderGroupId, 'grp-joint-schedule-1');
      expect(jobs[0].scheduledAt, jobs[1].scheduledAt);

      final internalJob = jobs.firstWhere((j) => j.recipientType == 'internal');
      final externalJob = jobs.firstWhere((j) => j.recipientType == 'external');

      expect(internalJob.profileId, internalPerson1.personId);
      expect(externalJob.externalRecipientId, externalPerson1.personId);
    });

    test('5. Multiple schedules persist distinct reminderGroupIds and times', () async {
      final action = ActionRecord(
        id: 'act-persist-005',
        actionNumber: 'ACT-005',
        organizationId: orgId,
        createdById: 'mgr-001',
        subject: 'Multi-stage compliance audit',
        actionRequired: 'Multi-stage review',
        division: 'Operations',
        primaryAssignee: internalPerson1,
        assignedTo: internalPerson1.name,
        additionalPeople: [externalPerson1],
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-early-warning',
            date: '10 Oct 2026',
            time: '08:30 AM',
            recipients: [internalPerson1],
          ),
          ActionEmailReminder(
            id: 'grp-final-call',
            date: '20 Oct 2026',
            time: '04:00 PM',
            recipients: [externalPerson1],
          ),
        ],
      );

      await ActionService.instance.createAction(action);

      final jobs = MockActionStore.instance.emailReminders
          .where((j) => j.actionId == action.id && j.status == 'pending')
          .toList();

      expect(jobs.length, 2);

      final job1 = jobs.firstWhere((j) => j.reminderGroupId == 'grp-early-warning');
      final job2 = jobs.firstWhere((j) => j.reminderGroupId == 'grp-final-call');

      expect(job1.recipientEmail, 'alice@sobha.com');
      expect(job1.scheduledAt?.day, 10);
      expect(job1.scheduledAt?.hour, 8);
      expect(job1.scheduledAt?.minute, 30);

      expect(job2.recipientEmail, 'charlie@contractor.com');
      expect(job2.scheduledAt?.day, 20);
      expect(job2.scheduledAt?.hour, 16);
      expect(job2.scheduledAt?.minute, 0);
    });

    test('6. Unselected assigned people do NOT receive reminder rows', () async {
      // Action assigned to 3 people: Alice (Internal), Bob (Internal), Charlie (External)
      final action = ActionRecord(
        id: 'act-persist-006',
        actionNumber: 'ACT-006',
        organizationId: orgId,
        createdById: 'mgr-001',
        subject: 'Electrical panel testing',
        actionRequired: 'Inspect switchgear',
        division: 'Operations',
        primaryAssignee: internalPerson1,
        assignedTo: internalPerson1.name,
        additionalPeople: [internalPerson2, externalPerson1],
        emailReminderEnabled: true,
        // Manager explicitly selects ONLY externalPerson1 (Charlie)
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-selected-only',
            date: '14 Oct 2026',
            time: '11:00 AM',
            recipients: [externalPerson1],
          ),
        ],
      );

      await ActionService.instance.createAction(action);

      final pendingJobs = MockActionStore.instance.emailReminders
          .where((j) => j.actionId == action.id && j.status == 'pending')
          .toList();

      // STRICT CHECK: Only Charlie receives reminder. Alice and Bob receive NOTHING.
      expect(pendingJobs.length, 1);
      expect(pendingJobs.first.recipientName, 'Charlie Contractor');
      expect(
        pendingJobs.any((j) => j.recipientName == 'Alice Internal'),
        isFalse,
      );
      expect(
        pendingJobs.any((j) => j.recipientName == 'Bob Internal'),
        isFalse,
      );
    });

    test('7. Edit/reload re-hydrates schedules and selected recipients', () async {
      final initialAction = ActionRecord(
        id: 'act-persist-007',
        actionNumber: 'ACT-007',
        organizationId: orgId,
        createdById: 'mgr-001',
        subject: 'Crane hydraulics verification',
        actionRequired: 'Check hose fittings',
        division: 'Operations',
        primaryAssignee: internalPerson1,
        assignedTo: internalPerson1.name,
        additionalPeople: [externalPerson1],
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-rehydrate-01',
            date: '22 Oct 2026',
            time: '09:00 AM',
            recipients: [internalPerson1, externalPerson1],
          ),
        ],
      );

      await ActionService.instance.createAction(initialAction);

      // Fetch back from service
      final reloaded = await ActionService.instance.fetchActionById('act-persist-007');
      expect(reloaded, isNotNull);
      expect(reloaded!.emailReminderEnabled, isTrue);
      expect(reloaded.emailReminders.length, 1);

      final loadedReminder = reloaded.emailReminders.first;
      expect(loadedReminder.id, 'grp-rehydrate-01');
      expect(loadedReminder.date, '22 Oct 2026');
      expect(loadedReminder.time, '09:00 AM');
      expect(loadedReminder.recipients.length, 2);

      final loadedRecipNames = loadedReminder.recipients.map((r) => r.name).toSet();
      expect(loadedRecipNames.contains('Alice Internal'), isTrue);
      expect(loadedRecipNames.contains('Charlie Contractor'), isTrue);
    });

    test('8. Removing a recipient cancels only that recipient pending job', () async {
      // 1. Initially create with 2 recipients
      final initialAction = ActionRecord(
        id: 'act-persist-008',
        actionNumber: 'ACT-008',
        organizationId: orgId,
        createdById: 'mgr-001',
        subject: 'Confined space entry prep',
        actionRequired: 'Gas detector calibration',
        division: 'Operations',
        primaryAssignee: internalPerson1,
        assignedTo: internalPerson1.name,
        additionalPeople: [externalPerson1],
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-remove-test',
            date: '25 Oct 2026',
            time: '10:00 AM',
            recipients: [internalPerson1, externalPerson1],
          ),
        ],
      );

      await ActionService.instance.createAction(initialAction);
      expect(
        MockActionStore.instance.emailReminders
            .where((j) => j.actionId == initialAction.id && j.status == 'pending')
            .length,
        2,
      );

      // 2. Manager removes externalPerson1, keeping only internalPerson1
      final updatedAction = initialAction.copyWith(
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-remove-test',
            date: '25 Oct 2026',
            time: '10:00 AM',
            recipients: [internalPerson1], // externalPerson1 removed
          ),
        ],
      );

      await ActionService.instance.updateAction(updatedAction);

      final allJobs = MockActionStore.instance.emailReminders
          .where((j) => j.actionId == initialAction.id)
          .toList();

      final pendingJobs = allJobs.where((j) => j.status == 'pending').toList();
      final cancelledJobs = allJobs.where((j) => j.status == 'cancelled').toList();

      expect(pendingJobs.length, 1);
      expect(pendingJobs.first.recipientName, 'Alice Internal');

      expect(cancelledJobs.length, 1);
      expect(cancelledJobs.first.recipientName, 'Charlie Contractor');
    });

    test('9. Disabling Email Reminder cancels all pending jobs', () async {
      final action = ActionRecord(
        id: 'act-persist-009',
        actionNumber: 'ACT-009',
        organizationId: orgId,
        createdById: 'mgr-001',
        subject: 'Excavation safety check',
        actionRequired: 'Inspect shoring shields',
        division: 'Operations',
        primaryAssignee: internalPerson1,
        assignedTo: internalPerson1.name,
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-disable-test',
            date: '28 Oct 2026',
            time: '01:00 PM',
            recipients: [internalPerson1],
          ),
        ],
      );

      await ActionService.instance.createAction(action);
      expect(
        MockActionStore.instance.emailReminders
            .where((j) => j.actionId == action.id && j.status == 'pending')
            .length,
        1,
      );

      // Manager toggles OFF
      final disabledAction = action.copyWith(emailReminderEnabled: false);
      await ActionService.instance.updateAction(disabledAction);

      final pendingAfterDisable = MockActionStore.instance.emailReminders
          .where((j) => j.actionId == action.id && j.status == 'pending')
          .toList();
      final cancelledAfterDisable = MockActionStore.instance.emailReminders
          .where((j) => j.actionId == action.id && j.status == 'cancelled')
          .toList();

      expect(pendingAfterDisable.isEmpty, isTrue);
      expect(cancelledAfterDisable.length, 1);
    });

    test('10. Idempotency: saving action repeatedly does NOT duplicate pending jobs', () async {
      final action = ActionRecord(
        id: 'act-persist-010',
        actionNumber: 'ACT-010',
        organizationId: orgId,
        createdById: 'mgr-001',
        subject: 'Idempotency verification',
        actionRequired: 'Verify no duplicate queue rows',
        division: 'Operations',
        primaryAssignee: internalPerson1,
        assignedTo: internalPerson1.name,
        emailReminderEnabled: true,
        emailReminders: [
          ActionEmailReminder(
            id: 'grp-idempotent-01',
            date: '30 Oct 2026',
            time: '09:00 AM',
            recipients: [internalPerson1],
          ),
        ],
      );

      // Save once
      await ActionService.instance.createAction(action);
      expect(
        MockActionStore.instance.emailReminders
            .where((j) => j.actionId == action.id && j.status == 'pending')
            .length,
        1,
      );

      // Save again without changes (e.g. updating description)
      final touchedAction = action.copyWith(description: 'Updated notes only');
      await ActionService.instance.updateAction(touchedAction);

      final pendingAfterSecondSave = MockActionStore.instance.emailReminders
          .where((j) => j.actionId == action.id && j.status == 'pending')
          .toList();

      expect(pendingAfterSecondSave.length, 1);
    });
  });
}
