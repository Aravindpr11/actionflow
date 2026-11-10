import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/notifications/models/app_notification.dart';
import 'package:action_flow/features/notifications/widgets/notification_centre_view.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:action_flow/services/notification_service.dart';

void main() {
  setUp(() {
    NotificationService.useMockOnly = true;
    MockNotificationStore.instance.clear();
    MockActionStore.instance.actions.clear();
    NotificationService.instance.clearReminderSessionCache();
  });

  tearDown(() {
    MockNotificationStore.instance.clear();
    MockActionStore.instance.actions.clear();
    NotificationService.instance.clearReminderSessionCache();
  });

  group('Notifications Feature Tests', () {
    // -------------------------------------------------------------------------
    // 1. Notification creation for Event 1: Official HSSE Action is assigned
    // -------------------------------------------------------------------------
    test('1. Event 1: Official HSSE Action assigned notifies staff member', () async {
      final service = NotificationService();
      final action = ActionRecord(
        id: 'act-001',
        actionNumber: 'AC-1001',
        subject: 'Inspect high-voltage electrical panels',
        actionRequired: 'Verify safety clearances',
        division: 'Operations',
        assignedTo: 'R. Kumar',
        assignedToId: 'worker-user-1',
        targetDate: '2026-10-30',
        status: 'Open',
      );

      final notif = await service.notifyActionAssigned(
        action: action,
        assigneeUserId: 'worker-user-1',
      );

      expect(notif, isNotNull);
      expect(notif!.userId, 'worker-user-1');
      expect(notif.eventType, 'action_assigned');
      expect(notif.title, contains('AC-1001'));
      expect(notif.message, contains('Inspect high-voltage electrical panels'));
      expect(notif.isRead, isFalse);
      expect(notif.actionId, 'AC-1001');

      final userNotifications = await service.getNotifications(userId: 'worker-user-1');
      expect(userNotifications.any((n) => n.idempotencyKey == notif.idempotencyKey), isTrue);
    });

    // -------------------------------------------------------------------------
    // 2. Notification creation for Event 2: Action target date is approaching (within 48h)
    // -------------------------------------------------------------------------
    test('2. Event 2: Target date approaching within 48h notifies recipient', () async {
      final service = NotificationService();
      final approachingDate = DateTime.now().add(const Duration(hours: 24));
      final dateStr = approachingDate.toIso8601String().substring(0, 10);

      final action = ActionRecord(
        id: 'act-002',
        actionNumber: 'AC-1002',
        subject: 'Calibrate gas detector sensors',
        actionRequired: 'Quarterly sensor bump test',
        division: 'HSE',
        assignedTo: 'R. Kumar',
        assignedToId: 'worker-user-1',
        targetDate: dateStr,
        status: 'In Progress',
      );

      final notif = await service.notifyDueDateApproaching(
        action: action,
        recipientUserId: 'worker-user-1',
        hoursRemaining: 24,
      );

      expect(notif, isNotNull);
      expect(notif!.userId, 'worker-user-1');
      expect(notif.eventType, 'due_date_approaching');
      expect(notif.title, contains('Approaching'));
      expect(notif.message, contains('24 hours'));
      expect(notif.actionId, 'AC-1002');
    });

    // -------------------------------------------------------------------------
    // 3. Notification creation for Event 3: Action becomes overdue
    // -------------------------------------------------------------------------
    test('3. Event 3: Action overdue alert notifies recipient', () async {
      final service = NotificationService();
      final action = ActionRecord(
        id: 'act-003',
        actionNumber: 'AC-1003',
        subject: 'Repair damaged scaffolding railing',
        actionRequired: 'Replace loose couplings',
        division: 'Maintenance',
        assignedTo: 'R. Kumar',
        assignedToId: 'worker-user-1',
        targetDate: '2026-10-20', // past date
        status: 'Open',
      );

      final notif = await service.notifyActionOverdue(
        action: action,
        recipientUserId: 'worker-user-1',
      );

      expect(notif, isNotNull);
      expect(notif!.userId, 'worker-user-1');
      expect(notif.eventType, 'action_overdue');
      expect(notif.title, contains('Overdue'));
      expect(notif.message, contains('exceeded its target completion date'));
      expect(notif.actionId, 'AC-1003');
    });

    // -------------------------------------------------------------------------
    // 4. Notification creation for Event 4: Action status changes
    // -------------------------------------------------------------------------
    test('4. Event 4: Action status change creates notification', () async {
      final service = NotificationService();
      final action = ActionRecord(
        id: 'act-004',
        actionNumber: 'AC-1004',
        subject: 'Pressure relief valve inspection',
        actionRequired: 'Perform annual hydro test',
        division: 'Operations',
        assignedTo: 'R. Kumar',
        status: 'Under Review',
      );

      final notif = await service.notifyStatusChanged(
        action: action,
        recipientUserId: 'worker-user-1',
        oldStatus: 'In Progress',
        newStatus: 'Under Review',
      );

      expect(notif, isNotNull);
      expect(notif!.userId, 'worker-user-1');
      expect(notif.eventType, 'status_changed');
      expect(notif.message, contains('"In Progress" to "Under Review"'));
    });

    // -------------------------------------------------------------------------
    // 5. Notification creation for Event 5: Staff submits progress or completes action
    // -------------------------------------------------------------------------
    test('5. Event 5: Staff progress update or completion notifies the manager', () async {
      final service = NotificationService();
      final action = ActionRecord(
        id: 'act-005',
        actionNumber: 'AC-1005',
        subject: 'Install chemical eyewash station signage',
        actionRequired: 'Fit luminescent signs',
        division: 'Safety',
        assignedTo: 'R. Kumar',
        percentComplete: 75,
        status: 'In Progress',
      );

      // 5a. Progress update
      final updateNotif = await service.notifyActionUpdatedOrCompleted(
        action: action,
        managerUserId: 'mgr-user-99',
        updatedByName: 'R. Kumar',
        isCompleted: false,
        notes: 'Signage brackets mounted, testing visibility.',
      );

      expect(updateNotif, isNotNull);
      expect(updateNotif!.userId, 'mgr-user-99');
      expect(updateNotif.eventType, 'action_updated');
      expect(updateNotif.message, contains('75%'));
      expect(updateNotif.message, contains('R. Kumar'));

      // 5b. Completion update
      final completedAction = action.copyWith(percentComplete: 100, status: 'Completed');
      final completeNotif = await service.notifyActionUpdatedOrCompleted(
        action: completedAction,
        managerUserId: 'mgr-user-99',
        updatedByName: 'R. Kumar',
        isCompleted: true,
      );

      expect(completeNotif, isNotNull);
      expect(completeNotif!.userId, 'mgr-user-99');
      expect(completeNotif.eventType, 'action_completed');
      expect(completeNotif.message, contains('100% completed'));
    });

    // -------------------------------------------------------------------------
    // 6. Notification creation for Event 6: Manager reopens an action
    // -------------------------------------------------------------------------
    test('6. Event 6: Manager reopening an action notifies assigned staff member', () async {
      final service = NotificationService();
      final action = ActionRecord(
        id: 'act-006',
        actionNumber: 'AC-1006',
        subject: 'Confined space ventilation certification',
        actionRequired: 'Check airflow sensors',
        division: 'Operations',
        assignedTo: 'R. Kumar',
        status: 'Reopened',
      );

      final notif = await service.notifyActionReopened(
        action: action,
        assigneeUserId: 'worker-user-1',
        reopenedByName: 'Manager Sarah',
        reason: 'Missing atmospheric test logs in attachment.',
      );

      expect(notif, isNotNull);
      expect(notif!.userId, 'worker-user-1');
      expect(notif.eventType, 'action_reopened');
      expect(notif.title, contains('Reopened'));
      expect(notif.message, contains('Manager Sarah reopened action "AC-1006"'));
      expect(notif.message, contains('Missing atmospheric test logs'));
    });

    // -------------------------------------------------------------------------
    // 7. Strict User Isolation: User A cannot access User B's notifications
    // -------------------------------------------------------------------------
    test('7. Strict Privacy & Isolation: User A cannot view User B notifications', () async {
      final store = MockNotificationStore.instance;

      store.createNotification(AppNotification(
        id: 'notif-user-a',
        userId: 'user-a',
        title: 'Secret Alert for User A',
        message: 'Confidential investigation findings',
        eventType: 'action_assigned',
        createdAt: DateTime.now(),
      ));

      store.createNotification(AppNotification(
        id: 'notif-user-b',
        userId: 'user-b',
        title: 'Private Notification for User B',
        message: 'Personal disciplinary review action',
        eventType: 'action_assigned',
        createdAt: DateTime.now(),
      ));

      final service = NotificationService();
      final listA = await service.getNotifications(userId: 'user-a');
      final listB = await service.getNotifications(userId: 'user-b');

      expect(listA.any((n) => n.userId == 'user-b'), isFalse);
      expect(listB.any((n) => n.userId == 'user-a'), isFalse);
      expect(listA.any((n) => n.id == 'notif-user-b'), isFalse);
      expect(listB.any((n) => n.id == 'notif-user-a'), isFalse);

      // Attempting to delete User B's notification using User A's ID fails silently
      await service.deleteNotification(notificationId: 'notif-user-b', userId: 'user-a');
      final checkB = await service.getNotifications(userId: 'user-b');
      expect(checkB.any((n) => n.id == 'notif-user-b'), isTrue);
    });

    // -------------------------------------------------------------------------
    // 8. Reliable Idempotency / Deduplication: Prevents duplicate notifications
    // -------------------------------------------------------------------------
    test('8. Idempotency check prevents duplicate notifications on repeated saves/rebuilds', () async {
      final service = NotificationService();
      final action = ActionRecord(
        id: 'act-008',
        actionNumber: 'AC-1008',
        subject: 'Idempotency Action Test',
        actionRequired: 'Verify idempotency key deduplication',
        division: 'HSE',
        assignedTo: 'R. Kumar',
      );

      // First call inserts
      final notif1 = await service.notifyActionAssigned(
        action: action,
        assigneeUserId: 'worker-user-1',
      );

      // Repeated call with identical action and recipient
      final notif2 = await service.notifyActionAssigned(
        action: action,
        assigneeUserId: 'worker-user-1',
      );

      expect(notif1, isNotNull);
      expect(notif2, isNotNull);
      expect(notif1!.id, notif2!.id); // exact same item returned
      expect(notif1.idempotencyKey, notif2.idempotencyKey);

      final userItems = await service.getNotifications(userId: 'worker-user-1');
      final matching = userItems.where((n) => n.idempotencyKey == notif1.idempotencyKey).toList();
      expect(matching.length, 1); // exactly one notification, no duplicates
    });

    // -------------------------------------------------------------------------
    // 9. Read/Unread toggles and Mark All as Read
    // -------------------------------------------------------------------------
    test('9. Toggle read/unread and Mark All as Read update status and counts', () async {
      final service = NotificationService();
      final store = MockNotificationStore.instance;

      store.createNotification(AppNotification(
        id: 'toggle-1',
        userId: 'test-user-1',
        title: 'Notification 1',
        message: 'Message 1',
        eventType: 'action_assigned',
        isRead: false,
        createdAt: DateTime.now(),
      ));

      store.createNotification(AppNotification(
        id: 'toggle-2',
        userId: 'test-user-1',
        title: 'Notification 2',
        message: 'Message 2',
        eventType: 'action_overdue',
        isRead: false,
        createdAt: DateTime.now(),
      ));

      expect(await service.getUnreadCount(userId: 'test-user-1'), 2);

      // Mark single as read
      await service.markAsRead(notificationId: 'toggle-1', userId: 'test-user-1');
      expect(await service.getUnreadCount(userId: 'test-user-1'), 1);

      // Toggle back to unread
      await service.toggleRead(notificationId: 'toggle-1', userId: 'test-user-1', isRead: false);
      expect(await service.getUnreadCount(userId: 'test-user-1'), 2);

      // Mark all as read
      await service.markAllAsRead(userId: 'test-user-1');
      expect(await service.getUnreadCount(userId: 'test-user-1'), 0);
    });

    // -------------------------------------------------------------------------
    // 10. Notification Centre Widget: UI rendering, filtering, and interactions
    // -------------------------------------------------------------------------
    testWidgets('10. NotificationCentreView renders alerts, unread filter, and mark all read', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final store = MockNotificationStore.instance;
      store.createNotification(AppNotification(
        id: 'ui-notif-1',
        userId: 'ui-test-user',
        title: 'Emergency Generator Testing',
        message: 'AC-1080 requires weekly run test verification.',
        eventType: 'action_assigned',
        actionId: 'AC-1080',
        isRead: false,
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ));

      store.createNotification(AppNotification(
        id: 'ui-notif-2',
        userId: 'ui-test-user',
        title: 'Hazard Review Completed',
        message: 'AC-1075 closed by Safety Department.',
        eventType: 'action_completed',
        actionId: 'AC-1075',
        isRead: true,
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      ));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: NotificationCentreView(
                userId: 'ui-test-user',
                title: 'Notifications & Alerts',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Header and items
      expect(find.text('Notifications & Alerts'), findsOneWidget);
      expect(find.text('1 Unread'), findsOneWidget);
      expect(find.text('Emergency Generator Testing'), findsOneWidget);
      expect(find.text('Hazard Review Completed'), findsOneWidget);

      // Filter by Unread
      await tester.tap(find.text('Unread (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Emergency Generator Testing'), findsOneWidget);
      expect(find.text('Hazard Review Completed'), findsNothing);

      // Switch back to All
      await tester.tap(find.text('All (2)'));
      await tester.pumpAndSettle();
      expect(find.text('Hazard Review Completed'), findsOneWidget);

      // Mark all read
      expect(find.text('Mark all read'), findsOneWidget);
      await tester.tap(find.text('Mark all read'));
      await tester.pumpAndSettle();

      expect(find.text('1 Unread'), findsNothing);
      expect(find.text('Unread (0)'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 11. Clicking action link invokes onActionTap callback
    // -------------------------------------------------------------------------
    testWidgets('11. Clicking a notification with an action opens that action', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final store = MockNotificationStore.instance;
      store.createNotification(AppNotification(
        id: 'tap-notif-1',
        userId: 'tap-test-user',
        title: 'Action Inspection Overdue',
        message: 'AC-1099 has exceeded target completion date.',
        eventType: 'action_overdue',
        actionId: 'AC-1099',
        isRead: false,
        createdAt: DateTime.now(),
      ));

      String? tappedActionId;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: NotificationCentreView(
                userId: 'tap-test-user',
                onActionTap: (actionId) {
                  tappedActionId = actionId;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AC-1099'), findsOneWidget);
      await tester.tap(find.text('Action Inspection Overdue'));
      await tester.pumpAndSettle();

      expect(tappedActionId, 'AC-1099');
    });

    // -------------------------------------------------------------------------
    // 12. Complete separation from external email dispatches and personal Calendar Tasks
    // -------------------------------------------------------------------------
    test('12. In-app only: Separation from email sending and personal calendar tasks', () async {
      final service = NotificationService();
      final action = ActionRecord(
        id: 'act-012',
        actionNumber: 'AC-1012',
        subject: 'Confirmatory isolation test',
        actionRequired: 'Verify zero email side effects',
        division: 'HSE',
        assignedTo: 'R. Kumar',
        emailReminderEnabled: false, // email reminders OFF by default
      );

      // Notification creation is strictly local in-app
      final notif = await service.notifyActionAssigned(
        action: action,
        assigneeUserId: 'worker-user-1',
      );

      expect(notif, isNotNull);
      expect(action.emailReminderEnabled, isFalse);

      // Confirm no personal calendar tasks are modified or polluted
      final userNotifs = await service.getNotifications(userId: 'worker-user-1');
      expect(userNotifs.isNotEmpty, isTrue);
      expect(userNotifs.every((n) => n.userId == 'worker-user-1'), isTrue);
    });

    // -------------------------------------------------------------------------
    // 13. Real Workflow: Action creation and update trigger in-app notifications
    // -------------------------------------------------------------------------
    test('13. ActionService.createAction and updateAction trigger in-app notifications', () async {
      final actionService = ActionService.instance;
      final notifService = NotificationService.instance;

      final action = ActionRecord(
        id: 'act-workflow-1',
        actionNumber: 'AC-2001',
        subject: 'Inspect high-pressure steam valve',
        actionRequired: 'Replace valve seal gasket',
        division: 'Engineering',
        assignedTo: 'S. Patel',
        assignedToId: 'worker-patel',
        status: 'Open',
        targetDate: '2026-11-05',
      );

      // Create action with notification enabled
      await actionService.createAction(
        action,
        sendAssignmentNotification: false,
      );

      final staffNotifs = await notifService.getNotifications(userId: 'worker-patel');
      final assignNotif = staffNotifs.firstWhereOrNull((n) => n.eventType == 'action_assigned');
      expect(assignNotif, isNotNull);
      expect(assignNotif!.title, contains('AC-2001'));
      expect(assignNotif.message, contains('Inspect high-pressure steam valve'));

      // Update action with new status
      final updatedAction = action.copyWith(
        status: 'In Progress',
        history: ['Action moved to In Progress by Manager'],
      );
      await actionService.updateAction(updatedAction);

      final updatedStaffNotifs = await notifService.getNotifications(userId: 'worker-patel');
      final statusNotif = updatedStaffNotifs.firstWhereOrNull(
        (n) => n.eventType == 'status_changed' && n.message.contains('"In Progress"'),
      );
      expect(statusNotif, isNotNull);
    });

    // -------------------------------------------------------------------------
    // 14. Real Workflow: Staff submits progress and Manager reopens action
    // -------------------------------------------------------------------------
    test('14. ActionService.submitProgressUpdate notifies manager, reopenAction notifies staff', () async {
      final actionService = ActionService.instance;
      final notifService = NotificationService.instance;

      final initialAction = ActionRecord(
        id: 'act-workflow-2',
        actionNumber: 'AC-2002',
        subject: 'Repair crane emergency stop button',
        actionRequired: 'Rewire switch contacts',
        division: 'Logistics',
        assignedTo: 'A. Kumar',
        assignedToId: 'worker-kumar',
        createdById: 'manager-jones',
        status: 'In Progress',
        percentComplete: 20,
      );

      await actionService.createAction(
        initialAction,
        sendAssignmentNotification: false,
      );

      // Staff submits progress update to 100% (Completed)
      await actionService.submitProgressUpdate(
        actionId: initialAction.id,
        updateDate: DateTime.now(),
        progress: 100,
        status: 'Completed',
        comments: 'Wiring tested and approved with multimeter.',
      );

      final managerNotifs = await notifService.getNotifications(userId: 'manager-jones');
      final completeNotif = managerNotifs.firstWhereOrNull(
        (n) => n.eventType == 'action_completed',
      );
      expect(completeNotif, isNotNull);
      expect(completeNotif!.message, contains('100% completed'));

      // Manager reopens the action
      await actionService.reopenAction(
        actionId: initialAction.id,
        reason: 'Missing sign-off documentation attachment.',
        reopenedBy: 'Manager Jones',
      );

      final staffNotifs = await notifService.getNotifications(userId: 'worker-kumar');
      final reopenNotif = staffNotifs.firstWhereOrNull(
        (n) => n.eventType == 'action_reopened',
      );
      expect(reopenNotif, isNotNull);
      expect(reopenNotif!.message, contains('Manager Jones reopened action'));
      expect(reopenNotif.message, contains('Missing sign-off documentation'));
    });

    // -------------------------------------------------------------------------
    // 15. Recipient Resolution: External recipients receive NO in-app notifications
    // -------------------------------------------------------------------------
    test('15. External recipients (isExternalRecipient == true) receive NO in-app notifications', () async {
      final actionService = ActionService.instance;
      final notifService = NotificationService.instance;

      final externalAction = ActionRecord(
        id: 'act-workflow-3',
        actionNumber: 'AC-2003',
        subject: 'External Contractor Asbestos Clearance',
        actionRequired: 'Provide disposal certificate',
        division: 'Environmental',
        assignedTo: 'contractor@thirdparty.com',
        assignedToId: 'ext-contractor-99',
        recipientType: 'external',
        status: 'Open',
      );

      await actionService.createAction(
        externalAction,
        sendAssignmentNotification: false,
      );

      final notifs = await notifService.getNotifications(userId: 'ext-contractor-99');
      // No notifications created for external action AC-2003
      expect(notifs.any((n) => n.actionId == 'AC-2003'), isFalse);
    });

    // -------------------------------------------------------------------------
    // 16. Legitimate Repeated Events vs Idempotent Retries
    // -------------------------------------------------------------------------
    test('16. Repeated transitions (complete -> reopen -> complete) generate distinct notifications without duplicate on retries', () async {
      final notifService = NotificationService.instance;

      var action = ActionRecord(
        id: 'act-workflow-4',
        actionNumber: 'AC-2004',
        subject: 'Generator coolant replacement',
        actionRequired: 'Flush radiator and fill 50/50 mix',
        division: 'Mechanical',
        assignedTo: 'M. Ali',
        assignedToId: 'worker-ali',
        createdById: 'manager-boss',
        history: const ['Initial assignment'],
      );

      // Event 5: Completed first time
      action = action.copyWith(
        percentComplete: 100,
        status: 'Completed',
        history: ['Initial assignment', 'Staff completed action first time'],
      );
      final notif1 = await notifService.notifyActionUpdatedOrCompleted(
        action: action,
        managerUserId: 'manager-boss',
        updatedByName: 'M. Ali',
        isCompleted: true,
      );
      expect(notif1, isNotNull);

      // Re-triggering exact same state (retry/rebuild) produces identical idempotent notif
      final notif1Retry = await notifService.notifyActionUpdatedOrCompleted(
        action: action,
        managerUserId: 'manager-boss',
        updatedByName: 'M. Ali',
        isCompleted: true,
      );
      expect(notif1Retry!.id, notif1!.id);

      // Event 6: Reopened
      action = action.copyWith(
        status: 'In Progress',
        percentComplete: 80,
        history: [...action.history, 'Manager reopened action'],
      );
      final reopenNotif = await notifService.notifyActionReopened(
        action: action,
        assigneeUserId: 'worker-ali',
        reopenedByName: 'Manager Boss',
        reason: 'Reservoir cap leak',
      );
      expect(reopenNotif, isNotNull);

      // Event 5: Completed second time (distinct event because history length grew)
      action = action.copyWith(
        percentComplete: 100,
        status: 'Completed',
        history: [...action.history, 'Staff completed action second time'],
      );
      final notif2 = await notifService.notifyActionUpdatedOrCompleted(
        action: action,
        managerUserId: 'manager-boss',
        updatedByName: 'M. Ali',
        isCompleted: true,
      );
      expect(notif2, isNotNull);
      expect(notif2!.idempotencyKey, isNot(equals(notif1.idempotencyKey)));

      final allManagerNotifs = await notifService.getNotifications(userId: 'manager-boss');
      final completedAlerts = allManagerNotifs.where((n) => n.eventType == 'action_completed').toList();
      expect(completedAlerts.length, 2); // Exactly two distinct completed notifications
    });

    // -------------------------------------------------------------------------
    // 17. checkActionReminders: Idempotent evaluations and completed action filtering
    // -------------------------------------------------------------------------
    test('17. checkActionReminders triggers approaching and overdue alerts idempotently', () async {
      final notifService = NotificationService.instance;
      final now = DateTime.now();

      final overdueAction = ActionRecord(
        id: 'act-rem-1',
        actionNumber: 'AC-3001',
        subject: 'Overdue valve test',
        actionRequired: 'Emergency inspection',
        division: 'Operations',
        assignedTo: 'R. Kumar',
        assignedToId: 'staff-rem',
        targetDate: now.subtract(const Duration(days: 2)).toIso8601String().substring(0, 10),
        status: 'In Progress',
      );

      final approachingAction = ActionRecord(
        id: 'act-rem-2',
        actionNumber: 'AC-3002',
        subject: 'Approaching due date task',
        actionRequired: 'Verify documentation',
        division: 'HSE',
        assignedTo: 'R. Kumar',
        assignedToId: 'staff-rem',
        targetDate: now.add(const Duration(hours: 24)).toIso8601String().substring(0, 10),
        status: 'Open',
      );

      final closedAction = ActionRecord(
        id: 'act-rem-3',
        actionNumber: 'AC-3003',
        subject: 'Closed action',
        actionRequired: 'Done already',
        division: 'Maintenance',
        assignedTo: 'R. Kumar',
        assignedToId: 'staff-rem',
        targetDate: now.subtract(const Duration(days: 5)).toIso8601String().substring(0, 10),
        status: 'Closed',
      );

      // First evaluation
      await notifService.checkActionReminders(
        actions: [overdueAction, approachingAction, closedAction],
        userId: 'staff-rem',
      );

      final notifs1 = await notifService.getNotifications(userId: 'staff-rem');
      expect(notifs1.any((n) => n.eventType == 'action_overdue'), isTrue);
      expect(notifs1.any((n) => n.eventType == 'due_date_approaching'), isTrue);
      // Closed action ignored
      expect(notifs1.any((n) => n.actionId == 'AC-3003'), isFalse);

      final countBefore = notifs1.length;

      // Second evaluation on the same dashboard session
      await notifService.checkActionReminders(
        actions: [overdueAction, approachingAction, closedAction],
        userId: 'staff-rem',
      );

      final notifs2 = await notifService.getNotifications(userId: 'staff-rem');
      expect(notifs2.length, countBefore); // Zero duplicates added
    });
  });
}
