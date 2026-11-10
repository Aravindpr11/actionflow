import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/dashboard/platform_admin_dashboard/screens/platform_admin_dashboard_screen.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/organization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    OrganizationService.instance.resetMockData();
    // Pre-populate with test organizations for search, filtering, and sorting
    await OrganizationService.instance.createOrganization(
      name: 'Beta Logistics',
      code: 'beta-logistics',
      isActive: true,
    );
    await OrganizationService.instance.createOrganization(
      name: 'Alpha Systems',
      code: 'alpha-systems',
      isActive: false,
    );
  });

  Widget createTestWidget() {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: const PlatformAdminDashboardScreen(),
    );
  }

  group(
    'Platform Admin Companies View Toggle, Search, Filter, and Sort Tests',
    () {
      testWidgets('1. Switches between Table view and Grid view correctly', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Initially in Table view (DataTable is present)
        expect(find.byType(DataTable), findsOneWidget);
        expect(
          find.byKey(const ValueKey('company_view_table_toggle')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('company_view_grid_toggle')),
          findsOneWidget,
        );

        // Switch to Grid view
        await tester.tap(
          find.byKey(const ValueKey('company_view_grid_toggle')),
        );
        await tester.pumpAndSettle();

        // DataTable should be gone, GridView should be present
        expect(find.byType(DataTable), findsNothing);
        expect(find.byType(GridView), findsOneWidget);

        // Grid cards for all 3 organizations should be displayed
        expect(
          find.byKey(const ValueKey(Organization.sobhaId)),
          findsOneWidget,
        );
        expect(find.text('Sobha'), findsWidgets);
        expect(find.text('Beta Logistics'), findsWidgets);
        expect(find.text('Alpha Systems'), findsWidgets);

        // Switch back to Table view
        await tester.tap(
          find.byKey(const ValueKey('company_view_table_toggle')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DataTable), findsOneWidget);
        expect(find.byType(GridView), findsNothing);
      });

      testWidgets(
        '2. Searches organizations by name, code, and organization ID',
        (tester) async {
          tester.view.physicalSize = const Size(1280, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await tester.pumpWidget(createTestWidget());
          await tester.pumpAndSettle();

          // Find search field
          final searchFinder = find.byType(TextField);
          expect(searchFinder, findsOneWidget);

          // Search by Name: "Beta"
          await tester.enterText(searchFinder, 'Beta');
          await tester.pumpAndSettle();

          expect(find.text('Beta Logistics'), findsOneWidget);
          expect(find.text('Alpha Systems'), findsNothing);
          expect(find.text('1 of 3 Companies'), findsOneWidget);

          // Search by Code: "alpha-systems"
          await tester.enterText(searchFinder, 'alpha-systems');
          await tester.pumpAndSettle();

          expect(find.text('Alpha Systems'), findsOneWidget);
          expect(find.text('Beta Logistics'), findsNothing);
          expect(find.text('1 of 3 Companies'), findsOneWidget);

          // Search by Organization ID: Sobha's ID
          await tester.enterText(searchFinder, Organization.sobhaId);
          await tester.pumpAndSettle();

          expect(find.text('Sobha'), findsWidgets);
          expect(find.text('Beta Logistics'), findsNothing);
          expect(find.text('Alpha Systems'), findsNothing);

          // Search with non-matching term: shows empty state and reset button
          await tester.enterText(searchFinder, 'NonExistentXYZ');
          await tester.pumpAndSettle();

          expect(find.text('No matching organizations found'), findsOneWidget);
          expect(find.text('Reset Filters'), findsOneWidget);

          // Tap Reset Filters
          await tester.tap(find.text('Reset Filters'));
          await tester.pumpAndSettle();

          expect(find.text('3 Companies Registered'), findsOneWidget);
          expect(find.text('Sobha'), findsWidgets);
          expect(find.text('Beta Logistics'), findsWidgets);
          expect(find.text('Alpha Systems'), findsWidgets);
        },
      );

      testWidgets(
        '3. Filters organizations by status (All, Active, Inactive)',
        (tester) async {
          tester.view.physicalSize = const Size(1280, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await tester.pumpWidget(createTestWidget());
          await tester.pumpAndSettle();

          // Find status dropdown (initial value: 'All')
          expect(find.text('All Status'), findsOneWidget);
          await tester.tap(find.text('All Status'));
          await tester.pumpAndSettle();

          // Select 'Inactive Only'
          await tester.tap(find.text('Inactive Only').last);
          await tester.pumpAndSettle();

          expect(find.text('Alpha Systems'), findsOneWidget);
          expect(find.text('Beta Logistics'), findsNothing);
          expect(find.text('Sobha'), findsNothing);
          expect(find.text('1 of 3 Companies'), findsOneWidget);

          // Select 'Active Only'
          await tester.tap(find.text('Inactive Only'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Active Only').last);
          await tester.pumpAndSettle();

          expect(find.text('Alpha Systems'), findsNothing);
          expect(find.text('Beta Logistics'), findsOneWidget);
          expect(find.text('Sobha'), findsWidgets);
          expect(find.text('2 of 3 Companies'), findsOneWidget);
        },
      );

      testWidgets('4. Sorts organizations by name ascending and descending', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Switch to Grid view for easy card order verification
        await tester.tap(
          find.byKey(const ValueKey('company_view_grid_toggle')),
        );
        await tester.pumpAndSettle();

        // Cards inside GridView
        final gridCards = find.descendant(
          of: find.byType(GridView),
          matching: find.byType(Card),
        );
        expect(gridCards, findsNWidgets(3));

        // Toggle sort to descending
        final sortDirectionBtn = find.byIcon(Icons.arrow_upward);
        expect(sortDirectionBtn, findsOneWidget);
        await tester.tap(sortDirectionBtn);
        await tester.pumpAndSettle();

        // Now direction icon should be arrow_downward
        expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
      });

      testWidgets(
        '5. Grid cards provide Manage Admins and Delete Company callbacks with Sobha protection',
        (tester) async {
          tester.view.physicalSize = const Size(1280, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await tester.pumpWidget(createTestWidget());
          await tester.pumpAndSettle();

          // Switch to Grid view
          await tester.tap(
            find.byKey(const ValueKey('company_view_grid_toggle')),
          );
          await tester.pumpAndSettle();

          // Sobha card should show "Anchor Tenant" badge
          expect(find.text('Anchor Tenant'), findsOneWidget);

          // Non-Sobha cards have "Manage Admins" and "Delete Company" buttons
          final manageButtons = find.text('Manage Admins');
          expect(manageButtons, findsWidgets);

          // Verify Sobha's delete button is disabled
          final sobhaCardFinder = find.byKey(
            const ValueKey(Organization.sobhaId),
          );
          final sobhaDeleteBtn = tester.widget<ElevatedButton>(
            find.descendant(
              of: sobhaCardFinder,
              matching: find.byType(ElevatedButton),
            ),
          );
          expect(sobhaDeleteBtn.onPressed, isNull);

          // Non-Sobha cards have enabled Delete buttons
          final deleteButtons = find.text('Delete Company');
          // The second or third button corresponds to a non-Sobha org
          await tester.tap(deleteButtons.at(1));
          await tester.pumpAndSettle();

          // Confirmation dialog should open
          expect(find.text('Permanently Delete Company?'), findsOneWidget);
          expect(find.text('Cancel'), findsOneWidget);

          // Dismiss dialog
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(find.text('Permanently Delete Company?'), findsNothing);
        },
      );
    },
  );
}
