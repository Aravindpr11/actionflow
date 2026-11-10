import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildTestableWidget({
    Size size = const Size(1280, 850),
    UserProfile? userProfile,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: WorkerDashboardScreen(userProfile: userProfile),
      ),
    );
  }

  group('WorkerDashboardScreen - Persistent Shell & UI Tests', () {
    testWidgets('Renders all Enterprise Worker Shell elements on Desktop', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestableWidget(size: const Size(1280, 850)));
      await tester.pumpAndSettle();

      // Top Header elements
      expect(find.text('Search my actions, sites...'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // Notification badge
      expect(find.text('R. Kumar'), findsWidgets);
      expect(find.text('Field Operations'), findsOneWidget);
      expect(find.text('Logout'), findsOneWidget);

      // Enterprise Sidebar Navigation (9 items)
      expect(find.text('My Dashboard'), findsOneWidget);
      expect(find.text('My Actions'), findsWidgets);
      expect(find.text('Reports'), findsOneWidget);
      expect(find.text('Pending Updates'), findsWidgets);
      expect(find.text('Calendar'), findsWidgets);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Documents'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      // Header Banner (Staff Portal adapted)
      expect(find.text('Staff Dashboard'), findsOneWidget);
      expect(find.text('My Action Management Overview'), findsOneWidget);
      expect(find.text('View Full Reports'), findsOneWidget);

      // Manager-grade Components adapted for Staff
      expect(find.text('Total Actions'), findsWidgets);
      expect(find.text('In Progress'), findsWidgets);
      expect(find.text('Overdue'), findsWidgets);
      expect(find.text('Closed'), findsWidgets);
      expect(find.text('Action Status Distribution'), findsOneWidget);
      expect(find.text('Progress Distribution'), findsOneWidget);
      expect(find.text('Quick Actions'), findsOneWidget);
      expect(find.text('Actions Due vs Completed (Last 30 Days)'), findsOneWidget);
      expect(find.text('Upcoming Follow-Ups'), findsOneWidget);
      expect(find.text('Recent Activity'), findsOneWidget);
    });

    testWidgets(
      'Persistent Worker Shell: Switching sidebar items replaces center content',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 850);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildTestableWidget(size: const Size(1280, 850)),
        );
        await tester.pumpAndSettle();

        // 1. My Actions tab (index 1)
        await tester.tap(find.text('My Actions').first);
        await tester.pumpAndSettle();
        expect(find.text('Filter & Search Actions'), findsOneWidget);
        expect(find.textContaining('My Assigned Actions'), findsOneWidget);

        // 2. Reports tab (index 2)
        await tester.tap(find.text('Reports'));
        await tester.pumpAndSettle();
        expect(find.text('Export Excel'), findsWidgets);

        // 3. Pending Updates tab (index 3)
        await tester.tap(find.text('Pending Updates').first);
        await tester.pumpAndSettle();
        expect(find.textContaining('Pending Action Updates'), findsOneWidget);

        // 4. Calendar tab (index 4)
        await tester.tap(find.text('Calendar').first);
        await tester.pumpAndSettle();
        expect(find.text('Action Calendar & Due Dates'), findsOneWidget);

        // 5. Notifications tab (index 5)
        await tester.tap(find.text('Notifications'));
        await tester.pumpAndSettle();
        expect(find.text('Notifications & Alerts'), findsOneWidget);

        // 6. Documents tab (index 6)
        await tester.tap(find.text('Documents'));
        await tester.pumpAndSettle();
        expect(find.text('Safety Documents & Guidelines'), findsOneWidget);

        // 7. Profile tab (index 7)
        await tester.tap(find.text('Profile'));
        await tester.pumpAndSettle();
        expect(find.text('Staff Profile'), findsOneWidget);
        expect(find.text('Employee ID'), findsOneWidget);
        expect(find.text('EMP-2049'), findsOneWidget);

        // 8. Settings tab (index 8)
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        expect(find.text('Preferences & Settings'), findsOneWidget);
        expect(find.text('Action Due Reminders'), findsOneWidget);

        // 9. Return to My Dashboard (index 0)
        await tester.tap(find.text('My Dashboard'));
        await tester.pumpAndSettle();
        expect(find.text('Staff Dashboard'), findsOneWidget);
      },
    );

    testWidgets('Binds dynamically to custom UserProfile', (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final customProfile = UserProfile.mockStaff().copyWith(
        id: 'EMP-9000',
        name: 'Sarah Connor',
        email: 'sarah.connor@actionflow.com',
        department: 'Cybernetics Safety',
        organizationName: 'Cyberdyne Systems',
      );

      await tester.pumpWidget(
        buildTestableWidget(
          size: const Size(1280, 850),
          userProfile: customProfile,
        ),
      );
      await tester.pumpAndSettle();

      // Top header renders Sarah Connor
      expect(find.text('Sarah Connor'), findsWidgets);
      expect(find.text('Cyberdyne Systems'), findsWidgets);

      // Navigate to Profile tab
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('EMP-9000'), findsOneWidget);
      expect(find.text('Cybernetics Safety'), findsOneWidget);
    });
  });

  group('WorkerDashboardScreen - Responsive Layout Verification', () {
    testWidgets('Renders with zero overflow at Desktop (1200px)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestableWidget(size: const Size(1200, 850)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Staff Dashboard'), findsOneWidget);
    });

    testWidgets('Renders with zero overflow at Tablet (768px)', (tester) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestableWidget(size: const Size(768, 1024)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Staff Dashboard'), findsOneWidget);
    });

    testWidgets('Renders with zero overflow at Mobile (400px)', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestableWidget(size: const Size(400, 800)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Staff Dashboard'), findsOneWidget);
    });

    testWidgets('Renders with zero overflow at Small Mobile (320px)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestableWidget(size: const Size(320, 600)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Staff Dashboard'), findsOneWidget);
    });
  });
}
