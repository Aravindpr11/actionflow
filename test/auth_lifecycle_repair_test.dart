import 'package:action_flow/core/routing/auth_router.dart';
import 'package:action_flow/features/auth/models/auth_models.dart';
import 'package:action_flow/features/auth/screens/account_status_screen.dart';
import 'package:action_flow/features/dashboard/admin_dashboard/screens/admin_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/platform_admin_dashboard/screens/platform_admin_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/services/account_request_service.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:action_flow/services/user_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthRouter - Strict Status & Portal Access Gating', () {
    testWidgets(
      'Active Platform Admin routes to PlatformAdminDashboardScreen',
      (tester) async {
        final profile = AuthProfileData(
          userProfile: const UserProfile(
            id: 'plat-admin-1',
            name: 'Platform Admin',
            email: 'platform@actionflow.com',
            phone: '+971 50 123 4567',
            role: 'Admin',
            designation: 'Platform Administrator',
            department: 'Executive',
            site: 'Headquarters',
          ),
          roleCode: 'admin',
          status: 'active',
          isActive: true,
          isPrimaryAdmin: false,
          isPlatformAdmin: true,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    AuthRouter.navigateToRolePortal(context, profile),
                child: const Text('Go'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Go'));
        await tester.pumpAndSettle();

        expect(find.byType(PlatformAdminDashboardScreen), findsOneWidget);
      },
    );

    testWidgets('Active Company Admin routes to AdminDashboardScreen', (
      tester,
    ) async {
      final profile = AuthProfileData(
        userProfile: const UserProfile(
          id: 'company-admin-1',
          name: 'Company Admin',
          email: 'admin@sobha.com',
          phone: '+971 50 123 4567',
          role: 'Admin',
          designation: 'HSE Director',
          department: 'HSE',
          site: 'Plant Alpha',
        ),
        roleCode: 'admin',
        status: 'active',
        isActive: true,
        isPrimaryAdmin: true,
        isPlatformAdmin: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  AuthRouter.navigateToRolePortal(context, profile),
              child: const Text('Go'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminDashboardScreen), findsOneWidget);
    });

    testWidgets('Active Manager routes to ManagerDashboardScreen', (
      tester,
    ) async {
      final profile = AuthProfileData(
        userProfile: const UserProfile(
          id: 'mgr-1',
          name: 'Manager User',
          email: 'mgr@sobha.com',
          phone: '+971 50 123 4567',
          role: 'Manager',
          designation: 'Safety Manager',
          department: 'HSE',
          site: 'Plant Alpha',
        ),
        roleCode: 'manager',
        status: 'active',
        isActive: true,
        isPrimaryAdmin: false,
        isPlatformAdmin: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  AuthRouter.navigateToRolePortal(context, profile),
              child: const Text('Go'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.byType(ManagerDashboardScreen), findsOneWidget);
    });

    testWidgets('Active Staff routes to WorkerDashboardScreen', (tester) async {
      final profile = AuthProfileData(
        userProfile: const UserProfile(
          id: 'staff-1',
          name: 'Staff Worker',
          email: 'staff@sobha.com',
          phone: '+971 50 123 4567',
          role: 'Worker / Staff',
          designation: 'Field Inspector',
          department: 'HSE',
          site: 'Plant Alpha',
        ),
        roleCode: 'staff',
        status: 'active',
        isActive: true,
        isPrimaryAdmin: false,
        isPlatformAdmin: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  AuthRouter.navigateToRolePortal(context, profile),
              child: const Text('Go'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.byType(WorkerDashboardScreen), findsOneWidget);
    });

    testWidgets(
      'Deactivated / Inactive profile is DENIED portal entry and routed to AccountStatusScreen',
      (tester) async {
        final inactiveProfile = AuthProfileData(
          userProfile: const UserProfile(
            id: 'inactive-staff-1',
            name: 'Inactive Staff',
            email: 'inactive@sobha.com',
            phone: '+971 50 123 4567',
            role: 'Worker / Staff',
            designation: 'Field Inspector',
            department: 'HSE',
            site: 'Plant Alpha',
          ),
          roleCode: 'staff',
          status: 'inactive',
          isActive: false,
          isPrimaryAdmin: false,
          isPlatformAdmin: false,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    AuthRouter.navigateToRolePortal(context, inactiveProfile),
                child: const Text('Go'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Go'));
        await tester.pumpAndSettle();

        // Must NOT be in WorkerDashboardScreen
        expect(find.byType(WorkerDashboardScreen), findsNothing);
        // Must be on AccountStatusScreen displaying Inactive state
        expect(find.byType(AccountStatusScreen), findsOneWidget);
        expect(find.text('Account Inactive'), findsOneWidget);
      },
    );
  });

  group('AccountRequestService - Lifecycle Invariants & Preconditions', () {
    test('approveAccountRequest throws if request is unverified', () async {
      final unverifiedReq = SignupRequest(
        id: 'req-001',
        authUserId: 'auth-001',
        fullName: 'Pending User',
        email: 'pending@example.com',
        phone: '1234567890',
        designation: 'Staff',
        department: 'HSE',
        site: 'Plant Alpha',
        requestedType: RequestedAccountType.staff,
        status: AuthAccountStatus.pendingVerification,
        isEmailVerified: false,
      );

      expect(
        () => AccountRequestService.instance.approveAccountRequest(
          unverifiedReq,
          adminUserId: 'admin-001',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'rejectAccountRequest throws if reason is less than 5 characters',
      () async {
        final req = SignupRequest(
          id: 'req-002',
          authUserId: 'auth-002',
          fullName: 'Test User',
          email: 'test@example.com',
          phone: '1234567890',
          designation: 'Staff',
          department: 'HSE',
          site: 'Plant Alpha',
          requestedType: RequestedAccountType.staff,
          status: AuthAccountStatus.pendingApproval,
          isEmailVerified: true,
        );

        expect(
          () => AccountRequestService.instance.rejectAccountRequest(
            req,
            reason: 'No',
            adminUserId: 'admin-001',
          ),
          throwsA(isA<Exception>()),
        );
      },
    );
  });

  group('UserService - Deletion Invariants', () {
    test(
      'deleteUser in offline/mock mode removes user from MockPeopleStore',
      () async {
        final testPerson = Person(
          id: 'TEST-DEL-001',
          name: 'To Be Deleted',
          email: 'delete_me@example.com',
          phone: '+91 99999 00001',
          designation: 'Temporary Worker',
          department: 'HSE',
          site: 'North Plant',
          type: PersonType.internalUser,
          isActive: true,
        );

        MockPeopleStore.instance.add(testPerson);
        expect(
          MockPeopleStore.instance.people.any((p) => p.id == 'TEST-DEL-001'),
          isTrue,
        );

        await UserService.instance.deleteUser(
          organizationId: 'org-001',
          profileId: 'TEST-DEL-001',
        );

        expect(
          MockPeopleStore.instance.people.any((p) => p.id == 'TEST-DEL-001'),
          isFalse,
        );
      },
    );
  });

  group('AuthService - Unapproved Applicant Gating Invariants', () {
    test('AuthSignInResult with pending_admin_approval yields accountRequest and null profileData', () {
      const accountReq = AuthAccountRequestData(
        id: 'req-123',
        authUserId: 'user-123',
        fullName: 'Pending Applicant',
        email: 'applicant@example.com',
        status: 'pending_admin_approval',
        isEmailVerified: true,
        requestedRoleCode: 'staff',
        organizationId: '00000000-0000-0000-0000-000000000001',
      );

      final result = AuthSignInResult.success(accountRequest: accountReq);

      expect(result.isSuccess, isTrue);
      expect(result.profileData, isNull);
      expect(result.accountRequest, isNotNull);
      expect(result.accountRequest!.status, 'pending_admin_approval');
      expect(result.accountRequest!.isEmailVerified, isTrue);
    });

    test('AuthSignInResult with rejected status yields accountRequest and null profileData', () {
      const accountReq = AuthAccountRequestData(
        id: 'req-456',
        authUserId: 'user-456',
        fullName: 'Rejected Applicant',
        email: 'rejected@example.com',
        status: 'rejected',
        isEmailVerified: true,
        rejectionReason: 'Does not meet organization criteria',
        requestedRoleCode: 'manager',
        organizationId: '00000000-0000-0000-0000-000000000001',
      );

      final result = AuthSignInResult.success(accountRequest: accountReq);

      expect(result.isSuccess, isTrue);
      expect(result.profileData, isNull);
      expect(result.accountRequest, isNotNull);
      expect(result.accountRequest!.status, 'rejected');
      expect(
        result.accountRequest!.rejectionReason,
        'Does not meet organization criteria',
      );
    });
  });
}
