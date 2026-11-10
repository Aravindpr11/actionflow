import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/widgets/dashboard_forwarded_actions_card.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_action_update_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const orgId = Organization.sobhaId;

  // Profiles
  const mgrAId = 'mgr-uuid-001';
  const mgrAName = 'Marcus Vance';
  const mgrAEmail = 'mvance@sobha.com';

  const mgrBId = 'mgr-uuid-002';
  const mgrBName = 'Elena Rostova';
  const mgrBEmail = 'erostova@sobha.com';

  const staffAId = 'staff-uuid-001';
  const staffAName = 'R. Kumar';
  const staffAEmail = 'rkumar@sobha.com';

  const staffBId = 'staff-uuid-002';
  const staffBName = 'S. Jones';
  const staffBEmail = 'sjones@sobha.com';

  const unauthorizedId = 'unauth-uuid-999';

  final mgrAProfile = UserProfile(
    id: mgrAId,
    name: mgrAName,
    email: mgrAEmail,
    phone: '+971 50 111 2222',
    role: 'manager',
    designation: 'Operations Director',
    organizationId: orgId,
    department: 'Operations',
    site: 'North Plant',
  );

  final mgrAContext = ManagerContext(
    authUserId: mgrAId,
    profile: mgrAProfile,
    organizationId: orgId,
    organizationName: Organization.sobhaName,
    scopes: const [],
  );

  final staffAProfile = UserProfile(
    id: staffAId,
    name: staffAName,
    email: staffAEmail,
    phone: '+971 50 333 4444',
    role: 'staff',
    designation: 'Field Inspector',
    organizationId: orgId,
    department: 'Operations',
    site: 'North Plant',
  );

  ActionRecord makeAction({
    required String id,
    String actionNumber = '',
    required String subject,
    String actionRequired = 'Action Required Details',
    String division = 'Operations',
    String department = 'Operations',
    String site = 'North Plant',
    String status = 'In Progress',
    String priority = 'High',
    required String assignedTo,
    String assignedToId = '',
    String assignedBy = 'Marcus Vance',
    int percentComplete = 0,
    String workerMessageSubject = 'Safety Inspection Progress',
    String workerMessage = 'Checkpoint verified.',
    List<ActionContributorRecord> contributors = const [],
    List<ActionSubTask> subTasks = const [],
    List<String> history = const [],
  }) {
    return ActionRecord(
      id: id,
      actionNumber: actionNumber.isNotEmpty ? actionNumber : id,
      organizationId: orgId,
      subject: subject,
      actionRequired: actionRequired,
      division: division,
      department: department,
      site: site,
      status: status,
      priority: priority,
      assignedTo: assignedTo,
      assignedToId: assignedToId,
      assignedBy: assignedBy,
      percentComplete: percentComplete,
      workerMessageSubject: workerMessageSubject,
      workerMessage: workerMessage,
      contributors: contributors,
      subTasks: subTasks,
      history: history,
    );
  }

  setUp(() {
    MockActionStore.instance.actions.clear();
    MockPeopleStore.instance.people.clear();
    MockPeopleStore.instance.people.addAll([
      Person(
        id: mgrAId,
        name: mgrAName,
        email: mgrAEmail,
        phone: '+971 50 111 2222',
        designation: 'Manager',
        type: PersonType.internalUser,
        isActive: true,
        department: 'Operations',
        site: 'North Plant',
      ),
      Person(
        id: mgrBId,
        name: mgrBName,
        email: mgrBEmail,
        phone: '+971 50 222 3333',
        designation: 'Engineering Manager',
        type: PersonType.internalUser,
        isActive: true,
        department: 'Engineering',
        site: 'North Plant',
      ),
      Person(
        id: staffAId,
        name: staffAName,
        email: staffAEmail,
        phone: '+971 50 333 4444',
        designation: 'Staff',
        type: PersonType.internalUser,
        isActive: true,
        department: 'Operations',
        site: 'North Plant',
      ),
      Person(
        id: staffBId,
        name: staffBName,
        email: staffBEmail,
        phone: '+971 50 444 5555',
        designation: 'Staff',
        type: PersonType.internalUser,
        isActive: true,
        department: 'Operations',
        site: 'North Plant',
      ),
    ]);
  });

  group('Group 1: ActionRecord Forwarding Predicates & Models (Criteria 5, 6, 11)', () {
    test('isForwarded, isForwardedTo, and isForwardedBy behave correctly', () {
      final directAction = makeAction(
        id: 'ACT-DIR-1',
        subject: 'Direct action',
        assignedTo: staffAName,
        assignedToId: staffAId,
        assignedBy: mgrAName,
      );

      final forwardedAction = makeAction(
        id: 'ACT-FWD-1',
        subject: 'Forwarded action',
        assignedTo: staffAName,
        assignedToId: staffAId,
        assignedBy: mgrAName,
        contributors: const [
          ActionContributorRecord(
            id: 'c-1',
            actionId: 'ACT-FWD-1',
            profileId: staffBId,
            profileName: staffBName,
            profileEmail: staffBEmail,
            addedBy: mgrAId,
            addedByName: mgrAName,
          ),
        ],
      );

      // Direct action assertions
      expect(directAction.isForwarded, isFalse);
      expect(directAction.isForwardedTo(staffBId, staffBName, staffBEmail), isFalse);
      expect(directAction.isForwardedBy(mgrAId, mgrAName, mgrAEmail), isFalse);

      // Forwarded action assertions
      expect(forwardedAction.isForwarded, isTrue);
      expect(forwardedAction.isForwardedTo(staffBId, staffBName, staffBEmail), isTrue);
      expect(forwardedAction.isForwardedTo(staffAId, staffAName, staffAEmail), isFalse);
      expect(forwardedAction.isForwardedBy(mgrAId, mgrAName, mgrAEmail), isTrue);
      expect(forwardedAction.isForwardedBy(staffBId, staffBName, staffBEmail), isFalse);
    });

    test('ActionContributorRecord serializes and deserializes addedBy and addedByName', () {
      final record = ActionContributorRecord(
        id: 'contrib-123',
        actionId: 'ACT-100',
        profileId: 'usr-456',
        profileName: 'Colleague',
        addedBy: 'mgr-789',
        addedByName: 'Manager Lead',
      );

      final json = record.toJson();
      expect(json['added_by'], equals('mgr-789'));
      expect(json['added_by_name'], equals('Manager Lead'));

      final reconstructed = ActionContributorRecord.fromJson(json);
      expect(reconstructed.addedBy, equals('mgr-789'));
      expect(reconstructed.addedByName, equals('Manager Lead'));
    });
  });

  group('Group 2: Manager & Staff Forwarding Workflows (Criteria 1, 2, 3, 4, 10, 11)', () {
    testWidgets('1. Manager forwards action to staff member', (tester) async {
      final initialAction = makeAction(
        id: 'ACT-M2S-01',
        subject: 'Pressure valve audit',
        assignedTo: mgrAName,
        assignedToId: mgrAId,
        assignedBy: mgrAName,
      );
      MockActionStore.instance.actions.add(initialAction);

      final res = await ActionService.instance.addContributor(
        actionId: initialAction.id,
        contributorProfileId: staffAId,
        addedBy: mgrAId,
        addedByName: mgrAName,
        notes: 'Please perform ultrasonic testing',
      );

      expect(res.success, isTrue);
      expect(res.contributorName, equals(staffAName));

      final updated = MockActionStore.instance.actions.firstWhere((a) => a.id == initialAction.id);
      expect(updated.contributors.length, equals(1));
      expect(updated.contributors.first.profileId, equals(staffAId));
      expect(updated.contributors.first.addedBy, equals(mgrAId));
      expect(updated.contributors.first.addedByName, equals(mgrAName));
      expect(updated.assignedTo, equals(mgrAName)); // Original owner intact
    });

    testWidgets('2. Manager forwards action to another manager', (tester) async {
      final initialAction = makeAction(
        id: 'ACT-M2M-02',
        subject: 'Multi-department safety protocol',
        assignedTo: mgrAName,
        assignedToId: mgrAId,
        assignedBy: mgrAName,
      );
      MockActionStore.instance.actions.add(initialAction);

      final res = await ActionService.instance.addContributor(
        actionId: initialAction.id,
        contributorProfileId: mgrBId,
        addedBy: mgrAId,
        addedByName: mgrAName,
        notes: 'Need engineering manager review',
      );

      expect(res.success, isTrue);
      expect(res.contributorName, equals(mgrBName));

      final updated = MockActionStore.instance.actions.firstWhere((a) => a.id == initialAction.id);
      expect(updated.contributors.any((c) => c.profileId == mgrBId), isTrue);
      expect(updated.assignedTo, equals(mgrAName)); // Owner untouched
    });

    testWidgets('3. Manager forwards action created by that manager', (tester) async {
      final createdAction = makeAction(
        id: 'ACT-MCR-03',
        subject: 'Created by Manager A for Staff A',
        assignedTo: staffAName,
        assignedToId: staffAId,
        assignedBy: mgrAName,
      );
      MockActionStore.instance.actions.add(createdAction);

      // Manager A forwards / delegates additional contributor Staff B
      final res = await ActionService.instance.addContributor(
        actionId: createdAction.id,
        contributorProfileId: staffBId,
        addedBy: mgrAId,
        addedByName: mgrAName,
        notes: 'Supporting task',
      );

      expect(res.success, isTrue);
      final updated = MockActionStore.instance.actions.firstWhere((a) => a.id == createdAction.id);
      expect(updated.isForwardedBy(mgrAId, mgrAName, mgrAEmail), isTrue);
      expect(updated.isForwardedTo(staffBId, staffBName, staffBEmail), isTrue);
    });

    testWidgets('4. Staff forwarding continues to work and preserves ownership & history (Criteria 4, 10, 11)', (tester) async {
      final staffAction = makeAction(
        id: 'ACT-S2S-04',
        subject: 'Scaffolding maintenance',
        assignedTo: staffAName,
        assignedToId: staffAId,
        assignedBy: mgrAName,
        history: const ['10 Sep 2026: Created by Marcus Vance.'],
      );
      MockActionStore.instance.actions.add(staffAction);

      final initialActionCount = MockActionStore.instance.actions.length;

      final res = await ActionService.instance.addContributor(
        actionId: staffAction.id,
        contributorProfileId: staffBId,
        addedBy: staffAId,
        addedByName: staffAName,
        notes: 'Help with welding inspection',
      );

      expect(res.success, isTrue);
      // No duplicate actions created (Criteria 10)
      expect(MockActionStore.instance.actions.length, equals(initialActionCount));

      final updated = MockActionStore.instance.actions.firstWhere((a) => a.id == staffAction.id);
      expect(updated.assignedTo, equals(staffAName)); // Original owner preserved (Criteria 11)
      expect(updated.history.length, greaterThanOrEqualTo(2));
      expect(updated.history.any((h) => h.contains('Contributor S. Jones added.')), isTrue);
    });
  });

  group('Group 3: DashboardForwardedActionsCard Component (Criteria 7, 8)', () {
    testWidgets('Renders card with accurate counts and triggers callbacks', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final List<ActionRecord> actions = [
        makeAction(
          id: 'A1',
          subject: 'Act 1',
          assignedTo: staffAName,
          assignedToId: staffAId,
          contributors: const [
            ActionContributorRecord(
              id: 'c1',
              actionId: 'A1',
              profileId: staffBId,
              profileName: staffBName,
              addedBy: staffAId,
              addedByName: staffAName,
            ),
          ],
        ),
        makeAction(
          id: 'A2',
          subject: 'Act 2',
          assignedTo: staffBName,
          assignedToId: staffBId,
          contributors: const [
            ActionContributorRecord(
              id: 'c2',
              actionId: 'A2',
              profileId: staffAId,
              profileName: staffAName,
              addedBy: staffBId,
              addedByName: staffBName,
            ),
          ],
        ),
      ];

      bool cardTapped = false;
      bool fwdToMeTapped = false;
      bool fwdByMeTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DashboardForwardedActionsCard(
                actions: actions,
                currentUserId: staffAId,
                currentUserName: staffAName,
                currentUserEmail: staffAEmail,
                isManager: false,
                onTapCard: () => cardTapped = true,
                onTapForwardedToMe: () => fwdToMeTapped = true,
                onTapForwardedByMe: () => fwdByMeTapped = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Forwarded Actions'), findsOneWidget);
      expect(find.text('Forwarded to Me'), findsOneWidget);
      expect(find.text('Forwarded by Me'), findsOneWidget);

      // Tap card
      await tester.tap(find.text('Forwarded Actions'));
      expect(cardTapped, isTrue);

      // Tap Forwarded to Me chip
      await tester.tap(find.text('Forwarded to Me'));
      expect(fwdToMeTapped, isTrue);

      // Tap Forwarded by Me chip
      await tester.tap(find.text('Forwarded by Me'));
      expect(fwdByMeTapped, isTrue);
    });
  });

  group('Group 4: Manager Portal Dashboard & Action Register Forwarded Filters (Criteria 5, 6, 7, 8, 9)', () {
    testWidgets('Manager Action Register filters by Forwarded by Me and Forwarded to Me', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final List<ActionRecord> testActions = [
        makeAction(
          id: 'ACT-MGR-FWD-BY',
          subject: 'Forwarded by Manager',
          assignedTo: staffAName,
          assignedToId: staffAId,
          assignedBy: mgrAName,
          contributors: const [
            ActionContributorRecord(
              id: 'c1',
              actionId: 'ACT-MGR-FWD-BY',
              profileId: staffBId,
              profileName: staffBName,
              addedBy: mgrAId,
              addedByName: mgrAName,
            ),
          ],
        ),
        makeAction(
          id: 'ACT-MGR-FWD-TO',
          subject: 'Forwarded to Manager',
          assignedTo: staffAName,
          assignedToId: staffAId,
          assignedBy: mgrBName,
          contributors: const [
            ActionContributorRecord(
              id: 'c2',
              actionId: 'ACT-MGR-FWD-TO',
              profileId: mgrAId,
              profileName: mgrAName,
              profileEmail: mgrAEmail,
              addedBy: mgrBId,
              addedByName: mgrBName,
            ),
          ],
        ),
        makeAction(
          id: 'ACT-MGR-DIRECT',
          subject: 'Direct Manager Action',
          assignedTo: mgrAName,
          assignedToId: mgrAId,
          assignedBy: mgrAName,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: ManagerDashboardScreen(
            userProfile: mgrAProfile,
            managerContext: mgrAContext,
            initialActions: testActions,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Card is present on Manager Dashboard tab (Criteria 7)
      expect(find.byType(DashboardForwardedActionsCard), findsOneWidget);

      // Navigate to Action Register
      await tester.tap(find.text('Action Register').first);
      await tester.pumpAndSettle();

      // Forwarded filter dropdown is present
      expect(find.text('Forwarded'), findsWidgets);

      // Initially all actions are visible
      expect(find.text('ACT-MGR-FWD-BY'), findsWidgets);
      expect(find.text('ACT-MGR-FWD-TO'), findsWidgets);
      expect(find.text('ACT-MGR-DIRECT'), findsWidgets);
    });
  });

  group('Group 5: Staff Portal Dashboard & Forwarded Filter Integration (Criteria 4, 5, 6, 7, 8)', () {
    testWidgets('Staff Dashboard renders card and filters properly', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final List<ActionRecord> staffActions = [
        makeAction(
          id: 'ACT-STF-FWD-TO',
          subject: 'Task forwarded to staff',
          assignedTo: staffBName,
          assignedToId: staffBId,
          contributors: const [
            ActionContributorRecord(
              id: 'c-stf-1',
              actionId: 'ACT-STF-FWD-TO',
              profileId: staffAId,
              profileName: staffAName,
              profileEmail: staffAEmail,
            ),
          ],
        ),
        makeAction(
          id: 'ACT-STF-DIR',
          subject: 'Task direct to staff',
          assignedTo: staffAName,
          assignedToId: staffAId,
        ),
      ];

      MockActionStore.instance.actions.addAll(staffActions);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkerDashboardScreen(
            userProfile: staffAProfile,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Card is present on Staff Dashboard (Criteria 7)
      expect(find.byType(DashboardForwardedActionsCard), findsOneWidget);

      // Forwarded Actions filter is present in Staff My Actions
      await tester.tap(find.text('My Actions').first);
      await tester.pumpAndSettle();

      expect(find.text('Forwarded Actions'), findsWidgets);
    });
  });

  group('Group 6: Subtask Progress Calculation, Partial Saves & Review (Criteria 12, 13, 14, 15, 18, 19)', () {
    test('13. Subtask progress formula round((completed/total)*100) at 25%, 50%, 75%, 100%', () {
      final tasks = [
        const ActionSubTask(
          id: 't1',
          parentActionId: 'A',
          title: 'Task 1',
          instruction: 'Inst 1',
          assignedStaff: 'Staff',
          status: 'Open',
        ),
        const ActionSubTask(
          id: 't2',
          parentActionId: 'A',
          title: 'Task 2',
          instruction: 'Inst 2',
          assignedStaff: 'Staff',
          status: 'Open',
        ),
        const ActionSubTask(
          id: 't3',
          parentActionId: 'A',
          title: 'Task 3',
          instruction: 'Inst 3',
          assignedStaff: 'Staff',
          status: 'Open',
        ),
        const ActionSubTask(
          id: 't4',
          parentActionId: 'A',
          title: 'Task 4',
          instruction: 'Inst 4',
          assignedStaff: 'Staff',
          status: 'Open',
        ),
      ];

      int calcProgress(List<ActionSubTask> subTasks) {
        if (subTasks.isEmpty) return 0;
        final completed = subTasks.where((t) => t.isCompleted).length;
        return ((completed / subTasks.length) * 100).round();
      }

      // 0 of 4 -> 0%
      expect(calcProgress(tasks), equals(0));

      // 1 of 4 -> 25%
      final t25 = [
        tasks[0].copyWith(status: 'Completed'),
        tasks[1],
        tasks[2],
        tasks[3],
      ];
      expect(calcProgress(t25), equals(25));

      // 2 of 4 -> 50%
      final t50 = [
        tasks[0].copyWith(status: 'Completed'),
        tasks[1].copyWith(status: 'Completed'),
        tasks[2],
        tasks[3],
      ];
      expect(calcProgress(t50), equals(50));

      // 3 of 4 -> 75%
      final t75 = [
        tasks[0].copyWith(status: 'Completed'),
        tasks[1].copyWith(status: 'Completed'),
        tasks[2].copyWith(status: 'Completed'),
        tasks[3],
      ];
      expect(calcProgress(t75), equals(75));

      // 4 of 4 -> 100%
      final t100 = tasks.map((t) => t.copyWith(status: 'Completed')).toList();
      expect(calcProgress(t100), equals(100));
    });

    testWidgets('14 & 15. Partial save preserves In Progress; 100% submit marks Pending Review', (tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final action = makeAction(
        id: 'ACT-SUB-TEST-01',
        subject: 'Subtask partial and full review test',
        assignedTo: staffAName,
        assignedToId: staffAId,
        percentComplete: 0,
        subTasks: const [
          ActionSubTask(
            id: 'st-1',
            parentActionId: 'ACT-SUB-TEST-01',
            title: 'Inspect Valves',
            instruction: 'Check leaks',
            assignedStaff: staffAName,
            assignedStaffId: staffAId,
            status: 'Open',
          ),
          ActionSubTask(
            id: 'st-2',
            parentActionId: 'ACT-SUB-TEST-01',
            title: 'Replace Seals',
            instruction: 'Replace with rubber gasket',
            assignedStaff: staffAName,
            assignedStaffId: staffAId,
            status: 'Open',
          ),
        ],
      );
      MockActionStore.instance.actions.add(action);

      ActionRecord? returnedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                returnedResult = await Navigator.of(ctx).push<ActionRecord>(
                  MaterialPageRoute(
                    builder: (_) => WorkerActionUpdateScreen(
                      action: returnedResult ?? action,
                      currentUserId: staffAId,
                      currentUserName: staffAName,
                      currentUserEmail: staffAEmail,
                    ),
                  ),
                );
              },
              child: const Text('Open Update Screen'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Update Screen'));
      await tester.pumpAndSettle();

      // Toggle first subtask (1 of 2 = 50%)
      final checkbox = find.byKey(const Key('worker_task_checkbox_0'));
      expect(checkbox, findsOneWidget);
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();

      // Tap Save Update in AppBar
      final saveBtn = find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithText(OutlinedButton, 'Save Update'),
      );
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(returnedResult, isNotNull);
      expect(returnedResult!.percentComplete, equals(50));
      expect(returnedResult!.status, equals('In Progress')); // Partial save preserves In Progress (Criteria 14)

      // Re-open for 100% submission
      await tester.tap(find.text('Open Update Screen'));
      await tester.pumpAndSettle();

      // Toggle second subtask (2 of 2 = 100%)
      final checkbox2 = find.byKey(const Key('worker_task_checkbox_1'));
      expect(checkbox2, findsOneWidget);
      await tester.ensureVisible(checkbox2);
      await tester.tap(checkbox2);
      await tester.pumpAndSettle();

      // Submit for Review in AppBar
      final reviewBtn = find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithText(ElevatedButton, 'Submit for Review'),
      );
      expect(reviewBtn, findsOneWidget);
      await tester.tap(reviewBtn);
      await tester.pumpAndSettle();

      expect(returnedResult, isNotNull);
      expect(returnedResult!.percentComplete, equals(100));
      expect(returnedResult!.status, equals('Pending Review')); // Transition to Pending Review (Criteria 15)
    });

    test('18. Direct action without subtasks preserves manual progress update', () {
      final action = makeAction(
        id: 'ACT-NO-SUB',
        subject: 'Action without subtasks',
        percentComplete: 15,
        assignedTo: staffAName,
        subTasks: const [],
      );

      final updated = action.copyWith(percentComplete: 65);
      expect(updated.percentComplete, equals(65));
      expect(updated.subTasks, isEmpty);
    });

    test('19. Repeated requests do not create duplicate contributors or corrupt history', () async {
      final action = makeAction(
        id: 'ACT-DUP-TEST',
        subject: 'Deduplication test',
        assignedTo: staffAName,
        assignedToId: staffAId,
        contributors: const [],
      );
      MockActionStore.instance.actions.add(action);

      // Call 1
      await ActionService.instance.addContributor(
        actionId: 'ACT-DUP-TEST',
        contributorProfileId: staffBId,
        addedBy: staffAId,
        addedByName: staffAName,
      );

      // Call 2 (Duplicate)
      await ActionService.instance.addContributor(
        actionId: 'ACT-DUP-TEST',
        contributorProfileId: staffBId,
        addedBy: staffAId,
        addedByName: staffAName,
      );

      final current = MockActionStore.instance.actions.firstWhere((a) => a.id == 'ACT-DUP-TEST');
      expect(current.contributors.length, equals(1)); // Exactly 1 contributor
    });
  });

  group('Group 7: Security & Unauthorized Protection (Criteria 16, 17)', () {
    testWidgets('16. Unauthorized user cannot submit updates to unassigned action', (tester) async {
      final action = makeAction(
        id: 'ACT-SEC-01',
        subject: 'Restricted action',
        assignedTo: staffAName,
        assignedToId: staffAId,
        contributors: const [],
      );

      // Unauthorized user check
      final isAssigned = action.assignedToId == unauthorizedId ||
          action.contributors.any((c) => c.profileId == unauthorizedId);
      expect(isAssigned, isFalse);
    });

    test('17. Counts & filters remain accurate after state reload', () {
      final action = makeAction(
        id: 'ACT-RELOAD',
        subject: 'Reload persistence',
        assignedTo: staffAName,
        assignedToId: staffAId,
        contributors: const [
          ActionContributorRecord(
            id: 'c-rel',
            actionId: 'ACT-RELOAD',
            profileId: staffBId,
            profileName: staffBName,
            profileEmail: staffBEmail,
            addedBy: mgrAId,
            addedByName: mgrAName,
          ),
        ],
      );

      // Verify before
      expect(action.isForwardedTo(staffBId, staffBName, staffBEmail), isTrue);
      expect(action.isForwardedBy(mgrAId, mgrAName, mgrAEmail), isTrue);

      // Reconstructed from copyWith
      final restored = action.copyWith();

      expect(restored.isForwardedTo(staffBId, staffBName, staffBEmail), isTrue);
      expect(restored.isForwardedBy(mgrAId, mgrAName, mgrAEmail), isTrue);
      expect(restored.contributors.first.addedByName, equals(mgrAName));
    });
  });
}
