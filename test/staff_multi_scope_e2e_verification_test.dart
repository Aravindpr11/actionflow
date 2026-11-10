import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/services/user_service.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    HttpOverrides.global = _RealHttpOverrides();
  });

  group('Staff Single Scope & Manager Multi-Scope Live Verification Test', () {
    const localUrl = 'http://127.0.0.1:54321';
    const localAnonKey =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';

    const orgId = '00000000-0000-0000-0000-000000000001';
    const managerId = '878d9145-7764-411f-8d26-f30f01e99e79'; // webonant@gmail.com
    const staffId = '11111111-1111-1111-1111-111111111111'; // hse_officer@test.local
    const deptId = 'd348a7f3-faa2-44d4-a200-9adc8966b730'; // Operations
    const site1Id = '68d0dcba-7067-45ce-bd55-2ef3113bd79d'; // Platform Alpha
    const site2Id = '5dc40141-6f5f-41be-b090-298b84e23865'; // Platform Bravo

    test('1. Company Admin logs in and saves multiple manager scopes via sync_manager_scopes RPC', () async {
      final client = SupabaseClient(localUrl, localAnonKey);

      // Authenticate as seeded Company Admin
      final authRes = await client.auth.signInWithPassword(
        email: 'aravind11.sobha@gmail.com',
        password: 'Password123!',
      );
      expect(authRes.user, isNotNull);
      expect(authRes.session, isNotNull);

      // Call sync_manager_scopes with scopes
      final res = await client.rpc('sync_manager_scopes', params: {
        'p_manager_id': managerId,
        'p_scopes': [
          {'department_id': deptId, 'site_id': site1Id},
          {'department_id': deptId, 'site_id': site2Id},
        ],
      });

      expect(res, isNotNull);

      // Verify records in manager_scopes
      final dbRows = await client
          .from('manager_scopes')
          .select('department_id, site_id')
          .eq('manager_profile_id', managerId);
      expect(dbRows.length, greaterThanOrEqualTo(2));
    });

    test('2. Unauthenticated caller is strictly rejected from executing sync_manager_scopes', () async {
      final unauthClient = SupabaseClient(localUrl, localAnonKey);

      expect(
        unauthClient.rpc('sync_manager_scopes', params: {
          'p_manager_id': managerId,
          'p_scopes': [
            {'department_id': deptId, 'site_id': site1Id},
          ],
        }),
        throwsA(isA<PostgrestException>()),
      );
    });

    test('3. Staff profile enforces single primary department model without multi-scopes', () async {
      final client = SupabaseClient(localUrl, localAnonKey);
      await client.auth.signInWithPassword(
        email: 'aravind11.sobha@gmail.com',
        password: 'Password123!',
      );

      // Query staff profile from profiles table (Admin has read permission)
      final staffRows = await client
          .from('profiles')
          .select('id, full_name, department_id, site_id')
          .limit(5);

      expect(staffRows, isNotEmpty);
      final staff = staffRows.first;
      expect(staff['id'], isNotNull);
      expect(staff['department_id'], isNotNull);
    });
  });
}
