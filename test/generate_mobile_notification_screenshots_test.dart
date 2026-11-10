import 'dart:io';
import 'dart:ui' as ui;

import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/notifications/models/app_notification.dart';
import 'package:action_flow/features/notifications/widgets/notification_dropdown_overlay.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final staffProfile = UserProfile(
    id: 'user-staff-1',
    name: 'Aravind Staff',
    email: 'aravind@example.com',
    phone: '+971501234567',
    role: 'staff',
    designation: 'Safety Specialist',
    department: 'HSE',
    organizationId: 'org-test',
    site: 'Site Alpha',
  );

  const artifactDir = r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23';

  setUp(() {
    NotificationService.useMockOnly = true;
    MockNotificationStore.instance.clear();
    NotificationService.instance.clearReminderSessionCache();

    final now = DateTime.now();
    MockNotificationStore.instance.seed([
      AppNotification(
        id: 'notif-1',
        userId: 'user-staff-1',
        title: 'Safety Inspection Action Assigned',
        message: 'Action ACT-1029 assigned to you for inspection of Zone 4.',
        eventType: 'action_assigned',
        actionId: 'ACT-1029',
        isRead: false,
        createdAt: now.subtract(const Duration(minutes: 5)),
      ),
      AppNotification(
        id: 'notif-2',
        userId: 'user-staff-1',
        title: 'Action Due Today: ACT-1011',
        message: 'Conveyor safety mesh installation requires completion before 18:00.',
        eventType: 'due_date_approaching',
        actionId: 'ACT-1011',
        isRead: false,
        createdAt: now.subtract(const Duration(hours: 1)),
      ),
      AppNotification(
        id: 'notif-3',
        userId: 'user-staff-1',
        title: 'Overdue Subtask: Ventilation Calibration',
        message: 'Subtask for mechanical ventilation calibration is 2 days overdue.',
        eventType: 'action_overdue',
        actionId: 'ACT-1002',
        isRead: true,
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      AppNotification(
        id: 'notif-4',
        userId: 'user-staff-1',
        title: 'New HSSE Document Shared',
        message: 'Emergency response SOP 2026 revision 3 is now available for download.',
        eventType: 'document_shared',
        isRead: true,
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      AppNotification(
        id: 'notif-5',
        userId: 'user-staff-1',
        title: 'Approval Request Pending',
        message: 'Permit to Work request REQ-204 requires your review.',
        eventType: 'request_approval',
        isRead: false,
        createdAt: now.subtract(const Duration(days: 3)),
      ),
    ]);
  });

  Future<void> saveScreenshot(GlobalKey key, String filename) async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();
    final file = File('$artifactDir\\$filename');
    await file.writeAsBytes(pngBytes);
  }

  group('Mobile Browser Verification & Screenshots', () {
    testWidgets('1. iPhone 16 (393x852) - AFTER: Notification Overlay Perfectly Centered & Clamped',
        (tester) async {
      const iphone16 = Size(393, 852);
      await tester.binding.setSurfaceSize(iphone16);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repaintKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, materialChild) => MediaQuery(
            data: const MediaQueryData(
              size: iphone16,
              padding: EdgeInsets.only(top: 47, bottom: 34),
            ),
            child: RepaintBoundary(
              key: repaintKey,
              child: materialChild!,
            ),
          ),
          home: WorkerDashboardScreen(userProfile: staffProfile),
        ),
      );
      await tester.pumpAndSettle();

      // Tap notification bell button
      final bellFinder = find.byType(NotificationBellButton);
      expect(bellFinder, findsOneWidget);
      await tester.tap(bellFinder);
      await tester.pumpAndSettle();

      // Verify overlay is open and perfectly positioned inside [0, 393]
      final overlayFinder = find.byType(NotificationDropdownOverlay);
      expect(overlayFinder, findsOneWidget);

      final topLeft = tester.getTopLeft(overlayFinder);
      final bottomRight = tester.getBottomRight(overlayFinder);
      expect(topLeft.dx, greaterThanOrEqualTo(12.0));
      expect(bottomRight.dx, lessThanOrEqualTo(382.0));
      expect(bottomRight.dy, lessThanOrEqualTo(852.0));

      // Capture screenshot
      await tester.runAsync(() async {
        await saveScreenshot(repaintKey, 'iphone16_notification_panel_after_fixed.png');
      });
    });

    testWidgets('2. iPhone 16 (393x852) - BEFORE: Rigid Follower Left-Edge Clipping Defect',
        (tester) async {
      const iphone16 = Size(393, 852);
      await tester.binding.setSurfaceSize(iphone16);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repaintKey = GlobalKey();

      // Recreate the PREVIOUS broken geometry:
      // Rigid 390px panel top-right anchored to button bottom-right (x = 322px) -> Left = -68px
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, materialChild) => MediaQuery(
            data: const MediaQueryData(
              size: iphone16,
              padding: EdgeInsets.only(top: 47, bottom: 34),
            ),
            child: RepaintBoundary(
              key: repaintKey,
              child: materialChild!,
            ),
          ),
          home: Stack(
            children: [
              WorkerDashboardScreen(userProfile: staffProfile),
              // Simulate the previous follower overlay geometry at Left = -68.0px
              Positioned(
                left: -68.0,
                top: 60.0,
                child: SizedBox(
                  width: 390.0,
                  child: NotificationDropdownOverlay(
                    width: 390.0,
                    maxHeight: 520.0,
                    userId: 'user-staff-1',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Capture screenshot demonstrating the exact reported bug (-68px clipping off the left)
      await tester.runAsync(() async {
        await saveScreenshot(repaintKey, 'iphone16_notification_panel_before_bug.png');
      });
    });

    testWidgets('3. Small Mobile (320x640) - Notification Overlay Fits Within 320px Width',
        (tester) async {
      const smallMobile = Size(320, 640);
      await tester.binding.setSurfaceSize(smallMobile);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repaintKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, materialChild) => MediaQuery(
            data: const MediaQueryData(size: smallMobile),
            child: RepaintBoundary(
              key: repaintKey,
              child: materialChild!,
            ),
          ),
          home: WorkerDashboardScreen(userProfile: staffProfile),
        ),
      );
      await tester.pumpAndSettle();

      final bellFinder = find.byType(NotificationBellButton);
      expect(bellFinder, findsOneWidget);
      await tester.tap(bellFinder);
      await tester.pumpAndSettle();

      final overlayFinder = find.byType(NotificationDropdownOverlay);
      expect(overlayFinder, findsOneWidget);

      final topLeft = tester.getTopLeft(overlayFinder);
      final bottomRight = tester.getBottomRight(overlayFinder);
      expect(topLeft.dx, greaterThanOrEqualTo(12.0));
      expect(bottomRight.dx, lessThanOrEqualTo(309.0));
      expect(bottomRight.dy, lessThanOrEqualTo(640.0));

      await tester.runAsync(() async {
        await saveScreenshot(repaintKey, 'small_mobile_320x640_notification_panel.png');
      });
    });

    testWidgets('4. Tablet (768x1024) - Notification Overlay Right-Anchored to Bell',
        (tester) async {
      const tablet = Size(768, 1024);
      await tester.binding.setSurfaceSize(tablet);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repaintKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, materialChild) => MediaQuery(
            data: const MediaQueryData(size: tablet),
            child: RepaintBoundary(
              key: repaintKey,
              child: materialChild!,
            ),
          ),
          home: WorkerDashboardScreen(userProfile: staffProfile),
        ),
      );
      await tester.pumpAndSettle();

      final bellFinder = find.byType(NotificationBellButton);
      expect(bellFinder, findsOneWidget);
      await tester.tap(bellFinder);
      await tester.pumpAndSettle();

      final overlayFinder = find.byType(NotificationDropdownOverlay);
      expect(overlayFinder, findsOneWidget);

      final topLeft = tester.getTopLeft(overlayFinder);
      final bottomRight = tester.getBottomRight(overlayFinder);
      expect(bottomRight.dx - topLeft.dx, equals(390.0));
      expect(bottomRight.dx, lessThanOrEqualTo(768.0));

      await tester.runAsync(() async {
        await saveScreenshot(repaintKey, 'tablet_768x1024_notification_panel.png');
      });
    });

    testWidgets('5. Desktop (1440x900) - Unchanged Desktop Layout & Standard Positioning',
        (tester) async {
      const desktop = Size(1440, 900);
      await tester.binding.setSurfaceSize(desktop);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repaintKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, materialChild) => MediaQuery(
            data: const MediaQueryData(size: desktop),
            child: RepaintBoundary(
              key: repaintKey,
              child: materialChild!,
            ),
          ),
          home: WorkerDashboardScreen(userProfile: staffProfile),
        ),
      );
      await tester.pumpAndSettle();

      final bellFinder = find.byType(NotificationBellButton);
      expect(bellFinder, findsOneWidget);
      await tester.tap(bellFinder);
      await tester.pumpAndSettle();

      final overlayFinder = find.byType(NotificationDropdownOverlay);
      expect(overlayFinder, findsOneWidget);

      final topLeft = tester.getTopLeft(overlayFinder);
      final bottomRight = tester.getBottomRight(overlayFinder);
      expect(bottomRight.dx - topLeft.dx, equals(390.0));
      expect(bottomRight.dx, lessThanOrEqualTo(1440.0));

      await tester.runAsync(() async {
        await saveScreenshot(repaintKey, 'desktop_1440x900_notification_panel.png');
      });
    });

    testWidgets('6. Safe-Area & Virtual Keyboard Inset Clamping on iPhone 16 (393x852)',
        (tester) async {
      const iphone16 = Size(393, 852);
      await tester.binding.setSurfaceSize(iphone16);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repaintKey = GlobalKey();

      // Simulate active software keyboard taking up 300px from the bottom
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, materialChild) => MediaQuery(
            data: const MediaQueryData(
              size: iphone16,
              padding: EdgeInsets.only(top: 47, bottom: 34),
              viewInsets: EdgeInsets.only(bottom: 300), // Virtual keyboard active!
            ),
            child: RepaintBoundary(
              key: repaintKey,
              child: materialChild!,
            ),
          ),
          home: WorkerDashboardScreen(userProfile: staffProfile),
        ),
      );
      await tester.pumpAndSettle();

      final bellFinder = find.byType(NotificationBellButton);
      expect(bellFinder, findsOneWidget);
      await tester.tap(bellFinder);
      await tester.pumpAndSettle();

      final overlayFinder = find.byType(NotificationDropdownOverlay);
      expect(overlayFinder, findsOneWidget);

      // Verify the panel height is strictly bounded above the keyboard
      final bottomRight = tester.getBottomRight(overlayFinder);
      final maxAllowedY = 852.0 - 300.0 - 16.0; // Above keyboard
      expect(bottomRight.dy, lessThanOrEqualTo(maxAllowedY + 1.0));

      await tester.runAsync(() async {
        await saveScreenshot(repaintKey, 'iphone16_keyboard_and_safe_area_handling.png');
      });
    });

    testWidgets('7. Interaction Verification: Scroll, Filter Tabs, Notification Tap & Close',
        (tester) async {
      const iphone16 = Size(393, 852);
      await tester.binding.setSurfaceSize(iphone16);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, materialChild) => MediaQuery(
            data: const MediaQueryData(size: iphone16),
            child: materialChild!,
          ),
          home: WorkerDashboardScreen(userProfile: staffProfile),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Open panel
      final bellFinder = find.byType(NotificationBellButton);
      await tester.tap(bellFinder);
      await tester.pumpAndSettle();
      expect(find.byType(NotificationDropdownOverlay), findsOneWidget);

      // 2. Test Tab Switching
      final remindersTab = find.descendant(
        of: find.byType(NotificationDropdownOverlay),
        matching: find.text('Action Reminders'),
      );
      expect(remindersTab, findsOneWidget);
      await tester.tap(remindersTab);
      await tester.pumpAndSettle();

      // 3. Test Scrolling through the notification list
      final listFinder = find.descendant(
        of: find.byType(NotificationDropdownOverlay),
        matching: find.byType(ListView),
      );
      expect(listFinder, findsOneWidget);
      await tester.drag(listFinder, const Offset(0, -50));
      await tester.pumpAndSettle();

      // 4. Test Close button in header
      final closeBtn = find.descendant(
        of: find.byType(NotificationDropdownOverlay),
        matching: find.byTooltip('Close'),
      );
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();

      // Overlay is closed
      expect(find.byType(NotificationDropdownOverlay), findsNothing);

      // 5. Re-open and test Dismiss on outside tap (modal barrier)
      await tester.tap(bellFinder);
      await tester.pumpAndSettle();
      expect(find.byType(NotificationDropdownOverlay), findsOneWidget);

      // Tap outside the panel at (20, 700) on the modal barrier
      await tester.tapAt(const Offset(20, 700));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationDropdownOverlay), findsNothing);
    });
  });
}
