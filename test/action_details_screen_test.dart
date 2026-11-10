import 'dart:typed_data';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/services/app_file_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sampleAction = ActionRecord(
    id: 'ACT-2026-001',
    subject: 'Replace damaged scaffolding clips in Zone B',
    status: 'In Progress',
    priority: 'High',
    category: 'HSE Audit Finding',
    assignedTo: 'Marcus Vance',
    targetDate: '14 Sep 2026',
    department: 'Offshore Operations',
    description: 'Safety audit found multiple scaffolding clips in Zone B showing significant wear and corrosion. Immediate replacement is required.',
    actionRequired:
        'Replace all scaffolding clamps and inspect framework in Zone B.',
    division: 'Production Assets',
    dateRaised: '01 Sep 2026',
    nextFollowUpDate: '10 Sep 2026',
    percentComplete: 65,
    attachments: [
      'Scaffold_Inspection_Report_ZoneB.pdf',
      'Site_Photo_Defect_01.jpg',
    ],
  );

  Widget buildTestableWidget({
    required ActionRecord action,
    Size size = const Size(1280, 900),
    VoidCallback? onUpdateAction,
    String? currentUserId,
    bool isWorker = false,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: ActionDetailsScreen(
            action: action,
            onUpdateAction: onUpdateAction,
            currentUserId: currentUserId,
            isWorker: isWorker,
          ),
        ),
      ),
    );
  }

  group('ActionDetailsScreen - UI & Component Tests', () {
    testWidgets(
      'Renders Top Hero section with circular progress and metadata',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestableWidget(action: sampleAction));
        await tester.pumpAndSettle();

        // Top Hero elements
        expect(find.text('ACT-2026-001'), findsWidgets);
        expect(
          find.text('Replace damaged scaffolding clips in Zone B'),
          findsWidgets,
        );
        expect(find.text('HSE Audit Finding'), findsWidgets);
        expect(find.text('High'), findsWidgets);
        expect(find.text('In Progress'), findsWidgets);
        expect(find.text('65%'), findsWidgets);
        expect(find.text('Completion'), findsOneWidget);

        // Action Header Buttons
        expect(find.text('Edit Action'), findsOneWidget);
        // Case 1: Action assigned to Marcus Vance viewed by manager -> Update Action is omitted
        expect(find.text('Update Action'), findsNothing);
        expect(find.text('Add Follow-up'), findsOneWidget);
      },
    );

    testWidgets(
      'Case 2: Shows Update Action when action is assigned to logged-in user or worker',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildTestableWidget(
            action: sampleAction,
            isWorker: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Submit Update'), findsOneWidget);
      },
    );

    testWidgets('Renders Quick Info Grid', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestableWidget(action: sampleAction));
      await tester.pumpAndSettle();

      // Quick Info labels & values
      expect(find.text('Assigned To'), findsWidgets);
      expect(find.text('Marcus Vance'), findsWidgets);
      expect(find.text('Project / Site'), findsWidgets);
      expect(find.text('Target Date'), findsWidgets);
      expect(find.text('14 Sep 2026'), findsWidgets);
      expect(find.text('Next Follow-up'), findsWidgets);
      expect(find.text('10 Sep 2026'), findsWidgets);
    });

    testWidgets('Renders all Navigation Tabs and switches content smoothly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2400, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestableWidget(action: sampleAction, size: const Size(2400, 1080)),
      );
      await tester.pumpAndSettle();

      // 5 Tabs present
      // Tabs present
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Lifecycle'), findsOneWidget);
      expect(find.text('Sub-tasks'), findsOneWidget);
      expect(find.text('Evidence & Attachments'), findsWidgets);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Comments'), findsOneWidget);
      expect(find.text('Related Actions'), findsWidgets);

      // Default: Overview Tab is active
      expect(find.text('Action Information'), findsOneWidget);
      expect(find.text('ACTION REQUIRED'), findsOneWidget);
      expect(
        find.text(
          'Replace all scaffolding clamps and inspect framework in Zone B.',
        ),
        findsOneWidget,
      );
      expect(find.text('Ownership & Participants'), findsOneWidget);
      expect(find.text('Dates & Milestones'), findsOneWidget);

      // Switch to Evidence & Attachments tab
      await tester.tap(find.text('Evidence & Attachments').first);
      await tester.pumpAndSettle();

      expect(find.text('Upload Evidence'), findsWidgets);
      expect(find.text('Scaffold_Inspection_Report_ZoneB.pdf'), findsOneWidget);
      expect(find.text('Site_Photo_Defect_01.jpg'), findsOneWidget);

      // Switch to History tab
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      expect(find.text('Action Audit Log & Lifecycle History'), findsOneWidget);

      // Switch to Comments tab
      await tester.tap(find.text('Comments'));
      await tester.pumpAndSettle();

      expect(find.text('Action Communication & Notes'), findsOneWidget);
      expect(find.text('Post Note'), findsOneWidget);

      // Switch to Related Actions tab
      await tester.ensureVisible(find.text('Related Actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Related Actions'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Related Actions in'), findsOneWidget);

      // Switch to Lifecycle tab
      await tester.ensureVisible(find.text('Lifecycle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lifecycle'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Action Lifecycle & Audit Trail'),
        findsOneWidget,
      );
    });

    testWidgets('Adding a new comment posts to the comments feed', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestableWidget(action: sampleAction));
      await tester.pumpAndSettle();

      // Go to Comments tab
      await tester.tap(find.text('Comments'));
      await tester.pumpAndSettle();

      // Enter comment text
      final commentField = find.byType(TextField);
      expect(commentField, findsOneWidget);
      await tester.enterText(
        commentField,
        'Replacement clamps arrived on site today.',
      );
      await tester.pumpAndSettle();

      // Tap Post Note
      await tester.tap(find.text('Post Note'));
      await tester.pumpAndSettle();

      // Verify comment appears in the feed
      expect(
        find.text('Replacement clamps arrived on site today.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'Worker Mode (isWorker: true) renders Worker actions toolbar and hides Manager edit controls',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ActionDetailsScreen(action: sampleAction, isWorker: true),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // In worker mode, manager-only edit buttons are hidden
        expect(find.text('Edit Action'), findsNothing);
        expect(find.text('Update Status'), findsNothing);
        expect(find.text('Add Follow-up'), findsNothing);

        // In worker mode, worker action buttons are shown
        expect(find.text('Submit Update'), findsOneWidget);
        expect(find.text('Upload Evidence'), findsWidgets);
        expect(find.text('Add Safety Remark'), findsOneWidget);
      },
    );

    testWidgets(
      'Clearly displays Assigned By and Assigned To in Summary and Ownership area',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final detailedAction = ActionRecord(
          id: 'ACT-ASSIGN-01',
          subject: 'Inspect Turbine Bearing Seals',
          actionRequired: 'Replace worn seals',
          division: 'Operations',
          department: 'Offshore Operations',
          assignedBy: 'R. Kumar',
          assignedTo: 'Marcus Vance',
        );

        await tester.pumpWidget(buildTestableWidget(action: detailedAction));
        await tester.pumpAndSettle();

        // Quick info strip & Ownership card show Assigned By
        expect(find.text('Assigned By'), findsWidgets);
        expect(find.text('R. Kumar'), findsWidgets);
        expect(find.textContaining('Manager'), findsWidgets);

        // Quick info strip & Ownership card show Assigned To
        expect(find.text('Assigned To'), findsWidgets);
        expect(find.text('Marcus Vance'), findsWidgets);
        expect(find.textContaining('Staff'), findsWidgets);
      },
    );
  });

  group('ActionDetailsScreen - Responsive Layout Verification', () {
    testWidgets('Renders with zero overflow at Desktop (1200px)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestableWidget(action: sampleAction, size: const Size(1200, 900)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('ACT-2026-001'), findsWidgets);
    });

    testWidgets('Renders with zero overflow at Tablet (768px)', (tester) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestableWidget(action: sampleAction, size: const Size(768, 1024)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('ACT-2026-001'), findsWidgets);
    });

    testWidgets('Renders with zero overflow at Mobile (400px)', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestableWidget(action: sampleAction, size: const Size(400, 800)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('ACT-2026-001'), findsWidgets);
    });

    testWidgets('Renders with zero overflow at Small Mobile (320px)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestableWidget(action: sampleAction, size: const Size(320, 600)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('ACT-2026-001'), findsWidgets);
    });

    testWidgets(
      'Action Lifecycle tab displays scheduled Follow-Up Date and Start Date events',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final actionWithDates = ActionRecord(
          id: 'ACT-LIFECYCLE-01',
          subject: 'Scaffolding Safety Review',
          actionRequired: 'Inspect scaffolding safety pins',
          division: 'Operations',
          department: 'Offshore Operations',
          assignedBy: 'Safety Manager',
          assignedTo: 'Marcus Vance',
          status: 'In Progress',
          priority: 'High',
          dateRaised: '01 Sep 2026',
          startDate: '05 Sep 2026',
          nextFollowUpDate: '16 Sep 2026',
          targetDate: '25 Sep 2026',
        );

        await tester.pumpWidget(buildTestableWidget(action: actionWithDates));
        await tester.pumpAndSettle();

        // Switch to Lifecycle tab
        final lifecycleTabFinder = find.text('Lifecycle');
        expect(lifecycleTabFinder, findsWidgets);
        await tester.tap(lifecycleTabFinder.first);
        await tester.pumpAndSettle();

        // Verify Follow-Up Date Scheduled event is displayed
        expect(find.text('Follow-Up Date Scheduled'), findsOneWidget);
        expect(find.text('16 Sep 2026'), findsWidgets);
        expect(
          find.text('Next follow-up review scheduled for 16 Sep 2026.'),
          findsOneWidget,
        );

        // Verify Start Date Scheduled event is displayed
        expect(find.text('Work Scheduled / Started'), findsOneWidget);
        expect(find.text('05 Sep 2026'), findsWidgets);
        expect(
          find.text('Action work commencement scheduled for 05 Sep 2026.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Evidence section: Download button triggers real download and shows success SnackBar',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          AppFilePicker.saveTestOverride = null;
        });

        String? downloadedFile;
        AppFilePicker.saveTestOverride = ({
          required String fileName,
          required Uint8List bytes,
          String mimeType = 'application/octet-stream',
        }) async {
          downloadedFile = fileName;
          return true;
        };

        await tester.pumpWidget(
          buildTestableWidget(
            action: sampleAction,
            currentUserId: 'creator-user',
          ),
        );
        await tester.pumpAndSettle();

        // Switch to Evidence & Attachments tab
        final evidenceTabFinder = find.text('Evidence & Attachments');
        expect(evidenceTabFinder, findsWidgets);
        await tester.tap(evidenceTabFinder.first);
        await tester.pumpAndSettle();

        final downloadBtn = find.byKey(
          const Key('download_attachment_Scaffold_Inspection_Report_ZoneB.pdf_btn'),
        );
        expect(downloadBtn, findsOneWidget);
        await tester.ensureVisible(downloadBtn);
        await tester.tap(downloadBtn);
        await tester.pumpAndSettle();

        expect(downloadedFile, equals('Scaffold_Inspection_Report_ZoneB.pdf'));
        expect(
          find.textContaining('Downloaded "Scaffold_Inspection_Report_ZoneB.pdf" successfully.'),
          findsOneWidget,
        );
      },
    );
  });

  group('Action Details Overview - Update Remarks and Roadblocks Display', () {
    testWidgets(
      'Displays all historical work completed remarks and pending roadblocks in Overview tab',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final actionWithUpdates = sampleAction.copyWith(
          progressUpdates: [
            ActionProgressUpdate(
              id: 'upd-01',
              actionId: 'ACT-2026-001',
              updatedById: 'worker-01',
              updatedByName: 'Marcus Vance',
              updateDate: '05 Sep 2026',
              progress: 35,
              status: 'In Progress',
              comments: 'Assembled primary scaffolding poles and base plates.',
              subject: 'Initial Scaffold Rigging',
              messageType: 'Progress Update',
              workCompleted: 'Assembled primary scaffolding poles and base plates.',
              pendingWork: 'Awaiting high-torque clamp deliveries.',
              requirement: '10x 48mm heavy-duty swivel clamps.',
              suggestion: 'Conduct pre-shift toolbox talk on clamp inspection.',
              remarks: 'Weather conditions dry and clear.',
              roleInAction: 'assignee',
              createdAt: DateTime(2026, 9, 5, 9, 30),
            ),
            ActionProgressUpdate(
              id: 'upd-02',
              actionId: 'ACT-2026-001',
              updatedById: 'mgr-01',
              updatedByName: 'David Miller',
              updateDate: '10 Sep 2026',
              progress: 75,
              status: 'In Progress',
              comments: 'Inspected delivered clamps and certified safe installation on Zone B.',
              subject: 'Midway Inspection and Clamp Verification',
              messageType: 'Work Completed',
              workCompleted: 'Inspected delivered clamps and certified safe installation on Zone B.',
              pendingWork: 'Final safety net installation pending.',
              requirement: 'Safety netting roll 50m.',
              suggestion: 'Schedule structural engineer walk-through.',
              remarks: 'All workers adhered to fall protection harnesses.',
              roleInAction: 'manager',
              createdAt: DateTime(2026, 9, 10, 14, 15),
            ),
          ],
        );

        await tester.pumpWidget(buildTestableWidget(action: actionWithUpdates));
        await tester.pumpAndSettle();

        // 1. Work Completed & Progress Remarks section
        expect(find.text('Work Completed & Progress Remarks'), findsOneWidget);
        expect(find.text('2 Entries'), findsOneWidget);

        // Update 2 (Manager update, newest first)
        expect(find.text('Midway Inspection and Clamp Verification'), findsOneWidget);
        expect(find.text('Work Completed'), findsWidgets);
        expect(find.text('75% Complete'), findsOneWidget);
        expect(find.text('David Miller'), findsWidgets);
        expect(find.text('Manager'), findsWidgets);
        expect(
          find.text('Inspected delivered clamps and certified safe installation on Zone B.'),
          findsWidgets,
        );

        // Update 1 (Staff update)
        expect(find.text('Initial Scaffold Rigging'), findsOneWidget);
        expect(find.text('35% Complete'), findsOneWidget);
        expect(find.text('Marcus Vance'), findsWidgets);
        expect(find.text('Staff'), findsWidgets);
        expect(
          find.text('Assembled primary scaffolding poles and base plates.'),
          findsWidgets,
        );

        // 2. Work Pending & Roadblocks section
        expect(find.text('Work Pending & Roadblocks'), findsOneWidget);
        expect(find.text('2 Reports'), findsOneWidget);

        // Pending Work fields from both updates
        expect(find.text('Work Still Pending / Next Steps'), findsWidgets);
        expect(find.text('Final safety net installation pending.'), findsOneWidget);
        expect(find.text('Awaiting high-torque clamp deliveries.'), findsOneWidget);

        // Requirement fields
        expect(find.text('Specific Equipment / Material Requirement'), findsWidgets);
        expect(find.text('Safety netting roll 50m.'), findsOneWidget);
        expect(find.text('10x 48mm heavy-duty swivel clamps.'), findsOneWidget);

        // Suggestion fields
        expect(find.text('Suggestion for HSSE Manager'), findsWidgets);
        expect(find.text('Schedule structural engineer walk-through.'), findsOneWidget);
        expect(find.text('Conduct pre-shift toolbox talk on clamp inspection.'), findsOneWidget);

        // Remarks fields
        expect(find.text('General Safety Remarks'), findsWidgets);
        expect(find.text('All workers adhered to fall protection harnesses.'), findsOneWidget);
        expect(find.text('Weather conditions dry and clear.'), findsOneWidget);
      },
    );

    testWidgets(
      'Displays clean empty states when no updates or roadblocks are submitted',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final emptyAction = sampleAction.copyWith(
          progressUpdates: [],
          workerMessage: '',
          workerMessageSubject: '',
          pendingReason: '',
          requirement: '',
          suggestion: '',
          remarks: '',
          managerMessage: '',
        );

        await tester.pumpWidget(buildTestableWidget(action: emptyAction));
        await tester.pumpAndSettle();

        expect(find.text('Work Completed & Progress Remarks'), findsOneWidget);
        expect(
          find.text('No work completed remarks submitted yet.'),
          findsOneWidget,
        );

        expect(find.text('Work Pending & Roadblocks'), findsOneWidget);
        expect(
          find.text('No pending work or roadblocks reported.'),
          findsOneWidget,
        );
      },
    );
  });
}
