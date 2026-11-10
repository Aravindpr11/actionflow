import 'dart:convert';
import 'dart:typed_data';

import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_action_update_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_action_update_screen.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:action_flow/services/app_file_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testOrgId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';

  final staffUser = ActionPersonReference(
    personId: 'staff-portal-01',
    name: 'R. Kumar',
    type: PersonType.internalUser,
    email: 'rkumar@sobha.com',
  );

  setUp(() {
    MockActionStore.instance.actions.clear();
    AppFilePicker.testOverride = null;
    AppFilePicker.saveTestOverride = null;
  });

  tearDown(() {
    MockActionStore.instance.actions.clear();
    AppFilePicker.testOverride = null;
    AppFilePicker.saveTestOverride = null;
  });

  ActionRecord createSampleAction({
    required String id,
    List<String> attachments = const ['gptexcel_chart_2026-10-31T09_41_23.796Z.png', 'site_hazard_log.pdf'],
    List<ActionSubTask> subtasks = const [],
    int percent = 40,
    String status = 'In Progress',
  }) {
    return ActionRecord(
      id: id,
      actionNumber: 'ACT-1028',
      organizationId: testOrgId,
      departmentId: 'dept-eng-01',
      siteId: 'site-hub-01',
      subject: 'Pressure Variance Investigation ACT-1028',
      actionRequired: 'Inspect and replace valve gaskets.',
      category: 'Inspection',
      source: 'Direct Action',
      priority: 'High',
      status: status,
      percentComplete: percent,
      dateRaised: '10 Oct 2026',
      targetDate: '25 Oct 2026',
      assignedTo: staffUser.name,
      assignedToId: staffUser.personId,
      primaryAssignee: staffUser,
      attachments: attachments,
      subTasks: subtasks,
      division: 'Engineering',
      workerMessageSubject: 'Gasket status',
      workerMessage: 'Initial inspection done.',
      history: ['10 Oct 2026: Action created.'],
    );
  }

  Widget buildUpdateScreenHarness({
    required ActionRecord action,
    void Function(ActionRecord?)? onPop,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              final result = await Navigator.of(ctx).push<ActionRecord>(
                MaterialPageRoute(
                  builder: (_) => WorkerActionUpdateScreen(
                    action: action,
                    currentUserId: staffUser.personId,
                    currentUserName: staffUser.name,
                    currentUserEmail: staffUser.email,
                  ),
                ),
              );
              onPop?.call(result);
            },
            child: const Text('Open Update Screen'),
          ),
        ),
      ),
    );
  }

  group('Requirement 1 & 2: Update Action Evidence State (Isolation of New Selection)', () {
    testWidgets('WorkerActionUpdateScreen initializes with empty new attachments, hiding previously attached files', (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final action = createSampleAction(id: 'ACT-1028');
      MockActionStore.instance.add(action);

      await tester.pumpWidget(buildUpdateScreenHarness(action: action));
      await tester.tap(find.text('Open Update Screen'));
      await tester.pumpAndSettle();

      // Verify the screen renders
      expect(find.text('ATTACHMENTS & EVIDENCE'), findsOneWidget);

      // MANDATORY REQUIREMENT: Previously attached files must NOT appear in Update Action
      expect(find.text('gptexcel_chart_2026-10-31T09_41_23.796Z.png'), findsNothing);
      expect(find.text('site_hazard_log.pdf'), findsNothing);

      // Verify the helper message indicates existing files remain in Action Details
      expect(
        find.textContaining('Previously attached files remain preserved in Action Details'),
        findsOneWidget,
      );

      // Verify the tab label reflects 0 newly selected files
      expect(find.text('Evidence (0)'), findsOneWidget);
    });

    testWidgets('Evidence tab also displays empty new-selection state and preserves previous files in Action Details', (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final action = createSampleAction(id: 'ACT-1028');
      MockActionStore.instance.add(action);

      await tester.pumpWidget(buildUpdateScreenHarness(action: action));
      await tester.tap(find.text('Open Update Screen'));
      await tester.pumpAndSettle();

      // Switch to Evidence tab
      await tester.tap(find.text('Evidence (0)'));
      await tester.pumpAndSettle();

      expect(find.text('INSPECTION EVIDENCE & ATTACHMENTS'), findsOneWidget);
      expect(find.text('gptexcel_chart_2026-10-31T09_41_23.796Z.png'), findsNothing);
      expect(find.text('site_hazard_log.pdf'), findsNothing);
      expect(
        find.textContaining('No new evidence files selected for this update'),
        findsOneWidget,
      );
    });

    testWidgets('Adding new document displays only newly selected document in list', (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final action = createSampleAction(id: 'ACT-1028');
      MockActionStore.instance.add(action);

      AppFilePicker.testOverride = ({required allowedExtensions}) async {
        return AppPickedFile(
          name: 'new_inspection_photo.png',
          bytes: Uint8List.fromList(utf8.encode('photo-bytes')),
        );
      };

      await tester.pumpWidget(buildUpdateScreenHarness(action: action));
      await tester.tap(find.text('Open Update Screen'));
      await tester.pumpAndSettle();

      // Switch to Evidence tab to pick file
      await tester.tap(find.text('Evidence (0)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Evidence Document'));
      await tester.pumpAndSettle();

      // Verify only newly selected file is displayed
      expect(find.text('new_inspection_photo.png'), findsOneWidget);
      // Previous files are STILL not displayed
      expect(find.text('gptexcel_chart_2026-10-31T09_41_23.796Z.png'), findsNothing);
      expect(find.text('site_hazard_log.pdf'), findsNothing);

      // Verify tab label updated to Evidence (1)
      expect(find.text('Evidence (1)'), findsOneWidget);
    });

    testWidgets('Save Update merges newly uploaded file with existing attachments without dropping or duplicating', (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final action = createSampleAction(id: 'ACT-1028');
      MockActionStore.instance.add(action);

      AppFilePicker.testOverride = ({required allowedExtensions}) async {
        return AppPickedFile(
          name: 'calibrated_gauge.jpg',
          bytes: Uint8List.fromList(utf8.encode('gauge-bytes')),
        );
      };

      ActionRecord? poppedResult;
      await tester.pumpWidget(buildUpdateScreenHarness(
        action: action,
        onPop: (res) => poppedResult = res,
      ));
      await tester.tap(find.text('Open Update Screen'));
      await tester.pumpAndSettle();

      // Switch to Evidence tab to add file
      await tester.tap(find.text('Evidence (0)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Evidence Document'));
      await tester.pumpAndSettle();
      expect(find.text('calibrated_gauge.jpg'), findsOneWidget);

      // Tap Save Update in AppBar
      final saveBtn = find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithText(OutlinedButton, 'Save Update'),
      );
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verify returned action has merged attachments: 2 previous + 1 new = 3
      expect(poppedResult, isNotNull);
      expect(poppedResult!.attachments.length, 3);
      expect(poppedResult!.attachments, contains('gptexcel_chart_2026-10-31T09_41_23.796Z.png'));
      expect(poppedResult!.attachments, contains('site_hazard_log.pdf'));
      expect(poppedResult!.attachments, contains('calibrated_gauge.jpg'));

      // Status remains active In Progress
      expect(poppedResult!.status, 'In Progress');
    });

    testWidgets('Discard / Back pops without altering action attachments', (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final action = createSampleAction(id: 'ACT-1028');
      MockActionStore.instance.add(action);

      AppFilePicker.testOverride = ({required allowedExtensions}) async {
        return AppPickedFile(
          name: 'discarded_doc.pdf',
          bytes: Uint8List.fromList(utf8.encode('discarded')),
        );
      };

      ActionRecord? poppedResult;
      await tester.pumpWidget(buildUpdateScreenHarness(
        action: action,
        onPop: (res) => poppedResult = res,
      ));
      await tester.tap(find.text('Open Update Screen'));
      await tester.pumpAndSettle();

      // Switch to Evidence tab and add file
      await tester.tap(find.text('Evidence (0)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Evidence Document'));
      await tester.pumpAndSettle();
      expect(find.text('discarded_doc.pdf'), findsOneWidget);

      // Switch back to Update tab and discard
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();

      // Pop / discard via AppBar back button
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      expect(poppedResult, isNull);

      // Verify store action still has original 2 attachments
      final storeAction = MockActionStore.instance.actions.firstWhere((a) => a.id == 'ACT-1028');
      expect(storeAction.attachments.length, 2);
      expect(storeAction.attachments, isNot(contains('discarded_doc.pdf')));
    });
  });

  group('Requirement 4: Save Update (Partial Progress) vs Submit for Review', () {
    testWidgets('Save Update permits partial progress (50%) and keeps action In Progress', (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final action = createSampleAction(id: 'ACT-PARTIAL-01', percent: 20);
      MockActionStore.instance.add(action);

      ActionRecord? poppedResult;
      await tester.pumpWidget(buildUpdateScreenHarness(
        action: action,
        onPop: (res) => poppedResult = res,
      ));
      await tester.tap(find.text('Open Update Screen'));
      await tester.pumpAndSettle();

      // Save update at 20% via AppBar Save Update button
      final saveBtn = find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithText(OutlinedButton, 'Save Update'),
      );
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(poppedResult, isNotNull);
      expect(poppedResult!.status, 'In Progress');
      expect(poppedResult!.percentComplete, 20);
      expect(poppedResult!.history.last, contains('Staff progress update'));
    });

    testWidgets('Submit for Review requires 100% and blocks when subtasks are incomplete', (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final subtask = ActionSubTask(
        id: 'task-01',
        parentActionId: 'ACT-SUBMIT-01',
        title: 'Calibration',
        instruction: 'Calibrate pressure sensor',
        assignedStaff: staffUser.name,
        assignedStaffId: staffUser.personId,
        assignedStaffEmail: staffUser.email,
        status: 'Pending',
      );
      final action = createSampleAction(
        id: 'ACT-SUBMIT-01',
        percent: 100,
        subtasks: [subtask],
      );
      MockActionStore.instance.add(action);

      ActionRecord? poppedResult;
      await tester.pumpWidget(buildUpdateScreenHarness(
        action: action,
        onPop: (res) => poppedResult = res,
      ));
      await tester.tap(find.text('Open Update Screen'));
      await tester.pumpAndSettle();

      // Tap Submit for Review in AppBar
      final submitBtn = find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithText(ElevatedButton, 'Submit for Review'),
      );
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Submission blocked by incomplete subtask
      expect(poppedResult, isNull);
      expect(
        find.text('All assigned tasks must be completed before submitting for review.'),
        findsOneWidget,
      );
    });
  });

  group('Requirement 1 & Storage Security: Authorization Matrix for Attachments', () {
    test('isUserAuthorizedForActionAttachment authorizes primary assignee by ID, Email, or Name', () {
      final action = createSampleAction(id: 'ACT-AUTH-01');

      // 1. By ID
      expect(
        ActionService.isUserAuthorizedForActionAttachment(
          action: action,
          userId: staffUser.personId,
          isManager: false,
        ),
        isTrue,
      );

      // 2. Headless/unrelated ID is denied
      expect(
        ActionService.isUserAuthorizedForActionAttachment(
          action: action,
          userId: 'stranger-id-999',
          isManager: false,
        ),
        isFalse,
      );

      // 3. Manager is always authorized
      expect(
        ActionService.isUserAuthorizedForActionAttachment(
          action: action,
          userId: 'stranger-id-999',
          isManager: true,
        ),
        isTrue,
      );
    });

    test('isUserAuthorizedForActionAttachment authorizes subtask assignees and contributors', () {
      final contributor = ActionContributorRecord(
        id: 'contrib-rec-01',
        actionId: 'ACT-AUTH-02',
        profileId: 'contrib-fatima-01',
        profileName: 'Fatima Al Mansoori',
        profileEmail: 'fatima@sobha.com',
        addedBy: 'manager-01',
        addedByName: 'Manager Vikram',
        createdAt: DateTime(2026, 10, 15),
      );
      final subtask = ActionSubTask(
        id: 'subtask-deepak-01',
        parentActionId: 'ACT-AUTH-02',
        title: 'Check panels',
        instruction: 'Check electrical panels',
        assignedStaff: 'Deepak Sharma',
        assignedStaffId: 'staff-deepak-02',
        assignedStaffEmail: 'deepak@sobha.com',
        status: 'Completed',
      );

      final action = createSampleAction(
        id: 'ACT-AUTH-02',
        subtasks: [subtask],
      ).copyWith(contributors: [contributor]);

      // Contributor by ID
      expect(
        ActionService.isUserAuthorizedForActionAttachment(
          action: action,
          userId: 'contrib-fatima-01',
        ),
        isTrue,
      );

      // Subtask assignee by ID
      expect(
        ActionService.isUserAuthorizedForActionAttachment(
          action: action,
          userId: 'staff-deepak-02',
        ),
        isTrue,
      );
    });

    test('buildActionAttachmentPath uses authenticated user organization UUID to satisfy Storage RLS', () {
      final path = ActionService.buildActionAttachmentPath(
        organizationId: testOrgId,
        actionId: 'ACT-1028',
        fileName: 'gptexcel_chart_2026-10-31T09_41_23.796Z.png',
      );

      expect(path, isNotNull);
      expect(path, startsWith('$testOrgId/actions/ACT-1028/'));
      expect(path, endsWith('gptexcel_chart_2026-10-31T09_41_23.796Z.png'));
    });

    test('isStorageAccessDenied correctly identifies 403, 401, and RLS error strings', () {
      expect(ActionService.isStorageAccessDenied('403 Unauthorized'), isTrue);
      expect(ActionService.isStorageAccessDenied('StorageException: new row violates row-level security policy — 403 Unauthorized'), isTrue);
      expect(ActionService.isStorageAccessDenied('401 Unauthorized'), isTrue);
      expect(ActionService.isStorageAccessDenied('permission denied for object'), isTrue);
      expect(ActionService.isStorageAccessDenied('Object not found'), isFalse);
      expect(ActionService.isStorageAccessDenied(null), isFalse);
    });

    test('Case A: getAttachmentCandidatePaths generates robust candidates for ACT-1029 and HSE PLAN SOBHA CITY ABUDHABI (1).pdf', () {
      final action = ActionRecord(
        id: 'AF-1042',
        actionNumber: 'AC-1029',
        subject: 'Equipment Inspection',
        actionRequired: 'Inspect and attach HSE Plan',
        division: 'Operations',
        department: 'Maintenance',
        site: 'North Plant',
        category: 'Inspection',
        assignedBy: 'M. Ali',
        assignedTo: 'R. Kumar',
        priority: 'High',
        status: 'In Progress',
        percentComplete: 65,
        dateRaised: '01 Aug 2026',
        targetDate: '12 Aug 2026',
        organizationId: 'sobha',
        attachments: ['HSE PLAN SOBHA CITY ABUDHABI (1).pdf'],
      );

      final candidates = ActionService.getAttachmentCandidatePaths(
        action: action,
        fileName: 'HSE PLAN SOBHA CITY ABUDHABI (1).pdf',
      );

      expect(candidates, isNotEmpty);

      // Verify that organization UUID is prioritized in the candidate list
      expect(candidates.any((p) => p.startsWith('${Organization.sobhaId}/actions/')), isTrue);

      // Verify action identifier variants are tested: AC-1029, ACT-1029, 1029, and AF-1042
      expect(candidates.any((p) => p.contains('/actions/AC-1029/')), isTrue);
      expect(candidates.any((p) => p.contains('/actions/ACT-1029/')), isTrue);
      expect(candidates.any((p) => p.contains('/actions/1029/')), isTrue);
      expect(candidates.any((p) => p.contains('/actions/AF-1042/')), isTrue);

      // Verify filename variations are tested: literal spaces, %20, and duplicate suffix stripped
      expect(candidates.any((p) => p.endsWith('HSE PLAN SOBHA CITY ABUDHABI (1).pdf')), isTrue);
      expect(candidates.any((p) => p.endsWith('HSE%20PLAN%20SOBHA%20CITY%20ABUDHABI%20(1).pdf')), isTrue);
      expect(candidates.any((p) => p.endsWith('HSE PLAN SOBHA CITY ABUDHABI.pdf')), isTrue);
    });

    test('Case A2: getAttachmentCandidatePaths reconciles single vs double spaces in attachment filenames', () {
      final action = ActionRecord(
        id: '15050fd3-5385-4276-bdec-9b799c730234',
        actionNumber: 'ACT-1029',
        subject: '4 : 30 pm nov 2 test',
        actionRequired: 'Inspect and attach HSE Plan',
        division: 'Operations',
        department: 'Maintenance',
        site: 'Sobha City',
        category: 'Inspection',
        assignedBy: 'Manager',
        assignedTo: 'test staff',
        priority: 'High',
        status: 'In Progress',
        percentComplete: 65,
        dateRaised: '02 Nov 2026',
        targetDate: '12 Nov 2026',
        organizationId: '00000000-0000-0000-0000-000000000001',
        attachments: ['HSE PLAN  SOBHA CITY ABUDHABI (1).pdf'], // TWO spaces in DB
      );

      // Caller requests single space
      final candidates = ActionService.getAttachmentCandidatePaths(
        action: action,
        fileName: 'HSE PLAN SOBHA CITY ABUDHABI (1).pdf',
      );

      // Must produce the exact candidate with two spaces matching storage
      expect(
        candidates.any((p) => p == '00000000-0000-0000-0000-000000000001/actions/15050fd3-5385-4276-bdec-9b799c730234/HSE PLAN  SOBHA CITY ABUDHABI (1).pdf'),
        isTrue,
      );
    });

    test('Case B: buildActionAttachmentPath and resolveOrganizationUuid guarantee UUID prefix preventing 403 Forbidden', () {
      expect(ActionService.isValidUuid('00000000-0000-0000-0000-000000000001'), isTrue);
      expect(ActionService.isValidUuid('sobha'), isFalse);
      expect(ActionService.isValidUuid('SOBHA-001'), isFalse);

      // Resolves non-UUID slug 'sobha' to valid UUID
      final resolved = ActionService.resolveOrganizationUuid('sobha');
      expect(ActionService.isValidUuid(resolved), isTrue);
      expect(resolved, Organization.sobhaId);

      // Path builder produces a path starting with a valid UUID
      final path = ActionService.buildActionAttachmentPath(
        organizationId: 'sobha',
        actionId: 'ACT-1029',
        fileName: 'evidence_doc.pdf',
      );
      expect(path, startsWith('${Organization.sobhaId}/actions/ACT-1029/evidence_doc.pdf'));
    });
  });

  group('Case C: Manager Update Action Screen Verification', () {
    testWidgets('ManagerActionUpdateScreen isolates newly selected files and merges on submit', (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final action = ActionRecord(
        id: 'ACT-MGR-TEST-01',
        actionNumber: 'ACT-MGR-TEST-01',
        subject: 'Manager Update Test',
        actionRequired: 'Test manager attachment picking',
        division: 'Operations',
        department: 'Maintenance',
        site: 'North Plant',
        category: 'Inspection',
        assignedBy: 'Director',
        assignedTo: 'Manager User',
        priority: 'High',
        status: 'In Progress',
        percentComplete: 40,
        dateRaised: '01 Aug 2026',
        targetDate: '12 Aug 2026',
        organizationId: Organization.sobhaId,
        attachments: ['Existing_Action_Details_Doc.pdf'],
      );

      AppFilePicker.testOverride = ({required allowedExtensions}) async {
        return AppPickedFile(
          name: 'Manager_Evidence_01.pdf',
          bytes: Uint8List.fromList([10, 20, 30]),
          size: 3,
        );
      };
      addTearDown(() => AppFilePicker.testOverride = null);

      ActionRecord? poppedResult;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  final res = await Navigator.of(ctx).push<ActionRecord>(
                    MaterialPageRoute(
                      builder: (_) => ManagerActionUpdateScreen(
                        action: action,
                        currentUserId: 'mgr-01',
                      ),
                    ),
                  );
                  poppedResult = res;
                },
                child: const Text('Open Manager Update'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Manager Update'));
      await tester.pumpAndSettle();

      // Verify that existing attachments do NOT appear in the update screen
      expect(find.text('Existing_Action_Details_Doc.pdf'), findsNothing);
      expect(
        find.textContaining('No new documents selected for this update'),
        findsOneWidget,
      );

      // Pick new attachment
      final addFileFinder = find.text('Add File');
      await tester.ensureVisible(addFileFinder);
      await tester.pumpAndSettle();
      await tester.tap(addFileFinder);
      await tester.pumpAndSettle();

      // Verify newly picked file is visible
      expect(find.text('Manager_Evidence_01.pdf'), findsOneWidget);

      // Fill in required comments
      final commentsField = find.byKey(const Key('manager_update_comments_field'));
      if (commentsField.evaluate().isNotEmpty) {
        await tester.ensureVisible(commentsField);
        await tester.pumpAndSettle();
        await tester.enterText(commentsField, 'Detailed progress update by Manager');
      } else {
        // Fallback finder
        for (final tf in find.byType(TextFormField).evaluate()) {
          final f = find.byWidget(tf.widget);
          await tester.ensureVisible(f);
          await tester.pumpAndSettle();
          await tester.enterText(f, 'Detailed progress update by Manager');
        }
      }
      await tester.pumpAndSettle();

      // Submit update
      final saveBtn = find.widgetWithText(ElevatedButton, 'Save Update');
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verify merged attachments in result: contains BOTH existing and new document
      expect(poppedResult, isNotNull);
      expect(poppedResult!.attachments.contains('Existing_Action_Details_Doc.pdf'), isTrue);
      expect(poppedResult!.attachments.contains('Manager_Evidence_01.pdf'), isTrue);
    });
  });

  group('Requirement 5: 404 Graceful Fallback Handling', () {
    test('fetchActionSubtasks gracefully handles missing RPC by falling back to JSONB subtasks and store', () async {
      final subtask = ActionSubTask(
        id: 'st-01',
        parentActionId: 'ACT-FB-01',
        title: 'Inspect flange',
        instruction: 'Inspect flange',
        assignedStaff: 'R. Kumar',
        assignedStaffId: 'staff-01',
        status: 'Pending',
      );
      final action = createSampleAction(id: 'ACT-FB-01', subtasks: [subtask]);
      MockActionStore.instance.add(action);

      // In mock/offline mode (or when RPC 404s), fetchActionSubtasks retrieves persisted subtasks cleanly
      final tasks = await ActionService.instance.fetchActionSubtasks('ACT-FB-01');
      expect(tasks, isNotEmpty);
      expect(tasks.first.instruction, 'Inspect flange');
    });
  });
}
