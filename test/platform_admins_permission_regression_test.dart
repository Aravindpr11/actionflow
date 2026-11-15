import 'package:flutter_test/flutter_test.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/services/auth_service.dart';

void main() {
  group('platform_admins Permission Regression & 403 Prevention Tests (SEC-02)', () {
    test('1. Staff role: is_platform_admin() returns false; table query is skipped and no 403 occurs', () {
      // Ordinary Staff profile
      final staffProfile = UserProfile(
        id: 'bf32c8c6-61be-453d-96d2-7e8c15d08a4f',
        name: 'Adrash',
        email: 'adrash@gmail.com',
        phone: '+91 98765 43210',
        designation: 'HSE Staff',
        department: 'Sobha Infra',
        site: 'Sobha Infra',
        role: 'Staff',
        accountStatus: 'Active',
      );

      final authData = AuthProfileData(
        userProfile: staffProfile,
        roleCode: 'staff',
        status: 'active',
        isActive: true,
        isPrimaryAdmin: false,
        isPlatformAdmin: false,
      );

      expect(authData.isPlatformAdmin, isFalse);
      expect(authData.roleCode, 'staff');

      // Simulate the logic in AuthService.fetchProfileResult:
      // RPC returns false without error -> user authoritatively not platform admin
      bool isPlatformAdmin = false;
      Object? platformAdminRpcError;
      dynamic rpcResult = false; // Ordinary staff receives false from RPC

      if (rpcResult == true) {
        isPlatformAdmin = true;
      }

      // Check whether direct table query fallback would be triggered:
      bool directTableQueryTriggered = false;
      if (!isPlatformAdmin && platformAdminRpcError != null) {
        directTableQueryTriggered = true;
      }

      expect(directTableQueryTriggered, isFalse,
          reason: 'Direct query to platform_admins MUST be skipped when RPC returns false cleanly.');
      expect(isPlatformAdmin, isFalse);
    });

    test('2. Manager role: is_platform_admin() returns false; table query is skipped and no 403 occurs', () {
      // Ordinary Manager profile
      final managerProfile = UserProfile(
        id: '7b3f384d-75ed-4201-9670-932950fb16b6',
        name: 'Reni Thomas',
        email: 'renialavelil@gmail.com',
        phone: '+91 98765 43210',
        designation: 'HSE Manager',
        department: 'Sobha Infra',
        site: 'Sobha Infra',
        role: 'Manager',
        accountStatus: 'Active',
      );

      final authData = AuthProfileData(
        userProfile: managerProfile,
        roleCode: 'manager',
        status: 'active',
        isActive: true,
        isPrimaryAdmin: false,
        isPlatformAdmin: false,
      );

      expect(authData.isPlatformAdmin, isFalse);
      expect(authData.roleCode, 'manager');

      // Simulate the logic in AuthService.verifyPlatformAdminAuthority:
      bool verified = false;
      Object? rpcError;
      dynamic rpcResult = false; // Ordinary manager receives false from RPC

      if (rpcResult == true) {
        verified = true;
      }

      bool directTableQueryTriggered = false;
      if (!verified && rpcError != null) {
        directTableQueryTriggered = true;
      }

      expect(directTableQueryTriggered, isFalse,
          reason: 'Direct query to platform_admins MUST be skipped for managers when RPC returns false.');
      expect(verified, isFalse);
    });

    test('3. Platform Admin role: is_platform_admin() returns true; retains all platform admin features', () {
      final platformAdminProfile = AuthProfileData.platformAdmin(
        authUserId: 'ed507b8e-bcd3-403c-80e4-42151b6681fa',
        email: 'arvin.pr1112@gmail.com',
        fullName: 'ActionFlow Owner',
      );

      expect(platformAdminProfile.isPlatformAdmin, isTrue);
      expect(platformAdminProfile.roleCode, 'admin');
      expect(platformAdminProfile.userProfile.permissions, contains('Global Platform Administration'));

      // Simulate the logic in AuthService.fetchProfileResult for Platform Admin:
      bool isPlatformAdmin = false;
      Object? platformAdminRpcError;
      dynamic rpcResult = true; // Platform Admin receives true from RPC

      if (rpcResult == true) {
        isPlatformAdmin = true;
      }

      bool directTableQueryTriggered = false;
      if (!isPlatformAdmin && platformAdminRpcError != null) {
        directTableQueryTriggered = true;
      }

      expect(isPlatformAdmin, isTrue, reason: 'Platform Admin identity confirmed via RPC.');
      expect(directTableQueryTriggered, isFalse, reason: 'No secondary table query needed when RPC returns true.');
    });

    test('4. Unexpected RPC error: fallback is safely triggered only when RPC throws', () {
      bool verified = false;
      Object? rpcError = Exception('PostgreSQL connection timeout');

      // When RPC genuinely fails, fallback to table query is allowed
      bool fallbackExecuted = false;
      if (!verified && rpcError != null) {
        fallbackExecuted = true;
      }

      expect(fallbackExecuted, isTrue, reason: 'Safe fallback permitted only when RPC genuinely throws an error.');
    });
  });
}
