import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_action_update_screen.dart';

void main() {
  setUp(() {
    MockActionStore.instance.actions.clear();
  });

  ActionRecord createTestAction({
    required String id,
    int percent = 0,
    String status = 'In Progress',
    List<ActionSubTask> subtasks = const [],
  }) {
    return ActionRecord(
      id: id,
      actionNumber: id,
      subject: 'Subtask Progress Verification',
      status: status,
      priority: 'High',
      category: 'Inspection',
      assignedTo: 'Staff Tester',
      targetDate: '10 Nov 2026',
      department: 'HSE',
      site: 'Main Facility',
      description: 'Test Description',
      actionRequired: 'Test Action Required',
      division: 'Operations',
      dateRaised: '01 Nov 2026',
      percentComplete: percent,
      workerMessageSubject: 'Safety Inspection Progress',
      workerMessage: 'Inspection checkpoint reached and verified.',
      subTasks: subtasks,
      attachments: const [],
      history: const ['01 Nov 2026: Created'],
    );
  }

  group('Subtask Progress Calculation & Partial Progress Workflow Tests', () {
    test('1. Dynamic subtask progress calculation handles arbitrary task counts correctly', () {
      // 0 of 4 -> 0%
      final tasks4_0 = List<ActionSubTask>.generate(
        4,
        (i) => ActionSubTask(
          id: 'task-4-$i',
          parentActionId: 'ACT-TEST',
          title: 'Subtask $i',
          instruction: 'Instruction $i',
          assignedStaff: 'Staff Tester',
          assignedStaffId: 'staff-user-id',
          status: 'Open',
        ),
      );
      int calcPercent(List<ActionSubTask> list) {
        if (list.isEmpty) return 0;
        final comp = list.where((t) => t.isCompleted).length;
        return ((comp / list.length) * 100).round().clamp(0, 100);
      }

      expect(calcPercent(tasks4_0), equals(0));

      // 1 of 4 -> 25%
      final tasks4_1 = [
        tasks4_0[0].copyWith(status: 'Completed'),
        tasks4_0[1],
        tasks4_0[2],
        tasks4_0[3],
      ];
      expect(calcPercent(tasks4_1), equals(25));

      // 2 of 4 -> 50%
      final tasks4_2 = [
        tasks4_0[0].copyWith(status: 'Completed'),
        tasks4_0[1].copyWith(status: 'Completed'),
        tasks4_0[2],
        tasks4_0[3],
      ];
      expect(calcPercent(tasks4_2), equals(50));

      // 3 of 4 -> 75%
      final tasks4_3 = [
        tasks4_0[0].copyWith(status: 'Completed'),
        tasks4_0[1].copyWith(status: 'Completed'),
        tasks4_0[2].copyWith(status: 'Completed'),
        tasks4_0[3],
      ];
      expect(calcPercent(tasks4_3), equals(75));

      // 4 of 4 -> 100%
      final tasks4_4 = tasks4_0.map((t) => t.copyWith(status: 'Completed')).toList();
      expect(calcPercent(tasks4_4), equals(100));

      // 1 of 2 -> 50%
      final tasks2_1 = [
        const ActionSubTask(id: 't-1', parentActionId: 'A', title: 'T1', instruction: 'I1', assignedStaff: 'Staff Tester', assignedStaffId: 'staff-user-id', status: 'Completed'),
        const ActionSubTask(id: 't-2', parentActionId: 'A', title: 'T2', instruction: 'I2', assignedStaff: 'Staff Tester', assignedStaffId: 'staff-user-id', status: 'Open'),
      ];
      expect(calcPercent(tasks2_1), equals(50));

      // 1 of 6 -> 17% (16.666% rounded to nearest integer)
      final tasks6_1 = List<ActionSubTask>.generate(
        6,
        (i) => ActionSubTask(
          id: 'task-6-$i',
          parentActionId: 'ACT-6',
          title: 'Subtask $i',
          instruction: 'Instruction $i',
          assignedStaff: 'Staff Tester',
          assignedStaffId: 'staff-user-id',
          status: i == 0 ? 'Completed' : 'Open',
        ),
      );
      expect(calcPercent(tasks6_1), equals(17));
    });

    testWidgets(
      '2. Toggling subtasks in WorkerActionUpdateScreen dynamically updates progress percentage',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final testSubtasks = [
          const ActionSubTask(id: 'st-1', parentActionId: 'ACT-SUB-01', title: 'Check equipment calibration', instruction: 'I1', assignedStaff: 'Staff Tester', assignedStaffId: 'staff-user-id', status: 'Open'),
          const ActionSubTask(id: 'st-2', parentActionId: 'ACT-SUB-01', title: 'Review safety checklist', instruction: 'I2', assignedStaff: 'Staff Tester', assignedStaffId: 'staff-user-id', status: 'Open'),
          const ActionSubTask(id: 'st-3', parentActionId: 'ACT-SUB-01', title: 'Verify harness integrity', instruction: 'I3', assignedStaff: 'Staff Tester', assignedStaffId: 'staff-user-id', status: 'Open'),
          const ActionSubTask(id: 'st-4', parentActionId: 'ACT-SUB-01', title: 'Post clearance certificate', instruction: 'I4', assignedStaff: 'Staff Tester', assignedStaffId: 'staff-user-id', status: 'Open'),
        ];

        final action = createTestAction(id: 'ACT-SUB-01', percent: 0, subtasks: testSubtasks);
        MockActionStore.instance.add(action);

        ActionRecord? returnedResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    returnedResult = await Navigator.of(ctx).push<ActionRecord>(
                      MaterialPageRoute(
                        builder: (_) => WorkerActionUpdateScreen(
                          action: action,
                          currentUserId: 'staff-user-id',
                          currentUserName: 'Staff Tester',
                          currentUserEmail: 'staff@example.com',
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

        // Screen is open. Check initial progress is 0%
        expect(find.text('0%'), findsWidgets);

        // Toggle task 0 (1 of 4 completed)
        final checkbox0 = find.byKey(const Key('worker_task_checkbox_0'));
        expect(checkbox0, findsOneWidget);
        await tester.tap(checkbox0);
        await tester.pumpAndSettle();

        // 1 of 4 = 25% complete!
        expect(find.text('25%'), findsWidgets);

        // Toggle task 1 (2 of 4 completed)
        final checkbox1 = find.byKey(const Key('worker_task_checkbox_1'));
        expect(checkbox1, findsOneWidget);
        await tester.tap(checkbox1);
        await tester.pumpAndSettle();

        // 2 of 4 = 50% complete!
        expect(find.text('50%'), findsWidgets);

        // Tap [Save Update] in AppBar to submit partial progress (50%)
        final saveBtn = find.descendant(
          of: find.byType(AppBar),
          matching: find.widgetWithText(OutlinedButton, 'Save Update'),
        );
        expect(saveBtn, findsOneWidget);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        // Verify popped result has active status 'In Progress' and 50% completion
        expect(returnedResult, isNotNull);
        expect(returnedResult!.status, equals('In Progress'));
        expect(returnedResult!.percentComplete, equals(50));
        expect(returnedResult!.subTasks.where((t) => t.isCompleted).length, equals(2));
      },
    );

    testWidgets(
      '3. Submitting 100% completed action transitions to Pending Review',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final completedTasks = [
          const ActionSubTask(id: 'st-1', parentActionId: 'ACT-100', title: 'Task 1', instruction: 'I1', assignedStaff: 'Staff Tester', assignedStaffId: 'staff-user-id', status: 'Completed'),
          const ActionSubTask(id: 'st-2', parentActionId: 'ACT-100', title: 'Task 2', instruction: 'I2', assignedStaff: 'Staff Tester', assignedStaffId: 'staff-user-id', status: 'Completed'),
        ];

        final action = createTestAction(id: 'ACT-100', percent: 100, subtasks: completedTasks);
        MockActionStore.instance.add(action);

        ActionRecord? returnedResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    returnedResult = await Navigator.of(ctx).push<ActionRecord>(
                      MaterialPageRoute(
                        builder: (_) => WorkerActionUpdateScreen(
                          action: action,
                          currentUserId: 'staff-user-id',
                          currentUserName: 'Staff Tester',
                          currentUserEmail: 'staff@example.com',
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

        // Tap [Submit for Review] in AppBar
        final submitBtn = find.descendant(
          of: find.byType(AppBar),
          matching: find.widgetWithText(ElevatedButton, 'Submit for Review'),
        );
        expect(submitBtn, findsOneWidget);
        await tester.tap(submitBtn);
        await tester.pumpAndSettle();

        // Validated: Result transitions to 'Pending Review'
        expect(returnedResult, isNotNull);
        expect(returnedResult!.status, equals('Pending Review'));
        expect(returnedResult!.percentComplete, equals(100));
        expect(returnedResult!.history.any((h) => h.contains('Staff submitted action for Manager review')), isTrue);
      },
    );
  });
}
