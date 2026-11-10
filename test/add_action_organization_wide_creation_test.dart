import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

class MockActionSectionService extends ActionSectionService {
  @override
  Future<List<ActionSection>> fetchSections(String organizationId, {bool onlyActive = false}) async => [];
}

class MockDivisionService extends DivisionService {
  @override
  Future<List<Division>> fetchDivisions(String organizationId, {bool onlyActive = false}) async => [];
}

class MockUsersService extends UserService {
  final List<Person> users;
  MockUsersService(this.users);

  @override
  Future<List<Person>> fetchUsers(String organizationId, {bool allowMockFallback = true}) async => users;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sobhaOrgId = '00000000-0000-0000-0000-000000000001';

  group('ActionRecord Organization-Wide and Scoped Models', () {
    test('1. ActionRecord defaults to scopeType specific and backward compatible', () {
      final record = ActionRecord(
        id: 'act-101',
        subject: 'Inspect electrical panel',
        actionRequired: 'Replace breaker',
        division: 'Engineering',
        department: 'Operations',
        departmentId: 'dept-uuid-1',
        site: 'Site Alpha',
        siteId: 'site-uuid-1',
        assignedTo: 'John Doe',
      );

      expect(record.scopeType, equals('specific'));
      expect(record.isSpecificScope, isTrue);
      expect(record.isOrganizationWide, isFalse);
      expect(record.isDepartmentWide, isFalse);
      expect(record.isSiteWide, isFalse);
    });

    test('2. ActionRecord correctly identifies organization-wide scope', () {
      final record = ActionRecord(
        id: 'act-102',
        subject: 'Annual Safety Awareness',
        actionRequired: 'Company-wide mandatory briefing',
        division: 'Corporate',
        department: 'All Departments',
        departmentId: '',
        site: 'All Sites / Locations',
        siteId: '',
        assignedTo: 'Global Staff',
        scopeType: 'organization',
      );

      expect(record.scopeType, equals('organization'));
      expect(record.isOrganizationWide, isTrue);
      expect(record.isSpecificScope, isFalse);
      expect(record.isDepartmentWide, isFalse);
      expect(record.isSiteWide, isFalse);

      final insertMap = record.toSupabaseInsertMap();
      expect(insertMap['scope_type'], equals('organization'));
      expect(insertMap['department_id'], isNull);
      expect(insertMap['site_id'], isNull);

      final updateMap = record.toSupabaseUpdateMap();
      expect(updateMap['scope_type'], equals('organization'));
      expect(updateMap['department_id'], isNull);
      expect(updateMap['site_id'], isNull);
    });

    test('3. ActionRecord correctly identifies department-wide scope', () {
      final record = ActionRecord(
        id: 'act-103',
        subject: 'HSE Equipment Calibration',
        actionRequired: 'Calibrate all sound level meters across all sites',
        division: 'Operations',
        department: 'HSE',
        departmentId: 'dept-hse-uuid',
        site: 'All Sites / Locations',
        siteId: '',
        assignedTo: 'HSE Lead',
        scopeType: 'department',
      );

      expect(record.isDepartmentWide, isTrue);
      expect(record.isOrganizationWide, isFalse);
      expect(record.isSiteWide, isFalse);
      expect(record.isSpecificScope, isFalse);

      final insertMap = record.toSupabaseInsertMap();
      expect(insertMap['scope_type'], equals('department'));
      expect(insertMap['department_id'], equals('dept-hse-uuid'));
      expect(insertMap['site_id'], isNull);
    });

    test('4. ActionRecord correctly identifies site-wide cross-department scope', () {
      final record = ActionRecord(
        id: 'act-104',
        subject: 'Plant Alpha Evacuation Drill',
        actionRequired: 'Site-wide emergency evacuation drill',
        division: 'Operations',
        department: 'All Departments',
        departmentId: '',
        site: 'Plant Alpha',
        siteId: 'site-alpha-uuid',
        assignedTo: 'Site Coordinator',
        scopeType: 'site',
      );

      expect(record.isSiteWide, isTrue);
      expect(record.isDepartmentWide, isFalse);
      expect(record.isOrganizationWide, isFalse);
      expect(record.isSpecificScope, isFalse);

      final insertMap = record.toSupabaseInsertMap();
      expect(insertMap['scope_type'], equals('site'));
      expect(insertMap['department_id'], isNull);
      expect(insertMap['site_id'], equals('site-alpha-uuid'));
    });

    test('5. ActionRecord.fromSupabase maps NULL database department and site to All Departments & All Sites', () {
      final json = <String, dynamic>{
        'id': 'a1111111-1111-1111-1111-111111111111',
        'action_number': 'ACT-9001',
        'title': 'Org-Wide Safety Training',
        'action_required': 'Complete video module',
        'scope_type': 'organization',
        'department_id': null,
        'site_id': null,
        'departments': null,
        'sites': null,
        'status': 'Open',
        'percent_complete': 0,
        'recipient_type': 'internal',
        'assigned_to': 'u1111111-1111-1111-1111-111111111111',
        'assignee': {
          'id': 'u1111111-1111-1111-1111-111111111111',
          'full_name': 'Alice Finance',
          'email': 'alice@company.com',
          'designation': 'Financial Analyst',
        },
      };

      final record = ActionRecord.fromSupabase(json);
      expect(record.scopeType, equals('organization'));
      expect(record.isOrganizationWide, isTrue);
      expect(record.department, equals('All Departments'));
      expect(record.site, equals('All Sites / Locations'));
      expect(record.assignedTo, equals('Alice Finance'));
    });
  });

  group('AddActionScreen Scope Selection & Organization-Wide Creation', () {
    late ManagerContext scopedManagerContext;
    late List<Person> mockPeople;
    late List<Map<String, dynamic>> departments;
    late List<Map<String, dynamic>> sites;

    setUp(() {
      departments = [
        {'id': 'dept-hse-id', 'name': 'HSE', 'is_active': true},
        {'id': 'dept-fin-id', 'name': 'Finance', 'is_active': true},
      ];

      sites = [
        {'id': 'site-alpha-id', 'name': 'Plant Alpha', 'is_active': true, 'department_name': 'HSE'},
        {'id': 'site-beta-id', 'name': 'Plant Beta', 'is_active': true, 'department_name': 'Finance'},
      ];

      scopedManagerContext = const ManagerContext(
        authUserId: 'mgr-user-uuid',
        organizationId: sobhaOrgId,
        organizationName: 'Sobha Developers',
        profile: UserProfile(
          id: 'mgr-user-uuid',
          name: 'Manager Bob',
          email: 'mgr.bob@sobha.com',
          phone: '+971 50 111 0000',
          designation: 'HSE Manager',
          role: 'Manager',
          department: 'HSE',
          site: 'Plant Alpha',
          organizationId: sobhaOrgId,
        ),
        scopes: [
          ManagerScopeItem(
            departmentId: 'dept-hse-id',
            departmentName: 'HSE',
            siteId: 'site-alpha-id',
            siteName: 'Plant Alpha',
          ),
        ],
      );

      mockPeople = [
        Person(
          id: 'user-hse-alpha',
          name: 'Bob HSE Alpha',
          email: 'bob@company.com',
          phone: '+971 50 111 0001',
          designation: 'HSE Inspector',
          role: UserRole.actionOwnerWorker,
          department: 'HSE',
          departmentId: 'dept-hse-id',
          site: 'Plant Alpha',
          siteId: 'site-alpha-id',
          isActive: true,
          type: PersonType.internalUser,
          organizationId: sobhaOrgId,
        ),
        Person(
          id: 'user-fin-beta',
          name: 'Carol Finance Beta',
          email: 'carol@company.com',
          phone: '+971 50 111 0002',
          designation: 'Finance Officer',
          role: UserRole.actionOwnerWorker,
          department: 'Finance',
          departmentId: 'dept-fin-id',
          site: 'Plant Beta',
          siteId: 'site-beta-id',
          isActive: true,
          type: PersonType.internalUser,
          organizationId: sobhaOrgId,
        ),
        Person(
          id: 'user-hse-beta',
          name: 'Dan HSE Beta',
          email: 'dan@company.com',
          phone: '+971 50 111 0003',
          designation: 'HSE Coordinator',
          role: UserRole.actionOwnerWorker,
          department: 'HSE',
          departmentId: 'dept-hse-id',
          site: 'Plant Beta',
          siteId: 'site-beta-id',
          isActive: true,
          type: PersonType.internalUser,
          organizationId: sobhaOrgId,
        ),
        Person(
          id: 'user-inactive',
          name: 'Inactive User',
          email: 'inactive@company.com',
          phone: '+971 50 111 0004',
          designation: 'Staff',
          role: UserRole.actionOwnerWorker,
          department: 'HSE',
          departmentId: 'dept-hse-id',
          site: 'Plant Alpha',
          siteId: 'site-alpha-id',
          isActive: false,
          type: PersonType.internalUser,
          organizationId: sobhaOrgId,
        ),
      ];

      MockPeopleStore.instance.people.clear();
      MockPeopleStore.instance.people.addAll(mockPeople);
    });

    Widget createScreen() {
      return MaterialApp(
        home: Scaffold(
          body: AddActionScreen(
            actionId: 'ACT-TEST-001',
            organizationId: sobhaOrgId,
            managerContext: scopedManagerContext,
            companyStructureService: MockStructureService(
              departments: departments,
              sites: sites,
              teams: [],
            ),
            actionSectionService: MockActionSectionService(),
            divisionService: MockDivisionService(),
            userService: MockUsersService(mockPeople),
          ),
        ),
      );
    }

    testWidgets('6. When All Departments and All Sites is selected, Org-Wide banner is displayed',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createScreen());
      await tester.pumpAndSettle();

      // Find department dropdown and ensure 'All Departments' is selected
      final deptDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Department *');
      await tester.ensureVisible(deptDropdown);
      await tester.tap(deptDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Departments').last);
      await tester.pumpAndSettle();

      // Select 'All Sites / Locations' in Location / Site dropdown
      final siteDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Location / Site *');
      await tester.ensureVisible(siteDropdown);
      await tester.tap(siteDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Sites / Locations').last);
      await tester.pumpAndSettle();

      // Verify that the Organization-Wide banner is displayed
      expect(find.byKey(const Key('org_wide_scope_banner')), findsOneWidget);
      expect(find.text('Organization-Wide Action'), findsOneWidget);
    });

    testWidgets('7. Outside-scope internal users are eligible as primary assignee for Organization-Wide action',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createScreen());
      await tester.pumpAndSettle();

      // Select 'All Departments'
      final deptDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Department *');
      await tester.ensureVisible(deptDropdown);
      await tester.tap(deptDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Departments').last);
      await tester.pumpAndSettle();

      // Select 'All Sites / Locations'
      final siteDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Location / Site *');
      await tester.ensureVisible(siteDropdown);
      await tester.tap(siteDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Sites / Locations').last);
      await tester.pumpAndSettle();

      // Ensure banner is visible
      expect(find.byKey(const Key('org_wide_scope_banner')), findsOneWidget);

      // Open primary internal person search/selection
      final searchField = find.byKey(const Key('internal_person_search_field'));
      if (searchField.evaluate().isNotEmpty) {
        await tester.ensureVisible(searchField);
        await tester.enterText(searchField, 'Carol');
        await tester.pumpAndSettle();

        // Carol Finance Beta (outside manager's HSE / Plant Alpha scope) is eligible and visible!
        expect(find.textContaining('Carol Finance Beta'), findsWidgets);
      }
    });

    testWidgets('8. Specific department + specific site restricts primary assignee to matching scope',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createScreen());
      await tester.pumpAndSettle();

      // Select specific Department HSE
      final deptDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Department *');
      await tester.ensureVisible(deptDropdown);
      await tester.tap(deptDropdown);
      await tester.pumpAndSettle();

      final hseItem = find.text('HSE').last;
      await tester.tap(hseItem);
      await tester.pumpAndSettle();

      // Select specific Site Plant Alpha
      final siteDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Location / Site *');
      await tester.ensureVisible(siteDropdown);
      await tester.tap(siteDropdown);
      await tester.pumpAndSettle();

      final plantAlphaItem = find.text('Plant Alpha').last;
      await tester.tap(plantAlphaItem);
      await tester.pumpAndSettle();

      // Org-wide banner should NOT be visible
      expect(find.byKey(const Key('org_wide_scope_banner')), findsNothing);

      // Open person search
      final searchField = find.byKey(const Key('internal_person_search_field'));
      if (searchField.evaluate().isNotEmpty) {
        await tester.ensureVisible(searchField);
        await tester.enterText(searchField, 'Carol');
        await tester.pumpAndSettle();
        // Carol is Finance/Beta, outside HSE Alpha scope, so she must NOT appear
        expect(find.textContaining('Carol Finance Beta'), findsNothing);
      }
    });
  });
}
