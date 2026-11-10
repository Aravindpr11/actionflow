import 'dart:convert';
import 'dart:typed_data';

import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_action_update_screen.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const orgId = Organization.sobhaId;

  ActionRecord makeAction({
    required String id,
    String actionNumber = '',
    required String subject,
    String actionRequired = 'Standard verification required',
    String division = 'Operations',
    String department = 'HSE',
    String site = 'Tower A',
    String status = 'In Progress',
    String priority = 'High',
    required String assignedTo,
    String assignedToId = '',
    String assignedBy = 'Marcus Vance',
    int percentComplete = 0,
    String workerMessageSubject = 'Update Subject',
    String workerMessage = 'Work completed description.',
    List<String> attachments = const [],
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
      assignedToId: assignedToId.isNotEmpty ? assignedToId : null,
      assignedBy: assignedBy,
      percentComplete: percentComplete,
      workerMessageSubject: workerMessageSubject,
      workerMessage: workerMessage,
      attachments: attachments,
      contributors: contributors,
      subTasks: subTasks,
      history: history.isNotEmpty ? history : ['01 Nov 2026: Action created.'],
    );
  }

  setUp(() {
    MockActionStore.instance.actions.clear();
    // Ensure mock person exists for contributor resolution
    final existingPeople = MockPeopleStore.instance.people;
    if (!existingPeople.any((p) => p.id == '22222222-2222-2222-2222-222222222222')) {
      existingPeople.add(
        Person(
          id: '22222222-2222-2222-2222-222222222222',
          name: 'Fatima Al Mansoori',
          type: PersonType.internalUser,
          email: 'fatima.m@sobha.com',
          phone: '+971 50 222 3333',
          department: 'HSE',
          site: 'Tower A',
          designation: 'Safety Officer',
          isActive: true,
        ),
      );
    }
  });

  group('Group 1: Contributor RPC Backend Compatibility & Actor Attribution', () {
    test('ActionContributorRecord parses added_by_profile from Supabase join query', () {
      final jsonWithJoinedProfile = {
        'id': 'contrib-uuid-001',
        'action_id': 'action-uuid-101',
        'profile_id': 'user-uuid-202',
        'added_by': 'manager-uuid-303',
        'notes': 'Please review HVAC ventilation filters.',
        'created_at': '2026-11-02T10:00:00.000Z',
        'profile': {
          'id': 'user-uuid-202',
          'full_name': 'Marcus Vance',
          'email': 'marcus.vance@sobha.com',
          'phone': '+971 50 123 4567',
          'designation': 'HSE Specialist',
        },
        'added_by_profile': {
          'id': 'manager-uuid-303',
          'full_name': 'Elena Rostova',
          'email': 'elena.rostova@sobha.com',
        },
      };

      final record = ActionContributorRecord.fromJson(jsonWithJoinedProfile);
      expect(record.id, 'contrib-uuid-001');
      expect(record.actionId, 'action-uuid-101');
      expect(record.profileId, 'user-uuid-202');
      expect(record.profileName, 'Marcus Vance');
      expect(record.profileEmail, 'marcus.vance@sobha.com');
      expect(record.addedBy, 'manager-uuid-303');
      expect(record.addedByName, 'Elena Rostova');
      expect(record.notes, 'Please review HVAC ventilation filters.');
    });

    test('ActionContributorRecord fallback to flat added_by_name when present', () {
      final flatJson = {
        'id': 'contrib-uuid-002',
        'action_id': 'action-uuid-102',
        'profile_id': 'user-uuid-203',
        'added_by': 'staff-uuid-404',
        'added_by_name': 'Farhan Qureshi',
        'notes': 'Delegated task.',
      };

      final record = ActionContributorRecord.fromJson(flatJson);
      expect(record.addedBy, 'staff-uuid-404');
      expect(record.addedByName, 'Farhan Qureshi');
    });

    test('ActionService.addContributor records addedBy and addedByName in Mock store', () async {
      final testAction = makeAction(
        id: 'ACT-VERIFY-001',
        subject: 'Scaffolding Safety Inspection',
        assignedTo: 'Vikram Patel',
        assignedToId: '11111111-1111-1111-1111-111111111111',
        percentComplete: 30,
      );
      MockActionStore.instance.actions.add(testAction);

      final res = await ActionService.instance.addContributor(
        actionId: testAction.id,
        contributorProfileId: '22222222-2222-2222-2222-222222222222',
        addedBy: '11111111-1111-1111-1111-111111111111',
        addedByName: 'Vikram Patel',
        notes: 'Assisting with inspection.',
      );

      expect(res.success, isTrue);
      expect(res.contributorName, 'Fatima Al Mansoori');

      final stored = MockActionStore.instance.actions.firstWhere((a) => a.id == testAction.id);
      expect(stored.contributors.length, 1);
      final c = stored.contributors.first;
      expect(c.profileName, 'Fatima Al Mansoori');
      expect(c.addedByName, 'Vikram Patel');
      expect(stored.history.first, contains('Contributor Fatima Al Mansoori added.'));
    });
  });

  group('Group 2: Evidence Upload Storage Path Resolution & Tenant Isolation', () {
    test('buildActionAttachmentPath prioritizes explicit organization UUID', () {
      const explicitOrg = 'c6131343-a630-4e76-8094-1df4ee99c8bf';
      final path = ActionService.buildActionAttachmentPath(
        organizationId: explicitOrg,
        actionId: 'ACT-9001',
        fileName: 'site_photo.jpg',
      );
      expect(path, '$explicitOrg/actions/ACT-9001/site_photo.jpg');
    });

    test('buildActionAttachmentPath falls back to standard sobhaId when org is generic SOBHA-001 or empty', () {
      final path1 = ActionService.buildActionAttachmentPath(
        organizationId: 'SOBHA-001',
        actionId: 'ACT-9002',
        fileName: 'inspection.pdf',
      );
      expect(path1, '${Organization.sobhaId}/actions/ACT-9002/inspection.pdf');

      final path2 = ActionService.buildActionAttachmentPath(
        organizationId: '',
        actionId: 'ACT-9002',
        fileName: 'inspection.pdf',
      );
      expect(path2, '${Organization.sobhaId}/actions/ACT-9002/inspection.pdf');
    });

    test('uploadActionAttachment handles empty bytes and invalid filenames gracefully', () async {
      final dummyAction = makeAction(
        id: 'ACT-FAIL-01',
        subject: 'Dummy',
        assignedTo: 'Tester',
      );

      final res1 = await ActionService.instance.uploadActionAttachment(
        action: dummyAction,
        fileName: 'test.png',
        bytes: Uint8List(0),
      );
      expect(res1.success, isFalse);
      expect(res1.error, contains('cannot be empty'));

      final res2 = await ActionService.instance.uploadActionAttachment(
        action: dummyAction,
        fileName: '   ',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      expect(res2.success, isFalse);
      expect(res2.error, contains('Invalid attachment filename'));
    });

    test('uploadActionAttachment updates ActionRecord metadata and history in Mock store', () async {
      final action = makeAction(
        id: 'ACT-UPLOAD-TEST',
        subject: 'Permit Verification',
        assignedTo: 'Sunil Verma',
      );
      MockActionStore.instance.actions.add(action);

      final res = await ActionService.instance.uploadActionAttachment(
        action: action,
        fileName: 'permit_doc.pdf',
        bytes: Uint8List.fromList(utf8.encode('PDF Mock Content')),
      );

      expect(res.success, isTrue);
      expect(res.updatedAction, isNotNull);
      expect(res.updatedAction!.attachments, contains('permit_doc.pdf'));
      expect(res.updatedAction!.history.first, contains('permit_doc.pdf'));
    });
  });

  group('Group 3: Multi-Path Storage Candidate Probing (Preview & Download)', () {
    test('getAttachmentCandidatePaths produces comprehensive prioritized locations for action attachment', () {
      final action = makeAction(
        id: '12345678-abcd-ef01-2345-6789abcdef01',
        actionNumber: 'ACT-1025',
        subject: 'Pressure Variance Investigation',
        assignedTo: 'Staff Member',
      );

      const fileName = 'gptexcel_chart_2026-10-31T09_41_23.796Z.png';
      final candidates = ActionService.getAttachmentCandidatePaths(
        action: action,
        fileName: fileName,
      );

      expect(candidates, isNotEmpty);
      // Primary standard path
      expect(candidates.first, '${Organization.sobhaId}/actions/${action.id}/$fileName');
      // Action number path variant
      expect(candidates, contains('${Organization.sobhaId}/actions/ACT-1025/$fileName'));
      // Legacy paths without org prefix
      expect(candidates, contains('actions/${action.id}/$fileName'));
      expect(candidates, contains('actions/ACT-1025/$fileName'));
      // Documents folder fallback
      expect(candidates, contains('${Organization.sobhaId}/documents/$fileName'));
      // Flat root fallback
      expect(candidates, contains(fileName));
    });

    test('getAttachmentCandidatePaths includes reports directory for Excel reports', () {
      final action = makeAction(
        id: '98765432-feed-baba-1234-abcdef987654',
        actionNumber: 'ACT-2050',
        subject: 'Monthly Audit',
        assignedTo: 'Auditor',
      );

      const reportFile = 'ActionFlow_Manager_Report_2026-09-23T19-25-52.xlsx';
      final candidates = ActionService.getAttachmentCandidatePaths(
        action: action,
        fileName: reportFile,
      );

      expect(candidates, contains('${Organization.sobhaId}/reports/$reportFile'));
      expect(candidates, contains('reports/$reportFile'));
      expect(candidates, contains(reportFile));
    });

    test('getAttachmentSignedUrl returns simulated mock URL in offline/mock environment', () async {
      final action = makeAction(
        id: 'ACT-OFFLINE-01',
        subject: 'Offline Test',
        assignedTo: 'User A',
        assignedToId: 'user-a-id',
        attachments: ['evidence_test.png'],
      );

      final res = await ActionService.instance.getAttachmentSignedUrl(
        action: action,
        fileName: 'evidence_test.png',
        userId: 'user-a-id',
      );

      expect(res.success, isTrue);
      expect(res.signedUrl, isNotNull);
      expect(res.signedUrl, contains('evidence_test.png'));
    });

    test('getActionAttachmentBytes returns simulated bytes for authorized assignee', () async {
      final action = makeAction(
        id: 'ACT-OFFLINE-02',
        subject: 'Offline Download Test',
        assignedTo: 'User B',
        assignedToId: 'user-b-id',
        attachments: ['checklist.pdf'],
      );

      final res = await ActionService.instance.getActionAttachmentBytes(
        action: action,
        fileName: 'checklist.pdf',
        userId: 'user-b-id',
      );

      expect(res.success, isTrue);
      expect(res.bytes, isNotNull);
      expect(res.bytes!.isNotEmpty, isTrue);
    });

    test('getActionAttachmentBytes denies access to unauthorized third party', () async {
      final action = makeAction(
        id: 'ACT-OFFLINE-03',
        subject: 'Confidential Safety Investigation',
        assignedTo: 'User C',
        assignedToId: 'user-c-id',
        attachments: ['confidential.pdf'],
      );

      final res = await ActionService.instance.getActionAttachmentBytes(
        action: action,
        fileName: 'confidential.pdf',
        userId: 'unauthorized-intruder-id',
      );

      expect(res.success, isFalse);
      expect(res.error, contains('Permission denied'));
    });
  });

  group('Group 4: Update Action Submission at 100% vs Save Update (Partial Progress)', () {
    final baseAction = makeAction(
      id: 'ACT-SUBMIT-100',
      subject: 'Fire Extinguisher Pressure Inspection',
      assignedTo: 'Kiran Rao',
      percentComplete: 50,
      subTasks: [
        const ActionSubTask(
          id: 'task-1',
          parentActionId: 'ACT-SUBMIT-100',
          title: 'Inspect Sector 3A extinguishers',
          instruction: 'Inspect gauge',
          status: 'Completed',
          assignedStaff: 'Kiran Rao',
        ),
        const ActionSubTask(
          id: 'task-2',
          parentActionId: 'ACT-SUBMIT-100',
          title: 'Inspect Sector 3B extinguishers',
          instruction: 'Inspect gauge',
          status: 'Open',
          assignedStaff: 'Kiran Rao',
        ),
      ],
    );

    Widget buildUpdateWidget({
      required ActionRecord action,
      void Function(ActionRecord?)? onPop,
    }) {
      return MaterialApp(
        theme: ThemeData.light(useMaterial3: true),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  final result = await Navigator.of(context).push<ActionRecord>(
                    MaterialPageRoute(
                      builder: (_) => WorkerActionUpdateScreen(
                        action: action,
                        currentUserId: 'kiran-rao-id',
                        currentUserName: 'Kiran Rao',
                      ),
                    ),
                  );
                  onPop?.call(result);
                },
                child: const Text('Open Update Form'),
              );
            },
          ),
        ),
      );
    }

    testWidgets('Save Update preserves In Progress status and does not advance to Pending Review', (
      tester,
    ) async {
      ActionRecord? popped;
      await tester.pumpWidget(buildUpdateWidget(action: baseAction, onPop: (res) => popped = res));
      await tester.tap(find.text('Open Update Form'));
      await tester.pumpAndSettle();

      // Tap Save Update in AppBar
      final saveBtn = find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithText(OutlinedButton, 'Save Update'),
      );
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(popped, isNotNull);
      expect(popped!.percentComplete, 50);
      expect(popped!.status, 'In Progress');
      expect(popped!.status, isNot('Pending Review'));
      expect(popped!.status, isNot('Completed'));
      expect(popped!.history.last, contains('Staff progress update: 50% (In Progress).'));
    });

    testWidgets('Submit for Review fails when subtasks remain incomplete', (tester) async {
      ActionRecord? popped;
      await tester.pumpWidget(buildUpdateWidget(action: baseAction, onPop: (res) => popped = res));
      await tester.tap(find.text('Open Update Form'));
      await tester.pumpAndSettle();

      // Tap Submit for Review while task-2 is incomplete
      final submitBtn = find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithText(ElevatedButton, 'Submit for Review'),
      );
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(popped, isNull);
      expect(
        find.text('All assigned tasks must be completed before submitting for review.'),
        findsOneWidget,
      );
    });

    testWidgets('Submit for Review succeeds at 100% with all tasks complete, moving to Pending Review with 1 review entry', (
      tester,
    ) async {
      final allTasksCompletedAction = baseAction.copyWith(
        percentComplete: 100,
        subTasks: baseAction.subTasks.map((t) => t.copyWith(status: 'Completed')).toList(),
      );

      ActionRecord? popped;
      await tester.pumpWidget(
        buildUpdateWidget(action: allTasksCompletedAction, onPop: (res) => popped = res),
      );
      await tester.tap(find.text('Open Update Form'));
      await tester.pumpAndSettle();

      // Tap Submit for Review
      final submitBtn = find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithText(ElevatedButton, 'Submit for Review'),
      );
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(popped, isNotNull);
      expect(popped!.percentComplete, 100);
      expect(popped!.status, 'Pending Review');

      // Exactly ONE review entry is logged
      final reviewEntries = popped!.history.where(
        (h) => h.contains('Staff submitted action for Manager review'),
      );
      expect(reviewEntries.length, 1);
    });

    testWidgets('Auto-populates subject and message when blank so form never remains silently stuck', (
      tester,
    ) async {
      final actionWithEmptyRemarks = baseAction.copyWith(
        remarks: '',
        workerMessage: '',
        workerMessageSubject: '',
        percentComplete: 100,
        subTasks: baseAction.subTasks.map((t) => t.copyWith(status: 'Completed')).toList(),
      );

      ActionRecord? popped;
      await tester.pumpWidget(
        buildUpdateWidget(action: actionWithEmptyRemarks, onPop: (res) => popped = res),
      );
      await tester.tap(find.text('Open Update Form'));
      await tester.pumpAndSettle();

      // Submit for Review without typing any text manually
      final submitBtn = find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithText(ElevatedButton, 'Submit for Review'),
      );
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Must succeed and pop
      expect(popped, isNotNull);
      expect(popped!.status, 'Pending Review');
      expect(popped!.percentComplete, 100);
      expect(popped!.workerMessage, contains('Work completed (100%)'));
    });
  });

  group('Group 5: Subtask Progress Formula & Manual Progress Integrity', () {
    test('calculateProgressFromSubtasks calculates round((completed / total) * 100)', () {
      // 1 of 4 = 25%
      expect(((1 / 4) * 100).round(), 25);

      // 2 of 4 = 50%
      expect(((2 / 4) * 100).round(), 50);

      // 3 of 4 = 75%
      expect(((3 / 4) * 100).round(), 75);

      // 4 of 4 = 100%
      expect(((4 / 4) * 100).round(), 100);

      // 1 of 3 = 33%
      expect(((1 / 3) * 100).round(), 33);

      // 2 of 3 = 67%
      expect(((2 / 3) * 100).round(), 67);
    });

    test('Action without subtasks preserves manual progress percentage in submitProgressUpdate', () async {
      final manualAction = makeAction(
        id: 'ACT-MANUAL-01',
        subject: 'General Workplace Assessment',
        assignedTo: 'Tariq Mansoor',
        percentComplete: 20,
      );
      MockActionStore.instance.actions.add(manualAction);

      final updated = await ActionService.instance.submitProgressUpdate(
        actionId: manualAction.id,
        updateDate: DateTime.now(),
        progress: 65,
        status: 'In Progress',
        comments: 'Completed initial walkaround and documented hazards.',
      );

      expect(updated.percentComplete, 65);
      expect(updated.status, 'In Progress');
      expect(updated.progressUpdates.first.progress, 65);
      expect(updated.progressUpdates.first.contributionValue, 45); // 65 - 20
    });
  });
}
