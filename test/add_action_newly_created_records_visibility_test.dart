import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/add_action_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/models/team.dart';
import 'package:action_flow/models/action_section.dart';
import 'package:action_flow/models/division.dart';
import 'package:action_flow/services/action_section_service.dart';
import 'package:action_flow/services/company_structure_service.dart';
import 'package:action_flow/services/division_service.dart';
import 'package:action_flow/services/user_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MockStructureService extends CompanyStructureService {
  final List<Map<String, dynamic>> departments;
  final List<Map<String, dynamic>> sites;
  final List<Map<String, dynamic>> teams;

  MockStructureService({
    required this.departments,
    required this.sites,
    required this.teams,
  });

  @override
  Future<List<Map<String, dynamic>>> fetchDepartments(String organizationId) async => departments;

  @override
  Future<List<Map<String, dynamic>>> fetchSites(String organizationId) async => sites;

  @override
  Future<List<Map<String, dynamic>>> fetchTeams(String organizationId) async => teams;
}

class MockDivisionService extends DivisionService {
  final List<Division> divisions;
  MockDivisionService({required this.divisions});

  @override
  Future<List<Division>> fetchDivisions(String organizationId, {bool onlyActive = false}) async => divisions;
}

class MockSectionService extends ActionSectionService {
  final List<ActionSection> sections;
  MockSectionService({required this.sections});

  @override
  Future<List<ActionSection>> fetchSections(String organizationId, {bool onlyActive = false}) async => sections;
}

class MockUserService extends UserService {
  final List<Person> users;
  MockUserService({required this.users});

  @override
  Future<List<Person>> fetchUsers(String organizationId, {bool allowMockFallback = true}) async => users;
}

void main() {
  const orgId = '00000000-0000-0000-0000-000000000001';

  final initialDepartments = [
    {'id': 'dept-1', 'name': 'Health & Safety', 'is_active': true, 'organization_id': orgId},
    {'id': 'dept-2', 'name': 'Operations', 'is_active': true, 'organization_id': orgId},
  ];

  final initialSites = [
    {'id': 'site-1', 'name': 'Dubai Main Office', 'is_active': true, 'organization_id': orgId},
  ];

  final initialUsers = <Person>[
    Person(
      id: 'user-mgr-1',
      name: 'Existing Manager',
      email: 'manager@test.local',
      phone: '+971 50 111 2222',
      designation: 'Operations Lead',
      role: UserRole.departmentManager,
      type: PersonType.internalUser,
      isActive: true,
      department: 'Health & Safety',
      departmentId: 'dept-1',
      site: 'Dubai Main Office',
      siteId: 'site-1',
      organizationId: orgId,
    ),
    Person(
      id: 'user-staff-1',
      name: 'Existing Staff',
      email: 'staff1@test.local',
      phone: '+971 50 222 3333',
      designation: 'HSE Inspector',
      role: UserRole.actionOwnerWorker,
      type: PersonType.internalUser,
      isActive: true,
      department: 'Health & Safety',
      departmentId: 'dept-1',
      site: 'Dubai Main Office',
      siteId: 'site-1',
      organizationId: orgId,
    ),
  ];

  testWidgets('Add Action displays newly created Department, Site and Staff user', (tester) async {
    // Include newly created Department, Site, and Staff user
    final departmentsWithNew = [
      ...initialDepartments,
      {'id': 'dept-new', 'name': 'Quality Assurance', 'is_active': true, 'organization_id': orgId},
    ];

    final sitesWithNew = [
      ...initialSites,
      {'id': 'site-new', 'name': 'North Coast Plant', 'is_active': true, 'organization_id': orgId},
    ];

    final usersWithNew = <Person>[
      ...initialUsers,
      Person(
        id: 'user-staff-new',
        name: 'Alice QA Staff',
        email: 'alice_qa@test.local',
        phone: '+971 50 333 4444',
        designation: 'QA Inspector',
        role: UserRole.actionOwnerWorker,
        type: PersonType.internalUser,
        isActive: true,
        department: 'Quality Assurance',
        departmentId: 'dept-new',
        site: 'North Coast Plant',
        siteId: 'site-new',
        organizationId: orgId,
      ),
    ];

    final mockStructure = MockStructureService(
      departments: departmentsWithNew,
      sites: sitesWithNew,
      teams: [],
    );
    final mockDivisions = MockDivisionService(divisions: []);
    final mockSections = MockSectionService(sections: []);
    final mockUsers = MockUserService(users: usersWithNew);

    final managerContext = ManagerContext(
      authUserId: 'user-mgr-1',
      organizationName: 'Sobha',
      organizationId: orgId,
      profile: const UserProfile(
        id: 'user-mgr-1',
        name: 'Existing Manager',
        email: 'manager@test.local',
        phone: '+971 50 111 2222',
        designation: 'Operations Lead',
        department: 'Health & Safety',
        division: 'Operations',
        site: 'Dubai Main Office',
        team: 'Lead Team',
        role: 'manager',
        supervisor: 'Director',
        certifications: 'NEBOSH',
        accountStatus: 'active',
        permissions: [],
        organizationId: orgId,
      ),
      scopes: const [
        // Manager has department-wide scope across both departments, without site constraints
        ManagerScopeItem(
          id: 'scope-1',
          departmentId: 'dept-1',
          departmentName: 'Health & Safety',
          siteId: '',
          siteName: '',
        ),
        ManagerScopeItem(
          id: 'scope-2',
          departmentId: 'dept-new',
          departmentName: 'Quality Assurance',
          siteId: '',
          siteName: '',
        ),
      ],
    );

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddActionScreen(
            actionId: 'AUTO',
            organizationId: orgId,
            managerContext: managerContext,
            companyStructureService: mockStructure,
            divisionService: mockDivisions,
            actionSectionService: mockSections,
            userService: mockUsers,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify initial department is displayed
    expect(find.text('Health & Safety'), findsWidgets);

    // Open Department dropdown
    final deptDropdown = find.widgetWithText(
      DropdownButtonFormField<String>,
      'Department *',
    );
    await tester.ensureVisible(deptDropdown);
    await tester.tap(deptDropdown);
    await tester.pumpAndSettle();

    // Verify newly created Department "Quality Assurance" is selectable
    expect(find.text('Quality Assurance').last, findsOneWidget);
    await tester.tap(find.text('Quality Assurance').last);
    await tester.pumpAndSettle();

    // Open Site dropdown
    final siteDropdown = find.widgetWithText(
      DropdownButtonFormField<String>,
      'Location / Site *',
    );
    await tester.ensureVisible(siteDropdown);
    await tester.tap(siteDropdown);
    await tester.pumpAndSettle();

    // Verify newly created Site "North Coast Plant" is selectable
    expect(find.text('North Coast Plant').last, findsOneWidget);
    await tester.tap(find.text('North Coast Plant').last);
    await tester.pumpAndSettle();

    // Search and assign newly created Staff user Alice
    final searchField = find.widgetWithText(
      TextFormField,
      'Search by name, email, or phone...',
    );
    await tester.ensureVisible(searchField);
    await tester.enterText(searchField, 'Alice');
    await tester.pumpAndSettle();

    expect(find.text('Alice QA Staff'), findsWidgets);
    await tester.tap(find.text('Alice QA Staff').first);
    await tester.pumpAndSettle();

    expect(find.text('Alice QA Staff'), findsWidgets);
    expect(find.text('Primary'), findsOneWidget);
  });

  testWidgets('Admin user sees all departments and independent sites', (tester) async {
    final departmentsWithNew = [
      ...initialDepartments,
      {'id': 'dept-new-2', 'name': 'Logistics', 'is_active': true, 'organization_id': orgId},
    ];

    final sitesWithNew = [
      ...initialSites,
      {'id': 'site-new-2', 'name': 'Offshore Terminal', 'is_active': true, 'organization_id': orgId},
    ];

    final mockStructure = MockStructureService(
      departments: departmentsWithNew,
      sites: sitesWithNew,
      teams: [],
    );
    final mockDivisions = MockDivisionService(divisions: []);
    final mockSections = MockSectionService(sections: []);
    final mockUsers = MockUserService(users: initialUsers);

    // Admin profile
    final adminContext = ManagerContext(
      authUserId: 'user-admin-1',
      organizationName: 'Sobha',
      organizationId: orgId,
      profile: const UserProfile(
        id: 'user-admin-1',
        name: 'Company Admin',
        email: 'admin@test.local',
        phone: '+971 50 999 8888',
        designation: 'Company Admin',
        department: 'Governance',
        division: 'Management',
        site: 'Dubai Main Office',
        team: 'Admin Team',
        role: 'admin',
        supervisor: 'Board',
        certifications: 'ITIL',
        accountStatus: 'active',
        permissions: [],
        organizationId: orgId,
      ),
      scopes: const [],
    );

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddActionScreen(
            actionId: 'AUTO',
            organizationId: orgId,
            managerContext: adminContext,
            companyStructureService: mockStructure,
            divisionService: mockDivisions,
            actionSectionService: mockSections,
            userService: mockUsers,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Logistics department is available in Department dropdown
    final deptDropdown = find.widgetWithText(
      DropdownButtonFormField<String>,
      'Department *',
    );
    await tester.ensureVisible(deptDropdown);
    await tester.tap(deptDropdown);
    await tester.pumpAndSettle();
    expect(find.text('Logistics').last, findsOneWidget);

    // Select Logistics
    await tester.tap(find.text('Logistics').last);
    await tester.pumpAndSettle();

    // Verify Offshore Terminal site is available independently
    final siteDropdown = find.widgetWithText(
      DropdownButtonFormField<String>,
      'Location / Site *',
    );
    await tester.ensureVisible(siteDropdown);
    await tester.tap(siteDropdown);
    await tester.pumpAndSettle();
    expect(find.text('Offshore Terminal').last, findsOneWidget);
  });
}
