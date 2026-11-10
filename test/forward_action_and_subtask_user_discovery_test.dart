import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/models/team.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:action_flow/models/organization.dart';

void main() {
  setUp(() {
    ActionService.instance.clientOverride = null;
  });

  group('Forward Action & Subtask User Discovery Tests', () {
    test('1. ActionPersonReference role determination correctly handles Staff with Lead/Supervisor designation', () {
      final staffSupervisor = ActionPersonReference(
        personId: '11111111-1111-1111-1111-111111111111',
        name: 'John Maintenance Supervisor',
        type: PersonType.internalUser,
        role: 'staff',
        designation: 'Maintenance Supervisor',
      );

      final staffLead = ActionPersonReference(
        personId: '22222222-2222-2222-2222-222222222222',
        name: 'Sarah Safety Lead',
        type: PersonType.internalUser,
        role: 'action_owner_worker',
        designation: 'HSE Lead Officer',
      );

      final managerPerson = ActionPersonReference(
        personId: '33333333-3333-3333-3333-333333333333',
        name: 'Dave Department Manager',
        type: PersonType.internalUser,
        role: 'manager',
        designation: 'Operations Lead',
      );

      expect(staffSupervisor.isStaff, isTrue);
      expect(staffSupervisor.isManager, isFalse);

      expect(staffLead.isStaff, isTrue);
      expect(staffLead.isManager, isFalse);

      expect(managerPerson.isManager, isTrue);
      expect(managerPerson.isStaff, isFalse);
    });

    test('2. ActionPersonReference serializes and deserializes team_ids, department_id, site_id', () {
      final ref = ActionPersonReference(
        personId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        name: 'Alice Cross Department',
        type: PersonType.internalUser,
        role: 'staff',
        designation: 'Safety Tech',
        department: 'HSE',
        site: 'North Plant',
        teamIds: ['team-cross-1', 'team-safety-2'],
        departmentId: 'dept-hse-001',
        siteId: 'site-np-001',
      );

      final json = ref.toJson();
      expect(json['team_ids'], contains('team-cross-1'));
      expect(json['department_id'], equals('dept-hse-001'));
      expect(json['site_id'], equals('site-np-001'));

      final parsed = ActionPersonReference.fromJson(json);
      expect(parsed.personId, equals('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'));
      expect(parsed.teamIds, containsAll(['team-cross-1', 'team-safety-2']));
      expect(parsed.departmentId, equals('dept-hse-001'));
      expect(parsed.siteId, equals('site-np-001'));
      expect(parsed.isStaff, isTrue);
    });

    test('3. Staff discovers colleague in same team across departments and sites', () async {
      // Setup MockPeopleStore with cross-department team members
      final mockPeople = [
        Person(
          id: '11111111-1111-1111-1111-111111111111',
          name: 'Caller Staff HSE',
          email: 'caller@sobha.local',
          phone: '+91 90000 00001',
          designation: 'HSE Technician',
          department: 'HSE',
          departmentId: 'dept-hse',
          site: 'HQ',
          siteId: 'site-hq',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.actionOwnerWorker,
          teamIds: ['team-joint-emergency'],
          organizationId: Organization.sobhaId,
        ),
        Person(
          id: '22222222-2222-2222-2222-222222222222',
          name: 'Target Staff Maintenance',
          email: 'target@sobha.local',
          phone: '+91 90000 00002',
          designation: 'Maintenance Lead Electrician',
          department: 'Maintenance',
          departmentId: 'dept-maint',
          site: 'Yard B',
          siteId: 'site-yardb',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.actionOwnerWorker,
          teamIds: ['team-joint-emergency'], // Shared team!
          organizationId: Organization.sobhaId,
        ),
        Person(
          id: '33333333-3333-3333-3333-333333333333',
          name: 'Unrelated Cross Dept Staff',
          email: 'unrelated@sobha.local',
          phone: '+91 90000 00003',
          designation: 'Civil Technician',
          department: 'Civil',
          departmentId: 'dept-civil',
          site: 'Yard B',
          siteId: 'site-yardb',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.actionOwnerWorker,
          teamIds: ['team-civil-only'], // No shared team!
          organizationId: Organization.sobhaId,
        ),
      ];

      MockPeopleStore.instance.people.clear();
      MockPeopleStore.instance.people.addAll(mockPeople);
      MockActionStore.instance.profiles.clear();

      final eligible = await ActionService.instance.fetchEligibleAssignees(
        organizationId: Organization.sobhaId,
        departmentId: 'dept-hse',
        siteId: 'site-hq',
        callerUserId: '11111111-1111-1111-1111-111111111111',
      );

      // Caller matches because department/site matches
      expect(eligible.any((p) => p.personId == '11111111-1111-1111-1111-111111111111'), isTrue);

      // Target matches because of SHARED TEAM ('team-joint-emergency'), despite being in Maintenance dept & Yard B site!
      expect(eligible.any((p) => p.personId == '22222222-2222-2222-2222-222222222222'), isTrue);

      // Unrelated staff does NOT match because they have a different department AND no shared team
      expect(eligible.any((p) => p.personId == '33333333-3333-3333-3333-333333333333'), isFalse);
    });

    test('4. Cross-organization users are strictly excluded from discovery', () async {
      final mockPeople = [
        Person(
          id: '11111111-1111-1111-1111-111111111111',
          name: 'Caller Sobha Staff',
          email: 'caller@sobha.local',
          phone: '+91 90000 00001',
          designation: 'HSE Officer',
          department: 'HSE',
          departmentId: 'dept-hse',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.actionOwnerWorker,
          teamIds: ['team-shared'],
          organizationId: Organization.sobhaId,
        ),
        Person(
          id: '99999999-9999-9999-9999-999999999999',
          name: 'Other Org Rogue User',
          email: 'rogue@other.local',
          phone: '+91 90000 00099',
          designation: 'HSE Officer',
          department: 'HSE',
          departmentId: 'dept-hse',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.actionOwnerWorker,
          teamIds: ['team-shared'],
          organizationId: '00000000-0000-0000-0000-000000000002', // Other Org!
        ),
      ];

      MockPeopleStore.instance.people.clear();
      MockPeopleStore.instance.people.addAll(mockPeople);
      MockActionStore.instance.profiles.clear();

      final eligible = await ActionService.instance.fetchEligibleAssignees(
        organizationId: Organization.sobhaId,
        departmentId: 'dept-hse',
        callerUserId: '11111111-1111-1111-1111-111111111111',
      );

      expect(eligible.any((p) => p.personId == '11111111-1111-1111-1111-111111111111'), isTrue);
      expect(eligible.any((p) => p.personId == '99999999-9999-9999-9999-999999999999'), isFalse);
    });

    test('5. Inactive users are excluded from discovery even with shared team', () async {
      final mockPeople = [
        Person(
          id: '11111111-1111-1111-1111-111111111111',
          name: 'Caller Active Staff',
          email: 'caller@sobha.local',
          phone: '+91 90000 00001',
          designation: 'HSE Officer',
          department: 'HSE',
          departmentId: 'dept-hse',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.actionOwnerWorker,
          teamIds: ['team-active'],
          organizationId: Organization.sobhaId,
        ),
        Person(
          id: '44444444-4444-4444-4444-444444444444',
          name: 'Inactive Team Colleague',
          email: 'inactive@sobha.local',
          phone: '+91 90000 00004',
          designation: 'Safety Tech',
          department: 'HSE',
          departmentId: 'dept-hse',
          type: PersonType.internalUser,
          isActive: false, // INACTIVE!
          role: UserRole.actionOwnerWorker,
          teamIds: ['team-active'],
          organizationId: Organization.sobhaId,
        ),
      ];

      MockPeopleStore.instance.people.clear();
      MockPeopleStore.instance.people.addAll(mockPeople);
      MockActionStore.instance.profiles.clear();

      final eligible = await ActionService.instance.fetchEligibleAssignees(
        organizationId: Organization.sobhaId,
        departmentId: 'dept-hse',
        callerUserId: '11111111-1111-1111-1111-111111111111',
      );

      expect(eligible.any((p) => p.personId == '44444444-4444-4444-4444-444444444444'), isFalse);
    });

    test('6. Action Team matching allows team members to discover action assignees', () async {
      final mockPeople = [
        Person(
          id: '55555555-5555-5555-5555-555555555555',
          name: 'Action Team Member',
          email: 'actmember@sobha.local',
          phone: '+91 90000 00005',
          designation: 'Field Worker',
          department: 'Operations',
          departmentId: 'dept-ops',
          site: 'Yard A',
          siteId: 'site-a',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.actionOwnerWorker,
          teamIds: ['team-action-assigned'],
          organizationId: Organization.sobhaId,
        ),
      ];

      MockPeopleStore.instance.people.clear();
      MockPeopleStore.instance.people.addAll(mockPeople);
      MockActionStore.instance.profiles.clear();

      // Action has different department 'dept-hse', but matches actionTeamId: 'team-action-assigned'
      final eligible = await ActionService.instance.fetchEligibleAssignees(
        organizationId: Organization.sobhaId,
        departmentId: 'dept-hse',
        actionTeamId: 'team-action-assigned',
      );

      expect(eligible.any((p) => p.personId == '55555555-5555-5555-5555-555555555555'), isTrue);
    });

    test('7. Forward Action contributor addition preserves original owner', () async {
      final originalAction = ActionRecord(
        id: 'ACT-TEST-001',
        actionNumber: 'ACT-TEST-001',
        subject: 'Safety Inspection Tower 4',
        actionRequired: 'Inspect clips',
        division: 'Construction',
        organizationId: Organization.sobhaId,
        assignedTo: 'Primary Owner Worker',
        assignedToId: '11111111-1111-1111-1111-111111111111',
        assignedBy: 'Manager Bob',
        status: 'In Progress',
        priority: 'High',
        category: 'Safety',
        department: 'HSE',
        departmentId: 'dept-hse',
        site: 'Tower 4',
        dateRaised: '07 Nov 2026',
        targetDate: '14 Nov 2026',
      );

      MockActionStore.instance.actions.clear();
      MockActionStore.instance.add(originalAction);

      MockPeopleStore.instance.people.clear();
      MockPeopleStore.instance.people.add(
        Person(
          id: '22222222-2222-2222-2222-222222222222',
          name: 'Colleague Contributor',
          email: 'contrib@sobha.local',
          phone: '+91 90000 00002',
          designation: 'Tech',
          department: 'Maintenance',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.actionOwnerWorker,
        ),
      );

      final res = await ActionService.instance.addContributor(
        actionId: originalAction.id,
        contributorProfileId: '22222222-2222-2222-2222-222222222222',
        addedBy: '11111111-1111-1111-1111-111111111111',
        addedByName: 'Primary Owner Worker',
        notes: 'Assisting on site inspection',
      );

      expect(res.success, isTrue);

      final reloaded = MockActionStore.instance.actions.firstWhere((a) => a.id == originalAction.id);

      // Primary owner MUST remain untouched!
      expect(reloaded.assignedTo, equals('Primary Owner Worker'));
      expect(reloaded.assignedToId, equals('11111111-1111-1111-1111-111111111111'));

      // Contributor must be attached!
      expect(reloaded.contributors.length, equals(1));
      expect(reloaded.contributors.first.profileId, equals('22222222-2222-2222-2222-222222222222'));
      expect(reloaded.contributors.first.profileName, equals('Colleague Contributor'));
    });

    test('8. Live Supabase: Cross-department colleague discovered via shared team in database', () async {
      try {
        final socket = await Socket.connect('127.0.0.1', 54321, timeout: const Duration(seconds: 1));
        await socket.close();
      } catch (_) {
        // Skip if local docker supabase is not running
        return;
      }

      const localUrl = 'http://127.0.0.1:54321';
      const localAnonKey =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM0Mzc2MDB9.CRXP1A_c_j_9_m8_k_8';

      final staffClient = SupabaseClient(localUrl, localAnonKey);

      final authRes = await staffClient.auth.signInWithPassword(
        email: 'hse_officer@test.local',
        password: 'Password123!',
      );
      if (authRes.user == null) {
        await staffClient.dispose();
        return;
      }

      final callerId = authRes.user!.id;
      ActionService.instance.clientOverride = staffClient;

      final depts = await staffClient.from('departments').select('id, name').eq('name', 'HSE / Safety');
      final hseDeptId = depts.isNotEmpty ? depts.first['id'].toString() : null;

      final discovered = await ActionService.instance.fetchEligibleAssignees(
        organizationId: Organization.sobhaId,
        departmentId: hseDeptId,
        callerUserId: callerId,
      );

      // maint_staff is in Maintenance, but shares team with hse_officer in local DB
      final maintStaffFound = discovered.any((u) => u.email == 'maint_staff@test.local');
      expect(maintStaffFound, isTrue);

      ActionService.instance.clientOverride = null;
      await staffClient.dispose();
    });

    test('9. Staff on unscoped action (null department/site) WITHOUT team memberships CANNOT discover arbitrary users', () async {
      final mockPeople = [
        Person(
          id: '11111111-1111-1111-1111-111111111111',
          name: 'Staff HSE Caller No Teams',
          email: 'caller_noteams@sobha.local',
          phone: '+91 90000 00001',
          designation: 'Safety Tech',
          department: 'HSE',
          departmentId: 'dept-hse',
          site: 'HQ',
          siteId: 'site-hq',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.actionOwnerWorker,
          teamIds: const [], // NO TEAMS!
          organizationId: Organization.sobhaId,
        ),
        Person(
          id: '22222222-2222-2222-2222-222222222222',
          name: 'Colleague Same Dept HSE',
          email: 'colleague_hse@sobha.local',
          phone: '+91 90000 00002',
          designation: 'Safety Officer',
          department: 'HSE',
          departmentId: 'dept-hse',
          site: 'HQ',
          siteId: 'site-hq',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.actionOwnerWorker,
          teamIds: const [],
          organizationId: Organization.sobhaId,
        ),
        Person(
          id: '33333333-3333-3333-3333-333333333333',
          name: 'Arbitrary Other Dept Staff',
          email: 'other_dept@sobha.local',
          phone: '+91 90000 00003',
          designation: 'Mechanical Tech',
          department: 'Mechanical',
          departmentId: 'dept-mech',
          site: 'Yard C',
          siteId: 'site-yardc',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.actionOwnerWorker,
          teamIds: const [],
          organizationId: Organization.sobhaId,
        ),
      ];

      MockPeopleStore.instance.people.clear();
      MockPeopleStore.instance.people.addAll(mockPeople);
      MockActionStore.instance.profiles.clear();

      // Action has NULL department and NULL site!
      final eligible = await ActionService.instance.fetchEligibleAssignees(
        organizationId: Organization.sobhaId,
        departmentId: null,
        siteId: null,
        callerUserId: '11111111-1111-1111-1111-111111111111',
      );

      // Caller discovers themselves and colleague in same department/site
      expect(eligible.any((p) => p.personId == '11111111-1111-1111-1111-111111111111'), isTrue);
      expect(eligible.any((p) => p.personId == '22222222-2222-2222-2222-222222222222'), isTrue);

      // Staff CANNOT discover user in Mechanical department merely because action has null department/site!
      expect(eligible.any((p) => p.personId == '33333333-3333-3333-3333-333333333333'), isFalse);
    });

    test('10. Staff on unscoped action (null department/site) WITH shared team discovers shared colleague but excludes unrelated users', () async {
      final mockPeople = [
        Person(
          id: '11111111-1111-1111-1111-111111111111',
          name: 'Staff HSE Caller',
          email: 'caller@sobha.local',
          phone: '+91 90000 00001',
          designation: 'Safety Tech',
          department: 'HSE',
          departmentId: 'dept-hse',
          site: 'HQ',
          siteId: 'site-hq',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.actionOwnerWorker,
          teamIds: ['team-crisis-response'],
          organizationId: Organization.sobhaId,
        ),
        Person(
          id: '22222222-2222-2222-2222-222222222222',
          name: 'Colleague Civil In Shared Team',
          email: 'civil_shared@sobha.local',
          phone: '+91 90000 00002',
          designation: 'Civil Engineer',
          department: 'Civil',
          departmentId: 'dept-civil',
          site: 'Yard A',
          siteId: 'site-yarda',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.actionOwnerWorker,
          teamIds: ['team-crisis-response'], // Shared team!
          organizationId: Organization.sobhaId,
        ),
        Person(
          id: '33333333-3333-3333-3333-333333333333',
          name: 'Colleague Electrical NOT In Shared Team',
          email: 'electrical_unrelated@sobha.local',
          phone: '+91 90000 00003',
          designation: 'Electrician',
          department: 'Electrical',
          departmentId: 'dept-elec',
          site: 'Yard B',
          siteId: 'site-yardb',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.actionOwnerWorker,
          teamIds: ['team-electrical-only'], // No shared team!
          organizationId: Organization.sobhaId,
        ),
      ];

      MockPeopleStore.instance.people.clear();
      MockPeopleStore.instance.people.addAll(mockPeople);
      MockActionStore.instance.profiles.clear();

      final eligible = await ActionService.instance.fetchEligibleAssignees(
        organizationId: Organization.sobhaId,
        departmentId: null,
        siteId: null,
        callerUserId: '11111111-1111-1111-1111-111111111111',
      );

      // Discovers shared team colleague from Civil dept
      expect(eligible.any((p) => p.personId == '22222222-2222-2222-2222-222222222222'), isTrue);

      // Excludes Electrical colleague who shares no team
      expect(eligible.any((p) => p.personId == '33333333-3333-3333-3333-333333333333'), isFalse);
    });

    test('11. Manager and Admin preserve organization-wide discovery on unscoped action', () async {
      final mockPeople = [
        Person(
          id: 'manager-001',
          name: 'Manager Caller',
          email: 'manager@sobha.local',
          phone: '+91 90000 00010',
          designation: 'Operations Manager',
          department: 'Operations',
          departmentId: 'dept-ops',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.departmentManager,
          organizationId: Organization.sobhaId,
        ),
        Person(
          id: 'staff-civil-001',
          name: 'Staff Civil',
          email: 'civil@sobha.local',
          phone: '+91 90000 00011',
          designation: 'Civil Worker',
          department: 'Civil',
          departmentId: 'dept-civil',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.actionOwnerWorker,
          organizationId: Organization.sobhaId,
        ),
      ];

      MockPeopleStore.instance.people.clear();
      MockPeopleStore.instance.people.addAll(mockPeople);
      MockActionStore.instance.profiles.clear();

      final eligible = await ActionService.instance.fetchEligibleAssignees(
        organizationId: Organization.sobhaId,
        departmentId: null,
        siteId: null,
        callerUserId: 'manager-001',
      );

      // Manager can discover across departments on unscoped action
      expect(eligible.any((p) => p.personId == 'staff-civil-001'), isTrue);
    });

    test('12. Database Guard: Staff direct action closure & closure field tampering is rejected', () async {
      try {
        final socket = await Socket.connect('127.0.0.1', 54321, timeout: const Duration(seconds: 1));
        await socket.close();
      } catch (_) {
        return;
      }

      const localUrl = 'http://127.0.0.1:54321';
      const localAnonKey =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM0Mzc2MDB9.CRXP1A_c_j_9_m8_k_8';

      final maintClient = SupabaseClient(localUrl, localAnonKey);
      await maintClient.auth.signInWithPassword(
        email: 'maint_staff@test.local',
        password: 'Password123!',
      );

      const ownedActionId = '3ccc1afd-9e47-4e80-8dc3-edd111c3ec7f';

      // 1. Verify direct status = 'Closed' by Staff is BLOCKED by trigger
      bool closedBlocked = false;
      try {
        await maintClient
            .from('actions')
            .update({'status': 'Closed'})
            .eq('id', ownedActionId);
      } catch (e) {
        closedBlocked = e.toString().contains('Staff cannot directly close actions') ||
            e.toString().contains('ActionFlow Security Violation');
      }
      expect(closedBlocked, isTrue, reason: 'Staff must be blocked from directly setting status=Closed');

      // 2. Verify direct closed_at modification by Staff is BLOCKED
      bool closedAtBlocked = false;
      try {
        await maintClient
            .from('actions')
            .update({'closed_at': DateTime.now().toIso8601String()})
            .eq('id', ownedActionId);
      } catch (e) {
        closedAtBlocked = e.toString().contains('Staff cannot modify action closed_at') ||
            e.toString().contains('ActionFlow Security Violation');
      }
      expect(closedAtBlocked, isTrue, reason: 'Staff must be blocked from modifying closed_at');

      // 3. Verify direct closed_by modification by Staff is BLOCKED
      bool closedByBlocked = false;
      try {
        await maintClient
            .from('actions')
            .update({'closed_by': '22222222-2222-2222-2222-222222222222'})
            .eq('id', ownedActionId);
      } catch (e) {
        closedByBlocked = e.toString().contains('Staff cannot modify action closed_by') ||
            e.toString().contains('ActionFlow Security Violation');
      }
      expect(closedByBlocked, isTrue, reason: 'Staff must be blocked from modifying closed_by');

      // 4. Verify legitimate Staff progress update is ALLOWED
      bool progressUpdateAllowed = false;
      try {
        await maintClient
            .from('actions')
            .update({'percent_complete': 75, 'worker_message': 'Normal progress update'})
            .eq('id', ownedActionId);
        progressUpdateAllowed = true;
      } catch (e) {
        progressUpdateAllowed = false;
      }
      expect(progressUpdateAllowed, isTrue, reason: 'Legitimate Staff progress updates must remain permitted');

      await maintClient.dispose();
    });

    test('13. Manager/Admin verified closure workflow still succeeds', () async {
      try {
        final socket = await Socket.connect('127.0.0.1', 54321, timeout: const Duration(seconds: 1));
        await socket.close();
      } catch (_) {
        return;
      }

      const localUrl = 'http://127.0.0.1:54321';
      const localAnonKey =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM0Mzc2MDB9.CRXP1A_c_j_9_m8_k_8';

      final adminClient = SupabaseClient(localUrl, localAnonKey);
      await adminClient.auth.signInWithPassword(
        email: 'webonant@gmail.com',
        password: 'Password123!',
      );

      const targetActionId = '3ccc1afd-9e47-4e80-8dc3-edd111c3ec7f';

      // 1. Mark assignees work_completed = true
      await adminClient
          .from('action_assignees')
          .update({'work_completed': true})
          .eq('action_id', targetActionId);

      // 2. Mark action percent_complete = 100
      await adminClient
          .from('actions')
          .update({'percent_complete': 100})
          .eq('id', targetActionId);

      // 3. Call verified closure RPC
      final rpcRes = await adminClient.rpc('close_action_verified', params: {
        'p_action_id': targetActionId,
        'p_closure_comment': 'Verified closure by Admin in test',
      });

      expect(rpcRes, isNotNull);
      expect(rpcRes['success'], isTrue);

      // 4. Verify status in DB
      final actionData = await adminClient.from('actions').select('status, closed_at').eq('id', targetActionId).single();
      expect(actionData['status'], equals('Closed'));
      expect(actionData['closed_at'], isNotNull);

      // 5. Reopen action back to In Progress for test isolation
      final reopenRes = await adminClient.rpc('reopen_action', params: {
        'p_action_id': targetActionId,
        'p_reason': 'Resetting test isolation',
      });
      expect(reopenRes['status'], equals('In Progress'));

      await adminClient.dispose();
    });

    test('14. Manager discovers staff across multiple authorized manager_scopes without requiring team membership', () async {
      ActionService.instance.clientOverride = null;
      final mockPeople = [
        Person(
          id: 'mgr-1111-1111-1111',
          name: 'Manager MultiScope Ops',
          email: 'mgr_ops@sobha.local',
          phone: '+91 90000 00001',
          designation: 'Operations Manager',
          department: 'Operations',
          departmentId: 'dept-ops',
          site: 'Platform Alpha',
          siteId: 'site-alpha',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.departmentManager,
          teamIds: const [], // NO TEAMS!
          organizationId: Organization.sobhaId,
        ),
        Person(
          id: 'staff-alpha-2222',
          name: 'Staff Alpha Ops',
          email: 'staff_alpha@sobha.local',
          phone: '+91 90000 00002',
          designation: 'Operations Tech',
          department: 'Operations',
          departmentId: 'dept-ops',
          site: 'Platform Alpha',
          siteId: 'site-alpha',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.actionOwnerWorker,
          teamIds: const [], // NO TEAMS!
          organizationId: Organization.sobhaId,
        ),
        Person(
          id: 'staff-bravo-3333',
          name: 'Staff Bravo Ops',
          email: 'staff_bravo@sobha.local',
          phone: '+91 90000 00003',
          designation: 'Operations Specialist',
          department: 'Operations',
          departmentId: 'dept-ops',
          site: 'Platform Bravo',
          siteId: 'site-bravo',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.actionOwnerWorker,
          teamIds: const [], // NO TEAMS!
          organizationId: Organization.sobhaId,
        ),
        Person(
          id: 'staff-unrelated-4444',
          name: 'Staff Finance Tech',
          email: 'staff_finance@sobha.local',
          phone: '+91 90000 00004',
          designation: 'Finance Clerk',
          department: 'Finance',
          departmentId: 'dept-fin',
          site: 'HQ',
          siteId: 'site-hq',
          type: PersonType.internalUser,
          isActive: true,
          role: UserRole.actionOwnerWorker,
          teamIds: const [],
          organizationId: Organization.sobhaId,
        ),
      ];

      MockPeopleStore.instance.people.clear();
      MockPeopleStore.instance.people.addAll(mockPeople);
      MockActionStore.instance.profiles.clear();

      final eligible = await ActionService.instance.fetchEligibleAssignees(
        organizationId: Organization.sobhaId,
        departmentId: 'dept-ops',
        callerUserId: 'mgr-1111-1111-1111',
        managerScopes: [
          const ManagerScopeItem(
            departmentId: 'dept-ops',
            departmentName: 'Operations',
            siteId: 'site-alpha',
            siteName: 'Platform Alpha',
          ),
          const ManagerScopeItem(
            departmentId: 'dept-ops',
            departmentName: 'Operations',
            siteId: 'site-bravo',
            siteName: 'Platform Bravo',
          ),
        ],
      );

      final returnedIds = eligible.map((u) => u.personId).toSet();
      // Both scoped staff members appear despite NO team memberships!
      expect(returnedIds, contains('staff-alpha-2222'));
      expect(returnedIds, contains('staff-bravo-3333'));
      // Unrelated finance staff is excluded
      expect(returnedIds, isNot(contains('staff-unrelated-4444')));
    });

    test('15. Manager discovers staff in authorized scopes even when action department differs (ACT-1026 scenario)', () async {
      ActionService.instance.clientOverride = null;
      final eligible = await ActionService.instance.fetchEligibleAssignees(
        organizationId: Organization.sobhaId,
        departmentId: 'dept-custom-test-1026', // Action department is custom 'test'
        callerUserId: 'mgr-1111-1111-1111',
        managerScopes: [
          const ManagerScopeItem(
            departmentId: 'dept-ops',
            departmentName: 'Operations',
            siteId: 'site-alpha',
            siteName: 'Platform Alpha',
          ),
        ],
      );

      final returnedIds = eligible.map((u) => u.personId).toSet();
      // Manager can still discover staff under their authorized scopes for delegation!
      expect(returnedIds, contains('staff-alpha-2222'));
      expect(returnedIds, contains('staff-bravo-3333'));
    });

    test('16. Staff discovers colleagues in same primary department without requiring team membership', () async {
      ActionService.instance.clientOverride = null;
      final eligible = await ActionService.instance.fetchEligibleAssignees(
        organizationId: Organization.sobhaId,
        departmentId: 'dept-ops',
        callerUserId: 'staff-alpha-2222', // Caller is Staff Alpha
      );

      final returnedIds = eligible.map((u) => u.personId).toSet();
      // Colleague in same department appears without team membership
      expect(returnedIds, contains('staff-bravo-3333'));
      // Finance staff is excluded
      expect(returnedIds, isNot(contains('staff-unrelated-4444')));
    });

    test('17. Forward Action contributor addition strictly preserves 50% existing progress and original assigned_to', () async {
      final test50Action = ActionRecord(
        id: 'test-action-progress-50',
        subject: 'Inspection with 50% Progress',
        organizationId: Organization.sobhaId,
        department: 'Operations',
        division: 'Operations & HSSE',
        departmentId: 'dept-ops',
        site: 'Platform Alpha',
        siteId: 'site-alpha',
        assignedTo: 'Original Staff Assignee',
        assignedToId: 'staff-alpha-2222',
        assignedBy: 'Operations Manager',
        status: 'In Progress',
        percentComplete: 50, // 50% COMPLETE!
        targetDate: '2026-11-15',
        priority: 'Medium',
        category: 'Inspection',
        source: 'Direct Action',
        actionRequired: 'Check safety valves',
        contributors: const [],
        history: ['01 Nov 2026: Created with 50% initial progress.'],
      );

      MockActionStore.instance.actions.clear();
      MockActionStore.instance.actions.add(test50Action);

      // Add contributor
      final res = await ActionService.instance.addContributor(
        actionId: 'test-action-progress-50',
        contributorProfileId: 'staff-bravo-3333',
        addedBy: 'staff-alpha-2222',
        addedByName: 'Staff Alpha Ops',
        notes: 'Assisting with valve inspection',
      );

      expect(res.success, isTrue);

      final updated = MockActionStore.instance.actions.firstWhere((a) => a.id == 'test-action-progress-50');
      // 1. Progress MUST remain 50%
      expect(updated.percentComplete, equals(50));
      // 2. Original owner MUST remain unchanged
      expect(updated.assignedToId, equals('staff-alpha-2222'));
      expect(updated.assignedTo, equals('Original Staff Assignee'));
      // 3. Status remains In Progress
      expect(updated.status, equals('In Progress'));
      // 4. Contributor is added
      expect(updated.contributors.length, equals(1));
      expect(updated.contributors.first.profileId, equals('staff-bravo-3333'));
      // 5. History recorded
      expect(updated.history.any((h) => h.contains('Contributor')), isTrue);
    });
  });
}
