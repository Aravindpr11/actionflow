import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/auth/models/auth_models.dart';
import 'package:action_flow/features/auth/screens/account_status_screen.dart';
import 'package:action_flow/features/dashboard/admin_dashboard/screens/admin_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/platform_admin_dashboard/screens/platform_admin_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Platform Admin Authentication & Identity Tests', () {
    test('1. AuthProfileData.platformAdmin synthesizes correct platform admin identity', () {
      final profileData = AuthProfileData.platformAdmin(
        authUserId: 'ed507b8e-bcd3-403c-80e4-42151b6681fa',
        email: 'arvin.pr1112@gmail.com',
        fullName: 'ActionFlow Owner',
      );

      expect(profileData.isPlatformAdmin, isTrue);
      expect(profileData.isCompanyAdmin, isFalse);
      expect(profileData.organizationId, isNull);
      expect(profileData.organization, isNull);
      expect(profileData.status, 'active');
      expect(profileData.isActive, isTrue);
      expect(profileData.roleCode, 'admin');
      expect(profileData.isPrimaryAdmin, isFalse);

      final userProfile = profileData.userProfile;
      expect(userProfile.id, 'ed507b8e-bcd3-403c-80e4-42151b6681fa');
      expect(userProfile.name, 'ActionFlow Owner');
      expect(userProfile.email, 'arvin.pr1112@gmail.com');
      expect(userProfile.organizationId, isNull);
      expect(userProfile.role, 'Platform Administrator');
      expect(userProfile.department, 'Platform Administration');
      expect(userProfile.site, 'Global');
      expect(
        userProfile.permissions,
        contains('Global Platform Administration'),
      );
    });

    test('2. Platform Admin does NOT require public.profiles row (synthetic resolution)', () {
      // Platform owner has no record in profiles table
      final profileData = AuthProfileData.platformAdmin(
        authUserId: 'ed507b8e-bcd3-403c-80e4-42151b6681fa',
        email: 'arvin.pr1112@gmail.com',
      );

      expect(
        profileData.userProfile.id,
        'ed507b8e-bcd3-403c-80e4-42151b6681fa',
      );
      expect(profileData.userProfile.name, 'arvin.pr1112');
      expect(profileData.organizationId, isNull);
      expect(profileData.organization, isNull);
    });

    test(
      '3. Platform Admin organizationId is null and not bound to any tenant',
      () {
        final profileData = AuthService.parseProfileData(
          {
            'id': 'ed507b8e-bcd3-403c-80e4-42151b6681fa',
            'full_name': 'ActionFlow Platform Owner',
            'email': 'owner@actionflow.io',
            'status': 'active',
            'is_active': true,
            'is_platform_admin': true,
            'organization_id': null,
          },
          'ed507b8e-bcd3-403c-80e4-42151b6681fa',
          isPlatformAdmin: true,
        );

        expect(profileData.organizationId, isNull);
        expect(profileData.organization, isNull);
        expect(profileData.userProfile.organizationId, isNull);
      },
    );

    test(
      '4. Platform Admin isCompanyAdmin is false and isPlatformAdmin is true',
      () {
        final profileData = AuthProfileData.platformAdmin(
          authUserId: 'plat-admin-uuid',
          email: 'admin@platform.io',
        );

        expect(profileData.isPlatformAdmin, isTrue);
        expect(profileData.isCompanyAdmin, isFalse);
      },
    );

    test('5. Existing Sobha Admin isCompanyAdmin is true and isPlatformAdmin is false', () {
      final sobhaAdminData = AuthService.parseProfileData(
        {
          'id': 'usr-sobha-admin-1',
          'full_name': 'Sobha Admin User',
          'email': 'admin@sobha.internal',
          'is_primary_admin': true,
          'status': 'active',
          'is_active': true,
          'organization_id': Organization.sobhaId,
          'roles': {'code': 'admin', 'name': 'System Administrator'},
          'departments': {'name': 'Operations', 'division': 'HSSE'},
          'sites': {'name': 'Sobha Hartland'},
          'organizations': {
            'id': Organization.sobhaId,
            'name': Organization.sobhaName,
            'code': Organization.sobhaCode,
            'is_active': true,
          },
        },
        'usr-sobha-admin-1',
        isPlatformAdmin: false,
      );

      expect(sobhaAdminData.isPlatformAdmin, isFalse);
      expect(sobhaAdminData.isCompanyAdmin, isTrue);
      expect(sobhaAdminData.organizationId, Organization.sobhaId);
      expect(sobhaAdminData.organization?.name, Organization.sobhaName);
    });
  });

  group('Authentication Routing Decision Tests', () {
    Widget resolveDestinationScreen(AuthProfileData profileData) {
      final status = profileData.status.toLowerCase();
      final isActive = profileData.isActive;
      final role = profileData.roleCode.toLowerCase();
      final isPrimaryAdmin = profileData.isPrimaryAdmin;

      if (status == 'active' && isActive) {
        if (profileData.isPlatformAdmin) {
          return const PlatformAdminDashboardScreen();
        } else if (role == 'admin' || isPrimaryAdmin) {
          return const AdminDashboardScreen();
        } else if (role == 'manager') {
          return ManagerDashboardScreen(userProfile: profileData.userProfile);
        } else {
          return WorkerDashboardScreen(userProfile: profileData.userProfile);
        }
      } else if (status == 'pending_approval') {
        return AccountStatusScreen(
          status: AuthAccountStatus.pendingApproval,
          userEmail: profileData.userProfile.email,
          userName: profileData.userProfile.name,
          requestedType: role == 'manager'
              ? RequestedAccountType.manager
              : RequestedAccountType.staff,
        );
      } else {
        return AccountStatusScreen(
          status: AuthAccountStatus.inactive,
          userEmail: profileData.userProfile.email,
          userName: profileData.userProfile.name,
          requestedType: role == 'manager'
              ? RequestedAccountType.manager
              : RequestedAccountType.staff,
        );
      }
    }

    test('6. Platform Admin routes to PlatformAdminDashboardScreen', () {
      final platformAdmin = AuthProfileData.platformAdmin(
        authUserId: 'ed507b8e-bcd3-403c-80e4-42151b6681fa',
        email: 'arvin.pr1112@gmail.com',
      );

      final screen = resolveDestinationScreen(platformAdmin);
      expect(screen, isA<PlatformAdminDashboardScreen>());
    });

    test('7. Company Admin routes to AdminDashboardScreen', () {
      final companyAdmin = AuthProfileData(
        userProfile: UserProfile.mockAdmin(),
        roleCode: 'admin',
        status: 'active',
        isActive: true,
        isPrimaryAdmin: true,
        isPlatformAdmin: false,
        organizationId: Organization.sobhaId,
        organization: Organization.sobha(),
      );

      final screen = resolveDestinationScreen(companyAdmin);
      expect(screen, isA<AdminDashboardScreen>());
    });

    test('8. Manager routes to ManagerDashboardScreen', () {
      final manager = AuthProfileData(
        userProfile: UserProfile.mockManager(),
        roleCode: 'manager',
        status: 'active',
        isActive: true,
        isPrimaryAdmin: false,
        isPlatformAdmin: false,
        organizationId: Organization.sobhaId,
        organization: Organization.sobha(),
      );

      final screen = resolveDestinationScreen(manager);
      expect(screen, isA<ManagerDashboardScreen>());
    });

    test('9. Staff routes to WorkerDashboardScreen', () {
      final staff = AuthProfileData(
        userProfile: UserProfile.mockStaff(),
        roleCode: 'staff',
        status: 'active',
        isActive: true,
        isPrimaryAdmin: false,
        isPlatformAdmin: false,
        organizationId: Organization.sobhaId,
        organization: Organization.sobha(),
      );

      final screen = resolveDestinationScreen(staff);
      expect(screen, isA<WorkerDashboardScreen>());
    });

    test('10. Pending approval routes to AccountStatusScreen', () {
      final pendingUser = AuthProfileData(
        userProfile: UserProfile.mockStaff().copyWith(
          accountStatus: 'Pending Approval',
        ),
        roleCode: 'staff',
        status: 'pending_approval',
        isActive: false,
        isPrimaryAdmin: false,
        isPlatformAdmin: false,
        organizationId: Organization.sobhaId,
      );

      final screen = resolveDestinationScreen(pendingUser);
      expect(screen, isA<AccountStatusScreen>());
    });
  });

  group('PlatformAdminDashboardScreen Widget UI Tests', () {
    testWidgets(
      'PlatformAdminDashboardScreen renders header, identity, metrics and organizations',
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
            home: const PlatformAdminDashboardScreen(
              overrideEmail: 'arvin.pr1112@gmail.com',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify header branding
        expect(find.text('Platform Administration'), findsWidgets);
        expect(find.text('ActionFlow'), findsWidgets);

        // Verify Owner Hero & Identity details
        expect(find.text('Welcome, ActionFlow Owner'), findsOneWidget);
        expect(find.text('Platform Administrator Identity'), findsOneWidget);
        expect(find.text('arvin.pr1112@gmail.com'), findsOneWidget);
        expect(find.text('Cross-Tenant (Global)'), findsOneWidget);
        expect(find.text('is_platform_admin() = true'), findsOneWidget);

        // Verify Multi-Tenant Management Section
        expect(
          find.text('Companies & Multi-Tenant Management'),
          findsOneWidget,
        );
        expect(find.text('1 Company Registered (Sobha)'), findsOneWidget);

        // Verify Capabilities / Metrics cards
        expect(find.text('Registered Organizations'), findsOneWidget);
        expect(find.text('Sobha (Organization #1)'), findsOneWidget);
        expect(find.text('Tenant Isolation'), findsOneWidget);
        expect(find.text('Row Level Security Active'), findsOneWidget);
        expect(find.text('Platform Authority'), findsOneWidget);

        // Verify Logout icon button exists with tooltip
        expect(find.byTooltip('Logout'), findsOneWidget);
      },
    );

    testWidgets(
      'PlatformAdminDashboardScreen renders responsively on compact screen',
      (tester) async {
        tester.view.physicalSize = const Size(600, 800);
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

        expect(find.text('Platform Administration'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
