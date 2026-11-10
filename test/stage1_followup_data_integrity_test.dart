import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/widgets/dashboard_attention_section.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/widgets/dashboard_upcoming_followups.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/action_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const orgId = Organization.sobhaId;
  const managerId = 'mgr-stage1-integrity';

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final tomorrow = today.add(const Duration(days: 1));

  String fmt(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final d = dt.day.toString().padLeft(2, '0');
    return '$d ${months[dt.month - 1]} ${dt.year}';
  }

  ActionRecord makeAction({
    required String id,
    required String actionNumber,
    required String subject,
    String status = 'Open',
    int percentComplete = 10,
    String targetDate = '15 Dec 2026',
    String nextFollowUpDate = '',
    List<ActionFollowUpRecord> followUps = const [],
    String assignedTo = 'Staff Member',
    String assignedToId = 'staff-stage1-001',
  }) {
    return ActionRecord(
      id: id,
      actionNumber: actionNumber,
      subject: subject,
      actionRequired: 'Follow-up data integrity verification',
      division: 'Operations',
      status: status,
      priority: 'High',
      department: 'HSE',
      site: 'Dubai Marina',
      targetDate: targetDate,
      nextFollowUpDate: nextFollowUpDate,
      followUps: followUps,
      assignedTo: assignedTo,
      assignedToId: assignedToId,
      organizationId: orgId,
      createdById: managerId,
      percentComplete: percentComplete,
    );
  }

  setUp(() {
    MockActionStore.instance.actions.clear();
    ActionService.instance.mockFollowUpPersistenceShouldFail = false;
    ActionService.instance.mockFollowUpPersistenceFailureReason = null;
  });

  tearDown(() {
    ActionService.instance.mockFollowUpPersistenceShouldFail = false;
    ActionService.instance.mockFollowUpPersistenceFailureReason = null;
  });

  group('Stage 1 Follow-up Data Integrity & Reconciliation Tests', () {
    test('1. Editing action creates or updates correct checkpoint', () async {
      final initialAction = makeAction(
        id: 'ACT-STAGE1-01',
        actionNumber: 'ACT-1001',
        subject: 'Initial Checkpoint Action',
        nextFollowUpDate: '10 Nov 2026',
        followUps: [
          ActionFollowUpRecord(
            id: 'fu-init',
            actionId: 'ACT-STAGE1-01',
            followUpDate: '10 Nov 2026',
            notes: 'Initial scheduled date',
            status: 'Scheduled',
          ),
        ],
      );
      MockActionStore.instance.add(initialAction);

      // Edit action with a new nextFollowUpDate
      final updatedAction = initialAction.copyWith(
        nextFollowUpDate: '20 Nov 2026',
      );

      final result = await ActionService.instance.updateAction(updatedAction);

      expect(result.nextFollowUpDate, equals('20 Nov 2026'));
      expect(result.followUps.length, equals(2));
      expect(result.followUps.any((f) => f.followUpDate == '20 Nov 2026'), isTrue);

      final inStore = MockActionStore.instance.actions.firstWhere((a) => a.id == 'ACT-STAGE1-01');
      expect(inStore.nextFollowUpDate, equals('20 Nov 2026'));
      expect(inStore.followUps.length, equals(2));
    });

    test('2. Existing checkpoints remain preserved when follow-up date changes', () async {
      final multiCheckpointAction = makeAction(
        id: 'ACT-STAGE1-02',
        actionNumber: 'ACT-1002',
        subject: 'Multi Checkpoint Action',
        nextFollowUpDate: '15 Nov 2026',
        followUps: [
          ActionFollowUpRecord(
            id: 'fu-chk-1',
            actionId: 'ACT-STAGE1-02',
            followUpDate: '10 Nov 2026',
            notes: 'First Milestone Inspection',
            status: 'Scheduled',
          ),
          ActionFollowUpRecord(
            id: 'fu-chk-2',
            actionId: 'ACT-STAGE1-02',
            followUpDate: '15 Nov 2026',
            notes: 'Second Milestone Inspection',
            status: 'Scheduled',
          ),
        ],
      );
      MockActionStore.instance.add(multiCheckpointAction);

      // Update to a 3rd follow-up date
      final updated = multiCheckpointAction.copyWith(
        nextFollowUpDate: '25 Nov 2026',
      );

      final saved = await ActionService.instance.updateAction(updated);

      expect(saved.followUps.length, equals(3));
      // First checkpoint is preserved
      final f1 = saved.followUps.firstWhere((f) => f.id == 'fu-chk-1');
      expect(f1.followUpDate, equals('10 Nov 2026'));
      expect(f1.notes, equals('First Milestone Inspection'));

      // Second checkpoint is preserved
      final f2 = saved.followUps.firstWhere((f) => f.id == 'fu-chk-2');
      expect(f2.followUpDate, equals('15 Nov 2026'));
      expect(f2.notes, equals('Second Milestone Inspection'));

      // Third checkpoint is newly created
      expect(saved.followUps.any((f) => f.followUpDate == '25 Nov 2026'), isTrue);
    });

    test('3. Completed checkpoints are not reset when action or dates change', () async {
      final actionWithCompleted = makeAction(
        id: 'ACT-STAGE1-03',
        actionNumber: 'ACT-1003',
        subject: 'Action with Completed Checkpoint',
        nextFollowUpDate: '05 Nov 2026',
        followUps: [
          ActionFollowUpRecord(
            id: 'fu-done',
            actionId: 'ACT-STAGE1-03',
            followUpDate: '05 Nov 2026',
            notes: 'Completed scaffolding review',
            status: 'Completed',
            actualProgress: 50,
            completedAt: DateTime.now().subtract(const Duration(hours: 2)),
          ),
        ],
      );
      MockActionStore.instance.add(actionWithCompleted);

      // Update nextFollowUpDate to a new future date
      final updated = actionWithCompleted.copyWith(
        nextFollowUpDate: '12 Nov 2026',
      );

      final saved = await ActionService.instance.updateAction(updated);

      final completedItem = saved.followUps.firstWhere((f) => f.id == 'fu-done');
      expect(completedItem.status, equals('Completed'));
      expect(completedItem.isCompleted, isTrue);
      expect(completedItem.actualProgress, equals(50));
      expect(completedItem.completedAt, isNotNull);

      // New checkpoint was added for the new date
      expect(saved.followUps.length, equals(2));
      expect(saved.followUps.any((f) => f.followUpDate == '12 Nov 2026'), isTrue);
    });

    test('4. Cancelled checkpoints remain correctly classified and excluded from active KPI', () async {
      final actionWithCancelled = makeAction(
        id: 'ACT-STAGE1-04',
        actionNumber: 'ACT-1004',
        subject: 'Action with Cancelled Checkpoint',
        nextFollowUpDate: '08 Nov 2026',
        followUps: [
          ActionFollowUpRecord(
            id: 'fu-cancel',
            actionId: 'ACT-STAGE1-04',
            followUpDate: '08 Nov 2026',
            notes: 'Cancelled due to bad weather',
            status: 'Cancelled',
          ),
        ],
      );
      MockActionStore.instance.add(actionWithCancelled);

      // Verify that cancelled checkpoint status is preserved
      final saved = await ActionService.instance.updateAction(actionWithCancelled);
      final cancelledItem = saved.followUps.firstWhere((f) => f.id == 'fu-cancel');
      expect(cancelledItem.status, equals('Cancelled'));
      expect(cancelledItem.isCompleted, isFalse);
    });

    test('5. Old checkpoint does not hide future nextFollowUpDate (Shadowing bug fix)', () {
      // Action has an overdue follow-up from yesterday, but updated nextFollowUpDate is TODAY
      final actionWithOldAndNew = makeAction(
        id: 'ACT-STAGE1-05',
        actionNumber: 'ACT-1005',
        subject: 'Action with Past Checkpoint and Today Follow-up',
        nextFollowUpDate: fmt(today),
        followUps: [
          ActionFollowUpRecord(
            id: 'fu-old-overdue',
            actionId: 'ACT-STAGE1-05',
            followUpDate: fmt(yesterday),
            notes: 'Overdue checkpoint from yesterday',
            status: 'Scheduled',
          ),
        ],
      );

      // 1. Test in DashboardUpcomingFollowups widget logic
      // Build widget with this action
      // The Today tab MUST show (1) and include ACT-1005, NOT be ignored!
      DashboardUpcomingFollowups(
        actions: [actionWithOldAndNew],
        onActionTap: (_) {},
        onOpenCalendar: () {},
      );

      // 2. Test in DashboardAttentionSection logic
      // In attention section, getFollowUpsToday MUST include this action
      // even though followUps contains an overdue item!
      expect(
        actionWithOldAndNew.nextFollowUpDate,
        equals(fmt(today)),
      );
    });

    test('6. Duplicate checkpoints are not generated for identical dates', () async {
      final action = makeAction(
        id: 'ACT-STAGE1-06',
        actionNumber: 'ACT-1006',
        subject: 'Deduplication Action',
        nextFollowUpDate: '18 Nov 2026',
        followUps: [
          ActionFollowUpRecord(
            id: 'fu-dedup',
            actionId: 'ACT-STAGE1-06',
            followUpDate: '18 Nov 2026',
            notes: 'Existing 18 Nov checkpoint',
            status: 'Scheduled',
          ),
        ],
      );
      MockActionStore.instance.add(action);

      // Save again with the exact same nextFollowUpDate
      final saved1 = await ActionService.instance.updateAction(action);
      expect(saved1.followUps.length, equals(1));

      // Save a second time
      final saved2 = await ActionService.instance.updateAction(saved1);
      expect(saved2.followUps.length, equals(1));
      expect(saved2.followUps.first.id, equals('fu-dedup'));
    });

    testWidgets('7. Today follow-up appears in correct dashboard card with two-line details',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final actionToday = makeAction(
        id: 'ACT-STAGE1-07',
        actionNumber: 'ACT-1007',
        subject: 'Fire Door Integrity Check',
        assignedTo: 'Robert Brown',
        targetDate: '30 Nov 2026',
        nextFollowUpDate: fmt(today),
        followUps: [
          ActionFollowUpRecord(
            id: 'fu-today-card',
            actionId: 'ACT-STAGE1-07',
            followUpDate: fmt(today),
            notes: 'Inspect seal strips',
            status: 'Scheduled',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DashboardAttentionSection(
                actions: [actionToday],
                onActionTap: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on Follow-Ups Today pill
      await tester.tap(find.text('Follow-Ups Today'));
      await tester.pumpAndSettle();

      // Verify action ID and subject appear
      expect(find.text('ACT-1007'), findsWidgets);
      expect(find.text('Fire Door Integrity Check'), findsWidgets);

      // Verify two-line subtitle details: notes and assigned person
      expect(find.textContaining('Inspect seal strips'), findsOneWidget);
      expect(find.textContaining('Robert Brown'), findsOneWidget);
      expect(find.byIcon(Icons.schedule_rounded), findsWidgets);
    });

    testWidgets('8. Past follow-ups do not appear as upcoming or due today',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final actionOverdueOnly = makeAction(
        id: 'ACT-STAGE1-08',
        actionNumber: 'ACT-1008',
        subject: 'Historical Past Checkpoint',
        nextFollowUpDate: fmt(yesterday),
        followUps: [
          ActionFollowUpRecord(
            id: 'fu-past-only',
            actionId: 'ACT-STAGE1-08',
            followUpDate: fmt(yesterday),
            notes: 'Should only be overdue, never upcoming',
            status: 'Scheduled',
          ),
        ],
      );

      // Test DashboardUpcomingFollowups
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardUpcomingFollowups(
              actions: [actionOverdueOnly],
              onActionTap: (_) {},
              onOpenCalendar: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Today (0), Tomorrow (0)
      expect(find.text('Today (0)'), findsOneWidget);
      expect(find.text('Tomorrow (0)'), findsOneWidget);
      expect(find.text('No scheduled follow-ups'), findsOneWidget);
      expect(find.text('ACT-1008'), findsNothing);
    });

    test('9. Manager and Staff visibility remains correct and synchronized', () async {
      final sharedAction = makeAction(
        id: 'ACT-STAGE1-09',
        actionNumber: 'ACT-1009',
        subject: 'Shared Excavation Shoring Action',
        assignedTo: 'Staff Specialist',
        assignedToId: 'staff-user-09',
        nextFollowUpDate: fmt(tomorrow),
        followUps: [
          ActionFollowUpRecord(
            id: 'fu-shared-chk',
            actionId: 'ACT-STAGE1-09',
            followUpDate: fmt(tomorrow),
            notes: 'Soil compaction verification',
            status: 'Scheduled',
          ),
        ],
      );
      MockActionStore.instance.add(sharedAction);

      // Manager view: queries all actions in organization
      final managerActions = MockActionStore.instance.actions
          .where((a) => a.organizationId == orgId)
          .toList();
      final managerAction = managerActions.firstWhere((a) => a.id == 'ACT-STAGE1-09');
      expect(managerAction.followUps.length, equals(1));
      expect(managerAction.nextFollowUpDate, equals(fmt(tomorrow)));

      // Staff view: queries actions assigned to staff-user-09
      final staffActions = MockActionStore.instance.actions
          .where((a) => a.assignedToId == 'staff-user-09' || a.assignedTo == 'Staff Specialist')
          .toList();
      expect(staffActions.length, equals(1));
      final staffAction = staffActions.first;
      expect(staffAction.followUps.length, equals(1));
      expect(staffAction.followUps.first.notes, equals('Soil compaction verification'));
      expect(staffAction.nextFollowUpDate, equals(fmt(tomorrow)));
    });

    test('10. Persistence failure throws ActionFollowUpPersistenceException safely', () async {
      final action = makeAction(
        id: 'ACT-STAGE1-10',
        actionNumber: 'ACT-1010',
        subject: 'Persistence Failure Test Action',
        nextFollowUpDate: '10 Nov 2026',
      );
      MockActionStore.instance.add(action);

      // Trigger test hook to simulate network or RLS failure during follow-up persistence
      ActionService.instance.mockFollowUpPersistenceShouldFail = true;
      ActionService.instance.mockFollowUpPersistenceFailureReason =
          'Simulated database timeout on action_follow_ups checkpoint insertion';

      expect(
        () async => await ActionService.instance.updateAction(
          action.copyWith(nextFollowUpDate: '28 Nov 2026'),
        ),
        throwsA(
          isA<ActionFollowUpPersistenceException>().having(
            (e) => e.message,
            'message',
            contains('Simulated database timeout'),
          ),
        ),
      );

      // Reset test hook
      ActionService.instance.mockFollowUpPersistenceShouldFail = false;
      ActionService.instance.mockFollowUpPersistenceFailureReason = null;

      // Ensure subsequent calls work normally without error
      final successfulUpdate = await ActionService.instance.updateAction(
        action.copyWith(nextFollowUpDate: '28 Nov 2026'),
      );
      expect(successfulUpdate.nextFollowUpDate, equals('28 Nov 2026'));
    });

    testWidgets('Bonus: Shadowing fix in DashboardUpcomingFollowups widget renders future date when past checkpoint exists',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Action has an overdue checkpoint from yesterday, but updated nextFollowUpDate is TODAY
      final actionWithOldAndToday = makeAction(
        id: 'ACT-STAGE1-SHADOW',
        actionNumber: 'ACT-1099',
        subject: 'Unshadowed Today Action',
        nextFollowUpDate: fmt(today),
        followUps: [
          ActionFollowUpRecord(
            id: 'fu-old-shadow',
            actionId: 'ACT-STAGE1-SHADOW',
            followUpDate: fmt(yesterday),
            notes: 'Old checkpoint from yesterday',
            status: 'Scheduled',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardUpcomingFollowups(
              actions: [actionWithOldAndToday],
              onActionTap: (_) {},
              onOpenCalendar: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Today (1) MUST be rendered because today's nextFollowUpDate was not shadowed by yesterday's checkpoint!
      expect(find.text('Today (1)'), findsOneWidget);
      expect(find.text('ACT-1099'), findsOneWidget);
      expect(find.text('Unshadowed Today Action'), findsOneWidget);
    });
  });
}
