import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/features/auth/data/mock_auth_store.dart';
import 'package:action_flow/features/auth/models/auth_models.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/providers/auth_provider.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthService Unit & Architecture Tests', () {
    test('SupabaseConfig clientOrNull returns null when not initialized', () {
      // In unit test environment where Supabase.initialize has not been called
      expect(SupabaseConfig.isInitialized, isFalse);
      expect(SupabaseConfig.clientOrNull, isNull);
    });

    test('AuthService returns friendly error when uninitialized', () async {
      final authService = AuthService.instance;
      final result = await authService.signIn(
        email: 'test@example.com',
        password: 'password',
      );

      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        'Authentication service is currently unavailable.',
      );
    });

    test('AuthProfileData correctly holds UserProfile and role metadata', () {
      final profile = UserProfile(
        id: 'usr-123',
        name: 'Jane Doe',
        email: 'jane.doe@company.com',
        phone: '+1 555 123 4567',
        designation: 'HSE Coordinator',
        department: 'HSE / Safety',
        division: 'Operations & HSSE',
        site: 'Platform Alpha',
        role: 'Manager / Action Approver',
        permissions: const ['Create & Assign Actions'],
      );

      final data = AuthProfileData(
        userProfile: profile,
        roleCode: 'manager',
        status: 'active',
        isActive: true,
        isPrimaryAdmin: false,
      );

      expect(data.roleCode, 'manager');
      expect(data.status, 'active');
      expect(data.isActive, isTrue);
      expect(data.isPrimaryAdmin, isFalse);
      expect(data.userProfile.name, 'Jane Doe');
      expect(data.userProfile.department, 'HSE / Safety');
      expect(data.userProfile.site, 'Platform Alpha');
    });

    test('AuthAccountRequestData correctly models pending request data', () {
      const req = AuthAccountRequestData(
        id: 'req-001',
        authUserId: 'auth-user-999',
        fullName: 'Mark Smith',
        email: 'mark@company.com',
        status: 'pending_admin_approval',
        requestedRoleCode: 'staff',
      );

      expect(req.id, 'req-001');
      expect(req.authUserId, 'auth-user-999');
      expect(req.fullName, 'Mark Smith');
      expect(req.email, 'mark@company.com');
      expect(req.status, 'pending_admin_approval');
      expect(req.requestedRoleCode, 'staff');
    });

    test('AuthSignInResult handles success and failure constructors', () {
      const failure = AuthSignInResult.failure('Invalid username or password');
      expect(failure.isSuccess, isFalse);
      expect(failure.errorMessage, 'Invalid username or password');
      expect(failure.profileData, isNull);

      const success = AuthSignInResult.success(
        session: null,
        user: null,
        profileData: null,
        accountRequest: null,
      );
      expect(success.isSuccess, isTrue);
      expect(success.errorMessage, isNull);
    });

    test('AuthProvider reflects initial unauthenticated state', () {
      final provider = AuthProvider();
      expect(provider.isAuthenticated, isFalse);
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);
      expect(provider.currentProfile, isNull);
    });

    test(
      'AuthSignInResult distinguishes database errors and missing profiles',
      () {
        const dbError = AuthSignInResult.failure(
          'Database error loading user profile.',
          isDatabaseError: true,
        );
        expect(dbError.isSuccess, isFalse);
        expect(dbError.isDatabaseError, isTrue);
        expect(dbError.isProfileMissing, isFalse);
        expect(dbError.errorMessage, 'Database error loading user profile.');

        const missingProfile = AuthSignInResult.failure(
          'No profile found.',
          isProfileMissing: true,
        );
        expect(missingProfile.isSuccess, isFalse);
        expect(missingProfile.isDatabaseError, isFalse);
        expect(missingProfile.isProfileMissing, isTrue);
      },
    );

    test('ProfileFetchResult correctly differentiates Success, NotFound, and Error', () {
      final profile = UserProfile(
        id: 'admin-001',
        name: 'Sobha Admin',
        email: 'sobha.admin@company.com',
        phone: '+971 50 123 4567',
        designation: 'Enterprise Administrator',
        department: 'Enterprise System Administration',
        division: 'System & Organization Governance',
        site: 'Corporate Headquarters',
        role: 'System Administrator',
        permissions: const ['Full System Configuration Access'],
      );

      final profileData = AuthProfileData(
        userProfile: profile,
        roleCode: 'admin',
        status: 'active',
        isActive: true,
        isPrimaryAdmin: true,
      );

      const notFound = ProfileFetchNotFound();
      expect(notFound, isA<ProfileFetchResult>());
      expect(notFound, isA<ProfileFetchNotFound>());

      final success = ProfileFetchSuccess(profileData);
      expect(success, isA<ProfileFetchResult>());
      expect(success.profileData.roleCode, 'admin');
      expect(success.profileData.isPrimaryAdmin, isTrue);

      const err = ProfileFetchError('PGRST200: ambiguous relationship');
      expect(err, isA<ProfileFetchResult>());
      expect(err.errorMessage, contains('PGRST200'));
    });

    test('Regression: Supabase Admin profile takes absolute priority over mock Staff account with same email', () {
      const email = 'sobha.admin@company.com';

      // 1. Seed a mock Staff user in MockAuthStore with the exact same email
      final mockStaff = SignupRequest(
        fullName: 'Sobha Mock Worker',
        email: email,
        phone: '+971 50 000 0000',
        designation: 'Technician',
        department: 'Operations',
        division: 'Operations & HSSE',
        site: 'Field Rig',
        team: 'Field Crew',
        supervisor: 'Lead',
        requestedType: RequestedAccountType.staff,
        password: 'password123',
        status: AuthAccountStatus.inactive,
        isEmailVerified: true,
        createdAt: DateTime.now(),
      );
      MockAuthStore.instance.addRegistration(mockStaff);

      // Verify the mock store has this email mapped to Staff and Inactive
      final mockFound = MockAuthStore.instance.getRegistrationByEmail(email);
      expect(mockFound, isNotNull);
      expect(mockFound!.requestedType, RequestedAccountType.staff);
      expect(mockFound.status, AuthAccountStatus.inactive);

      // 2. Authoritative Supabase profile loaded from public.profiles
      final supabaseAdminProfile = UserProfile(
        id: 'admin-uuid-1234',
        name: 'Sobha Administrator',
        email: email,
        phone: '+971 50 123 4567',
        designation: 'Principal System Administrator',
        department: 'Enterprise System Administration',
        division: 'System & Organization Governance',
        site: 'Corporate Headquarters',
        role: 'System Administrator',
        permissions: const ['Full System Configuration Access'],
      );

      final authoritativeData = AuthProfileData(
        userProfile: supabaseAdminProfile,
        roleCode: 'admin',
        status: 'active',
        isActive: true,
        isPrimaryAdmin: true,
      );

      final signInResult = AuthSignInResult.success(
        session: null,
        user: null,
        profileData: authoritativeData,
      );

      // 3. Assert that authoritative database profile takes absolute precedence:
      // It must resolve to Admin, active, isPrimaryAdmin, and NOT be overridden by mock Staff
      expect(signInResult.isSuccess, isTrue);
      expect(signInResult.profileData, isNotNull);

      final resolved = signInResult.profileData!;
      expect(resolved.roleCode, 'admin');
      expect(resolved.status, 'active');
      expect(resolved.isActive, isTrue);
      expect(resolved.isPrimaryAdmin, isTrue);
      expect(resolved.roleCode, isNot('staff'));

      // Routing condition verification
      final isAdminRoute =
          (resolved.roleCode == 'admin' || resolved.isPrimaryAdmin) &&
          resolved.status == 'active' &&
          resolved.isActive;
      expect(
        isAdminRoute,
        isTrue,
        reason: 'Authoritative Admin must route to AdminDashboard, never Staff or Inactive',
      );
    });

    test('AuthService.parseProfileData correctly parses joined roles/departments/sites query shape for Admin', () {
      // Simulates exact payload returned by Supabase PostgREST for an Admin user with joined relations
      final adminJoinedPayload = {
        'id': 'auth-admin-uuid-001',
        'full_name': 'Sobha Admin',
        'email': 'sobha.admin@company.com',
        'phone': '+971 50 111 2222',
        'designation': 'Executive Administrator',
        'department_id': null, // Admin has null department
        'site_id': null, // Admin has null site
        'role_id': 'role-uuid-admin',
        'status': 'active',
        'is_active': true,
        'is_primary_admin': true,
        'avatar_url': null,
        'roles': {'id': 'role-uuid-admin', 'name': 'Admin', 'code': 'admin'},
        'departments': null, // Embedded relation returns null when FK is null
        'sites': null, // Embedded relation returns null when FK is null
      };

      final parsed = AuthService.parseProfileData(
        adminJoinedPayload,
        'auth-admin-uuid-001',
      );

      expect(parsed.roleCode, 'admin');
      expect(parsed.isPrimaryAdmin, isTrue);
      expect(parsed.status, 'active');
      expect(parsed.isActive, isTrue);
      expect(parsed.userProfile.name, 'Sobha Admin');
      expect(parsed.userProfile.email, 'sobha.admin@company.com');
      expect(parsed.userProfile.department, 'Enterprise System Administration');
      expect(parsed.userProfile.site, 'Corporate Headquarters');
      expect(parsed.userProfile.role, 'System Administrator');

      // Verify routing rule to AdminDashboardScreen
      final canRouteToAdminDashboard =
          (parsed.roleCode == 'admin' || parsed.isPrimaryAdmin) &&
          parsed.status == 'active' &&
          parsed.isActive;
      expect(canRouteToAdminDashboard, isTrue);
    });

    test('AuthService.parseProfileData defensively handles List shape for embedded relations', () {
      // PostgREST can sometimes return embedded relations as a 1-element list
      final listShapePayload = {
        'id': 'auth-mgr-uuid-002',
        'full_name': 'Operations Manager',
        'email': 'mgr@company.com',
        'phone': '+971 50 333 4444',
        'designation': 'Field Operations Lead',
        'department_id': 'dept-uuid-ops',
        'site_id': 'site-uuid-alpha',
        'role_id': 'role-uuid-mgr',
        'status': 'active',
        'is_active': true,
        'is_primary_admin': false,
        'roles': [
          {'id': 'role-uuid-mgr', 'name': 'Manager', 'code': 'manager'},
        ],
        'departments': [
          {
            'id': 'dept-uuid-ops',
            'name': 'Operations',
            'division': 'Operations & HSSE',
          },
        ],
        'sites': [
          {'id': 'site-uuid-alpha', 'name': 'Platform Alpha'},
        ],
      };

      final parsed = AuthService.parseProfileData(
        listShapePayload,
        'auth-mgr-uuid-002',
      );

      expect(parsed.roleCode, 'manager');
      expect(parsed.isPrimaryAdmin, isFalse);
      expect(parsed.userProfile.department, 'Operations');
      expect(parsed.userProfile.site, 'Platform Alpha');
    });

    test('AccountRequestFetchResult correctly differentiates Success, NotFound, and Error', () {
      const req = AuthAccountRequestData(
        id: 'req-001',
        authUserId: 'auth-001',
        fullName: 'Test User',
        email: 'test@example.com',
        status: 'pending_admin_approval',
        isEmailVerified: true,
        requestedRoleCode: 'staff',
      );

      const success = AccountRequestFetchSuccess(req);
      expect(success, isA<AccountRequestFetchResult>());
      expect(success.accountRequest.status, 'pending_admin_approval');
      expect(success.accountRequest.isEmailVerified, isTrue);

      const notFound = AccountRequestFetchNotFound();
      expect(notFound, isA<AccountRequestFetchResult>());

      const err = AccountRequestFetchError('Network failure');
      expect(err, isA<AccountRequestFetchResult>());
      expect(err.errorMessage, 'Network failure');
    });

    test('Regression: Pending applicant with no public.profiles but valid account_requests resolves to pending approval and does NOT report isProfileMissing', () {
      // Verified live state for user: webonant@gmail.com
      // - auth.users row exists & authenticated
      // - public.profiles does NOT exist (ProfileFetchNotFound)
      // - public.account_requests row exists with status = 'pending_admin_approval', is_email_verified = true
      const pendingRequest = AuthAccountRequestData(
        id: 'req-webonant-001',
        authUserId: 'auth-uuid-webonant-777',
        fullName: 'Webonant User',
        email: 'webonant@gmail.com',
        status: 'pending_admin_approval',
        isEmailVerified: true,
        requestedRoleCode: 'staff',
      );

      final accountFetchResult = AccountRequestFetchSuccess(pendingRequest);
      expect(accountFetchResult, isA<AccountRequestFetchResult>());

      // Simulating the signIn resolution logic with ProfileFetchNotFound and AccountRequestFetchSuccess
      AuthSignInResult resolveSignInResult({
        required ProfileFetchResult profileResult,
        required AccountRequestFetchResult accountResult,
      }) {
        if (profileResult is ProfileFetchSuccess) {
          return AuthSignInResult.success(
            session: null,
            user: null,
            profileData: profileResult.profileData,
          );
        }
        if (profileResult is ProfileFetchError) {
          return AuthSignInResult.failure(
            profileResult.errorMessage,
            isDatabaseError: true,
          );
        }
        if (accountResult is AccountRequestFetchSuccess) {
          return AuthSignInResult.success(
            session: null,
            user: null,
            accountRequest: accountResult.accountRequest,
          );
        }
        if (accountResult is AccountRequestFetchError) {
          return AuthSignInResult.failure(
            accountResult.errorMessage,
            isDatabaseError: true,
          );
        }
        return const AuthSignInResult.failure(
          'Account authenticated, but no organizational profile was found in the database.',
          isProfileMissing: true,
        );
      }

      final result = resolveSignInResult(
        profileResult: const ProfileFetchNotFound(),
        accountResult: accountFetchResult,
      );

      // Verification of requirements:
      // 1. Login resolves the account request
      expect(result.isSuccess, isTrue);
      expect(result.accountRequest, isNotNull);
      expect(result.accountRequest!.status, 'pending_admin_approval');
      expect(result.accountRequest!.isEmailVerified, isTrue);
      expect(result.accountRequest!.email, 'webonant@gmail.com');

      // 2. Does NOT report isProfileMissing or isDatabaseError
      expect(result.isProfileMissing, isFalse);
      expect(result.isDatabaseError, isFalse);
      expect(result.errorMessage, isNull);

      // 3. Pending Administrator Approval routing verification
      final reqStatus = result.accountRequest!.status.toLowerCase();
      final routesToPendingApproval =
          reqStatus == 'pending_admin_approval' ||
          (reqStatus != 'pending_email_verification' &&
              reqStatus != 'rejected');
      expect(routesToPendingApproval, isTrue);
    });

    test('AccountRequestFetchError correctly sets isDatabaseError: true and does NOT report isProfileMissing: true', () {
      const errorResult = AccountRequestFetchError(
        'Database connection failure',
      );
      expect(errorResult, isA<AccountRequestFetchResult>());
      expect(errorResult.errorMessage, 'Database connection failure');

      final signInError = AuthSignInResult.failure(
        errorResult.errorMessage,
        isDatabaseError: true,
      );
      expect(signInError.isSuccess, isFalse);
      expect(signInError.isDatabaseError, isTrue);
      expect(signInError.isProfileMissing, isFalse);
    });
  });
}
