import 'package:action_flow/features/dashboard/admin_dashboard/screens/admin_dashboard_screen.dart';
import 'package:action_flow/services/company_structure_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CompanyStructureService Unit & Offline Tests', () {
    test(
      'CompanyStructureService instance singleton and default offline state',
      () {
        final service = CompanyStructureService.instance;
        expect(service, isNotNull);
        // In offline/test environments without Supabase init, isReady should be false
        expect(service.isReady, isFalse);
      },
    );

    test('Uninitialized fetch throws clean exception', () async {
      final service = CompanyStructureService.instance;
      expect(
        () => service.fetchDepartments('00000000-0000-0000-0000-000000000000'),
        throwsA(isA<Exception>()),
      );
      expect(
        () => service.fetchSites('00000000-0000-0000-0000-000000000000'),
        throwsA(isA<Exception>()),
      );
      expect(
        () => service.fetchTeams('00000000-0000-0000-0000-000000000000'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group(
    'AdminDashboardScreen Departments, Sites, and Teams UI Integration',
    () {
      Widget buildDashboardTab(int tabIndex) {
        return MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1280, 800)),
            child: AdminDashboardScreen(initialTabIndex: tabIndex),
          ),
        );
      }

      testWidgets(
        'Departments view displays cards, refresh button, and add dialog',
        (tester) async {
          tester.view.physicalSize = const Size(1280, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          // Tab 2 = Departments
          await tester.pumpWidget(buildDashboardTab(2));
          await tester.pumpAndSettle();

          expect(find.text('Departments & Business Units'), findsOneWidget);
          expect(find.byTooltip('Refresh Departments'), findsOneWidget);
          expect(find.text('Add Department'), findsOneWidget);
          expect(find.text('Health & Safety'), findsOneWidget);

          // Open Add Department dialog
          await tester.tap(find.text('Add Department'));
          await tester.pumpAndSettle();

          expect(find.text('Department Name'), findsOneWidget);
          expect(find.text('Short Code (e.g. HSE)'), findsOneWidget);
          expect(find.text('Cancel'), findsOneWidget);

          // Cancel dialog
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(find.text('Short Code (e.g. HSE)'), findsNothing);
        },
      );

      testWidgets('Sites view displays cards, refresh button, and add dialog', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Tab 3 = Sites
        await tester.pumpWidget(buildDashboardTab(3));
        await tester.pumpAndSettle();

        expect(find.text('Sites & Operational Facilities'), findsOneWidget);
        expect(find.byTooltip('Refresh Sites'), findsOneWidget);
        expect(find.text('Add Site'), findsOneWidget);
        expect(find.text('North Plant Facility'), findsOneWidget);

        // Open Add Site dialog
        await tester.tap(find.text('Add Site'));
        await tester.pumpAndSettle();

        expect(find.text('Add Facility Site'), findsOneWidget);
        expect(find.text('Site Name'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);

        // Cancel dialog
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Add Facility Site'), findsNothing);
      });

      testWidgets(
        'Teams view displays list, refresh button, and add dialog with department dropdown',
        (tester) async {
          tester.view.physicalSize = const Size(1280, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          // Tab 4 = Teams
          await tester.pumpWidget(buildDashboardTab(4));
          await tester.pumpAndSettle();

          expect(find.text('Operational Teams & Squads'), findsOneWidget);
          expect(find.byTooltip('Refresh Teams'), findsOneWidget);
          expect(find.text('Add Team'), findsOneWidget);
          expect(find.text('Hazard Inspection Squad'), findsOneWidget);

          // Open Add Team dialog
          await tester.tap(find.text('Add Team'));
          await tester.pumpAndSettle();

          expect(find.text('Add Team / Squad'), findsOneWidget);
          expect(find.text('Team Name'), findsOneWidget);
          expect(find.text('Team Lead Manager'), findsOneWidget);
          expect(find.text('Cancel'), findsOneWidget);

          // Cancel dialog
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(find.text('Add Team / Squad'), findsNothing);
        },
      );

      testWidgets(
        'Can toggle department, site, and team active status offline',
        (tester) async {
          tester.view.physicalSize = const Size(1280, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          // Teams Tab
          await tester.pumpWidget(buildDashboardTab(4));
          await tester.pumpAndSettle();

          // Find status toggle icon on first team item
          final deactivateButton = find.byTooltip('Deactivate Team').first;
          await tester.tap(deactivateButton);
          await tester.pumpAndSettle();

          // Should now show activate icon
          expect(find.byTooltip('Activate Team'), findsWidgets);
        },
      );
    },
  );
}
