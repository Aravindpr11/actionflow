import 'dart:io';
import 'package:action_flow/core/routing/auth_router.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  setUpAll(() {
    HttpOverrides.global = _RealHttpOverrides();
  });

  group('Webonant Test Account - Manager Conversion & Routing Verification', () {
    testWidgets(
      'Login with webonant@gmail.com Manager profile routes to ManagerDashboardScreen and NOT WorkerDashboardScreen',
      (tester) async {
        // Construct AuthProfileData matching the exact database row for webonant@gmail.com
        final webonantProfile = AuthProfileData(
          userProfile: const UserProfile(
            id: '878d9145-7764-411f-8d26-f30f01e99e79',
            name: 'Manager',
            email: 'webonant@gmail.com',
            phone: '',
            role: 'Manager',
            designation: 'HSE',
            department: 'HSE / Safety',
            site: 'test',
          ),
          roleCode: 'manager',
          status: 'active',
          isActive: true,
          isPrimaryAdmin: false,
          isPlatformAdmin: false,
          organizationId: '00000000-0000-0000-0000-000000000001',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    AuthRouter.navigateToRolePortal(context, webonantProfile),
                child: const Text('Login As Webonant'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Login As Webonant'));
        await tester.pumpAndSettle();

        // 1. Must route to Manager Portal
        expect(find.byType(ManagerDashboardScreen), findsOneWidget);

        // 2. Must NOT route to Staff / Worker Portal
        expect(find.byType(WorkerDashboardScreen), findsNothing);
      },
    );

    test('Remote Supabase verification for webonant@gmail.com', () async {
      final client = SupabaseClient(
        'https://mxaptaudaqrtwiguosvt.supabase.co',
        'sb_publishable_RUdq4T4DCvSNwPHx5cEaNQ_ppYiVTol',
      );

      // Verify active organizations
      final orgs = await client
          .from('organizations')
          .select('id, name')
          .eq('id', '00000000-0000-0000-0000-000000000001');
      expect(orgs, isNotEmpty);
      expect(orgs.first['name'], equals('Sobha'));

      // Verify public departments & sites for manager scopes
      final depts = await client.from('departments').select('id, name').inFilter(
        'id',
        [
          'f0ad05aa-c85a-40e5-b309-19f1e6629e7a',
          '6000544e-dfe7-4911-b2cc-4c4bebead468',
        ],
      );
      expect(depts.length, equals(2));

      final sites = await client.from('sites').select('id, name').inFilter(
        'id',
        [
          '6abf4ba5-e8b7-4076-8c97-80f4a354f94b',
          '46a89a44-c577-47d6-bb95-3488c1f7562e',
        ],
      );
      expect(sites.length, equals(2));
    });
  });
}
