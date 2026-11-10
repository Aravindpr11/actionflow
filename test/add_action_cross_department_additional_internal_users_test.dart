import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/add_action_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/models/action_section.dart';
import 'package:action_flow/models/division.dart';
import 'package:action_flow/services/action_section_service.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:action_flow/services/company_structure_service.dart';
import 'package:action_flow/services/division_service.dart';
import 'package:action_flow/services/user_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ============================================================================
// MOCKS FOR TEST ISOLATION
// ============================================================================

class MockTestStructureService extends CompanyStructureService {
  final List<Map<String, dynamic>> departments;
  final List<Map<String, dynamic>> sites;
  final List<Map<String, dynamic>> teams;

  MockTestStructureService({
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

class MockTestDivisionService extends DivisionService {
  @override
  Future<List<Division>> fetchDivisions(String organizationId, {bool onlyActive = false}) async => [];
}

class MockTestSectionService extends ActionSectionService {
  @override
  Future<List<ActionSection>> fetchSections(String organizationId, {bool onlyActive = false}) async => [
    ActionSection(
      id: 'sec-1',
      name: 'Safety Section',
      organizationId: 'org-test-1',
      isActive: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  ];
}

class MockTestUserService extends UserService {
  final List<Person> users;
  MockTestUserService({required this.users});

  @override
  Future<List<Person>> fetchUsers(String organizationId, {bool allowMockFallback = true}) async => users;
}

// ============================================================================
// TEST SUITE: CROSS-DEPARTMENT & CROSS-SITE ADDITIONAL INTERNAL USERS
// ============================================================================

void main() {
  const testOrgId = '00000000-0000-0000-0000-000000000001';

  late MockTestStructureService structureService;
  late MockTestDivisionService divisionService;
  late MockTestSectionService sectionService;
  late MockTestUserService userService;

  // Test users across different departments and sites
  final hseStaff = Person(
    id: '11111111-1111-1111-1111-111111111111',
    name: 'Rahul Sharma',
    email: 'rahul.sharma@sobha.test',
    phone: '+91 98765 00001',
    designation: 'HSE Officer',
    department: 'HSE',
    site: 'Tower A',
    type: PersonType.internalUser,
    isActive: true,
  );

  final civilStaff1 = Person(
    id: '22222222-2222-2222-2222-222222222222',
    name: 'Brenda Roy',
    email: 'brenda.roy@sobha.test',
    phone: '+91 98765 00002',
    designation: 'Civil Inspector',
    department: 'Civil Engineering',
    site: 'Tower B',
    type: PersonType.internalUser,
    isActive: true,
  );

  final civilStaff2 = Person(
    id: '33333333-3333-3333-3333-333333333333',
    name: 'Chetan Patel',
    email: 'chetan.patel@sobha.test',
    phone: '+91 98765 00003',
    designation: 'Civil Engineer',
    department: 'Civil Engineering',
    site: 'Tower B',
    type: PersonType.internalUser,
    isActive: true,
  );

  final financeStaff = Person(
    id: '44444444-4444-4444-4444-444444444444',
    name: 'David Nair',
    email: 'david.nair@sobha.test',
    phone: '+91 98765 00004',
    designation: 'Finance Specialist',
    department: 'Finance',
    site: 'Corporate HQ',
    type: PersonType.internalUser,
    isActive: true,
  );

  final inactiveStaff = Person(
    id: '55555555-5555-5555-5555-555555555555',
    name: 'Inactive OldStaff',
    email: 'inactive@sobha.test',
    phone: '+91 98765 00005',
    designation: 'Former Tech',
    department: 'HSE',
    site: 'Tower A',
    type: PersonType.internalUser,
    isActive: false, // Inactive!
  );

  // Scoped manager for HSE / Tower A
  final managerContext = ManagerContext(
    authUserId: 'mgr-profile-1',
    organizationId: testOrgId,
    organizationName: 'Sobha Developers',
    profile: UserProfile(
      id: 'mgr-profile-1',
      name: 'Manager Bob',
      email: 'mgr.bob@sobha.test',
      phone: '+91 98765 00000',
      designation: 'HSE Manager',
      role: 'Manager',
      department: 'HSE',
      site: 'Tower A',
      organizationId: testOrgId,
    ),
    scopes: const [
      ManagerScopeItem(
        id: 'scope-1',
        departmentId: 'dept-hse',
        departmentName: 'HSE',
        siteId: 'site-tower-a',
        siteName: 'Tower A',
      ),
    ],
  );

  setUp(() {
    structureService = MockTestStructureService(
      departments: [
        {'id': 'dept-hse', 'name': 'HSE', 'status': 'Active'},
        {'id': 'dept-civil', 'name': 'Civil Engineering', 'status': 'Active'},
        {'id': 'dept-finance', 'name': 'Finance', 'status': 'Active'},
      ],
      sites: [
        {'id': 'site-tower-a', 'name': 'Tower A', 'status': 'Active', 'department_id': 'dept-hse'},
        {'id': 'site-tower-b', 'name': 'Tower B', 'status': 'Active', 'department_id': 'dept-civil'},
        {'id': 'site-hq', 'name': 'Corporate HQ', 'status': 'Active', 'department_id': 'dept-finance'},
      ],
      teams: [
        {'id': 'team-1', 'name': 'HSE Alpha Team', 'department_id': 'dept-hse', 'status': 'Active'},
      ],
    );

    divisionService = MockTestDivisionService();
    sectionService = MockTestSectionService();
    userService = MockTestUserService(
      users: [hseStaff, civilStaff1, civilStaff2, financeStaff, inactiveStaff],
    );

    MockPeopleStore.instance.people.clear();
    MockPeopleStore.instance.people.addAll([
      hseStaff,
      civilStaff1,
      civilStaff2,
      financeStaff,
      inactiveStaff,
    ]);
  });

  Widget buildTestWidget({ActionRecord? existingAction}) {
    return MaterialApp(
      home: AddActionScreen(
        actionId: 'AC-TEST-1',
        existingAction: existingAction,
        managerContext: managerContext,
        organizationId: testOrgId,
        companyStructureService: structureService,
        divisionService: divisionService,
        actionSectionService: sectionService,
        userService: userService,
      ),
    );
  }

  testWidgets(
    '1. Add single additional internal user from another department and site',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Verify initial Department and Site selected for manager (HSE / Tower A)
      expect(find.text('HSE'), findsWidgets);
      expect(find.text('Tower A'), findsWidgets);

      // Select Primary Internal Assignee (Rahul Sharma from HSE / Tower A)
      final internalSearch = find.widgetWithText(
        TextFormField,
        'Search by name, email, or phone...',
      );
      await tester.enterText(internalSearch, 'Rahul');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rahul Sharma'));
      await tester.pumpAndSettle();

      expect(find.text('Primary'), findsOneWidget);
      expect(find.text('Rahul Sharma'), findsWidgets);

      // Tap "Add Internal Person" button
      await tester.tap(find.text('Add Internal Person'));
      await tester.pumpAndSettle();

      // Dialog opens in "Select Existing Users" mode
      expect(find.byKey(const Key('tab_select_existing_users')), findsOneWidget);
      expect(find.byKey(const Key('dialog_department_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('dialog_site_dropdown')), findsOneWidget);

      // Select Department: "Civil Engineering"
      await tester.tap(find.byKey(const Key('dialog_department_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Civil Engineering').last);
      await tester.pumpAndSettle();

      // Brenda Roy should appear in the eligible list
      expect(find.text('Brenda Roy'), findsOneWidget);
      expect(find.textContaining('Civil Inspector'), findsOneWidget);

      // Select Brenda Roy
      await tester.tap(find.byKey(Key('user_checkbox_${civilStaff1.id}')));
      await tester.pumpAndSettle();

      expect(find.text('1 user(s) selected'), findsWidgets);

      // Click "Add Selected Users"
      await tester.tap(find.byKey(const Key('dialog_add_selected_users_button')));
      await tester.pumpAndSettle();

      // Dialog closes and Brenda Roy appears under Additional Internal Persons
      expect(find.text('Additional Internal Persons (1)'), findsOneWidget);
      expect(find.text('Brenda Roy'), findsOneWidget);
      expect(find.text('Additional'), findsOneWidget);
      expect(find.textContaining('Civil Engineering'), findsWidgets);

      // Verify original action department and site are unchanged
      expect(find.text('HSE'), findsWidgets);
      expect(find.text('Tower A'), findsWidgets);
    },
  );

  testWidgets(
    '2. Add multiple internal users from the same department simultaneously',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Open Add Internal Person dialog
      await tester.tap(find.text('Add Internal Person'));
      await tester.pumpAndSettle();

      // Select Civil Engineering
      await tester.tap(find.byKey(const Key('dialog_department_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Civil Engineering').last);
      await tester.pumpAndSettle();

      // Both Brenda Roy and Chetan Patel are visible
      expect(find.text('Brenda Roy'), findsOneWidget);
      expect(find.text('Chetan Patel'), findsOneWidget);

      // Select both users
      await tester.tap(find.byKey(Key('user_checkbox_${civilStaff1.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('user_checkbox_${civilStaff2.id}')));
      await tester.pumpAndSettle();

      expect(find.text('2 user(s) selected'), findsWidgets);

      // Tap Add Selected Users
      await tester.tap(find.byKey(const Key('dialog_add_selected_users_button')));
      await tester.pumpAndSettle();

      // Both added
      expect(find.text('Additional Internal Persons (2)'), findsOneWidget);
      expect(find.text('Brenda Roy'), findsOneWidget);
      expect(find.text('Chetan Patel'), findsOneWidget);
    },
  );

  testWidgets(
    '3. Add users from different departments & sites in repeated operations and prevent duplicates',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Set Primary Assignee to Rahul Sharma (HSE)
      final internalSearch = find.widgetWithText(
        TextFormField,
        'Search by name, email, or phone...',
      );
      await tester.enterText(internalSearch, 'Rahul');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rahul Sharma'));
      await tester.pumpAndSettle();

      // First addition: Brenda from Civil
      await tester.tap(find.text('Add Internal Person'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dialog_department_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Civil Engineering').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('user_checkbox_${civilStaff1.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dialog_add_selected_users_button')));
      await tester.pumpAndSettle();

      expect(find.text('Additional Internal Persons (1)'), findsOneWidget);
      expect(find.text('Brenda Roy'), findsOneWidget);

      // Second addition: Open dialog again
      await tester.tap(find.text('Add Internal Person'));
      await tester.pumpAndSettle();

      // Verify Brenda is now marked "Already Added"
      await tester.tap(find.byKey(const Key('dialog_department_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Civil Engineering').last);
      await tester.pumpAndSettle();

      expect(find.text('Already Added'), findsOneWidget);

      // Select Finance department
      await tester.tap(find.byKey(const Key('dialog_department_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finance').last);
      await tester.pumpAndSettle();

      // David Nair from Finance / Corporate HQ appears
      expect(find.text('David Nair'), findsOneWidget);
      expect(find.textContaining('Corporate HQ'), findsOneWidget);

      // Select David
      await tester.tap(find.byKey(Key('user_checkbox_${financeStaff.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dialog_add_selected_users_button')));
      await tester.pumpAndSettle();

      // Both cross-department & cross-site users are now present on the same action!
      expect(find.text('Additional Internal Persons (2)'), findsOneWidget);
      expect(find.text('Brenda Roy'), findsOneWidget);
      expect(find.text('David Nair'), findsOneWidget);

      // Verify Primary Assignee is still Rahul Sharma
      expect(find.text('Primary'), findsOneWidget);
      expect(find.text('Rahul Sharma'), findsWidgets);

      // Remove Brenda Roy
      final removeButtons = find.byTooltip('Remove');
      // Primary has 1, additional has 2
      expect(removeButtons, findsNWidgets(3));
      await tester.tap(removeButtons.at(1));
      await tester.pumpAndSettle();

      expect(find.text('Additional Internal Persons (1)'), findsOneWidget);
      expect(find.text('Brenda Roy'), findsNothing);
      expect(find.text('David Nair'), findsOneWidget);
    },
  );

  testWidgets(
    '4. Inactive users are excluded from the selection list',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Open Add Internal Person dialog
      await tester.tap(find.text('Add Internal Person'));
      await tester.pumpAndSettle();

      // Select HSE department
      await tester.tap(find.byKey(const Key('dialog_department_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HSE').last);
      await tester.pumpAndSettle();

      // Rahul Sharma (active) is present
      expect(find.text('Rahul Sharma'), findsOneWidget);

      // Inactive OldStaff (isActive: false) must NEVER be offered
      expect(find.text('Inactive OldStaff'), findsNothing);
    },
  );

  testWidgets(
    '5. Select All and Deselect All functionality in dialog',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Internal Person'));
      await tester.pumpAndSettle();

      // Select Civil Engineering (has Brenda and Chetan)
      await tester.tap(find.byKey(const Key('dialog_department_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Civil Engineering').last);
      await tester.pumpAndSettle();

      // Tap "Select All"
      await tester.tap(find.byKey(const Key('dialog_select_all_button')));
      await tester.pumpAndSettle();

      expect(find.text('2 user(s) selected'), findsWidgets);
      expect(find.text('Deselect All'), findsOneWidget);

      // Tap "Deselect All"
      await tester.tap(find.byKey(const Key('dialog_select_all_button')));
      await tester.pumpAndSettle();

      expect(find.text('No users selected'), findsOneWidget);
      expect(find.text('Select All'), findsOneWidget);
    },
  );

  testWidgets(
    '6. Primary Internal Person scope restrictions remain strictly enforced',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Search for Brenda Roy (Civil Engineering - outside manager's HSE scope) in Primary field
      final internalSearch = find.widgetWithText(
        TextFormField,
        'Search by name, email, or phone...',
      );
      await tester.enterText(internalSearch, 'Brenda');
      await tester.pumpAndSettle();

      // Brenda Roy must NOT be offered as Primary Assignee because Manager scope is HSE / Tower A only
      expect(find.text('Brenda Roy'), findsNothing);

      // Search for Rahul Sharma (HSE / Tower A - inside manager scope)
      await tester.enterText(internalSearch, 'Rahul');
      await tester.pumpAndSettle();

      expect(find.text('Rahul Sharma'), findsOneWidget);
    },
  );

  testWidgets(
    '7. ActionRecord persistence seeds additional people into action_assignees structure',
    (tester) async {
      // Create ActionRecord with primary owner + cross-department additional users
      final testRecord = ActionRecord(
        id: 'action-test-persist-1',
        actionNumber: 'AC-1001',
        subject: 'Perimeter Check',
        actionRequired: 'Verify safety fence',
        division: 'Operations',
        department: 'HSE',
        site: 'Tower A',
        assignedTo: 'Rahul Sharma',
        assignedToId: hseStaff.id,
        organizationId: testOrgId,
        primaryAssignee: ActionPersonReference(
          personId: hseStaff.id,
          name: hseStaff.name,
          email: hseStaff.email,
          phone: hseStaff.phone,
          designation: hseStaff.designation,
          department: hseStaff.department,
          site: hseStaff.site,
          type: PersonType.internalUser,
        ),
        additionalPeople: [
          ActionPersonReference(
            personId: civilStaff1.id,
            name: civilStaff1.name,
            email: civilStaff1.email,
            phone: civilStaff1.phone,
            designation: civilStaff1.designation,
            department: civilStaff1.department,
            site: civilStaff1.site,
            type: PersonType.internalUser,
          ),
          ActionPersonReference(
            personId: financeStaff.id,
            name: financeStaff.name,
            email: financeStaff.email,
            phone: financeStaff.phone,
            designation: financeStaff.designation,
            department: financeStaff.department,
            site: financeStaff.site,
            type: PersonType.internalUser,
          ),
        ],
      );

      // Extract desired assignees as ActionService does during save
      final assignees = ActionService.instance.testExtractDesiredAssignees(
        testRecord,
        actionId: testRecord.id,
        fallbackOwnerId: testRecord.assignedToId,
        fallbackOwnerName: testRecord.assignedTo,
      );

      // Must have 3 assignees: 1 owner + 2 assignees
      expect(assignees.length, equals(3));

      // Owner is primary assignee
      final owner = assignees.firstWhere((a) => a.assignmentRole == 'owner');
      expect(owner.profileId, equals(hseStaff.id));
      expect(owner.profileName, equals('Rahul Sharma'));

      // Additional assignees
      final civilAssignee = assignees.firstWhere((a) => a.profileId == civilStaff1.id);
      expect(civilAssignee.assignmentRole, equals('assignee'));
      expect(civilAssignee.profileName, equals('Brenda Roy'));

      final financeAssignee = assignees.firstWhere((a) => a.profileId == financeStaff.id);
      expect(financeAssignee.assignmentRole, equals('assignee'));
      expect(financeAssignee.profileName, equals('David Nair'));
    },
  );
}
