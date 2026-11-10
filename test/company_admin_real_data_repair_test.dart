import 'package:action_flow/features/auth/models/auth_models.dart';
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

  group('Company Admin Real Data & Account Flow Repair Tests', () {
    testWidgets(
      'Header search bar provides interactive Autocomplete for system entities',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestableWidget());
        await tester.pumpAndSettle();

        // Find the header autocomplete search field
        final searchFields = find.byType(TextField);
        expect(searchFields, findsWidgets);

        // The header search has hint 'Search actions, users, sites, settings...'
        final headerSearch = find.widgetWithText(
          TextField,
          'Search actions, users, sites, settings...',
        );
        expect(headerSearch, findsOneWidget);

        // Entering 'users' should not pollute the User Directory filter
        await tester.enterText(headerSearch, 'users');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();

        // We should navigate to Tab 1 (Users)
        expect(
          find.text('User Directory & Authentication Roles'),
          findsOneWidget,
        );

        // The User directory search field should remain blank or search users, NOT be forced to 'users'
        final userDirSearch = find.widgetWithText(
          TextField,
          'Search by name, email, designation, site...',
        );
        expect(userDirSearch, findsOneWidget);
        final textFieldWidget = tester.widget<TextField>(userDirSearch);
        expect(textFieldWidget.controller?.text ?? '', isEmpty);
      },
    );

    testWidgets(
      'Users directory search controller clears query and reset filters works',
      (tester) async {
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

        final searchField = find.widgetWithText(
          TextField,
          'Search by name, email, designation, site...',
        );
        expect(searchField, findsOneWidget);

        // Enter search term
        await tester.enterText(searchField, 'Engineering');
        await tester.pumpAndSettle();

        // Reset filters button should appear
        expect(find.text('Reset Filters'), findsOneWidget);

        // Tap Reset Filters
        await tester.tap(find.text('Reset Filters'));
        await tester.pumpAndSettle();

        // Search field should be cleared
        final clearedField = tester.widget<TextField>(searchField);
        expect(clearedField.controller?.text ?? '', isEmpty);
        expect(find.text('Reset Filters'), findsNothing);
      },
    );

    testWidgets(
      'Notifications tab reflects pending account requests dynamically',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestableWidget(initialTab: 7));
        await tester.pumpAndSettle();

        expect(
          find.text('System Alerts & Broadcast Dispatcher'),
          findsOneWidget,
        );
        expect(find.text('New Broadcast'), findsOneWidget);
        // Ensure fake static notifications NOTIF-01 to NOTIF-05 are removed
        expect(find.text('NOTIF-01'), findsNothing);
        expect(find.text('NOTIF-02'), findsNothing);
      },
    );

    testWidgets(
      'Reports tab shows honest state without fake 94.2% compliance in production',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestableWidget(initialTab: 8));
        await tester.pumpAndSettle();

        expect(
          find.text('Executive Action & Compliance Reports'),
          findsOneWidget,
        );
        // Verify fake hardcoded cards are not displayed in production shell
        expect(find.text('94.2%'), findsNothing);
      },
    );

    test('Account request model correctly instantiates with department, site, and team IDs', () {
      final req = SignupRequest(
        id: 'req-123',
        fullName: 'Jane Doe',
        email: 'jane@example.com',
        phone: '+971 50 123 4567',
        designation: 'Safety Officer',
        department: 'HSE',
        departmentId: 'dept-uuid-001',
        site: 'Site Alpha',
        siteId: 'site-uuid-001',
        team: 'Emergency Response Squad',
        teamId: 'team-uuid-001',
        requestedType: RequestedAccountType.staff,
        requestedRoleId: 'staff',
      );

      expect(req.departmentId, 'dept-uuid-001');
      expect(req.siteId, 'site-uuid-001');
      expect(req.teamId, 'team-uuid-001');
      expect(req.requestedType, RequestedAccountType.staff);
      expect(req.initials, 'JD');
    });
  });
}
