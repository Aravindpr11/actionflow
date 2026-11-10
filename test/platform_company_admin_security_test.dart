import 'dart:io';

import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Platform Admin vs Company Admin Security - Model & Service Tests', () {
    test('Platform Admin AuthProfileData has isPlatformAdmin=true, isCompanyAdmin=false, and null organization', () {
      const platformProfile = UserProfile(
        id: 'plat-admin-001',
        name: 'Platform Super Admin',
        email: 'superadmin@actionflow.io',
        phone: '+1 800 000 0001',
        designation: 'Platform Administrator',
        department: 'Platform Administration',
        division: 'Global Platform Governance',
        site: 'Global',
        role: 'Platform Administrator',
        permissions: [
          'Global Platform Administration',
          'Create & Manage Organizations',
        ],
        organizationId: null,
        organizationName: '',
      );

      const authData = AuthProfileData(
        userProfile: platformProfile,
        roleCode: 'admin',
        status: 'active',
        isActive: true,
        isPrimaryAdmin: false,
        isPlatformAdmin: true,
        organizationId: null,
        organization: null,
      );

      expect(authData.isPlatformAdmin, isTrue);
      expect(authData.isCompanyAdmin, isFalse);
      expect(authData.organizationId, isNull);
      expect(authData.organization, isNull);
      expect(authData.roleCode, 'admin');
      expect(authData.userProfile.organizationId, isNull);
    });

    test('Company Admin AuthProfileData has isPlatformAdmin=false, isCompanyAdmin=true, and belongs to Sobha', () {
      final sobhaAdminProfile = UserProfile.mockAdmin();

      final authData = AuthProfileData(
        userProfile: sobhaAdminProfile,
        roleCode: 'admin',
        status: 'active',
        isActive: true,
        isPrimaryAdmin: true,
        isPlatformAdmin: false,
        organizationId: Organization.sobhaId,
        organization: Organization.sobha(),
      );

      expect(authData.isPlatformAdmin, isFalse);
      expect(authData.isCompanyAdmin, isTrue);
      expect(authData.organizationId, Organization.sobhaId);
      expect(authData.organization, isNotNull);
      expect(authData.organization?.id, Organization.sobhaId);
      expect(authData.organization?.name, Organization.sobhaName);
      expect(authData.roleCode, 'admin');
      expect(authData.isPrimaryAdmin, isTrue);
    });

    test('Manager / Staff AuthProfileData has isPlatformAdmin=false and isCompanyAdmin=false', () {
      final managerProfile = UserProfile.mockManager();
      final managerAuthData = AuthProfileData(
        userProfile: managerProfile,
        roleCode: 'manager',
        status: 'active',
        isActive: true,
        isPrimaryAdmin: false,
        isPlatformAdmin: false,
        organizationId: Organization.sobhaId,
      );

      expect(managerAuthData.isPlatformAdmin, isFalse);
      expect(managerAuthData.isCompanyAdmin, isFalse);
      expect(managerAuthData.organizationId, Organization.sobhaId);

      final staffProfile = UserProfile.mockStaff();
      final staffAuthData = AuthProfileData(
        userProfile: staffProfile,
        roleCode: 'staff',
        status: 'active',
        isActive: true,
        isPrimaryAdmin: false,
        isPlatformAdmin: false,
        organizationId: Organization.sobhaId,
      );

      expect(staffAuthData.isPlatformAdmin, isFalse);
      expect(staffAuthData.isCompanyAdmin, isFalse);
      expect(staffAuthData.organizationId, Organization.sobhaId);
    });

    test('AuthService.parseProfileData correctly parses Platform Admin with null organization', () {
      final rawRow = {
        'id': 'usr-platform-99',
        'full_name': 'Platform Operations Admin',
        'email': 'platform.ops@actionflow.io',
        'phone': '+1 555 9999',
        'designation': 'Platform Administrator',
        'is_primary_admin': false,
        'is_platform_admin': true,
        'status': 'active',
        'is_active': true,
        'organization_id': null,
        'roles': {'code': 'admin', 'name': 'Platform Administrator'},
      };

      final profileData = AuthService.parseProfileData(
        rawRow,
        'usr-platform-99',
      );

      expect(profileData.isPlatformAdmin, isTrue);
      expect(profileData.isCompanyAdmin, isFalse);
      expect(profileData.organizationId, isNull);
      expect(profileData.organization, isNull);
      expect(profileData.userProfile.organizationId, isNull);
      expect(profileData.userProfile.role, 'Platform Administrator');
      expect(profileData.userProfile.department, 'Platform Administration');
      expect(profileData.userProfile.site, 'Global');
      expect(
        profileData.userProfile.permissions,
        contains('Global Platform Administration'),
      );
    });

    test('AuthService.parseProfileData preserves existing Sobha Admin as Company Admin', () {
      final rawRow = {
        'id': 'usr-sobha-admin-1',
        'full_name': 'Sobha System Administrator',
        'email': 'admin@sobha.internal',
        'phone': '+971 50 123 4567',
        'designation': 'Principal Administrator',
        'is_primary_admin': true,
        'status': 'active',
        'is_active': true,
        'organization_id': Organization.sobhaId,
        'roles': {'code': 'admin', 'name': 'System Administrator'},
        'departments': {
          'id': '00000000-0000-0000-0000-000000000010',
          'name': 'Enterprise Administration',
          'division': 'Corporate Governance',
        },
        'sites': {
          'id': '00000000-0000-0000-0000-000000000020',
          'name': 'Corporate HQ',
        },
        'organizations': {
          'id': Organization.sobhaId,
          'name': Organization.sobhaName,
          'code': Organization.sobhaCode,
          'is_active': true,
        },
      };

      final profileData = AuthService.parseProfileData(
        rawRow,
        'usr-sobha-admin-1',
        isPlatformAdmin: false,
      );

      expect(profileData.isPlatformAdmin, isFalse);
      expect(profileData.isCompanyAdmin, isTrue);
      expect(profileData.isPrimaryAdmin, isTrue);
      expect(profileData.organizationId, Organization.sobhaId);
      expect(profileData.organization, isNotNull);
      expect(profileData.organization?.id, Organization.sobhaId);
      expect(profileData.organization?.name, Organization.sobhaName);
      expect(profileData.userProfile.organizationId, Organization.sobhaId);
      expect(profileData.userProfile.role, 'System Administrator');
      expect(
        profileData.userProfile.permissions,
        contains('Full System Configuration Access'),
      );
    });

    test('AuthService getters reflect profile data correctly', () {
      final authService = AuthService.instance;
      // In default offline/unauthenticated state
      expect(authService.isPlatformAdmin, isFalse);
      expect(authService.isCompanyAdmin, isFalse);
    });
  });

  group('Migration 20260915000001 Safety and Security Contract Audit', () {
    late String migrationSql;

    setUpAll(() {
      final file = File(
        'supabase/migrations/20260915000001_platform_and_company_admin_security.sql',
      );
      expect(file.existsSync(), isTrue, reason: 'Migration file must exist');
      migrationSql = file.readAsStringSync();
    });

    test(
      'Migration creates platform_admins table with auth.users foreign key',
      () {
        expect(
          migrationSql,
          contains('CREATE TABLE IF NOT EXISTS public.platform_admins'),
        );
        expect(
          migrationSql,
          contains(
            'user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE',
          ),
        );
      },
    );

    test('Migration defines SECURITY DEFINER functions is_platform_admin and is_company_admin', () {
      expect(
        migrationSql,
        contains('CREATE OR REPLACE FUNCTION public.is_platform_admin()'),
      );
      expect(
        migrationSql,
        contains('CREATE OR REPLACE FUNCTION public.is_company_admin()'),
      );
      expect(migrationSql, contains('SECURITY DEFINER'));
    });

    test('Migration relaxes profiles.organization_id NOT NULL and installs enforce trigger', () {
      expect(migrationSql, contains('ALTER TABLE public.profiles'));
      expect(
        migrationSql,
        contains('ALTER COLUMN organization_id DROP NOT NULL'),
      );
      expect(
        migrationSql,
        contains(
          'CREATE OR REPLACE FUNCTION public.enforce_profile_organization_requirement()',
        ),
      );
      expect(
        migrationSql,
        contains('CREATE TRIGGER trg_enforce_profile_org_requirement'),
      );
    });

    test('Migration installs cross-organization consistency triggers', () {
      expect(
        migrationSql,
        contains('CREATE TRIGGER trg_validate_manager_scope_org_consistency'),
      );
      expect(
        migrationSql,
        contains(
          'CREATE TRIGGER trg_validate_account_request_scope_org_consistency',
        ),
      );
      expect(
        migrationSql,
        contains('CREATE TRIGGER trg_validate_account_request_org_consistency'),
      );
      expect(
        migrationSql,
        contains('CREATE TRIGGER trg_validate_team_member_org_consistency'),
      );
      expect(
        migrationSql,
        contains('CREATE TRIGGER trg_validate_team_dept_org_consistency'),
      );
    });

    test('Migration enforces RLS policies separating platform admin and company admin', () {
      expect(
        migrationSql,
        contains(
          'CREATE POLICY "Platform and company admin read organizations"',
        ),
      );
      expect(
        migrationSql,
        contains('CREATE POLICY "Platform admin manage organizations"'),
      );
      expect(
        migrationSql,
        contains('CREATE POLICY "Admin read all departments"'),
      );
      expect(migrationSql, contains('CREATE POLICY "Admin read all sites"'));
      expect(migrationSql, contains('CREATE POLICY "Admin read all teams"'));
      expect(migrationSql, contains('CREATE POLICY "Admin manage profiles"'));
      expect(
        migrationSql,
        contains('CREATE POLICY "Admin manage account requests"'),
      );
      expect(
        migrationSql,
        contains('CREATE POLICY "Admin manage account request scopes"'),
      );
      expect(
        migrationSql,
        contains('CREATE POLICY "Admin manage manager scopes"'),
      );
      expect(
        migrationSql,
        contains('CREATE POLICY "Admin and Manager manage team members"'),
      );
    });

    test('Migration updates directory_profiles security barrier view with org scoping', () {
      expect(
        migrationSql,
        contains('CREATE OR REPLACE VIEW public.directory_profiles'),
      );
      expect(migrationSql, contains('WITH (security_barrier = true)'));
      expect(
        migrationSql,
        contains('p.organization_id = public.get_my_organization_id()'),
      );
    });
  });
}
