import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/auth/data/mock_auth_store.dart';
import 'package:action_flow/features/auth/models/auth_models.dart';
import 'package:action_flow/features/auth/screens/account_status_screen.dart';
import 'package:action_flow/features/auth/screens/email_verification_screen.dart';
import 'package:action_flow/features/auth/screens/login_screen.dart';
import 'package:action_flow/features/auth/screens/signup_screen.dart';
import 'package:action_flow/features/auth/screens/signup_success_screen.dart';
import 'package:action_flow/features/dashboard/admin_dashboard/screens/admin_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    MockAuthStore.instance.reset();
  });

  Widget buildTestableWidget(
    Widget child, {
    Size size = const Size(1200, 800),
    ThemeMode themeMode = ThemeMode.light,
  }) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: child,
      ),
    );
  }

  group('MockAuthStore Unit & Lifecycle Tests', () {
    test('Initializes with default sample accounts across all statuses', () {
      final store = MockAuthStore.instance;
      expect(store.registrations.isNotEmpty, isTrue);

      final pending = store.getPendingRequests();
      expect(pending.any((r) => r.fullName == 'Elena Vlad'), isTrue);
      expect(pending.any((r) => r.fullName == 'Arjun Nair'), isTrue);

      final rejected = store.getRejectedRequests();
      expect(rejected.any((r) => r.fullName == 'Tom Holloway'), isTrue);
      expect(rejected.first.rejectionReason, isNotNull);
    });

    test('Staff signup starts as pending email verification', () {
      final store = MockAuthStore.instance;
      final staffRequest = SignupRequest(
        fullName: 'Jane Doe',
        email: 'jane.doe@company.com',
        phone: '+1 555-0192',
        designation: 'Safety Field Inspector',
        department: 'HSE / Safety',
        site: 'Site Bravo',
        requestedType: RequestedAccountType.staff,
        password: 'password123',
      );

      store.addRegistration(staffRequest);
      final retrieved = store.getRegistrationByEmail('jane.doe@company.com');

      expect(retrieved, isNotNull);
      expect(retrieved!.status, equals(AuthAccountStatus.pendingVerification));
      expect(retrieved.isEmailVerified, isFalse);
    });

    test('Email verification transitions both Staff and Manager to Pending Administrator Approval', () {
      final store = MockAuthStore.instance;
      final staffRequest = SignupRequest(
        fullName: 'Staff User',
        email: 'staff.user@company.com',
        phone: '+1 555-1111',
        designation: 'Technician',
        department: 'Operations',
        site: 'Site A',
        requestedType: RequestedAccountType.staff,
        password: 'password123',
      );
      final managerRequest = SignupRequest(
        fullName: 'Manager User',
        email: 'mgr.user@company.com',
        phone: '+1 555-2222',
        designation: 'Operations Lead',
        department: 'Operations',
        site: 'Site B',
        requestedType: RequestedAccountType.manager,
        password: 'password123',
      );

      store.addRegistration(staffRequest);
      store.addRegistration(managerRequest);

      final verifiedStaff = store.verifyEmail('staff.user@company.com');
      final verifiedMgr = store.verifyEmail('mgr.user@company.com');

      expect(verifiedStaff!.status, equals(AuthAccountStatus.pendingApproval));
      expect(verifiedStaff.isEmailVerified, isTrue);

      expect(verifiedMgr!.status, equals(AuthAccountStatus.pendingApproval));
      expect(verifiedMgr.isEmailVerified, isTrue);
    });

    test(
      'Admin approval activates account and registers user in MockPeopleStore',
      () {
        final store = MockAuthStore.instance;
        final staffRequest = SignupRequest(
          fullName: 'Approved Staff',
          email: 'approved.staff@company.com',
          phone: '+1 555-3333',
          designation: 'Plant Operator',
          department: 'Operations',
          site: 'Site Alpha',
          requestedType: RequestedAccountType.staff,
          password: 'password123',
        );
        store.addRegistration(staffRequest);

        final approved = store.approveRegistration(
          'approved.staff@company.com',
          approvedBy: 'Admin Chief',
        );

        expect(approved, isNotNull);
        expect(approved!.status, equals(AuthAccountStatus.active));
        expect(approved.approvedBy, equals('Admin Chief'));
        expect(approved.approvedAt, isNotNull);

        // Verify presence in MockPeopleStore
        final person = MockPeopleStore.instance.people.firstWhere(
          (p) => p.email == 'approved.staff@company.com',
        );
        expect(person.name, equals('Approved Staff'));
        expect(person.isActive, isTrue);
      },
    );

    test('Admin rejection stores reason, administrator name, and rejection timestamp', () {
      final store = MockAuthStore.instance;
      final managerRequest = SignupRequest(
        fullName: 'Denied Manager',
        email: 'denied.mgr@company.com',
        phone: '+1 555-4444',
        designation: 'External Supervisor',
        department: 'Drilling',
        site: 'Site Bravo',
        requestedType: RequestedAccountType.manager,
        password: 'password123',
      );
      store.addRegistration(managerRequest);

      final rejected = store.rejectRegistration(
        'denied.mgr@company.com',
        reason: 'Missing corporate site badge authorization.',
        rejectedBy: 'Lead Administrator',
      );

      expect(rejected, isNotNull);
      expect(rejected!.status, equals(AuthAccountStatus.rejected));
      expect(
        rejected.rejectionReason,
        equals('Missing corporate site badge authorization.'),
      );
      expect(rejected.rejectedBy, equals('Lead Administrator'));
      expect(rejected.rejectedAt, isNotNull);
    });
  });

  group('SignupScreen & Success Screen Flow Tests', () {
    testWidgets('Submitting Signup creates persistent MockAuthStore record', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestableWidget(const SignupScreen()));
      await tester.pumpAndSettle();

      // Verify form elements exist
      expect(find.text('Create an account'), findsWidgets);
      expect(find.text('Staff'), findsOneWidget);
      expect(find.text('Manager'), findsOneWidget);

      // Fill in required fields
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full Name *'),
        'Alex Rivers',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email Address *'),
        'alex.rivers@company.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone Number *'),
        '+1 555-1234',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Designation / Job Title *'),
        'Safety Specialist',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password *'),
        'StrongPass1!',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm Password *'),
        'StrongPass1!',
      );

      // Submit
      final submitButton = find.widgetWithText(
        ElevatedButton,
        'Create Staff Account',
      );
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Check success screen
      expect(find.text('Account Registration Submitted'), findsOneWidget);
      expect(find.text('alex.rivers@company.com'), findsOneWidget);

      // Verify store has record
      final record = MockAuthStore.instance.getRegistrationByEmail(
        'alex.rivers@company.com',
      );
      expect(record, isNotNull);
      expect(record!.fullName, equals('Alex Rivers'));
      expect(record.status, equals(AuthAccountStatus.pendingVerification));
    });

    testWidgets('SignupSuccessScreen provides Next Steps guidance', (
      tester,
    ) async {
      final request = SignupRequest(
        fullName: 'Jordan Bell',
        email: 'jordan.bell@company.com',
        phone: '+1 555-5555',
        designation: 'Engineer',
        department: 'Operations',
        site: 'Platform 1',
        requestedType: RequestedAccountType.staff,
        password: 'password123',
      );

      await tester.pumpWidget(
        buildTestableWidget(SignupSuccessScreen(request: request)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Account Registration Submitted'), findsOneWidget);
      expect(find.text('Next Steps for Account Activation:'), findsOneWidget);
      expect(find.text('Verify Email Address'), findsOneWidget);
    });
  });

  group('EmailVerificationScreen & Stepper Tests', () {
    testWidgets(
      'Verifying email transitions user to Pending Administrator Approval',
      (tester) async {
        final request = SignupRequest(
          fullName: 'Morgan Hayes',
          email: 'morgan.hayes@company.com',
          phone: '+1 555-6666',
          designation: 'Field Inspector',
          department: 'HSE',
          site: 'Alpha Rig',
          requestedType: RequestedAccountType.staff,
          password: 'password123',
        );
        MockAuthStore.instance.addRegistration(request);

        await tester.pumpWidget(
          buildTestableWidget(
            EmailVerificationScreen(
              email: 'morgan.hayes@company.com',
              signupRequest: request,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Verify your email'), findsOneWidget);
        expect(find.text('morgan.hayes@company.com'), findsOneWidget);

        // Tap simulate verify email button
        final verifyButton = find.widgetWithText(
          ElevatedButton,
          'Simulate Email Verified (Mock)',
        );
        expect(verifyButton, findsOneWidget);
        await tester.tap(verifyButton);
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // Should land on AccountStatusScreen with Pending Administrator Approval
        expect(find.text('Pending Administrator Approval'), findsWidgets);

        // Verify store updated
        final updated = MockAuthStore.instance.getRegistrationByEmail(
          'morgan.hayes@company.com',
        );
        expect(updated!.status, equals(AuthAccountStatus.pendingApproval));
        expect(updated.isEmailVerified, isTrue);
      },
    );
  });

  group('AccountStatusScreen Decision & Stepper Tests', () {
    testWidgets('Displays applicant details and 4-step lifecycle stepper', (
      tester,
    ) async {
      final request = SignupRequest(
        fullName: 'Elena Vlad',
        email: 'elena.vlad@company.com',
        phone: '+1 (555) 345-6789',
        designation: 'Senior Safety Lead',
        department: 'HSE / Safety',
        site: 'Platform Alpha',
        requestedType: RequestedAccountType.manager,
        password: 'password123',
        status: AuthAccountStatus.pendingApproval,
        isEmailVerified: true,
      );

      await tester.pumpWidget(
        buildTestableWidget(
          AccountStatusScreen(
            status: AuthAccountStatus.pendingApproval,
            userEmail: 'elena.vlad@company.com',
            userName: 'Elena Vlad',
            requestedType: RequestedAccountType.manager,
            registration: request,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pending Administrator Approval'), findsWidgets);
      expect(find.text('Manager (Approval Required)'), findsOneWidget);
      expect(find.text('Elena Vlad'), findsWidgets);
      expect(find.text('elena.vlad@company.com'), findsWidgets);

      // Stepper labels
      expect(find.text('Registration'), findsOneWidget);
      expect(find.text('Email Verified'), findsOneWidget);
      expect(find.text('Admin Approval'), findsOneWidget);
      expect(find.text('Portal Access'), findsOneWidget);
    });

    testWidgets('Renders rejection reason and audit details when rejected', (
      tester,
    ) async {
      final rejectedRequest = SignupRequest(
        fullName: 'Tom Holloway',
        email: 'tom.holloway@external.com',
        phone: '+1 555-678-9012',
        designation: 'Contractor Lead',
        department: 'Operations',
        site: 'Central Base',
        requestedType: RequestedAccountType.manager,
        password: 'password123',
        status: AuthAccountStatus.rejected,
        isEmailVerified: true,
        rejectionReason: 'Manager role requires minimum 12 months internal enterprise employment.',
        rejectedBy: 'System Administrator',
      );

      await tester.pumpWidget(
        buildTestableWidget(
          AccountStatusScreen(
            status: AuthAccountStatus.rejected,
            userEmail: 'tom.holloway@external.com',
            userName: 'Tom Holloway',
            requestedType: RequestedAccountType.manager,
            registration: rejectedRequest,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Access Request Rejected'), findsWidgets);
      expect(find.text('Application Decision Details'), findsOneWidget);
      expect(
        find.textContaining('Manager role requires minimum 12 months'),
        findsOneWidget,
      );
      expect(find.textContaining('System Administrator'), findsOneWidget);
    });

    testWidgets('Active account displays Proceed to Dashboard button', (
      tester,
    ) async {
      final activeStaff = SignupRequest(
        fullName: 'Active Worker',
        email: 'active.worker@company.com',
        phone: '+1 555-7777',
        designation: 'Technician',
        department: 'Operations',
        site: 'Site 1',
        requestedType: RequestedAccountType.staff,
        password: 'password123',
        status: AuthAccountStatus.active,
        isEmailVerified: true,
      );

      await tester.pumpWidget(
        buildTestableWidget(
          AccountStatusScreen(
            status: AuthAccountStatus.active,
            userEmail: 'active.worker@company.com',
            userName: 'Active Worker',
            requestedType: RequestedAccountType.staff,
            registration: activeStaff,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Account Active'), findsWidgets);
      expect(find.text('Proceed to Dashboard'), findsOneWidget);
    });
  });

  group('LoginScreen Dynamic Status Routing Tests', () {
    testWidgets('Hardcoded dev credentials immediately route to dashboards', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestableWidget(const LoginScreen()));
      await tester.pumpAndSettle();

      // Test Admin login
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username or email'),
        'admin',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        '123456',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.byType(AdminDashboardScreen), findsOneWidget);
    });

    testWidgets(
      'User with pending approval is routed to AccountStatusScreen upon login',
      (tester) async {
        await tester.pumpWidget(buildTestableWidget(const LoginScreen()));
        await tester.pumpAndSettle();

        // Elena Vlad is pending approval with password 'password123'
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Username or email'),
          'elena.vlad@company.com',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'),
          'password123',
        );
        await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
        await tester.pumpAndSettle(const Duration(seconds: 1));

        expect(find.byType(AccountStatusScreen), findsOneWidget);
        expect(find.text('Pending Administrator Approval'), findsWidgets);
      },
    );

    testWidgets(
      'User with pending verification is routed to EmailVerificationScreen upon login',
      (tester) async {
        await tester.pumpWidget(buildTestableWidget(const LoginScreen()));
        await tester.pumpAndSettle();

        // Marcus Vance is pending verification with password 'password123'
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Username or email'),
          'marcus.vance@company.com',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'),
          'password123',
        );
        await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
        await tester.pumpAndSettle(const Duration(seconds: 1));

        expect(find.byType(EmailVerificationScreen), findsOneWidget);
        expect(find.text('Verify your email'), findsOneWidget);
      },
    );

    testWidgets(
      'Rejected user is routed to AccountStatusScreen showing rejection reason',
      (tester) async {
        await tester.pumpWidget(buildTestableWidget(const LoginScreen()));
        await tester.pumpAndSettle();

        // Tom Holloway is rejected with password 'password123'
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Username or email'),
          'tom.holloway@external.com',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'),
          'password123',
        );
        await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
        await tester.pumpAndSettle(const Duration(seconds: 1));

        expect(find.byType(AccountStatusScreen), findsOneWidget);
        expect(find.text('Access Request Rejected'), findsWidgets);
        expect(
          find.textContaining('Manager role requires minimum 12 months'),
          findsOneWidget,
        );
      },
    );

    testWidgets('Active user login routes directly to designated dashboard', (
      tester,
    ) async {
      // Approve Arjun Nair (Staff)
      MockAuthStore.instance.approveRegistration('arjun.nair@company.com');

      await tester.pumpWidget(buildTestableWidget(const LoginScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username or email'),
        'arjun.nair@company.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'password123',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.byType(WorkerDashboardScreen), findsOneWidget);
    });
  });

  group('Admin Portal Account Requests Management Tests', () {
    testWidgets(
      'Admin Portal has Account Requests in navigation and renders management view',
      (tester) async {
        await tester.pumpWidget(
          buildTestableWidget(const AdminDashboardScreen(initialTabIndex: 10)),
        );
        await tester.pumpAndSettle();

        expect(find.text('Account Requests & Approvals'), findsWidgets);
        expect(find.text('Pending Approvals'), findsOneWidget);
        expect(find.text('Approved Accounts'), findsOneWidget);
        expect(find.text('Rejected Applications'), findsOneWidget);

        // Verify pending items listed
        expect(find.text('Elena Vlad'), findsOneWidget);
        expect(find.text('Arjun Nair'), findsOneWidget);
      },
    );

    testWidgets('Admin can approve a pending request', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestableWidget(const AdminDashboardScreen(initialTabIndex: 10)),
      );
      await tester.pumpAndSettle();

      // Find Approve button for Elena Vlad
      final approveButtons = find.widgetWithText(ElevatedButton, 'Approve');
      expect(approveButtons, findsWidgets);

      await tester.ensureVisible(approveButtons.first);
      await tester.tap(approveButtons.first);
      await tester.pumpAndSettle();

      final confirmApprove = find.text('Confirm Approval');
      expect(confirmApprove, findsOneWidget);
      await tester.tap(confirmApprove);
      await tester.pumpAndSettle();

      // Verify Elena Vlad is now Active in MockAuthStore
      final elena = MockAuthStore.instance.getRegistrationByEmail(
        'elena.vlad@company.com',
      );
      expect(elena!.status, equals(AuthAccountStatus.active));
    });

    testWidgets('Admin can reject a request with required explanation', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestableWidget(const AdminDashboardScreen(initialTabIndex: 10)),
      );
      await tester.pumpAndSettle();

      // Find Reject button
      final rejectButtons = find.widgetWithText(OutlinedButton, 'Reject');
      expect(rejectButtons, findsWidgets);

      await tester.ensureVisible(rejectButtons.first);
      await tester.tap(rejectButtons.first);
      await tester.pumpAndSettle();

      // Modal appears
      expect(find.text('Reject Account Request'), findsOneWidget);

      // Enter reason and confirm
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Reason for Rejection *'),
        'Need manager verification for North Rig #4 site assignment.',
      );
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Confirm Rejection'),
      );
      await tester.pumpAndSettle();

      // Check rejection in store for Elena Vlad (first in list)
      final reg = MockAuthStore.instance.getRegistrationByEmail(
        'elena.vlad@company.com',
      );
      expect(reg!.status, equals(AuthAccountStatus.rejected));
      expect(
        reg.rejectionReason,
        equals('Need manager verification for North Rig #4 site assignment.'),
      );
    });

    testWidgets(
      'View Details dialog displays full applicant profile snapshot',
      (tester) async {
        await tester.pumpWidget(
          buildTestableWidget(const AdminDashboardScreen(initialTabIndex: 10)),
        );
        await tester.pumpAndSettle();

        final viewDetailsButtons = find.widgetWithText(
          OutlinedButton,
          'View Details',
        );
        expect(viewDetailsButtons, findsWidgets);

        await tester.ensureVisible(viewDetailsButtons.first);
        await tester.tap(viewDetailsButtons.first);
        await tester.pumpAndSettle();

        expect(find.text('APPLICANT PROFILE & CONTACT'), findsOneWidget);
        expect(find.text('ORGANIZATIONAL PLACEMENT'), findsOneWidget);
        expect(find.text('AUDIT & TIMELINE'), findsOneWidget);
        expect(find.text('Close'), findsOneWidget);
      },
    );
  });

  group('Responsive Layout & Theme Tests', () {
    final screenSizes = [
      const Size(1200, 800),
      const Size(768, 1024),
      const Size(400, 800),
      const Size(320, 640),
    ];

    for (final size in screenSizes) {
      testWidgets(
        'AccountStatusScreen renders without overflow at ${size.width}x${size.height}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await tester.pumpWidget(
            buildTestableWidget(
              const AccountStatusScreen(
                status: AuthAccountStatus.pendingApproval,
                userEmail: 'test@company.com',
                userName: 'Test User',
              ),
              size: size,
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Pending Administrator Approval'), findsWidgets);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'Admin Account Requests renders without overflow at ${size.width}x${size.height}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await tester.pumpWidget(
            buildTestableWidget(
              const AdminDashboardScreen(initialTabIndex: 10),
              size: size,
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('Dark theme renders cleanly for AccountStatusScreen', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestableWidget(
          const AccountStatusScreen(
            status: AuthAccountStatus.pendingApproval,
            userEmail: 'dark@company.com',
            userName: 'Dark User',
          ),
          themeMode: ThemeMode.dark,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pending Administrator Approval'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
