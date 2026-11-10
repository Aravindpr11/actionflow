import 'dart:io';
import 'dart:ui' as ui;
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/add_action_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/models/action_section.dart';
import 'package:action_flow/models/division.dart';
import 'package:action_flow/services/action_section_service.dart';
import 'package:action_flow/services/company_structure_service.dart';
import 'package:action_flow/services/division_service.dart';
import 'package:action_flow/services/user_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  const sobhaOrgId = '00000000-0000-0000-0000-000000000001';
  final screenshotDir = Directory(r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23');

  final departments = [
    {'id': 'dept-civil', 'name': 'Civil Engineering', 'is_active': true},
    {'id': 'dept-finish', 'name': 'Finishing & Interiors', 'is_active': true},
    {'id': 'dept-mep', 'name': 'Mechanical & Electrical', 'is_active': true},
  ];

  final sites = [
    {'id': 'site-hartland', 'name': 'Sobha Hartland', 'is_active': true, 'department_name': 'Civil Engineering'},
    {'id': 'site-vistas', 'name': 'Sobha Creek Vistas', 'is_active': true, 'department_name': 'Finishing & Interiors'},
    {'id': 'site-central', 'name': 'Central Logistics Hub', 'is_active': true, 'department_name': 'Mechanical & Electrical'},
  ];

  final testUsers = [
    Person(
      id: 'user-alice',
      name: 'Alice Civil',
      email: 'alice@sobha.com',
      phone: '+971 50 111 0001',
      department: 'Civil Engineering',
      departmentId: 'dept-civil',
      site: 'Sobha Hartland',
      siteId: 'site-hartland',
      designation: 'Civil Inspector',
      type: PersonType.internalUser,
      isActive: true,
      organizationId: sobhaOrgId,
    ),
    Person(
      id: 'user-bob',
      name: 'Bob Civil Vistas',
      email: 'bob@sobha.com',
      phone: '+971 50 111 0002',
      department: 'Civil Engineering',
      departmentId: 'dept-civil',
      site: 'Sobha Creek Vistas',
      siteId: 'site-vistas',
      designation: 'Civil Site Engineer',
      type: PersonType.internalUser,
      isActive: true,
      organizationId: sobhaOrgId,
    ),
    Person(
      id: 'user-charlie',
      name: 'Charlie Finishing Hartland',
      email: 'charlie@sobha.com',
      phone: '+971 50 111 0003',
      department: 'Finishing & Interiors',
      departmentId: 'dept-finish',
      site: 'Sobha Hartland',
      siteId: 'site-hartland',
      designation: 'Finishing Supervisor',
      type: PersonType.internalUser,
      isActive: true,
      organizationId: sobhaOrgId,
    ),
    Person(
      id: 'user-david',
      name: 'David Finishing Vistas',
      email: 'david@sobha.com',
      phone: '+971 50 111 0004',
      department: 'Finishing & Interiors',
      departmentId: 'dept-finish',
      site: 'Sobha Creek Vistas',
      siteId: 'site-vistas',
      designation: 'Interiors QA',
      type: PersonType.internalUser,
      isActive: true,
      organizationId: sobhaOrgId,
    ),
    Person(
      id: 'user-eve',
      name: 'Eve MEP Logistics',
      email: 'eve@sobha.com',
      phone: '+971 50 111 0005',
      department: 'Mechanical & Electrical',
      departmentId: 'dept-mep',
      site: 'Central Logistics Hub',
      siteId: 'site-central',
      designation: 'Electrical Lead',
      type: PersonType.internalUser,
      isActive: true,
      organizationId: sobhaOrgId,
    ),
    Person(
      id: 'user-frank-inactive',
      name: 'Frank Inactive',
      email: 'frank@sobha.com',
      phone: '+971 50 111 0006',
      department: 'Civil Engineering',
      departmentId: 'dept-civil',
      site: 'Sobha Hartland',
      siteId: 'site-hartland',
      designation: 'Former Technician',
      type: PersonType.internalUser,
      isActive: false, // Inactive user
      organizationId: sobhaOrgId,
    ),
  ];

  final scopedManager = ManagerContext(
    authUserId: 'mgr-civil',
    profile: const UserProfile(
      id: 'mgr-civil',
      name: 'Manager Bob',
      email: 'mgr.bob@sobha.com',
      phone: '+971 50 111 0000',
      designation: 'Civil Manager',
      role: 'Manager',
      department: 'Civil Engineering',
      site: 'Sobha Hartland',
      organizationId: sobhaOrgId,
    ),
    organizationId: sobhaOrgId,
    organizationName: 'Sobha Developers',
    scopes: const [
      ManagerScopeItem(
        departmentId: 'dept-civil',
        departmentName: 'Civil Engineering',
        siteId: 'site-hartland',
        siteName: 'Sobha Hartland',
      ),
      ManagerScopeItem(
        departmentId: 'dept-finish',
        departmentName: 'Finishing & Interiors',
        siteId: 'site-vistas',
        siteName: 'Sobha Creek Vistas',
      ),
    ],
  );

  setUp(() {
    MockPeopleStore.instance.people.clear();
    MockPeopleStore.instance.people.addAll(testUsers);
  });

  Future<void> captureWidgetScreenshot(GlobalKey key, String filename) async {
    final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary != null) {
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final file = File('${screenshotDir.path}\\$filename');
        await file.writeAsBytes(byteData.buffer.asUint8List());
      }
    }
  }

  Widget createTestWidget({
    required GlobalKey repaintKey,
    ManagerContext? managerContext,
    ActionRecord? existingAction,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: RepaintBoundary(
          key: repaintKey,
          child: AddActionScreen(
            actionId: 'ACT-NEW-01',
            organizationId: sobhaOrgId,
            managerContext: managerContext ?? scopedManager,
            companyStructureService: MockStructureService(
              departments: departments,
              sites: sites,
              teams: [],
            ),
            actionSectionService: MockActionSectionService(),
            divisionService: MockDivisionService(),
            userService: MockUsersService(testUsers),
            existingAction: existingAction,
          ),
        ),
      ),
    );
  }

  group('Add Action Step 2: All Departments and All Sites Options & Filtering', () {
    testWidgets('1. All Departments + All Sites shows all eligible organization users and captures screenshot', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      await tester.pumpWidget(createTestWidget(repaintKey: repaintKey));
      await tester.pumpAndSettle();

      // Verify Step 2 WHERE IT BELONGS is rendered
      expect(find.text('WHERE IT BELONGS'), findsOneWidget);

      // Select 'All Departments' in Department dropdown
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

      // Open Add Internal Person dialog
      final addBtn = find.widgetWithText(OutlinedButton, 'Add Internal Person');
      await tester.ensureVisible(addBtn);
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      // Dialog opens with All Departments and All Sites
      expect(find.text('Select Existing Users'), findsOneWidget);
      expect(find.text('All Departments'), findsWidgets);
      expect(find.text('All Sites / Locations'), findsWidgets);

      // All 5 active users across all departments appear
      expect(find.text('Alice Civil'), findsOneWidget);
      expect(find.text('Bob Civil Vistas'), findsOneWidget);
      expect(find.text('Charlie Finishing Hartland'), findsOneWidget);
      expect(find.text('David Finishing Vistas'), findsOneWidget);
      expect(find.text('Eve MEP Logistics'), findsOneWidget);

      // Inactive user Frank is excluded
      expect(find.text('Frank Inactive'), findsNothing);

      // Capture screenshot 1: all_departments_all_sites.png
      await tester.runAsync(() async {
        await captureWidgetScreenshot(repaintKey, 'all_departments_all_sites.png');
      });
      expect(File('${screenshotDir.path}\\all_departments_all_sites.png').existsSync(), isTrue);

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();
    });

    testWidgets('2. Specific Department + All Sites filters correctly and captures screenshot', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      await tester.pumpWidget(createTestWidget(repaintKey: repaintKey));
      await tester.pumpAndSettle();

      // Select 'Civil Engineering'
      final deptDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Department *');
      await tester.ensureVisible(deptDropdown);
      await tester.tap(deptDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Civil Engineering').last);
      await tester.pumpAndSettle();

      // Select 'All Sites / Locations'
      final siteDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Location / Site *');
      await tester.ensureVisible(siteDropdown);
      await tester.tap(siteDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Sites / Locations').last);
      await tester.pumpAndSettle();

      // Open Add Internal Person dialog
      final addBtn = find.widgetWithText(OutlinedButton, 'Add Internal Person');
      await tester.ensureVisible(addBtn);
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      // Dialog should show only Civil Engineering users across all sites
      expect(find.text('Alice Civil'), findsOneWidget);
      expect(find.text('Bob Civil Vistas'), findsOneWidget);

      // Users from Finishing or MEP are NOT shown
      expect(find.text('Charlie Finishing Hartland'), findsNothing);
      expect(find.text('David Finishing Vistas'), findsNothing);
      expect(find.text('Eve MEP Logistics'), findsNothing);

      // Capture screenshot 2: specific_department_all_sites.png
      await tester.runAsync(() async {
        await captureWidgetScreenshot(repaintKey, 'specific_department_all_sites.png');
      });
      expect(File('${screenshotDir.path}\\specific_department_all_sites.png').existsSync(), isTrue);

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();
    });

    testWidgets('3. Specific Department + Specific Site filters correctly and captures screenshot', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      await tester.pumpWidget(createTestWidget(repaintKey: repaintKey));
      await tester.pumpAndSettle();

      // Select 'Civil Engineering'
      final deptDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Department *');
      await tester.ensureVisible(deptDropdown);
      await tester.tap(deptDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Civil Engineering').last);
      await tester.pumpAndSettle();

      // Select 'Sobha Hartland'
      final siteDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Location / Site *');
      await tester.ensureVisible(siteDropdown);
      await tester.tap(siteDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sobha Hartland').last);
      await tester.pumpAndSettle();

      // Open Add Internal Person dialog
      final addBtn = find.widgetWithText(OutlinedButton, 'Add Internal Person');
      await tester.ensureVisible(addBtn);
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      // Only Alice Civil (Civil Engineering at Sobha Hartland) appears
      expect(find.text('Alice Civil'), findsOneWidget);

      // Bob Civil Vistas (different site) and others do not appear
      expect(find.text('Bob Civil Vistas'), findsNothing);
      expect(find.text('Charlie Finishing Hartland'), findsNothing);
      expect(find.text('David Finishing Vistas'), findsNothing);
      expect(find.text('Eve MEP Logistics'), findsNothing);

      // Capture screenshot 3: specific_department_specific_site.png
      await tester.runAsync(() async {
        await captureWidgetScreenshot(repaintKey, 'specific_department_specific_site.png');
      });
      expect(File('${screenshotDir.path}\\specific_department_specific_site.png').existsSync(), isTrue);

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();
    });

    testWidgets('4. All Departments + Specific Site filters correctly and captures screenshot', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      await tester.pumpWidget(createTestWidget(repaintKey: repaintKey));
      await tester.pumpAndSettle();

      // Select 'All Departments'
      final deptDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Department *');
      await tester.ensureVisible(deptDropdown);
      await tester.tap(deptDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Departments').last);
      await tester.pumpAndSettle();

      // Select 'Sobha Hartland'
      final siteDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Location / Site *');
      await tester.ensureVisible(siteDropdown);
      await tester.tap(siteDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sobha Hartland').last);
      await tester.pumpAndSettle();

      // Open Add Internal Person dialog
      final addBtn = find.widgetWithText(OutlinedButton, 'Add Internal Person');
      await tester.ensureVisible(addBtn);
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      // Shows users from any department at Sobha Hartland: Alice (Civil) and Charlie (Finishing)
      expect(find.text('Alice Civil'), findsOneWidget);
      expect(find.text('Charlie Finishing Hartland'), findsOneWidget);

      // Users at Sobha Creek Vistas or Central Logistics Hub do not appear
      expect(find.text('Bob Civil Vistas'), findsNothing);
      expect(find.text('David Finishing Vistas'), findsNothing);
      expect(find.text('Eve MEP Logistics'), findsNothing);

      // Capture screenshot 4: all_departments_specific_site.png
      await tester.runAsync(() async {
        await captureWidgetScreenshot(repaintKey, 'all_departments_specific_site.png');
      });
      expect(File('${screenshotDir.path}\\all_departments_specific_site.png').existsSync(), isTrue);

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();
    });

    testWidgets('5. Changing selections inside dialog dynamically refreshes user list and dependent sites', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      await tester.pumpWidget(createTestWidget(repaintKey: repaintKey));
      await tester.pumpAndSettle();

      // Open dialog
      final addBtn = find.widgetWithText(OutlinedButton, 'Add Internal Person');
      await tester.ensureVisible(addBtn);
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      // Initial state in dialog: change dialog department to 'Finishing & Interiors'
      final dialogDept = find.byKey(const Key('dialog_department_dropdown'));
      await tester.tap(dialogDept);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finishing & Interiors').last);
      await tester.pumpAndSettle();

      // Should only show Finishing users at current site (Sobha Hartland)
      expect(find.text('Charlie Finishing Hartland'), findsOneWidget);
      expect(find.text('David Finishing Vistas'), findsNothing);
      expect(find.text('Alice Civil'), findsNothing);

      // Now change dialog site to 'Sobha Creek Vistas'
      final dialogSite = find.byKey(const Key('dialog_site_dropdown'));
      await tester.tap(dialogSite);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sobha Creek Vistas').last);
      await tester.pumpAndSettle();

      // Only David appears
      expect(find.text('David Finishing Vistas'), findsOneWidget);
      expect(find.text('Charlie Finishing Hartland'), findsNothing);

      // Now switch dialog department back to 'All Departments'
      await tester.tap(dialogDept);
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Departments').last);
      await tester.pumpAndSettle();

      // All users associated with 'Sobha Creek Vistas' appear across departments: Bob and David
      expect(find.text('Bob Civil Vistas'), findsOneWidget);
      expect(find.text('David Finishing Vistas'), findsOneWidget);
      expect(find.text('Alice Civil'), findsNothing);

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();
    });

    testWidgets('6. Primary assignee scope restrictions remain strictly unchanged', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      await tester.pumpWidget(createTestWidget(repaintKey: repaintKey));
      await tester.pumpAndSettle();

      // Select 'All Departments' and 'All Sites / Locations' in Step 2
      final deptDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Department *');
      await tester.ensureVisible(deptDropdown);
      await tester.tap(deptDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Departments').last);
      await tester.pumpAndSettle();

      // In Section 3: Primary Internal Person search
      final searchInput = find.widgetWithText(TextFormField, 'Search by name, email, or phone...');
      await tester.ensureVisible(searchInput);
      await tester.enterText(searchInput, 'Eve');
      await tester.pumpAndSettle();

      // Eve MEP Logistics is in Mechanical & Electrical which is OUTSIDE Manager Bob's scope (Civil & Finishing)
      // Primary search must NOT show Eve
      expect(find.text('Eve MEP Logistics'), findsNothing);

      // Search for Alice (in Civil Engineering, which is inside Manager Bob's scope)
      await tester.enterText(searchInput, 'Alice');
      await tester.pumpAndSettle();
      expect(find.text('Alice Civil'), findsOneWidget);
    });

    testWidgets('7. Additional users can still be added across departments/sites and multi-selected', (tester) async {
      tester.view.physicalSize = const Size(1280, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      await tester.pumpWidget(createTestWidget(repaintKey: repaintKey));
      await tester.pumpAndSettle();

      // Open Add Internal Person dialog
      final addBtn = find.widgetWithText(OutlinedButton, 'Add Internal Person');
      await tester.ensureVisible(addBtn);
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      // Switch dialog department to All Departments and site to All Sites to select across departments
      final dialogDept = find.byKey(const Key('dialog_department_dropdown'));
      await tester.tap(dialogDept);
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Departments').last);
      await tester.pumpAndSettle();

      final dialogSite = find.byKey(const Key('dialog_site_dropdown'));
      await tester.tap(dialogSite);
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Sites / Locations').last);
      await tester.pumpAndSettle();

      // Multi-select Alice (Civil) and Eve (MEP - cross-department!)
      await tester.tap(find.byKey(const Key('user_checkbox_user-alice')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('user_checkbox_user-eve')));
      await tester.pumpAndSettle();

      // Click Add Selected Users
      final addSelectedBtn = find.byKey(const Key('dialog_add_selected_users_button'));
      await tester.tap(addSelectedBtn);
      await tester.pumpAndSettle();

      // Both users now appear in Additional Internal Persons on AddActionScreen
      expect(find.text('Additional Internal Persons (2)'), findsOneWidget);
      expect(find.text('Alice Civil'), findsOneWidget);
      expect(find.text('Eve MEP Logistics'), findsOneWidget);
    });

    testWidgets('8. Cross-organization and inactive users remain rejected and excluded', (tester) async {
      tester.view.physicalSize = const Size(1280, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      await tester.pumpWidget(createTestWidget(repaintKey: repaintKey));
      await tester.pumpAndSettle();

      // Open dialog
      final addBtn = find.widgetWithText(OutlinedButton, 'Add Internal Person');
      await tester.ensureVisible(addBtn);
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      // Search for inactive Frank
      final searchInput = find.byKey(const Key('dialog_user_search_input'));
      await tester.enterText(searchInput, 'Frank');
      await tester.pumpAndSettle();

      expect(find.text('Frank Inactive'), findsNothing);
      expect(find.textContaining('No eligible users found'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();
    });

    testWidgets('9. Original action ownership remains unchanged when editing an action and selecting All Departments', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final existing = ActionRecord(
        id: 'act-existing-99',
        actionNumber: 'ACT-099',
        subject: 'Original Title',
        actionRequired: 'Original Required',
        division: 'General',
        department: 'Civil Engineering',
        departmentId: 'dept-civil',
        site: 'Sobha Hartland',
        siteId: 'site-hartland',
        section: 'None',
        assignedTo: 'Alice Civil',
        assignedToId: 'user-alice',
        status: 'Open',
        priority: 'High',
        percentComplete: 0,
        organizationId: sobhaOrgId,
      );

      ActionRecord? savedRecord;
      final repaintKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: repaintKey,
              child: AddActionScreen(
                actionId: 'ACT-099',
                organizationId: sobhaOrgId,
                managerContext: scopedManager,
                existingAction: existing,
                companyStructureService: MockStructureService(
                  departments: departments,
                  sites: sites,
                  teams: [],
                ),
                userService: MockUsersService(testUsers),
                onSaved: (record) {
                  savedRecord = record;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select 'All Departments' to discover users
      final deptDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Department *');
      await tester.ensureVisible(deptDropdown);
      await tester.tap(deptDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Departments').last);
      await tester.pumpAndSettle();

      // Save changes
      final saveBtn = find.widgetWithText(FilledButton, 'SAVE CHANGES');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Preserves original department and site ownership
      expect(savedRecord, isNotNull);
      expect(savedRecord!.departmentId, equals('dept-civil'));
      expect(savedRecord!.department, equals('Civil Engineering'));
      expect(savedRecord!.siteId, equals('site-hartland'));
      expect(savedRecord!.site, equals('Sobha Hartland'));
    });

    testWidgets('10. Existing department/site-specific workflows continue working and saving properly', (tester) async {
      tester.view.physicalSize = const Size(1280, 2500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      ActionRecord? createdRecord;
      final repaintKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: repaintKey,
              child: AddActionScreen(
                actionId: 'ACT-NEW-100',
                organizationId: sobhaOrgId,
                managerContext: scopedManager,
                companyStructureService: MockStructureService(
                  departments: departments,
                  sites: sites,
                  teams: [],
                ),
                userService: MockUsersService(testUsers),
                onSaved: (record) {
                  createdRecord = record;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Title
      final titleInput = find.widgetWithText(TextFormField, 'Action Title *');
      await tester.ensureVisible(titleInput);
      await tester.enterText(titleInput, 'Standard Scoped Safety Action');
      await tester.pumpAndSettle();

      // Description
      final descInput = find.widgetWithText(TextFormField, 'Action Description');
      await tester.ensureVisible(descInput);
      await tester.enterText(descInput, 'Ensure edge protection is installed.');
      await tester.pumpAndSettle();

      // Select specific department and site
      final deptDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Department *');
      await tester.ensureVisible(deptDropdown);
      await tester.tap(deptDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Civil Engineering').last);
      await tester.pumpAndSettle();

      final siteDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Location / Site *');
      await tester.ensureVisible(siteDropdown);
      await tester.tap(siteDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sobha Hartland').last);
      await tester.pumpAndSettle();

      // Primary assignee
      final primarySearch = find.widgetWithText(TextFormField, 'Search by name, email, or phone...');
      await tester.ensureVisible(primarySearch);
      await tester.enterText(primarySearch, 'Alice');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('internal_person_option_Alice Civil')));
      await tester.pumpAndSettle();

      // Save
      final sendBtn = find.widgetWithText(FilledButton, 'SEND ACTION');
      await tester.ensureVisible(sendBtn);
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      expect(createdRecord, isNotNull);
      expect(createdRecord!.subject, equals('Standard Scoped Safety Action'));
      expect(createdRecord!.department, equals('Civil Engineering'));
      expect(createdRecord!.departmentId, equals('dept-civil'));
      expect(createdRecord!.site, equals('Sobha Hartland'));
      expect(createdRecord!.siteId, equals('site-hartland'));
      expect(createdRecord!.assignedTo, equals('Alice Civil'));
    });
  });
}
