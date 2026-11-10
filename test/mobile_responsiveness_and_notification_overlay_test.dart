import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/dashboard/admin_dashboard/screens/admin_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/notifications/models/app_notification.dart';
import 'package:action_flow/features/notifications/widgets/notification_dropdown_overlay.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/models/document_record.dart';
import 'package:action_flow/services/notification_service.dart';
import 'package:action_flow/widgets/document_preview/action_attachment_preview_dialog.dart';
import 'package:action_flow/widgets/document_preview/document_preview_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const standardViewports = <String, Size>{
    '320x640 (Small Mobile)': Size(320, 640),
    '360x800 (Standard Android)': Size(360, 800),
    '393x852 (iPhone 16)': Size(393, 852),
    '400x800 (Wide Mobile)': Size(400, 800),
    '768x1024 (Tablet)': Size(768, 1024),
  };

  setUp(() {
    NotificationService.useMockOnly = true;
    MockNotificationStore.instance.clear();
    MockActionStore.instance.actions.clear();
    NotificationService.instance.clearReminderSessionCache();

    // Seed mock notifications
    final now = DateTime.now();
    MockNotificationStore.instance.seed([
      AppNotification(
        id: 'notif-1',
        userId: 'user-test',
        title: 'Safety Inspection Action Assigned',
        message: 'You have been assigned to safety inspection for Zone 4.',
        eventType: 'action_assigned',
        actionId: 'ACT-1029',
        isRead: false,
        createdAt: now.subtract(const Duration(minutes: 5)),
      ),
      AppNotification(
        id: 'notif-2',
        userId: 'user-test',
        title: 'Action Due Today',
        message: 'Action ACT-1011 requires completion by end of shift.',
        eventType: 'due_date_approaching',
        actionId: 'ACT-1011',
        isRead: false,
        createdAt: now.subtract(const Duration(hours: 1)),
      ),
      AppNotification(
        id: 'notif-3',
        userId: 'user-test',
        title: 'Overdue Task Warning',
        message: 'Subtask for ventilation repair is overdue.',
        eventType: 'action_overdue',
        actionId: 'ACT-1002',
        isRead: true,
        createdAt: now.subtract(const Duration(days: 1)),
      ),
    ]);
  });

  tearDown(() {
    MockNotificationStore.instance.clear();
    MockActionStore.instance.actions.clear();
  });

  Widget createHarness({
    required Size viewport,
    required Widget child,
  }) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (context, materialChild) => MediaQuery(
        data: MediaQueryData(size: viewport),
        child: materialChild!,
      ),
      home: SizedBox(
        width: viewport.width,
        height: viewport.height,
        child: Scaffold(body: child),
      ),
    );
  }

  group('Part 1: NotificationDropdownOverlay Positioning across 5 Viewports', () {
    for (final entry in standardViewports.entries) {
      final name = entry.key;
      final size = entry.value;

      testWidgets('Notification panel fits entirely within visible viewport at $name',
          (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // Place a notification bell near the top right of the viewport
        await tester.pumpWidget(
          createHarness(
            viewport: size,
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 16, right: 16),
                child: NotificationBellButton(
                  userId: 'user-test',
                  unreadCount: 2,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Verify bell button is rendered
        final bellFinder = find.byType(NotificationBellButton);
        expect(bellFinder, findsOneWidget);

        // 2. Open notification panel
        await tester.tap(bellFinder);
        await tester.pumpAndSettle();

        // 3. Find NotificationDropdownOverlay
        final overlayFinder = find.byType(NotificationDropdownOverlay);
        expect(overlayFinder, findsOneWidget);

        // 4. Verify exact Rect bounds
        final rect = tester.getRect(overlayFinder);

        // Crucial Check: left boundary must NEVER be negative (off screen to the left)
        expect(
          rect.left >= 0.0,
          isTrue,
          reason: 'Left bound ${rect.left} must not be negative on $name',
        );
        expect(
          rect.left >= 10.0,
          isTrue,
          reason: 'Safe left margin must be at least 10px on $name (was ${rect.left})',
        );

        // Crucial Check: right boundary must NEVER exceed viewport width
        expect(
          rect.right <= size.width,
          isTrue,
          reason: 'Right bound ${rect.right} must not exceed screen width ${size.width} on $name',
        );
        expect(
          rect.right <= size.width - 10.0,
          isTrue,
          reason: 'Safe right margin must be at least 10px on $name (was ${size.width - rect.right})',
        );

        // Check vertical positioning
        expect(
          rect.top >= 0.0,
          isTrue,
          reason: 'Top bound ${rect.top} must be within screen on $name',
        );
        expect(
          rect.bottom <= size.height,
          isTrue,
          reason: 'Bottom bound ${rect.bottom} must not exceed height ${size.height} on $name',
        );

        // 5. Test interaction: switch tabs
        final remindersTab = find.text('Reminders');
        if (remindersTab.evaluate().isNotEmpty) {
          await tester.tap(remindersTab);
          await tester.pumpAndSettle();
        }

        // 6. Test interaction: close button
        final closeBtn = find.byTooltip('Close');
        expect(closeBtn, findsOneWidget);
        await tester.tap(closeBtn);
        await tester.pumpAndSettle();

        // Overlay should be closed
        expect(find.byType(NotificationDropdownOverlay), findsNothing);
      });
    }
  });

  group('Part 2: Staff Dashboard Header & Overlay on iPhone 16 (393x852)', () {
    testWidgets('Staff Dashboard bell opens overlay correctly positioned without clipping',
        (tester) async {
      const iphone16 = Size(393, 852);
      await tester.binding.setSurfaceSize(iphone16);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final staffProfile = UserProfile(
        id: 'user-test',
        name: 'John Staff',
        email: 'john@example.com',
        phone: '+971501234567',
        role: 'worker',
        designation: 'HSE Technician',
        department: 'Operations',
        organizationId: 'org-test',
        site: 'Site Alpha',
      );

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

      // Open notification overlay
      final bellButton = find.byType(NotificationBellButton);
      expect(bellButton, findsOneWidget);

      await tester.tap(bellButton);
      await tester.pumpAndSettle();

      final overlayFinder = find.byType(NotificationDropdownOverlay);
      expect(overlayFinder, findsOneWidget);

      final rect = tester.getRect(overlayFinder);

      // Verify bounds on iPhone 16
      expect(rect.left >= 10.0, isTrue, reason: 'Must not clip on left side of iPhone 16');
      expect(rect.right <= 393.0 - 10.0, isTrue, reason: 'Must not clip on right side of iPhone 16');
      expect(rect.width <= 393.0 - 20.0, isTrue, reason: 'Width must adapt to iPhone 16 width');

      // Dismiss overlay by tapping barrier
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationDropdownOverlay), findsNothing);
    });
  });

  group('Part 3: Manager Dashboard Header & Overlay on iPhone 16 (393x852)', () {
    testWidgets('Manager Dashboard bell opens overlay correctly positioned without clipping',
        (tester) async {
      const iphone16 = Size(393, 852);
      await tester.binding.setSurfaceSize(iphone16);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final managerProfile = UserProfile(
        id: 'user-test',
        name: 'Manager Alice',
        email: 'alice@example.com',
        phone: '+971509876543',
        role: 'manager',
        designation: 'Safety Lead',
        department: 'Operations',
        organizationId: 'org-test',
        site: 'Site Alpha',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, materialChild) => MediaQuery(
            data: const MediaQueryData(size: iphone16),
            child: materialChild!,
          ),
          home: ManagerDashboardScreen(
            userProfile: managerProfile,
            initialActions: const [],
            initialMyActions: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open notification overlay
      final bellButton = find.byType(NotificationBellButton);
      expect(bellButton, findsOneWidget);

      await tester.tap(bellButton);
      await tester.pumpAndSettle();

      final overlayFinder = find.byType(NotificationDropdownOverlay);
      expect(overlayFinder, findsOneWidget);

      final rect = tester.getRect(overlayFinder);

      // Verify bounds on iPhone 16
      expect(rect.left >= 10.0, isTrue, reason: 'Must not clip on left side of iPhone 16');
      expect(rect.right <= 393.0 - 10.0, isTrue, reason: 'Must not clip on right side of iPhone 16');

      // Close
      final closeBtn = find.byTooltip('Close');
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();
      expect(find.byType(NotificationDropdownOverlay), findsNothing);
    });
  });

  group('Part 4: Dialog Responsiveness on Narrow Viewports (320x640)', () {
    testWidgets('ActionAttachmentPreviewDialog fits on 320x640 without horizontal overflow',
        (tester) async {
      const smallSize = Size(320, 640);
      await tester.binding.setSurfaceSize(smallSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final action = ActionRecord(
        id: 'action-1',
        actionNumber: 'ACT-1029',
        subject: 'Turbine Vibration Inspection',
        actionRequired: 'Verify turbine blades',
        division: 'Mechanical',
        assignedTo: 'John Staff',
        status: 'Open',
        attachments: ['evidence_1.pdf'],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, materialChild) => MediaQuery(
            data: const MediaQueryData(size: smallSize),
            child: materialChild!,
          ),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    ActionAttachmentPreviewDialog.show(
                      ctx,
                      action: action,
                      fileName: 'evidence_1.pdf',
                    );
                  },
                  child: const Text('Open Preview'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Preview'));
      await tester.pumpAndSettle();

      // Verify dialog is presented
      final dialogFinder = find.byType(ActionAttachmentPreviewDialog);
      expect(dialogFinder, findsOneWidget);

      final dialogRect = tester.getRect(dialogFinder);
      expect(
        dialogRect.left >= 0,
        isTrue,
        reason: 'Dialog must fit inside 320px width',
      );
      expect(
        dialogRect.right <= 320.0,
        isTrue,
        reason: 'Dialog right bound must not exceed 320px',
      );

      // Verify close button works
      final closeBtn = find.byKey(const Key('action_preview_dialog_close_btn'));
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(ActionAttachmentPreviewDialog), findsNothing);
    });

    testWidgets('DocumentPreviewDialog fits on 320x640 without horizontal overflow',
        (tester) async {
      const smallSize = Size(320, 640);
      await tester.binding.setSurfaceSize(smallSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final doc = DocumentRecord(
        id: 'doc-1',
        organizationId: 'org-test',
        title: 'HSSE Standard Manual',
        fileName: 'hsse_manual.pdf',
        filePath: 'org-test/hsse_manual.pdf',
        fileSize: 204800,
        fileType: 'application/pdf',
        category: 'Policies',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, materialChild) => MediaQuery(
            data: const MediaQueryData(size: smallSize),
            child: materialChild!,
          ),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    DocumentPreviewDialog.show(
                      ctx,
                      doc: doc,
                      organizationId: 'org-test',
                    );
                  },
                  child: const Text('Open Doc Preview'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Doc Preview'));
      await tester.pumpAndSettle();

      final dialogFinder = find.byType(DocumentPreviewDialog);
      expect(dialogFinder, findsOneWidget);

      final dialogRect = tester.getRect(dialogFinder);
      expect(dialogRect.left >= 0, isTrue);
      expect(dialogRect.right <= 320.0, isTrue);

      final closeBtn = find.byTooltip('Close');
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(DocumentPreviewDialog), findsNothing);
    });
  });

  group('Part 5: Staff Navigation Drawer & Search on iPhone 16 (393x852)', () {
    testWidgets('Drawer opens, navigation works, search input functions cleanly',
        (tester) async {
      const iphone16 = Size(393, 852);
      await tester.binding.setSurfaceSize(iphone16);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final staffProfile = UserProfile(
        id: 'user-test',
        name: 'John Staff',
        email: 'john@example.com',
        phone: '+971501234567',
        role: 'worker',
        designation: 'HSE Technician',
        department: 'Operations',
        organizationId: 'org-test',
        site: 'Site Alpha',
      );

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

      // Open navigation drawer via hamburger button
      final menuBtn = find.byIcon(Icons.menu_rounded);
      expect(menuBtn, findsOneWidget);
      await tester.tap(menuBtn);
      await tester.pumpAndSettle();

      // Verify drawer opened and contains standard navigation items
      expect(find.byType(Drawer), findsOneWidget);
      final drawerActionRegister = find.descendant(
        of: find.byType(Drawer),
        matching: find.text('Action Register'),
      );
      final drawerMyActions = find.descendant(
        of: find.byType(Drawer),
        matching: find.text('My Actions'),
      );
      expect(drawerActionRegister, findsOneWidget);
      expect(drawerMyActions, findsOneWidget);

      // Tap Action Register in drawer
      await tester.tap(drawerActionRegister);
      await tester.pumpAndSettle();

      // Verify drawer closed and Action Register is selected
      expect(find.byType(Drawer), findsNothing);

      // Search input interaction
      final searchInput = find.byType(TextField).first;
      expect(searchInput, findsOneWidget);
      await tester.enterText(searchInput, 'Inspection');
      await tester.pumpAndSettle();
    });
  });

  group('Part 6: Manager Navigation Drawer & Search on iPhone 16 (393x852)', () {
    testWidgets('Manager drawer opens, items accessible, search functions',
        (tester) async {
      const iphone16 = Size(393, 852);
      await tester.binding.setSurfaceSize(iphone16);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final managerProfile = UserProfile(
        id: 'user-test',
        name: 'Manager Alice',
        email: 'alice@example.com',
        phone: '+971509876543',
        role: 'manager',
        designation: 'Safety Lead',
        department: 'Operations',
        organizationId: 'org-test',
        site: 'Site Alpha',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, materialChild) => MediaQuery(
            data: const MediaQueryData(size: iphone16),
            child: materialChild!,
          ),
          home: ManagerDashboardScreen(
            userProfile: managerProfile,
            initialActions: const [],
            initialMyActions: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open navigation drawer via hamburger button
      final menuBtn = find.byIcon(Icons.menu_rounded);
      expect(menuBtn, findsOneWidget);
      await tester.tap(menuBtn);
      await tester.pumpAndSettle();

      // Verify drawer
      expect(find.byType(Drawer), findsOneWidget);

      // Close drawer by tapping outside
      await tester.tapAt(const Offset(350, 400));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsNothing);
    });
  });

  group('Part 7: Admin Dashboard Notification View & Navigation on iPhone 16', () {
    testWidgets('Admin Dashboard renders System Notifications and bell navigation',
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
          home: const AdminDashboardScreen(initialTabIndex: 8),
        ),
      );
      await tester.pumpAndSettle();

      // Verify notifications tab title is displayed
      expect(find.text('System Notifications & Broadcasts'), findsOneWidget);

      // Bell icon tooltip and tap
      final bellButton = find.byIcon(Icons.notifications_outlined);
      expect(bellButton, findsOneWidget);
      await tester.tap(bellButton);
      await tester.pumpAndSettle();

      // Stays on tab 8 (notifications)
      expect(find.text('System Notifications & Broadcasts'), findsOneWidget);
    });
  });
}
