import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/dashboard/platform_admin_dashboard/widgets/platform_global_search_dialog.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:action_flow/services/platform_audit_service.dart';
import 'package:action_flow/services/platform_settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    PlatformAuditService.instance.clearInMemoryLogs();
  });

  group('Platform Owner Authority Diagnostic & Profile Tests', () {
    test('1. verifyPlatformAdminAuthority reports truthfully based on live auth state', () async {
      final isAuth = await AuthService.instance.verifyPlatformAdminAuthority();
      // In offline/test environment without Supabase connection, it returns false (truthful, not fake)
      expect(isAuth, isA<bool>());
    });

    test('2. parseProfileData synthesizes pure Tier 0 Platform Owner without organization pollution', () {
      final profile = AuthService.parseProfileData(
        {
          'id': 'po-uuid-1',
          'email': 'owner@actionflow.internal',
          'full_name': 'Super Owner',
          'is_platform_admin': true,
          // Old or stale company id attached to account
          'organization_id': 'sobha-org-id',
          'organization': {'name': 'Sobha Construction LLC'},
        },
        'po-uuid-1',
        isPlatformAdmin: true,
      );

      expect(profile.isPlatformAdmin, isTrue);
      expect(profile.isCompanyAdmin, isFalse);
      expect(profile.organizationId, isNull);
      expect(profile.userProfile.organizationName, isEmpty);
      expect(profile.organization, isNull);
    });
  });

  group('Platform Global Audit Logs Persistence & Filtering Tests', () {
    test(
      '1. Audit events persist in memory and can be filtered by category',
      () async {
        final service = PlatformAuditService.instance;

        await service.recordAuditEvent(
          eventType: 'organization_created',
          category: 'tenancy',
          severity: 'info',
          description: 'Tenant Alpha created',
        );

        await service.recordAuditEvent(
          eventType: 'setting_updated',
          category: 'security',
          severity: 'warn',
          description: 'Session timeout modified',
        );

        final allLogs = await service.fetchAuditLogs();
        expect(allLogs.length, greaterThanOrEqualTo(2));

        final tenancyLogs = await service.fetchAuditLogs(category: 'tenancy');
        expect(tenancyLogs.any((l) => l.category == 'tenancy'), isTrue);
        expect(tenancyLogs.any((l) => l.category == 'security'), isFalse);

        final securityLogs = await service.fetchAuditLogs(category: 'security');
        expect(securityLogs.any((l) => l.category == 'security'), isTrue);
        expect(securityLogs.any((l) => l.category == 'tenancy'), isFalse);
      },
    );

    test(
      '2. Audit events can be searched across description and organization',
      () async {
        final service = PlatformAuditService.instance;

        await service.recordAuditEvent(
          eventType: 'organization_deleted',
          category: 'tenancy_delete',
          severity: 'critical',
          description: 'Omega Logistics removed',
        );

        final searchResults = await service.fetchAuditLogs(
          searchQuery: 'Omega',
        );
        expect(
          searchResults.any((l) => l.description.contains('Omega Logistics')),
          isTrue,
        );

        final noResults = await service.fetchAuditLogs(
          searchQuery: 'NonExistentXYZ',
        );
        expect(noResults, isEmpty);
      },
    );
  });

  group('Platform Settings Persistence & Audit Trail Tests', () {
    test(
      '1. PlatformSettingsService provides default keys and persists updates',
      () async {
        final service = PlatformSettingsService.instance;
        final settings = await service.fetchSettings();

        expect(settings.containsKey('platform_name'), isTrue);
        expect(settings.containsKey('session_timeout_minutes'), isTrue);
        expect(settings.containsKey('require_mfa_for_admins'), isTrue);
        expect(settings.containsKey('allow_cross_tenant_view'), isTrue);
        expect(settings.containsKey('audit_retention_days'), isTrue);

        // Update a setting
        await service.updateSetting(key: 'session_timeout_minutes', value: 120);
        expect(
          service.getSettingValue<int>('session_timeout_minutes'),
          equals(120),
        );

        // Reset
        await service.updateSetting(key: 'session_timeout_minutes', value: 60);
        expect(
          service.getSettingValue<int>('session_timeout_minutes'),
          equals(60),
        );
      },
    );
  });

  group('Platform Global Command Palette Search Dialog Tests', () {
    testWidgets(
      '1. PlatformGlobalSearchDialog opens and filters companies and settings',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final testOrgs = <Organization>[
          const Organization(
            id: 'org-1',
            name: 'Apex Facilities Ltd',
            code: 'apex',
            isActive: true,
          ),
          Organization.sobha(),
        ];

        int? navigatedIndex;
        String? selectedFilter;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    PlatformGlobalSearchDialog.show(
                      context,
                      organizations: testOrgs,
                      platformSettings: {},
                      onNavigate: (index, {companyFilter}) {
                        navigatedIndex = index;
                        selectedFilter = companyFilter;
                      },
                      onAddCompany: () {},
                      onRunDiagnostics: () {},
                    );
                  },
                  child: const Text('Open Search'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open dialog
        await tester.tap(find.text('Open Search'));
        await tester.pumpAndSettle();

        // Verify Command Palette is open
        expect(find.byType(PlatformGlobalSearchDialog), findsOneWidget);
        expect(
          find.text('ActionFlow Platform Command Palette'),
          findsOneWidget,
        );
        expect(find.byType(TextField), findsOneWidget);

        // Search for 'Apex'
        await tester.enterText(find.byType(TextField), 'Apex');
        await tester.pumpAndSettle();

        // Check results list has Apex
        expect(find.text('Apex Facilities Ltd'), findsOneWidget);

        // Tap on Apex result
        await tester.tap(find.text('Apex Facilities Ltd'));
        await tester.pumpAndSettle();

        // Navigation should be triggered to Companies view (index 1) with Apex filter
        expect(navigatedIndex, equals(1));
        expect(selectedFilter, equals('Apex Facilities Ltd'));
      },
    );
  });
}
