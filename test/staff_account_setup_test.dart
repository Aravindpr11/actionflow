import 'package:action_flow/features/auth/screens/staff_account_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildTestWidget({ThemeMode themeMode = ThemeMode.light}) {
    return MaterialApp(
      themeMode: themeMode,
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: const StaffAccountSetupScreen(),
    );
  }

  Finder findTeamDropdown() => find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('staff_team_dropdown'),
  );

  group('StaffAccountSetupScreen - Content & Structure Tests', () {
    testWidgets('Staff form renders all required sections and fields', (
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

      // Screen Title & Subtitle
      expect(find.text('Create Staff Account'), findsOneWidget);
      expect(
        find.text(
          'Enter your personal details and select your department, site, and optional team.',
        ),
        findsOneWidget,
      );

      // Section 1: Personal Information
      expect(find.text('PERSONAL INFORMATION'), findsOneWidget);
      expect(find.text('Full Name *'), findsOneWidget);
      expect(find.text('Email *'), findsOneWidget);
      expect(find.text('Phone (Optional)'), findsOneWidget);
      expect(find.text('Designation *'), findsOneWidget);

      // Section 2: Organization
      expect(find.text('ORGANIZATION'), findsOneWidget);
      expect(find.text('Department *'), findsOneWidget);
      expect(find.text('Site *'), findsOneWidget);
      expect(find.text('Team / Unit (Optional)'), findsOneWidget);

      // Section 3: Password
      expect(find.text('PASSWORD'), findsOneWidget);
      expect(find.text('Password *'), findsOneWidget);
      expect(find.text('Confirm Password *'), findsOneWidget);

      // Bottom Buttons
      expect(find.byKey(const ValueKey('staff_back_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('staff_submit_button')), findsOneWidget);
      expect(find.text('Submit Account Request'), findsOneWidget);

      // Strictly verify Supervisor, Management Scope, and Admin are NOT present
      expect(find.text('Supervisor'), findsNothing);
      expect(find.text('Supervisor (Optional)'), findsNothing);
      expect(find.text('MANAGEMENT SCOPE'), findsNothing);
      expect(find.text('Add another department'), findsNothing);
      expect(find.text('Admin'), findsNothing);
      expect(find.text('Administrator'), findsNothing);
    });
  });

  group('StaffAccountSetupScreen - Validation Tests', () {
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
      await tester.ensureVisible(
        find.byKey(const ValueKey('staff_submit_button')),
      );
      await tester.tap(find.byKey(const ValueKey('staff_submit_button')));
      await tester.pumpAndSettle();

      // Verify form validators triggered
      expect(find.text('Please enter your full name'), findsOneWidget);
      expect(find.text('Please enter your email address'), findsOneWidget);
      expect(find.text('Please enter your designation'), findsOneWidget);
      expect(find.text('Please enter a password'), findsOneWidget);
      expect(find.text('Please confirm your password'), findsOneWidget);
    });

    testWidgets('Email format and password mismatch validation', (
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
        'invalid-email-format',
      );

      // Enter mismatched passwords
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password *'),
        'SecurePassword123!',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm Password *'),
        'Mismatch123!',
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('staff_submit_button')),
      );
      await tester.tap(find.byKey(const ValueKey('staff_submit_button')));
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
        '12345',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm Password *'),
        '12345',
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('staff_submit_button')),
      );
      await tester.tap(find.byKey(const ValueKey('staff_submit_button')));
      await tester.pumpAndSettle();

      expect(
        find.text('Password must be at least 6 characters'),
        findsOneWidget,
      );
    });
  });

  group('StaffAccountSetupScreen - Organization & Team Filtering Tests', () {
    testWidgets('Team dropdown shows teams for selected department (HSE)', (
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

      // By default, HSE / Safety is selected.
      // Open the Team dropdown
      final teamDropdown = findTeamDropdown();
      expect(teamDropdown, findsOneWidget);

      await tester.tap(teamDropdown);
      await tester.pumpAndSettle();

      // Should find HSE teams in menu
      expect(find.text('HSSE Audit & Compliance Team').last, findsOneWidget);
      expect(
        find.text('Field Safety & Emergency Response').last,
        findsOneWidget,
      );

      // Select 'Field Safety & Emergency Response'
      await tester.tap(find.text('Field Safety & Emergency Response').last);
      await tester.pumpAndSettle();

      // Selected team is displayed
      expect(find.text('Field Safety & Emergency Response'), findsOneWidget);
    });

    testWidgets(
      'Changing department clears selected team when team does not belong to new department',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // 1. Select a team in HSE
        final teamDropdown = findTeamDropdown();
        await tester.tap(teamDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('HSSE Audit & Compliance Team').last);
        await tester.pumpAndSettle();

        expect(find.text('HSSE Audit & Compliance Team'), findsOneWidget);

        // 2. Change Department to Maintenance (dept-maint)
        final deptDropdown = find.byKey(const ValueKey('staff_dept_dropdown'));
        await tester.tap(deptDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Maintenance').last);
        await tester.pumpAndSettle();

        // 3. Verify the previous HSE team was cleared
        expect(find.text('HSSE Audit & Compliance Team'), findsNothing);

        // 4. Verify the Team dropdown now offers Maintenance teams
        final maintTeamDropdown = findTeamDropdown();
        await tester.tap(maintTeamDropdown);
        await tester.pumpAndSettle();

        expect(find.text('Mechanical Maintenance Unit').last, findsOneWidget);
        expect(find.text('Electrical & Instrumentation').last, findsOneWidget);

        // Tap outside / select Mechanical Maintenance Unit
        await tester.tap(find.text('Mechanical Maintenance Unit').last);
        await tester.pumpAndSettle();

        expect(find.text('Mechanical Maintenance Unit'), findsOneWidget);
      },
    );

    testWidgets(
      'Selecting department with no teams shows "No teams available for this department"',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // Change Department to Logistics (dept-log) which has no teams
        final deptDropdown = find.byKey(const ValueKey('staff_dept_dropdown'));
        await tester.tap(deptDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Logistics').last);
        await tester.pumpAndSettle();

        // Team dropdown should be replaced by the fallback notice
        expect(findTeamDropdown(), findsNothing);
        expect(
          find.text('No teams available for this department'),
          findsOneWidget,
        );
      },
    );
  });

  group('StaffAccountSetupScreen - Preview Dialog & Actions Tests', () {
    testWidgets(
      'Valid submission displays review dialog with all details and handles Edit and Continue',
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
          'Sarah Jenkins',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Email *'),
          'sarah.j@company.com',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Phone (Optional)'),
          '+971 50 123 4567',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Designation *'),
          'Safety Officer',
        );

        // Select team
        final teamDropdown = findTeamDropdown();
        await tester.tap(teamDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Field Safety & Emergency Response').last);
        await tester.pumpAndSettle();

        // Enter password
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Password *'),
          'SecretPassword123!',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirm Password *'),
          'SecretPassword123!',
        );

        // Submit form
        await tester.ensureVisible(
          find.byKey(const ValueKey('staff_submit_button')),
        );
        await tester.tap(find.byKey(const ValueKey('staff_submit_button')));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        // Dialog should be open
        expect(find.text('Review Staff Account Request'), findsOneWidget);

        // Content in dialog
        final dialogFinder = find.byType(AlertDialog);
        expect(
          find.descendant(
            of: dialogFinder,
            matching: find.text('Sarah Jenkins'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: dialogFinder,
            matching: find.text('sarah.j@company.com'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: dialogFinder,
            matching: find.text('+971 50 123 4567'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: dialogFinder,
            matching: find.text('Safety Officer'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: dialogFinder,
            matching: find.text('HSE / Safety'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: dialogFinder,
            matching: find.text('Platform Alpha'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: dialogFinder,
            matching: find.text('Field Safety & Emergency Response'),
          ),
          findsOneWidget,
        );

        // Approval notice
        expect(
          find.descendant(
            of: dialogFinder,
            matching: find.text(
              'Your account will require email verification and Administrator approval.',
            ),
          ),
          findsOneWidget,
        );

        // Test Edit button
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();

        // Dialog closes, form fields remain intact
        expect(find.text('Review Staff Account Request'), findsNothing);
        expect(find.text('Sarah Jenkins'), findsOneWidget);

        // Submit again to test Continue button
        await tester.tap(find.byKey(const ValueKey('staff_submit_button')));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        expect(find.text('Review Staff Account Request'), findsOneWidget);
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // Dialog closes and auth error SnackBar is shown (since AuthService has no active client in test)
        expect(find.text('Review Staff Account Request'), findsNothing);
        expect(
          find.text(
            'Authentication service is currently unavailable. Please try again later.',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('StaffAccountSetupScreen - Theme & Responsive Tests', () {
    testWidgets('Renders cleanly in Dark Theme mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget(themeMode: ThemeMode.dark));
      await tester.pumpAndSettle();

      expect(find.text('Create Staff Account'), findsOneWidget);
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

        expect(find.text('Create Staff Account'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });
}
