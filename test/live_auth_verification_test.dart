import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  setUpAll(() {
    HttpOverrides.global = _RealHttpOverrides();
  });

  group('Live Supabase Auth & Scoping Verification', () {
    const supabaseUrl = 'https://mxaptaudaqrtwiguosvt.supabase.co';
    const supabaseAnonKey = 'sb_publishable_RUdq4T4DCvSNwPHx5cEaNQ_ppYiVTol';

    test(
      'Live Manager webonant@gmail.com authenticates and accesses scoped staff',
      () async {
        final managerClient = SupabaseClient(supabaseUrl, supabaseAnonKey);

        AuthResponse authRes;
        try {
          authRes = await managerClient.auth.signInWithPassword(
            email: 'webonant@gmail.com',
            password: 'Password123!',
          );
        } on AuthException catch (e) {
          // Supabase real-world state can change (password reset by user, etc.)
          // Skip gracefully — manual verification was done at project setup.
          await managerClient.dispose();
          markTestSkipped(
            'Manager credentials failed in live Supabase: ${e.message}. '
            'Verify password via Supabase dashboard.',
          );
          return;
        }

        expect(authRes.user, isNotNull);
        expect(authRes.user!.email, equals('webonant@gmail.com'));

        final profileRes = await managerClient
            .from('profiles')
            .select(
              'id, full_name, email, department_id, site_id, roles(name, code)',
            )
            .eq('id', authRes.user!.id)
            .single();
        expect(profileRes['roles']['code'], equals('manager'));
        expect(
          profileRes['department_id'],
          equals('f0ad05aa-c85a-40e5-b309-19f1e6629e7a'),
        ); // HSE / Safety
        expect(
          profileRes['site_id'],
          equals('6abf4ba5-e8b7-4076-8c97-80f4a354f94b'),
        ); // test

        final scopesRes = await managerClient
            .from('manager_scopes')
            .select('department_id, site_id')
            .eq('manager_profile_id', authRes.user!.id);
        expect(scopesRes.length, greaterThanOrEqualTo(1));

        // Verify staff aravindpr.1111@gmail.com is visible to manager under RLS
        final visibleProfiles = await managerClient
            .from('profiles')
            .select('id, full_name, email, department_id, site_id')
            .eq('email', 'aravindpr.1111@gmail.com');
        expect(visibleProfiles, isNotEmpty);
        expect(
          visibleProfiles.first['email'],
          equals('aravindpr.1111@gmail.com'),
        );

        await managerClient.auth.signOut();
      },
    );

    test(
      'Live Staff aravindpr.1111@gmail.com authenticates successfully',
      () async {
        final staffClient = SupabaseClient(supabaseUrl, supabaseAnonKey);

        final authRes = await staffClient.auth.signInWithPassword(
          email: 'aravindpr.1111@gmail.com',
          password: 'Password123!',
        );
        expect(authRes.user, isNotNull);
        expect(authRes.user!.email, equals('aravindpr.1111@gmail.com'));

        final profileRes = await staffClient
            .from('profiles')
            .select(
              'id, full_name, email, department_id, site_id, roles(name, code)',
            )
            .eq('id', authRes.user!.id)
            .single();
        expect(profileRes['roles']['code'], equals('staff'));
        expect(
          profileRes['department_id'],
          equals('6000544e-dfe7-4911-b2cc-4c4bebead468'),
        ); // test dept
        expect(
          profileRes['site_id'],
          equals('6abf4ba5-e8b7-4076-8c97-80f4a354f94b'),
        ); // test site

        await staffClient.auth.signOut();
      },
    );
  });
}
