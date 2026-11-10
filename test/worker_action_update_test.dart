import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_action_update_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final initialAction = ActionRecord(
    id: 'ACT-2026-042',
    subject: 'Inspect high-pressure relief valve seals',
    status: 'In Progress',
    priority: 'High',
    category: 'Safety Inspection',
    assignedTo: 'R. Kumar',
    targetDate: '18 Sep 2026',
    department: 'Field Operations',
    site: 'North Plant Facility',
    description: 'Quarterly safety review detected slight pressure variance.',
    actionRequired: 'Inspect and replace valve gaskets.',
    division: 'Operations',
    dateRaised: '05 Sep 2026',
    percentComplete: 40,
    workerMessageSubject: 'Gaskets inspected',
    workerMessage: 'Initial inspection completed on valve A1.',
    history: ['05 Sep 2026: Action created.'],
    attachments: ['inspection_photo_1.jpg'],
  );

  Widget buildTestWidget({
    required ActionRecord action,
    Size size = const Size(1280, 850),
    ThemeMode themeMode = ThemeMode.light,
    void Function(ActionRecord?)? onPop,
  }) {
    return MaterialApp(
      themeMode: themeMode,
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final result = await Navigator.of(context)
                        .push<ActionRecord>(
                          MaterialPageRoute(
                            builder: (_) =>
                                WorkerActionUpdateScreen(action: action),
                          ),
                        );
                    onPop?.call(result);
                  },
                  child: const Text('Open Update Screen'),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  group('WorkerActionUpdateScreen - Workflow & UI Tests', () {
    testWidgets(
      'Renders breadcrumb, hero summary, guidance banners, and tabs',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 850);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestWidget(action: initialAction));
        await tester.tap(find.text('Open Update Screen'));
        await tester.pumpAndSettle();

        // Breadcrumbs & Header
        expect(find.text('My Actions'), findsWidgets);
        expect(find.text('Update Action'), findsWidgets);
        expect(find.text('ACT-2026-042'), findsWidgets);
        expect(
          find.text('Inspect high-pressure relief valve seals'),
          findsWidgets,
        );
        expect(find.text('High'), findsWidgets);

        // Workflow Action Guide
        expect(find.text('Workflow Action Guide'), findsOneWidget);
        expect(find.text('Save Update (Progress Report)'), findsOneWidget);
        expect(find.text('Submit for Review (Completed Work)'), findsOneWidget);

        // 3 Tabs (Update, Evidence, History)
        expect(find.text('Update'), findsWidgets);
        expect(find.textContaining('Evidence'), findsWidgets);
        expect(find.textContaining('History'), findsWidgets);
        expect(find.text('Requirements'), findsNothing);
        expect(find.text('Suggestions'), findsNothing);

        // Core Panels in Tab 0
        expect(find.text('PROGRESS & STATUS'), findsOneWidget);
        expect(find.text('WORK COMPLETED & PROGRESS REMARKS'), findsOneWidget);

        // Sidebar
        expect(find.text('Action Summary'), findsOneWidget);
        expect(find.text('Quick Actions'), findsOneWidget);
        expect(find.text('Need Assistance?'), findsNothing);
      },
    );

    testWidgets('Switches across 3 tabs (Update, Evidence, History) properly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget(action: initialAction));
      await tester.tap(find.text('Open Update Screen'));
      await tester.pumpAndSettle();

      // Switch to Evidence Tab
      await tester.tap(find.byIcon(Icons.attach_file_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('INSPECTION EVIDENCE & ATTACHMENTS'), findsOneWidget);

      // Switch to History Tab
      await tester.tap(find.byIcon(Icons.history_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('ACTIVITY LOG & AUDIT TRAIL'), findsOneWidget);
      expect(find.textContaining('Action created'), findsOneWidget);

      // Switch back to Update Tab
      await tester.tap(find.byIcon(Icons.edit_note_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('PROGRESS & STATUS'), findsOneWidget);
    });

    testWidgets('Quick action buttons trigger expected tab and state actions', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget(action: initialAction));
      await tester.tap(find.text('Open Update Screen'));
      await tester.pumpAndSettle();

      // Tap 'Mark as Complete (100%)' in Quick Actions
      await tester.tap(find.text('Mark as Complete (100%)'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Progress is set to 100%'), findsOneWidget);

      // Tap 'Attach Evidence' in Quick Actions
      await tester.tap(find.text('Attach Evidence'));
      await tester.pumpAndSettle();
      expect(find.text('INSPECTION EVIDENCE & ATTACHMENTS'), findsOneWidget);
    });

    testWidgets(
      'Normal Progress Update [Save Update] preserves active status and logs progress history without moving to Pending Review',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 850);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        ActionRecord? updatedResult;
        await tester.pumpWidget(
          buildTestWidget(
            action: initialAction,
            onPop: (res) => updatedResult = res,
          ),
        );
        await tester.tap(find.text('Open Update Screen'));
        await tester.pumpAndSettle();

        // Change % Complete dropdown from 40% to 65%
        await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
        await tester.pumpAndSettle();
        await tester.tap(find.text('65%').last);
        await tester.pumpAndSettle();

        // Tap [Save Update] in AppBar
        final saveBtn = find.descendant(
          of: find.byType(AppBar),
          matching: find.widgetWithText(OutlinedButton, 'Save Update'),
        );
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        // Verify result
        expect(updatedResult, isNotNull);
        expect(updatedResult!.percentComplete, 65);
        expect(
          updatedResult!.status,
          'In Progress',
        ); // Must stay In Progress, NOT Pending Review
        expect(updatedResult!.status, isNot('Pending Review'));
        expect(updatedResult!.status, isNot('Completed'));
        expect(
          updatedResult!.history.last,
          contains('Staff progress update: 40% → 65%'),
        );
      },
    );

    testWidgets(
      'Normal Progress Update [Save Update] on Overdue action keeps active Overdue status',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 850);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final overdueAction = initialAction.copyWith(
          status: 'Overdue',
          percentComplete: 40,
        );

        ActionRecord? updatedResult;
        await tester.pumpWidget(
          buildTestWidget(
            action: overdueAction,
            onPop: (res) => updatedResult = res,
          ),
        );
        await tester.tap(find.text('Open Update Screen'));
        await tester.pumpAndSettle();

        // Change % Complete dropdown to 65%
        await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
        await tester.pumpAndSettle();
        await tester.tap(find.text('65%').last);
        await tester.pumpAndSettle();

        // Tap [Save Update] in AppBar
        final saveBtn = find.descendant(
          of: find.byType(AppBar),
          matching: find.widgetWithText(OutlinedButton, 'Save Update'),
        );
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        // Verify result
        expect(updatedResult, isNotNull);
        expect(updatedResult!.status, 'Overdue');
        expect(updatedResult!.percentComplete, 65);
        expect(
          updatedResult!.history.last,
          contains('Staff progress update: 40% → 65%'),
        );
      },
    );

    testWidgets(
      'Submit for Review requires 100% progress and shows validation error if < 100%',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 850);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        ActionRecord? updatedResult;
        await tester.pumpWidget(
          buildTestWidget(
            action: initialAction, // at 40%
            onPop: (res) => updatedResult = res,
          ),
        );
        await tester.tap(find.text('Open Update Screen'));
        await tester.pumpAndSettle();

        // Tap [Submit for Review] in AppBar while percent is 40%
        final submitBtn = find.descendant(
          of: find.byType(AppBar),
          matching: find.widgetWithText(ElevatedButton, 'Submit for Review'),
        );
        await tester.tap(submitBtn);
        await tester.pumpAndSettle();

        // Validation SnackBar must be displayed and navigation NOT popped
        expect(
          find.text(
            'Progress must be 100% when submitting action for Manager review.',
          ),
          findsOneWidget,
        );
        expect(updatedResult, isNull);
      },
    );

    testWidgets(
      'Submit for Review when 100% sets status to Pending Review and records manager review history',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 850);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        ActionRecord? updatedResult;
        await tester.pumpWidget(
          buildTestWidget(
            action: initialAction,
            onPop: (res) => updatedResult = res,
          ),
        );
        await tester.tap(find.text('Open Update Screen'));
        await tester.pumpAndSettle();

        // Set % Complete to 100%
        await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
        await tester.pumpAndSettle();
        await tester.tap(find.text('100%').last);
        await tester.pumpAndSettle();

        // 100% readiness message should appear
        expect(find.textContaining('Progress is set to 100%'), findsOneWidget);

        // Tap [Submit for Review] in AppBar
        final submitBtn = find.descendant(
          of: find.byType(AppBar),
          matching: find.widgetWithText(ElevatedButton, 'Submit for Review'),
        );
        await tester.tap(submitBtn);
        await tester.pumpAndSettle();

        // Verify result
        expect(updatedResult, isNotNull);
        expect(updatedResult!.status, 'Pending Review');
        expect(updatedResult!.percentComplete, 100);
        expect(
          updatedResult!.history.last,
          contains('Staff submitted action for Manager review'),
        );
      },
    );

    testWidgets('Discard Changes pops without updating the action', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      ActionRecord? updatedResult;
      var popped = false;
      await tester.pumpWidget(
        buildTestWidget(
          action: initialAction,
          onPop: (res) {
            popped = true;
            updatedResult = res;
          },
        ),
      );
      await tester.tap(find.text('Open Update Screen'));
      await tester.pumpAndSettle();

      // Scroll to Discard Changes and tap it
      await tester.scrollUntilVisible(
        find.text('Discard Changes'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Discard Changes'));
      await tester.pumpAndSettle();

      expect(popped, isTrue);
      expect(updatedResult, isNull);
    });
  });

  group('WorkerActionUpdateScreen - Responsive Layout & Overflow Tests', () {
    testWidgets('Renders with 0 overflow at Desktop (1200px)', (tester) async {
      tester.view.physicalSize = const Size(1200, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget(action: initialAction));
      await tester.tap(find.text('Open Update Screen'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Workflow Action Guide'), findsOneWidget);
    });

    testWidgets('Renders with 0 overflow at Tablet (768px)', (tester) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget(action: initialAction));
      await tester.tap(find.text('Open Update Screen'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Workflow Action Guide'), findsOneWidget);
    });

    testWidgets('Renders with 0 overflow at Mobile (400px)', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget(action: initialAction));
      await tester.tap(find.text('Open Update Screen'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Workflow Action Guide'), findsOneWidget);
    });

    testWidgets('Renders with 0 overflow at Small Mobile (320px)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget(action: initialAction));
      await tester.tap(find.text('Open Update Screen'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Workflow Action Guide'), findsOneWidget);
    });
  });

  group(
    'WorkerDashboardScreen - Integration with Separated Update Workflow',
    () {
      testWidgets(
        'Dashboard reflects correct pending review vs active metrics',
        (tester) async {
          tester.view.physicalSize = const Size(1280, 850);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await tester.pumpWidget(
            const MaterialApp(home: WorkerDashboardScreen()),
          );
          await tester.pumpAndSettle();

          // Verify summary cards exist and are consistent
          expect(find.text('Total Actions'), findsWidgets);
          expect(find.text('In Progress'), findsWidgets);
          expect(find.textContaining('Review'), findsWidgets);
        },
      );
    },
  );
}
