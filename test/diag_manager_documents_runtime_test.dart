import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/services/user_service.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  setUpAll(() {
    HttpOverrides.global = _RealHttpOverrides();
  });

  test('Diagnose Manager Documents Sharing Runtime End to End', () async {
    const supabaseUrl = 'https://mxaptaudaqrtwiguosvt.supabase.co';
    const supabaseAnonKey = 'sb_publishable_RUdq4T4DCvSNwPHx5cEaNQ_ppYiVTol';

    final client = SupabaseClient(supabaseUrl, supabaseAnonKey);

    print('=== DIAGNOSTIC 1: AUTHENTICATION ===');
    final authRes = await client.auth.signInWithPassword(
      email: 'webonant@gmail.com',
      password: 'Password123!',
    );
    final user = authRes.user!;
    print('Authenticated User ID: ${user.id}');
    print('Authenticated Email: ${user.email}');

    // Initialize SupabaseConfig client wrapper for services
    SupabaseConfig.isInitializedForTesting = true;

    print('\n=== DIAGNOSTIC 2: RECENT DOCUMENTS IN SUPABASE ===');
    final recentDocs = await client
        .from('documents')
        .select('id, title, file_name, department_id, action_id, category, created_by, created_at')
        .order('created_at', ascending: false)
        .limit(5);
    for (final d in recentDocs) {
      print('Doc: id=${d['id']}, title="${d['title']}", fileName="${d['file_name']}", deptId=${d['department_id']}, actionId=${d['action_id']}, created_by=${d['created_by']}, created_at=${d['created_at']}');
    }

    print('\n=== DIAGNOSTIC 3: MANAGER PROFILE & SCOPES ===');
    final profileRes = await client
        .from('profiles')
        .select('id, full_name, email, organization_id, department_id, site_id, roles(name, code)')
        .eq('id', user.id)
        .single();
    print('Manager Profile: $profileRes');

    final scopesRes = await client
        .from('manager_scopes')
        .select('id, department_id, site_id, departments(id, name), sites(id, name)')
        .eq('manager_profile_id', user.id);
    print('Manager Scopes Count: ${scopesRes.length}');
    for (final s in scopesRes) {
      print('  Scope: dept="${s['departments']?['name']}" (${s['department_id']}), site="${s['sites']?['name']}" (${s['site_id']})');
    }

    print('\n=== DIAGNOSTIC 4: WHAT PROFILES TABLE RETURNS FOR MANAGER ===');
    final orgId = profileRes['organization_id'].toString();
    final rawProfiles = await client
        .from('profiles')
        .select('id, full_name, email, department_id, site_id, role_id, is_active, status')
        .eq('organization_id', orgId);
    print('Raw Profiles count returned by "profiles" table: ${rawProfiles.length}');
    for (final p in rawProfiles) {
      print('  Profile: id=${p['id']}, name="${p['full_name']}", email="${p['email']}", deptId=${p['department_id']}, siteId=${p['site_id']}, active=${p['is_active']}, status=${p['status']}');
    }

    print('\n=== DIAGNOSTIC 5: WHAT DIRECTORY_PROFILES VIEW RETURNS FOR MANAGER ===');
    try {
      final dirProfiles = await client
          .from('directory_profiles')
          .select('id, full_name, email, department_id, site_id, role_code, is_active')
          .eq('organization_id', orgId);
      print('Directory Profiles count returned by "directory_profiles" view: ${dirProfiles.length}');
      for (final dp in dirProfiles) {
        print('  DirProfile: id=${dp['id']}, name="${dp['full_name']}", email="${dp['email']}", deptId=${dp['department_id']}, role=${dp['role_code']}, active=${dp['is_active']}');
      }
    } catch (e) {
      print('Error querying directory_profiles: $e');
    }

    print('\n=== DIAGNOSTIC 6: USER SERVICE FETCH USERS ===');
    final userService = UserService(client: client);
    final users = await userService.fetchUsers(orgId, allowMockFallback: false);
    print('UserService.fetchUsers count: ${users.length}');
    for (final u in users) {
      print('  User: id=${u.id}, name="${u.name}", email="${u.email}", role="${u.roleLabel}", dept="${u.department}" (${u.departmentId}), site="${u.site}" (${u.siteId}), active=${u.isActive}, type=${u.type}');
    }

    await client.dispose();
  });
}

