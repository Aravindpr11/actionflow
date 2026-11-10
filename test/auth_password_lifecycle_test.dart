import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/auth/screens/create_password_screen.dart';
import 'package:action_flow/features/auth/screens/forgot_password_screen.dart';
import 'package:action_flow/features/profile/widgets/change_password_dialog.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Password Policy & Regex Validation Tests', () {
    final letterRegex = RegExp(r'[A-Za-z]');
    final numberRegex = RegExp(r'[0-9]');

    bool isValidPassword(String password) {
      return password.length >= 8 &&
          letterRegex.hasMatch(password) &&
          numberRegex.hasMatch(password);
    }

    test('Rejects password shorter than 8 characters', () {
      expect(isValidPassword('Abc1!'), isFalse);
      expect(isValidPassword('1234567'), isFalse);
      expect(isValidPassword('Short1'), isFalse);
    });

    test('Rejects password without letters', () {
      expect(isValidPassword('12345678'), isFalse);
      expect(isValidPassword('1234567890'), isFalse);
      expect(isValidPassword('12345678!@#'), isFalse);
    });

    test('Rejects password without numbers', () {
      expect(isValidPassword('abcdefgh'), isFalse);
      expect(isValidPassword('PasswordOnly'), isFalse);
      expect(isValidPassword('ABCDEFGHIJKL'), isFalse);
    });

    test(
      'Accepts compliant password with at least 8 chars, letters, and numbers',
      () {
        expect(isValidPassword('Password123'), isTrue);
        expect(isValidPassword('ActionFlow2026'), isTrue);
        expect(isValidPassword('p@ssw0rdSecure!'), isTrue);
        expect(isValidPassword('abcXYZ999'), isTrue);
      },
    );
  });

  group('AuthService Password Foundation Unit Tests (Uninitialized State)', () {
    test('Supabase is uninitialized in test environment', () {
      expect(SupabaseConfig.isInitialized, isFalse);
      expect(SupabaseConfig.clientOrNull, isNull);
    });

    test(
      'updatePassword returns graceful failure when uninitialized',
      () async {
        final result = await AuthService.instance.updatePassword(
          'NewPassword123',
        );
        expect(result.isSuccess, isFalse);
        expect(
          result.errorMessage,
          'Authentication service is currently unavailable.',
        );
      },
    );

    test(
      'resetPasswordForEmail returns graceful failure when uninitialized',
      () async {
        final result = await AuthService.instance.resetPasswordForEmail(
          'user@example.com',
          redirectTo: 'http://localhost:8080',
        );
        expect(result.isSuccess, isFalse);
        expect(
          result.errorMessage,
          'Authentication service is currently unavailable.',
        );
      },
    );

    test(
      'changePassword returns graceful failure when uninitialized',
      () async {
        final result = await AuthService.instance.changePassword(
          currentPassword: 'OldPassword123',
          newPassword: 'NewPassword123',
        );
        expect(result.isSuccess, isFalse);
        expect(
          result.errorMessage,
          'Authentication service is currently unavailable.',
        );
      },
    );

    test('AuthPasswordUpdateResult handles success and failure', () {
      const success = AuthPasswordUpdateResult.success();
      expect(success.isSuccess, isTrue);
      expect(success.errorMessage, isNull);

      const failure = AuthPasswordUpdateResult.failure('Invalid token');
      expect(failure.isSuccess, isFalse);
      expect(failure.errorMessage, 'Invalid token');
    });

    test('AuthPasswordResetResult handles success and failure', () {
      const success = AuthPasswordResetResult.success();
      expect(success.isSuccess, isTrue);
      expect(success.errorMessage, isNull);

      const failure = AuthPasswordResetResult.failure('Rate limited');
      expect(failure.isSuccess, isFalse);
      expect(failure.errorMessage, 'Rate limited');
    });
  });

  group('CreatePasswordScreen Widget Tests', () {
    testWidgets('Renders invitation mode header and fields', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const CreatePasswordScreen(
            mode: PasswordScreenMode.invite,
            email: 'invited.admin@company.com',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Activate Account'), findsOneWidget);
      expect(
        find.text(
          'Create a secure password to complete your account activation',
        ),
        findsOneWidget,
      );
      expect(find.text('invited.admin@company.com'), findsOneWidget);
      expect(find.text('Activate Account & Continue'), findsOneWidget);
      expect(find.text('Password Security Requirements:'), findsOneWidget);
      expect(find.text('At least 8 characters'), findsOneWidget);
      expect(find.text('Contains letters and numbers'), findsOneWidget);
      expect(find.text('Passwords match'), findsOneWidget);
    });

    testWidgets('Renders recovery mode header and fields', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const CreatePasswordScreen(mode: PasswordScreenMode.recovery),
        ),
      );
      await tester.pump();

      expect(find.text('Create New Password'), findsOneWidget);
      expect(
        find.text('Set a new secure password for your ActionFlow account'),
        findsOneWidget,
      );
      expect(find.text('Update Password & Continue'), findsOneWidget);
    });

    testWidgets(
      'Form validation blocks submission on empty or non-matching passwords',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const CreatePasswordScreen(mode: PasswordScreenMode.invite),
          ),
        );
        await tester.pump();

        // Tap submit with empty inputs
        await tester.tap(find.text('Activate Account & Continue'));
        await tester.pump();

        expect(find.text('Please enter a password'), findsOneWidget);
        expect(find.text('Please confirm your password'), findsOneWidget);

        // Enter password with less than 8 chars
        final textFields = find.byType(TextFormField);
        await tester.enterText(textFields.first, 'Short1');
        await tester.enterText(textFields.last, 'Short1');
        await tester.tap(find.text('Activate Account & Continue'));
        await tester.pump();

        expect(
          find.text('Password must be at least 8 characters'),
          findsOneWidget,
        );

        // Enter mismatched passwords
        await tester.enterText(textFields.first, 'ValidPass123');
        await tester.enterText(textFields.last, 'Different123');
        await tester.tap(find.text('Activate Account & Continue'));
        await tester.pump();

        expect(find.text('Passwords do not match'), findsOneWidget);
      },
    );

    testWidgets('Obscure text toggle button flips visibility', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const CreatePasswordScreen(mode: PasswordScreenMode.invite),
        ),
      );
      await tester.pump();

      // Find visibility toggle buttons (initially visibility_off)
      final visibilityIcons = find.byIcon(Icons.visibility_off_outlined);
      expect(visibilityIcons, findsNWidgets(2));

      // Tap the first toggle
      await tester.tap(visibilityIcons.first);
      await tester.pump();

      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });
  });

  group('ForgotPasswordScreen Widget Tests', () {
    testWidgets('Renders request form with initial email if provided', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const ForgotPasswordScreen(
            initialEmail: 'admin@sobharealty.com',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Forgot Password?'), findsOneWidget);
      expect(find.text('Reset your account password'), findsOneWidget);
      expect(find.text('Send Reset Link'), findsOneWidget);
      expect(find.text('admin@sobharealty.com'), findsOneWidget);
    });

    testWidgets('Validates email format before submission', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const ForgotPasswordScreen(),
        ),
      );
      await tester.pump();

      // Submit with empty email
      await tester.tap(find.text('Send Reset Link'));
      await tester.pump();
      expect(find.text('Please enter your email address'), findsOneWidget);

      // Submit with invalid email format
      await tester.enterText(find.byType(TextFormField), 'not-an-email');
      await tester.tap(find.text('Send Reset Link'));
      await tester.pump();
      expect(find.text('Please enter a valid email address'), findsOneWidget);
    });

    testWidgets(
      'Transitions to safe confirmation state after sending request',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: ForgotPasswordScreen(
              // In tests Supabase is not initialized; inject a success override
              // to simulate the normal successful reset-email path.
              resetPasswordOverride: (_) async =>
                  const AuthPasswordResetResult.success(),
            ),
          ),
        );
        await tester.pump();

        await tester.enterText(find.byType(TextFormField), 'valid@company.com');
        await tester.tap(find.text('Send Reset Link'));
        await tester.pumpAndSettle();

        // Verify safe generic confirmation message
        expect(find.text('Password Reset Instructions Sent'), findsOneWidget);
        expect(find.text('valid@company.com'), findsOneWidget);
        expect(
          find.textContaining('If an account exists for this email'),
          findsOneWidget,
        );
        expect(find.text('Back to Login'), findsOneWidget);
      },
    );
  });

  group('ChangePasswordDialog Widget Tests', () {
    testWidgets('Renders all fields and password policy rules', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: ChangePasswordDialog()),
        ),
      );
      await tester.pump();

      expect(find.text('Change Password'), findsOneWidget);
      expect(find.text('Current Password *'), findsOneWidget);
      expect(find.text('New Password *'), findsOneWidget);
      expect(find.text('Confirm New Password *'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Update Password'), findsOneWidget);
      expect(find.text('Requirements:'), findsOneWidget);
      expect(find.text('At least 8 characters'), findsOneWidget);
      expect(find.text('Letters & numbers included'), findsOneWidget);
      expect(find.text('Passwords match'), findsOneWidget);
    });

    testWidgets('Validates required fields in ChangePasswordDialog', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: ChangePasswordDialog()),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Update Password'));
      await tester.pump();

      expect(find.text('Please enter your current password'), findsOneWidget);
      expect(find.text('Please enter a new password'), findsOneWidget);
      expect(find.text('Please confirm your new password'), findsOneWidget);
    });
  });
}
