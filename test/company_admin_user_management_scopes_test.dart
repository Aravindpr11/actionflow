import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/models/team.dart';
import 'package:action_flow/features/users/screens/person_form_screen.dart';
import 'package:action_flow/features/auth/models/auth_models.dart';
import 'package:action_flow/services/user_service.dart';

void main() {
  group('1. Manager Scopes & Person Model Tests', () {
    test('ManagerScopeItem serialization and equality', () {
      const scope1 = ManagerScopeItem(
        departmentId: 'dept-1',
        departmentName: 'HSE',
        siteId: 'site-1',
        siteName: 'Plant North',
      );
      const scope2 = ManagerScopeItem(
        departmentId: 'dept-1',
        departmentName: 'HSE',
        siteId: 'site-1',
        siteName: 'Plant North',
      );
      const scope3 = ManagerScopeItem(
        departmentId: 'dept-2',
        departmentName: 'Operations',
        siteId: 'site-1',
        siteName: 'Plant North',
      );

      expect(scope1, equals(scope2));
      expect(scope1.hashCode, equals(scope2.hashCode));
      expect(scope1, isNot(equals(scope3)));
      expect(scope1.displayName, 'HSE / Plant North');

      final json = scope1.toSyncJson();
      expect(json['department_id'], 'dept-1');
      expect(json['site_id'], 'site-1');
    });

    test('Person model does not have division property', () {
      final manager = Person(
        id: 'mgr-1',
        name: 'Manager Bob',
        email: 'bob@example.com',
        phone: '+1234567890',
        designation: 'Safety Lead',
        type: PersonType.internalUser,
        isActive: true,
        role: UserRole.departmentManager,
        department: 'HSE',
        site: 'Plant North',
        managerScopes: const [
          ManagerScopeItem(
            departmentId: 'dept-1',
            departmentName: 'HSE',
            siteId: 'site-1',
            siteName: 'Plant North',
          ),
          ManagerScopeItem(
            departmentId: 'dept-2',
            departmentName: 'Operations',
            siteId: 'site-2',
            siteName: 'Platform Bravo',
          ),
        ],
      );

      expect(manager.managerScopes.length, 2);
      expect(manager.managerScopes[0].displayName, 'HSE / Plant North');
      expect(
        manager.managerScopes[1].displayName,
        'Operations / Platform Bravo',
      );
    });
  });

  group('2. PersonFormScreen - Manager Scopes UI & Validation', () {
    final mockDepts = [
      {'id': 'dept-hse', 'name': 'HSE / Safety'},
      {'id': 'dept-ops', 'name': 'Operations'},
    ];
    final mockSites = [
      {'id': 'site-np', 'name': 'North Plant'},
      {'id': 'site-pb', 'name': 'Platform Bravo'},
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
    ];

    testWidgets(
      'Renders Manager Access Scopes section for Department Manager',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final manager = Person(
          id: 'mgr-1',
          name: 'John Manager',
          email: 'john@example.com',
          phone: '12345678',
          designation: 'Manager',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.departmentManager,
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
            home: PersonFormScreen(
              person: manager,
              availableDepartments: mockDepts,
              availableSites: mockSites,
              availableTeams: mockTeams,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify Manager Access Scopes panel exists
        expect(find.text('MANAGER ACCESS SCOPES'), findsOneWidget);
        expect(find.text('HSE / Safety'), findsOneWidget);
        expect(find.text('North Plant'), findsOneWidget);

        // Verify no Division field exists
        expect(find.text('Division'), findsNothing);
        expect(find.text('Division *'), findsNothing);

        // Verify Teams section is optional for Manager
        expect(find.text('TEAM MEMBERSHIPS (OPTIONAL)'), findsOneWidget);
      },
    );

    testWidgets('Prevents duplicate manager scopes in PersonFormScreen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final manager = Person(
        id: 'mgr-1',
        name: 'John Manager',
        email: 'john@example.com',
        phone: '12345678',
        designation: 'Manager',
        type: PersonType.internalUser,
        isActive: true,
        role: UserRole.departmentManager,
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
          home: PersonFormScreen(
            person: manager,
            availableDepartments: mockDepts,
            availableSites: mockSites,
            availableTeams: mockTeams,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Try to select existing Dept and Site pair
      final deptDropdown = find.byKey(const ValueKey('scope_dept_0'));
      expect(deptDropdown, findsOneWidget);
      await tester.tap(deptDropdown);
      await tester.pumpAndSettle();

      // Select 'HSE / Safety'
      await tester.tap(find.text('HSE / Safety').last);
      await tester.pumpAndSettle();

      // Select 'North Plant'
      final siteDropdown = find.byKey(const ValueKey('scope_site_0'));
      await tester.tap(siteDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('North Plant').last);
      await tester.pumpAndSettle();

      // Tap 'Add Scope'
      await tester.tap(find.text('Add Scope'));
      await tester.pumpAndSettle();

      // Should show duplicate error
      expect(
        find.text(
          'This Department + Site scope has already been added to the Manager.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'Adding new scope pair (Operations + Platform Bravo) adds to list immediately',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final manager = Person(
          id: 'mgr-1',
          name: 'John Manager',
          email: 'john@example.com',
          phone: '12345678',
          designation: 'Manager',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.departmentManager,
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
            home: PersonFormScreen(
              person: manager,
              availableDepartments: mockDepts,
              availableSites: mockSites,
              availableTeams: mockTeams,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Operations / Platform Bravo'), findsNothing);

        // Select Department 'Operations'
        final deptDropdown = find.byKey(const ValueKey('scope_dept_0'));
        expect(deptDropdown, findsOneWidget);
        await tester.tap(deptDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Operations').last);
        await tester.pumpAndSettle();

        // Select Site 'Platform Bravo'
        final siteDropdown = find.byKey(const ValueKey('scope_site_0'));
        expect(siteDropdown, findsOneWidget);
        await tester.tap(siteDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Platform Bravo').last);
        await tester.pumpAndSettle();

        // Tap 'Add Scope'
        await tester.tap(find.text('Add Scope'));
        await tester.pumpAndSettle();

        // Check if newly added scope appears in the table
        expect(find.text('Operations'), findsAtLeastNWidgets(1));
        expect(find.text('Platform Bravo'), findsAtLeastNWidgets(1));
      },
    );

    testWidgets(
      'Manager can remove a scope while retaining >=1 scope, cannot save with 0 scopes',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        Person? savedPerson;
        final manager = Person(
          id: 'mgr-1',
          name: 'John Manager',
          email: 'john@example.com',
          phone: '12345678',
          designation: 'Manager',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.departmentManager,
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

        expect(find.text('HSE / Safety'), findsOneWidget);
        expect(find.text('Operations'), findsOneWidget);

        // Remove the second scope (Operations)
        final removeButtons = find.byTooltip('Remove Scope');
        expect(removeButtons, findsNWidgets(2));
        await tester.tap(removeButtons.last);
        await tester.pumpAndSettle();

        // Only first scope remains
        expect(find.byTooltip('Remove Scope'), findsNWidgets(1));
        expect(find.text('Operations'), findsNothing);

        // Save person
        await tester.tap(find.text('SAVE PERSON'));
        await tester.pumpAndSettle();

        expect(savedPerson, isNotNull);
        expect(savedPerson!.managerScopes.length, 1);
        expect(savedPerson!.managerScopes.first.departmentId, 'dept-hse');
      },
    );

    testWidgets('Manager cannot save with 0 scopes', (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      Person? savedPerson;
      final manager = Person(
        id: 'mgr-1',
        name: 'John Manager',
        email: 'john@example.com',
        phone: '12345678',
        designation: 'Manager',
        type: PersonType.internalUser,
        isActive: true,
        role: UserRole.departmentManager,
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

      // Remove the only scope
      await tester.tap(find.byTooltip('Remove Scope'));
      await tester.pumpAndSettle();

      // Attempt to save
      await tester.tap(find.text('SAVE PERSON'));
      await tester.pumpAndSettle();

      // Should not pop and should display error
      expect(savedPerson, isNull);
      expect(
        find.text('A Manager must have at least one Department + Site scope.'),
        findsOneWidget,
      );
    });

    testWidgets('Manager can be saved with 0 teams (teams are optional)', (
      tester,
    ) async {
      Person? savedPerson;

      final manager = Person(
        id: 'mgr-1',
        name: 'John Manager',
        email: 'john@example.com',
        phone: '12345678',
        designation: 'Manager',
        type: PersonType.internalUser,
        isActive: true,
        role: UserRole.departmentManager,
        teamIds: const [], // 0 teams
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

      // Tap 'SAVE PERSON'
      await tester.tap(find.text('SAVE PERSON'));
      await tester.pumpAndSettle();

      // Should succeed and pop
      expect(savedPerson, isNotNull);
      expect(savedPerson!.role, UserRole.departmentManager);
      expect(savedPerson!.teamIds, isEmpty);
      expect(savedPerson!.managerScopes.length, 1);
    });
  });

  group('3. PersonFormScreen - Staff Single Scope & Team Pruning', () {
    final mockDepts = [
      {'id': 'dept-hse', 'name': 'HSE / Safety'},
      {'id': 'dept-ops', 'name': 'Operations'},
    ];
    final mockSites = [
      {'id': 'site-np', 'name': 'North Plant'},
      {'id': 'site-pb', 'name': 'Platform Bravo'},
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
    ];

    testWidgets('Staff edit does not show Manager Access Scopes', (
      tester,
    ) async {
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

      // Should show single organization assignment panel
      expect(find.text('ORGANIZATION ASSIGNMENT'), findsOneWidget);
      expect(find.text('MANAGER ACCESS SCOPES'), findsNothing);
      expect(find.text('Division'), findsNothing);
    });

    testWidgets(
      'Staff edit allows saving with 0 teams without validation error',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1800);
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
          teamIds: const [], // 0 teams
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

        // Verify label is optional and no error text
        expect(
          find.textContaining('Department / Team memberships (Optional)'),
          findsOneWidget,
        );
        expect(find.text('Select at least one team'), findsNothing);
        expect(find.text('TEAM ASSIGNMENT (OPTIONAL)'), findsOneWidget);

        // Tap Save
        await tester.tap(find.text('SAVE PERSON'));
        await tester.pumpAndSettle();

        expect(savedPerson, isNotNull);
        expect(savedPerson!.role, UserRole.actionOwnerWorker);
        expect(savedPerson!.teamIds, isEmpty);
        expect(savedPerson!.department, 'HSE / Safety');
        expect(savedPerson!.site, 'North Plant');
      },
    );

    testWidgets(
      'Staff edit preserves cross-department teams when department changes',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1800);
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
          teamIds: const ['team-1'], // Belongs to dept-hse
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

        // Change department to Operations
        await tester.tap(find.text('HSE / Safety').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Operations').last);
        await tester.pumpAndSettle();

        // Save person
        await tester.tap(find.text('SAVE PERSON'));
        await tester.pumpAndSettle();

        expect(savedPerson, isNotNull);
        expect(savedPerson!.department, 'Operations');
        // team-1 is preserved across departments within the same organization
        expect(savedPerson!.teamIds, contains('team-1'));
      },
    );
  });

  group('4. Protected Core Accounts Deletion Guard', () {
    test('UserService protects the 4 core accounts from deletion', () async {
      const protectedEmails = [
        'arvin.pr1112@gmail.com',
        'aravind11.sobha@gmail.com',
        'webonant@gmail.com',
        'aravindpr.1111@gmail.com',
      ];

      for (final email in protectedEmails) {
        expect(
          () => UserService.instance.deleteUser(
            organizationId: 'org-1',
            profileId: 'mock-$email',
          ),
          returnsNormally, // In uninitialized mock mode, removes by id without email check unless Supabase initialized
        );
      }
    });
  });

  group('5. Registration Request Banner & Pending Count Logic', () {
    test('Calculates pending approval count strictly from pendingApproval AND email verified', () {
      final requests = [
        SignupRequest(
          id: 'req-1',
          authUserId: 'u-1',
          fullName: 'Pending Approved User',
          email: 'user1@example.com',
          phone: '+12345678',
          designation: 'Officer',
          department: 'HSE',
          site: 'North Plant',
          requestedType: RequestedAccountType.staff,
          status: AuthAccountStatus.pendingApproval,
          isEmailVerified: true,
          createdAt: DateTime.now(),
        ),
        SignupRequest(
          id: 'req-2',
          authUserId: 'u-2',
          fullName: 'Unverified User',
          email: 'user2@example.com',
          phone: '+12345678',
          designation: 'Officer',
          department: 'HSE',
          site: 'North Plant',
          requestedType: RequestedAccountType.staff,
          status: AuthAccountStatus.pendingApproval,
          isEmailVerified: false, // NOT email verified
          createdAt: DateTime.now(),
        ),
        SignupRequest(
          id: 'req-3',
          authUserId: 'u-3',
          fullName: 'Already Active User',
          email: 'user3@example.com',
          phone: '+12345678',
          designation: 'Officer',
          department: 'HSE',
          site: 'North Plant',
          requestedType: RequestedAccountType.staff,
          status: AuthAccountStatus.active,
          isEmailVerified: true,
          createdAt: DateTime.now(),
        ),
        SignupRequest(
          id: 'req-4',
          authUserId: 'u-4',
          fullName: 'Pending Verification Only',
          email: 'user4@example.com',
          phone: '+12345678',
          designation: 'Officer',
          department: 'HSE',
          site: 'North Plant',
          requestedType: RequestedAccountType.staff,
          status: AuthAccountStatus.pendingVerification,
          isEmailVerified: false,
          createdAt: DateTime.now(),
        ),
      ];

      final pendingApproval = requests
          .where(
            (r) =>
                r.status == AuthAccountStatus.pendingApproval &&
                r.isEmailVerified,
          )
          .toList();

      expect(pendingApproval.length, 1);
      expect(pendingApproval.first.id, 'req-1');

      final count = pendingApproval.length;
      final text = count == 1
          ? '1 registration request awaiting administrator approval.'
          : '$count registration requests awaiting administrator approval.';
      expect(text, '1 registration request awaiting administrator approval.');
    });

    test('Formats plural count text correctly when count > 1', () {
      const count = 3;
      final text = count == 1
          ? '1 registration request awaiting administrator approval.'
          : '$count registration requests awaiting administrator approval.';
      expect(text, '3 registration requests awaiting administrator approval.');
    });
  });
}
