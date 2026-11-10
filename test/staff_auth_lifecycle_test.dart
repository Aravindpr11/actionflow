// Staff auth lifecycle tests — focused on ForgotPasswordScreen behaviour.
//
// Verifies:
//   1. Form renders correctly with pre-populated email
//   2. Successful reset shows confirmation screen (not an error)
//   3. Rate-limit error is displayed (not silently swallowed)
//   4. Submit button is re-enabled after error (allows retry)
//   5. "Try again" from confirmation returns to form
//   6. Error banner X button clears the error
//   7. Email is trimmed and normalised to lowercase before submission
//   8. Empty email shows validation error; API is NOT called
//   9. Network error result surfaces to user

import 'package:action_flow/features/auth/screens/forgot_password_screen.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ─── Helper ────────────────────────────────────────────────────────────────
  Future<void> pump(
    WidgetTester tester, {
    String? initialEmail,
    required Future<AuthPasswordResetResult> Function(String) onReset,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ForgotPasswordScreen(
          initialEmail: initialEmail,
          resetPasswordOverride: onReset,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // =========================================================================
  // Test 1 – Form renders correctly
  // =========================================================================
  testWidgets('Test 1: Form shows email field and Send Reset Link button', (
    tester,
  ) async {
    await pump(
      tester,
      initialEmail: 'aravindpr.1111@gmail.com',
      onReset: (_) async => const AuthPasswordResetResult.success(),
    );

    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.text('Send Reset Link'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);

    // Email pre-populated
    final field = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(field.controller?.text, 'aravindpr.1111@gmail.com');
  });

  // =========================================================================
  // Test 2 – Success shows confirmation
  // =========================================================================
  testWidgets('Test 2: Successful reset shows confirmation screen', (
    tester,
  ) async {
    await pump(
      tester,
      initialEmail: 'aravindpr.1111@gmail.com',
      onReset: (_) async => const AuthPasswordResetResult.success(),
    );

    await tester.tap(find.text('Send Reset Link'));
    await tester.pumpAndSettle();

    expect(find.text('Password Reset Instructions Sent'), findsOneWidget);
    expect(find.text('aravindpr.1111@gmail.com'), findsOneWidget);
    expect(find.text("Didn't receive the email? Try again"), findsOneWidget);
  });

  // =========================================================================
  // Test 3 – Rate limit error is shown, not swallowed
  // =========================================================================
  testWidgets(
    'Test 3: Rate-limit failure is displayed to user — not silently swallowed',
    (tester) async {
      await pump(
        tester,
        initialEmail: 'aravindpr.1111@gmail.com',
        onReset: (_) async => const AuthPasswordResetResult.failure(
          'Too many password reset requests. Supabase limits one reset email '
          'per hour. Please wait before requesting again.',
        ),
      );

      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();

      // Must NOT show the confirmation success screen
      expect(find.text('Password Reset Instructions Sent'), findsNothing);

      // Must show the rate-limit error
      expect(
        find.textContaining('Too many password reset requests'),
        findsOneWidget,
      );
    },
  );

  // =========================================================================
  // Test 4 – Button re-enabled after error; allows retry that succeeds
  // =========================================================================
  testWidgets(
    'Test 4: Submit button re-enabled after error and retry succeeds',
    (tester) async {
      int callCount = 0;
      await pump(
        tester,
        initialEmail: 'aravindpr.1111@gmail.com',
        onReset: (_) async {
          callCount++;
          if (callCount == 1) {
            return const AuthPasswordResetResult.failure(
              'Network error. Please try again.',
            );
          }
          return const AuthPasswordResetResult.success();
        },
      );

      // First tap → error
      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Network error'), findsOneWidget);

      // Button must still be present and enabled
      final btn = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Send Reset Link'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(
        btn.onPressed,
        isNotNull,
        reason: 'Submit button must be re-enabled after error',
      );

      // Second tap → success
      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();

      expect(find.text('Password Reset Instructions Sent'), findsOneWidget);
      expect(callCount, 2);
    },
  );

  // =========================================================================
  // Test 5 – "Try again" returns from confirmation to form
  // =========================================================================
  testWidgets(
    'Test 5: "Try again" from confirmation screen returns to the form',
    (tester) async {
      await pump(
        tester,
        initialEmail: 'aravindpr.1111@gmail.com',
        onReset: (_) async => const AuthPasswordResetResult.success(),
      );

      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();

      expect(find.text('Password Reset Instructions Sent'), findsOneWidget);

      // The confirmation card may scroll the "Try again" button off-screen
      // in the test canvas (800×600). Ensure it is visible before tapping.
      await tester.ensureVisible(
        find.text("Didn't receive the email? Try again"),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text("Didn't receive the email? Try again"));
      await tester.pumpAndSettle();

      // Should be back on the form
      expect(find.text('Send Reset Link'), findsOneWidget);
      expect(find.text('Password Reset Instructions Sent'), findsNothing);
    },
  );

  // =========================================================================
  // Test 6 – Error banner close (X) button dismisses error
  // =========================================================================
  testWidgets('Test 6: Error banner close button clears the error message', (
    tester,
  ) async {
    await pump(
      tester,
      initialEmail: 'aravindpr.1111@gmail.com',
      onReset: (_) async =>
          const AuthPasswordResetResult.failure('Some error occurred.'),
    );

    await tester.tap(find.text('Send Reset Link'));
    await tester.pumpAndSettle();

    expect(find.text('Some error occurred.'), findsOneWidget);

    // Tap the X close button in the error banner
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Some error occurred.'), findsNothing);
  });

  // =========================================================================
  // Test 7 – Email trimmed and normalised before API call
  // =========================================================================
  testWidgets('Test 7: Email is trimmed and lowercased before submission', (
    tester,
  ) async {
    String? capturedEmail;
    await pump(
      tester,
      onReset: (email) async {
        capturedEmail = email;
        return const AuthPasswordResetResult.success();
      },
    );

    await tester.enterText(
      find.byType(TextFormField),
      '  ARAVINDPR.1111@GMAIL.COM  ',
    );
    await tester.tap(find.text('Send Reset Link'));
    await tester.pumpAndSettle();

    expect(capturedEmail, 'aravindpr.1111@gmail.com');
  });

  // =========================================================================
  // Test 8 – Empty email shows validation error; API not called
  // =========================================================================
  testWidgets(
    'Test 8: Empty email shows validation error and does not call API',
    (tester) async {
      bool called = false;
      await pump(
        tester,
        onReset: (_) async {
          called = true;
          return const AuthPasswordResetResult.success();
        },
      );

      // Leave email empty
      await tester.enterText(find.byType(TextFormField), '');
      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your email address'), findsOneWidget);
      expect(called, isFalse, reason: 'API must not be called for empty email');
    },
  );

  // =========================================================================
  // Test 9 – Network error result shows error banner
  // =========================================================================
  testWidgets('Test 9: Network error is surfaced in error banner', (
    tester,
  ) async {
    await pump(
      tester,
      initialEmail: 'aravindpr.1111@gmail.com',
      onReset: (_) async => const AuthPasswordResetResult.failure(
        'Network connection error. Please check your internet connection and try again.',
      ),
    );

    await tester.tap(find.text('Send Reset Link'));
    await tester.pumpAndSettle();

    expect(find.text('Password Reset Instructions Sent'), findsNothing);
    expect(find.textContaining('Network connection error'), findsOneWidget);
  });
}
