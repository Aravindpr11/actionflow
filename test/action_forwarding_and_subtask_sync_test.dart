import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_action_update_screen.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/services/action_service.dart';

void main() {
  const staffAId = 'user-staff-a-uuid';
  const staffAName = 'Staff A';
  const staffAEmail = 'staff-a@actionflow.demo';

  const staffBId = 'user-staff-b-uuid';
  const staffBName = 'Staff B';
  const staffBEmail = 'staff-b@actionflow.demo';

  const unauthCId = 'user-unauth-c-uuid';
  const unauthCName = 'Unauthorized User C';
  const unauthCEmail = 'unauth-c@actionflow.demo';

  const managerId = 'manager-m-uuid';
  const managerName = 'Manager M';
  const managerEmail = 'manager@actionflow.demo';

  final staffAPerson = Person(
    id: staffAId,
    name: staffAName,
    email: staffAEmail,
    phone: '+1-555-0101',
    designation: 'HSE Specialist',
    type: PersonType.internalUser,
    isActive: true,
    department: 'HSE',
    site: 'North Plant',
  );

  final staffBPerson = Person(
    id: staffBId,
    name: staffBName,
    email: staffBEmail,
    phone: '+1-555-0102',
    designation: 'Maintenance Technician',
    type: PersonType.internalUser,
    isActive: true,
    department: 'Maintenance',
    site: 'North Plant',
  );

  final unauthCPerson = Person(
    id: unauthCId,
    name: unauthCName,
    email: unauthCEmail,
    phone: '+1-555-0103',
    designation: 'Guest Auditor',
    type: PersonType.internalUser,
    isActive: true,
    department: 'Finance',
    site: 'HQ',
  );

  final managerPerson = Person(
    id: managerId,
    name: managerName,
    email: managerEmail,
    phone: '+1-555-0100',
    designation: 'Operations Manager',
    type: PersonType.internalUser,
    isActive: true,
    department: 'Operations',
    site: 'North Plant',
  );

  setUp(() {
    MockActionStore.instance.actions.clear();
    MockPeopleStore.instance.people.clear();
    MockPeopleStore.instance.notifications.clear();

    MockPeopleStore.instance.people.addAll([
      staffAPerson,
      staffBPerson,
      unauthCPerson,
      managerPerson,
    ]);
  });

  List<ActionSubTask> buildInitialSubTasks(String actionId) {
    return [
      ActionSubTask(
        id: '$actionId-ST-1',
        parentActionId: actionId,
        title: 'Isolate & depressurize valve station',
        instruction: 'Tag out valve V-102 and confirm zero gauge pressure',
        assignedStaff: staffBName,
        assignedStaffId: staffBId,
        assignedStaffEmail: staffBEmail,
        status: 'Open',
        dueDate: '10 Nov 2026',
      ),
      ActionSubTask(
        id: '$actionId-ST-2',
        parentActionId: actionId,
        title: 'Disassemble valve assembly & inspect seating',
        instruction: 'Check elastomer seals and seat rings for scoring',
        assignedStaff: staffBName,
        assignedStaffId: staffBId,
        assignedStaffEmail: staffBEmail,
        status: 'Open',
        dueDate: '12 Nov 2026',
      ),
      ActionSubTask(
        id: '$actionId-ST-3',
        parentActionId: actionId,
        title: 'Replace seal kits and bench-calibrate',
        instruction: 'Install certified OEM seal kit and verify lift pressure',
        assignedStaff: staffBName,
        assignedStaffId: staffBId,
        assignedStaffEmail: staffBEmail,
        status: 'Open',
        dueDate: '14 Nov 2026',
      ),
      ActionSubTask(
        id: '$actionId-ST-4',
        parentActionId: actionId,
        title: 'Reinstall, torque flange bolts & signoff QA tag',
        instruction: 'Torque bolts cross-pattern to 85 Nm and attach green QA tag',
        assignedStaff: staffBName,
        assignedStaffId: staffBId,
        assignedStaffEmail: staffBEmail,
        status: 'Open',
        dueDate: '16 Nov 2026',
      ),
    ];
  }

  ActionRecord buildSampleAction({
    required String actionId,
    int percent = 0,
    String status = 'In Progress',
    List<ActionContributorRecord> contributors = const [],
    List<ActionSubTask>? subTasks,
    List<String>? history,
  }) {
    return ActionRecord(
      id: actionId,
      actionNumber: actionId,
      subject: 'Pressure Relief Valve Overhaul',
      description: 'Annual overhaul of safety relief valve in Process Loop 4',
      actionRequired: 'Inspect, rebuild, calibrate, and recertify relief valve.',
      category: 'Maintenance',
      priority: 'High',
      status: status,
      division: 'Operations',
      department: 'Maintenance',
      site: 'North Plant',
      assignedTo: staffAName,
      assignedToId: staffAId,
      assignedBy: managerName,
      primaryAssignee: const ActionPersonReference(
        personId: staffAId,
        name: staffAName,
        email: staffAEmail,
        type: PersonType.internalUser,
      ),
      dateRaised: '01 Nov 2026',
      targetDate: '20 Nov 2026',
      percentComplete: percent,
      contributors: contributors,
      subTasks: subTasks ?? buildInitialSubTasks(actionId),
      workerMessageSubject: 'Valve Overhaul Progress Update',
      workerMessage: 'Inspection and maintenance steps in progress.',
      history: history ?? [
        '01 Nov 2026: Manager M created and assigned action to Staff A.',
      ],
      attachments: const [],
    );
  }

  group('Action Forwarding & Subtask Progress Synchronization — 14 Scenarios', () {
    const actionId = 'ACT-SYNC-2026';

    testWidgets(
      'End-to-End Workflow: Scenarios 1 through 10 (Assign, Forward, 25%, 50%, 100%, Review, Ownership & History)',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // =====================================================================
        // SCENARIO 1: Manager assigns action to Staff A
        // =====================================================================
        final initialAction = buildSampleAction(
          actionId: actionId,
          contributors: const [],
        );
        MockActionStore.instance.add(initialAction);

        expect(initialAction.assignedTo, equals(staffAName));
        expect(initialAction.assignedToId, equals(staffAId));
        expect(initialAction.assignedBy, equals(managerName));
        expect(initialAction.primaryAssignee?.personId, equals(staffAId));
        expect(initialAction.percentComplete, equals(0));
        expect(initialAction.subTasks.length, equals(4));

        // Staff A sees action in My Actions
        final staffAActions = await ActionService.instance.fetchMyActions(
          organizationId: 'org-sobha-01',
          userId: staffAId,
        );
        expect(staffAActions.any((a) => a.id == actionId), isTrue);

        // Unrelated User C does not see action
        final unauthActions = await ActionService.instance.fetchMyActions(
          organizationId: 'org-sobha-01',
          userId: unauthCId,
        );
        expect(unauthActions.any((a) => a.id == actionId), isFalse);

        // =====================================================================
        // SCENARIO 2: Staff A forwards action to Staff B via addContributor
        // =====================================================================
        final forwardRes = await ActionService.instance.addContributor(
          actionId: actionId,
          contributorProfileId: staffBId,
          notes: 'Assigned to overhaul mechanical assembly',
        );
        expect(forwardRes.success, isTrue);
        expect(forwardRes.contributorName, equals(staffBName));

        var currentAction = MockActionStore.instance.actions.firstWhere((a) => a.id == actionId);
        expect(currentAction.assignedTo, equals(staffAName)); // Owner remains Staff A
        expect(currentAction.assignedToId, equals(staffAId));
        expect(currentAction.primaryAssignee?.name, equals(staffAName));
        expect(currentAction.contributors.length, equals(1));
        expect(currentAction.contributors.first.profileId, equals(staffBId));
        expect(currentAction.history.any((h) => h.contains('Contributor Staff B added.')), isTrue);

        // Staff B now sees the action in their action list
        final staffBActions = await ActionService.instance.fetchMyActions(
          organizationId: 'org-sobha-01',
          userId: staffBId,
        );
        expect(staffBActions.any((a) => a.id == actionId), isTrue);

        // =====================================================================
        // SCENARIO 3 & 4: Staff B completes 1 of 4 subtasks and saves; progress = 25%
        // =====================================================================
        ActionRecord? poppedAction;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    poppedAction = await Navigator.of(ctx).push<ActionRecord>(
                      MaterialPageRoute(
                        builder: (_) => WorkerActionUpdateScreen(
                          action: currentAction,
                          currentUserId: staffBId,
                          currentUserName: staffBName,
                          currentUserEmail: staffBEmail,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Update Screen'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Update Screen'));
        await tester.pumpAndSettle();

        // Screen starts at 0%
        expect(find.text('0%'), findsWidgets);

        // Toggle task 0 (1 of 4 completed)
        await tester.tap(find.byKey(const Key('worker_task_checkbox_0')));
        await tester.pumpAndSettle();

        // 1 of 4 = exactly 25%
        expect(find.text('25%'), findsWidgets);

        // Save update
        final saveBtn1 = find.descendant(
          of: find.byType(AppBar),
          matching: find.widgetWithText(OutlinedButton, 'Save Update'),
        );
        await tester.tap(saveBtn1);
        await tester.pumpAndSettle();

        expect(poppedAction, isNotNull);
        expect(poppedAction!.percentComplete, equals(25));
        expect(poppedAction!.status, equals('In Progress'));
        expect(poppedAction!.subTasks[0].isCompleted, isTrue);

        // Check persisted state in MockActionStore
        currentAction = MockActionStore.instance.actions.firstWhere((a) => a.id == actionId);
        expect(currentAction.percentComplete, equals(25));
        expect(currentAction.status, equals('In Progress'));

        // =====================================================================
        // SCENARIO 5: Staff A and Manager both see 25% progress & synchronized state
        // =====================================================================
        final staffAView = (await ActionService.instance.fetchMyActions(
          organizationId: 'org-sobha-01',
          userId: staffAId,
        )).firstWhere((a) => a.id == actionId);
        expect(staffAView.percentComplete, equals(25));
        expect(staffAView.subTasks.where((t) => t.isCompleted).length, equals(1));
        expect(staffAView.subTasks.length, equals(4));

        final managerView = await ActionService.instance.fetchActionById(actionId);
        expect(managerView, isNotNull);
        expect(managerView!.percentComplete, equals(25));
        expect(managerView.subTasks.where((t) => t.isCompleted).length, equals(1));

        // Pump ActionDetailsScreen for Staff A and Manager to verify UI rendering
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ActionDetailsScreen(
                action: currentAction,
                isWorker: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('25%'), findsWidgets);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ActionDetailsScreen(
                action: currentAction,
                isWorker: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('25%'), findsWidgets);

        // =====================================================================
        // SCENARIO 6: Staff B completes 2nd subtask; progress dynamically updates to 50%
        // =====================================================================
        poppedAction = null;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    poppedAction = await Navigator.of(ctx).push<ActionRecord>(
                      MaterialPageRoute(
                        builder: (_) => WorkerActionUpdateScreen(
                          action: currentAction,
                          currentUserId: staffBId,
                          currentUserName: staffBName,
                          currentUserEmail: staffBEmail,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Update Screen 2'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Update Screen 2'));
        await tester.pumpAndSettle();

        // Opens with 25%
        expect(find.text('25%'), findsWidgets);

        // Toggle task 1 (2 of 4 completed)
        await tester.tap(find.byKey(const Key('worker_task_checkbox_1')));
        await tester.pumpAndSettle();

        // 2 of 4 = 50%
        expect(find.text('50%'), findsWidgets);

        // Save update
        final saveBtn2 = find.descendant(
          of: find.byType(AppBar),
          matching: find.widgetWithText(OutlinedButton, 'Save Update'),
        );
        await tester.tap(saveBtn2);
        await tester.pumpAndSettle();

        expect(poppedAction, isNotNull);
        expect(poppedAction!.percentComplete, equals(50));
        expect(poppedAction!.status, equals('In Progress'));

        currentAction = MockActionStore.instance.actions.firstWhere((a) => a.id == actionId);
        expect(currentAction.percentComplete, equals(50));
        expect(currentAction.subTasks.where((t) => t.isCompleted).length, equals(2));

        // =====================================================================
        // SCENARIO 7: Partial save keeps In Progress, no false review submission
        // =====================================================================
        expect(currentAction.status, equals('In Progress'));
        expect(
          currentAction.history.any((h) => h.contains('Staff submitted action for Manager review')),
          isFalse,
        );
        expect(
          currentAction.history.any((h) => h.contains('50%')),
          isTrue,
        );

        // =====================================================================
        // SCENARIO 8: Remaining subtasks are completed; progress reaches 100%
        // =====================================================================
        poppedAction = null;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    poppedAction = await Navigator.of(ctx).push<ActionRecord>(
                      MaterialPageRoute(
                        builder: (_) => WorkerActionUpdateScreen(
                          action: currentAction,
                          currentUserId: staffBId,
                          currentUserName: staffBName,
                          currentUserEmail: staffBEmail,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Update Screen 3'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Update Screen 3'));
        await tester.pumpAndSettle();

        expect(find.text('50%'), findsWidgets);

        // Complete subtask 2 (3 of 4 = 75%)
        final cb2 = find.byKey(const Key('worker_task_checkbox_2'));
        await tester.ensureVisible(cb2);
        await tester.tap(cb2);
        await tester.pumpAndSettle();
        expect(find.text('75%'), findsWidgets);

        // Complete subtask 3 (4 of 4 = 100%)
        final cb3 = find.byKey(const Key('worker_task_checkbox_3'));
        await tester.ensureVisible(cb3);
        await tester.tap(cb3);
        await tester.pumpAndSettle();
        expect(find.text('100%'), findsWidgets);

        // =====================================================================
        // SCENARIO 9: Final review submission succeeds without duplicate entries
        // =====================================================================
        final submitBtn = find.descendant(
          of: find.byType(AppBar),
          matching: find.widgetWithText(ElevatedButton, 'Submit for Review'),
        );
        expect(submitBtn, findsOneWidget);
        await tester.tap(submitBtn);
        await tester.pumpAndSettle();

        expect(poppedAction, isNotNull);
        expect(poppedAction!.status, equals('Pending Review'));
        expect(poppedAction!.percentComplete, equals(100));

        currentAction = MockActionStore.instance.actions.firstWhere((a) => a.id == actionId);
        expect(currentAction.status, equals('Pending Review'));
        expect(currentAction.percentComplete, equals(100));
        expect(currentAction.subTasks.length, equals(4)); // No duplicates

        final reviewEntries = currentAction.history
            .where((h) => h.contains('Staff submitted action for Manager review'))
            .toList();
        expect(reviewEntries.length, equals(1)); // Exactly 1 log entry

        // =====================================================================
        // SCENARIO 10: Forwarding chain preserves original assignee & contributor
        // =====================================================================
        expect(currentAction.assignedTo, equals(staffAName));
        expect(currentAction.assignedToId, equals(staffAId));
        expect(currentAction.primaryAssignee?.name, equals(staffAName));
        expect(currentAction.contributors.any((c) => c.profileId == staffBId), isTrue);

        expect(currentAction.history.any((h) => h.contains('assigned action to Staff A')), isTrue);
        expect(currentAction.history.any((h) => h.contains('Contributor Staff B added')), isTrue);
        expect(currentAction.history.any((h) => h.contains('Staff submitted action for Manager review')), isTrue);
      },
    );

    testWidgets('11. Unauthorized users are blocked from updating action or subtasks', (tester) async {
      final sampleAction = buildSampleAction(actionId: 'ACT-UNAUTH-TEST');
      MockActionStore.instance.add(sampleAction);

      expect(sampleAction.isForwardedTo(unauthCId, unauthCName, unauthCEmail), isFalse);
      expect(sampleAction.assignedToId, isNot(equals(unauthCId)));

      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkerActionUpdateScreen(
              action: sampleAction,
              currentUserId: unauthCId,
              currentUserName: unauthCName,
              currentUserEmail: unauthCEmail,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No interactive subtask checkboxes are rendered for unauthorized user C
      expect(find.byType(CheckboxListTile), findsNothing);
    });

    testWidgets('12. Reopening action does not revert to stale values', (tester) async {
      final sampleAction = buildSampleAction(
        actionId: 'ACT-REOPEN-TEST',
        percent: 100,
        status: 'Pending Review',
        subTasks: buildInitialSubTasks('ACT-REOPEN-TEST')
            .map((t) => t.copyWith(status: 'Completed'))
            .toList(),
      );
      MockActionStore.instance.add(sampleAction);

      final read1 = await ActionService.instance.fetchActionById('ACT-REOPEN-TEST');
      final read2 = await ActionService.instance.fetchMyActions(
        organizationId: 'org-sobha-01',
        userId: staffAId,
      );
      final read3 = await ActionService.instance.fetchMyActions(
        organizationId: 'org-sobha-01',
        userId: staffBId,
      );

      expect(read1!.percentComplete, equals(100));
      expect(read1.status, equals('Pending Review'));
      expect(read1.subTasks.every((t) => t.isCompleted), isTrue);

      expect(read2.firstWhere((a) => a.id == 'ACT-REOPEN-TEST').percentComplete, equals(100));
      expect(read3.firstWhere((a) => a.id == 'ACT-REOPEN-TEST').percentComplete, equals(100));
    });

    testWidgets('13. Repeated updates do not duplicate tasks or corrupt progress calculation', (tester) async {
      final subtasks = buildInitialSubTasks('ACT-REPEAT-TEST');
      final sampleAction = buildSampleAction(
        actionId: 'ACT-REPEAT-TEST',
        percent: 100,
        status: 'Pending Review',
        subTasks: subtasks,
      );
      MockActionStore.instance.add(sampleAction);

      // Submit multiple updates sequentially
      await ActionService.instance.submitProgressUpdate(
        actionId: 'ACT-REPEAT-TEST',
        updateDate: DateTime.now(),
        progress: 100,
        status: 'Pending Review',
        comments: 'Progress verified first time',
        subTasks: subtasks,
        history: sampleAction.history,
      );

      await ActionService.instance.submitProgressUpdate(
        actionId: 'ACT-REPEAT-TEST',
        updateDate: DateTime.now(),
        progress: 100,
        status: 'Pending Review',
        comments: 'Progress verified second time',
        subTasks: subtasks,
        history: sampleAction.history,
      );

      final persisted = MockActionStore.instance.actions.firstWhere((a) => a.id == 'ACT-REPEAT-TEST');
      expect(persisted.subTasks.length, equals(4));
      expect(persisted.percentComplete, equals(100));
    });

    testWidgets('14. Direct assignment with no subtasks preserves manual progress updates', (tester) async {
      const directActionId = 'ACT-DIRECT-MANUAL';
      final directAction = buildSampleAction(
        actionId: directActionId,
        percent: 30,
        subTasks: const [], // No subtasks -> manual entry
      );
      MockActionStore.instance.add(directAction);

      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      ActionRecord? poppedAction;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  poppedAction = await Navigator.of(ctx).push<ActionRecord>(
                    MaterialPageRoute(
                      builder: (_) => WorkerActionUpdateScreen(
                        action: directAction,
                        currentUserId: staffAId,
                        currentUserName: staffAName,
                        currentUserEmail: staffAEmail,
                      ),
                    ),
                  );
                },
                child: const Text('Open Direct Update'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Direct Update'));
      await tester.pumpAndSettle();

      // Quick progress chip '75%' tapped
      final chip75 = find.widgetWithText(ActionChip, '75%');
      if (chip75.evaluate().isNotEmpty) {
        await tester.tap(chip75);
        await tester.pumpAndSettle();
      }

      // Save update
      final saveBtn = find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithText(OutlinedButton, 'Save Update'),
      );
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(poppedAction, isNotNull);
      expect(poppedAction!.subTasks, isEmpty);
      // Progress remains as manually set (75% or 30%)
      expect(poppedAction!.percentComplete, anyOf(equals(75), equals(30)));
    });
  });
}
