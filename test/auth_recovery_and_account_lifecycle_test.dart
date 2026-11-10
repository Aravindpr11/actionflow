import 'package:action_flow/features/auth/screens/create_password_screen.dart';
import 'package:action_flow/features/auth/screens/login_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/splash/screens/splash_screen.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/models/team.dart';
import 'package:action_flow/features/users/screens/person_form_screen.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    AuthService.clearCapturedInitialAuthFlow();
    AuthService.clearCapturedAuthLinkError();
    AuthService.clearPasswordRecoveryState();
  });

  tearDown(() {
    AuthService.clearCapturedInitialAuthFlow();
    AuthService.clearCapturedAuthLinkError();
    AuthService.clearPasswordRecoveryState();
  });

  group('AuthService - Recovery & Auth Link Error Parsing', () {
    test('Correctly captures expired link error from URL fragment', () {
      final uri = Uri.parse(
        'https://actionflow.app/#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired',
      );

      AuthService.captureInitialAuthFlow(uri);

      final error = AuthService.capturedAuthLinkError;
      expect(error, isNotNull);
      expect(error!.error, equals('access_denied'));
      expect(error.errorCode, equals('otp_expired'));
      expect(error.description, equals('Email link is invalid or has expired'));
      expect(error.isExpired, isTrue);
      expect(
        error.userFriendlyMessage,
        contains('Your invitation or password reset link has expired'),
      );

      // Flow must NOT be flagged as valid invite or recovery
      expect(AuthService.capturedInitialAuthFlow, equals(InitialAuthFlow.none));
      expect(AuthService.isIncomingRecoveryFlow, isFalse);
      expect(AuthService.isIncomingInviteFlow, isFalse);
    });

    test('Correctly captures expired link error from query parameters', () {
      final uri = Uri.parse(
        'https://actionflow.app/?error=access_denied&error_code=otp_expired&error_description=Token+expired',
      );

      AuthService.captureInitialAuthFlow(uri);

      final error = AuthService.capturedAuthLinkError;
      expect(error, isNotNull);
      expect(error!.errorCode, equals('otp_expired'));
      expect(error.isExpired, isTrue);
      expect(AuthService.isIncomingRecoveryFlow, isFalse);
    });

    test('Captures valid recovery flow and sets isPasswordRecoveryActive', () {
      final uri = Uri.parse(
        'https://actionflow.app/#type=recovery&access_token=test_tok',
      );

      AuthService.captureInitialAuthFlow(uri);

      expect(AuthService.capturedAuthLinkError, isNull);
      expect(
        AuthService.capturedInitialAuthFlow,
        equals(InitialAuthFlow.recovery),
      );
      expect(AuthService.isIncomingRecoveryFlow, isTrue);
      expect(AuthService.isPasswordRecoveryActive, isTrue);

      AuthService.clearCapturedInitialAuthFlow();
      expect(AuthService.capturedInitialAuthFlow, equals(InitialAuthFlow.none));
      // isPasswordRecoveryActive remains until consumed or reset
      expect(AuthService.isPasswordRecoveryActive, isTrue);

      AuthService.clearPasswordRecoveryState();
      expect(AuthService.isPasswordRecoveryActive, isFalse);
    });

    test('Captures valid invite flow', () {
      final uri = Uri.parse('https://actionflow.app/?type=invite');

      AuthService.captureInitialAuthFlow(uri);

      expect(AuthService.capturedAuthLinkError, isNull);
      expect(
        AuthService.capturedInitialAuthFlow,
        equals(InitialAuthFlow.invite),
      );
      expect(AuthService.isIncomingInviteFlow, isTrue);
      expect(AuthService.isIncomingRecoveryFlow, isFalse);
    });
  });

  group('SplashScreen - Error and Recovery Interception', () {
    testWidgets(
      'Routes to LoginScreen with banner error when auth link is expired',
      (tester) async {
        AuthService.setCapturedAuthLinkErrorForTesting(
          const AuthLinkError(
            error: 'access_denied',
            errorCode: 'otp_expired',
            description: 'Email link is invalid or has expired',
          ),
        );

        await tester.pumpWidget(
          const MaterialApp(home: SplashScreen(duration: Duration.zero)),
        );

        await tester.pumpAndSettle();

        // Must navigate to LoginScreen and display the user-friendly expiration banner
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(
          find.textContaining(
            'Your invitation or password reset link has expired',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('PersonFormScreen - Cross-Department Team Membership', () {
    testWidgets(
      'Permits cross-department team memberships within the same organization',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final availableDepartments = [
          {'id': 'dept-hse', 'name': 'HSE / Safety', 'division': 'HSSE'},
          {'id': 'dept-ops', 'name': 'Operations', 'division': 'Operations'},
        ];
        final availableTeams = [
          {
            'id': 'team-safety',
            'name': 'Safety Inspection Team',
            'deptId': 'dept-hse',
            'dept': 'HSE / Safety',
          },
          {
            'id': 'team-ops-alpha',
            'name': 'Field Operations Team Alpha',
            'deptId': 'dept-ops',
            'dept': 'Operations',
          },
        ];

        // Person profile configured with HSE department and holding cross-department team
        final initialPerson = Person(
          id: 'user-manager-1',
          name: 'Test Manager',
          email: 'manager@example.com',
          phone: '+971 50 111 2222',
          designation: 'HSE Lead',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.departmentManager,
          department: 'HSE / Safety',
          departmentId: 'dept-hse',
          site: 'North Plant',
          teamIds: const [
            'team-safety',
            'team-ops-alpha',
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: PersonFormScreen(
              person: initialPerson,
              availableDepartments: availableDepartments,
              availableTeams: availableTeams,
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Both teams across departments within the organization should be displayed
        expect(find.text('Safety Inspection Team'), findsOneWidget);
        expect(find.text('Field Operations Team Alpha'), findsOneWidget);
      },
    );
  });

  group('CreatePasswordScreen - Form & Validation UI', () {
    testWidgets(
      'Renders recovery mode UI with password validation requirements',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: CreatePasswordScreen(
              mode: PasswordScreenMode.recovery,
              email: 'webonant@gmail.com',
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Create New Password'), findsOneWidget);
        expect(
          find.textContaining('Set a new secure password'),
          findsOneWidget,
        );
        expect(find.text('webonant@gmail.com'), findsOneWidget);
        expect(find.text('At least 8 characters'), findsOneWidget);
      },
    );
  });

  group('Self-Service Account Deletion - Danger Zone UI', () {
    testWidgets(
      'Manager Portal Settings displays Danger Zone with Delete My Account',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          const MaterialApp(home: ManagerDashboardScreen()),
        );
        await tester.pumpAndSettle();

        // Navigate to Settings in Manager Dashboard
        final settingsNav = find.text('Settings');
        expect(settingsNav, findsOneWidget);
        await tester.tap(settingsNav);
        await tester.pumpAndSettle();

        // Verify Danger Zone is rendered
        expect(find.text('Danger Zone'), findsOneWidget);
        expect(find.text('Delete My Account'), findsOneWidget);

        // Tap Delete My Account to open confirmation dialog
        await tester.ensureVisible(find.text('Delete My Account'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete My Account'));
        await tester.pumpAndSettle();

        expect(find.text('Delete Your Account'), findsOneWidget);
        expect(find.text('Delete Permanently'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);

        // Cancel dismissal
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Delete Your Account'), findsNothing);
      },
    );

    testWidgets(
      'Worker Portal Settings displays Danger Zone with Delete My Account',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          const MaterialApp(home: WorkerDashboardScreen()),
        );
        await tester.pumpAndSettle();

        // Navigate to Settings in Worker Dashboard
        final settingsNav = find.text('Settings');
        expect(settingsNav, findsOneWidget);
        await tester.tap(settingsNav);
        await tester.pumpAndSettle();

        // Verify Danger Zone is rendered
        expect(find.text('Danger Zone'), findsOneWidget);
        expect(find.text('Delete My Account'), findsOneWidget);

        // Tap Delete My Account to open confirmation dialog
        await tester.ensureVisible(find.text('Delete My Account'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete My Account'));
        await tester.pumpAndSettle();

        expect(find.text('Delete Your Account'), findsOneWidget);
        expect(find.text('Delete Permanently'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);

        // Cancel dismissal
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Delete Your Account'), findsNothing);
      },
    );
  });
}
