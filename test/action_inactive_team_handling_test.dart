import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/add_action_screen.dart';
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
// MOCKS FOR INACTIVE TEAM HANDLING TESTS
// ============================================================================

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
  Future<List<Map<String, dynamic>>> fetchDepartments(String organizationId) async {
    return departments;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchSites(String organizationId) async {
    return sites;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTeams(String organizationId) async {
    return teams;
  }
}

class MockDivisionService extends DivisionService {
  final List<Division> divisions;
  MockDivisionService({required this.divisions});

  @override
  Future<List<Division>> fetchDivisions(String organizationId, {bool onlyActive = false}) async {
    return divisions;
  }
}

class MockSectionService extends ActionSectionService {
  final List<ActionSection> sections;
  MockSectionService({required this.sections});

  @override
  Future<List<ActionSection>> fetchSections(String organizationId, {bool onlyActive = false}) async {
    return sections;
  }
}

class MockUserService extends UserService {
  final List<Person> users;
  MockUserService({required this.users});

  @override
  Future<List<Person>> fetchUsers(String organizationId, {bool allowMockFallback = true}) async {
    return users;
  }
}

void main() {
  const testOrgId = '00000000-0000-0000-0000-000000000001';
  const deptSafetyId = 'dept-safety-001';
  const deptCivilId = 'dept-civil-002';
  const siteAlphaId = 'site-alpha-001';

  const activeTeamId = 'team-active-001';
  const inactiveTeamId = 'team-inactive-002';

  late MockStructureService structureService;
  late MockDivisionService divisionService;
  late MockSectionService sectionService;
  late MockUserService userService;

  setUp(() {
    structureService = MockStructureService(
      departments: [
        {'id': deptSafetyId, 'name': 'Safety & HSE', 'status': 'Active', 'is_active': true},
        {'id': deptCivilId, 'name': 'Civil Engineering', 'status': 'Active', 'is_active': true},
      ],
      sites: [
        {'id': siteAlphaId, 'name': 'Tower Site Alpha', 'status': 'Active', 'is_active': true},
      ],
      teams: [
        {
          'id': activeTeamId,
          'name': 'Scaffolding Safety Squad',
          'department_id': deptSafetyId,
          'deptId': deptSafetyId,
          'status': 'Active',
          'is_active': true,
        },
        {
          'id': inactiveTeamId,
          'name': 'Legacy Rigging Unit',
          'department_id': deptSafetyId,
          'deptId': deptSafetyId,
          'status': 'Inactive',
          'is_active': false,
        },
      ],
    );

    final now = DateTime.now();
    divisionService = MockDivisionService(divisions: [
      Division(
        id: 'div-001',
        organizationId: testOrgId,
        name: 'Operations',
        code: 'OPS',
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ),
    ]);

    sectionService = MockSectionService(sections: [
      ActionSection(
        id: 'sec-001',
        organizationId: testOrgId,
        name: 'Audit Finding',
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ),
    ]);

    userService = MockUserService(users: [
      Person(
        id: 'user-001',
        name: 'John Inspector',
        email: 'john@sobha.com',
        phone: '+971 50 123 4567',
        designation: 'Safety Inspector',
        department: 'Safety & HSE',
        site: 'Tower Site Alpha',
        type: PersonType.internalUser,
        isActive: true,
      ),
    ]);
  });

  Widget buildTestableScreen({
    ActionRecord? existingAction,
    ValueChanged<ActionRecord>? onSaved,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: AddActionScreen(
          actionId: existingAction?.id ?? 'ACT-TEST-NEW',
          organizationId: testOrgId,
          existingAction: existingAction,
          companyStructureService: structureService,
          divisionService: divisionService,
          actionSectionService: sectionService,
          userService: userService,
          onSaved: onSaved,
        ),
      ),
    );
  }

  group('Inactive Team Handling: UI & Dropdown Verification', () {
    testWidgets('1. New action does NOT offer inactive teams for selection', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildTestableScreen());
      await tester.pumpAndSettle();

      // Inactive team 'Legacy Rigging Unit' must NOT appear in the available choices
      expect(find.text('Legacy Rigging Unit'), findsNothing);
      expect(find.text('Legacy Rigging Unit (Inactive)'), findsNothing);
    });

    testWidgets('2. Existing action with inactive team displays name with (Inactive) label', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final existingWithInactiveTeam = ActionRecord(
        id: 'ACT-HISTORICAL-01',
        actionNumber: 'ACT-HISTORICAL-01',
        organizationId: testOrgId,
        departmentId: deptSafetyId,
        department: 'Safety & HSE',
        siteId: siteAlphaId,
        site: 'Tower Site Alpha',
        teamId: inactiveTeamId,
        subject: 'Historical Scaffold Inspection',
        actionRequired: 'Inspect legacy anchors',
        status: 'Open',
        priority: 'High',
        assignedTo: 'John Inspector',
        assignedToId: 'user-001',
        division: 'Operations',
      );

      await tester.pumpWidget(buildTestableScreen(existingAction: existingWithInactiveTeam));
      await tester.pumpAndSettle();

      // UI must visibly show the team name with '(Inactive)' tag, NOT 'None'
      expect(find.text('Legacy Rigging Unit (Inactive)'), findsWidgets);
    });

    testWidgets('3. Unrelated edit (e.g. description/priority) preserves existing inactive teamId', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final existingWithInactiveTeam = ActionRecord(
        id: 'ACT-HISTORICAL-02',
        actionNumber: 'ACT-HISTORICAL-02',
        organizationId: testOrgId,
        departmentId: deptSafetyId,
        department: 'Safety & HSE',
        siteId: siteAlphaId,
        site: 'Tower Site Alpha',
        teamId: inactiveTeamId,
        subject: 'Anchor Point Testing',
        actionRequired: 'Original required text',
        description: 'Original description',
        status: 'Open',
        priority: 'Medium',
        assignedTo: 'John Inspector',
        assignedToId: 'user-001',
        division: 'Operations',
      );

      ActionRecord? savedResult;
      await tester.pumpWidget(buildTestableScreen(
        existingAction: existingWithInactiveTeam,
        onSaved: (saved) => savedResult = saved,
      ));
      await tester.pumpAndSettle();

      // Modify only description (unrelated edit)
      final descField = find.widgetWithText(TextFormField, 'Enter action details here...');
      if (descField.evaluate().isNotEmpty) {
        await tester.enterText(descField, 'Updated description text for audit');
      }

      // Tap Save button
      final saveBtn = find.text('Save Changes').evaluate().isNotEmpty
          ? find.text('Save Changes').first
          : find.text('SAVE CHANGES').first;
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(savedResult, isNotNull);
      // Historical teamId must be strictly preserved
      expect(savedResult!.teamId, equals(inactiveTeamId));
    });

    testWidgets('4. Explicitly choosing None clears the inactive team assignment', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final existingWithInactiveTeam = ActionRecord(
        id: 'ACT-HISTORICAL-03',
        actionNumber: 'ACT-HISTORICAL-03',
        organizationId: testOrgId,
        departmentId: deptSafetyId,
        department: 'Safety & HSE',
        siteId: siteAlphaId,
        site: 'Tower Site Alpha',
        teamId: inactiveTeamId,
        subject: 'Scaffolding Audit',
        actionRequired: 'Audit scaffolding',
        status: 'Open',
        priority: 'Medium',
        assignedTo: 'John Inspector',
        assignedToId: 'user-001',
        division: 'Operations',
      );

      ActionRecord? savedResult;
      await tester.pumpWidget(buildTestableScreen(
        existingAction: existingWithInactiveTeam,
        onSaved: (saved) => savedResult = saved,
      ));
      await tester.pumpAndSettle();

      // Open Teams dropdown
      final teamDropdown = find.text('Legacy Rigging Unit (Inactive)');
      expect(teamDropdown, findsWidgets);
      await tester.tap(teamDropdown.first);
      await tester.pumpAndSettle();

      // Select 'None'
      final noneOption = find.text('None').last;
      await tester.tap(noneOption);
      await tester.pumpAndSettle();

      // Save
      final saveBtn = find.text('Save Changes').evaluate().isNotEmpty
          ? find.text('Save Changes').first
          : find.text('SAVE CHANGES').first;
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(savedResult, isNotNull);
      expect(savedResult!.teamId, isNull);
    });

    testWidgets('5. Changing Department to an incompatible department resets the inactive team', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final existingWithInactiveTeam = ActionRecord(
        id: 'ACT-HISTORICAL-04',
        actionNumber: 'ACT-HISTORICAL-04',
        organizationId: testOrgId,
        departmentId: deptSafetyId,
        department: 'Safety & HSE',
        siteId: siteAlphaId,
        site: 'Tower Site Alpha',
        teamId: inactiveTeamId,
        subject: 'Structural Beam Inspection',
        actionRequired: 'Check beam integrity',
        status: 'Open',
        priority: 'Medium',
        assignedTo: 'John Inspector',
        assignedToId: 'user-001',
        division: 'Operations',
      );

      ActionRecord? savedResult;
      await tester.pumpWidget(buildTestableScreen(
        existingAction: existingWithInactiveTeam,
        onSaved: (saved) => savedResult = saved,
      ));
      await tester.pumpAndSettle();

      // Change department from 'Safety & HSE' to 'Civil Engineering'
      final deptDropdown = find.text('Safety & HSE');
      await tester.tap(deptDropdown.first);
      await tester.pumpAndSettle();

      final civilOption = find.text('Civil Engineering').last;
      await tester.tap(civilOption);
      await tester.pumpAndSettle();

      // Save
      final saveBtn = find.text('Save Changes').evaluate().isNotEmpty
          ? find.text('Save Changes').first
          : find.text('SAVE CHANGES').first;
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(savedResult, isNotNull);
      expect(savedResult!.departmentId, equals(deptCivilId));
      // Incompatible team from Safety & HSE must be safely cleared, not submitted
      expect(savedResult!.teamId, isNull);
    });
  });

  group('Database Trigger Rule Simulation: validate_action_before_write', () {
    // Exact simulation of public.validate_action_before_write() logic
    String? simulateValidateActionBeforeWrite({
      required String operation, // 'INSERT' or 'UPDATE'
      required String actionOrgId,
      required String actionDeptId,
      required String? newTeamId,
      required String? oldTeamId,
      required Map<String, dynamic>? teamRecord,
    }) {
      if (newTeamId != null) {
        if (teamRecord == null) {
          return 'ActionFlow Validation Error: Team not found.';
        }
        final teamOrg = teamRecord['organization_id'];
        final teamDept = teamRecord['department_id'];
        final isTeamActive = teamRecord['is_active'] == true;

        if (teamOrg != actionOrgId) {
          return 'ActionFlow Security Violation: Team does not belong to this organization.';
        }
        if (teamDept != actionDeptId) {
          return 'ActionFlow Validation Error: Team does not belong to the selected department.';
        }

        if (operation == 'INSERT') {
          if (!isTeamActive) {
            return 'ActionFlow Validation Error: Cannot associate new action with an inactive team.';
          }
        } else if (operation == 'UPDATE' && newTeamId != oldTeamId) {
          if (!isTeamActive) {
            return 'ActionFlow Validation Error: Cannot associate action with an inactive team.';
          }
        }
      }
      return null; // Valid
    }

    test('6. INSERT with inactive team is strictly rejected', () {
      final inactiveTeam = {
        'id': inactiveTeamId,
        'organization_id': testOrgId,
        'department_id': deptSafetyId,
        'is_active': false,
      };

      final error = simulateValidateActionBeforeWrite(
        operation: 'INSERT',
        actionOrgId: testOrgId,
        actionDeptId: deptSafetyId,
        newTeamId: inactiveTeamId,
        oldTeamId: null,
        teamRecord: inactiveTeam,
      );

      expect(error, equals('ActionFlow Validation Error: Cannot associate new action with an inactive team.'));
    });

    test('7. UPDATE changing team_id to an inactive team is strictly rejected', () {
      final inactiveTeam = {
        'id': inactiveTeamId,
        'organization_id': testOrgId,
        'department_id': deptSafetyId,
        'is_active': false,
      };

      final error = simulateValidateActionBeforeWrite(
        operation: 'UPDATE',
        actionOrgId: testOrgId,
        actionDeptId: deptSafetyId,
        newTeamId: inactiveTeamId,
        oldTeamId: activeTeamId, // Changed from active team to inactive team
        teamRecord: inactiveTeam,
      );

      expect(error, equals('ActionFlow Validation Error: Cannot associate action with an inactive team.'));
    });

    test('8. UPDATE retaining existing inactive team during unrelated edit succeeds', () {
      final inactiveTeam = {
        'id': inactiveTeamId,
        'organization_id': testOrgId,
        'department_id': deptSafetyId,
        'is_active': false,
      };

      final error = simulateValidateActionBeforeWrite(
        operation: 'UPDATE',
        actionOrgId: testOrgId,
        actionDeptId: deptSafetyId,
        newTeamId: inactiveTeamId,
        oldTeamId: inactiveTeamId, // Unchanged!
        teamRecord: inactiveTeam,
      );

      expect(error, isNull); // Allowed!
    });

    test('9. UPDATE with department mismatch is rejected even if team was unchanged', () {
      final inactiveTeam = {
        'id': inactiveTeamId,
        'organization_id': testOrgId,
        'department_id': deptSafetyId, // Belongs to Safety
        'is_active': false,
      };

      final error = simulateValidateActionBeforeWrite(
        operation: 'UPDATE',
        actionOrgId: testOrgId,
        actionDeptId: deptCivilId, // Changed to Civil
        newTeamId: inactiveTeamId,
        oldTeamId: inactiveTeamId,
        teamRecord: inactiveTeam,
      );

      expect(error, equals('ActionFlow Validation Error: Team does not belong to the selected department.'));
    });

    test('10. UPDATE with cross-tenant organization mismatch is rejected', () {
      const foreignOrgId = 'foreign-org-999';
      final foreignTeam = {
        'id': activeTeamId,
        'organization_id': foreignOrgId,
        'department_id': deptSafetyId,
        'is_active': true,
      };

      final error = simulateValidateActionBeforeWrite(
        operation: 'UPDATE',
        actionOrgId: testOrgId,
        actionDeptId: deptSafetyId,
        newTeamId: activeTeamId,
        oldTeamId: null,
        teamRecord: foreignTeam,
      );

      expect(error, equals('ActionFlow Security Violation: Team does not belong to this organization.'));
    });

    test('11. ActionRecord toSupabaseUpdateMap accurately serializes inactive team_id', () {
      final actionWithInactiveTeam = ActionRecord(
        id: 'ACT-MAP-01',
        actionNumber: 'ACT-MAP-01',
        organizationId: testOrgId,
        departmentId: deptSafetyId,
        siteId: siteAlphaId,
        teamId: inactiveTeamId,
        subject: 'Serialization Test',
        actionRequired: 'Verify update map serialization',
        status: 'Open',
        priority: 'High',
        assignedTo: 'John Inspector',
        division: 'Operations',
      );

      final updateMap = actionWithInactiveTeam.toSupabaseUpdateMap();
      expect(updateMap['team_id'], equals(inactiveTeamId));
    });

    test('12. Removing an attachment on an action with an inactive team preserves teamId', () async {
      final action = ActionRecord(
        id: 'ACT-ATT-INACTIVE-01',
        actionNumber: 'ACT-ATT-INACTIVE-01',
        organizationId: testOrgId,
        departmentId: deptSafetyId,
        siteId: siteAlphaId,
        teamId: inactiveTeamId,
        subject: 'Attachment with Inactive Team',
        actionRequired: 'Verify attachment operations with inactive team',
        status: 'Open',
        priority: 'High',
        assignedTo: 'John Inspector',
        division: 'Operations',
        attachments: const ['evidence_1.pdf', 'evidence_2.png'],
      );

      MockActionStore.instance.add(action);

      final result = await ActionService.instance.removeActionAttachment(
        action: action,
        fileName: 'evidence_1.pdf',
      );

      expect(result.success, isTrue);
      // In MockActionStore or returned metadata, the inactive teamId remains intact
      final storedAction = await ActionService.instance.fetchActionById('ACT-ATT-INACTIVE-01');
      expect(storedAction, isNotNull);
      expect(storedAction!.teamId, equals(inactiveTeamId));
      expect(storedAction.attachments, equals(['evidence_2.png']));
    });
  });
}
