import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/core/theme/theme_controller.dart';
import 'package:action_flow/features/dashboard/admin_dashboard/screens/admin_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/settings/screens/settings_screen.dart';
import 'package:action_flow/widgets/common/theme_toggle_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    ThemeController.instance.setThemeMode(ThemeMode.light);
  });

  group('1. ThemeController & Offline Persistence Tests', () {
    test('Defaults to ThemeMode.light and isDark is false', () {
      expect(ThemeController.instance.themeMode, ThemeMode.light);
      expect(ThemeController.instance.isDark, isFalse);
    });

    test('toggleTheme switches from light to dark, then dark to light', () {
      ThemeController.instance.toggleTheme();
      expect(ThemeController.instance.themeMode, ThemeMode.dark);
      expect(ThemeController.instance.isDark, isTrue);

      ThemeController.instance.toggleTheme();
      expect(ThemeController.instance.themeMode, ThemeMode.light);
      expect(ThemeController.instance.isDark, isFalse);
    });

    test('setThemeMode updates to system and notifies listeners', () {
      var notified = false;
      void listener() {
        notified = true;
      }

      ThemeController.instance.addListener(listener);
      ThemeController.instance.setThemeMode(ThemeMode.system);
      expect(ThemeController.instance.themeMode, ThemeMode.system);
      expect(notified, isTrue);
      ThemeController.instance.removeListener(listener);
    });
  });

  group('2. AppTheme ThemeData & Dynamic Helpers Tests', () {
    test('lightTheme and darkTheme definition tokens match specification', () {
      expect(AppTheme.lightTheme.brightness, Brightness.light);
      expect(
        AppTheme.lightTheme.scaffoldBackgroundColor,
        const Color(0xFFF1F5F9),
      );

      expect(AppTheme.darkTheme.brightness, Brightness.dark);
      expect(
        AppTheme.darkTheme.scaffoldBackgroundColor,
        const Color(0xFF0F172A),
      );
      expect(AppTheme.darkTheme.colorScheme.surface, const Color(0xFF1E293B));
    });

    testWidgets(
      'Dynamic helpers return appropriate colors based on context brightness',
      (tester) async {
        late BuildContext lightCtx;
        late BuildContext darkCtx;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.light,
            home: Builder(
              builder: (ctx) {
                lightCtx = ctx;
                return const SizedBox();
              },
            ),
          ),
        );

        expect(AppTheme.isDark(lightCtx), isFalse);
        expect(AppTheme.scaffoldBg(lightCtx), const Color(0xFFF1F5F9));
        expect(AppTheme.cardBg(lightCtx), const Color(0xFFFFFFFF));
        expect(AppTheme.textPrimary(lightCtx), const Color(0xFF0F172A));

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.dark,
            home: Builder(
              builder: (ctx) {
                darkCtx = ctx;
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(AppTheme.isDark(darkCtx), isTrue);
        expect(AppTheme.scaffoldBg(darkCtx), const Color(0xFF0F172A));
        expect(AppTheme.cardBg(darkCtx), const Color(0xFF1E293B));
        expect(AppTheme.textPrimary(darkCtx), const Color(0xFFF8FAFC));
      },
    );
  });

  group('3. ThemeToggleButton Widget Tests', () {
    testWidgets(
      'Renders dark_mode icon when in light mode and toggles to light_mode icon on tap',
      (tester) async {
        ThemeController.instance.setThemeMode(ThemeMode.light);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.light,
            home: const Scaffold(body: Center(child: ThemeToggleButton())),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
        expect(ThemeController.instance.isDark, isFalse);

        await tester.tap(find.byType(ThemeToggleButton));
        await tester.pumpAndSettle();

        expect(ThemeController.instance.isDark, isTrue);
        expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);
      },
    );
  });

  group('4. SettingsScreen Theme Selection Tests', () {
    testWidgets(
      'SettingsScreen lists theme tiles and allows selecting Dark Theme',
      (tester) async {
        ThemeController.instance.setThemeMode(ThemeMode.light);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.light,
            home: const SettingsScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Appearance & Theme'), findsOneWidget);
        expect(find.text('Light Theme'), findsOneWidget);
        expect(find.text('Dark Theme'), findsOneWidget);
        expect(find.text('System Default'), findsOneWidget);

        await tester.tap(find.text('Dark Theme'));
        await tester.pumpAndSettle();

        expect(ThemeController.instance.themeMode, ThemeMode.dark);
      },
    );
  });

  group('5. Manager Dashboard Responsive & Theme Rendering Tests', () {
    testWidgets(
      'ManagerDashboardScreen renders in Light Theme at 1200x800 without errors',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.light,
            home: const ManagerDashboardScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ManagerDashboardScreen), findsOneWidget);
        expect(find.byType(ThemeToggleButton), findsOneWidget);
      },
    );

    testWidgets(
      'ManagerDashboardScreen renders in Dark Theme at 768x1024 without errors',
      (tester) async {
        tester.view.physicalSize = const Size(768, 1024);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        ThemeController.instance.setThemeMode(ThemeMode.dark);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.dark,
            home: const ManagerDashboardScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ManagerDashboardScreen), findsOneWidget);
        expect(find.byType(ThemeToggleButton), findsOneWidget);
      },
    );
  });

  group('6. Worker Dashboard Responsive & Theme Rendering Tests', () {
    testWidgets('WorkerDashboardScreen renders in Light Theme at 1200x800', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.light,
          home: const WorkerDashboardScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(WorkerDashboardScreen), findsOneWidget);
      expect(find.byType(ThemeToggleButton), findsOneWidget);
    });

    testWidgets('WorkerDashboardScreen renders in Dark Theme at 400x800', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      ThemeController.instance.setThemeMode(ThemeMode.dark);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: const WorkerDashboardScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(WorkerDashboardScreen), findsOneWidget);
      expect(find.byType(ThemeToggleButton), findsOneWidget);
    });
  });

  group('7. Admin Dashboard Responsive & Theme Rendering Tests', () {
    testWidgets('AdminDashboardScreen renders in Light Theme at 1200x800', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.light,
          home: const AdminDashboardScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AdminDashboardScreen), findsOneWidget);
      expect(find.byType(ThemeToggleButton), findsOneWidget);
    });

    testWidgets('AdminDashboardScreen renders in Dark Theme at 768x1024', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      ThemeController.instance.setThemeMode(ThemeMode.dark);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: const AdminDashboardScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AdminDashboardScreen), findsOneWidget);
      expect(find.byType(ThemeToggleButton), findsOneWidget);
    });
  });

  group('8. Action Details Responsive & Theme Rendering Tests', () {
    testWidgets(
      'ActionDetailsScreen renders in Light and Dark themes with ThemeToggleButton',
      (tester) async {
        final sampleAction = ActionRecord(
          id: 'AC-1001',
          subject: 'Fix Pressure Relief Valve on Tank 4',
          actionRequired: 'Inspect and recalibrate safety relief valve',
          division: 'Downstream',
          category: 'Maintenance',
          site: 'North Plant',
          department: 'Operations',
          priority: 'High',
          status: 'In Progress',
          assignedTo: 'R. Kumar',
          assignedBy: 'S. Thomas',
          dateRaised: '2026-03-01',
          targetDate: '2026-03-15',
          lastFollowUpDate: '2026-03-08',
          percentComplete: 45,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.light,
            home: ActionDetailsScreen(action: sampleAction),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ActionDetailsScreen), findsOneWidget);
        expect(find.byType(ThemeToggleButton), findsOneWidget);
        expect(find.text('AC-1001'), findsAtLeast(1));

        // Switch to Dark Theme
        ThemeController.instance.setThemeMode(ThemeMode.dark);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.dark,
            home: ActionDetailsScreen(action: sampleAction),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ActionDetailsScreen), findsOneWidget);
        expect(find.byType(ThemeToggleButton), findsOneWidget);
      },
    );
  });
}
