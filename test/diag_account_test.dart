import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  setUpAll(() {
    HttpOverrides.global = _RealHttpOverrides();
  });
  test('Inspect remote database users, profiles, and account_requests', () async {
    final client = SupabaseClient(
      'https://mxaptaudaqrtwiguosvt.supabase.co',
      'sb_publishable_RUdq4T4DCvSNwPHx5cEaNQ_ppYiVTol',
    );

    try {
      print('=== AUDIT REMOTE USERS VIA get_system_users_audit() ===');
      final dynamic auditRes = await client.rpc('get_system_users_audit');
      if (auditRes is List) {
        print('Total system users in Supabase: ${auditRes.length}');
        for (final u in auditRes) {
          final m = Map<String, dynamic>.from(u as Map);
          print(
            'User: id=${m['user_id']}, email=${m['email']}, name=${m['full_name']}, role=${m['role_code']}, org=${m['org_name']} (${m['organization_id']}), active=${m['is_active']}, primary_admin=${m['is_primary_admin']}, scopes=${m['scopes_count']}, teams=${m['teams_count']}, actions_assigned=${m['actions_assigned_count']}, actions_created=${m['actions_created_count']}, protected=${m['is_protected']}',
          );
        }
      } else {
        print('Audit returned unexpected type: $auditRes');
      }

      print('\n=== AUDIT ACCOUNT REQUESTS ===');
      final dynamic reqs = await client.rpc(
        'get_system_account_requests_audit',
      );
      if (reqs is List) {
        print('Total account_requests in Supabase: ${reqs.length}');
        for (final r in reqs) {
          final m = Map<String, dynamic>.from(r as Map);
          print(
            'AccountRequest: id=${m['request_id']}, auth_id=${m['auth_user_id']}, email=${m['email']}, name=${m['full_name']}, status=${m['status']}, verified=${m['is_email_verified']}, org_id=${m['organization_id']}',
          );
        }
      } else {
        print('Account requests returned unexpected type: $reqs');
      }
    } catch (e) {
      print('Query error: $e');
    }

    print('\n=== REMOTE ORGANIZATIONS (anon query) ===');
    final orgs = await client
        .from('organizations')
        .select('id, name, code, is_active')
        .eq('is_active', true);
    print('Organizations: $orgs');
    expect(orgs, isNotEmpty);

    print('\n=== REMOTE DEPARTMENTS (anon query) ===');
    final depts = await client
        .from('departments')
        .select('id, name, code, is_active')
        .eq('is_active', true);
    print('Departments: $depts');
    expect(depts, isNotEmpty);

    print('\n=== REMOTE SITES (anon query) ===');
    final sites = await client
        .from('sites')
        .select('id, name, code, is_active')
        .eq('is_active', true);
    print('Sites: $sites');
    expect(sites, isNotEmpty);

    print('\n=== REMOTE TEAMS (anon query) ===');
    final teams = await client
        .from('teams')
        .select('id, name, department_id, is_active')
        .eq('is_active', true);
    print('Teams: $teams');
    expect(teams, isNotEmpty);
  });
}
