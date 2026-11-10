import 'package:action_flow/features/dashboard/admin_dashboard/screens/admin_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final testAdminProfile = UserProfile(
    id: 'test-admin-uuid-1',
    name: 'Sarah Connor',
    email: 'sarah.connor@acme-corp.com',
    phone: '+1 555-0199',
    designation: 'Safety & Operations Director',
    department: 'Health, Safety & Environment',
    division: 'Corporate Operations',
    site: 'Headquarters Facility',
    team: 'Executive Safety Committee',
    role: 'System Administrator',
    accountStatus: 'Active',
    permissions: const [
      'Full System Configuration Access',
      'User, Department & Site Governance',
      'Security Policy & 2FA Enforcement',
      'System Audit Log Inspection',
      'Emergency Broadcast Dispatch',
    ],
    organizationId: 'org-acme-corp-123',
    organizationName: 'Acme Corporation Industries',
  );

  Widget buildTestableWidget({
    Size size = const Size(1280, 800),
    int initialTab = 0,
    UserProfile? profile,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: AdminDashboardScreen(
          initialTabIndex: initialTab,
          adminProfile: profile ?? testAdminProfile,
        ),
      ),
    );
  }

  group(
    'Company Admin Portal - Feature Block 1: Dashboard + Admin Shell Tests',
    () {
      testWidgets(
        'Renders complete Admin Shell with 12 sidebar items and tenant badge',
        (tester) async {
          tester.view.physicalSize = const Size(1280, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await tester.pumpWidget(buildTestableWidget());
          await tester.pumpAndSettle();

          // Header Branding & Profile
          expect(find.text('ADMIN PORTAL'), findsOneWidget);
          expect(find.text('Admin Dashboard'), findsOneWidget);
          expect(find.text('Sarah Connor'), findsWidgets);
          expect(find.text('SC'), findsOneWidget);

          // Verify all 12 navigation items in Sidebar
          expect(find.text('Dashboard'), findsOneWidget);
          expect(find.text('Users'), findsOneWidget);
          expect(find.text('Departments'), findsOneWidget);
          expect(find.text('Sites'), findsOneWidget);
          expect(find.text('Teams'), findsOneWidget);
          expect(find.text('Roles & Permissions'), findsOneWidget);
          expect(find.text('Action Sections'), findsOneWidget);
          expect(find.text('Notifications'), findsOneWidget);
          expect(find.text('Reports'), findsOneWidget);
          expect(find.text('System Settings'), findsOneWidget);
          expect(find.text('Account Requests'), findsOneWidget);
          expect(find.text('Calendar'), findsOneWidget);

          // Verify Dashboard KPI Metric Cards
          expect(find.text('Total Active Users'), findsOneWidget);
          expect(find.text('Total Tracked Actions'), findsOneWidget);
          expect(find.text('Departments & Sites'), findsOneWidget);
          expect(find.text('System Compliance Rate'), findsOneWidget);
          expect(find.text('Teams & Operational Squads'), findsOneWidget);
          expect(find.text('Pending Account Requests'), findsOneWidget);

          // Verify Quick Administrative Actions
          expect(find.text('Quick Administrative Actions'), findsOneWidget);
          expect(find.text('Add User'), findsOneWidget);
          expect(find.text('Add Department'), findsOneWidget);
          expect(find.text('Add Site'), findsOneWidget);
          expect(find.text('Add Team'), findsOneWidget);
          expect(find.text('Review Requests'), findsOneWidget);
          expect(find.text('Broadcast Alert'), findsWidgets);

          // Directory users and activity feed
          expect(find.text('Registered Directory Users'), findsOneWidget);
          expect(find.text('System Audit & Activity Feed'), findsOneWidget);
        },
      );

      testWidgets('Header global search navigates to relevant admin sections', (
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

        // Search for "Calendar" in header search
        final searchField = find.widgetWithText(
          TextField,
          'Search actions, users, sites, settings...',
        );
        expect(searchField, findsOneWidget);

        await tester.enterText(searchField, 'Calendar');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();

        // Should now be on Calendar View (tab 11)
        expect(find.text('Operational Calendar & Schedule'), findsWidgets);

        // Search for "Requests"
        await tester.enterText(searchField, 'Requests');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();

        // Should now be on Account Requests View (tab 10)
        expect(find.text('Account Requests & Approvals'), findsWidgets);
      });

      testWidgets(
        'Operational Calendar view renders month grid, side panel and schedule dialog',
        (tester) async {
          tester.view.physicalSize = const Size(1280, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          // Directly open tab 11 (Calendar)
          await tester.pumpWidget(buildTestableWidget(initialTab: 11));
          await tester.pumpAndSettle();

          // Verify Header
          expect(find.text('Operational Calendar & Schedule'), findsWidgets);
          expect(
            find.text(
              'Company-wide HSE events, scheduled audits, compliance deadlines, and action follow-ups',
            ),
            findsOneWidget,
          );

          // Verify Month Navigation & Weekday labels
          expect(find.text('Today'), findsOneWidget);
          expect(find.text('Mon'), findsOneWidget);
          expect(find.text('Fri'), findsOneWidget);
          expect(find.text('Sun'), findsOneWidget);

          // Verify Events Side Panel and honest Action Tracker note
          expect(find.text('Events & Milestones'), findsOneWidget);
          expect(find.text('Action Follow-Up & Audit Sync'), findsOneWidget);
          expect(
            find.textContaining('Action Tracker module is connected'),
            findsOneWidget,
          );

          // Verify Schedule Event Dialog
          await tester.tap(
            find.widgetWithText(ElevatedButton, 'Schedule Event'),
          );
          await tester.pumpAndSettle();

          expect(find.text('Schedule Operational Event'), findsOneWidget);
          expect(find.text('Event Title *'), findsOneWidget);
          expect(find.text('Category'), findsOneWidget);
          expect(find.text('Target Facility / Site'), findsOneWidget);

          // Dismiss dialog
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(find.text('Schedule Operational Event'), findsNothing);
        },
      );

      testWidgets(
        'Responsive rendering across breakpoints without layout overflow',
        (tester) async {
          final testBreakpoints = [
            const Size(1280, 800), // Desktop
            const Size(768, 1024), // Tablet
            const Size(400, 800), // Mobile
            const Size(320, 640), // Small Mobile
          ];

          for (final size in testBreakpoints) {
            // Test Dashboard (Tab 0)
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1.0;

            await tester.pumpWidget(
              buildTestableWidget(size: size, initialTab: 0),
            );
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: 'Dashboard failed at $size',
            );

            // Test Calendar (Tab 11)
            await tester.pumpWidget(
              buildTestableWidget(size: size, initialTab: 11),
            );
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: 'Calendar failed at $size',
            );
          }

          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        },
      );
    },
  );
}
