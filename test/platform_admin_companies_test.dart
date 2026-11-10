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

  group('OrganizationService Unit Tests', () {
    test('1. Initial fetch returns default Sobha organization', () async {
      final service = OrganizationService.instance;
      final orgs = await service.fetchOrganizations();

      expect(orgs.length, 1);
      expect(orgs.first.id, Organization.sobhaId);
      expect(orgs.first.name, Organization.sobhaName);
      expect(orgs.first.code, Organization.sobhaCode);
      expect(orgs.first.isActive, isTrue);
    });

    test('2. Name validation enforces required and max length', () async {
      final service = OrganizationService.instance;

      // Empty name
      final resEmpty = await service.createOrganization(
        name: '   ',
        code: 'valid-code',
      );
      expect(resEmpty.isSuccess, isFalse);
      expect(resEmpty.errorMessage, contains('Company name cannot be empty'));

      // Too long name (> 150 chars)
      final resLong = await service.createOrganization(
        name: 'A' * 151,
        code: 'valid-code',
      );
      expect(resLong.isSuccess, isFalse);
      expect(resLong.errorMessage, contains('cannot exceed 150 characters'));
    });

    test(
      '3. Code validation enforces required, slug format, and max length',
      () async {
        final service = OrganizationService.instance;

        // Empty code
        final resEmpty = await service.createOrganization(
          name: 'Acme Corp',
          code: '   ',
        );
        expect(resEmpty.isSuccess, isFalse);
        expect(resEmpty.errorMessage, contains('Company code cannot be empty'));

        // Too long code (> 50 chars)
        final resLong = await service.createOrganization(
          name: 'Acme Corp',
          code: 'a' * 51,
        );
        expect(resLong.isSuccess, isFalse);
        expect(resLong.errorMessage, contains('cannot exceed 50 characters'));

        // Invalid characters (spaces, symbols)
        final resSpecial = await service.createOrganization(
          name: 'Acme Corp',
          code: 'acme corp!',
        );
        expect(resSpecial.isSuccess, isFalse);
        expect(
          resSpecial.errorMessage,
          contains(
            'only contain lowercase letters, numbers, hyphens, and underscores',
          ),
        );
      },
    );

    test(
      '4. Duplicate code and duplicate name are prevented with clear error',
      () async {
        final service = OrganizationService.instance;

        // Duplicate code 'sobha'
        final resDupCode = await service.createOrganization(
          name: 'Another Sobha Branch',
          code: 'sobha',
        );
        expect(resDupCode.isSuccess, isFalse);
        expect(resDupCode.errorMessage, contains('already exists'));

        // Duplicate name 'Sobha'
        final resDupName = await service.createOrganization(
          name: 'Sobha',
          code: 'sobha-two',
        );
        expect(resDupName.isSuccess, isFalse);
        expect(resDupName.errorMessage, contains('already exists'));
      },
    );

    test('5. Successfully creates new organization and updates list', () async {
      final service = OrganizationService.instance;

      final res = await service.createOrganization(
        name: 'Apex Infrastructure',
        code: 'apex-infra',
        isActive: true,
      );

      expect(res.isSuccess, isTrue);
      expect(res.organization, isNotNull);
      expect(res.organization!.name, 'Apex Infrastructure');
      expect(res.organization!.code, 'apex-infra');
      expect(res.organization!.isActive, isTrue);

      final orgs = await service.fetchOrganizations();
      expect(orgs.length, 2);
      expect(orgs.any((o) => o.code == 'apex-infra'), isTrue);
    });
  });

  group('Platform Admin Companies UI & Modal Tests', () {
    testWidgets(
      'Displays real organization table with Sobha and Add Company button',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const PlatformAdminDashboardScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Verify table section header and button
        expect(
          find.text('Companies & Multi-Tenant Management'),
          findsOneWidget,
        );
        expect(find.text('1 Company Registered (Sobha)'), findsOneWidget);
        expect(find.text('Add Company'), findsOneWidget);

        // Verify table columns
        expect(find.text('Company / Tenant'), findsOneWidget);
        expect(find.text('Code / Slug'), findsOneWidget);
        expect(find.text('Status'), findsOneWidget);
        expect(find.text('Organization ID'), findsOneWidget);
        expect(find.text('Created Date'), findsOneWidget);

        // Verify Sobha row
        expect(find.text('Sobha'), findsWidgets);
        expect(find.text('sobha'), findsOneWidget);
        expect(find.text('Active'), findsWidgets);
      },
    );

    testWidgets('Opens Add Company dialog and validates required fields', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const PlatformAdminDashboardScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap 'Add Company'
      await tester.tap(find.text('Add Company'));
      await tester.pumpAndSettle();

      // Dialog should be open
      expect(find.text('Add New Organization'), findsOneWidget);
      expect(find.text('Company Name *'), findsOneWidget);
      expect(find.text('Company Code / Slug *'), findsOneWidget);

      // Tap 'Create Company' with empty fields
      await tester.tap(find.text('Create Company'));
      await tester.pumpAndSettle();

      // Form validators should show errors
      expect(find.text('Company name is required'), findsOneWidget);
      expect(find.text('Company code is required'), findsOneWidget);

      // Tap Cancel to dismiss
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Add New Organization'), findsNothing);
    });

    testWidgets(
      'Successfully creates a new company via dialog and updates UI',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const PlatformAdminDashboardScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Initial count is 1
        expect(find.text('1 Company Registered (Sobha)'), findsOneWidget);

        // Open dialog
        await tester.tap(find.text('Add Company'));
        await tester.pumpAndSettle();

        // Enter company name
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Company Name *'),
          'Zenith Tech',
        );
        await tester.pumpAndSettle();

        // Auto-slug generates 'zenith-tech'
        expect(find.text('zenith-tech'), findsOneWidget);

        // Submit form
        await tester.tap(find.text('Create Company'));
        await tester.pumpAndSettle();

        // Dialog closes and success snackbar appears
        expect(find.text('Add New Organization'), findsNothing);
        expect(find.text('Organization created successfully.'), findsOneWidget);

        // Count badge updates to 2
        expect(find.text('2 Companies Registered'), findsOneWidget);

        // New company shows in table
        expect(find.text('Zenith Tech'), findsOneWidget);
        expect(find.text('zenith-tech'), findsOneWidget);

        // Registered Organizations metric card updates to 2
        expect(find.text('2'), findsWidgets);
      },
    );

    testWidgets(
      'Renders responsively without layout overflow on tablet and mobile viewports',
      (tester) async {
        // Tablet (768 x 1024)
        tester.view.physicalSize = const Size(768, 1024);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const PlatformAdminDashboardScreen(),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Mobile (375 x 812)
        tester.view.physicalSize = const Size(375, 812);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const PlatformAdminDashboardScreen(),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      },
    );
  });
}
