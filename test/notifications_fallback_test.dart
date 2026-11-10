import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:action_flow/features/notifications/models/app_notification.dart';
import 'package:action_flow/services/notification_service.dart';

void main() {
  setUp(() {
    MockNotificationStore.instance.clear();
    NotificationService.instance.clearReminderSessionCache();
  });

  tearDown(() {
    MockNotificationStore.instance.clear();
    NotificationService.instance.clearReminderSessionCache();
  });

  group('NotificationService Missing-Table Fallback Tests', () {
    test('1. Recognizes PostgREST PGRST205 missing notifications table error', () {
      const pgrst205 = PostgrestException(
        message: "Could not find the table 'public.notifications' in the schema cache",
        code: 'PGRST205',
        hint: "Perhaps you meant to query the relation 'public.organizations'",
      );
      expect(NotificationService.isMissingNotificationsTableError(pgrst205), isTrue);
    });

    test('2. Recognizes PostgreSQL 42P01 undefined notifications table error', () {
      const pg42p01 = PostgrestException(
        message: 'relation "public.notifications" does not exist',
        code: '42P01',
      );
      expect(NotificationService.isMissingNotificationsTableError(pg42p01), isTrue);
    });

    test('3. Rejects PGRST205 for unrelated tables', () {
      const unrelatedTableError = PostgrestException(
        message: "Could not find the table 'public.unrelated_entity' in the schema cache",
        code: 'PGRST205',
      );
      // The helper validates that the missing relation is specifically notifications
      expect(NotificationService.isMissingNotificationsTableError(unrelatedTableError), isFalse);
    });

    test('4. Rejects RLS / authorization errors (42501)', () {
      const rlsError = PostgrestException(
        message: 'new row violates row-level security policy for table "notifications"',
        code: '42501',
      );
      expect(NotificationService.isMissingNotificationsTableError(rlsError), isFalse);
    });

    test('5. Rejects token expiration / auth errors (PGRST301)', () {
      const authError = PostgrestException(
        message: 'JWT expired',
        code: 'PGRST301',
      );
      expect(NotificationService.isMissingNotificationsTableError(authError), isFalse);
    });

    test('6. Rejects generic network and connection failures', () {
      final networkError = Exception('ClientException: Connection reset by peer');
      expect(NotificationService.isMissingNotificationsTableError(networkError), isFalse);
    });

    test('7. Mock store fallback provides complete notification lifecycle in memory', () async {
      // Direct MockNotificationStore verification
      final mockStore = MockNotificationStore.instance;
      const testUserId = 'test-user-fallback-1';

      // Verify seeding
      final list = mockStore.getNotifications(testUserId);
      expect(list.isNotEmpty, isTrue);
      expect(list.every((n) => n.userId == testUserId), isTrue);

      final initialUnread = mockStore.getUnreadCount(testUserId);
      expect(initialUnread, greaterThan(0));

      // Create new in-memory notification
      final created = mockStore.createNotification(
        AppNotification(
          id: 'fb-notif-1',
          userId: testUserId,
          title: 'Emergency Drill Alert',
          message: 'Assembly point inspection scheduled',
          eventType: 'action_assigned',
          actionId: 'AC-9999',
          isRead: false,
          idempotencyKey: 'drill_key_1',
          createdAt: DateTime.now(),
        ),
      );
      expect(created.id, 'fb-notif-1');
      expect(mockStore.getUnreadCount(testUserId), equals(initialUnread + 1));

      // Toggle read
      mockStore.toggleRead(notificationId: 'fb-notif-1', userId: testUserId, isRead: true);
      expect(mockStore.getUnreadCount(testUserId), equals(initialUnread));

      // Mark all read
      mockStore.markAllAsRead(userId: testUserId);
      expect(mockStore.getUnreadCount(testUserId), equals(0));

      // Delete
      mockStore.deleteNotification(notificationId: 'fb-notif-1', userId: testUserId);
      final remaining = mockStore.getNotifications(testUserId);
      expect(remaining.any((n) => n.id == 'fb-notif-1'), isFalse);
    });

    test('8. Existing tests and mock-only mode continue to function seamlessly', () async {
      NotificationService.useMockOnly = true;
      final service = NotificationService.instance;
      const user = 'user-mock-mode-1';

      final notifs = await service.getNotifications(userId: user);
      expect(notifs.isNotEmpty, isTrue);

      final unread = await service.getUnreadCount(userId: user);
      expect(unread, greaterThan(0));

      final first = notifs.first;
      await service.markAsRead(notificationId: first.id, userId: user);

      final updated = await service.getNotifications(userId: user);
      final readItem = updated.firstWhere((n) => n.id == first.id);
      expect(readItem.isRead, isTrue);

      NotificationService.useMockOnly = false;
    });
  });
}

