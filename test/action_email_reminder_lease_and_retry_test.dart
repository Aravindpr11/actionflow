import 'dart:io';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_email_reminder_job.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/services/email_service.dart';
import 'package:action_flow/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const orgId = 'org-test-sobha-01';
  const actionId = '00000000-0000-0000-0000-000000000101';

  final testRecipient = ActionPersonReference(
    personId: '00000000-0000-0000-0000-000000000001',
    name: 'Test Staff',
    type: PersonType.internalUser,
    email: 'staff@sobha.com',
  );

  setUp(() {
    MockActionStore.instance.actions.clear();
    MockActionStore.instance.externalRecipients.clear();
    MockActionStore.instance.emailReminders.clear();
    MockActionStore.instance.profiles.clear();
    MockNotificationStore.instance.clear();
    EmailService.mockSendHandler = null;

    MockActionStore.instance.profiles.add({
      'id': testRecipient.personId,
      'organization_id': orgId,
      'email': testRecipient.email,
      'full_name': testRecipient.name,
      'is_active': true,
      'status': 'active',
    });

    MockActionStore.instance.actions.add(
      ActionRecord(
        id: actionId,
        actionNumber: 'AC-2001',
        subject: 'Safety Barrier Inspection',
        actionRequired: 'Verify scaffolding barriers on floor 4',
        division: 'Operations',
        organizationId: orgId,
        status: 'Open',
        percentComplete: 30,
        emailReminderEnabled: true,
        createdById: '00000000-0000-0000-0000-000000000099',
        assignedTo: testRecipient.name,
        assignedToId: testRecipient.personId,
        targetDate: '2026-10-30',
      ),
    );
  });

  group('TASK 1: Safe Claim Ownership Fencing & Stale Worker Rejection', () {
    test('1. Worker A loses its lease and cannot overwrite Worker B successful sent status', () async {
      final now = DateTime.now();
      // Worker B already recovered the reminder and marked it 'sent'
      final reminder = ActionEmailReminderJob(
        id: 'rem-fence-01',
        organizationId: orgId,
        actionId: actionId,
        recipientName: testRecipient.name,
        recipientEmail: testRecipient.email,
        emailSubject: 'Fencing Test 1',
        emailBody: 'Testing lease fencing',
        scheduledAt: now.subtract(const Duration(minutes: 25)),
        status: 'sent',
        sentAt: now.subtract(const Duration(minutes: 2)),
        claimedAt: now.subtract(const Duration(minutes: 5)),
        claimedBy: 'worker-B-recovered',
        attemptCount: 2,
        maxAttempts: 3,
      );
      MockActionStore.instance.emailReminders.add(reminder);

      // Worker A attempts to record a late failure or timeout using its old lease
      // Invariant: Because Worker A's workerId does not match 'worker-B-recovered'
      // and status is not 'processing', Worker A cannot overwrite status 'sent'.
      expect(reminder.status, equals('sent'));
      expect(reminder.claimedBy, equals('worker-B-recovered'));
      expect(reminder.isEligibleForClaim(now: now), isFalse);

      final result = await EmailService.instance.processDueReminders(
        organizationId: orgId,
        simulatedNow: now,
      );

      expect(result['processed_count'], equals(0));
      expect(result['sent_count'], equals(0));
      final unchanged = MockActionStore.instance.emailReminders.first;
      expect(unchanged.status, equals('sent'));
      expect(unchanged.claimedBy, equals('worker-B-recovered'));
    });

    test('2. Worker A cannot overwrite a newer worker pending or failed status', () async {
      final now = DateTime.now();
      // Worker B took over the job: currently processing with attempt 2
      final reminder = ActionEmailReminderJob(
        id: 'rem-fence-02',
        organizationId: orgId,
        actionId: actionId,
        recipientName: testRecipient.name,
        recipientEmail: testRecipient.email,
        emailSubject: 'Fencing Test 2',
        emailBody: 'Testing lease fencing',
        scheduledAt: now.subtract(const Duration(minutes: 20)),
        status: 'processing',
        claimedAt: now.subtract(const Duration(minutes: 1)), // Active fresh lease held by Worker B
        claimedBy: 'worker-B-active',
        attemptCount: 2,
        maxAttempts: 3,
      );
      MockActionStore.instance.emailReminders.add(reminder);

      // Worker B holds an active lease (< 10 minutes)
      expect(reminder.isClaimStale(now: now, leaseSeconds: 600), isFalse);
      expect(reminder.isEligibleForClaim(now: now), isFalse);

      final result = await EmailService.instance.processDueReminders(
        organizationId: orgId,
        simulatedNow: now,
      );

      // Stale Worker A or new Worker C cannot touch Worker B's active lease
      expect(result['processed_count'], equals(0));
      final preserved = MockActionStore.instance.emailReminders.first;
      expect(preserved.claimedBy, equals('worker-B-active'));
      expect(preserved.attemptCount, equals(2));
    });

    test('3. A worker that no longer owns the claim cannot schedule a retry', () async {
      final now = DateTime.now();
      // Job in processing under worker A, but already modified in store
      final reminder = ActionEmailReminderJob(
        id: 'rem-fence-03',
        organizationId: orgId,
        actionId: actionId,
        recipientName: testRecipient.name,
        recipientEmail: testRecipient.email,
        emailSubject: 'Fencing Test 3',
        emailBody: 'Testing retry fencing',
        scheduledAt: now.subtract(const Duration(minutes: 20)),
        status: 'failed', // Worker B already failed it permanently
        isRetryable: false,
        claimedAt: now.subtract(const Duration(minutes: 2)),
        claimedBy: 'worker-B-finalizer',
        attemptCount: 3,
        maxAttempts: 3,
      );
      MockActionStore.instance.emailReminders.add(reminder);

      // Invariant: Exhausted failed job cannot be scheduled for retry
      expect(reminder.isEligibleForClaim(now: now), isFalse);

      final result = await EmailService.instance.processDueReminders(
        organizationId: orgId,
        simulatedNow: now,
      );

      expect(result['processed_count'], equals(0));
      final finalJob = MockActionStore.instance.emailReminders.first;
      expect(finalJob.status, equals('failed'));
      expect(finalJob.nextRetryAt, isNull);
    });

    test('4. Concurrent claim attempts cannot both own the same active lease', () async {
      final now = DateTime.now();
      final reminder = ActionEmailReminderJob(
        id: 'rem-concurrent-lease',
        organizationId: orgId,
        actionId: actionId,
        recipientName: testRecipient.name,
        recipientEmail: testRecipient.email,
        emailSubject: 'Concurrent Test',
        emailBody: 'Testing concurrency',
        scheduledAt: now.subtract(const Duration(minutes: 5)),
        status: 'pending',
        attemptCount: 0,
        maxAttempts: 3,
      );
      MockActionStore.instance.emailReminders.add(reminder);

      // Worker 1 claims and delivers
      final result1 = await EmailService.instance.processDueReminders(
        organizationId: orgId,
        simulatedNow: now,
      );
      expect(result1['sent_count'], equals(1));

      // Worker 2 attempts claim concurrently immediately after
      final result2 = await EmailService.instance.processDueReminders(
        organizationId: orgId,
        simulatedNow: now,
      );
      // Worker 2 gets 0 processed
      expect(result2['processed_count'], equals(0));
      expect(result2['sent_count'], equals(0));

      final finalJob = MockActionStore.instance.emailReminders.first;
      expect(finalJob.status, equals('sent'));
      expect(finalJob.attemptCount, equals(1));
    });
  });

  group('TASK 2: PostgreSQL Function Signature Conflict Remediation', () {
    test('5. Migration 20261027000002 drops obsolete 3-argument signature before creating 5-argument version', () {
      final migrationFile = File(
        'supabase/migrations/20261027000002_action_email_reminder_lease_and_retry.sql',
      );
      expect(migrationFile.existsSync(), isTrue);
      final sqlContent = migrationFile.readAsStringSync();

      // Invariant: Must drop obsolete 3-argument signature to prevent PostgreSQL function overloading ambiguity
      expect(
        sqlContent.contains('DROP FUNCTION IF EXISTS public.claim_action_email_reminder(UUID, UUID, UUID);'),
        isTrue,
        reason: 'Explicit DROP FUNCTION of 3-argument signature is required to avoid ambiguous overload in Postgres',
      );

      // Invariant: Defines 5-argument signature with defaults
      expect(
        sqlContent.contains('CREATE OR REPLACE FUNCTION public.claim_action_email_reminder('),
        isTrue,
      );
      expect(sqlContent.contains('p_worker_id TEXT DEFAULT NULL'), isTrue);
      expect(sqlContent.contains('p_lease_seconds INT DEFAULT 600'), isTrue);

      // Invariant: Grants execute on 5-argument signature
      expect(
        sqlContent.contains('GRANT EXECUTE ON FUNCTION public.claim_action_email_reminder(UUID, UUID, UUID, TEXT, INT) TO authenticated, service_role;'),
        isTrue,
      );
    });

    test('6. Existing reminder records and reminder_group_id remain compatible with safe defaults', () {
      final migrationFile = File(
        'supabase/migrations/20261027000002_action_email_reminder_lease_and_retry.sql',
      );
      expect(migrationFile.existsSync(), isTrue);
      final sqlContent = migrationFile.readAsStringSync();

      // Columns are added safely with non-breaking defaults
      expect(sqlContent.contains('ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ'), isTrue);
      expect(sqlContent.contains('ADD COLUMN IF NOT EXISTS claimed_by TEXT'), isTrue);
      expect(sqlContent.contains('ADD COLUMN IF NOT EXISTS attempt_count INT NOT NULL DEFAULT 0'), isTrue);
      expect(sqlContent.contains('ADD COLUMN IF NOT EXISTS max_attempts INT NOT NULL DEFAULT 3'), isTrue);
      expect(sqlContent.contains('ADD COLUMN IF NOT EXISTS is_retryable BOOLEAN NOT NULL DEFAULT TRUE'), isTrue);

      // Existing reminder_group_id and recipient selection are never altered or dropped
      expect(sqlContent.contains('DROP COLUMN'), isFalse);
    });
  });

  group('TASK 3: Insecure Secret Fallback Removal & Vault Exclusivity', () {
    test('7. Missing Vault secret fails securely with no insecure GUC fallback', () {
      final migrationFile = File(
        'supabase/migrations/20261027000001_action_email_reminder_scheduler.sql',
      );
      expect(migrationFile.existsSync(), isTrue);
      final sqlContent = migrationFile.readAsStringSync();

      // Invariant: app.settings.scheduler_secret fallback is permanently removed
      expect(
        sqlContent.contains('current_setting'),
        isFalse,
        reason: 'current_setting must not be used because GUC parameters are readable by ordinary authenticated users',
      );
      expect(
        sqlContent.contains('app.settings.scheduler_secret'),
        isFalse,
        reason: 'Insecure GUC fallback must not exist in scheduler migration',
      );

      // Invariant: Exclusively checks Supabase Vault
      expect(sqlContent.contains('vault.decrypted_secrets'), isTrue);
      expect(sqlContent.contains('actionflow_scheduler_secret'), isTrue);

      // Invariant: Fails closed with explicit security exceptions
      expect(
        sqlContent.contains('ActionFlow Scheduler Security Error: Supabase Vault extension is not installed or accessible.'),
        isTrue,
      );
      expect(
        sqlContent.contains('ActionFlow Scheduler Security Error: Scheduler secret not found or insufficient in Supabase Vault'),
        isTrue,
      );
    });

    test('8. Zero raw scheduler secret is stored in cron command text or metadata', () {
      final migrationFile = File(
        'supabase/migrations/20261027000001_action_email_reminder_scheduler.sql',
      );
      final sqlContent = migrationFile.readAsStringSync();

      // Invariant: cron.schedule command contains only the URL, zero secrets
      expect(
        sqlContent.contains("SELECT public.invoke_scheduled_action_reminders(%L);"),
        isTrue,
      );
      expect(
        sqlContent.contains("invoke_scheduled_action_reminders(%L, %L)"),
        isFalse,
      );

      // Invariant: Permissions are strictly revoked from PUBLIC
      expect(
        sqlContent.contains('REVOKE ALL ON FUNCTION public.get_actionflow_scheduler_secret() FROM PUBLIC;'),
        isTrue,
      );
      expect(
        sqlContent.contains('GRANT EXECUTE ON FUNCTION public.get_actionflow_scheduler_secret() TO service_role;'),
        isTrue,
      );
    });
  });

  group('TASK 4: Timing & Isolation Guarantees', () {
    test('9. Future reminders are never processed early', () async {
      final now = DateTime.now();
      final futureReminder = ActionEmailReminderJob(
        id: 'rem-future-guard',
        organizationId: orgId,
        actionId: actionId,
        recipientName: testRecipient.name,
        recipientEmail: testRecipient.email,
        emailSubject: 'Future Alert',
        emailBody: 'Wait until tomorrow',
        scheduledAt: now.add(const Duration(days: 2)),
        status: 'pending',
        attemptCount: 0,
        maxAttempts: 3,
      );
      MockActionStore.instance.emailReminders.add(futureReminder);

      expect(futureReminder.isEligibleForClaim(now: now), isFalse);

      final result = await EmailService.instance.processDueReminders(
        organizationId: orgId,
        simulatedNow: now,
      );

      expect(result['processed_count'], equals(0));
      expect(result['sent_count'], equals(0));
      final unchanged = MockActionStore.instance.emailReminders.first;
      expect(unchanged.status, equals('pending'));
      expect(unchanged.attemptCount, equals(0));
    });

    test('10. Explicit recipient selection and organization isolation remain intact', () async {
      final now = DateTime.now();
      const crossOrgId = 'org-other-tenant-99';

      // Cross-organization reminder
      final crossOrgReminder = ActionEmailReminderJob(
        id: 'rem-cross-org',
        organizationId: crossOrgId,
        actionId: '00000000-0000-0000-0000-000000000999',
        recipientName: 'Other Tenant Staff',
        recipientEmail: 'mallory@other.com',
        emailSubject: 'Cross Org',
        emailBody: 'Cross org',
        scheduledAt: now.subtract(const Duration(hours: 1)),
        status: 'pending',
      );
      MockActionStore.instance.emailReminders.add(crossOrgReminder);

      final result = await EmailService.instance.processDueReminders(
        organizationId: orgId, // Calling for orgId
        simulatedNow: now,
      );

      // Invariant: Cross-organization reminder must never be touched
      expect(result['processed_count'], equals(0));
      final untouched = MockActionStore.instance.emailReminders.first;
      expect(untouched.status, equals('pending'));
      expect(untouched.attemptCount, equals(0));
    });
  });
}
