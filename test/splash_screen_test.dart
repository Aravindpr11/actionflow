import 'dart:io';

import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/features/auth/screens/create_password_screen.dart';
import 'package:action_flow/features/auth/screens/login_screen.dart';
import 'package:action_flow/features/dashboard/admin_dashboard/screens/admin_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/splash/screens/splash_screen.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:action_flow/widgets/common/action_flow_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('ActionFlow SplashScreen & Logo Branding Tests', () {
    testWidgets(
      'SplashScreen renders logo symbol, title, tagline and progress indicator on desktop',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: SplashScreen(duration: Duration(seconds: 10)),
          ),
        );
        await tester.pump();

        expect(find.byType(ActionFlowSymbol), findsOneWidget);
        expect(find.text('ActionFlow'), findsOneWidget);
        expect(
          find.text('Streamline Actions • Track Progress'),
          findsOneWidget,
        );
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
      },
    );

    testWidgets('SplashScreen renders without overflow on 400px mobile width', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(home: SplashScreen(duration: Duration(seconds: 10))),
      );
      await tester.pump();

      expect(find.byType(ActionFlowSymbol), findsOneWidget);
      expect(find.text('ActionFlow'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'SplashScreen renders without overflow on 320px ultra-compact width',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: SplashScreen(duration: Duration(seconds: 10)),
          ),
        );
        await tester.pump();

        expect(find.byType(ActionFlowSymbol), findsOneWidget);
        expect(find.text('ActionFlow'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'SplashScreen smoothly transitions to LoginScreen after duration elapses',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: SplashScreen(duration: Duration(milliseconds: 300)),
          ),
        );
        await tester.pump();

        // Initial state: SplashScreen is rendered
        expect(find.byType(SplashScreen), findsOneWidget);
        expect(find.byType(LoginScreen), findsNothing);

        // Advance past duration and wait for transition
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        // Transitioned state: LoginScreen is now rendered
        expect(find.byType(SplashScreen), findsNothing);
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(find.text('Welcome back'), findsOneWidget);
        expect(find.text('Sign In'), findsOneWidget);
      },
    );

    testWidgets(
      'ActionFlowLogo renders with expected proportions and icon mark across variants',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  ActionFlowLogo.primary(size: 40),
                  ActionFlowLogo.white(size: 76),
                  ActionFlowLogo.light(size: 32),
                  const ActionFlowBrand(logoSize: 38, fontSize: 18),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ActionFlowLogo), findsNWidgets(4));
        expect(find.byType(ActionFlowSymbol), findsNWidgets(4));
        expect(find.text('ActionFlow'), findsOneWidget);
      },
    );

    testWidgets(
      'ActionFlowSymbol renders stylized A + arrow symbol across variants',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  ActionFlowSymbol.white(size: 96),
                  ActionFlowSymbol.primary(size: 48),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ActionFlowSymbol), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('SplashScreen Auth Flow Routing & Interception Tests', () {
    tearDown(() {
      SupabaseConfig.isInitializedForTesting = null;
      AuthService.clearCapturedInitialAuthFlow();
      AuthService.clearPasswordRecoveryState();
      AuthService.clearCapturedAuthLinkError();
      AuthService.instance.setSessionForTesting(null);
      AuthService.instance.setProfileDataForTesting(null);
    });

    test('1. initial invite flag captured before Supabase URL scrubbing', () {
      final uri = Uri.parse(
        'http://localhost:8080/#access_token=token123&refresh_token=ref123&expires_in=3600&token_type=bearer&type=invite',
      );
      AuthService.captureInitialAuthFlow(uri);

      expect(AuthService.capturedInitialAuthFlow, InitialAuthFlow.invite);
      expect(AuthService.isIncomingInviteFlow, isTrue);
      expect(AuthService.isIncomingRecoveryFlow, isFalse);
    });

    test('2. initial recovery flag captured before URL scrubbing', () {
      final uri = Uri.parse(
        'http://localhost:8080/#access_token=token123&refresh_token=ref123&type=recovery',
      );
      AuthService.captureInitialAuthFlow(uri);

      expect(AuthService.capturedInitialAuthFlow, InitialAuthFlow.recovery);
      expect(AuthService.isIncomingRecoveryFlow, isTrue);
      expect(AuthService.isIncomingInviteFlow, isFalse);
    });

    test('3. captured flag is consumed and does not retrigger', () {
      AuthService.captureInitialAuthFlow(
        Uri.parse('http://localhost:8080/#type=invite'),
      );
      expect(AuthService.isIncomingInviteFlow, isTrue);

      AuthService.clearCapturedInitialAuthFlow();
      expect(AuthService.capturedInitialAuthFlow, InitialAuthFlow.none);
      expect(AuthService.isIncomingInviteFlow, isFalse);
      expect(AuthService.isIncomingRecoveryFlow, isFalse);
    });

    test('4. invitation redirect configuration uses localhost:8080', () {
      final edgeFunctionFile = File(
        'supabase/functions/invite-company-admin/index.ts',
      );
      expect(edgeFunctionFile.existsSync(), isTrue);
      final content = edgeFunctionFile.readAsStringSync();

      expect(
        content.contains('redirectTo: "http://localhost:8080"'),
        isTrue,
        reason: 'inviteUserByEmail must explicitly specify redirectTo: http://localhost:8080',
      );
    });

    testWidgets('5. invite routes to CreatePasswordScreen and consumes flag', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SupabaseConfig.isInitializedForTesting = true;
      const fakeUser = User(
        id: 'invite-user-id',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-09-17T00:00:00.000Z',
        email: 'invited.admin@company.com',
      );
      final fakeSession = Session(
        accessToken: 'token123',
        expiresIn: 3600,
        refreshToken: 'ref123',
        tokenType: 'bearer',
        user: fakeUser,
      );
      AuthService.instance.setSessionForTesting(fakeSession);
      AuthService.instance.setProfileDataForTesting(
        AuthProfileData(
          userProfile: UserProfile(
            id: 'invite-user-id',
            name: 'Invited Admin',
            email: 'invited.admin@company.com',
            phone: '',
            designation: 'Company Administrator',
            department: 'Corporate Headquarters',
            division: 'Executive Leadership',
            site: 'HQ',
            team: '',
            role: 'System Administrator',
            accountStatus: 'Active',
            permissions: const [],
            organizationId: 'org-test-123',
            organizationName: 'Test Company',
          ),
          roleCode: 'admin',
          status: 'active',
          isActive: true,
          isPrimaryAdmin: true,
          organizationId: 'org-test-123',
        ),
      );
      AuthService.setCapturedInitialAuthFlowForTesting(InitialAuthFlow.invite);

      await tester.pumpWidget(
        const MaterialApp(
          home: SplashScreen(duration: Duration(milliseconds: 100)),
        ),
      );
      await tester.pump();

      expect(find.byType(SplashScreen), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();

      expect(find.byType(CreatePasswordScreen), findsOneWidget);
      expect(find.text('Activate Account'), findsOneWidget);
      expect(find.text('Activate Account & Continue'), findsOneWidget);
      expect(AuthService.capturedInitialAuthFlow, InitialAuthFlow.none);
    });

    testWidgets(
      '6. recovery routes to CreatePasswordScreen and consumes flag',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        SupabaseConfig.isInitializedForTesting = true;
        const fakeUser = User(
          id: 'recovery-user-id',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-09-17T00:00:00.000Z',
          email: 'user@company.com',
        );
        final fakeSession = Session(
          accessToken: 'token123',
          expiresIn: 3600,
          refreshToken: 'ref123',
          tokenType: 'bearer',
          user: fakeUser,
        );
        AuthService.instance.setSessionForTesting(fakeSession);
        AuthService.instance.setProfileDataForTesting(
          AuthProfileData(
            userProfile: UserProfile(
              id: 'recovery-user-id',
              name: 'Existing User',
              email: 'user@company.com',
              phone: '',
              designation: 'Staff',
              department: 'Field Ops',
              division: 'Operations',
              site: 'Site A',
              team: '',
              role: 'Staff',
              accountStatus: 'Active',
              permissions: const [],
              organizationId: 'org-test-123',
              organizationName: 'Test Company',
            ),
            roleCode: 'staff',
            status: 'active',
            isActive: true,
            isPrimaryAdmin: false,
            organizationId: 'org-test-123',
          ),
        );
        AuthService.setCapturedInitialAuthFlowForTesting(
          InitialAuthFlow.recovery,
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: SplashScreen(duration: Duration(milliseconds: 100)),
          ),
        );
        await tester.pump();

        await tester.pump(const Duration(milliseconds: 150));
        await tester.pumpAndSettle();

        expect(find.byType(CreatePasswordScreen), findsOneWidget);
        expect(find.text('Create New Password'), findsOneWidget);
        expect(
          find.text('Set a new secure password for your ActionFlow account'),
          findsOneWidget,
        );
        expect(AuthService.capturedInitialAuthFlow, InitialAuthFlow.none);
      },
    );

    testWidgets('7. ordinary authenticated login still routes normally', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SupabaseConfig.isInitializedForTesting = true;
      const fakeUser = User(
        id: 'admin-user-id',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-09-17T00:00:00.000Z',
        email: 'admin@company.com',
      );
      final fakeSession = Session(
        accessToken: 'token123',
        expiresIn: 3600,
        refreshToken: 'ref123',
        tokenType: 'bearer',
        user: fakeUser,
      );
      AuthService.instance.setSessionForTesting(fakeSession);
      AuthService.instance.setProfileDataForTesting(
        AuthProfileData(
          userProfile: UserProfile(
            id: 'admin-user-id',
            name: 'Active Admin',
            email: 'admin@company.com',
            phone: '',
            designation: 'Admin',
            department: 'Corporate Headquarters',
            division: 'Governance',
            site: 'HQ',
            team: '',
            role: 'System Administrator',
            accountStatus: 'Active',
            permissions: const [],
            organizationId: 'org-test-123',
            organizationName: 'Test Company',
          ),
          roleCode: 'admin',
          status: 'active',
          isActive: true,
          isPrimaryAdmin: true,
          organizationId: 'org-test-123',
        ),
      );
      AuthService.setCapturedInitialAuthFlowForTesting(InitialAuthFlow.none);

      await tester.pumpWidget(
        const MaterialApp(
          home: SplashScreen(duration: Duration(milliseconds: 100)),
        ),
      );
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();

      expect(find.byType(CreatePasswordScreen), findsNothing);
      expect(find.byType(AdminDashboardScreen), findsOneWidget);
    });
  });
}
