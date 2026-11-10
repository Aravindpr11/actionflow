import 'package:action_flow/features/dashboard/admin_dashboard/screens/admin_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Company Admin Identity & Session Restoration Tests', () {
    const sobhaAdminProfile = UserProfile(
      id: 'a7f0b85c-aed5-439e-8dac-083b3f0e7d15',
      name: 'Sobha Admin',
      email: 'aravind11.sobha@gmail.com',
      phone: '+971 50 123 4567',
      designation: 'Infra Head',
      department: 'Infrastructure',
      division: 'Engineering & Construction',
      site: 'Sobha Hartland',
      team: 'Civil & Infra',
      role: 'System Administrator',
      accountStatus: 'Active',
      permissions: [
        'Full System Configuration Access',
        'User, Department & Site Governance',
      ],
      organizationId: Organization.sobhaId,
      organizationName: Organization.sobhaName,
    );

    const sobhaAdminAuthData = AuthProfileData(
      userProfile: sobhaAdminProfile,
      roleCode: 'admin',
      status: 'active',
      isActive: true,
      isPrimaryAdmin: true,
      organizationId: Organization.sobhaId,
    );

    tearDown(() {
      AuthService.instance.setProfileDataForTesting(null);
    });

    testWidgets(
      'AdminDashboardScreen uses injected adminProfile from fresh login',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: AdminDashboardScreen(adminProfile: sobhaAdminProfile),
          ),
        );
        await tester.pump();

        expect(find.text('Sobha Admin'), findsOneWidget);
        expect(find.text('Infra Head'), findsOneWidget);
        expect(find.text('System Administrator'), findsNothing);
        expect(find.text('Enterprise System Administrator'), findsNothing);
      },
    );

    testWidgets(
      'AdminDashboardScreen restores identity from AuthService.currentProfileData on browser reload',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Simulate restored session in AuthService
        AuthService.instance.setCurrentProfileData(sobhaAdminAuthData);

        // Render AdminDashboardScreen without explicit constructor parameter (as in reload/deep link)
        await tester.pumpWidget(
          const MaterialApp(home: AdminDashboardScreen()),
        );
        await tester.pump();

        expect(find.text('Sobha Admin'), findsOneWidget);
        expect(find.text('Infra Head'), findsOneWidget);
        expect(find.text('System Administrator'), findsNothing);
        expect(find.text('Enterprise System Administrator'), findsNothing);
      },
    );

    test('AuthService.setCurrentProfileData updates currentProfile and currentProfileData', () {
      AuthService.instance.setCurrentProfileData(sobhaAdminAuthData);

      expect(
        AuthService.instance.currentProfileData?.userProfile.name,
        'Sobha Admin',
      );
      expect(AuthService.instance.currentProfile?.designation, 'Infra Head');
      expect(AuthService.instance.isCompanyAdmin, isTrue);
      expect(AuthService.instance.isPlatformAdmin, isFalse);
    });
  });
}
