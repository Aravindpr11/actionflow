import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/dashboard/platform_admin_dashboard/screens/platform_admin_dashboard_screen.dart';
import 'package:action_flow/services/organization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    OrganizationService.instance.resetMockData();
  });

  Widget createTestWidget() {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: const PlatformAdminDashboardScreen(),
    );
  }

  group('Platform Owner Navigation & View Switching Tests', () {
    testWidgets(
      '1. Default view (index 0) renders Platform Overview with all sections',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Overview items
        expect(find.text('Welcome, ActionFlow Owner'), findsOneWidget);
        expect(find.text('Platform Administrator Identity'), findsOneWidget);
        expect(
          find.text('Companies & Multi-Tenant Management'),
          findsOneWidget,
        );
        expect(find.text('Registered Organizations'), findsOneWidget);
        expect(find.text('Sobha (Organization #1)'), findsOneWidget);
      },
    );

    testWidgets('2. Sidebar switches to Companies & Tenants view (index 1)', (
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

      // Tap 'Companies & Tenants' in sidebar
      await tester.tap(find.byKey(const ValueKey('platform_nav_item_1')));
      await tester.pumpAndSettle();

      // Overview hero banner should be gone
      expect(find.text('Welcome, ActionFlow Owner'), findsNothing);
      // Completed companies section should be present
      expect(find.text('Companies & Multi-Tenant Management'), findsOneWidget);
      expect(find.text('1 Company Registered (Sobha)'), findsOneWidget);
      expect(find.byType(DataTable), findsOneWidget);
    });

    testWidgets(
      '3. Sidebar switches to Platform Security view (index 2) with verified controls',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Tap 'Platform Security' in sidebar
        await tester.tap(find.byKey(const ValueKey('platform_nav_item_2')));
        await tester.pumpAndSettle();

        // Verify Security View Banner
        expect(find.text('Platform Security & Governance'), findsOneWidget);
        expect(
          find.text(
            'Real-time security posture, authority checks, and multi-tenant isolation status',
          ),
          findsOneWidget,
        );

        // Verify 5 required security statuses based strictly on real implementation
        expect(find.text('Platform Authorization'), findsOneWidget);
        expect(find.text('Tier 0 Active'), findsOneWidget);
        expect(find.text('is_platform_admin() = true'), findsOneWidget);

        expect(find.text('Tenant Isolation'), findsOneWidget);
        expect(find.text('Row-Level Security Active'), findsOneWidget);

        expect(find.text('Anchor Protection'), findsOneWidget);
        expect(find.text('Protected'), findsWidgets);
        expect(find.text('Sobha Deletion Guard Active'), findsOneWidget);

        // Verify clearly marked unmeasurable states
        expect(find.text('Automated Scanning'), findsOneWidget);
        expect(find.text('Not available'), findsWidgets);

        // Verify detailed security controls
        expect(find.text('Platform Authorization Gate'), findsOneWidget);
        expect(find.text('Multi-Tenant Data Isolation (RLS)'), findsOneWidget);
        expect(find.text('Authentication & Session Integrity'), findsOneWidget);
        expect(find.text('Company Admin Governance'), findsOneWidget);
        expect(find.text('Anchor Tenant Deletion Guard'), findsOneWidget);
        expect(find.text('5 Controls Enforced'), findsOneWidget);
      },
    );

    testWidgets(
      '4. Sidebar switches to Global Audit Logs view (index 3) with empty state',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Tap 'Global Audit Logs' in sidebar
        await tester.tap(find.byKey(const ValueKey('platform_nav_item_3')));
        await tester.pumpAndSettle();

        // Verify Audit Logs Banner
        expect(find.text('Global Platform Audit Logs'), findsOneWidget);

        // Verify Honest Empty State
        expect(
          find.text('Audit Logging Service Pending Integration'),
          findsOneWidget,
        );
        expect(find.text('Audit Backend Pending'), findsOneWidget);
        expect(
          find.textContaining(
            'Detailed platform audit events (organization creation, admin invitations, deletion requests, and security policy modifications) will automatically appear here once the audit-log backend is implemented.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'No fake records are generated. All operations remain isolated under database RLS.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '5. Sidebar switches to Platform Settings view (index 4) with backend integration badges',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Tap 'Platform Settings' in sidebar
        await tester.tap(find.byKey(const ValueKey('platform_nav_item_4')));
        await tester.pumpAndSettle();

        // Verify Settings Banner
        expect(find.text('Platform Settings & Configuration'), findsOneWidget);

        // Verify Sections
        expect(find.text('Platform Configuration'), findsOneWidget);
        expect(find.text('Email & Notification Configuration'), findsOneWidget);
        expect(find.text('Security Configuration'), findsOneWidget);
        expect(find.text('System Defaults'), findsOneWidget);

        // Real active parameters
        expect(find.text('ActionFlow HSE Multi-Tenant Portal'), findsOneWidget);
        expect(find.text('Mumbai (ap-south-1) Supabase'), findsOneWidget);
        expect(
          find.text('Strict Partitioned Row-Level Security'),
          findsOneWidget,
        );

        // Backend dependent placeholders clearly marked
        expect(find.text('Coming with backend integration'), findsWidgets);
      },
    );

    testWidgets(
      '6. Mobile bottom navigation switches between all 5 views without overflow',
      (tester) async {
        // Mobile viewport
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Verify bottom nav is present with 5 items
        final bottomNav = find.byType(BottomNavigationBar);
        expect(bottomNav, findsOneWidget);

        // Tap 'Security'
        await tester.tap(find.text('Security'));
        await tester.pumpAndSettle();
        expect(find.text('Platform Security & Governance'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Tap 'Audit'
        await tester.tap(find.text('Audit'));
        await tester.pumpAndSettle();
        expect(find.text('Global Platform Audit Logs'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Tap 'Settings'
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        expect(find.text('Platform Settings & Configuration'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Tap 'Companies'
        await tester.tap(find.text('Companies'));
        await tester.pumpAndSettle();
        expect(
          find.text('Companies & Multi-Tenant Management'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        // Tap 'Overview'
        await tester.tap(find.text('Overview'));
        await tester.pumpAndSettle();
        expect(find.text('Welcome, ActionFlow Owner'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
