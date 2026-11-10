import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/dashboard/platform_admin_dashboard/screens/platform_admin_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/platform_admin_dashboard/widgets/platform_owner_profile_dialog.dart';
import 'package:action_flow/features/profile/widgets/change_password_dialog.dart';
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

  group('Platform Owner Profile Button & Dialog Tests', () {
    testWidgets(
      '1. Dashboard AppBar renders platform_owner_profile_button with owner initials',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        final profileBtn = find.byKey(
          const ValueKey('platform_owner_profile_button'),
        );
        expect(profileBtn, findsOneWidget);
        expect(find.text('Profile'), findsOneWidget);
      },
    );

    testWidgets(
      '2. Tapping platform_owner_profile_button opens PlatformOwnerProfileDialog',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Tap the profile button in the AppBar
        final profileBtn = find.byKey(
          const ValueKey('platform_owner_profile_button'),
        );
        await tester.tap(profileBtn);
        await tester.pumpAndSettle();

        // Verify PlatformOwnerProfileDialog is displayed
        expect(find.byType(PlatformOwnerProfileDialog), findsOneWidget);
        expect(find.text('Platform Owner Profile'), findsOneWidget);
        expect(find.text('Tier 0 Global Platform Authority'), findsOneWidget);
        expect(find.text('Platform Authority & Scope'), findsOneWidget);
        expect(find.text('Platform Owner (Tier 0)'), findsWidgets);
        expect(find.text('Account Settings & Preferences'), findsOneWidget);
        expect(find.text('Change Password'), findsOneWidget);
        expect(find.text('Theme Preference'), findsOneWidget);
        expect(find.text('Sign Out of Platform'), findsOneWidget);
      },
    );

    testWidgets(
      '3. Tapping Change Password in dialog opens ChangePasswordDialog',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Open profile dialog
        await tester.tap(
          find.byKey(const ValueKey('platform_owner_profile_button')),
        );
        await tester.pumpAndSettle();

        // Tap Change Password tile
        await tester.tap(find.text('Change Password'));
        await tester.pumpAndSettle();

        // Verify ChangePasswordDialog is now open
        expect(find.byType(ChangePasswordDialog), findsOneWidget);
        expect(find.text('Update your credentials securely'), findsOneWidget);
        expect(find.text('Current Password *'), findsOneWidget);
      },
    );

    testWidgets(
      '4. PlatformOwnerProfileDialog standalone triggers onLogout callback',
      (tester) async {
        bool logoutCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: PlatformOwnerProfileDialog(
                ownerName: 'ActionFlow Owner',
                ownerEmail: 'arvin.pr1112@gmail.com',
                onLogout: () {
                  logoutCalled = true;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('ActionFlow Owner'), findsOneWidget);
        expect(find.text('arvin.pr1112@gmail.com'), findsOneWidget);

        // Tap Sign Out of Platform
        final signOutBtn = find.text('Sign Out of Platform');
        await tester.ensureVisible(signOutBtn);
        await tester.tap(signOutBtn);
        await tester.pumpAndSettle();

        expect(logoutCalled, isTrue);
      },
    );
  });
}
