import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/add_action_screen.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const testOrgId = '00000000-0000-0000-0000-000000000001';

  final primaryOwner = ActionPersonReference(
    personId: '10000000-0000-0000-0000-000000000001',
    name: 'Primary Owner User',
    type: PersonType.internalUser,
    email: 'primary.owner@sobha.com',
  );

  final secondaryAssignee1 = ActionPersonReference(
    personId: '20000000-0000-0000-0000-000000000002',
    name: 'Secondary Assignee One',
    type: PersonType.internalUser,
    email: 'secondary.one@sobha.com',
  );

  final secondaryAssignee2 = ActionPersonReference(
    personId: '30000000-0000-0000-0000-000000000003',
    name: 'Secondary Assignee Two',
    type: PersonType.internalUser,
    email: 'secondary.two@sobha.com',
  );

  final secondaryAssignee3 = ActionPersonReference(
    personId: '40000000-0000-0000-0000-000000000004',
    name: 'Secondary Assignee Three',
    type: PersonType.internalUser,
    email: 'secondary.three@sobha.com',
  );

  ActionRecord createBaseRecord({
    required String id,
    required ActionPersonReference primary,
    List<ActionPersonReference> additional = const [],
    List<ActionAssigneeRecord> assignees = const [],
    List<ActionContributorRecord> contributors = const [],
  }) {
    return ActionRecord(
      id: id,
      organizationId: testOrgId,
      actionNumber: id,
      subject: 'Assignee Reconciliation Test Action $id',
      description: 'Testing secondary assignee reconciliation and error handling',
      actionRequired: 'Verify assignees',
      assignedTo: primary.name,
      assignedToId: primary.personId,
      primaryAssignee: primary,
      additionalPeople: additional,
      assignees: assignees,
      contributors: contributors,
      createdById: 'mgr-001',
      assignedBy: 'Manager User',
      priority: 'High',
      status: 'In Progress',
      percentComplete: 0,
      division: 'Operations',
      department: 'HSE',
      site: 'North Plant',
      dateRaised: '16 Oct 2026',
      targetDate: '30 Oct 2026',
    );
  }

  setUp(() {
    ActionService.instance.mockAssigneePersistenceShouldFail = false;
    ActionService.instance.mockAssigneePersistenceFailureReason = null;
    MockActionStore.instance.actions.clear();
  });

  tearDown(() {
    ActionService.instance.mockAssigneePersistenceShouldFail = false;
    ActionService.instance.mockAssigneePersistenceFailureReason = null;
  });

  group('Step 19: Action Assignee Reconciliation & Persistence Error Handling', () {
    // --------------------------------------------------------------------------
    // Scenario 1: Creating action with primary and secondary assignee persists both
    // --------------------------------------------------------------------------
    test('1. Creating action with primary and secondary assignee persists both', () async {
      final initialRecord = createBaseRecord(
        id: 'ACT-SCENARIO-1',
        primary: primaryOwner,
        additional: [secondaryAssignee1],
      );

      final created = await ActionService.instance.createAction(
        initialRecord,
        sendAssignmentNotification: false,
      );

      expect(created.assignees.length, equals(2));

      final ownerAssignee = created.assignees.firstWhere((a) => a.profileId == primaryOwner.personId);
      expect(ownerAssignee.assignmentRole, equals('owner'));
      expect(ownerAssignee.isRequired, isTrue);

      final secAssignee = created.assignees.firstWhere((a) => a.profileId == secondaryAssignee1.personId);
      expect(secAssignee.assignmentRole, equals('assignee'));
      expect(secAssignee.isRequired, isTrue);

      // Verify stored in MockActionStore
      final stored = MockActionStore.instance.actions.firstWhere((a) => a.id == created.id);
      expect(stored.assignees.length, equals(2));
      expect(stored.assignees.map((a) => a.profileId).toSet(), equals({
        primaryOwner.personId,
        secondaryAssignee1.personId,
      }));
    });

    // --------------------------------------------------------------------------
    // Scenario 2: Updating action to add secondary assignee persists new link
    // --------------------------------------------------------------------------
    test('2. Updating action to add secondary assignee persists new link', () async {
      // Create with only primary owner
      final initialRecord = createBaseRecord(
        id: 'ACT-SCENARIO-2',
        primary: primaryOwner,
        additional: const [],
      );
      final created = await ActionService.instance.createAction(
        initialRecord,
        sendAssignmentNotification: false,
      );
      expect(created.assignees.length, equals(1));
      expect(created.assignees.first.profileId, equals(primaryOwner.personId));

      // Update to add secondaryAssignee1
      final updateCandidate = created.copyWith(
        additionalPeople: [secondaryAssignee1],
        assignees: [
          created.assignees.first,
          ActionAssigneeRecord(
            id: 'assignee-${secondaryAssignee1.personId}',
            actionId: created.id,
            profileId: secondaryAssignee1.personId,
            profileName: secondaryAssignee1.name,
            profileEmail: secondaryAssignee1.email,
            assignmentRole: 'assignee',
            isRequired: true,
          ),
        ],
      );

      final updated = await ActionService.instance.updateAction(updateCandidate);

      expect(updated.assignees.length, equals(2));
      expect(updated.assignees.map((a) => a.profileId).toSet(), equals({
        primaryOwner.personId,
        secondaryAssignee1.personId,
      }));

      final stored = MockActionStore.instance.actions.firstWhere((a) => a.id == created.id);
      expect(stored.assignees.length, equals(2));
    });

    // --------------------------------------------------------------------------
    // Scenario 3: Updating action to remove secondary assignee removes obsolete link
    // --------------------------------------------------------------------------
    test('3. Updating action to remove secondary assignee removes obsolete link', () async {
      // Create with primary owner and two secondary assignees
      final initialRecord = createBaseRecord(
        id: 'ACT-SCENARIO-3',
        primary: primaryOwner,
        additional: [secondaryAssignee1, secondaryAssignee2],
      );
      final created = await ActionService.instance.createAction(
        initialRecord,
        sendAssignmentNotification: false,
      );
      expect(created.assignees.length, equals(3));
      expect(created.additionalPeople.length, equals(2));

      // Now remove secondaryAssignee2 from the form
      final remainingAssignees = created.assignees
          .where((a) => a.profileId != secondaryAssignee2.personId)
          .toList();
      final remainingPeople = created.additionalPeople
          .where((p) => p.personId != secondaryAssignee2.personId)
          .toList();

      final updateCandidate = created.copyWith(
        additionalPeople: remainingPeople,
        assignees: remainingAssignees,
      );

      final updated = await ActionService.instance.updateAction(updateCandidate);

      // Verify obsolete link is removed
      expect(updated.assignees.length, equals(2));
      expect(updated.assignees.any((a) => a.profileId == secondaryAssignee2.personId), isFalse);
      expect(updated.additionalPeople.any((p) => p.personId == secondaryAssignee2.personId), isFalse);

      // Verify stored record in store also removed the obsolete assignee
      final stored = MockActionStore.instance.actions.firstWhere((a) => a.id == created.id);
      expect(stored.assignees.length, equals(2));
      expect(stored.assignees.any((a) => a.profileId == secondaryAssignee2.personId), isFalse);
    });

    // --------------------------------------------------------------------------
    // Scenario 4: Retaining an assignee preserves existing link and completion state
    // --------------------------------------------------------------------------
    test('4. Retaining an assignee preserves existing link and completion state', () async {
      final initialRecord = createBaseRecord(
        id: 'ACT-SCENARIO-4',
        primary: primaryOwner,
        additional: [secondaryAssignee1, secondaryAssignee2],
      );
      final created = await ActionService.instance.createAction(
        initialRecord,
        sendAssignmentNotification: false,
      );

      // Mark secondaryAssignee1 as completed
      final markRes = await ActionService.instance.markAssigneeCompleted(
        actionId: created.id,
        profileId: secondaryAssignee1.personId,
        completed: true,
      );
      expect(markRes.success, isTrue);

      final beforeUpdate = MockActionStore.instance.actions.firstWhere((a) => a.id == created.id);
      final sec1Before = beforeUpdate.assignees.firstWhere((a) => a.profileId == secondaryAssignee1.personId);
      expect(sec1Before.workCompleted, isTrue);
      expect(sec1Before.completedAt, isNotNull);

      // Now update the action: remove secondaryAssignee2, but keep secondaryAssignee1
      final remainingAssignees = beforeUpdate.assignees
          .where((a) => a.profileId != secondaryAssignee2.personId)
          .toList();
      final remainingPeople = beforeUpdate.additionalPeople
          .where((p) => p.personId != secondaryAssignee2.personId)
          .toList();

      final updateCandidate = beforeUpdate.copyWith(
        subject: 'Updated Subject While Preserving Completion',
        additionalPeople: remainingPeople,
        assignees: remainingAssignees,
      );

      final updated = await ActionService.instance.updateAction(updateCandidate);

      expect(updated.assignees.length, equals(2));
      final sec1After = updated.assignees.firstWhere((a) => a.profileId == secondaryAssignee1.personId);
      expect(sec1After.workCompleted, isTrue, reason: 'Retained assignee workCompleted state must be preserved');
      expect(sec1After.completedAt, equals(sec1Before.completedAt), reason: 'Retained assignee completedAt timestamp must be preserved');
    });

    // --------------------------------------------------------------------------
    // Scenario 5: Saving same assignment list twice is idempotent (zero duplicate links)
    // --------------------------------------------------------------------------
    test('5. Saving same assignment list twice is idempotent (zero duplicate links)', () async {
      final initialRecord = createBaseRecord(
        id: 'ACT-SCENARIO-5',
        primary: primaryOwner,
        additional: [secondaryAssignee1, secondaryAssignee2],
      );
      final created = await ActionService.instance.createAction(
        initialRecord,
        sendAssignmentNotification: false,
      );
      expect(created.assignees.length, equals(3));

      // Save once
      final savedOnce = await ActionService.instance.updateAction(created);
      expect(savedOnce.assignees.length, equals(3));

      // Save second time with identical assignees
      final savedTwice = await ActionService.instance.updateAction(savedOnce);
      expect(savedTwice.assignees.length, equals(3));

      final profileIds = savedTwice.assignees.map((a) => a.profileId).toList();
      expect(profileIds.toSet().length, equals(profileIds.length), reason: 'Zero duplicate assignee links allowed');
    });

    // --------------------------------------------------------------------------
    // Scenario 6: Primary owner remains assigned when secondary assignees change
    // --------------------------------------------------------------------------
    test('6. Primary owner remains assigned when secondary assignees change', () async {
      final initialRecord = createBaseRecord(
        id: 'ACT-SCENARIO-6',
        primary: primaryOwner,
        additional: [secondaryAssignee1],
      );
      final created = await ActionService.instance.createAction(
        initialRecord,
        sendAssignmentNotification: false,
      );

      // Completely replace secondary assignees: remove secondaryAssignee1, add secondaryAssignee2 and secondaryAssignee3
      final updateCandidate = created.copyWith(
        additionalPeople: [secondaryAssignee2, secondaryAssignee3],
        assignees: [
          created.assignees.firstWhere((a) => a.assignmentRole == 'owner'),
          ActionAssigneeRecord(
            id: 'assignee-${secondaryAssignee2.personId}',
            actionId: created.id,
            profileId: secondaryAssignee2.personId,
            profileName: secondaryAssignee2.name,
            assignmentRole: 'assignee',
            isRequired: true,
          ),
          ActionAssigneeRecord(
            id: 'assignee-${secondaryAssignee3.personId}',
            actionId: created.id,
            profileId: secondaryAssignee3.personId,
            profileName: secondaryAssignee3.name,
            assignmentRole: 'assignee',
            isRequired: true,
          ),
        ],
      );

      final updated = await ActionService.instance.updateAction(updateCandidate);

      // Verify primary owner is still intact
      expect(updated.assignedToId, equals(primaryOwner.personId));
      expect(updated.assignedTo, equals(primaryOwner.name));

      final owner = updated.assignees.firstWhere((a) => a.profileId == primaryOwner.personId);
      expect(owner.assignmentRole, equals('owner'));
      expect(owner.isRequired, isTrue);

      // Verify secondary assignees are exactly 2 and 3
      final secondaryIds = updated.assignees
          .where((a) => a.assignmentRole == 'assignee')
          .map((a) => a.profileId)
          .toSet();
      expect(secondaryIds, equals({secondaryAssignee2.personId, secondaryAssignee3.personId}));
      expect(secondaryIds.contains(secondaryAssignee1.personId), isFalse);
    });

    // --------------------------------------------------------------------------
    // Scenario 7: Contributor records remain unchanged during assignee reconciliation
    // --------------------------------------------------------------------------
    test('7. Contributor records remain unchanged during assignee reconciliation', () async {
      final contributor = ActionContributorRecord(
        id: 'contrib-001',
        actionId: 'ACT-SCENARIO-7',
        profileId: '90000000-0000-0000-0000-000000000099',
        profileName: 'Independent Contributor',
        profileEmail: 'contrib@sobha.com',
        notes: 'Reviewing safety checklists',
      );

      final initialRecord = createBaseRecord(
        id: 'ACT-SCENARIO-7',
        primary: primaryOwner,
        additional: [secondaryAssignee1],
        contributors: [contributor],
      );

      final created = await ActionService.instance.createAction(
        initialRecord,
        sendAssignmentNotification: false,
      );
      expect(created.contributors.length, equals(1));
      expect(created.contributors.first.profileId, equals(contributor.profileId));

      // Remove secondaryAssignee1 from assignees
      final updateCandidate = created.copyWith(
        additionalPeople: const [],
        assignees: created.assignees.where((a) => a.assignmentRole == 'owner').toList(),
      );

      final updated = await ActionService.instance.updateAction(updateCandidate);

      // Assignee reconciliation must NOT delete or touch action_contributors
      expect(updated.assignees.length, equals(1));
      expect(updated.contributors.length, equals(1));
      expect(updated.contributors.first.profileId, equals(contributor.profileId));
      expect(updated.contributors.first.notes, equals('Reviewing safety checklists'));
    });

    // --------------------------------------------------------------------------
    // Scenario 8: Assignee persistence failure is propagated and not reported as successful
    // --------------------------------------------------------------------------
    test('8. Assignee persistence failure is propagated and not reported as successful', () async {
      final initialRecord = createBaseRecord(
        id: 'ACT-SCENARIO-8',
        primary: primaryOwner,
        additional: [secondaryAssignee1],
      );

      ActionService.instance.mockAssigneePersistenceShouldFail = true;
      ActionService.instance.mockAssigneePersistenceFailureReason =
          'Database constraint violation: foreign key check failed on action_assignees.profile_id';

      expect(
        () async => await ActionService.instance.createAction(
          initialRecord,
          sendAssignmentNotification: false,
        ),
        throwsA(isA<ActionAssigneePersistenceException>().having(
          (e) => e.message,
          'message',
          contains('foreign key check failed on action_assignees.profile_id'),
        )),
      );

      // Verify the action was not added to the store
      final inStore = MockActionStore.instance.actions.any((a) => a.id == initialRecord.id);
      expect(inStore, isFalse, reason: 'Failed action must not be saved into action store');
    });

    // --------------------------------------------------------------------------
    // Scenario 9: Authorization/RLS failure is handled safely
    // --------------------------------------------------------------------------
    test('9. Authorization/RLS failure is handled safely and surfaces actionable error', () async {
      final initialRecord = createBaseRecord(
        id: 'ACT-SCENARIO-9',
        primary: primaryOwner,
        additional: const [],
      );

      // Create successfully
      final created = await ActionService.instance.createAction(
        initialRecord,
        sendAssignmentNotification: false,
      );

      // Now simulate RLS authorization failure on update
      ActionService.instance.mockAssigneePersistenceShouldFail = true;
      ActionService.instance.mockAssigneePersistenceFailureReason =
          'new row violates row-level security policy for table "action_assignees"';

      final updateCandidate = created.copyWith(
        additionalPeople: [secondaryAssignee1],
      );

      expect(
        () async => await ActionService.instance.updateAction(updateCandidate),
        throwsA(isA<ActionAssigneePersistenceException>().having(
          (e) => e.message,
          'message',
          contains('new row violates row-level security policy'),
        )),
      );
    });

    // --------------------------------------------------------------------------
    // Scenario 10: Failed reconciliation does not silently leave UI in misleading state
    // --------------------------------------------------------------------------
    testWidgets('10. Failed reconciliation does not silently leave UI in misleading state', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final existingAction = createBaseRecord(
        id: 'ACT-UI-FAIL-TEST',
        primary: primaryOwner,
        additional: [secondaryAssignee1],
      );

      // Configure failure on save
      ActionService.instance.mockAssigneePersistenceShouldFail = true;
      ActionService.instance.mockAssigneePersistenceFailureReason =
          'RLS permission denied: user cannot write to action_assignees';

      bool onSavedCalled = false;
      ActionRecord? receivedRecord;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddActionScreen(
              actionId: existingAction.id,
              existingAction: existingAction,
              onSaved: (record) {
                onSavedCalled = true;
                receivedRecord = record;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Save Changes in header
      final saveBtn = find.text('SAVE CHANGES');
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // 1. Verify onSaved callback was NEVER called
      expect(onSavedCalled, isFalse);
      expect(receivedRecord, isNull);

      // 2. Verify red error SnackBar is displayed with the exact failure reason
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.textContaining('RLS permission denied: user cannot write to action_assignees'),
        findsOneWidget,
      );

      // 3. Verify screen is still active (not popped/closed) so user does not lose input
      expect(find.text('Edit Action'), findsOneWidget);
      expect(find.text(existingAction.subject), findsOneWidget);
    });
  });
}
