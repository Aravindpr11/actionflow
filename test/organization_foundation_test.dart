import 'package:action_flow/features/auth/models/auth_models.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Organization Model Tests', () {
    test('Organization.sobha() creates default Sobha organization #1', () {
      final org = Organization.sobha();

      expect(org.id, Organization.sobhaId);
      expect(org.code, Organization.sobhaCode);
      expect(org.name, Organization.sobhaName);
      expect(org.isActive, isTrue);
      expect(org.id, '00000000-0000-0000-0000-000000000001');
      expect(org.code, 'sobha');
      expect(org.name, 'Sobha');
    });

    test('Organization fromJson and toJson roundtrip', () {
      final now = DateTime.utc(2026, 9, 14, 12, 0, 0);
      final json = {
        'id': 'org-100',
        'name': 'Sobha Constructions',
        'code': 'sobha-constructions',
        'is_active': true,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final org = Organization.fromJson(json);
      expect(org.id, 'org-100');
      expect(org.name, 'Sobha Constructions');
      expect(org.code, 'sobha-constructions');
      expect(org.isActive, isTrue);
      expect(org.createdAt, now);
      expect(org.updatedAt, now);

      final outJson = org.toJson();
      expect(outJson['id'], 'org-100');
      expect(outJson['name'], 'Sobha Constructions');
      expect(outJson['code'], 'sobha-constructions');
      expect(outJson['is_active'], isTrue);
      expect(outJson['created_at'], now.toIso8601String());
      expect(outJson['updated_at'], now.toIso8601String());
    });

    test('Organization fromJson defaults safely when fields missing', () {
      final org = Organization.fromJson({});
      expect(org.id, Organization.sobhaId);
      expect(org.name, Organization.sobhaName);
      expect(org.code, Organization.sobhaCode);
      expect(org.isActive, isTrue);
    });

    test('Organization copyWith and equality', () {
      final org = Organization.sobha();
      final updated = org.copyWith(name: 'Sobha Middle East');

      expect(updated.id, org.id);
      expect(updated.code, org.code);
      expect(updated.name, 'Sobha Middle East');

      final org2 = Organization.sobha();
      expect(org, equals(org2));
      expect(org.hashCode, equals(org2.hashCode));
    });
  });

  group('UserProfile Organization Integration Tests', () {
    test('UserProfile defaults organization to Sobha', () {
      const profile = UserProfile(
        id: 'usr-1',
        name: 'Alex Rivera',
        email: 'alex@company.com',
        phone: '+1 555 0001',
        designation: 'Safety Engineer',
        department: 'HSE',
        site: 'Site Alpha',
        role: 'Staff',
      );

      expect(profile.organizationId, Organization.sobhaId);
      expect(profile.organizationName, Organization.sobhaName);
    });

    test('UserProfile copyWith updates organization fields', () {
      final profile = UserProfile.mockAdmin();
      expect(profile.organizationId, Organization.sobhaId);
      expect(profile.organizationName, Organization.sobhaName);

      final modified = profile.copyWith(
        organizationId: 'org-custom-1',
        organizationName: 'Custom Org',
      );

      expect(modified.organizationId, 'org-custom-1');
      expect(modified.organizationName, 'Custom Org');
      expect(modified.role, profile.role);
    });

    test('Mock profiles default to Sobha', () {
      expect(UserProfile.mockAdmin().organizationName, 'Sobha');
      expect(UserProfile.mockManager().organizationName, 'Sobha');
      expect(UserProfile.mockStaff().organizationName, 'Sobha');
    });
  });

  group('SignupRequest Organization Integration Tests', () {
    test('SignupRequest defaults to Sobha and propagates to UserProfile', () {
      final req = SignupRequest(
        fullName: 'Carlos Gomez',
        email: 'carlos@company.com',
        phone: '+1 555 9876',
        designation: 'Site Inspector',
        department: 'Operations',
        site: 'Main Yard',
        requestedType: RequestedAccountType.staff,
      );

      expect(req.organizationId, Organization.sobhaId);
      expect(req.organizationName, Organization.sobhaName);

      final profile = req.toUserProfile();
      expect(profile.organizationId, Organization.sobhaId);
      expect(profile.organizationName, Organization.sobhaName);
    });

    test('SignupRequest copyWith handles organization fields', () {
      final req = SignupRequest(
        fullName: 'Maria Santos',
        email: 'maria@company.com',
        phone: '+1 555 4321',
        designation: 'Site Manager',
        department: 'Engineering',
        site: 'South Facility',
        requestedType: RequestedAccountType.manager,
      );

      final updated = req.copyWith(
        organizationId: 'org-sub-99',
        organizationName: 'Sobha Engineering',
      );

      expect(updated.organizationId, 'org-sub-99');
      expect(updated.organizationName, 'Sobha Engineering');
      expect(updated.toUserProfile().organizationId, 'org-sub-99');
      expect(updated.toUserProfile().organizationName, 'Sobha Engineering');
    });
  });

  group('AuthService & AuthProfileData Organization Resolution Tests', () {
    test('AuthProfileData defaults to Sobha organization', () {
      final profile = UserProfile.mockAdmin();
      final authData = AuthProfileData(
        userProfile: profile,
        roleCode: 'admin',
        status: 'active',
        isActive: true,
        isPrimaryAdmin: true,
      );

      expect(authData.organizationId, Organization.sobhaId);
      expect(authData.organization, isNotNull);
      expect(authData.organization?.id, Organization.sobhaId);
      expect(authData.organization?.code, Organization.sobhaCode);
      expect(authData.organization?.name, Organization.sobhaName);
    });

    test(
      'AuthService.parseProfileData extracts joined organizations relation',
      () {
        final rawRow = {
          'id': 'usr-admin-1',
          'full_name': 'Sobha System Admin',
          'email': 'sobha.admin@company.com',
          'phone': '+1 555 0000',
          'designation': 'Enterprise Administrator',
          'is_primary_admin': true,
          'status': 'active',
          'is_active': true,
          'roles': {'code': 'admin', 'name': 'System Administrator'},
          'departments': {
            'name': 'Enterprise Administration',
            'division': 'Governance',
          },
          'sites': {'name': 'Corporate HQ'},
          'organizations': {
            'id': '00000000-0000-0000-0000-000000000001',
            'name': 'Sobha',
            'code': 'sobha',
            'is_active': true,
          },
        };

        final profileData = AuthService.parseProfileData(rawRow, 'usr-admin-1');

        expect(profileData.roleCode, 'admin');
        expect(profileData.isPrimaryAdmin, isTrue);
        expect(profileData.organizationId, Organization.sobhaId);
        expect(profileData.organization, isNotNull);
        expect(profileData.organization?.name, 'Sobha');
        expect(profileData.organization?.code, 'sobha');
        expect(profileData.userProfile.organizationId, Organization.sobhaId);
        expect(profileData.userProfile.organizationName, 'Sobha');
      },
    );

    test('AuthService.parseProfileData resolves organization_id fallback gracefully', () {
      final rawRow = {
        'id': 'usr-manager-2',
        'full_name': 'HSE Manager',
        'email': 'manager@sobha.internal',
        'organization_id': '00000000-0000-0000-0000-000000000001',
        'roles': {'code': 'manager', 'name': 'Manager'},
        'status': 'active',
        'is_active': true,
      };

      final profileData = AuthService.parseProfileData(rawRow, 'usr-manager-2');

      expect(profileData.roleCode, 'manager');
      expect(profileData.organizationId, Organization.sobhaId);
      expect(profileData.organization, isNotNull);
      expect(profileData.organization?.code, Organization.sobhaCode);
      expect(profileData.organization?.name, Organization.sobhaName);
    });

    test('AuthService.parseProfileData gracefully falls back to Sobha if no org fields exist', () {
      // Pre-migration compatibility test: profiles table has no organization columns yet
      final rawRow = {
        'id': 'usr-legacy-3',
        'full_name': 'Legacy Worker',
        'email': 'worker@sobha.internal',
        'roles': {'code': 'staff', 'name': 'Staff'},
        'status': 'active',
        'is_active': true,
      };

      final profileData = AuthService.parseProfileData(rawRow, 'usr-legacy-3');

      expect(profileData.roleCode, 'staff');
      expect(profileData.organizationId, Organization.sobhaId);
      expect(profileData.organization, isNotNull);
      expect(profileData.organization?.id, Organization.sobhaId);
      expect(profileData.organization?.name, Organization.sobhaName);
      expect(profileData.userProfile.organizationId, Organization.sobhaId);
      expect(profileData.userProfile.organizationName, Organization.sobhaName);
    });

    test('AuthService organization lookups fall back to Sobha in offline test mode', () async {
      final authService = AuthService.instance;

      final sobhaByCode = await authService.fetchOrganizationByCode('sobha');
      expect(sobhaByCode, isNotNull);
      expect(sobhaByCode!.id, Organization.sobhaId);
      expect(sobhaByCode.name, Organization.sobhaName);

      final sobhaById = await authService.fetchOrganizationById(
        Organization.sobhaId,
      );
      expect(sobhaById, isNotNull);
      expect(sobhaById!.code, Organization.sobhaCode);

      final allOrgs = await authService.fetchOrganizations();
      expect(allOrgs, isNotEmpty);
      expect(allOrgs.first.code, Organization.sobhaCode);
    });
  });
}
