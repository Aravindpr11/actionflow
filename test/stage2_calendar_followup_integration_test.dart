import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:action_flow/features/calendar/widgets/calendar_view.dart';
import 'package:action_flow/features/calendar/models/calendar_task.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/services/calendar_task_service.dart';

Widget buildTestableWidget(Widget child) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(body: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final refDate = DateTime(2026, 11, 15); // 15 Nov 2026

  final sampleActions = <ActionRecord>[
    ActionRecord(
      id: 'ACT-2001',
      subject: 'Perimeter Safety Fence Maintenance',
      actionRequired: 'Inspect and repair damaged perimeter posts',
      division: 'Construction',
      assignedTo: 'Alice Green',
      targetDate: '25 Nov 2026',
      status: 'In Progress',
      priority: 'High',
      followUps: const [
        ActionFollowUpRecord(
          id: 'fu-2001-1',
          actionId: 'ACT-2001',
          followUpDate: '15 Nov 2026',
          notes: 'Inspect northwest boundary post alignments',
          status: 'Scheduled',
          createdByName: 'Safety Manager',
        ),
        ActionFollowUpRecord(
          id: 'fu-2001-2',
          actionId: 'ACT-2001',
          followUpDate: '20 Nov 2026',
          notes: 'Verify contractor fence installation progress',
          status: 'Scheduled',
          createdByName: 'Safety Manager',
        ),
      ],
    ),
    ActionRecord(
      id: 'ACT-2002',
      subject: 'Ventilation Duct Servicing',
      actionRequired: 'Clean and service main intake filters',
      division: 'Operations',
      assignedTo: 'Bob Vance',
      targetDate: '15 Nov 2026', // Target date is ALSO on 15 Nov 2026
      status: 'Open',
      priority: 'Medium',
      followUps: const [
        ActionFollowUpRecord(
          id: 'fu-2002-1',
          actionId: 'ACT-2002',
          followUpDate: '10 Nov 2026',
          notes: 'Previous checkpoint already completed',
          status: 'Completed',
          createdByName: 'Operations Lead',
        ),
      ],
    ),
    ActionRecord(
      id: 'ACT-2003',
      subject: 'Emergency Generator Load Test',
      actionRequired: 'Perform 4-hour continuous generator load run',
      division: 'Engineering',
      assignedTo: 'Charlie Day',
      targetDate: '30 Nov 2026',
      status: 'Open',
      priority: 'Critical',
      nextFollowUpDate: '18 Nov 2026', // Legacy/single nextFollowUpDate
      followUps: const [],
    ),
  ];

  setUp(() {
    CalendarTaskService.useMockOnly = true;
    MockCalendarTaskStore.instance.clear();
  });

  tearDown(() {
    MockCalendarTaskStore.instance.clear();
  });

  group('Stage 2: Calendar Follow-up Integration Tests', () {
    testWidgets('1. Displays follow-up dates alongside action target dates on same day', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));

      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: sampleActions,
            currentUserId: 'test-user',
            initialDate: refDate, // 15 Nov 2026
          ),
        ),
      );
      await tester.pumpAndSettle();

      // On 15 Nov 2026:
      // ACT-2002 has its target date on 15 Nov.
      // ACT-2001 has its follow-up checkpoint on 15 Nov.
      // Both should appear in the Agenda!
      expect(find.byKey(const Key('calendar_action_item_ACT-2002')), findsOneWidget);
      expect(find.byKey(const Key('calendar_followup_item_fu-2001-1')), findsOneWidget);

      // Verify count pills in agenda
      expect(find.text('1 Actions'), findsOneWidget);
      expect(find.text('1 Follow-ups'), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('2. Distinct visual presentation between action target cards and follow-up cards', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));

      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: sampleActions,
            currentUserId: 'test-user',
            initialDate: refDate,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Header sections are clearly distinguished
      expect(find.text('HSSE Actions (Target Dates)'), findsOneWidget);
      expect(find.text('Follow-up Checkpoints'), findsOneWidget);

      // Follow-up card has the 'FOLLOW-UP' badge
      expect(find.text('FOLLOW-UP'), findsOneWidget);

      // Action card has the 'HSSE' badge
      expect(find.text('HSSE'), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('3. Follow-ups Only filter isolates follow-up checkpoints', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));

      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: sampleActions,
            currentUserId: 'test-user',
            initialDate: refDate,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on 'Follow-ups' filter chip
      final followUpFilter = find.byKey(const Key('filter_type_follow_ups'));
      expect(followUpFilter, findsOneWidget);
      await tester.tap(followUpFilter);
      await tester.pumpAndSettle();

      // Follow-up checkpoint should remain visible
      expect(find.byKey(const Key('calendar_followup_item_fu-2001-1')), findsOneWidget);

      // Action target date should be HIDDEN
      expect(find.byKey(const Key('calendar_action_item_ACT-2002')), findsNothing);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('4. Official Actions filter hides follow-ups', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));

      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: sampleActions,
            currentUserId: 'test-user',
            initialDate: refDate,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on 'Official Actions' filter chip
      final actionFilter = find.byKey(const Key('filter_type_actions'));
      expect(actionFilter, findsOneWidget);
      await tester.tap(actionFilter);
      await tester.pumpAndSettle();

      // Action target date is visible
      expect(find.byKey(const Key('calendar_action_item_ACT-2002')), findsOneWidget);

      // Follow-up checkpoint is HIDDEN
      expect(find.byKey(const Key('calendar_followup_item_fu-2001-1')), findsNothing);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('5. Selecting a follow-up checkpoint opens details dialog with all required information', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));

      ActionRecord? openedAction;
      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: sampleActions,
            currentUserId: 'test-user',
            initialDate: refDate,
            onActionTap: (act) => openedAction = act,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap follow-up card
      final fuCard = find.byKey(const Key('calendar_followup_item_fu-2001-1'));
      expect(fuCard, findsOneWidget);
      await tester.tap(fuCard);
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.text('Follow-up Checkpoint Details'), findsOneWidget);

      // Displays parent action info
      expect(find.text('ACT-2001'), findsWidgets);
      expect(find.text('Perimeter Safety Fence Maintenance'), findsWidgets);

      // Displays scheduled date
      expect(find.text('15 Nov 2026'), findsWidgets);

      // Displays responsible person
      expect(find.text('Alice Green'), findsWidgets);

      // Displays notes
      expect(find.text('Inspect northwest boundary post alignments'), findsWidgets);

      // Displays creator
      expect(find.text('Safety Manager'), findsOneWidget);

      // Tap 'View Action Details' button
      final viewActionBtn = find.byKey(const Key('follow_up_details_view_action_button'));
      expect(viewActionBtn, findsOneWidget);
      await tester.tap(viewActionBtn);
      await tester.pumpAndSettle();

      // Dialog closes and onActionTap is called with parent action
      expect(openedAction, isNotNull);
      expect(openedAction!.id, 'ACT-2001');

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('6. Legacy nextFollowUpDate synthesized and displayed correctly', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));

      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: sampleActions,
            currentUserId: 'test-user',
            initialDate: DateTime(2026, 11, 18), // 18 Nov 2026
          ),
        ),
      );
      await tester.pumpAndSettle();

      // ACT-2003 has nextFollowUpDate = '18 Nov 2026'
      expect(find.text('ACT-2003'), findsWidgets);
      expect(find.text('Emergency Generator Load Test'), findsWidgets);
      expect(find.text('Follow-up: 18 Nov 2026'), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('7. Deduplication: duplicate follow-up records on same action are not duplicated', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));

      final actionWithDuplicates = <ActionRecord>[
        ActionRecord(
          id: 'ACT-DUP',
          subject: 'Duplicate Checkpoint Test',
          actionRequired: 'Verify no duplicate checkpoints rendered',
          division: 'QA',
          assignedTo: 'Dan Brown',
          targetDate: '25 Nov 2026',
          status: 'In Progress',
          followUps: const [
            ActionFollowUpRecord(
              id: 'fu-dup-1',
              actionId: 'ACT-DUP',
              followUpDate: '15 Nov 2026',
              notes: 'Same ID checkpoint',
              status: 'Scheduled',
            ),
            ActionFollowUpRecord(
              id: 'fu-dup-1', // Same ID
              actionId: 'ACT-DUP',
              followUpDate: '15 Nov 2026',
              notes: 'Same ID checkpoint duplicate',
              status: 'Scheduled',
            ),
          ],
        ),
      ];

      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: actionWithDuplicates,
            currentUserId: 'test-user',
            initialDate: refDate,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Only ONE follow-up card should be rendered
      expect(find.byKey(const Key('calendar_followup_item_fu-dup-1')), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('8. Preserves completed and historical follow-ups when selected', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));

      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: sampleActions,
            currentUserId: 'test-user',
            initialDate: DateTime(2026, 11, 10), // 10 Nov 2026 has a completed follow-up
          ),
        ),
      );
      await tester.pumpAndSettle();

      // ACT-2002 completed follow-up on 10 Nov
      final completedCard = find.byKey(const Key('calendar_followup_item_fu-2002-1'));
      expect(completedCard, findsOneWidget);
      expect(find.text('Completed'), findsWidgets);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('9. All Items filter displays Actions, Follow-ups, and Personal Tasks concurrently', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));

      final personalTask = CalendarTask(
        id: 'pt-1',
        userId: 'test-user',
        title: 'Calibrate Noise Meter',
        dueDate: DateTime(2026, 11, 15, 14, 0),
        priority: 'High',
      );
      MockCalendarTaskStore.instance.createTask(personalTask);

      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: sampleActions,
            currentUserId: 'test-user',
            initialDate: refDate,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // All 3 items should appear in agenda:
      // Action target date: ACT-2002
      expect(find.byKey(const Key('calendar_action_item_ACT-2002')), findsOneWidget);
      // Follow-up: ACT-2001 (fu-2001-1)
      expect(find.byKey(const Key('calendar_followup_item_fu-2001-1')), findsOneWidget);
      // Personal task: pt-1
      expect(find.text('Calibrate Noise Meter'), findsOneWidget);

      // Verify all 3 count pills are displayed
      expect(find.text('1 Actions'), findsOneWidget);
      expect(find.text('1 Follow-ups'), findsOneWidget);
      expect(find.text('1 Personal Tasks'), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('10. Personal Tasks Only filter hides actions and follow-ups', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));

      final personalTask = CalendarTask(
        id: 'pt-2',
        userId: 'test-user',
        title: 'Review PPE Storage',
        dueDate: DateTime(2026, 11, 15, 10, 0),
        priority: 'Medium',
      );
      MockCalendarTaskStore.instance.createTask(personalTask);

      await tester.pumpWidget(
        buildTestableWidget(
          ActionFlowCalendarView(
            actions: sampleActions,
            currentUserId: 'test-user',
            initialDate: refDate,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on 'Personal Tasks' filter chip
      await tester.tap(find.byKey(const Key('filter_type_personal_tasks')));
      await tester.pumpAndSettle();

      // Personal task is visible
      expect(find.text('Review PPE Storage'), findsOneWidget);

      // Action and Follow-up are HIDDEN
      expect(find.byKey(const Key('calendar_action_item_ACT-2002')), findsNothing);
      expect(find.byKey(const Key('calendar_followup_item_fu-2001-1')), findsNothing);

      await tester.binding.setSurfaceSize(null);
    });
  });
}
