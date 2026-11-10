import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:action_flow/features/auth/models/manager_scope_item.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/models/team.dart';
import 'package:action_flow/features/users/screens/person_form_screen.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('Admin Portal Staff Single-Scope & Manager Multi-Scope UI Workflow Test', () {
    const dept1Id = 'ed815d33-eb6f-4a9b-bc52-798c1c6937a2'; // Maintenance
    const site1Id = '6abf4ba5-e8b7-4076-8c97-80f4a354f94b'; // test site
    const dept2Id = 'd348a7f3-faa2-44d4-a200-9adc8966b730'; // Operations
    const site2Id = '5dc40141-6f5f-41be-b090-298b84e23865'; // Platform Bravo

    final availableDepts = [
      {'id': dept1Id, 'name': 'Maintenance', 'is_active': true},
      {'id': dept2Id, 'name': 'Operations', 'is_active': true},
    ];
    final availableSites = [
      {'id': site1Id, 'name': 'test site', 'is_active': true},
      {'id': site2Id, 'name': 'Platform Bravo', 'is_active': true},
    ];

    testWidgets(
      'Staff member in PersonFormScreen enforces single primary Organization Assignment (no multi-scope)',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final maintStaff = Person(
          id: 'staff-222',
          name: 'Maint Staff',
          email: 'maint_staff@test.local',
          phone: '+1234567890',
          designation: 'Maintenance Worker',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.actionOwnerWorker,
          department: 'Maintenance',
          departmentId: dept1Id,
          site: 'test site',
          siteId: site1Id,
        );

        Person? savedPerson;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                key: const ValueKey('open_edit_btn'),
                onPressed: () async {
                  savedPerson = await Navigator.of(context).push<Person>(
                    MaterialPageRoute(
                      builder: (_) => PersonFormScreen(
                        person: maintStaff,
                        availableDepartments: availableDepts,
                        availableSites: availableSites,
                      ),
                    ),
                  );
                },
                child: const Text('Open Edit'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('open_edit_btn')));
        await tester.pumpAndSettle();

        // Verify Staff single scope UI: Shows ORGANIZATION ASSIGNMENT, does NOT show MANAGER ACCESS SCOPES
        expect(find.text('ORGANIZATION ASSIGNMENT'), findsOneWidget);
        expect(find.text('MANAGER ACCESS SCOPES'), findsNothing);
        expect(find.text('Maintenance'), findsWidgets);
        expect(find.text('test site'), findsWidgets);

        // Save
        await tester.tap(find.text('SAVE PERSON'));
        await tester.pumpAndSettle();

        expect(savedPerson, isNotNull);
        expect(savedPerson!.role, equals(UserRole.actionOwnerWorker));
        expect(savedPerson!.departmentId, equals(dept1Id));
        expect(savedPerson!.siteId, equals(site1Id));
      },
    );

    testWidgets(
      'Manager member in PersonFormScreen renders Manager Access Scopes and retains scopes',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final manager = Person(
          id: 'mgr-878',
          name: 'Operations Manager',
          email: 'webonant@gmail.com',
          phone: '+1234567890',
          designation: 'Operations Manager',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.departmentManager,
          department: 'Operations',
          departmentId: dept2Id,
          site: 'Platform Bravo',
          siteId: site2Id,
          managerScopes: const [
            ManagerScopeItem(
              departmentId: dept2Id,
              departmentName: 'Operations',
              siteId: site2Id,
              siteName: 'Platform Bravo',
            ),
          ],
        );

        Person? savedPerson;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                key: const ValueKey('open_edit_mgr_btn'),
                onPressed: () async {
                  savedPerson = await Navigator.of(context).push<Person>(
                    MaterialPageRoute(
                      builder: (_) => PersonFormScreen(
                        person: manager,
                        availableDepartments: availableDepts,
                        availableSites: availableSites,
                      ),
                    ),
                  );
                },
                child: const Text('Open Edit Manager'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('open_edit_mgr_btn')));
        await tester.pumpAndSettle();

        // Verify Manager Access Scopes panel appears
        expect(find.text('MANAGER ACCESS SCOPES'), findsOneWidget);
        expect(find.text('Operations'), findsWidgets);
        expect(find.text('Platform Bravo'), findsWidgets);

        // Save
        await tester.tap(find.text('SAVE PERSON'));
        await tester.pumpAndSettle();

        expect(savedPerson, isNotNull);
        expect(savedPerson!.role, equals(UserRole.departmentManager));
        expect(savedPerson!.managerScopes.length, equals(1));
        expect(savedPerson!.managerScopes.first.departmentId, equals(dept2Id));
      },
    );
  });
}
