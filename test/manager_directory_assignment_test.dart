import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/add_action_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/models/team.dart';
import 'package:action_flow/features/users/screens/users_screen.dart';
import 'package:action_flow/services/user_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MockUserServiceForManager extends UserService {
  MockUserServiceForManager({
    this.mockDirectoryPeople,
    this.shouldThrow = false,
  });

  final List<Person>? mockDirectoryPeople;
  final bool shouldThrow;

  @override
  Future<List<Person>> fetchManagerDirectory({
    required ManagerContext managerContext,
  }) async {
    if (shouldThrow) {
      throw Exception('Simulated network error fetching staff directory');
    }
    return mockDirectoryPeople ?? [];
  }
}

void main() {
  const orgId = '00000000-0000-0000-0000-000000000001';
  const managerId = '878d9145-7764-411f-8d26-f30f01e99e79';
  const dept1Id = 'd1111111-1111-1111-1111-111111111111';
  const dept2Id = 'd2222222-2222-2222-2222-222222222222';
  const site1Id = 's1111111-1111-1111-1111-111111111111';
  const site2Id = 's2222222-2222-2222-2222-222222222222';

  final testManagerContext = ManagerContext(
    authUserId: managerId,
    organizationId: orgId,
    organizationName: 'Sobha Constructions',
    profile: const UserProfile(
      id: managerId,
      name: 'Webonant Manager',
      email: 'webonant@gmail.com',
      phone: '+971501112233',
      designation: 'HSE Manager',
      department: 'HSE',
      site: 'Tower A',
      role: 'manager',
    ),
    scopes: const [
      ManagerScopeItem(
        departmentId: dept1Id,
        departmentName: 'HSE',
        siteId: site1Id,
        siteName: 'Tower A',
      ),
      ManagerScopeItem(
        departmentId: dept2Id,
        departmentName: 'Civil Engineering',
        siteId: site2Id,
        siteName: 'Plant North',
      ),
    ],
  );

  final sampleStaff = [
    Person(
      id: 'u1111111-0000-0000-0000-000000000001',
      name: 'Ahmed Hassan',
      email: 'ahmed.hassan@sobha.com',
      phone: '+971501234567',
      designation: 'Safety Officer',
      type: PersonType.internalUser,
      isActive: true,
      role: UserRole.actionOwnerWorker,
      department: 'HSE',
      departmentId: dept1Id,
      site: 'Tower A',
      siteId: site1Id,
      teamNames: const ['Emergency Response Team', 'Fire Safety'],
      organizationId: orgId,
    ),
    Person(
      id: 'u2222222-0000-0000-0000-000000000002',
      name: 'Elena Rostova',
      email: 'elena.rostova@sobha.com',
      phone: '+971509876543',
      designation: 'Site Engineer',
      type: PersonType.internalUser,
      isActive: true,
      role: UserRole.actionOwnerWorker,
      department: 'Civil Engineering',
      departmentId: dept2Id,
      site: 'Plant North',
      siteId: site2Id,
      teamNames: const ['Structural QA'],
      organizationId: orgId,
    ),
    Person(
      id: 'u3333333-0000-0000-0000-000000000003',
      name: 'Vikram Singh',
      email: 'vikram.singh@sobha.com',
      phone: '+971504567890',
      designation: 'Junior Safety Inspector',
      type: PersonType.internalUser,
      isActive: false, // Inactive user for testing Status filter
      role: UserRole.actionOwnerWorker,
      department: 'HSE',
      departmentId: dept1Id,
      site: 'Tower A',
      siteId: site1Id,
      teamNames: const ['Inspection Squad'],
      organizationId: orgId,
    ),
  ];

  group('Manager Users / Staff Directory - Scoped UI & Security Tests', () {
    testWidgets(
      'UsersScreen with ManagerContext renders real scoped staff and hides Add Person',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final mockService = MockUserServiceForManager(
          mockDirectoryPeople: sampleStaff,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: UsersScreen(
              managerContext: testManagerContext,
              userService: mockService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Verify title and scoped count
        expect(find.text('People / Staff Directory'), findsOneWidget);
        expect(
          find.text('3 staff members available within your permitted scopes'),
          findsOneWidget,
        );

        // 2. Add Person button MUST NOT be present in manager mode
        expect(find.text('Add Person'), findsNothing);

        // 3. Verify real users from Supabase/service are rendered
        expect(find.text('Ahmed Hassan'), findsOneWidget);
        expect(find.text('Elena Rostova'), findsOneWidget);
        expect(find.text('Vikram Singh'), findsOneWidget);

        // 4. Verify teams are rendered from real data
        expect(find.textContaining('Emergency Response Team'), findsOneWidget);
        expect(find.textContaining('Structural QA'), findsOneWidget);

        // 5. Verify department filter options are constrained to Manager's scopes
        await tester.tap(find.text('All Departments'));
        await tester.pumpAndSettle();
        expect(find.text('HSE'), findsWidgets);
        expect(find.text('Civil Engineering'), findsWidgets);
        // An unrelated department must NOT be listed
        expect(find.text('Human Resources'), findsNothing);
      },
    );

    testWidgets(
      'UsersScreen filters staff by Manager Scope Department and Site',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final mockService = MockUserServiceForManager(
          mockDirectoryPeople: sampleStaff,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: UsersScreen(
              managerContext: testManagerContext,
              userService: mockService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Filter by Department: Civil Engineering
        await tester.tap(find.text('All Departments'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Civil Engineering').last);
        await tester.pumpAndSettle();

        // Elena is Civil Engineering, Ahmed & Vikram are HSE
        expect(find.text('Elena Rostova'), findsOneWidget);
        expect(find.text('Ahmed Hassan'), findsNothing);
        expect(find.text('Vikram Singh'), findsNothing);

        // Filter by Site under Civil Engineering: Plant North
        expect(find.text('All Sites'), findsOneWidget);
        await tester.tap(find.text('All Sites'));
        await tester.pumpAndSettle();
        expect(find.text('Plant North'), findsWidgets);
      },
    );

    testWidgets('UsersScreen filters staff by Status (Active vs Inactive)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockService = MockUserServiceForManager(
        mockDirectoryPeople: sampleStaff,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: UsersScreen(
            managerContext: testManagerContext,
            userService: mockService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially All Statuses shows all 3
      expect(find.text('Ahmed Hassan'), findsOneWidget);
      expect(find.text('Vikram Singh'), findsOneWidget);

      // Filter by Inactive
      await tester.tap(find.text('All Statuses'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactive').last);
      await tester.pumpAndSettle();

      // Only Vikram Singh is inactive
      expect(find.text('Vikram Singh'), findsOneWidget);
      expect(find.text('Ahmed Hassan'), findsNothing);
      expect(find.text('Elena Rostova'), findsNothing);

      // Filter by Active
      await tester.tap(find.text('Inactive').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Active').last);
      await tester.pumpAndSettle();

      expect(find.text('Ahmed Hassan'), findsOneWidget);
      expect(find.text('Elena Rostova'), findsOneWidget);
      expect(find.text('Vikram Singh'), findsNothing);
    });

    testWidgets(
      'UsersScreen search finds staff by partial name, email, or designation',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final mockService = MockUserServiceForManager(
          mockDirectoryPeople: sampleStaff,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: UsersScreen(
              managerContext: testManagerContext,
              userService: mockService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Search by designation "Site Engineer"
        await tester.enterText(find.byType(TextField), 'Site Engineer');
        await tester.pumpAndSettle();

        expect(find.text('Elena Rostova'), findsOneWidget);
        expect(find.text('Ahmed Hassan'), findsNothing);
        expect(find.text('Vikram Singh'), findsNothing);

        // Search by email "ahmed"
        await tester.enterText(find.byType(TextField), 'ahmed');
        await tester.pumpAndSettle();

        expect(find.text('Ahmed Hassan'), findsOneWidget);
        expect(find.text('Elena Rostova'), findsNothing);
      },
    );

    testWidgets(
      'UsersScreen tapping a person opens Read-Only Staff Profile with UUID & authorization note',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final mockService = MockUserServiceForManager(
          mockDirectoryPeople: sampleStaff,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: UsersScreen(
              managerContext: testManagerContext,
              userService: mockService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap Ahmed Hassan's row
        await tester.tap(find.text('Ahmed Hassan'));
        await tester.pumpAndSettle();

        // Verify bottom sheet modal renders
        expect(find.text('Managed Staff Profile'), findsOneWidget);
        expect(find.text('Stable UUID'), findsOneWidget);
        expect(
          find.text('u1111111-0000-0000-0000-000000000001'),
          findsOneWidget,
        );
        expect(find.text('ahmed.hassan@sobha.com'), findsWidgets);
        expect(
          find.text('Emergency Response Team, Fire Safety'),
          findsOneWidget,
        );
        expect(
          find.text(
            'User authorization, roles, and manager scopes are managed by Company Admin.',
          ),
          findsOneWidget,
        );

        // Edit Person button must NOT exist in read-only manager view
        expect(find.text('Edit Person'), findsNothing);
      },
    );

    testWidgets('UsersScreen handles error state with retry button', (
      tester,
    ) async {
      final mockService = MockUserServiceForManager(shouldThrow: true);

      await tester.pumpWidget(
        MaterialApp(
          home: UsersScreen(
            managerContext: testManagerContext,
            userService: mockService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Failed to load directory'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('Add Action - Secure Staff Assignment & Team Selection', () {
    testWidgets(
      'AddActionScreen in Manager mode loads scope-based assignees and hides fake person generator',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AddActionScreen(
                actionId: 'ACT-TEST-1001',
                managerContext: testManagerContext,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Verify "Add New Internal Person" button is HIDDEN in manager flow
        expect(find.text('Add New Internal Person'), findsNothing);

        // 2. Verify Team dropdown is present in Section 2
        expect(find.text('Team (Optional)'), findsWidgets);
        expect(find.text('No Team'), findsWidgets);
      },
    );

    test('ActionRecord serialization includes real UUIDs for assigned_to and team_id', () {
      final record = ActionRecord(
        id: 'ACT-2001',
        organizationId: orgId,
        departmentId: dept1Id,
        siteId: site1Id,
        teamId: 't1111111-1111-1111-1111-111111111111',
        assignedToId: 'u1111111-0000-0000-0000-000000000001',
        subject: 'Fix scaffolding handrails',
        actionRequired: 'Inspect and secure all loose couplings',
        division: 'Operations',
        assignedTo: 'Ahmed Hassan',
      );

      final insertMap = record.toSupabaseInsertMap();

      expect(insertMap['organization_id'], orgId);
      expect(insertMap['department_id'], dept1Id);
      expect(insertMap['site_id'], site1Id);
      expect(insertMap['team_id'], 't1111111-1111-1111-1111-111111111111');
      expect(insertMap['assigned_to'], 'u1111111-0000-0000-0000-000000000001');
      expect(insertMap['title'], 'Fix scaffolding handrails');
    });
  });
}
