import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/dashboard/platform_admin_dashboard/screens/platform_admin_dashboard_screen.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/models/platform_audit_log.dart';
import 'package:action_flow/services/organization_service.dart';
import 'package:action_flow/services/platform_audit_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    OrganizationService.instance.resetMockData();
    PlatformAuditService.instance.clearInMemoryLogs();
  });

  group('Delete Organization Service Tests', () {
    test('1. Rejects deleting Sobha by sobhaId', () async {
      final service = OrganizationService.instance;
      final result = await service.deleteOrganization(Organization.sobhaId);

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('Sobha'));
      expect(result.errorMessage, contains('cannot be deleted'));

      // Verify Sobha still exists in organizations
      final orgs = await service.fetchOrganizations();
      expect(orgs.any((o) => o.id == Organization.sobhaId), isTrue);
    });

    test('2. Rejects deleting non-existent organization', () async {
      final service = OrganizationService.instance;
      final result = await service.deleteOrganization('non-existent-id-999');

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('Organization not found'));
    });

    test('3. Rejects empty organization ID', () async {
      final service = OrganizationService.instance;
      final result = await service.deleteOrganization('   ');

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('Organization ID is required'));
    });

    test(
      '4. Successfully deletes non-anchor organization and its admins',
      () async {
        final service = OrganizationService.instance;

        // Create a test organization
        final createRes = await service.createOrganization(
          name: 'Test Tenant Corp',
          code: 'test-tenant',
          isActive: true,
        );
        expect(createRes.isSuccess, isTrue);
        final testOrg = createRes.organization!;

        // Invite an admin for this test org
        final inviteRes = await service.inviteCompanyAdmin(
          organization: testOrg,
          fullName: 'Test Admin',
          email: 'admin@testtenant.com',
        );
        expect(inviteRes.isSuccess, isTrue);

        // Verify organization and admin exist
        var orgs = await service.fetchOrganizations();
        expect(orgs.length, 2);
        var admins = await service.fetchCompanyAdmins(testOrg.id);
        expect(admins.length, 1);

        // Delete the test organization
        final deleteRes = await service.deleteOrganization(testOrg.id);
        expect(deleteRes.isSuccess, isTrue);
        expect(deleteRes.message, contains('Test Tenant Corp'));

        // Verify organization is gone
        orgs = await service.fetchOrganizations();
        expect(orgs.length, 1);
        expect(orgs.any((o) => o.id == testOrg.id), isFalse);

        // Verify associated admins are also purged
        admins = await service.fetchCompanyAdmins(testOrg.id);
        expect(admins.isEmpty, isTrue);

        // Verify Sobha is untouched
        expect(orgs.first.id, Organization.sobhaId);

        // Verify audit log preservation and snapshot integrity
        final auditLogs = await PlatformAuditService.instance.fetchAuditLogs(
          category: 'tenancy',
        );
        final deleteLog = auditLogs.firstWhere(
          (l) => l.eventType == 'organization_deleted',
        );

        // organization_id must be null (no dangling FK)
        expect(deleteLog.organizationId, isNull);
        // organization context is preserved
        expect(deleteLog.organizationName, 'Test Tenant Corp');
        expect(deleteLog.organizationCode, 'test-tenant');
        expect(deleteLog.isDeletedTenant, isTrue);
        expect(deleteLog.displayOrganization, 'Test Tenant Corp (Deleted)');

        // Can still find deleted tenant in Global Audit Logs search
        final searchResults = await PlatformAuditService.instance
            .fetchAuditLogs(searchQuery: 'Test Tenant Corp');
        expect(searchResults.isNotEmpty, isTrue);
        expect(
          searchResults.any((l) => l.displayOrganization.contains('(Deleted)')),
          isTrue,
        );
      },
    );

    test(
      '5. PlatformAuditLog model correctly handles deleted tenant display',
      () {
        // Normal active tenant
        final activeLog = PlatformAuditLog(
          id: 'log-1',
          createdAt: DateTime.now(),
          eventType: 'user_created',
          organizationId: 'org-uuid-123',
          organizationName: 'Active Corp',
          organizationCode: 'active-corp',
          description: 'User invited',
        );
        expect(activeLog.isDeletedTenant, isFalse);
        expect(activeLog.displayOrganization, 'Active Corp');

        // Deleted tenant (organizationId is null, organizationName snapshot preserved)
        final deletedLog = PlatformAuditLog(
          id: 'log-2',
          createdAt: DateTime.now(),
          eventType: 'organization_deleted',
          organizationId: null,
          organizationName: 'Deleted Corp',
          organizationCode: 'deleted-corp',
          description: 'Company deleted',
        );
        expect(deletedLog.isDeletedTenant, isTrue);
        expect(deletedLog.displayOrganization, 'Deleted Corp (Deleted)');

        // JSON deserialization with snapshot columns
        final jsonLog = PlatformAuditLog.fromJson({
          'id': 'log-3',
          'created_at': DateTime.now().toIso8601String(),
          'event_type': 'organization_deleted',
          'category': 'tenancy',
          'severity': 'warning',
          'organization_id': null,
          'organization_name': 'abc company',
          'organization_code': 'abc',
          'description': 'Organization "abc company" (abc) deleted',
          'metadata': {'is_deleted': true},
        });
        expect(jsonLog.organizationId, isNull);
        expect(jsonLog.organizationName, 'abc company');
        expect(jsonLog.organizationCode, 'abc');
        expect(jsonLog.isDeletedTenant, isTrue);
        expect(jsonLog.displayOrganization, 'abc company (Deleted)');
      },
    );
  });

  group('Delete Company UI & Dialog Tests', () {
    testWidgets(
      'Sobha company details dialog displays Anchor Notice and NO delete button',
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

        // Tap on Sobha row in the table to open details
        await tester.tap(find.text('Sobha').first);
        await tester.pumpAndSettle();

        // Should display Sobha anchor protection notice
        expect(
          find.textContaining(
            'Anchor Organization: Sobha (#1) is the permanent default tenant',
          ),
          findsOneWidget,
        );

        // Must NOT display Delete Company button
        expect(find.byKey(const Key('delete_company_button')), findsNothing);
      },
    );

    testWidgets(
      'Non-Sobha company details dialog displays Danger Zone and Delete Company button',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Seed a non-Sobha test organization
        final service = OrganizationService.instance;
        final res = await service.createOrganization(
          name: 'Beta Construction',
          code: 'beta-construction',
        );
        expect(res.isSuccess, isTrue);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const PlatformAdminDashboardScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Tap on Beta Construction row
        await tester.tap(find.text('Beta Construction').first);
        await tester.pumpAndSettle();

        // Should display Danger Zone
        expect(find.text('Danger Zone'), findsOneWidget);
        expect(find.byKey(const Key('delete_company_button')), findsOneWidget);
        expect(find.text('Anchor Organization: Sobha'), findsNothing);
      },
    );

    testWidgets(
      'Confirmation dialog requires exact company name to enable deletion',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final service = OrganizationService.instance;
        await service.createOrganization(
          name: 'Delta Energy',
          code: 'delta-energy',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const PlatformAdminDashboardScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Open details
        await tester.tap(find.text('Delta Energy').first);
        await tester.pumpAndSettle();

        // Click Delete Company
        await tester.tap(find.byKey(const Key('delete_company_button')));
        await tester.pumpAndSettle();

        // Confirmation dialog is open
        expect(find.text('Permanently Delete Company?'), findsOneWidget);
        expect(
          find.textContaining('To confirm, type "Delta Energy" below:'),
          findsOneWidget,
        );

        final confirmButton = find.byKey(
          const Key('confirm_delete_company_button'),
        );
        expect(confirmButton, findsOneWidget);

        // Initially disabled because field is empty
        final elevatedButtonBefore = tester.widget<ElevatedButton>(
          confirmButton,
        );
        expect(elevatedButtonBefore.onPressed, isNull);

        // Enter partial or incorrect name
        await tester.enterText(
          find.byKey(const Key('confirm_company_name_field')),
          'Delta',
        );
        await tester.pumpAndSettle();

        final elevatedButtonPartial = tester.widget<ElevatedButton>(
          confirmButton,
        );
        expect(elevatedButtonPartial.onPressed, isNull);

        // Enter exact name
        await tester.enterText(
          find.byKey(const Key('confirm_company_name_field')),
          'Delta Energy',
        );
        await tester.pumpAndSettle();

        final elevatedButtonExact = tester.widget<ElevatedButton>(
          confirmButton,
        );
        expect(elevatedButtonExact.onPressed, isNotNull);

        // Tap confirm delete
        await tester.tap(confirmButton);
        await tester.pumpAndSettle();

        // Dialog should be closed and success message shown
        expect(find.text('Permanently Delete Company?'), findsNothing);
        expect(
          find.text('Organization "Delta Energy" deleted successfully.'),
          findsOneWidget,
        );

        // Delta Energy should no longer be in the list
        expect(find.text('Delta Energy'), findsNothing);
      },
    );
  });
}
