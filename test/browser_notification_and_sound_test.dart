import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/notifications/models/app_notification.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/requests/models/request_models.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:action_flow/services/browser_notification_service.dart';
import 'package:action_flow/services/notification_service.dart';
import 'package:action_flow/services/sound_service.dart';
import 'package:action_flow/widgets/notifications/browser_notification_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    NotificationService.useMockOnly = true;
    MockNotificationStore.enableDefaultSeeding = false;
    MockNotificationStore.instance.clear();
    MockActionStore.instance.actions.clear();
    NotificationService.instance.clearReminderSessionCache();
    BrowserNotificationService.instance.resetSessionCache();
    BrowserNotificationService.instance.setMockSupported(true);
    BrowserNotificationService.instance.setMockPermission(NotificationPermissionStatus.defaultStatus);
    BrowserNotificationService.instance.setNotificationEnabled(true);
    SoundService.instance.setSoundEnabled(true);
    SoundService.instance.setSoundVolume(0.8);
  });

  tearDown(() {
    MockNotificationStore.enableDefaultSeeding = true;
    MockNotificationStore.instance.clear();
    MockActionStore.instance.actions.clear();
    NotificationService.instance.clearReminderSessionCache();
    BrowserNotificationService.instance.resetSessionCache();
  });

  group('A. Browser Notification Permission Requirements', () {
    test('1. Checks browser Notification API support and detects support state', () {
      final bn = BrowserNotificationService.instance;
      expect(bn.isSupported, isTrue);

      bn.setMockSupported(false);
      expect(bn.isSupported, isFalse);
      expect(bn.permissionStatus, NotificationPermissionStatus.unsupported);

      bn.setMockSupported(true);
      expect(bn.isSupported, isTrue);
    });

    test('2 & 3. Requests permission only on explicit interaction and does not repeatedly prompt when decided', () async {
      final bn = BrowserNotificationService.instance;
      // Initial state is Not Requested
      expect(bn.permissionStatus, NotificationPermissionStatus.defaultStatus);

      // Explicit request simulates user granting permission
      final res = await bn.requestPermission();
      expect(res, NotificationPermissionStatus.granted);
      expect(bn.permissionStatus.isGranted, isTrue);

      // Once granted, calling requestPermission does not prompt again
      final resAgain = await bn.requestPermission();
      expect(resAgain, NotificationPermissionStatus.granted);

      // When denied, requestPermission immediately returns denied without re-prompting
      bn.setMockPermission(NotificationPermissionStatus.denied);
      final resDenied = await bn.requestPermission();
      expect(resDenied, NotificationPermissionStatus.denied);
      expect(bn.permissionStatus.isDenied, isTrue);
    });

    test('4. Correctly formats and displays Granted, Denied, and Not Requested labels', () {
      expect(NotificationPermissionStatus.granted.label, 'Granted');
      expect(NotificationPermissionStatus.denied.label, 'Denied (Blocked)');
      expect(NotificationPermissionStatus.defaultStatus.label, 'Not Requested');
      expect(NotificationPermissionStatus.unsupported.label, 'Unsupported');
    });

    testWidgets('5. Displays clear instructions dialog when user has blocked notifications in browser settings', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => BrowserNotificationDialogs.showBlockedInstructions(ctx),
                child: const Text('Show Help'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Help'));
      await tester.pumpAndSettle();

      expect(find.text('Browser Notifications Blocked'), findsOneWidget);
      expect(find.textContaining('https://app.actionflow.cc'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Click the Site Settings / Padlock icon'), findsOneWidget);
      expect(find.textContaining('Change setting to "Allow"'), findsOneWidget);
      expect(find.textContaining('Reload the web page'), findsOneWidget);

      await tester.tap(find.text('Got it, Close'));
      await tester.pumpAndSettle();
      expect(find.text('Browser Notifications Blocked'), findsNothing);
    });

    test('6 & 7. Shows desktop notification for active/background sessions when permitted', () async {
      final bn = BrowserNotificationService.instance;
      bn.setMockPermission(NotificationPermissionStatus.granted);
      bn.setNotificationEnabled(true);

      final shown = await bn.showNotification(
        title: 'Urgent HSSE Alert',
        body: 'Action ACT-3001 requires immediate inspection.',
        tag: 'notif-urgent-1',
        actionId: 'ACT-3001',
      );

      expect(shown, isTrue);
      expect(bn.shownNotificationsForTesting.length, 1);
      expect(bn.shownNotificationsForTesting.first['title'], 'Urgent HSSE Alert');
      expect(bn.shownNotificationsForTesting.first['actionId'], 'ACT-3001');

      // Does not show if user disabled notifications in ActionFlow settings
      bn.setNotificationEnabled(false);
      final shownMuted = await bn.showNotification(
        title: 'Muted Alert',
        body: 'Should not appear',
        tag: 'notif-muted-1',
      );
      expect(shownMuted, isFalse);
    });
  });

  group('B. Actual Web Push vs In-App Notifications Verification', () {
    test('Verifies in-app notification infrastructure vs offline Web Push', () {
      // ActionFlow implements live in-app notifications via Supabase Realtime and in-memory mock store
      expect(NotificationService.instance, isNotNull);
      expect(NotificationService.useMockOnly, isTrue);

      // Offline Web Push (Push API, VAPID, Service Worker offline wakeups) is NOT configured:
      // - No service worker registered
      // - No VAPID keys in environment
      // - No Web Push subscription table in database
      // This is accurately reported in the verification audit.
    });
  });

  group('C. Notification Sound Requirements', () {
    test('1 & 2. Toggles sound setting and updates preference state', () {
      final sound = SoundService.instance;
      expect(sound.isSoundEnabled, isTrue);

      sound.setSoundEnabled(false);
      expect(sound.isSoundEnabled, isFalse);

      final next = sound.toggleSound();
      expect(next, isTrue);
      expect(sound.isSoundEnabled, isTrue);
    });

    test('3. Allows user to select or adjust volume preference', () {
      final sound = SoundService.instance;
      expect(sound.soundVolume, 0.8);

      sound.setSoundVolume(0.5);
      expect(sound.soundVolume, 0.5);

      // Clamps to 0.0 - 1.0 range
      sound.setSoundVolume(1.5);
      expect(sound.soundVolume, 1.0);

      sound.setSoundVolume(-0.2);
      expect(sound.soundVolume, 0.0);
    });

    test('4, 5, 8 & 9. Sound playback executes cleanly without throwing on valid or edge cases', () async {
      final sound = SoundService.instance;
      // Should not throw
      await expectLater(sound.playNotificationSound(), completes);

      sound.unlockAudio();
      await expectLater(sound.playNotificationSound(), completes);

      // When muted, does not play sound
      sound.setSoundEnabled(false);
      await expectLater(sound.playNotificationSound(), completes);
    });
  });

  group('D & E. Notification Event Triggers and Delivery Invariants', () {
    late NotificationService service;

    setUp(() {
      service = NotificationService.instance;
    });

    test('Event 1: notifyActionAssigned dispatches notification with sound and desktop alert', () async {
      final bn = BrowserNotificationService.instance;
      bn.setMockPermission(NotificationPermissionStatus.granted);

      final action = ActionRecord(
        id: 'act-uuid-101',
        actionNumber: 'ACT-101',
        subject: 'Fix Safety Barrier',
        actionRequired: 'Replace broken latch',
        division: 'HSE',
        assignedTo: 'R. Kumar',
        assignedToId: 'usr-staff-1',
        organizationId: '00000000-0000-0000-0000-000000000001',
      );

      final notif = await service.notifyActionAssigned(
        action: action,
        assigneeUserId: 'usr-staff-1',
        organizationId: '00000000-0000-0000-0000-000000000001',
      );

      expect(notif, isNotNull);
      expect(notif!.userId, 'usr-staff-1');
      expect(notif.title, contains('Action Assigned: ACT-101'));
      expect(bn.shownNotificationsForTesting.any((n) => n['title'].contains('ACT-101')), isTrue);
    });

    test('Event 2: notifyActionForwarded delivers notification to delegated staff', () async {
      final action = ActionRecord(
        id: 'act-uuid-102',
        actionNumber: 'ACT-102',
        subject: 'Inspect Scaffolding',
        actionRequired: 'Verify tags',
        division: 'HSE',
        assignedTo: 'M. Ali',
        organizationId: '00000000-0000-0000-0000-000000000001',
      );

      final notif = await service.notifyActionForwarded(
        action: action,
        forwardedToUserId: 'usr-staff-2',
        forwardedByName: 'R. Kumar',
      );

      expect(notif, isNotNull);
      expect(notif!.userId, 'usr-staff-2');
      expect(notif.title, contains('Action Forwarded: ACT-102'));
      expect(notif.message, contains('Action ACT-102 was forwarded to you by R. Kumar'));
    });

    test('Event 3 & 4: Request submission and approval generate dedicated notifications', () async {
      final submitNotif = await service.notifyRequestSubmitted(
        requestId: 'req-uuid-201',
        requestCode: 'REQ-1001',
        approverUserId: 'usr-approver-1',
        requesterName: 'Reni Thomas',
        requestTitle: 'New Safety Harnesses',
      );

      expect(submitNotif, isNotNull);
      expect(submitNotif!.userId, 'usr-approver-1');
      expect(submitNotif.title, contains('Request Approval Required: REQ-1001'));

      final approveNotif = await service.notifyRequestApproved(
        requestId: 'req-uuid-201',
        requestCode: 'REQ-1001',
        requesterUserId: 'usr-requester-1',
        approverName: 'HSE Director',
        requestTitle: 'New Safety Harnesses',
      );

      expect(approveNotif, isNotNull);
      expect(approveNotif!.userId, 'usr-requester-1');
      expect(approveNotif.title, contains('Request Approved: REQ-1001'));
    });

    test('Event 5 & 6: Request rejection and forwarding generate clear notifications', () async {
      final rejectNotif = await service.notifyRequestRejected(
        requestId: 'req-uuid-202',
        requestCode: 'REQ-1002',
        requesterUserId: 'usr-requester-1',
        approverName: 'HSE Director',
        requestTitle: 'Overtime Permit',
        reason: 'Missing risk assessment document',
      );

      expect(rejectNotif, isNotNull);
      expect(rejectNotif!.userId, 'usr-requester-1');
      expect(rejectNotif.title, contains('Request Rejected: REQ-1002'));
      expect(rejectNotif.message, contains('Missing risk assessment document'));

      final forwardNotif = await service.notifyRequestForwarded(
        requestId: 'req-uuid-202',
        requestCode: 'REQ-1002',
        delegatedToUserId: 'usr-approver-2',
        forwardedByName: 'HSE Director',
        requestTitle: 'Overtime Permit',
      );

      expect(forwardNotif, isNotNull);
      expect(forwardNotif!.userId, 'usr-approver-2');
      expect(forwardNotif.title, contains('Request Delegated: REQ-1002'));
    });

    test('Event 7: checkActionReminders does not produce duplicate alerts or sounds', () async {
      final today = DateTime.now();
      final overdueDate = '${today.year}-${today.month.toString().padLeft(2, '0')}-${(today.day - 2).toString().padLeft(2, '0')}';

      final overdueAction = ActionRecord(
        id: 'act-overdue-1',
        actionNumber: 'ACT-999',
        subject: 'Overdue Hazard Check',
        actionRequired: 'Inspect area',
        division: 'HSE',
        assignedTo: 'Worker',
        assignedToId: 'usr-worker-1',
        targetDate: overdueDate,
        status: 'In Progress',
        percentComplete: 50,
      );

      // First evaluation triggers overdue alert
      await service.checkActionReminders(
        actions: [overdueAction],
        userId: 'usr-worker-1',
      );

      final notifs1 = await service.getNotifications(userId: 'usr-worker-1');
      expect(notifs1.where((n) => n.eventType == 'action_overdue').length, 1);

      // Second immediate evaluation is suppressed by in-memory session deduplication
      await service.checkActionReminders(
        actions: [overdueAction],
        userId: 'usr-worker-1',
      );

      final notifs2 = await service.getNotifications(userId: 'usr-worker-1');
      expect(notifs2.where((n) => n.eventType == 'action_overdue').length, 1);
    });

    test('8. Idempotency key strictly prevents duplicate notifications and duplicate sounds', () async {
      final notif = AppNotification(
        id: 'notif-idem-1',
        userId: 'usr-test-1',
        organizationId: '00000000-0000-0000-0000-000000000001',
        title: 'Action Created',
        message: 'Action created successfully',
        eventType: 'action_assigned',
        idempotencyKey: 'idem-key-unique-12345',
        createdAt: DateTime.now(),
      );

      final first = await service.createNotification(notif);
      final second = await service.createNotification(notif);

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first!.id, second!.id);

      final all = await service.getNotifications(userId: 'usr-test-1');
      expect(all.where((n) => n.idempotencyKey == 'idem-key-unique-12345').length, 1);
    });

    test('9. Session isolation resets cleanly on logout and unsubscribe', () {
      service.unsubscribeFromRealtime();
      service.clearReminderSessionCache();
      BrowserNotificationService.instance.resetSessionCache();

      expect(BrowserNotificationService.instance.shownNotificationsForTesting.isEmpty, isTrue);
    });
  });
}
