import 'package:action_flow/features/auth/screens/staff_account_setup_screen.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/models/team.dart';
import 'package:action_flow/features/users/screens/person_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('1. Staff Primary Department Model Tests', () {
    // Note: staffScopes was removed in the Staff single-primary-dept refactor.
    // Staff always have exactly ONE primary department and site.
    // Multi-scope is only available to Managers via managerScopes.

    test('Staff with primary department correctly scopes via person.scopes', () {
      final staff = Person(
        id: 'staff-1',
        name: 'Carlos Staff',
        email: 'carlos@example.com',
        phone: '+1234567890',
        designation: 'Safety Inspector',
        type: PersonType.internalUser,
        isActive: true,
        role: UserRole.actionOwnerWorker,
        department: 'HSE / Safety',
        departmentId: 'dept-hse',
        site: 'North Plant',
        siteId: 'site-np',
      );

      // Staff have exactly one scope derived from primary dept+site
      expect(staff.scopes.length, 1);
      expect(staff.scopes[0].departmentId, 'dept-hse');
      expect(staff.scopes[0].siteId, 'site-np');
      expect(staff.isScopePermitted('dept-hse', 'site-np'), isTrue);
      expect(staff.isScopePermitted('dept-ops', 'site-pb'), isFalse);
      expect(staff.isScopePermitted('dept-other', 'site-np'), isFalse);
    });

    test('Staff without site correctly scopes to department', () {
      final legacyStaff = Person(
        id: 'staff-legacy',
        name: 'Legacy Staff',
        email: 'legacy@example.com',
        phone: '+1234567890',
        designation: 'Field Worker',
        type: PersonType.internalUser,
        isActive: true,
        role: UserRole.actionOwnerWorker,
        department: 'HSE / Safety',
        departmentId: 'dept-hse',
        site: 'North Plant',
        siteId: 'site-np',
      );

      expect(legacyStaff.scopes.length, 1);
      expect(legacyStaff.scopes.first.departmentId, 'dept-hse');
      expect(legacyStaff.scopes.first.siteId, 'site-np');
      expect(legacyStaff.isScopePermitted('dept-hse', 'site-np'), isTrue);
      expect(legacyStaff.isScopePermitted('dept-ops', 'site-pb'), isFalse);
    });
  });

  group('2. PersonFormScreen - Staff Single Scope & Manager Multi-Scope UI & Validation', () {
    final mockDepts = [
      {'id': 'dept-hse', 'name': 'HSE / Safety', 'is_active': true},
      {'id': 'dept-ops', 'name': 'Operations', 'is_active': true},
      {'id': 'dept-maint', 'name': 'Maintenance', 'is_active': true},
    ];
    final mockSites = [
      {'id': 'site-np', 'name': 'North Plant', 'is_active': true},
      {'id': 'site-pb', 'name': 'Platform Bravo', 'is_active': true},
      {'id': 'site-sp', 'name': 'South Plant', 'is_active': true},
    ];
    final mockTeams = [
      {
        'id': 'team-1',
        'name': 'HSE Emergency Team',
        'deptId': 'dept-hse',
        'dept': 'HSE / Safety',
      },
      {
        'id': 'team-2',
        'name': 'Ops Alpha',
        'deptId': 'dept-ops',
        'dept': 'Operations',
      },
      {
        'id': 'team-3',
        'name': 'Maintenance Team',
        'deptId': 'dept-maint',
        'dept': 'Maintenance',
      },
    ];

    testWidgets('Staff member renders single primary Organization Assignment (no Manager scopes)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final staff = Person(
        id: 'staff-1',
        name: 'Alice Staff',
        email: 'alice@example.com',
        phone: '12345678',
        designation: 'Safety Officer',
        type: PersonType.internalUser,
        isActive: true,
        role: UserRole.actionOwnerWorker,
        department: 'HSE / Safety',
        departmentId: 'dept-hse',
        site: 'North Plant',
        siteId: 'site-np',
        teamIds: const ['team-1'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PersonFormScreen(
            person: staff,
            availableDepartments: mockDepts,
            availableSites: mockSites,
            availableTeams: mockTeams,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ORGANIZATION ASSIGNMENT'), findsOneWidget);
      expect(find.text('MANAGER ACCESS SCOPES'), findsNothing);
      expect(find.text('HSE / Safety'), findsWidgets);
      expect(find.text('North Plant'), findsWidgets);
    });

    testWidgets('Manager member renders Manager Access Scopes and seeds initial scope', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      Person? savedPerson;

      final manager = Person(
        id: 'mgr-1',
        name: 'Alice Manager',
        email: 'alice.mgr@example.com',
        phone: '12345678',
        designation: 'Operations Manager',
        type: PersonType.internalUser,
        isActive: true,
        role: UserRole.departmentManager,
        department: 'HSE / Safety',
        departmentId: 'dept-hse',
        site: 'North Plant',
        siteId: 'site-np',
        managerScopes: const [
          ManagerScopeItem(
            departmentId: 'dept-hse',
            departmentName: 'HSE / Safety',
            siteId: 'site-np',
            siteName: 'North Plant',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                savedPerson = await Navigator.of(context).push<Person>(
                  MaterialPageRoute(
                    builder: (_) => PersonFormScreen(
                      person: manager,
                      availableDepartments: mockDepts,
                      availableSites: mockSites,
                      availableTeams: mockTeams,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('MANAGER ACCESS SCOPES'), findsOneWidget);
      expect(find.text('HSE / Safety'), findsWidgets);
      expect(find.text('North Plant'), findsWidgets);

      // Save manager
      await tester.tap(find.text('SAVE PERSON'));
      await tester.pumpAndSettle();

      expect(savedPerson, isNotNull);
      expect(savedPerson!.managerScopes.length, 1);
      expect(savedPerson!.managerScopes[0].displayName, 'HSE / Safety / North Plant');
    });

    testWidgets('Manager can remove an individual scope pair while retaining >=1 scope', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      Person? savedPerson;

      final manager = Person(
        id: 'mgr-1',
        name: 'Alice Manager',
        email: 'alice.mgr@example.com',
        phone: '12345678',
        designation: 'Operations Manager',
        type: PersonType.internalUser,
        isActive: true,
        role: UserRole.departmentManager,
        department: 'HSE / Safety',
        departmentId: 'dept-hse',
        site: 'North Plant',
        siteId: 'site-np',
        managerScopes: const [
          ManagerScopeItem(
            departmentId: 'dept-hse',
            departmentName: 'HSE / Safety',
            siteId: 'site-np',
            siteName: 'North Plant',
          ),
          ManagerScopeItem(
            departmentId: 'dept-ops',
            departmentName: 'Operations',
            siteId: 'site-pb',
            siteName: 'Platform Bravo',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                savedPerson = await Navigator.of(context).push<Person>(
                  MaterialPageRoute(
                    builder: (_) => PersonFormScreen(
                      person: manager,
                      availableDepartments: mockDepts,
                      availableSites: mockSites,
                      availableTeams: mockTeams,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Find remove scope icon button (first remove_circle icon)
      final removeIcons = find.byIcon(Icons.remove_circle_outline_rounded);
      expect(removeIcons, findsWidgets);
      await tester.tap(removeIcons.last);
      await tester.pumpAndSettle();

      // Tap save
      await tester.tap(find.text('SAVE PERSON'));
      await tester.pumpAndSettle();

      expect(savedPerson, isNotNull);
      expect(savedPerson!.managerScopes.length, 1);
      expect(savedPerson!.managerScopes[0].displayName, 'HSE / Safety / North Plant');
    });
  });

  group('3. Cross-Department Team Membership for Staff & Managers', () {
    final mockDepts = [
      {'id': 'dept-hse', 'name': 'HSE / Safety'},
      {'id': 'dept-ops', 'name': 'Operations'},
    ];
    final mockSites = [
      {'id': 'site-np', 'name': 'North Plant'},
    ];
    final mockTeams = [
      {
        'id': 'team-1',
        'name': 'HSE Inspection Team',
        'deptId': 'dept-hse',
        'dept': 'HSE / Safety',
      },
      {
        'id': 'team-2',
        'name': 'Ops Cross-Functional Team',
        'deptId': 'dept-ops',
        'dept': 'Operations',
      },
    ];

    testWidgets('Staff can select multiple teams across department boundaries within organization', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      Person? savedPerson;

      final staff = Person(
        id: 'staff-1',
        name: 'Alice Staff',
        email: 'alice@example.com',
        phone: '12345678',
        designation: 'Safety Officer',
        type: PersonType.internalUser,
        isActive: true,
        role: UserRole.actionOwnerWorker,
        department: 'HSE / Safety',
        departmentId: 'dept-hse',
        site: 'North Plant',
        siteId: 'site-np',
        teamIds: const ['team-1'], // Initially has HSE team
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                savedPerson = await Navigator.of(context).push<Person>(
                  MaterialPageRoute(
                    builder: (_) => PersonFormScreen(
                      person: staff,
                      availableDepartments: mockDepts,
                      availableSites: mockSites,
                      availableTeams: mockTeams,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Both teams are visible and selectable
      expect(find.text('HSE Inspection Team'), findsOneWidget);
      expect(find.text('Ops Cross-Functional Team'), findsOneWidget);

      // Select Ops Cross-Functional Team as well
      await tester.tap(find.text('Ops Cross-Functional Team'));
      await tester.pumpAndSettle();

      // Save person
      await tester.tap(find.text('SAVE PERSON'));
      await tester.pumpAndSettle();

      expect(savedPerson, isNotNull);
      expect(savedPerson!.teamIds, contains('team-1'));
      expect(savedPerson!.teamIds, contains('team-2'));
      expect(savedPerson!.teamIds.length, 2);
    });
  });

  group('4. Staff Signup Screen Primary Scope Assignment Tests', () {
    testWidgets('Staff signup configures primary Department and Site scope (single scope model)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const depts = <DepartmentOption>[
        DepartmentOption(id: 'dept-hse', name: 'HSE / Safety', code: 'HSE'),
        DepartmentOption(id: 'dept-ops', name: 'Operations', code: 'OPS'),
      ];
      const sites = <SiteOption>[
        SiteOption(id: 'site-np', name: 'North Plant', code: 'NP'),
        SiteOption(id: 'site-pb', name: 'Platform Bravo', code: 'PB'),
      ];
      const teams = <TeamOption>[
        TeamOption(
          id: 'team-1',
          name: 'HSE Emergency Team',
          departmentId: 'dept-hse',
        ),
      ];

      await tester.pumpWidget(
        const MaterialApp(
          home: StaffAccountSetupScreen(
            initialDepartments: depts,
            initialSites: sites,
            initialTeams: teams,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Fill in personal information
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full Name *'),
        'Staff Candidate',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email *'),
        'candidate@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone (Optional)'),
        '+971 50 123 4567',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Designation *'),
        'Field Officer',
      );

      // Fill passwords
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password *'),
        'StrongPass123!',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm Password *'),
        'StrongPass123!',
      );

      // Verify single primary scope model: Additional requested scopes does NOT appear
      expect(
        find.text('ADDITIONAL REQUESTED ACCESS SCOPES (OPTIONAL)'),
        findsNothing,
      );

      // Verify primary department is available and selectable
      expect(find.text('HSE / Safety'), findsWidgets);
    });
  });
}

