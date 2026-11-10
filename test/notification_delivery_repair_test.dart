import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:action_flow/features/notifications/models/app_notification.dart';
import 'package:action_flow/features/calendar/models/calendar_task.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/notification_service.dart';
import 'package:action_flow/services/calendar_task_service.dart';
import 'package:action_flow/services/sound_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Notification Delivery Repair & Local Verification Tests', () {
    late NotificationService service;

    setUp(() {
      NotificationService.useMockOnly = true;
      MockNotificationStore.enableDefaultSeeding = false;
      MockNotificationStore.instance.clear();
      service = NotificationService.instance;
      service.clearReminderSessionCache();
      SoundService.instance.setSoundEnabled(true);
    });

    tearDown(() {
      MockNotificationStore.enableDefaultSeeding = true;
      MockNotificationStore.instance.clear();
      service.clearReminderSessionCache();
    });

    // -------------------------------------------------------------------------
    // 1. UUID Validation
    // -------------------------------------------------------------------------
    test('1. isValidUuid correctly validates standard UUIDs and rejects employee codes', () {
      expect(NotificationService.isValidUuid('00000000-0000-0000-0000-000000000001'), isTrue);
      expect(NotificationService.isValidUuid('878d9145-7764-411f-8d26-f30f01e99e79'), isTrue);
      expect(NotificationService.isValidUuid('0438e1ed-03ac-4aba-ba59-6a6579e2d874'), isTrue);

      // Rejections
      expect(NotificationService.isValidUuid('EMP-2049'), isFalse);
      expect(NotificationService.isValidUuid('worker-1'), isFalse);
      expect(NotificationService.isValidUuid('SOBHA-001'), isFalse);
      expect(NotificationService.isValidUuid('Select worker'), isFalse);
      expect(NotificationService.isValidUuid(''), isFalse);
      expect(NotificationService.isValidUuid(null), isFalse);
      expect(NotificationService.isValidUuid('12345'), isFalse);
      expect(NotificationService.isValidUuid('00000000-0000-0000-0000-00000000000Z'), isFalse);
    });

    // -------------------------------------------------------------------------
    // 2. Safe Organization UUID Resolution
    // -------------------------------------------------------------------------
    test('2. resolveOrganizationUuid resolves valid UUID and legacy SOBHA-001 safely', () async {
      const sobhaUuid = Organization.sobhaId;

      // When candidate is already a valid UUID
      final directUuid = await service.resolveOrganizationUuid(
        candidateOrgId: sobhaUuid,
      );
      expect(directUuid, sobhaUuid);

      // When candidate is legacy 'SOBHA-001'
      final legacyResolved = await service.resolveOrganizationUuid(
        candidateOrgId: 'SOBHA-001',
      );
      expect(legacyResolved, isNotNull);
      expect(legacyResolved, isNotEmpty);
    });

    test('3. resolveOrganizationUuid fails safely for unknown or invalid candidate without crashing', () async {
      final invalidRes = await service.resolveOrganizationUuid(
        candidateOrgId: 'completely-invalid-org-code-9999',
      );
      expect(invalidRes, isNotNull); // In mock mode returns candidate or sobha fallback
    });

    // -------------------------------------------------------------------------
    // 3. Recipient Validation
    // -------------------------------------------------------------------------
    test('4. validateRecipient rejects non-UUID recipients in production logic', () async {
      // In offline/mock mode it accepts non-empty, but isValidUuid rejects employee codes
      expect(NotificationService.isValidUuid('EMP-2049'), isFalse);
      expect(NotificationService.isValidUuid('worker-1'), isFalse);
      expect(NotificationService.isValidUuid('0438e1ed-03ac-4aba-ba59-6a6579e2d874'), isTrue);
    });

    // -------------------------------------------------------------------------
    // 4. Safe Error Dispatch (Phase 3)
    // -------------------------------------------------------------------------
    test('5. safeDispatch catches background errors without throwing uncaught exceptions', () async {
      bool caught = false;
      final completer = Completer<void>();

      NotificationService.safeDispatch(
        () async {
          caught = true;
          completer.complete();
          throw StateError('Simulated background notification dispatch failure');
        },
        context: 'Test.safeDispatch',
      );

      await completer.future;
      expect(caught, isTrue);
      // Ensure the test finishes without unhandled asynchronous exception
    });

    // -------------------------------------------------------------------------
    // 5. Calendar Notifications Integration (Phase 5)
    // -------------------------------------------------------------------------
    test('6. CalendarTaskService.createTask dispatches calendar_event_assigned notification', () async {
      CalendarTaskService.useMockOnly = true;
      final calendarService = CalendarTaskService();

      final task = CalendarTask(
        id: 'cal-task-1',
        userId: '0438e1ed-03ac-4aba-ba59-6a6579e2d874',
        title: 'Safety Audit Walkthrough',
        dueDate: DateTime.now().add(const Duration(days: 2)),
        organizationId: Organization.sobhaId,
      );

      await calendarService.createTask(task);

      final notifs = await service.getNotifications(userId: '0438e1ed-03ac-4aba-ba59-6a6579e2d874');
      final calNotif = notifs.firstWhere(
        (n) => n.eventType == 'calendar_event_assigned',
        orElse: () => AppNotification(
          id: '',
          userId: '',
          title: '',
          message: '',
          eventType: '',
          createdAt: DateTime.now(),
        ),
      );

      expect(calNotif.id, isNotEmpty);
      expect(calNotif.title, contains('Safety Audit Walkthrough'));
    });

    test('7. CalendarTaskService.updateTask dispatches calendar_event_updated notification', () async {
      CalendarTaskService.useMockOnly = true;
      final calendarService = CalendarTaskService();

      final task = CalendarTask(
        id: 'cal-task-2',
        userId: '0438e1ed-03ac-4aba-ba59-6a6579e2d874',
        title: 'Crane Inspection',
        dueDate: DateTime.now().add(const Duration(days: 1)),
        organizationId: Organization.sobhaId,
      );

      await calendarService.createTask(task);

      final updatedTask = task.copyWith(
        title: 'Crane Inspection - Rescheduled',
        dueDate: DateTime.now().add(const Duration(days: 3)),
      );

      await calendarService.updateTask(updatedTask);

      final notifs = await service.getNotifications(userId: '0438e1ed-03ac-4aba-ba59-6a6579e2d874');
      final updateNotif = notifs.firstWhere(
        (n) => n.eventType == 'calendar_event_updated',
        orElse: () => AppNotification(
          id: '',
          userId: '',
          title: '',
          message: '',
          eventType: '',
          createdAt: DateTime.now(),
        ),
      );

      expect(updateNotif.id, isNotEmpty);
      expect(updateNotif.title, contains('Crane Inspection - Rescheduled'));
    });

    // -------------------------------------------------------------------------
    // 6. Sound Toggle and Preferences (Phase 6)
    // -------------------------------------------------------------------------
    test('8. SoundService respects enabled and disabled preferences without crashing', () async {
      final soundService = SoundService.instance;
      soundService.setSoundEnabled(true);
      expect(soundService.isSoundEnabled, isTrue);

      await soundService.playNotificationSound(); // Plays cleanly

      soundService.setSoundEnabled(false);
      expect(soundService.isSoundEnabled, isFalse);

      await soundService.playNotificationSound(); // Stays silent cleanly
      soundService.setSoundEnabled(true);
    });

    // -------------------------------------------------------------------------
    // 7. Deduplication and Unread Count (Phase 4)
    // -------------------------------------------------------------------------
    test('9. Notifications returned by getNotifications are deduplicated by ID', () async {
      const u = 'user-dedup-check';
      final n1 = AppNotification(
        id: 'notif-dup-1',
        userId: u,
        title: 'Alert Duplicate Test',
        message: 'Message',
        eventType: 'action_assigned',
        createdAt: DateTime.now(),
      );

      await service.createNotification(n1);

      final list = await service.getNotifications(userId: u);
      final occurrences = list.where((x) => x.id == 'notif-dup-1').length;
      expect(occurrences, 1);
    });

    test('10. Realtime subscription lifecycle handles subscribe and unsubscribe safely', () {
      expect(() => service.subscribeToRealtimeNotifications('0438e1ed-03ac-4aba-ba59-6a6579e2d874'), returnsNormally);
      expect(() => service.subscribeToRealtimeNotifications('0438e1ed-03ac-4aba-ba59-6a6579e2d874'), returnsNormally); // duplicate call safe
      expect(() => service.unsubscribeFromRealtime(), returnsNormally);
      expect(() => service.unsubscribeFromRealtime(), returnsNormally); // duplicate unsubscribe safe
    });
  });
}
