import 'package:action_flow/features/dashboard/admin_dashboard/screens/admin_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/settings/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserProfile Model Unit Tests', () {
    test('Calculates initials accurately across various user profiles', () {
      final manager = UserProfile.mockManager();
      expect(manager.initials, 'M');

      final staff = UserProfile.mockStaff();
      expect(staff.initials, 'RK');

      final admin = UserProfile.mockAdmin();
      expect(admin.initials, 'AD');

      const singleName = UserProfile(
        id: 'U-1',
        name: 'Alexander',
        email: 'alex@flow.internal',
        phone: '123',
        designation: 'Engineer',
        department: 'Tech',
        site: 'Site A',
        role: 'Staff',
      );
      expect(singleName.initials, 'AL');

      const customName = UserProfile(
        id: 'U-2',
        name: 'Sarah Jenkins',
        email: 'sj@flow.internal',
        phone: '123',
        designation: 'Manager',
        department: 'HSE',
        site: 'Site A',
        role: 'Manager',
      );
      expect(customName.initials, 'SJ');
    });

    test('copyWith properly updates permitted fields while retaining immutable ones', () {
      final initial = UserProfile.mockManager();
      final updated = initial.copyWith(
        name: 'Sarah M. Jenkins',
        phone: '+1 (555) 000-1111',
        designation: 'Senior HSSE Manager',
      );

      expect(updated.name, 'Sarah M. Jenkins');
      expect(updated.phone, '+1 (555) 000-1111');
      expect(updated.designation, 'Senior HSSE Manager');
      expect(updated.id, initial.id);
      expect(updated.department, initial.department);
      expect(updated.site, initial.site);
      expect(updated.role, initial.role);
    });
  });

  group('Manager Profile & Settings Portal Tests', () {
    Widget buildManagerPortal({Size size = const Size(1280, 800)}) {
      return MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: const ManagerDashboardScreen(),
        ),
      );
    }

    testWidgets(
      'Manager Profile view renders identity, contact details and permissions',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildManagerPortal());
        await tester.pumpAndSettle();

        // Navigate to My Profile (Sidebar item)
        final profileNav = find.text('My Profile');
        expect(profileNav, findsOneWidget);
        await tester.tap(profileNav);
        await tester.pumpAndSettle();

        // Profile View assertions
        expect(find.text('Manager Profile'), findsOneWidget);
        expect(find.text('Manager'), findsWidgets);
        expect(find.text('MGR-1042'), findsOneWidget);
        expect(find.text('manager@actionflow.internal'), findsOneWidget);
        expect(find.text('+1 (555) 234-5678'), findsOneWidget);
        expect(find.text('Operations Lead'), findsWidgets);
        expect(find.text('Health & Safety'), findsWidgets);
        expect(find.text('North Plant Facility'), findsWidgets);
        expect(find.text('Active'), findsWidgets);

        // Permissions list
        expect(find.text('Create & Assign Actions'), findsOneWidget);
        expect(find.text('Approve Action Closures & Evidence'), findsOneWidget);
        expect(
          find.text('Escalate SLA Breaches & Overdue Items'),
          findsOneWidget,
        );
        expect(find.text('Export Compliance & Audit Reports'), findsOneWidget);

        // Edit Profile button
        expect(find.text('Edit Profile'), findsOneWidget);
      },
    );

    testWidgets(
      'Manager Edit Profile dialog allows editing permitted fields and protects governance fields',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildManagerPortal());
        await tester.pumpAndSettle();

        // Open Profile view
        await tester.tap(find.text('My Profile'));
        await tester.pumpAndSettle();

        // Open Edit Profile Dialog
        await tester.tap(find.text('Edit Profile'));
        await tester.pumpAndSettle();

        // Dialog assertions
        expect(find.text('Edit Profile Information'), findsOneWidget);
        expect(find.text('PROTECTED'), findsOneWidget);
        expect(
          find.text('Organizational Governance (Read-Only)'),
          findsOneWidget,
        );
        expect(find.text('Employee ID'), findsWidgets);
        expect(find.text('MGR-1042'), findsWidgets);

        // Edit Full Name field
        final nameField = find.byType(TextFormField).at(0);
        expect(nameField, findsOneWidget);
        await tester.enterText(nameField, 'Sarah Jenkins');

        // Edit Phone field
        final phoneField = find.byType(TextFormField).at(1);
        expect(phoneField, findsOneWidget);
        await tester.enterText(phoneField, '+1 (555) 777-8888');

        // Save Changes
        await tester.tap(find.text('Save Changes'));
        await tester.pumpAndSettle();

        // Verify updated values in profile view
        expect(find.text('Sarah Jenkins'), findsWidgets);
        expect(find.text('+1 (555) 777-8888'), findsOneWidget);
      },
    );

    testWidgets(
      'Manager Settings view renders theme switcher, notification triggers, and table density options',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildManagerPortal());
        await tester.pumpAndSettle();

        // Navigate to Settings tab (Index 9)
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();

        // Verify Settings sections
        expect(find.text('Appearance & Theme Mode'), findsOneWidget);
        expect(find.text('Light Theme'), findsOneWidget);
        expect(find.text('Dark Theme'), findsOneWidget);
        expect(find.text('System Default'), findsOneWidget);

        expect(find.text('Notification & Reminder Triggers'), findsOneWidget);
        expect(find.text('Action Due Reminders'), findsOneWidget);
        expect(find.text('Overdue Escalation Alerts'), findsOneWidget);
        expect(find.text('Daily Action Summary Digest'), findsOneWidget);
        expect(find.text('Email Dispatch Schedule'), findsOneWidget);

        expect(find.text('Workspace & Table Density'), findsOneWidget);
        expect(find.text('Compact Table Rows'), findsOneWidget);

        // Save preferences action
        final saveBtn = find.text('Save Portal Preferences');
        expect(saveBtn, findsOneWidget);
        await tester.ensureVisible(saveBtn);
        await tester.pumpAndSettle();
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();
        expect(
          find.text('Manager portal preferences saved successfully.'),
          findsOneWidget,
        );
      },
    );
  });

  group('Staff Profile & Settings Portal Tests', () {
    Widget buildStaffPortal({Size size = const Size(1280, 800)}) {
      return MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: const WorkerDashboardScreen(),
        ),
      );
    }

    testWidgets(
      'Staff Profile view displays contact info, supervisor, certifications and performance summary',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildStaffPortal());
        await tester.pumpAndSettle();

        // Navigate to Profile tab
        await tester.tap(find.text('Profile'));
        await tester.pumpAndSettle();

        // Staff details assertions
        expect(find.text('Staff Profile'), findsOneWidget);
        expect(find.text('R. Kumar'), findsWidgets);
        expect(find.text('EMP-2049'), findsOneWidget);
        expect(find.text('r.kumar@actionflow.internal'), findsOneWidget);
        expect(find.text('Field Operations'), findsWidgets);
        expect(find.text('Operations / Maintenance'), findsWidgets);
        expect(find.text('Direct Supervisor'), findsOneWidget);
        expect(find.text('Sarah Jenkins (HSSE Manager)'), findsOneWidget);
        expect(find.text('Safety Certification'), findsOneWidget);
        expect(
          find.textContaining('Level 3 HSSE Site Qualified'),
          findsOneWidget,
        );

        // Performance Summary stats
        expect(find.text('Action Performance Summary'), findsOneWidget);
        expect(find.text('Total Actions'), findsOneWidget);
        expect(find.text('In Progress'), findsWidgets);
        expect(find.text('Completed'), findsWidgets);
        expect(find.text('Overdue'), findsWidgets);
      },
    );

    testWidgets(
      'Staff Edit Profile dialog prevents designation modification for standard staff',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildStaffPortal());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Profile'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Edit Profile'));
        await tester.pumpAndSettle();

        // Read-only designation row should exist under Protected Section
        expect(find.text('Designation / Role Title'), findsOneWidget);
        expect(find.text('PROTECTED'), findsOneWidget);

        // Update phone number
        final phoneField = find.byType(TextFormField).at(1);
        expect(phoneField, findsOneWidget);
        await tester.enterText(phoneField, '+1 (555) 999-8888');

        await tester.tap(find.text('Save Changes'));
        await tester.pumpAndSettle();

        expect(find.text('+1 (555) 999-8888'), findsOneWidget);
      },
    );

    testWidgets(
      'Staff Settings view renders Theme options and staff reminder toggles',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildStaffPortal());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();

        expect(find.text('Preferences & Settings'), findsOneWidget);
        expect(find.text('Appearance & Theme Mode'), findsOneWidget);
        expect(
          find.text('Notification & Task Alert Preferences'),
          findsOneWidget,
        );
        expect(find.text('Action Due Reminders'), findsOneWidget);
        expect(find.text('Manager Feedback Alerts'), findsOneWidget);
        expect(find.text('Daily Task Summary Email'), findsOneWidget);

        final saveBtn = find.text('Save Preferences');
        expect(saveBtn, findsOneWidget);
        await tester.ensureVisible(saveBtn);
        await tester.pumpAndSettle();
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();
        expect(
          find.text('Staff preferences saved successfully.'),
          findsOneWidget,
        );
      },
    );
  });

  group('Admin Profile Modal & System Settings Tests', () {
    Widget buildAdminPortal({Size size = const Size(1280, 800)}) {
      return MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: const AdminDashboardScreen(),
        ),
      );
    }

    testWidgets(
      'Clicking Admin Profile Pill opens AdminProfileDialog with clearance and governance badge',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildAdminPortal());
        await tester.pumpAndSettle();

        // Find Admin Profile Pill in header
        final profilePill = find.text('System Administrator');
        expect(profilePill, findsOneWidget);
        await tester.tap(profilePill);
        await tester.pumpAndSettle();

        // Admin Profile Dialog assertions
        expect(
          find.text('Administrator Identity & Governance'),
          findsOneWidget,
        );
        expect(find.text('SUPER ADMIN'), findsOneWidget);
        expect(find.text('ADM-0001'), findsOneWidget);
        expect(find.text('admin@actionflow.internal'), findsOneWidget);
        expect(find.text('2FA Enforced • Active'), findsOneWidget);
        expect(find.text('Full System Configuration Access'), findsOneWidget);
        expect(find.text('Security Policy & 2FA Enforcement'), findsOneWidget);
      },
    );

    testWidgets(
      'Admin System Settings renders theme selection, security toggles and timeout parameters',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildAdminPortal());
        await tester.pumpAndSettle();

        // Navigate to System Settings (tab 9)
        await tester.tap(find.text('System Settings'));
        await tester.pumpAndSettle();

        expect(
          find.text('System Preferences & Security Governance'),
          findsOneWidget,
        );
        expect(find.text('Appearance & Theme Mode'), findsOneWidget);
        expect(find.text('Light Theme'), findsOneWidget);
        expect(find.text('Dark Theme'), findsOneWidget);
        expect(find.text('System Default'), findsOneWidget);

        expect(find.text('Security & Access Policies'), findsOneWidget);
        expect(
          find.text(
            'Enforce Multi-Factor Authentication (2FA) for Managers & Admins',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Allow Self-Registration for External Staff'),
          findsOneWidget,
        );
        expect(
          find.text('Automated Overdue Action Escalation Alerts'),
          findsOneWidget,
        );
        expect(find.text('Inactivity Session Timeout'), findsOneWidget);

        final saveBtn = find.text('Save System Preferences');
        expect(saveBtn, findsOneWidget);
        await tester.ensureVisible(saveBtn);
        await tester.pumpAndSettle();
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();
        expect(
          find.text('System configuration preferences saved successfully.'),
          findsOneWidget,
        );
      },
    );
  });

  group('Standalone SettingsScreen & Reusable Widgets Tests', () {
    testWidgets(
      'Standalone SettingsScreen functions with ThemeController and saves preferences',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
        await tester.pumpAndSettle();

        expect(find.text('Application Settings'), findsOneWidget);
        expect(find.text('Appearance & Theme'), findsOneWidget);
        expect(
          find.text('Notification & Reminder Preferences'),
          findsOneWidget,
        );
        expect(find.text('Display & Table Density'), findsOneWidget);

        final saveBtn = find.text('Save Preferences');
        expect(saveBtn, findsOneWidget);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();
        expect(
          find.text('Settings and preferences saved successfully.'),
          findsOneWidget,
        );
      },
    );
  });

  group('Responsive Breakpoint Verification (1200px, 768px, 400px, 320px)', () {
    testWidgets(
      'Manager Profile & Settings render without RenderFlex overflows across breakpoints',
      (tester) async {
        for (final size in [
          const Size(1200, 800),
          const Size(768, 1024),
          const Size(400, 800),
          const Size(320, 600),
        ]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(size: size),
                child: const ManagerDashboardScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Overflow detected at size $size',
          );
        }

        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      },
    );

    testWidgets(
      'Staff Profile & Settings render without RenderFlex overflows across breakpoints',
      (tester) async {
        for (final size in [
          const Size(1200, 800),
          const Size(768, 1024),
          const Size(400, 800),
          const Size(320, 600),
        ]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(size: size),
                child: const WorkerDashboardScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Overflow detected at size $size',
          );
        }

        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      },
    );
  });
}
