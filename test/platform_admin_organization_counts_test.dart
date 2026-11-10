import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/dashboard/platform_admin_dashboard/screens/platform_admin_dashboard_screen.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/organization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    OrganizationService.instance.resetMockData();
  });

  group('OrganizationCounts Model Tests', () {
    test('Defaults to 0 for users, departments, sites', () {
      const counts = OrganizationCounts();
      expect(counts.users, 0);
      expect(counts.departments, 0);
      expect(counts.sites, 0);
    });

    test('Serializes to and deserializes from JSON correctly', () {
      final original = const OrganizationCounts(
        users: 25,
        departments: 4,
        sites: 8,
      );

      final json = original.toJson();
      expect(json, {'users': 25, 'departments': 4, 'sites': 8});

      final deserialized = OrganizationCounts.fromJson(json);
      expect(deserialized, equals(original));
      expect(deserialized.users, 25);
      expect(deserialized.departments, 4);
      expect(deserialized.sites, 8);
    });

    test('Supports copyWith and equality checks', () {
      const c1 = OrganizationCounts(users: 10, departments: 2, sites: 3);
      final c2 = c1.copyWith(users: 15);
      expect(c2.users, 15);
      expect(c2.departments, 2);
      expect(c2.sites, 3);
      expect(c1 == c2, isFalse);

      final c3 = c2.copyWith(users: 10);
      expect(c1 == c3, isTrue);
      expect(c1.hashCode, c3.hashCode);
      expect(c1.toString(), contains('users: 10'));
    });
  });

  group('OrganizationService Counts Retrieval Tests', () {
    test('Retrieves mock counts in test/offline mode', () async {
      OrganizationService.instance.setMockCounts(
        Organization.sobhaId,
        const OrganizationCounts(users: 50, departments: 12, sites: 20),
      );

      final allCounts = await OrganizationService.instance
          .fetchOrganizationCounts();
      expect(allCounts.containsKey(Organization.sobhaId), isTrue);
      expect(allCounts[Organization.sobhaId]?.users, 50);
      expect(allCounts[Organization.sobhaId]?.departments, 12);
      expect(allCounts[Organization.sobhaId]?.sites, 20);

      final singleCount = await OrganizationService.instance
          .fetchCountsForOrganization(Organization.sobhaId);
      expect(singleCount.users, 50);
      expect(singleCount.departments, 12);
      expect(singleCount.sites, 20);
    });

    test('resetMockData clears mock counts', () async {
      OrganizationService.instance.setMockCounts(
        Organization.sobhaId,
        const OrganizationCounts(users: 10, departments: 1, sites: 1),
      );
      OrganizationService.instance.resetMockData();

      final allCounts = await OrganizationService.instance
          .fetchOrganizationCounts();
      expect(allCounts.isEmpty, isTrue);
    });
  });

  group('Platform Admin Dashboard Companies Grid Real Counts Tests', () {
    Widget createTestWidget() {
      return MaterialApp(
        theme: AppTheme.lightTheme,
        home: const PlatformAdminDashboardScreen(),
      );
    }

    testWidgets(
      'Displays real Supabase counts for Users, Depts, and Sites in Grid cards',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Configure real counts for Sobha tenant
        OrganizationService.instance.setMockCounts(
          Organization.sobhaId,
          const OrganizationCounts(users: 42, departments: 7, sites: 15),
        );

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Switch from Table view to Grid view
        final gridToggle = find.byKey(
          const ValueKey('company_view_grid_toggle'),
        );
        expect(gridToggle, findsOneWidget);
        await tester.tap(gridToggle);
        await tester.pumpAndSettle();

        // Verify that the Grid Card for Sobha shows real counts
        final sobhaCard = find.byKey(const ValueKey(Organization.sobhaId));
        expect(sobhaCard, findsOneWidget);

        // Verify counts 42 (Users), 7 (Depts), 15 (Sites) exist inside the card
        expect(
          find.descendant(of: sobhaCard, matching: find.text('42')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: sobhaCard, matching: find.text('7')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: sobhaCard, matching: find.text('15')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: sobhaCard, matching: find.text('Users')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: sobhaCard, matching: find.text('Depts')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: sobhaCard, matching: find.text('Sites')),
          findsOneWidget,
        );
      },
    );
  });
}
