import 'package:action_flow/features/auth/screens/manager_account_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildTestWidget({ThemeMode themeMode = ThemeMode.light}) {
    return MaterialApp(
      themeMode: themeMode,
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: const ManagerAccountSetupScreen(),
    );
  }

  group('ManagerAccountSetupScreen - Content & Structure Tests', () {
    testWidgets('Manager form renders all required sections and fields', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 950);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Title and subtitle
      expect(find.text('Create Manager Account'), findsOneWidget);
      expect(
        find.text(
          'Enter your details and select the departments and sites you will manage.',
        ),
        findsOneWidget,
      );

      // Section 1: Personal Information
      expect(find.text('PERSONAL INFORMATION'), findsOneWidget);
      expect(find.text('Full Name *'), findsOneWidget);
      expect(find.text('Email *'), findsOneWidget);
      expect(find.text('Phone (Optional)'), findsOneWidget);
      expect(find.text('Designation *'), findsOneWidget);

      // Section 2: Management Scope
      expect(find.text('MANAGEMENT SCOPE'), findsOneWidget);
      expect(find.text('Department 1'), findsOneWidget);
      expect(find.text('Sites (Select all that apply):'), findsOneWidget);
      expect(find.text('Add another department'), findsOneWidget);
      expect(find.text('Management Scope'), findsOneWidget);

      // Section 3: Password
      expect(find.text('PASSWORD'), findsOneWidget);
      expect(find.text('Password *'), findsOneWidget);
      expect(find.text('Confirm Password *'), findsOneWidget);

      // Bottom buttons
      expect(find.text('Back'), findsOneWidget);
      expect(find.text('Submit Account Request'), findsOneWidget);

      // Strictly verify Supervisor, Team, and Admin are NOT shown
      expect(find.text('Supervisor'), findsNothing);
      expect(find.text('Supervisor (Optional)'), findsNothing);
      expect(find.text('Team'), findsNothing);
      expect(find.text('Team / Unit (Optional)'), findsNothing);
      expect(find.text('Admin'), findsNothing);
      expect(find.text('Administrator'), findsNothing);
    });
  });

  group('ManagerAccountSetupScreen - Validation Tests', () {
    testWidgets('Required field validation fails when submitting empty form', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Tap Submit with empty fields
      await tester.ensureVisible(find.text('Submit Account Request'));
      await tester.tap(find.text('Submit Account Request'));
      await tester.pumpAndSettle();

      // Verify form validators triggered
      expect(find.text('Please enter your full name'), findsOneWidget);
      expect(find.text('Please enter your email address'), findsOneWidget);
      expect(find.text('Please enter your designation'), findsOneWidget);
      expect(find.text('Please enter a password'), findsOneWidget);
      expect(find.text('Please confirm your password'), findsOneWidget);

      // Verify scope validator triggered (no sites selected yet)
      expect(
        find.text('At least one Department + Site combination required'),
        findsOneWidget,
      );
    });

    testWidgets('Email format validation and password mismatch validation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Enter invalid email
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email *'),
        'not-an-email',
      );

      // Enter mismatched passwords
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password *'),
        'Password123!',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm Password *'),
        'MismatchedPassword',
      );

      await tester.ensureVisible(find.text('Submit Account Request'));
      await tester.tap(find.text('Submit Account Request'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid email address'), findsOneWidget);
      expect(find.text('Passwords do not match'), findsOneWidget);
    });

    testWidgets('Password length validation enforces at least 6 characters', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password *'),
        '123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm Password *'),
        '123',
      );

      await tester.ensureVisible(find.text('Submit Account Request'));
      await tester.tap(find.text('Submit Account Request'));
      await tester.pumpAndSettle();

      expect(
        find.text('Password must be at least 6 characters'),
        findsOneWidget,
      );
    });
  });

  group('ManagerAccountSetupScreen - Scope Selection & Management Tests', () {
    testWidgets('Selecting multiple sites updates Scope Summary', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Initial empty state in summary
      expect(
        find.text(
          'No management scopes configured yet. Select at least one department and site above.',
        ),
        findsOneWidget,
      );
      expect(find.text('0 Scopes'), findsOneWidget);

      // Select 'Platform Alpha' chip
      await tester.tap(find.text('Platform Alpha').first);
      await tester.pumpAndSettle();

      // Verify summary updated
      expect(find.text('HSE / Safety / Platform Alpha'), findsOneWidget);
      expect(find.text('1 Scopes'), findsOneWidget);

      // Select 'Platform Bravo' chip
      await tester.tap(find.text('Platform Bravo').first);
      await tester.pumpAndSettle();

      // Verify both scopes are listed
      expect(find.text('HSE / Safety / Platform Alpha'), findsOneWidget);
      expect(find.text('HSE / Safety / Platform Bravo'), findsOneWidget);
      expect(find.text('2 Scopes'), findsOneWidget);
    });

    testWidgets(
      'Adding another department allows configuring multi-department scopes',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // Select site in Department 1 (HSE / Safety)
        await tester.tap(find.text('North Plant').first);
        await tester.pumpAndSettle();

        expect(find.text('HSE / Safety / North Plant'), findsOneWidget);

        // Tap "+ Add another department"
        await tester.ensureVisible(find.text('Add another department'));
        await tester.tap(find.text('Add another department'));
        await tester.pumpAndSettle();

        // Verify Department 2 block appeared
        expect(find.text('Department 2'), findsOneWidget);

        // Select site in Department 2 (which defaults to Operations)
        await tester.tap(
          find.byKey(const ValueKey('chip_dept-ops_site-cy-main')),
        );
        await tester.pumpAndSettle();

        // Verify both Department scopes appear in the summary
        expect(find.text('HSE / Safety / North Plant'), findsOneWidget);
        expect(find.text('Operations / Central Yard'), findsOneWidget);
        expect(find.text('2 Scopes'), findsOneWidget);
      },
    );

    testWidgets('Removing a scope from Scope Summary unchecks the site chip', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Select 'Platform Alpha'
      await tester.tap(find.text('Platform Alpha').first);
      await tester.pumpAndSettle();

      expect(find.text('HSE / Safety / Platform Alpha'), findsOneWidget);
      expect(find.text('1 Scopes'), findsOneWidget);

      // Tap remove button in summary
      await tester.tap(
        find.byKey(const ValueKey('remove_scope_dept-hse_site-plt-a')),
      );
      await tester.pumpAndSettle();

      // Scope is removed from summary
      expect(find.text('HSE / Safety / Platform Alpha'), findsNothing);
      expect(find.text('0 Scopes'), findsOneWidget);
    });

    testWidgets(
      'Validates that every configured department must have at least one site',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // Select site in Dept 1
        await tester.tap(find.text('Platform Alpha').first);
        await tester.pumpAndSettle();

        // Add Dept 2 but don't select any site for it
        await tester.ensureVisible(find.text('Add another department'));
        await tester.tap(find.text('Add another department'));
        await tester.pumpAndSettle();

        // Fill all required fields
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Full Name *'),
          'Sarah Jenkins',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Email *'),
          'sarah.j@company.com',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Designation *'),
          'Operations Manager',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Password *'),
          'SecurePass123!',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirm Password *'),
          'SecurePass123!',
        );

        // Submit form
        await tester.ensureVisible(find.text('Submit Account Request'));
        await tester.tap(find.text('Submit Account Request'));
        await tester.pumpAndSettle();

        // Should show error for Dept 2 having no sites
        expect(
          find.textContaining(
            'Every selected Department must have at least one Site',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Successful local validation displays preview confirmation dialog',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // Fill personal information
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Full Name *'),
          'David Miller',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Email *'),
          'david.miller@company.com',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Phone (Optional)'),
          '+971 55 987 6543',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Designation *'),
          'Regional HSE & Operations Lead',
        );

        // Select multiple sites for Department 1 (HSE)
        await tester.tap(find.text('Platform Alpha').first);
        await tester.tap(find.text('Platform Bravo').first);
        await tester.pumpAndSettle();

        // Passwords
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Password *'),
          'SecretPassword123!',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirm Password *'),
          'SecretPassword123!',
        );

        // Submit
        await tester.ensureVisible(find.text('Submit Account Request'));
        await tester.tap(find.text('Submit Account Request'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        // Dialog appears
        expect(find.text('Manager Request Validated'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('David Miller'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('david.miller@company.com'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Regional HSE & Operations Lead'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Configured Management Scopes (2):'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('HSE / Safety / Platform Alpha'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('HSE / Safety / Platform Bravo'),
          ),
          findsOneWidget,
        );

        // Close dialog
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();

        expect(find.text('Manager Request Validated'), findsNothing);
      },
    );
  });

  group('ManagerAccountSetupScreen - Theme & Responsive Tests', () {
    testWidgets('Renders cleanly in Dark Theme mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget(themeMode: ThemeMode.dark));
      await tester.pumpAndSettle();

      expect(find.text('Create Manager Account'), findsOneWidget);
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

        expect(find.text('Create Manager Account'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });
}
