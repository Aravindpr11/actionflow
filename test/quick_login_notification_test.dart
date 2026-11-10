import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/notifications/models/app_notification.dart';
import 'package:action_flow/features/notifications/widgets/quick_alert_toast.dart';
import 'package:action_flow/services/notification_service.dart';

void main() {
  setUp(() {
    NotificationService.useMockOnly = true;
    MockNotificationStore.instance.clear();
    QuickAlertListener.clearSessions();
  });

  tearDown(() {
    MockNotificationStore.instance.clear();
    QuickAlertListener.clearSessions();
  });

  group('Quick-Login Notification Tests', () {
    testWidgets('1. Displays toast on login when user has unread notifications', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Seed unread notifications for user
      final notif1 = AppNotification(
        id: 'notif-01',
        userId: 'usr-login-01',
        title: 'Action Assigned',
        message: 'AC-1001 assigned to you',
        eventType: 'action_assigned',
        actionId: 'AC-1001',
        isRead: false,
        createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
      );
      final notif2 = AppNotification(
        id: 'notif-02',
        userId: 'usr-login-01',
        title: 'Overdue Warning',
        message: 'AC-1002 is overdue',
        eventType: 'action_overdue',
        actionId: 'AC-1002',
        isRead: false,
        createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
      );

      MockNotificationStore.instance.seed([notif1, notif2]);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: QuickAlertListener(
              userId: 'usr-login-01',
              child: const Text('Dashboard Content'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify QuickAlertToast is shown
      expect(find.byType(QuickAlertToast), findsOneWidget);
      expect(find.text('Overdue Warning'), findsOneWidget);
      // Unread count indicator: "+1 more unread"
      expect(find.textContaining('(+1 more unread)'), findsOneWidget);

      // Verify that notification is NOT marked as read upon showing
      final unreadAfterShow = MockNotificationStore.instance.allNotificationsForTesting
          .where((n) => n.userId == 'usr-login-01' && !n.isRead)
          .length;
      expect(unreadAfterShow, 2);
    });

    testWidgets('2. Does not show duplicate alert toast on dashboard rebuild or re-render', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final notif = AppNotification(
        id: 'notif-single',
        userId: 'usr-login-02',
        title: 'Action Due Today',
        message: 'AC-1003 is due today',
        eventType: 'action_due_today',
        actionId: 'AC-1003',
        isRead: false,
        createdAt: DateTime.now(),
      );

      MockNotificationStore.instance.seed([notif]);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: QuickAlertListener(
              userId: 'usr-login-02',
              child: const Text('Dashboard Content Initial'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(QuickAlertToast), findsOneWidget);

      // Dismiss the toast
      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.byType(QuickAlertToast), findsNothing);

      // Trigger a dashboard rebuild (simulating state update or tab switch)
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: QuickAlertListener(
              userId: 'usr-login-02',
              child: const Text('Dashboard Content Rebuilt'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify no duplicate toast was spawned on rebuild
      expect(find.byType(QuickAlertToast), findsNothing);
    });

    testWidgets('3. Resetting session on logout allows subsequent login to trigger alert', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final notif = AppNotification(
        id: 'notif-relogin',
        userId: 'usr-login-03',
        title: 'Action Assigned',
        message: 'AC-1004 assigned',
        eventType: 'action_assigned',
        actionId: 'AC-1004',
        isRead: false,
        createdAt: DateTime.now(),
      );

      MockNotificationStore.instance.seed([notif]);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: QuickAlertListener(
              userId: 'usr-login-03',
              child: const Text('Dashboard'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(QuickAlertToast), findsOneWidget);

      // Dismiss toast
      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();

      // Simulate logout: reset session
      QuickAlertListener.resetSession('usr-login-03');

      // Simulate re-login
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: QuickAlertListener(
              userId: 'usr-login-03',
              child: const Text('Dashboard After Re-login'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Toast appears again for the new session!
      expect(find.byType(QuickAlertToast), findsOneWidget);
      expect(find.text('Action Assigned'), findsOneWidget);
    });

    testWidgets('4. No alert shown when user has 0 unread notifications', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final readNotif = AppNotification(
        id: 'notif-read',
        userId: 'usr-login-04',
        title: 'Action Closed',
        message: 'AC-1005 was closed',
        eventType: 'action_closed',
        actionId: 'AC-1005',
        isRead: true,
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      // Mark seeded so default unread items aren't generated
      MockNotificationStore.instance.seed([readNotif]);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: QuickAlertListener(
              userId: 'usr-login-04',
              child: const Text('Dashboard Content'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(QuickAlertToast), findsNothing);
    });

    testWidgets('5. Tapping View marks notification as read and triggers onActionTap or onViewNotifications', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final notif = AppNotification(
        id: 'notif-view-test',
        userId: 'usr-login-05',
        title: 'Action Assigned',
        message: 'AC-1006 assigned',
        eventType: 'action_assigned',
        actionId: 'AC-1006',
        isRead: false,
        createdAt: DateTime.now(),
      );

      MockNotificationStore.instance.seed([notif]);

      String? tappedActionId;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: QuickAlertListener(
              userId: 'usr-login-05',
              onActionTap: (actionId) {
                tappedActionId = actionId;
              },
              child: const Text('Dashboard Content'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(QuickAlertToast), findsOneWidget);

      // Tap View button
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();

      // Action tap callback was fired
      expect(tappedActionId, 'AC-1006');

      // Notification is now marked as read
      final updated = MockNotificationStore.instance.allNotificationsForTesting.firstWhere((n) => n.id == 'notif-view-test');
      expect(updated.isRead, isTrue);
    });

    testWidgets('6. Failed fetch can be retried successfully in the same session without permanent suppression', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final notif = AppNotification(
        id: 'notif-retry-01',
        userId: 'usr-retry-01',
        title: 'Action Assigned on Retry',
        message: 'AC-1007 assigned',
        eventType: 'action_assigned',
        actionId: 'AC-1007',
        isRead: false,
        createdAt: DateTime.now(),
      );

      MockNotificationStore.instance.seed([notif]);

      bool failFetch = true;
      final testService = _FailingNotificationService(() => failFetch);

      // Attempt 1: Fetch fails due to simulated network failure
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: QuickAlertListener(
              userId: 'usr-retry-01',
              notificationService: testService,
              child: const Text('Dashboard Content Attempt 1'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // No toast shown because fetch threw an error
      expect(find.byType(QuickAlertToast), findsNothing);

      // Invariant: The session MUST NOT be marked as checked after a failure
      expect(QuickAlertListener.hasCheckedSession('usr-retry-01'), isFalse);

      // Network transient issue resolves
      failFetch = false;

      // Attempt 2: Re-render / retry in the SAME session
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: QuickAlertListener(
              userId: 'usr-retry-01',
              notificationService: testService,
              child: const Text('Dashboard Content Attempt 2'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // The quick alert toast successfully appears on retry in the same session!
      expect(find.byType(QuickAlertToast), findsOneWidget);
      expect(find.text('Action Assigned on Retry'), findsOneWidget);

      // Session is now marked as checked
      expect(QuickAlertListener.hasCheckedSession('usr-retry-01'), isTrue);

      // Dismiss the toast
      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();

      // Attempt 3: Further rebuilds in the same session do NOT duplicate the toast
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: QuickAlertListener(
              userId: 'usr-retry-01',
              notificationService: testService,
              child: const Text('Dashboard Content Attempt 3'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(QuickAlertToast), findsNothing);
    });
  });
}

class _FailingNotificationService implements NotificationService {
  final bool Function() shouldFail;
  final StreamController<AppNotification> _streamCtrl = StreamController<AppNotification>.broadcast();

  _FailingNotificationService(this.shouldFail);

  @override
  Stream<AppNotification> get onNotificationReceived => _streamCtrl.stream;

  @override
  Future<List<AppNotification>> getNotifications({required String userId}) async {
    if (shouldFail()) {
      throw Exception('Simulated transient network error');
    }
    return NotificationService.instance.getNotifications(userId: userId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

