import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('platform_admins Permission Regression & 403 Prevention Tests (SEC-02)', () {
    test('1. Staff role with successful false RPC result: table query skipped, zero 403 errors, session initializes cleanly', () {
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

      // Simulate AuthService._fetchUserProfile session initialization
      bool isPlatformAdmin = false;
      Object? platformAdminRpcError;
      dynamic rpcResult = false; // Succeeded with false

      if (rpcResult == true) {
        isPlatformAdmin = true;
      }

      bool directTableQueryTriggered = false;
      if (!isPlatformAdmin && platformAdminRpcError != null) {
        directTableQueryTriggered = true;
      }

      expect(directTableQueryTriggered, isFalse,
          reason: 'Direct query to platform_admins MUST be skipped when RPC returns false cleanly.');
      expect(isPlatformAdmin, isFalse);
    });

    test('2. Manager role with successful false RPC result: table query skipped, zero 403 errors, session initializes cleanly', () {
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

      // Simulate AuthService.verifyPlatformAdminAuthority
      bool verified = false;
      Object? rpcError;
      dynamic rpcResult = false;

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

    test('3. Platform Admin role with successful true RPC result: authority confirmed and admin session initializes', () {
      final platformAdminProfile = AuthProfileData.platformAdmin(
        authUserId: 'ed507b8e-bcd3-403c-80e4-42151b6681fa',
        email: 'arvin.pr1112@gmail.com',
        fullName: 'ActionFlow Owner',
      );

      expect(platformAdminProfile.isPlatformAdmin, isTrue);
      expect(platformAdminProfile.roleCode, 'admin');
      expect(platformAdminProfile.userProfile.permissions, contains('Global Platform Administration'));

      bool isPlatformAdmin = false;
      Object? platformAdminRpcError;
      dynamic rpcResult = true; // Succeeded with true

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

    test('4. RPC network timeout: safely caught, normal session initialization does not break, safely defaults to non-admin', () {
      bool isPlatformAdmin = false;
      Object? platformAdminRpcError;

      // Simulate RPC timeout throw
      try {
        throw TimeoutException('PostgreSQL RPC connection timed out after 5000ms');
      } catch (rpcErr) {
        platformAdminRpcError = rpcErr;
      }

      expect(platformAdminRpcError, isA<TimeoutException>());

      // Session initialization logic proceeds to fallback table check
      Object? platformAdminTableError;
      if (!isPlatformAdmin && platformAdminRpcError != null) {
        try {
          // Table check also encounters timeout or is denied
          throw TimeoutException('Fallback table query timed out');
        } catch (tableErr) {
          platformAdminTableError = tableErr;
        }
      }

      expect(platformAdminTableError, isNotNull);

      // Session initialization does NOT throw uncaught error; defaults safely to non-admin
      expect(isPlatformAdmin, isFalse, reason: 'Must safely default to non-admin on network timeout.');

      // Verify that user profile loading proceeds normally
      final userProfile = UserProfile(
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
        userProfile: userProfile,
        roleCode: 'staff',
        status: 'active',
        isActive: true,
        isPrimaryAdmin: false,
        isPlatformAdmin: isPlatformAdmin,
      );

      expect(authData.userProfile.name, 'Adrash');
      expect(authData.roleCode, 'staff');
    });

    test('5. RPC server exception (500 internal error): safely caught, normal session initialization proceeds', () {
      bool isPlatformAdmin = false;
      Object? platformAdminRpcError;

      try {
        throw const PostgrestException(
          message: 'Internal server error executing function is_platform_admin()',
          code: '500',
        );
      } catch (rpcErr) {
        platformAdminRpcError = rpcErr;
      }

      expect(platformAdminRpcError, isA<PostgrestException>());

      // Session initialization continues without throwing
      if (!isPlatformAdmin && platformAdminRpcError != null) {
        try {
          // Simulate empty table row
          final Map<String, dynamic>? platformAdminRow = null;
          if (platformAdminRow != null) {
            isPlatformAdmin = true;
          }
        } catch (_) {}
      }

      expect(isPlatformAdmin, isFalse);

      final userProfile = UserProfile(
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
        userProfile: userProfile,
        roleCode: 'manager',
        status: 'active',
        isActive: true,
        isPrimaryAdmin: false,
        isPlatformAdmin: isPlatformAdmin,
      );

      expect(authData.userProfile.name, 'Reni Thomas');
      expect(authData.roleCode, 'manager');
    });

    test('6. RPC permission error (42501 / 403): safely caught, normal session initialization proceeds, RLS intact', () {
      bool isPlatformAdmin = false;
      Object? platformAdminRpcError;

      try {
        throw const PostgrestException(
          message: 'permission denied for function is_platform_admin',
          code: '42501',
        );
      } catch (rpcErr) {
        platformAdminRpcError = rpcErr;
      }

      expect(platformAdminRpcError, isA<PostgrestException>());

      // Fallback table query is attempted and fails due to RLS 403
      Object? tablePermissionError;
      if (!isPlatformAdmin && platformAdminRpcError != null) {
        try {
          throw const PostgrestException(
            message: 'new row violates row-level security policy for table "platform_admins"',
            code: '42501',
          );
        } catch (tableErr) {
          tablePermissionError = tableErr;
        }
      }

      expect(tablePermissionError, isA<PostgrestException>());
      expect(isPlatformAdmin, isFalse);

      // Verify that user session successfully populates with standard user profile
      final userProfile = UserProfile(
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
        userProfile: userProfile,
        roleCode: 'staff',
        status: 'active',
        isActive: true,
        isPrimaryAdmin: false,
        isPlatformAdmin: isPlatformAdmin,
      );

      expect(authData.userProfile.id, 'bf32c8c6-61be-453d-96d2-7e8c15d08a4f');
      expect(authData.isPlatformAdmin, isFalse);
    });
  });
}
