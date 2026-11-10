import 'package:action_flow/features/auth/models/manager_scope_item.dart';
import 'package:action_flow/features/auth/screens/email_verification_screen.dart';
import 'package:action_flow/features/auth/screens/manager_account_setup_screen.dart';
import 'package:action_flow/features/auth/screens/staff_account_setup_screen.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeAuthService extends AuthService {
  FakeAuthService({
    this.shouldFailOrg = false,
    this.signUpResult,
    List<DepartmentOption>? departments,
    List<SiteOption>? sites,
    List<TeamOption>? teams,
  }) : _depts = departments ?? defaultDepartments,
       _sitesList = sites ?? defaultSites,
       _teamsList = teams ?? defaultTeams,
       super.forTesting();

  bool shouldFailOrg;
  AuthSignUpResult? signUpResult;
  final List<DepartmentOption> _depts;
  final List<SiteOption> _sitesList;
  final List<TeamOption> _teamsList;

  int signUpCallCount = 0;
  String? lastEmail;
  String? lastPassword;
  Map<String, dynamic>? lastData;

  @override
  bool get hasClient => true;

  @override
  Future<List<DepartmentOption>> fetchDepartments({
    String? organizationId,
    bool fallbackToDefaults = false,
  }) async {
    if (shouldFailOrg) {
      throw Exception('Network error fetching departments');
    }
    return _depts;
  }

  @override
  Future<List<SiteOption>> fetchSites({
    String? organizationId,
    bool fallbackToDefaults = false,
  }) async {
    if (shouldFailOrg) {
      throw Exception('Network error fetching sites');
    }
    return _sitesList;
  }

  @override
  Future<List<TeamOption>> fetchTeams({
    String? organizationId,
    bool fallbackToDefaults = false,
  }) async {
    if (shouldFailOrg) {
      throw Exception('Network error fetching teams');
    }
    return _teamsList;
  }

  @override
  Future<AuthSignUpResult> signUp({
    required String email,
    required String password,
    required Map<String, dynamic> data,
  }) async {
    signUpCallCount++;
    lastEmail = email;
    lastPassword = password;
    lastData = data;

    if (signUpResult != null) {
      return signUpResult!;
    }

    final fakeUser = User(
      id: 'mock-user-uuid-123',
      appMetadata: {},
      userMetadata: data,
      aud: 'authenticated',
      createdAt: DateTime.now().toIso8601String(),
      email: email,
    );

    return AuthSignUpResult.success(user: fakeUser);
  }
}

void main() {
  group('AuthService - Metadata Payload Builders', () {
    test('buildStaffSignupMetadata constructs exact payload without excluded fields', () {
      final meta = AuthService.buildStaffSignupMetadata(
        fullName: 'Jane Doe',
        phone: '+971 50 123 4567',
        designation: 'Safety Officer',
        departmentId: 'dept-uuid-001',
        siteId: 'site-uuid-002',
        teamId: 'team-uuid-003',
      );

      expect(meta['full_name'], 'Jane Doe');
      expect(meta['phone'], '+971 50 123 4567');
      expect(meta['designation'], 'Safety Officer');
      expect(meta['requested_role'], 'staff');
      expect(meta['department_id'], 'dept-uuid-001');
      expect(meta['site_id'], 'site-uuid-002');
      expect(meta['team_id'], 'team-uuid-003');

      // Verify excluded fields
      expect(meta.containsKey('supervisor_id'), isFalse);
      expect(meta.containsKey('manager_id'), isFalse);
      expect(meta.containsKey('scopes'), isFalse);
      expect(meta.containsKey('admin'), isFalse);
      expect(meta.containsKey('email'), isFalse);
    });

    test('buildStaffSignupMetadata omits team_id when null', () {
      final meta = AuthService.buildStaffSignupMetadata(
        fullName: 'Jane Doe',
        phone: null,
        designation: 'Safety Officer',
        departmentId: 'dept-uuid-001',
        siteId: 'site-uuid-002',
        teamId: null,
      );

      expect(meta['phone'], isNull);
      expect(meta['team_id'], isNull);
      expect(meta.containsKey('team_id'), isFalse);
      expect(meta['requested_role'], 'staff');
    });

    test('buildManagerSignupMetadata constructs multi-scope payload without excluded fields', () {
      final scopes = [
        const ManagerScopeItem(
          departmentId: 'dept-uuid-001',
          departmentName: 'HSE',
          siteId: 'site-uuid-001',
          siteName: 'Plant A',
        ),
        const ManagerScopeItem(
          departmentId: 'dept-uuid-001',
          departmentName: 'HSE',
          siteId: 'site-uuid-002',
          siteName: 'Plant B',
        ),
      ];

      final meta = AuthService.buildManagerSignupMetadata(
        fullName: 'John Smith',
        phone: '+971 50 987 6543',
        designation: 'Operations Lead',
        scopes: scopes,
      );

      expect(meta['full_name'], 'John Smith');
      expect(meta['phone'], '+971 50 987 6543');
      expect(meta['designation'], 'Operations Lead');
      expect(meta['requested_role'], 'manager');

      final scopesList = meta['scopes'] as List;
      expect(scopesList.length, 2);
      expect(scopesList[0], {
        'department_id': 'dept-uuid-001',
        'site_id': 'site-uuid-001',
      });
      expect(scopesList[1], {
        'department_id': 'dept-uuid-001',
        'site_id': 'site-uuid-002',
      });

      // Verify excluded fields
      expect(meta.containsKey('team_id'), isFalse);
      expect(meta.containsKey('supervisor_id'), isFalse);
      expect(meta.containsKey('manager_id'), isFalse);
      expect(meta.containsKey('admin'), isFalse);
      expect(meta.containsKey('email'), isFalse);
    });
  });

  group('AuthService - Error Sanitization', () {
    test('sanitizes duplicate email errors to friendly guidance', () {
      final msg = AuthService.sanitizeSignUpError('User already registered');
      expect(
        msg,
        'An account with this email already exists. Please sign in or use a different email.',
      );

      final msg2 = AuthService.sanitizeSignUpError(
        'duplicate key value violates unique constraint "users_email_key"',
      );
      expect(
        msg2,
        'An account with this email already exists. Please sign in or use a different email.',
      );
    });

    test('sanitizes weak password errors', () {
      final msg = AuthService.sanitizeSignUpError(
        'Password should be at least 6 characters',
      );
      expect(msg, 'Password must be at least 6 characters long.');
    });

    test('sanitizes rate limit errors', () {
      final msg = AuthService.sanitizeSignUpError(
        'over_email_send_rate_limit: rate limit exceeded',
      );
      expect(msg, 'Too many attempts. Please wait a moment and try again.');
    });

    test('sanitizes database trigger & Postgres internal errors without leaking details', () {
      final msg = AuthService.sanitizeSignUpError(
        'Postgres error: trigger trg_on_auth_user_created execution failed: 42P01',
      );
      expect(msg, contains('Unable to complete registration'));
      expect(msg, isNot(contains('trg_on_auth_user_created')));
      expect(msg, isNot(contains('Postgres')));
      expect(msg, isNot(contains('42P01')));
    });

    test('sanitizes organization validation errors', () {
      final msg = AuthService.sanitizeSignUpError(
        'Invalid department_id: department not exist',
      );
      expect(
        msg,
        'The selected department is invalid or inactive. Please select an active department.',
      );
    });
  });

  group('StaffAccountSetupScreen - Real Supabase Signup Flow', () {
    testWidgets(
      'Org loading failure displays retry banner and blocks form submission',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeAuth = FakeAuthService(shouldFailOrg: true);

        await tester.pumpWidget(
          MaterialApp(home: StaffAccountSetupScreen(authService: fakeAuth)),
        );
        await tester.pumpAndSettle();

        // Verify retry banner is displayed
        expect(
          find.byKey(const ValueKey('staff_retry_org_button')),
          findsOneWidget,
        );
        expect(
          find.text(
            'Unable to load organization data from server. Please check your connection and tap Retry.',
          ),
          findsOneWidget,
        );

        // Attempt to submit
        await tester.ensureVisible(
          find.byKey(const ValueKey('staff_submit_button')),
        );
        await tester.tap(find.byKey(const ValueKey('staff_submit_button')));
        await tester.pumpAndSettle();

        // Form validation error for organization data
        expect(
          find.text(
            'Organization data is unavailable. Please check your connection and tap Retry.',
          ),
          findsOneWidget,
        );

        // Now heal the error and tap Retry
        fakeAuth.shouldFailOrg = false;
        await tester.tap(find.byKey(const ValueKey('staff_retry_org_button')));
        await tester.pumpAndSettle();

        // Error banner gone
        expect(
          find.byKey(const ValueKey('staff_retry_org_button')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Staff signup success navigates to EmailVerificationScreen with email',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeAuth = FakeAuthService();

        await tester.pumpWidget(
          MaterialApp(
            home: StaffAccountSetupScreen(
              authService: fakeAuth,
              initialDepartments: [
                const DepartmentOption(
                  id: 'dept-real-uuid',
                  name: 'Operations & Maintenance',
                  code: 'OPS',
                ),
              ],
              initialSites: [
                const SiteOption(
                  id: 'site-real-uuid',
                  name: 'Main Plant',
                  code: 'MPL',
                ),
              ],
              initialTeams: [
                const TeamOption(
                  id: 'team-real-uuid',
                  name: 'Operations Team 1',
                  departmentId: 'dept-real-uuid',
                  isActive: true,
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Fill in Section 1
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Full Name *'),
          'Sarah Jenkins',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Email *'),
          'sarah.jenkins@example.com',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Designation *'),
          'Safety Specialist',
        );

        // Fill in Section 3
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Password *'),
          'ActionFlow!2026',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirm Password *'),
          'ActionFlow!2026',
        );

        // Submit
        await tester.ensureVisible(
          find.byKey(const ValueKey('staff_submit_button')),
        );
        await tester.tap(find.byKey(const ValueKey('staff_submit_button')));
        await tester.pumpAndSettle();

        // Verify Review dialog appears
        expect(find.text('Review Staff Account Request'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Sarah Jenkins'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('sarah.jenkins@example.com'),
          ),
          findsOneWidget,
        );

        // Tap Continue in dialog
        await tester.tap(
          find.byKey(const ValueKey('staff_dialog_continue_button')),
        );
        await tester.pumpAndSettle();

        // Verify signUp was called with real organization UUIDs
        expect(fakeAuth.signUpCallCount, 1);
        expect(fakeAuth.lastEmail, 'sarah.jenkins@example.com');
        expect(fakeAuth.lastData?['department_id'], 'dept-real-uuid');
        expect(fakeAuth.lastData?['site_id'], 'site-real-uuid');
        expect(fakeAuth.lastData?['requested_role'], 'staff');

        // Verify navigation to EmailVerificationScreen
        expect(find.byType(EmailVerificationScreen), findsOneWidget);
        expect(find.text('sarah.jenkins@example.com'), findsOneWidget);
      },
    );

    testWidgets(
      'Staff signup failure shows error SnackBar and stays on screen',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeAuth = FakeAuthService(
          signUpResult: const AuthSignUpResult.failure(
            'An account with this email already exists. Please sign in or use a different email.',
            isDuplicateEmail: true,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: StaffAccountSetupScreen(
              authService: fakeAuth,
              initialDepartments: [
                const DepartmentOption(
                  id: 'dept-real-uuid',
                  name: 'Operations & Maintenance',
                  code: 'OPS',
                ),
              ],
              initialSites: [
                const SiteOption(
                  id: 'site-real-uuid',
                  name: 'Main Plant',
                  code: 'MPL',
                ),
              ],
              initialTeams: const [],
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Full Name *'),
          'Sarah Jenkins',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Email *'),
          'existing@example.com',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Designation *'),
          'Safety Specialist',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Password *'),
          'ActionFlow!2026',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirm Password *'),
          'ActionFlow!2026',
        );

        await tester.ensureVisible(
          find.byKey(const ValueKey('staff_submit_button')),
        );
        await tester.tap(find.byKey(const ValueKey('staff_submit_button')));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('staff_dialog_continue_button')),
        );
        await tester.pumpAndSettle();

        // Stays on StaffAccountSetupScreen and shows SnackBar
        expect(find.byType(StaffAccountSetupScreen), findsOneWidget);
        expect(
          find.text(
            'An account with this email already exists. Please sign in or use a different email.',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('ManagerAccountSetupScreen - Real Supabase Signup Flow', () {
    testWidgets(
      'Org loading failure displays retry banner and blocks form submission',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeAuth = FakeAuthService(shouldFailOrg: true);

        await tester.pumpWidget(
          MaterialApp(home: ManagerAccountSetupScreen(authService: fakeAuth)),
        );
        await tester.pumpAndSettle();

        // Verify retry banner is displayed
        expect(
          find.byKey(const ValueKey('manager_retry_org_button')),
          findsOneWidget,
        );
        expect(
          find.text(
            'Unable to load organization data from server. Please check your connection and tap Retry.',
          ),
          findsOneWidget,
        );

        // Attempt to submit
        await tester.ensureVisible(find.text('Submit Account Request'));
        await tester.tap(find.text('Submit Account Request'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Organization data is unavailable. Please check your connection and tap Retry.',
          ),
          findsOneWidget,
        );

        // Heal error and tap Retry
        fakeAuth.shouldFailOrg = false;
        await tester.tap(
          find.byKey(const ValueKey('manager_retry_org_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('manager_retry_org_button')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Manager signup success navigates to EmailVerificationScreen with email',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeAuth = FakeAuthService();

        await tester.pumpWidget(
          MaterialApp(
            home: ManagerAccountSetupScreen(
              authService: fakeAuth,
              initialDepartments: [
                const DepartmentOption(
                  id: 'dept-real-001',
                  name: 'HSE',
                  code: 'HSE',
                ),
              ],
              initialSites: [
                const SiteOption(
                  id: 'site-real-001',
                  name: 'Offshore Alpha',
                  code: 'OA',
                ),
                const SiteOption(
                  id: 'site-real-002',
                  name: 'Offshore Bravo',
                  code: 'OB',
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Fill in Section 1
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Full Name *'),
          'David Miller',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Email *'),
          'david.miller@example.com',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Designation *'),
          'Operations Manager',
        );

        // Select sites in Section 2
        await tester.tap(find.text('Offshore Alpha'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Offshore Bravo'));
        await tester.pumpAndSettle();

        // Fill in Section 3
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Password *'),
          'ActionFlow!2026',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirm Password *'),
          'ActionFlow!2026',
        );

        // Submit
        await tester.ensureVisible(find.text('Submit Account Request'));
        await tester.tap(find.text('Submit Account Request'));
        await tester.pumpAndSettle();

        // Verify confirmation dialog
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
            matching: find.text('david.miller@example.com'),
          ),
          findsOneWidget,
        );
        expect(find.text('Configured Management Scopes (2):'), findsOneWidget);

        // Tap Continue in dialog
        await tester.tap(
          find.byKey(const ValueKey('manager_dialog_continue_button')),
        );
        await tester.pumpAndSettle();

        // Verify signUp called with real UUIDs and scopes array
        expect(fakeAuth.signUpCallCount, 1);
        expect(fakeAuth.lastEmail, 'david.miller@example.com');
        expect(fakeAuth.lastData?['requested_role'], 'manager');
        final scopes = fakeAuth.lastData?['scopes'] as List;
        expect(scopes.length, 2);
        expect(scopes[0]['department_id'], 'dept-real-001');
        expect(scopes[0]['site_id'], 'site-real-001');
        expect(scopes[1]['department_id'], 'dept-real-001');
        expect(scopes[1]['site_id'], 'site-real-002');

        // Verify navigation to EmailVerificationScreen
        expect(find.byType(EmailVerificationScreen), findsOneWidget);
        expect(find.text('david.miller@example.com'), findsOneWidget);
      },
    );

    testWidgets(
      'Manager signup failure shows error SnackBar and stays on screen',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeAuth = FakeAuthService(
          signUpResult: const AuthSignUpResult.failure(
            'Network connection error. Please check your internet connection and try again.',
            isNetworkError: true,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ManagerAccountSetupScreen(
              authService: fakeAuth,
              initialDepartments: [
                const DepartmentOption(
                  id: 'dept-real-001',
                  name: 'HSE',
                  code: 'HSE',
                ),
              ],
              initialSites: [
                const SiteOption(
                  id: 'site-real-001',
                  name: 'Offshore Alpha',
                  code: 'OA',
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Full Name *'),
          'David Miller',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Email *'),
          'david.miller@example.com',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Designation *'),
          'Operations Manager',
        );

        await tester.tap(find.text('Offshore Alpha'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Password *'),
          'ActionFlow!2026',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirm Password *'),
          'ActionFlow!2026',
        );

        await tester.ensureVisible(find.text('Submit Account Request'));
        await tester.tap(find.text('Submit Account Request'));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('manager_dialog_continue_button')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ManagerAccountSetupScreen), findsOneWidget);
        expect(
          find.text(
            'Network connection error. Please check your internet connection and try again.',
          ),
          findsOneWidget,
        );
      },
    );
  });
}
