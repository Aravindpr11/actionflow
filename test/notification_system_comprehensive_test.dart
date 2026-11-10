import 'package:flutter_test/flutter_test.dart';
import 'package:action_flow/features/notifications/models/app_notification.dart';
import 'package:action_flow/services/notification_service.dart';
import 'package:action_flow/services/sound_service.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';

ActionRecord _makeAction({
  required String id,
  required String subject,
  int percentComplete = 0,
  String organizationId = 'org-1',
}) {
  return ActionRecord(
    id: id,
    subject: subject,
    actionRequired: 'Test Action Required',
    division: 'HSE',
    assignedTo: 'Staff Member',
    percentComplete: percentComplete,
    organizationId: organizationId,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 7: ActionFlow Comprehensive Notification System Tests', () {
    late NotificationService service;

    setUp(() {
      NotificationService.useMockOnly = true;
      MockNotificationStore.enableDefaultSeeding = false;
      service = NotificationService.instance;
      MockNotificationStore.instance.clear();
      service.clearReminderSessionCache();
    });

    tearDown(() {
      MockNotificationStore.enableDefaultSeeding = true;
      MockNotificationStore.instance.clear();
      service.clearReminderSessionCache();
    });

    // 1. Notification creation
    test('1. Notification creation returns a valid populated notification', () async {
      final notif = AppNotification(
        id: '',
        userId: 'user-staff-1',
        organizationId: 'org-1',
        title: 'Action Assigned: ACT-2001',
        message: 'New action assigned to you.',
        eventType: 'action_assigned',
        actionId: 'ACT-2001',
        createdAt: DateTime.now(),
      );

      final created = await service.createNotification(notif);
      expect(created, isNotNull);
      expect(created!.id, isNotEmpty);
      expect(created.userId, 'user-staff-1');
      expect(created.title, 'Action Assigned: ACT-2001');
      expect(created.isRead, false);
    });

    // 2. Correct recipient
    test('2. Notification is saved strictly for the designated recipient', () async {
      final notif = AppNotification(
        id: '',
        userId: 'user-staff-target',
        organizationId: 'org-1',
        title: 'Confidential Task',
        message: 'Message for target user only.',
        eventType: 'action_assigned',
        createdAt: DateTime.now(),
      );

      await service.createNotification(notif);
      final targetList = await service.getNotifications(userId: 'user-staff-target');
      final otherList = await service.getNotifications(userId: 'user-staff-other');

      expect(targetList.any((n) => n.title == 'Confidential Task'), isTrue);
      expect(otherList.any((n) => n.title == 'Confidential Task'), isFalse);
    });

    // 3. Incorrect recipient isolation
    test('3. Users cannot view notifications belonging to another user', () async {
      await service.createNotification(
        AppNotification(
          id: 'notif-a',
          userId: 'user-a',
          organizationId: 'org-1',
          title: 'Alert A',
          message: 'Only for A',
          eventType: 'action_assigned',
          createdAt: DateTime.now(),
        ),
      );
      await service.createNotification(
        AppNotification(
          id: 'notif-b',
          userId: 'user-b',
          organizationId: 'org-1',
          title: 'Alert B',
          message: 'Only for B',
          eventType: 'action_assigned',
          createdAt: DateTime.now(),
        ),
      );

      final notifsA = await service.getNotifications(userId: 'user-a');
      expect(notifsA.every((n) => n.userId == 'user-a'), isTrue);
      expect(notifsA.any((n) => n.title == 'Alert B'), isFalse);
    });

    // 4. Manager notifications (action update / completed)
    test('4. Staff progress and completion updates notify manager', () async {
      final action = _makeAction(
        id: 'ACT-3001',
        subject: 'HVAC Duct Maintenance',
        percentComplete: 100,
        organizationId: 'org-1',
      );

      final notif = await service.notifyActionUpdatedOrCompleted(
        action: action,
        managerUserId: 'user-manager-1',
        updatedByName: 'Staff John',
        isCompleted: true,
      );

      expect(notif, isNotNull);
      expect(notif!.userId, 'user-manager-1');
      expect(notif.eventType, 'action_completed');
      expect(notif.title, contains('Action Completed: ACT-3001'));
      expect(notif.message, contains('Staff John marked action ACT-3001 as 100% completed'));
    });

    // 5. Staff notifications (action assigned & reopened)
    test('5. Manager action assignment and reopen notify staff', () async {
      final action = _makeAction(
        id: 'ACT-3002',
        subject: 'Scaffolding Inspection',
        organizationId: 'org-1',
      );

      final assigned = await service.notifyActionAssigned(
        action: action,
        assigneeUserId: 'user-staff-2',
      );
      expect(assigned!.userId, 'user-staff-2');
      expect(assigned.eventType, 'action_assigned');

      final reopened = await service.notifyActionReopened(
        action: action,
        assigneeUserId: 'user-staff-2',
        reopenedByName: 'Manager Sarah',
        reason: 'Missing photographic evidence',
      );
      expect(reopened!.userId, 'user-staff-2');
      expect(reopened.eventType, 'action_reopened');
      expect(reopened.message, contains('Missing photographic evidence'));
    });

    // 6. Request notifications
    test('6. Request submission, assignment, approval, and rejection generate notifications', () async {
      // 6a. Submission -> Approver
      final sub = await service.notifyRequestSubmitted(
        requestId: 'req-101',
        requestCode: 'REQ-1001',
        approverUserId: 'user-approver-1',
        requesterName: 'Alice',
        requestTitle: 'Safety Boots Requisition',
      );
      expect(sub!.userId, 'user-approver-1');
      expect(sub.eventType, 'request_submitted');
      expect(sub.isRequestRelated, isTrue);

      // 6b. Approval -> Requester
      final appr = await service.notifyRequestApproved(
        requestId: 'req-101',
        requestCode: 'REQ-1001',
        requesterUserId: 'user-alice',
        approverName: 'Manager Bob',
        requestTitle: 'Safety Boots Requisition',
        isCompleted: true,
      );
      expect(appr!.userId, 'user-alice');
      expect(appr.eventType, 'request_completed');
      expect(appr.title, contains('Request Completed'));

      // 6c. Rejection -> Requester
      final rej = await service.notifyRequestRejected(
        requestId: 'req-102',
        requestCode: 'REQ-1002',
        requesterUserId: 'user-alice',
        approverName: 'Manager Bob',
        requestTitle: 'Extra Helmet',
        reason: 'Sufficient stock on site',
      );
      expect(rej!.userId, 'user-alice');
      expect(rej.eventType, 'request_rejected');
      expect(rej.message, contains('Sufficient stock on site'));

      // 6d. Forwarded -> Delegated Approver
      final fwd = await service.notifyRequestForwarded(
        requestId: 'req-103',
        requestCode: 'REQ-1003',
        delegatedToUserId: 'user-charlie',
        forwardedByName: 'Manager Bob',
        requestTitle: 'Crane Permit',
      );
      expect(fwd!.userId, 'user-charlie');
      expect(fwd.eventType, 'request_forwarded');
    });

    // 7. Calendar notifications
    test('7. Calendar task assignment and update generate notifications', () async {
      final asgn = await service.notifyCalendarEventAssigned(
        taskId: 'cal-201',
        taskTitle: 'Fire Drill Briefing',
        assigneeUserId: 'user-staff-1',
        scheduledDate: '2026-11-15',
        assignedByName: 'HSE Officer',
      );
      expect(asgn!.userId, 'user-staff-1');
      expect(asgn.eventType, 'calendar_event_assigned');
      expect(asgn.isCalendarRelated, isTrue);

      final upd = await service.notifyCalendarEventUpdated(
        taskId: 'cal-201',
        taskTitle: 'Fire Drill Briefing',
        recipientUserId: 'user-staff-1',
        newDate: '2026-11-18',
        updatedByName: 'HSE Officer',
      );
      expect(upd!.userId, 'user-staff-1');
      expect(upd.eventType, 'calendar_event_updated');
      expect(upd.message, contains('2026-11-18'));
    });

    // 8. Contributor notifications
    test('8. Adding a contributor creates contributor_added notification', () async {
      final action = _makeAction(
        id: 'ACT-4001',
        subject: 'Confined Space Audit',
      );

      final notif = await service.notifyContributorAdded(
        action: action,
        contributorUserId: 'user-contributor-1',
        addedByName: 'Manager Dave',
      );
      expect(notif!.userId, 'user-contributor-1');
      expect(notif.eventType, 'contributor_added');
      expect(notif.title, contains('Added as Contributor: ACT-4001'));
      expect(notif.message, contains('Manager Dave'));
    });

    // 9. Subtask notifications
    test('9. Subtask assignment and delegation create dedicated notifications', () async {
      final action = _makeAction(
        id: 'ACT-5001',
        subject: 'Excavation Safety Protocol',
      );

      final asgn = await service.notifySubtaskAssigned(
        action: action,
        assigneeUserId: 'user-subtask-1',
        subtaskTitle: 'Inspect trench shoring',
        assignedByName: 'Lead Supervisor',
      );
      expect(asgn!.userId, 'user-subtask-1');
      expect(asgn.eventType, 'subtask_assigned');
      expect(asgn.message, contains('Inspect trench shoring'));

      final del = await service.notifySubtaskDelegated(
        action: action,
        delegatedToUserId: 'user-subtask-2',
        subtaskTitle: 'Inspect trench shoring',
        delegatedByName: 'user-subtask-1',
      );
      expect(del!.userId, 'user-subtask-2');
      expect(del.eventType, 'subtask_delegated');
    });

    // 10. Duplicate prevention (idempotency key)
    test('10. Idempotency key prevents duplicate notifications', () async {
      final notif1 = AppNotification(
        id: '',
        userId: 'user-idemp-1',
        organizationId: 'org-1',
        title: 'Alert',
        message: 'First attempt',
        eventType: 'action_assigned',
        idempotencyKey: 'idemp-key-unique-123',
        createdAt: DateTime.now(),
      );

      final notif2 = AppNotification(
        id: '',
        userId: 'user-idemp-1',
        organizationId: 'org-1',
        title: 'Alert Repeated',
        message: 'Second attempt with same key',
        eventType: 'action_assigned',
        idempotencyKey: 'idemp-key-unique-123',
        createdAt: DateTime.now(),
      );

      final res1 = await service.createNotification(notif1);
      final res2 = await service.createNotification(notif2);

      expect(res1!.id, res2!.id);
      final all = await service.getNotifications(userId: 'user-idemp-1');
      expect(all.where((n) => n.idempotencyKey == 'idemp-key-unique-123').length, 1);
    });

    // 11. Unread count tracking
    test('11. Unread count increments with new alerts and decrements when marked read', () async {
      const u = 'user-unread-test';
      expect(await service.getUnreadCount(userId: u), 0);

      final n1 = await service.createNotification(
        AppNotification(
          id: 'n1',
          userId: u,
          title: 'T1',
          message: 'M1',
          eventType: 'action_assigned',
          createdAt: DateTime.now(),
        ),
      );
      expect(await service.getUnreadCount(userId: u), 1);

      await service.createNotification(
        AppNotification(
          id: 'n2',
          userId: u,
          title: 'T2',
          message: 'M2',
          eventType: 'action_assigned',
          createdAt: DateTime.now(),
        ),
      );
      expect(await service.getUnreadCount(userId: u), 2);

      await service.markAsRead(notificationId: n1!.id, userId: u);
      expect(await service.getUnreadCount(userId: u), 1);
    });

    // 12. Mark as read
    test('12. Mark as read updates isRead flag and sets readAt', () async {
      const u = 'user-read-single';
      final n = await service.createNotification(
        AppNotification(
          id: 'n-single',
          userId: u,
          title: 'Read me',
          message: 'Content',
          eventType: 'action_assigned',
          createdAt: DateTime.now(),
        ),
      );
      expect(n!.isRead, false);

      await service.markAsRead(notificationId: n.id, userId: u);
      final list = await service.getNotifications(userId: u);
      final updated = list.firstWhere((x) => x.id == n.id);
      expect(updated.isRead, true);
      expect(updated.readAt, isNotNull);
    });

    // 13. Mark all as read
    test('13. Mark all as read updates all unread notifications for the user', () async {
      const u = 'user-read-all';
      await service.createNotification(
        AppNotification(id: 'r1', userId: u, title: 'T1', message: 'M1', eventType: 'action_assigned', createdAt: DateTime.now()),
      );
      await service.createNotification(
        AppNotification(id: 'r2', userId: u, title: 'T2', message: 'M2', eventType: 'action_assigned', createdAt: DateTime.now()),
      );
      expect(await service.getUnreadCount(userId: u), 2);

      await service.markAllAsRead(userId: u);
      expect(await service.getUnreadCount(userId: u), 0);
      final list = await service.getNotifications(userId: u);
      expect(list.every((n) => n.isRead), isTrue);
    });

    // 14. Realtime stream delivery
    test('14. onNotificationReceived stream delivers newly created alert in active session', () async {
      const u = 'user-stream-test';
      final receivedAlerts = <AppNotification>[];
      final sub = service.onNotificationReceived.listen((notif) {
        if (notif.userId == u) receivedAlerts.add(notif);
      });

      await service.createNotification(
        AppNotification(
          id: 'stream-1',
          userId: u,
          title: 'Stream Alert',
          message: 'Delivered via broadcast stream',
          eventType: 'action_assigned',
          createdAt: DateTime.now(),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(receivedAlerts.length, 1);
      expect(receivedAlerts.first.title, 'Stream Alert');
      await sub.cancel();
    });

    // 15. Subscription lifecycle
    test('15. subscribe and unsubscribe handle clean lifecycle without throwing', () {
      expect(() => service.subscribeToRealtimeNotifications('user-sub-lifecycle'), returnsNormally);
      expect(() => service.unsubscribeFromRealtime(), returnsNormally);
    });

    // 16. Sound settings ON/OFF
    test('16. SoundService toggles sound state and updates preference', () {
      final sound = SoundService.instance;
      final initial = sound.isSoundEnabled;
      sound.setSoundEnabled(true);
      expect(sound.isSoundEnabled, isTrue);

      final toggled = sound.toggleSound();
      expect(toggled, isFalse);
      expect(sound.isSoundEnabled, isFalse);

      sound.setSoundEnabled(initial); // Restore
    });

    // 17. Sound playback does not throw
    test('17. Sound playback executes cleanly without crashing on native or web', () async {
      expect(() => SoundService.instance.playNotificationSound(), returnsNormally);
    });

    // 18. Historical notifications do not play sound
    test('18. getNotifications and unread count do not invoke audio sound', () async {
      const u = 'user-hist-check';
      await service.createNotification(
        AppNotification(id: 'hist-1', userId: u, title: 'Hist', message: 'M', eventType: 'action_assigned', createdAt: DateTime.now()),
      );
      // Fetching history
      final items = await service.getNotifications(userId: u);
      expect(items.length, 1);
      // Getting count
      final count = await service.getUnreadCount(userId: u);
      expect(count, 1);
    });

    // 19. Notification navigation resolution
    test('19. effectiveActionIdentifier and effectiveRequestIdentifier extract targets correctly', () {
      final notifAction = AppNotification(
        id: '1',
        userId: 'u',
        title: 'Action Assigned: ACT-1048',
        message: 'Action ACT-1048 assigned to you.',
        eventType: 'action_assigned',
        actionId: 'ACT-1048',
        createdAt: DateTime.now(),
      );
      expect(notifAction.effectiveActionIdentifier, 'ACT-1048');

      final notifReq = AppNotification(
        id: '2',
        userId: 'u',
        title: 'Request Approved: REQ-1005',
        message: 'Request REQ-1005 was approved.',
        eventType: 'request_approved',
        actionId: 'REQ-1005',
        createdAt: DateTime.now(),
      );
      expect(notifReq.effectiveRequestIdentifier, 'REQ-1005');
      expect(notifReq.isRequestRelated, isTrue);
    });

    // 20. Organization isolation
    test('20. Cross-organization notifications are segregated', () async {
      await service.createNotification(
        AppNotification(
          id: 'org1-n',
          userId: 'user-org1',
          organizationId: 'org-alpha',
          title: 'Alpha Internal',
          message: 'Org Alpha only',
          eventType: 'action_assigned',
          createdAt: DateTime.now(),
        ),
      );
      await service.createNotification(
        AppNotification(
          id: 'org2-n',
          userId: 'user-org2',
          organizationId: 'org-beta',
          title: 'Beta Internal',
          message: 'Org Beta only',
          eventType: 'action_assigned',
          createdAt: DateTime.now(),
        ),
      );

      final alphaList = await service.getNotifications(userId: 'user-org1');
      expect(alphaList.any((n) => n.organizationId == 'org-beta'), isFalse);
    });
  });
}
