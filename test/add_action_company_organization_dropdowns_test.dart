import 'package:action_flow/features/auth/models/manager_scope_item.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/add_action_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
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

// ============================================================================
// MOCK SERVICES FOR MULTI-COMPANY ISOLATION AND TESTING
// ============================================================================

class MockMultiCompanyStructureService extends CompanyStructureService {
  final Map<String, List<Map<String, dynamic>>> departmentsByOrg;
  final Map<String, List<Map<String, dynamic>>> sitesByOrg;
  final Map<String, List<Map<String, dynamic>>> teamsByOrg;
  bool shouldThrow = false;

  MockMultiCompanyStructureService({
    required this.departmentsByOrg,
    required this.sitesByOrg,
    required this.teamsByOrg,
  });

  @override
  Future<List<Map<String, dynamic>>> fetchDepartments(String organizationId) async {
    if (shouldThrow) throw Exception('Simulated network error fetching departments');
    return departmentsByOrg[organizationId] ?? [];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchSites(String organizationId) async {
    if (shouldThrow) throw Exception('Simulated network error fetching sites');
    return sitesByOrg[organizationId] ?? [];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTeams(String organizationId) async {
    if (shouldThrow) throw Exception('Simulated network error fetching teams');
    return teamsByOrg[organizationId] ?? [];
  }
}

class MockMultiCompanyDivisionService extends DivisionService {
  final Map<String, List<Division>> divisionsByOrg;
  bool shouldThrow = false;

  MockMultiCompanyDivisionService({required this.divisionsByOrg});

  @override
  Future<List<Division>> fetchDivisions(String organizationId, {bool onlyActive = false}) async {
    if (shouldThrow) throw Exception('Simulated network error fetching divisions');
    return divisionsByOrg[organizationId] ?? [];
  }
}

class MockMultiCompanySectionService extends ActionSectionService {
  final Map<String, List<ActionSection>> sectionsByOrg;
  bool shouldThrow = false;

  MockMultiCompanySectionService({required this.sectionsByOrg});

  @override
  Future<List<ActionSection>> fetchSections(String organizationId, {bool onlyActive = false}) async {
    if (shouldThrow) throw Exception('Simulated network error fetching sections');
    return sectionsByOrg[organizationId] ?? [];
  }
}

class MockMultiCompanyUserService extends UserService {
  final Map<String, List<Person>> usersByOrg;
  bool shouldThrow = false;

  MockMultiCompanyUserService({required this.usersByOrg});

  @override
  Future<List<Person>> fetchUsers(String organizationId, {bool allowMockFallback = true}) async {
    if (shouldThrow) throw Exception('Simulated network error fetching users');
    return usersByOrg[organizationId] ?? [];
  }
}

void main() {
  const sobhaOrgId = '00000000-0000-0000-0000-000000000001';
  const acmeOrgId = '00000000-0000-0000-0000-000000000002';

  late MockMultiCompanyStructureService structureService;
  late MockMultiCompanyDivisionService divisionService;
  late MockMultiCompanySectionService sectionService;
  late MockMultiCompanyUserService userService;

  setUp(() {
    structureService = MockMultiCompanyStructureService(
      departmentsByOrg: {
        sobhaOrgId: [
          {'id': 'dept-sobha-1', 'name': 'Civil Engineering', 'status': 'Active'},
          {'id': 'dept-sobha-2', 'name': 'Finishing & Interiors', 'status': 'Active'},
        ],
        acmeOrgId: [
          {'id': 'dept-acme-1', 'name': 'Logistics & Fleet', 'status': 'Active'},
          {'id': 'dept-acme-2', 'name': 'Procurement', 'status': 'Active'},
        ],
      },
      sitesByOrg: {
        sobhaOrgId: [
          {'id': 'site-sobha-1', 'name': 'Sobha Hartland', 'status': 'Active'},
          {'id': 'site-sobha-2', 'name': 'Sobha Creek Vistas', 'status': 'Active'},
        ],
        acmeOrgId: [
          {'id': 'site-acme-1', 'name': 'Acme Central Hub', 'status': 'Active'},
        ],
      },
      teamsByOrg: {
        sobhaOrgId: [
          {'id': 'team-sobha-1', 'name': 'Concrete Team', 'department_id': 'dept-sobha-1', 'status': 'Active'},
        ],
        acmeOrgId: [
          {'id': 'team-acme-1', 'name': 'Dispatch Team', 'department_id': 'dept-acme-1', 'status': 'Active'},
        ],
      },
    );

    final now = DateTime.now();
    divisionService = MockMultiCompanyDivisionService(
      divisionsByOrg: {
        sobhaOrgId: [
          Division(
            id: 'div-sobha-1',
            name: 'Real Estate Development',
            code: 'RED',
            organizationId: sobhaOrgId,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        acmeOrgId: [
          Division(
            id: 'div-acme-1',
            name: 'Global Supply',
            code: 'GS',
            organizationId: acmeOrgId,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      },
    );

    sectionService = MockMultiCompanySectionService(
      sectionsByOrg: {
        sobhaOrgId: [
          ActionSection(
            id: 'sec-sobha-1',
            name: 'Quality Audit',
            organizationId: sobhaOrgId,
            createdAt: now,
            updatedAt: now,
          ),
          ActionSection(
            id: 'sec-sobha-2',
            name: 'Safety Observation',
            organizationId: sobhaOrgId,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        acmeOrgId: [
          ActionSection(
            id: 'sec-acme-1',
            name: 'Inventory Compliance',
            organizationId: acmeOrgId,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      },
    );

    userService = MockMultiCompanyUserService(
      usersByOrg: {
        sobhaOrgId: [
          Person(
            id: 'user-sobha-civil-1',
            name: 'Vikram Mehta',
            email: 'vikram.mehta@sobha.com',
            phone: '+971 50 111 2222',
            designation: 'Lead Civil Engineer',
            type: PersonType.internalUser,
            isActive: true,
            department: 'Civil Engineering',
            departmentId: 'dept-sobha-1',
            site: 'Sobha Hartland',
            siteId: 'site-sobha-1',
          ),
          Person(
            id: 'user-sobha-finish-1',
            name: 'Priya Nair',
            email: 'priya.nair@sobha.com',
            phone: '+971 50 333 4444',
            designation: 'Interiors Specialist',
            type: PersonType.internalUser,
            isActive: true,
            department: 'Finishing & Interiors',
            departmentId: 'dept-sobha-2',
            site: 'Sobha Creek Vistas',
            siteId: 'site-sobha-2',
          ),
        ],
        acmeOrgId: [
          Person(
            id: 'user-acme-logistics-1',
            name: 'John Miller',
            email: 'john.miller@acme.com',
            phone: '+1 555 123 4567',
            designation: 'Fleet Manager',
            type: PersonType.internalUser,
            isActive: true,
            department: 'Logistics & Fleet',
            departmentId: 'dept-acme-1',
            site: 'Acme Central Hub',
            siteId: 'site-acme-1',
          ),
        ],
      },
    );
  });

  group('Multi-Company Isolation & Dropdown Population', () {
    testWidgets(
      'Loads only Sobha organizational records and never displays Acme records',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: AddActionScreen(
              actionId: 'ACT-SOBHA-001',
              organizationId: sobhaOrgId,
              companyStructureService: structureService,
              divisionService: divisionService,
              actionSectionService: sectionService,
              userService: userService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Section 2 rendered
        expect(find.text('WHERE IT BELONGS'), findsOneWidget);

        // Shows Sobha's primary department
        expect(find.text('Civil Engineering'), findsWidgets);
        expect(find.text('Sobha Hartland'), findsWidgets);

        // Never shows Acme data
        expect(find.text('Logistics & Fleet'), findsNothing);
        expect(find.text('Procurement'), findsNothing);
        expect(find.text('Acme Central Hub'), findsNothing);
        expect(find.text('Inventory Compliance'), findsNothing);
      },
    );

    testWidgets(
      'Loads only Acme Corp records when Acme organizationId is provided',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: AddActionScreen(
              actionId: 'ACT-ACME-001',
              organizationId: acmeOrgId,
              companyStructureService: structureService,
              divisionService: divisionService,
              actionSectionService: sectionService,
              userService: userService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Shows Acme's primary department
        expect(find.text('Logistics & Fleet'), findsWidgets);
        expect(find.text('Acme Central Hub'), findsWidgets);

        // Never shows Sobha data
        expect(find.text('Civil Engineering'), findsNothing);
        expect(find.text('Finishing & Interiors'), findsNothing);
        expect(find.text('Sobha Hartland'), findsNothing);
        expect(find.text('Quality Audit'), findsNothing);
      },
    );

    testWidgets(
      'Clean empty states when organization has zero configured entities, no fake demo data',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const emptyOrgId = '00000000-0000-0000-0000-000000000099';

        await tester.pumpWidget(
          MaterialApp(
            home: AddActionScreen(
              actionId: 'ACT-EMPTY-001',
              organizationId: emptyOrgId,
              companyStructureService: structureService,
              divisionService: divisionService,
              actionSectionService: sectionService,
              userService: userService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify clean empty state hints
        expect(find.text('No departments configured'), findsOneWidget);
        expect(find.text('No sites configured'), findsOneWidget);

        // Verify fake demo lists like Operations/HSE/General/Site 1 are not present
        expect(find.text('Operations'), findsNothing);
        expect(find.text('HSE'), findsNothing);
        expect(find.text('General'), findsNothing);
        expect(find.text('Site 1'), findsNothing);
      },
    );

    testWidgets(
      'Error banner with Retry button appears on query failure, retrying reloads data',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        structureService.shouldThrow = true;

        await tester.pumpWidget(
          MaterialApp(
            home: AddActionScreen(
              actionId: 'ACT-ERR-001',
              organizationId: sobhaOrgId,
              companyStructureService: structureService,
              divisionService: divisionService,
              actionSectionService: sectionService,
              userService: userService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Error message rendered
        expect(find.byKey(const Key('retry_load_org_data_btn')), findsOneWidget);
        expect(find.textContaining('Failed to load organizational configuration'), findsOneWidget);

        // Fix error and retry
        structureService.shouldThrow = false;
        await tester.tap(find.byKey(const Key('retry_load_org_data_btn')));
        await tester.pumpAndSettle();

        // Now loaded
        expect(find.byKey(const Key('retry_load_org_data_btn')), findsNothing);
        expect(find.text('Civil Engineering'), findsWidgets);
      },
    );
  });

  group('Optional Section Workflow', () {
    testWidgets(
      'Action can be created and saved without selecting any Section (Section is optional)',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        ActionRecord? createdRecord;

        await tester.pumpWidget(
          MaterialApp(
            home: AddActionScreen(
              actionId: 'ACT-NO-SEC-101',
              organizationId: sobhaOrgId,
              companyStructureService: structureService,
              divisionService: divisionService,
              actionSectionService: sectionService,
              userService: userService,
              onSaved: (rec) => createdRecord = rec,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Fill Title
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Action Title *'),
          'Inspect foundation rebar',
        );

        // Assign Vikram Mehta
        final searchField = find.widgetWithText(
          TextFormField,
          'Search by name, email, or phone...',
        );
        await tester.enterText(searchField, 'Vikram');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Vikram Mehta').first);
        await tester.pumpAndSettle();

        // Do not select any section (it remains empty / 'None')
        final sendBtn = find.text('Send Action');
        await tester.ensureVisible(sendBtn);
        await tester.tap(sendBtn);
        await tester.pumpAndSettle();

        expect(createdRecord, isNotNull);
        expect(createdRecord!.subject, equals('Inspect foundation rebar'));
        expect(createdRecord!.department, equals('Civil Engineering'));
        expect(createdRecord!.site, equals('Sobha Hartland'));
        expect(createdRecord!.sectionId, isNull);
        expect(createdRecord!.section, isEmpty);
      },
    );
  });

  group('Cross-Department Assignment & Scopes', () {
    testWidgets(
      'Manager from HSE can create action for Civil Engineering and assign to Civil staff member',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Creating manager is from HSE, but has scope for Civil Engineering @ Sobha Hartland
        final managerCtx = ManagerContext(
          authUserId: 'mgr-hse-001',
          profile: UserProfile(
            id: 'mgr-hse-001',
            name: 'Rajesh Sen',
            email: 'mgr.hse@sobha.com',
            phone: '+971 50 999 1111',
            designation: 'HSE Manager',
            role: 'Manager',
            department: 'HSE',
            site: 'Sobha Hartland',
            organizationId: sobhaOrgId,
          ),
          organizationId: sobhaOrgId,
          organizationName: 'Sobha Developers',
          scopes: const [
            ManagerScopeItem(
              departmentId: 'dept-sobha-1',
              departmentName: 'Civil Engineering',
              siteId: 'site-sobha-1',
              siteName: 'Sobha Hartland',
            ),
          ],
        );

        ActionRecord? createdRecord;

        await tester.pumpWidget(
          MaterialApp(
            home: AddActionScreen(
              actionId: 'ACT-CROSS-001',
              organizationId: sobhaOrgId,
              managerContext: managerCtx,
              companyStructureService: structureService,
              divisionService: divisionService,
              actionSectionService: sectionService,
              userService: userService,
              onSaved: (rec) => createdRecord = rec,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Manager context automatically scoped department to Civil Engineering
        expect(find.text('Civil Engineering'), findsWidgets);
        expect(find.text('Sobha Hartland'), findsWidgets);

        // Search for Vikram Mehta (who is in Civil Engineering)
        final searchField = find.widgetWithText(
          TextFormField,
          'Search by name, email, or phone...',
        );
        await tester.enterText(searchField, 'Vikram');
        await tester.pumpAndSettle();

        expect(find.text('Vikram Mehta'), findsWidgets);
        await tester.tap(find.text('Vikram Mehta').first);
        await tester.pumpAndSettle();

        // Assigned to Vikram Mehta
        expect(find.text('Vikram Mehta'), findsWidgets);
        expect(find.text('Primary'), findsOneWidget);

        // Title
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Action Title *'),
          'Cross-department structural audit',
        );

        // Send
        final sendBtn = find.text('Send Action');
        await tester.ensureVisible(sendBtn);
        await tester.tap(sendBtn);
        await tester.pumpAndSettle();

        expect(createdRecord, isNotNull);
        expect(createdRecord!.subject, equals('Cross-department structural audit'));
        expect(createdRecord!.assignedTo, equals('Vikram Mehta'));
        expect(createdRecord!.department, equals('Civil Engineering'));
        expect(createdRecord!.site, equals('Sobha Hartland'));
      },
    );

    testWidgets(
      'Manager scope restricts department and site dropdowns to authorized scopes',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Manager authorized ONLY for Finishing & Interiors @ Sobha Creek Vistas
        final managerCtx = ManagerContext(
          authUserId: 'mgr-finish-001',
          profile: UserProfile(
            id: 'mgr-finish-001',
            name: 'Farah Khan',
            email: 'mgr.finish@sobha.com',
            phone: '+971 50 888 2222',
            designation: 'Finishing Manager',
            role: 'Manager',
            department: 'Finishing & Interiors',
            site: 'Sobha Creek Vistas',
            organizationId: sobhaOrgId,
          ),
          organizationId: sobhaOrgId,
          organizationName: 'Sobha Developers',
          scopes: const [
            ManagerScopeItem(
              departmentId: 'dept-sobha-2',
              departmentName: 'Finishing & Interiors',
              siteId: 'site-sobha-2',
              siteName: 'Sobha Creek Vistas',
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: AddActionScreen(
              actionId: 'ACT-SCOPE-001',
              organizationId: sobhaOrgId,
              managerContext: managerCtx,
              companyStructureService: structureService,
              divisionService: divisionService,
              actionSectionService: sectionService,
              userService: userService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Authorized department and site are active
        expect(find.text('Finishing & Interiors'), findsWidgets);
        expect(find.text('Sobha Creek Vistas'), findsWidgets);

        // Civil Engineering and Sobha Hartland are not available in permitted scopes
        expect(find.text('Civil Engineering'), findsNothing);
      },
    );

    testWidgets(
      'Assignee revalidation on Department change: clears selected assignee if not eligible for new Department',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Manager authorized for both Civil Engineering and Finishing & Interiors
        final managerCtx = ManagerContext(
          authUserId: 'mgr-multi-001',
          profile: UserProfile(
            id: 'mgr-multi-001',
            name: 'Sunil Verma',
            email: 'sunil.verma@sobha.com',
            phone: '+971 50 777 3333',
            designation: 'General Manager',
            role: 'Manager',
            department: 'Civil Engineering',
            site: 'Sobha Hartland',
            organizationId: sobhaOrgId,
          ),
          organizationId: sobhaOrgId,
          organizationName: 'Sobha Developers',
          scopes: const [
            ManagerScopeItem(
              departmentId: 'dept-sobha-1',
              departmentName: 'Civil Engineering',
              siteId: 'site-sobha-1',
              siteName: 'Sobha Hartland',
            ),
            ManagerScopeItem(
              departmentId: 'dept-sobha-2',
              departmentName: 'Finishing & Interiors',
              siteId: 'site-sobha-2',
              siteName: 'Sobha Creek Vistas',
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: AddActionScreen(
              actionId: 'ACT-REVAL-001',
              organizationId: sobhaOrgId,
              managerContext: managerCtx,
              companyStructureService: structureService,
              divisionService: divisionService,
              actionSectionService: sectionService,
              userService: userService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Initially in Civil Engineering @ Sobha Hartland
        expect(find.text('Civil Engineering'), findsWidgets);

        // Assign Vikram Mehta (Civil Engineering)
        final searchField = find.widgetWithText(
          TextFormField,
          'Search by name, email, or phone...',
        );
        await tester.enterText(searchField, 'Vikram');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Vikram Mehta').first);
        await tester.pumpAndSettle();

        // Vikram is primary assignee
        expect(find.text('Vikram Mehta'), findsWidgets);
        expect(find.text('Primary'), findsOneWidget);

        // Change Department to 'Finishing & Interiors'
        final deptDropdown = find.widgetWithText(
          DropdownButtonFormField<String>,
          'Department *',
        );
        await tester.ensureVisible(deptDropdown);
        await tester.tap(deptDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Finishing & Interiors').last);
        await tester.pumpAndSettle();

        // Vikram Mehta is no longer eligible for Finishing & Interiors, so he is cleared
        expect(find.text('Vikram Mehta'), findsNothing);
        expect(find.text('Primary'), findsNothing);
        expect(find.textContaining('Primary assignee cleared'), findsOneWidget);
      },
    );

    testWidgets(
      'Division and Unit are NOT displayed in Add Action UI; Teams is displayed as an optional field',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: AddActionScreen(
              actionId: 'ACT-OPT-TEAM-01',
              organizationId: sobhaOrgId,
              companyStructureService: structureService,
              divisionService: divisionService,
              actionSectionService: sectionService,
              userService: userService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Division & Unit dropdowns must not exist
        expect(find.text('Division'), findsNothing);
        expect(find.text('Unit'), findsNothing);

        // Required Department & Site exist with asterisks
        expect(find.text('Department *'), findsOneWidget);
        expect(find.text('Location / Site *'), findsOneWidget);

        // Section and Teams exist as optional fields (no asterisk)
        expect(find.text('Section'), findsWidgets);
        expect(find.text('Teams'), findsWidgets);
        expect(find.text('Teams *'), findsNothing);
      },
    );

    testWidgets(
      'Teams load from existing Admin Portal / CompanyStructureService and filter by company and department',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: AddActionScreen(
              actionId: 'ACT-SOBHA-TEAM-01',
              organizationId: sobhaOrgId,
              companyStructureService: structureService,
              divisionService: divisionService,
              actionSectionService: sectionService,
              userService: userService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Select Sobha Department 'Civil Engineering'
        final deptDropdown = find.widgetWithText(
          DropdownButtonFormField<String>,
          'Department *',
        );
        await tester.ensureVisible(deptDropdown);
        await tester.tap(deptDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Civil Engineering').last);
        await tester.pumpAndSettle();

        // Open Teams dropdown
        final teamsDropdown = find.widgetWithText(
          DropdownButtonFormField<String>,
          'Teams',
        );
        await tester.ensureVisible(teamsDropdown);
        await tester.tap(teamsDropdown);
        await tester.pumpAndSettle();

        // Sobha's 'Concrete Team' is present, while Acme's 'Dispatch Team' is never shown
        expect(find.text('Concrete Team'), findsWidgets);
        expect(find.text('Dispatch Team'), findsNothing);
      },
    );

    testWidgets(
      'New action can be saved without selecting a team, and persists teamId when a team is selected',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        ActionRecord? savedRecord;

        await tester.pumpWidget(
          MaterialApp(
            home: AddActionScreen(
              actionId: 'ACT-PERSIST-TEAM-01',
              organizationId: sobhaOrgId,
              companyStructureService: structureService,
              divisionService: divisionService,
              actionSectionService: sectionService,
              userService: userService,
              onSaved: (rec) {
                savedRecord = rec;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Fill required fields
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Action Title *'),
          'Test Action Without Team',
        );

        // Select Department & Site
        final deptDropdown = find.widgetWithText(
          DropdownButtonFormField<String>,
          'Department *',
        );
        await tester.ensureVisible(deptDropdown);
        await tester.tap(deptDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Civil Engineering').last);
        await tester.pumpAndSettle();

        final siteDropdown = find.widgetWithText(
          DropdownButtonFormField<String>,
          'Location / Site *',
        );
        await tester.ensureVisible(siteDropdown);
        await tester.tap(siteDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sobha Hartland').last);
        await tester.pumpAndSettle();

        // Assign to Vikram Mehta
        final searchField = find.widgetWithText(
          TextFormField,
          'Search by name, email, or phone...',
        );
        await tester.enterText(searchField, 'Vikram');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Vikram Mehta').first);
        await tester.pumpAndSettle();

        // Save without selecting any Team (Teams stays 'None')
        final sendBtn = find.text('Send Action');
        await tester.ensureVisible(sendBtn);
        await tester.tap(sendBtn);
        await tester.pumpAndSettle();

        expect(savedRecord, isNotNull);
        expect(savedRecord!.department, 'Civil Engineering');
        expect(savedRecord!.teamId, isNull);

        // Now select a team
        final teamsDropdown = find.widgetWithText(
          DropdownButtonFormField<String>,
          'Teams',
        );
        await tester.ensureVisible(teamsDropdown);
        await tester.tap(teamsDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Concrete Team').last);
        await tester.pumpAndSettle();

        // Save with selected team
        savedRecord = null;
        await tester.ensureVisible(sendBtn);
        await tester.tap(sendBtn);
        await tester.pumpAndSettle();

        expect(savedRecord, isNotNull);
        expect(savedRecord!.teamId, 'team-sobha-1');
      },
    );

    testWidgets(
      'Editing existing action preserves stored division and team values even when Division is hidden',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final existingAction = ActionRecord(
          id: 'ACT-EXISTING-01',
          subject: 'Existing Action with Division and Team',
          actionRequired: 'Verify preservation of division and team on edit',
          department: 'Civil Engineering',
          departmentId: 'dept-sobha-1',
          site: 'Sobha Hartland',
          siteId: 'site-sobha-1',
          division: 'Real Estate Development',
          divisionId: 'div-sobha-1',
          teamId: 'team-sobha-1',
          section: 'Quality Audit',
          sectionId: 'sec-sobha-1',
          priority: 'High',
          status: 'Open',
          percentComplete: 50,
          dateRaised: '01 Oct 2026',
          targetDate: '15 Oct 2026',
          assignedTo: 'Aarav Sharma',
          assignedToId: 'user-sobha-1',
          organizationId: sobhaOrgId,
          recipientType: 'internal',
          primaryAssignee: ActionPersonReference(
            personId: 'user-sobha-1',
            name: 'Aarav Sharma',
            type: PersonType.internalUser,
          ),
        );

        ActionRecord? updatedRecord;

        await tester.pumpWidget(
          MaterialApp(
            home: AddActionScreen(
              actionId: 'ACT-EXISTING-01',
              existingAction: existingAction,
              organizationId: sobhaOrgId,
              companyStructureService: structureService,
              divisionService: divisionService,
              actionSectionService: sectionService,
              userService: userService,
              onSaved: (rec) {
                updatedRecord = rec;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Division is NOT in UI
        expect(find.text('Division'), findsNothing);

        // Team 'Concrete Team' is loaded into the Teams dropdown
        expect(find.text('Concrete Team'), findsWidgets);

        // Save without modifying organizational fields
        final saveBtn = find.text('Save Changes');
        await tester.ensureVisible(saveBtn);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        expect(updatedRecord, isNotNull);
        // Preserves division from existing action
        expect(updatedRecord!.division, 'Real Estate Development');
        expect(updatedRecord!.divisionId, 'div-sobha-1');
        // Preserves team from existing action
        expect(updatedRecord!.teamId, 'team-sobha-1');
        // Preserves department and section
        expect(updatedRecord!.departmentId, 'dept-sobha-1');
        expect(updatedRecord!.sectionId, 'sec-sobha-1');
      },
    );
  });
}
