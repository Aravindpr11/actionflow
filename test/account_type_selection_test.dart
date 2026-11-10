import 'package:action_flow/features/auth/screens/account_type_selection_screen.dart';
import 'package:action_flow/features/auth/screens/login_screen.dart';
import 'package:action_flow/features/auth/screens/manager_account_setup_screen.dart';
import 'package:action_flow/features/auth/screens/staff_account_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildTestWidget({
    Widget? home,
    ThemeMode themeMode = ThemeMode.light,
  }) {
    return MaterialApp(
      themeMode: themeMode,
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: home ?? const AccountTypeSelectionScreen(),
    );
  }

  group('AccountTypeSelectionScreen - Content & Structure Tests', () {
    testWidgets(
      'Renders title, subtitle, manager card, staff card, and info note',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 850);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // Check screen title & subtitle
        expect(find.text('Create a New Account'), findsOneWidget);
        expect(find.text('Choose the account type'), findsOneWidget);

        // Check Manager card & exact description
        expect(find.text('Manager'), findsOneWidget);
        expect(
          find.text('Manage actions across assigned departments & sites'),
          findsOneWidget,
        );

        // Check Staff card & exact description
        expect(find.text('Staff'), findsOneWidget);
        expect(
          find.text('Execute actions and submit progress'),
          findsOneWidget,
        );

        // Verify Administrator is NOT presented as a selectable option
        expect(find.text('Admin'), findsNothing);
        expect(find.text('Administrator'), findsNothing);

        // Check informational note
        expect(
          find.text(
            'Administrator accounts are created by existing administrators.',
          ),
          findsOneWidget,
        );

        // Check Back/Sign In link
        expect(find.text('Already have an account? '), findsOneWidget);
        expect(find.text('Sign In'), findsOneWidget);
      },
    );
  });

  group('AccountTypeSelectionScreen - Navigation & Interaction Tests', () {
    testWidgets('Tapping Manager card navigates to ManagerAccountSetupScreen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('account_type_manager')));
      await tester.pumpAndSettle();

      expect(find.byType(ManagerAccountSetupScreen), findsOneWidget);
      expect(find.text('Create Manager Account'), findsOneWidget);

      // Back navigation returns to AccountTypeSelectionScreen
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.byType(AccountTypeSelectionScreen), findsOneWidget);
    });

    testWidgets('Tapping Staff card navigates to StaffAccountSetupScreen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('account_type_staff')));
      await tester.pumpAndSettle();

      expect(find.byType(StaffAccountSetupScreen), findsOneWidget);
      expect(find.text('Create Staff Account'), findsOneWidget);

      // Back navigation returns to AccountTypeSelectionScreen
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.byType(AccountTypeSelectionScreen), findsOneWidget);
    });

    testWidgets(
      'LoginScreen "Create Account" navigates to AccountTypeSelectionScreen and back pops to LoginScreen',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 850);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestWidget(home: const LoginScreen()));
        await tester.pumpAndSettle();

        // Tap Create Account
        await tester.tap(find.text('Create Account'));
        await tester.pumpAndSettle();

        expect(find.byType(AccountTypeSelectionScreen), findsOneWidget);

        // Tap AppBar back button
        await tester.tap(find.byTooltip('Back to Sign In'));
        await tester.pumpAndSettle();

        expect(find.byType(LoginScreen), findsOneWidget);

        // Tap Create Account again
        await tester.tap(find.text('Create Account'));
        await tester.pumpAndSettle();

        expect(find.byType(AccountTypeSelectionScreen), findsOneWidget);

        // Tap bottom Sign In text button
        await tester.tap(find.text('Sign In'));
        await tester.pumpAndSettle();

        expect(find.byType(LoginScreen), findsOneWidget);
      },
    );
  });

  group('AccountTypeSelectionScreen - Theme & Responsive Tests', () {
    testWidgets('Renders cleanly in Dark Theme mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget(themeMode: ThemeMode.dark));
      await tester.pumpAndSettle();

      expect(find.text('Create a New Account'), findsOneWidget);
      expect(find.text('Manager'), findsOneWidget);
      expect(find.text('Staff'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders with 0 overflow across all breakpoints', (
      tester,
    ) async {
      const testSizes = [
        Size(1200, 850), // Desktop
        Size(768, 1024), // Tablet
        Size(400, 800), // Mobile
        Size(320, 568), // Small Mobile
      ];

      for (final size in testSizes) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Create a New Account'), findsOneWidget);
        expect(find.text('Manager'), findsOneWidget);
        expect(find.text('Staff'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });
}
