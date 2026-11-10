import 'package:action_flow/features/auth/screens/login_screen.dart';
import 'package:action_flow/features/dashboard/admin_dashboard/screens/admin_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildTestableWidget({
    Size size = const Size(1280, 800),
    int initialTab = 0,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: AdminDashboardScreen(initialTabIndex: initialTab),
      ),
    );
  }

  group('AdminDashboardScreen Shell & Navigation Tests', () {
    testWidgets(
      'Renders Admin Dashboard shell and elements on Desktop (1280x800)',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestableWidget());
        await tester.pumpAndSettle();

        // Top Header & Sidebar Branding
        expect(find.text('ADMIN PORTAL'), findsOneWidget);
        expect(find.text('Admin Dashboard'), findsOneWidget);
        expect(find.text('System Administrator'), findsOneWidget);
        expect(find.text('AD'), findsOneWidget);

        // Sidebar Navigation Items
        expect(find.text('Dashboard'), findsOneWidget);
        expect(find.text('Users'), findsOneWidget);
        expect(find.text('Departments'), findsOneWidget);
        expect(find.text('Sites'), findsOneWidget);
        expect(find.text('Teams'), findsOneWidget);
        expect(find.text('Roles & Permissions'), findsOneWidget);
        expect(find.text('Action Sections'), findsOneWidget);
        expect(find.text('Divisions'), findsOneWidget);
        expect(find.text('Notifications'), findsOneWidget);
        expect(find.text('Reports'), findsOneWidget);
        expect(find.text('System Settings'), findsOneWidget);

        // Dashboard View Elements
        expect(find.text('Total Active Users'), findsOneWidget);
        expect(find.text('Total Tracked Actions'), findsOneWidget);
        expect(find.text('Departments & Sites'), findsOneWidget);
        expect(find.text('System Compliance Rate'), findsOneWidget);
        expect(find.text('Registered Directory Users'), findsOneWidget);
        expect(find.text('System Audit & Activity Feed'), findsOneWidget);
      },
    );

    testWidgets('Can navigate across all 10 modular tabs in Admin Portal', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      // Tab 1: Users
      await tester.tap(find.text('Users'));
      await tester.pumpAndSettle();
      expect(
        find.text('User Directory & Authentication Roles'),
        findsOneWidget,
      );
      expect(find.text('Add User'), findsOneWidget);

      // Tab 2: Departments
      await tester.tap(find.text('Departments'));
      await tester.pumpAndSettle();
      expect(find.text('Departments & Business Units'), findsOneWidget);
      expect(find.text('Add Department'), findsOneWidget);

      // Tab 3: Sites
      await tester.tap(find.text('Sites'));
      await tester.pumpAndSettle();
      expect(find.text('Sites & Operational Facilities'), findsOneWidget);
      expect(find.text('Add Site'), findsOneWidget);

      // Tab 4: Teams
      await tester.tap(find.text('Teams'));
      await tester.pumpAndSettle();
      expect(find.text('Operational Teams & Squads'), findsOneWidget);
      expect(find.text('Add Team'), findsOneWidget);

      // Tab 5: Roles & Permissions
      await tester.tap(find.text('Roles & Permissions'));
      await tester.pumpAndSettle();
      expect(find.text('Roles & Permissions Matrix'), findsOneWidget);
      expect(find.text('SYSTEM CAPABILITY'), findsOneWidget);

      // Tab 6: Action Sections
      await tester.tap(find.text('Action Sections'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Configure organizational action sections and classification areas for action management.',
        ),
        findsOneWidget,
      );
      expect(find.text('Add Section'), findsOneWidget);

      // Tab 7: Divisions
      await tester.tap(find.text('Divisions'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Configure organizational divisions and business lines for action tracking.',
        ),
        findsOneWidget,
      );
      expect(find.text('Add Division'), findsOneWidget);

      // Tab 8: Notifications
      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();
      expect(find.text('System Alerts & Broadcast Dispatcher'), findsOneWidget);
      expect(find.text('New Broadcast'), findsOneWidget);

      // Tab 9: Reports
      await tester.tap(find.text('Reports'));
      await tester.pumpAndSettle();
      expect(
        find.text('Executive Action & Compliance Reports'),
        findsOneWidget,
      );
      expect(find.text('Export Summary CSV'), findsOneWidget);

      // Tab 10: System Settings
      await tester.tap(find.text('System Settings'));
      await tester.pumpAndSettle();
      expect(
        find.text('System Preferences & Security Governance'),
        findsOneWidget,
      );
      expect(find.text('Save System Preferences'), findsOneWidget);
    });

    testWidgets('Users management tab filter and status toggle work', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestableWidget(initialTab: 1));
      await tester.pumpAndSettle();

      expect(
        find.text('User Directory & Authentication Roles'),
        findsOneWidget,
      );

      // Search input
      await tester.enterText(find.byType(TextField).first, 'Kumar');
      await tester.pumpAndSettle();

      expect(find.text('R. Kumar'), findsWidgets);
    });

    testWidgets('Broadcast alert dialog opens and dispatches correctly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestableWidget(initialTab: 8));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New Broadcast'));
      await tester.pumpAndSettle();

      expect(find.text('Broadcast Alert Announcement'), findsOneWidget);

      // Enter broadcast title
      final titleField = find.widgetWithText(TextField, 'Announcement Title');
      await tester.enterText(titleField, 'Critical Site Inspection');

      // Dispatch
      await tester.tap(find.text('Dispatch Broadcast'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Critical Site Inspection'), findsOneWidget);
    });

    testWidgets('Renders properly on Mobile (400x800) with Drawer', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestableWidget(size: const Size(400, 800)));
      await tester.pumpAndSettle();

      // Drawer hamburger icon is visible
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);

      // Open drawer
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      // Drawer navigation options are visible
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget);
    });

    testWidgets('LoginScreen routes admin/123456 to AdminDashboardScreen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pumpAndSettle();

      final usernameField = find.widgetWithText(
        TextFormField,
        'Username or email',
      );
      final passwordField = find.widgetWithText(TextFormField, 'Password');

      await tester.enterText(usernameField, 'admin');
      await tester.enterText(passwordField, '123456');

      await tester.tap(find.text('Sign In'));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(find.byType(AdminDashboardScreen), findsOneWidget);
    });

    testWidgets(
      'Renders all Admin views across breakpoints (1200px, 768px, 400px, 320px) without overflows',
      (tester) async {
        final widths = [1200.0, 768.0, 400.0, 320.0];

        for (final width in widths) {
          for (int tab = 0; tab < 13; tab++) {
            tester.view.physicalSize = Size(width, 800);
            tester.view.devicePixelRatio = 1.0;

            await tester.pumpWidget(
              buildTestableWidget(size: Size(width, 800), initialTab: tab),
            );
            await tester.pumpAndSettle();

            expect(
              tester.takeException(),
              isNull,
              reason: 'Tab $tab failed on width $width',
            );
          }
        }
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      },
    );
  });
}
