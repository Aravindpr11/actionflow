import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    MockPeopleStore.instance.notifications.clear();
  });

  ActionRecord createSampleAction({
    String id = 'ACT-2026-001',
    String subject = 'Replace damaged scaffolding clips in Zone B',
    String assignedTo = 'Marcus Vance',
    int percentComplete = 50,
    List<ActionSubTask> subTasks = const [],
  }) {
    return ActionRecord(
      id: id,
      subject: subject,
      status: 'In Progress',
      priority: 'High',
      category: 'HSE Audit Finding',
      assignedTo: assignedTo,
      targetDate: '14 Sep 2026',
      department: 'Offshore Operations',
      description: 'Safety audit found multiple scaffolding clips showing significant wear.',
      actionRequired:
          'Replace all scaffolding clamps and inspect framework in Zone B.',
      division: 'Production Assets',
      dateRaised: '01 Sep 2026',
      nextFollowUpDate: '10 Sep 2026',
      percentComplete: percentComplete,
      subTasks: subTasks,
    );
  }

  Widget buildDetailsWidget({
    required ActionRecord action,
    bool isWorker = false,
    Size size = const Size(1280, 900),
    VoidCallback? onUpdateAction,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: ActionDetailsScreen(
            action: action,
            isWorker: isWorker,
            onUpdateAction: onUpdateAction,
          ),
        ),
      ),
    );
  }

  group('Forward Action Workflow Tests', () {
    testWidgets(
      'Forward Action button is displayed in both Manager and Staff views',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Manager View
        await tester.pumpWidget(
          buildDetailsWidget(action: createSampleAction(), isWorker: false),
        );
        await tester.pumpAndSettle();
        expect(find.text('Forward Action'), findsOneWidget);

        // Staff View
        await tester.pumpWidget(
          buildDetailsWidget(action: createSampleAction(), isWorker: true),
        );
        await tester.pumpAndSettle();
        expect(find.text('Forward Action'), findsOneWidget);
      },
    );

    testWidgets(
      'Tapping Forward Action displays the 2-choice modal (Forward Entire Action & Forward as Sub-task)',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildDetailsWidget(action: createSampleAction()),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Forward Action'));
        await tester.pumpAndSettle();

        // Modal Title & Subtitle
        expect(find.text('Forward Action — ACT-2026-001'), findsOneWidget);
        expect(
          find.text('Select forwarding or delegation mode'),
          findsOneWidget,
        );

        // Options
        expect(find.text('Forward Action / Add Contributor'), findsOneWidget);
        expect(
          find.text(
            'Add a supporting team member to collaborate. Main ownership remains with the current owner.',
          ),
          findsOneWidget,
        );
        expect(find.text('Forward as Sub-task'), findsOneWidget);
        expect(
          find.text(
            'Keep main action ownership and delegate a weighted sub-task to a team member.',
          ),
          findsOneWidget,
        );
        expect(find.text('Continue'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
      },
    );

    testWidgets(
      'Option 1: Forward Action / Add Contributor adds collaborator and logs history & notification',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final initialNotificationsCount =
            MockPeopleStore.instance.notifications.length;
        final action = createSampleAction(assignedTo: 'Marcus Vance');

        await tester.pumpWidget(buildDetailsWidget(action: action));
        await tester.pumpAndSettle();

        // Tap Forward Action
        await tester.tap(find.text('Forward Action'));
        await tester.pumpAndSettle();

        // Ensure Contributor is selected and tap Continue
        await tester.tap(find.text('Forward Action / Add Contributor'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // Check Forward Contributor Dialog contents
        expect(find.text('Add Contributor — ACT-2026-001'), findsOneWidget);
        expect(find.text('ACTION OWNER (REMAINS RESPONSIBLE)'), findsOneWidget);
        expect(find.text('Marcus Vance'), findsWidgets);
        expect(find.text('Select Contributor *'), findsOneWidget);
        expect(find.text('Add Contributor'), findsOneWidget);

        // Enter optional notes
        final reasonField = find.byType(TextField);
        expect(reasonField, findsOneWidget);
        await tester.enterText(
          reasonField,
          'Reassigning to Lead Specialist for fabrication approval',
        );
        await tester.pumpAndSettle();

        // Confirm Add Contributor
        await tester.tap(find.text('Add Contributor'));
        await tester.pumpAndSettle();

        // Dialog should be dismissed and notification created
        expect(find.text('Add Contributor — ACT-2026-001'), findsNothing);
        expect(
          MockPeopleStore.instance.notifications.length,
          initialNotificationsCount + 1,
        );
        final lastNotification = MockPeopleStore.instance.notifications.first;
        expect(lastNotification.title, 'Added as Contributor');
        expect(lastNotification.message, contains('Marcus Vance'));
      },
    );

    testWidgets(
      'Option 2: Forward as Sub-task delegates a sub-task and logs history & notification',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final initialNotificationsCount =
            MockPeopleStore.instance.notifications.length;
        final action = createSampleAction();

        await tester.pumpWidget(buildDetailsWidget(action: action));
        await tester.pumpAndSettle();

        // Tap Forward Action
        await tester.tap(find.text('Forward Action'));
        await tester.pumpAndSettle();

        // Select Forward as Sub-task option
        await tester.tap(find.text('Forward as Sub-task'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // Check Sub-task Dialog
        expect(find.text('Delegate Sub-task — ACT-2026-001'), findsOneWidget);
        expect(find.text('Sub-task Title *'), findsOneWidget);
        expect(find.text('Detailed Instruction *'), findsOneWidget);
        expect(find.text('Assign Staff *'), findsOneWidget);
        expect(find.text('Progress Weight'), findsOneWidget);

        // Fill in title and instruction
        final textFields = find.byType(TextField);
        expect(textFields, findsNWidgets(3)); // Title, Instruction, Remarks
        await tester.enterText(textFields.at(0), 'Fabricate bracket assembly');
        await tester.enterText(
          textFields.at(1),
          'Weld 4mm steel brackets to specification BS-5950',
        );
        await tester.enterText(
          textFields.at(2),
          'Inspect welds before handover',
        );
        await tester.pumpAndSettle();

        // Tap Create Sub-task button
        await tester.tap(find.text('Create Sub-task'));
        await tester.pumpAndSettle();

        // Dialog dismissed
        expect(find.text('Delegate Sub-task — ACT-2026-001'), findsNothing);

        // Notification generated for staff
        expect(
          MockPeopleStore.instance.notifications.length,
          initialNotificationsCount + 1,
        );
        final lastNotification = MockPeopleStore.instance.notifications.first;
        expect(lastNotification.title, 'New Sub-task Assigned');
        expect(
          lastNotification.message,
          contains('Fabricate bracket assembly'),
        );

        // Check Sub-tasks tab and overview card
        expect(find.text('Sub-tasks'), findsWidgets);
        expect(find.text('Delegated Sub-tasks (1)'), findsOneWidget);
      },
    );

    testWidgets(
      'Sub-task Completion increases parent progress and records remarks without auto-closing',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final initialNotificationsCount =
            MockPeopleStore.instance.notifications.length;
        final subTask = ActionSubTask(
          id: 'ST-001-1',
          parentActionId: 'ACT-2026-001',
          title: 'Fabricate bracket assembly',
          instruction: 'Weld 4mm steel brackets',
          assignedStaff: 'Elena Rostova',
          assignedStaffId: 'USR-004',
          assignedStaffEmail: 'elena.rostova@actionflow.io',
          dueDate: '20 Sep 2026',
          status: 'Open',
          progressWeight: 25,
          remarks: 'Priority component',
        );

        final action = createSampleAction(
          percentComplete: 40,
          subTasks: [subTask],
        );

        await tester.pumpWidget(buildDetailsWidget(action: action));
        await tester.pumpAndSettle();

        // Switch to Sub-tasks tab
        await tester.tap(find.text('Sub-tasks'));
        await tester.pumpAndSettle();

        // Verify Sub-task Card renders
        expect(find.text('Fabricate bracket assembly'), findsOneWidget);
        expect(find.text('Elena Rostova'), findsWidgets);
        expect(find.text('Weight: 25%'), findsOneWidget);
        expect(find.text('Complete Sub-task'), findsOneWidget);

        // Tap Complete Sub-task
        await tester.tap(find.text('Complete Sub-task'));
        await tester.pumpAndSettle();

        // Check Complete Sub-task dialog
        expect(find.text('Complete Sub-task — ST-001-1'), findsOneWidget);
        expect(
          find.text(
            'Completing this sub-task adds +25% progress to parent Action ACT-2026-001.',
          ),
          findsOneWidget,
        );

        final closingRemarksField = find.byType(TextField);
        expect(closingRemarksField, findsNWidgets(2)); // Remarks, Evidence
        await tester.enterText(
          closingRemarksField.at(0),
          'Fabrication completed in workshop. QA approved.',
        );
        await tester.enterText(
          closingRemarksField.at(1),
          'qa_inspection_signoff_2026.pdf',
        );
        await tester.pumpAndSettle();

        // Submit completion
        await tester.tap(find.text('Mark as Completed'));
        await tester.pumpAndSettle();

        // Sub-task is now Completed
        expect(find.text('Completed'), findsWidgets);
        expect(find.text('Complete Sub-task'), findsNothing);

        // Parent progress increased from 40% + 25% = 65%
        expect(find.text('65%'), findsWidgets);

        // Status remains In Progress (not closed)
        expect(find.text('In Progress'), findsWidgets);

        // Notification sent to action owner
        expect(
          MockPeopleStore.instance.notifications.length,
          initialNotificationsCount + 1,
        );
        final completionNotification =
            MockPeopleStore.instance.notifications.first;
        expect(completionNotification.title, 'Sub-task Completed');
        expect(
          completionNotification.message,
          contains('Fabricate bracket assembly'),
        );
      },
    );

    testWidgets('Worker dashboard includes actions delegated as sub-tasks', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Add an action assigned to someone else with sub-task for R. Kumar
      final subTaskAction = ActionRecord(
        id: 'AF-SUB-01',
        subject: 'Calibrate pressure gauges',
        actionRequired: 'Verify calibration tolerances',
        division: 'Operations',
        department: 'Maintenance',
        site: 'North Plant',
        category: 'Inspection',
        assignedTo: 'M. Ali', // Assigned to someone else
        priority: 'High',
        status: 'Open',
        percentComplete: 10,
        dateRaised: '01 Sep 2026',
        targetDate: '15 Sep 2026',
        nextFollowUpDate: '10 Sep 2026',
        subTasks: [
          ActionSubTask(
            id: 'ST-01-1',
            parentActionId: 'AF-SUB-01',
            title: 'Gauge Sensor Check',
            instruction: 'Inspect sensor seal',
            assignedStaff: 'R. Kumar', // Delegated to R. Kumar
            assignedStaffId: 'AFU-001',
            assignedStaffEmail: 'r.kumar@actionflow.demo',
            dueDate: '12 Sep 2026',
            status: 'Open',
            progressWeight: 20,
          ),
        ],
      );
      MockActionStore.instance.actions.add(subTaskAction);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: WorkerDashboardScreen())),
      );
      await tester.pumpAndSettle();

      // Verify the delegated sub-task action appears in the staff dashboard
      expect(find.text('Calibrate pressure gauges'), findsWidgets);

      // Cleanup
      MockActionStore.instance.actions.removeWhere((a) => a.id == 'AF-SUB-01');
    });

    testWidgets(
      'Forward Action responsive layout rendering across widths (1200px, 768px, 400px, 320px)',
      (tester) async {
        final widths = [1200.0, 768.0, 400.0, 320.0];

        for (final width in widths) {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(
            buildDetailsWidget(
              action: createSampleAction(
                subTasks: [
                  ActionSubTask(
                    id: 'ST-001',
                    parentActionId: 'ACT-2026-001',
                    title: 'Responsive Subtask',
                    instruction: 'Check layout',
                    assignedStaff: 'Marcus Vance',
                    assignedStaffId: 'USR-001',
                    assignedStaffEmail: 'marcus@actionflow.io',
                    dueDate: '15 Sep 2026',
                    status: 'Open',
                    progressWeight: 20,
                  ),
                ],
              ),
              size: Size(width, 800),
            ),
          );
          await tester.pumpAndSettle();

          // Ensure Forward Action button is visible and tap
          final forwardBtn = find.text('Forward Action');
          expect(forwardBtn, findsOneWidget);
          await tester.ensureVisible(forwardBtn);
          await tester.tap(forwardBtn);
          await tester.pumpAndSettle();

          expect(find.text('Forward Action — ACT-2026-001'), findsOneWidget);

          // Dismiss Dialog
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();

          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        }
      },
    );
  });
}
