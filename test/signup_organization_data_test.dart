import 'package:action_flow/features/auth/models/manager_scope_item.dart';
import 'package:action_flow/features/auth/screens/manager_account_setup_screen.dart';
import 'package:action_flow/features/auth/screens/staff_account_setup_screen.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MockOrgAuthService extends AuthService {
  final List<Organization> mockOrgs;
  final List<DepartmentOption> mockDepts;
  final List<SiteOption> mockSites;
  final List<TeamOption> mockTeams;

  String? lastOrgIdForDepts;
  String? lastOrgIdForSites;
  String? lastOrgIdForTeams;

  MockOrgAuthService({
    required this.mockOrgs,
    required this.mockDepts,
    required this.mockSites,
    required this.mockTeams,
  }) : super.forTesting();

  @override
  bool get hasClient => true;

  @override
  Future<List<Organization>> fetchOrganizations({
    bool activeOnly = true,
  }) async {
    return mockOrgs;
  }

  @override
  Future<List<DepartmentOption>> fetchDepartments({
    String? organizationId,
    bool fallbackToDefaults = false,
  }) async {
    lastOrgIdForDepts = organizationId;
    return mockDepts;
  }

  @override
  Future<List<SiteOption>> fetchSites({
    String? organizationId,
    bool fallbackToDefaults = false,
  }) async {
    lastOrgIdForSites = organizationId;
    return mockSites;
  }

  @override
  Future<List<TeamOption>> fetchTeams({
    String? organizationId,
    bool fallbackToDefaults = false,
  }) async {
    lastOrgIdForTeams = organizationId;
    return mockTeams;
  }
}

void main() {
  const sobhaOrg = Organization(
    id: Organization.sobhaId,
    name: Organization.sobhaName,
    code: Organization.sobhaCode,
    isActive: true,
  );

  const secondOrg = Organization(
    id: '00000000-0000-0000-0000-000000000002',
    name: 'Al Futtaim',
    code: 'alfuttaim',
    isActive: true,
  );

  final testDepts = [
    const DepartmentOption(
      id: 'd1111111-1111-1111-1111-111111111111',
      name: 'HSE / Safety',
      code: 'HSE',
    ),
    const DepartmentOption(
      id: 'd2222222-2222-2222-2222-222222222222',
      name: 'Operations',
      code: 'OPS',
    ),
  ];

  final testSites = [
    const SiteOption(
      id: 's1111111-1111-1111-1111-111111111111',
      name: 'Platform Alpha',
      code: 'PLT-A',
    ),
  ];

  final testTeams = [
    const TeamOption(
      id: 't1111111-1111-1111-1111-111111111111',
      name: 'HSE Audit Team',
      departmentId: 'd1111111-1111-1111-1111-111111111111',
    ),
  ];

  group('Signup Organization Data Loading & Isolation', () {
    testWidgets(
      'ManagerAccountSetupScreen displays single company badge and scopes correctly',
      (tester) async {
        final authService = MockOrgAuthService(
          mockOrgs: [sobhaOrg],
          mockDepts: testDepts,
          mockSites: testSites,
          mockTeams: testTeams,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ManagerAccountSetupScreen(authService: authService),
          ),
        );
        await tester.pumpAndSettle();

        // Verify company badge is shown
        expect(find.text('Company: '), findsOneWidget);
        expect(find.text('Sobha'), findsOneWidget);

        // Verify organization dropdown is not needed when only 1 org
        expect(
          find.byKey(const ValueKey('manager_org_dropdown')),
          findsNothing,
        );

        // Verify fetch was called with Sobha org ID
        expect(authService.lastOrgIdForDepts, equals(Organization.sobhaId));
        expect(authService.lastOrgIdForSites, equals(Organization.sobhaId));

        // Verify department is displayed
        expect(find.text('HSE / Safety'), findsWidgets);
      },
    );

    testWidgets(
      'ManagerAccountSetupScreen displays organization dropdown when multiple orgs exist',
      (tester) async {
        final authService = MockOrgAuthService(
          mockOrgs: [sobhaOrg, secondOrg],
          mockDepts: testDepts,
          mockSites: testSites,
          mockTeams: testTeams,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ManagerAccountSetupScreen(authService: authService),
          ),
        );
        await tester.pumpAndSettle();

        // Verify company dropdown is displayed
        expect(
          find.byKey(const ValueKey('manager_org_dropdown')),
          findsOneWidget,
        );
        expect(find.text('Sobha'), findsWidgets);
      },
    );

    testWidgets(
      'StaffAccountSetupScreen displays single company badge and filters teams by dept',
      (tester) async {
        final authService = MockOrgAuthService(
          mockOrgs: [sobhaOrg],
          mockDepts: testDepts,
          mockSites: testSites,
          mockTeams: testTeams,
        );

        await tester.pumpWidget(
          MaterialApp(home: StaffAccountSetupScreen(authService: authService)),
        );
        await tester.pumpAndSettle();

        // Verify company badge
        expect(find.text('Company: '), findsOneWidget);
        expect(find.text('Sobha'), findsOneWidget);

        // Verify fetch was called with Sobha org ID
        expect(authService.lastOrgIdForDepts, equals(Organization.sobhaId));
        expect(authService.lastOrgIdForSites, equals(Organization.sobhaId));
        expect(authService.lastOrgIdForTeams, equals(Organization.sobhaId));

        // Check team dropdown shows HSE Audit Team when HSE is selected
        expect(
          find.byKey(ValueKey('staff_team_dropdown_${testDepts.first.id}')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'StaffAccountSetupScreen displays organization dropdown when multiple orgs exist',
      (tester) async {
        final authService = MockOrgAuthService(
          mockOrgs: [sobhaOrg, secondOrg],
          mockDepts: testDepts,
          mockSites: testSites,
          mockTeams: testTeams,
        );

        await tester.pumpWidget(
          MaterialApp(home: StaffAccountSetupScreen(authService: authService)),
        );
        await tester.pumpAndSettle();

        // Verify company dropdown is shown
        expect(
          find.byKey(const ValueKey('staff_org_dropdown')),
          findsOneWidget,
        );
      },
    );
  });
}
