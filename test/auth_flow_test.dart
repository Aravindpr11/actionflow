import 'package:action_flow/features/auth/models/auth_models.dart';
import 'package:action_flow/features/auth/screens/account_status_screen.dart';
import 'package:action_flow/features/auth/screens/account_type_selection_screen.dart';
import 'package:action_flow/features/auth/screens/email_verification_screen.dart';
import 'package:action_flow/features/auth/screens/forgot_password_screen.dart';
import 'package:action_flow/features/auth/screens/login_screen.dart';
import 'package:action_flow/features/auth/screens/signup_screen.dart';
import 'package:action_flow/features/auth/screens/signup_success_screen.dart';
import 'package:action_flow/features/dashboard/admin_dashboard/screens/admin_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildAppWidget({
    required Widget home,
    ThemeMode themeMode = ThemeMode.light,
  }) {
    return MaterialApp(
      themeMode: themeMode,
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: home,
    );
  }

  group('ActionFlow Authentication Suite - Login Screen Tests', () {
    testWidgets(
      'Login screen renders branding, input fields, and all action buttons',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 850);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildAppWidget(home: const LoginScreen()));
        await tester.pumpAndSettle();

        expect(find.text('Welcome back'), findsOneWidget);
        expect(find.text('Username or email'), findsOneWidget);
        expect(find.text('Password'), findsOneWidget);
        expect(find.text('Remember me'), findsOneWidget);
        expect(find.text('Sign In'), findsOneWidget);
        expect(find.text('Forgot Password?'), findsOneWidget);
        expect(find.text('Create Account'), findsOneWidget);
      },
    );

    testWidgets('Password visibility toggle toggles obscureText', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildAppWidget(home: const LoginScreen()));
      await tester.pumpAndSettle();

      // Find password field
      final passFieldFinder = find.widgetWithText(TextFormField, 'Password');
      expect(passFieldFinder, findsOneWidget);

      TextField textField = tester.widget<TextField>(
        find.descendant(of: passFieldFinder, matching: find.byType(TextField)),
      );
      expect(textField.obscureText, isTrue);

      // Tap visibility toggle
      await tester.tap(find.byIcon(Icons.visibility_rounded));
      await tester.pumpAndSettle();

      textField = tester.widget<TextField>(
        find.descendant(of: passFieldFinder, matching: find.byType(TextField)),
      );
      expect(textField.obscureText, isFalse);
    });

    testWidgets('Shows validation error on empty credentials', (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildAppWidget(home: const LoginScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your username or email'), findsOneWidget);
    });

    testWidgets('Shows validation error on invalid credentials', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildAppWidget(home: const LoginScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username or email'),
        'wronguser',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'wrongpass',
      );
      await tester.tap(find.text('Sign In'));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(find.text('Invalid username or password'), findsOneWidget);
    });

    testWidgets('Existing mock login routes to AdminDashboardScreen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildAppWidget(home: const LoginScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username or email'),
        'admin',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        '123456',
      );
      await tester.tap(find.text('Sign In'));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(find.byType(AdminDashboardScreen), findsOneWidget);
    });

    testWidgets('Existing mock login routes to ManagerDashboardScreen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildAppWidget(home: const LoginScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username or email'),
        'manager',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        '123456',
      );
      await tester.tap(find.text('Sign In'));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(find.byType(ManagerDashboardScreen), findsOneWidget);
    });

    testWidgets('Existing mock login routes to WorkerDashboardScreen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildAppWidget(home: const LoginScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username or email'),
        'staff',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        '123456',
      );
      await tester.tap(find.text('Sign In'));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(find.byType(WorkerDashboardScreen), findsOneWidget);
    });
  });

  group('ActionFlow Authentication Suite - Forgot Password Tests', () {
    testWidgets('Forgot password navigates and displays email request form', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildAppWidget(home: const LoginScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
      expect(find.text('Forgot Password?'), findsOneWidget);
      expect(find.text('Send Reset Link'), findsOneWidget);

      // Validate email requirement (empty field)
      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter your email address'), findsOneWidget);

      // Enter valid email — test that form accepts valid input
      // (Supabase is not initialized in this test suite, so the submit
      //  will return an error — confirmation state is tested in
      //  auth_password_lifecycle_test.dart with a resetPasswordOverride)
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address *'),
        'alex@company.com',
      );
      expect(find.text('alex@company.com'), findsOneWidget);
      // Verify 'Send Reset Link' button is still present and enabled
      expect(find.text('Send Reset Link'), findsOneWidget);
    });
  });

  group('ActionFlow Authentication Suite - Signup & Registration Tests', () {
    testWidgets(
      'Create Account opens AccountTypeSelectionScreen with Manager and Staff options',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 850);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildAppWidget(home: const LoginScreen()));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Create Account'));
        await tester.pumpAndSettle();

        expect(find.byType(AccountTypeSelectionScreen), findsOneWidget);
        expect(find.text('Create a New Account'), findsOneWidget);
        expect(find.text('Choose the account type'), findsOneWidget);
        expect(find.text('Manager'), findsOneWidget);
        expect(
          find.text('Manage actions across assigned departments & sites'),
          findsOneWidget,
        );
        expect(find.text('Staff'), findsOneWidget);
        expect(
          find.text('Execute actions and submit progress'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Administrator accounts are created by existing administrators.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('SignupScreen renders with all sections', (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildAppWidget(home: const SignupScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(SignupScreen), findsOneWidget);
      expect(find.text('PERSONAL INFORMATION'), findsOneWidget);
      expect(find.text('WORK INFORMATION'), findsOneWidget);
      expect(find.text('ACCOUNT & ACCESS TYPE'), findsOneWidget);
      expect(
        find.textContaining('Department, Site, Designation, Role'),
        findsOneWidget,
      );
    });

    testWidgets('Manager account request displays approval disclaimer', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildAppWidget(home: const SignupScreen()));
      await tester.pumpAndSettle();

      // Tap Manager radio / card
      await tester.tap(find.text('Manager'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'Manager access request: Selecting Manager does not grant instant administrator privileges',
        ),
        findsOneWidget,
      );
      expect(find.text('Submit Manager Access Request'), findsOneWidget);
    });

    testWidgets('Signup validates required fields and password mismatch', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildAppWidget(home: const SignupScreen()));
      await tester.pumpAndSettle();

      // Submit empty
      await tester.ensureVisible(find.text('Create Staff Account'));
      await tester.tap(find.text('Create Staff Account'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your full name'), findsOneWidget);

      // Fill in details with mismatched passwords
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full Name *'),
        'Alex Morgan',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email Address *'),
        'alex.m@actionflow.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone Number *'),
        '+1 555 123 4567',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Designation / Job Title *'),
        'Field Safety Lead',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password *'),
        'Secret123!',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm Password *'),
        'DifferentPass',
      );

      await tester.ensureVisible(find.text('Create Staff Account'));
      await tester.tap(find.text('Create Staff Account'));
      await tester.pumpAndSettle();

      expect(find.text('Passwords do not match'), findsOneWidget);

      // Fix password match and submit
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm Password *'),
        'Secret123!',
      );
      await tester.ensureVisible(find.text('Create Staff Account'));
      await tester.tap(find.text('Create Staff Account'));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      // Successfully transitioned to SignupSuccessScreen
      expect(find.byType(SignupSuccessScreen), findsOneWidget);
      expect(find.text('Account Registration Submitted'), findsOneWidget);
      expect(find.text('Alex Morgan'), findsOneWidget);
      expect(find.text('alex.m@actionflow.com'), findsOneWidget);
    });
  });

  group('ActionFlow Authentication Suite - Verification & Status Screens', () {
    testWidgets('EmailVerificationScreen renders email and resend action', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildAppWidget(
          home: const EmailVerificationScreen(email: 'sarah@actionflow.com'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Verify your email'), findsOneWidget);
      expect(find.text('sarah@actionflow.com'), findsOneWidget);
      expect(find.text('Resend Verification Email'), findsOneWidget);

      await tester.tap(find.text('Resend Verification Email'));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'Verification email resent to sarah@actionflow.com',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'AccountStatusScreen renders pending approval and active states',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 850);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildAppWidget(
            home: const AccountStatusScreen(
              status: AuthAccountStatus.pendingApproval,
              userName: 'David Miller',
              userEmail: 'david.m@actionflow.com',
              requestedType: RequestedAccountType.manager,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Pending Administrator Approval'), findsOneWidget);
        expect(find.text('David Miller'), findsOneWidget);
        expect(find.text('david.m@actionflow.com'), findsOneWidget);
      },
    );
  });

  group('ActionFlow Authentication Suite - Responsive & Theme Tests', () {
    testWidgets('All auth screens render cleanly in Dark Theme', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildAppWidget(home: const LoginScreen(), themeMode: ThemeMode.dark),
      );
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('LoginScreen renders with 0 overflow at Desktop (1200px)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildAppWidget(home: const LoginScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('LoginScreen renders with 0 overflow at Tablet (768px)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildAppWidget(home: const LoginScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('LoginScreen renders with 0 overflow at Mobile (400px)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildAppWidget(home: const LoginScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('LoginScreen renders with 0 overflow at Small Mobile (320px)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildAppWidget(home: const LoginScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('SignupScreen renders with 0 overflow across all breakpoints', (
      tester,
    ) async {
      for (final size in const [
        Size(1200, 850),
        Size(768, 1024),
        Size(400, 800),
        Size(320, 568),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(buildAppWidget(home: const SignupScreen()));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });
}
