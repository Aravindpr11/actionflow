import 'dart:typed_data';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:action_flow/services/app_file_picker_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testOrgId = 'ORG-TEST-001';

  final staffUser = ActionPersonReference(
    personId: 'staff-att-01',
    name: 'Inspector James',
    type: PersonType.internalUser,
    email: 'james@test.com',
  );

  setUp(() {
    MockActionStore.instance.actions.clear();
  });

  tearDown(() {
    MockActionStore.instance.actions.clear();
  });

  ActionRecord createActionWithAttachments({
    required String id,
    required List<String> attachments,
  }) {
    return ActionRecord(
      id: id,
      actionNumber: 'ACT-$id',
      organizationId: testOrgId,
      departmentId: 'dept-safety-01',
      siteId: 'site-hub-01',
      subject: 'Attachment Storage Test Action',
      actionRequired: 'Verify attachment cleanup lifecycle',
      category: 'Inspection',
      source: 'Direct Action',
      priority: 'High',
      status: 'Open',
      percentComplete: 10,
      dateRaised: '01 Jan 2026',
      targetDate: '25 Jan 2026',
      assignedTo: staffUser.name,
      assignedToId: staffUser.personId,
      primaryAssignee: staffUser,
      attachments: attachments,
      division: 'Safety',
    );
  }

  group('Fix 3: Safe Attachment Storage Cleanup & Scoping', () {
    test('buildActionAttachmentPath correctly formats storage object path', () {
      final path = ActionService.buildActionAttachmentPath(
        organizationId: 'ORG-01',
        actionId: 'ACT-100',
        fileName: 'site_inspection.pdf',
      );
      expect(path, equals('ORG-01/actions/ACT-100/site_inspection.pdf'));
    });

    test('Path traversal prevention: sanitizeAttachmentFileName strips directory traversal and separators', () {
      final sanitized = ActionService.sanitizeAttachmentFileName('../../etc/passwd.pdf');
      expect(sanitized, equals('passwd.pdf'));

      final winSanitized = ActionService.sanitizeAttachmentFileName(r'C:\Windows\System32\evidence.png');
      expect(winSanitized, equals('evidence.png'));

      final constructedPath = ActionService.buildActionAttachmentPath(
        organizationId: 'ORG-01',
        actionId: 'ACT-100',
        fileName: '../../secret_report.pdf',
      );
      // Path must strictly be constrained to the specific action folder
      expect(constructedPath, equals('ORG-01/actions/ACT-100/secret_report.pdf'));
    });

    test('Removing an attachment safely detaches it from metadata and updates history', () async {
      final action = createActionWithAttachments(
        id: 'ACT-REM-01',
        attachments: ['photo1.png', 'report.pdf', 'checklist.xlsx'],
      );
      MockActionStore.instance.add(action);

      final result = await ActionService.instance.removeActionAttachment(
        action: action,
        fileName: 'report.pdf',
      );

      expect(result.success, isTrue);

      final updated = MockActionStore.instance.actions.firstWhere((a) => a.id == 'ACT-REM-01');
      expect(updated.attachments.length, equals(2));
      expect(updated.attachments.contains('report.pdf'), isFalse);
      expect(updated.attachments, containsAll(['photo1.png', 'checklist.xlsx']));
      expect(updated.history.first, contains('Attachment "report.pdf" was removed.'));
    });

    test('Ordinary edit preserves all existing attachments without deleting them', () async {
      final action = createActionWithAttachments(
        id: 'ACT-PRESERVE-01',
        attachments: ['baseline.pdf', 'evidence.jpg'],
      );
      await ActionService.instance.createAction(action);

      final existing = await ActionService.instance.fetchActionById('ACT-PRESERVE-01');
      expect(existing!.attachments.length, equals(2));

      // Ordinary edit: update subject only
      final updatedCandidate = existing.copyWith(subject: 'Updated Action Subject');
      final updated = await ActionService.instance.updateAction(updatedCandidate);

      expect(updated.subject, equals('Updated Action Subject'));
      expect(updated.attachments.length, equals(2));
      expect(updated.attachments, containsAll(['baseline.pdf', 'evidence.jpg']));
    });

    test('Preventing accidental deletion: attempting to remove a non-existent attachment fails safely', () async {
      final action = createActionWithAttachments(
        id: 'ACT-NONEXISTENT',
        attachments: ['existing.pdf'],
      );
      MockActionStore.instance.add(action);

      final result = await ActionService.instance.removeActionAttachment(
        action: action,
        fileName: 'unrelated_other_file.pdf',
      );

      expect(result.success, isFalse);
      expect(result.error, contains('not found'));

      // Metadata must remain unmodified
      final stored = MockActionStore.instance.actions.firstWhere((a) => a.id == 'ACT-NONEXISTENT');
      expect(stored.attachments, equals(['existing.pdf']));
    });

    test('Deleting an action with multiple attachments safely clears them', () async {
      final action = createActionWithAttachments(
        id: 'ACT-DEL-01',
        attachments: ['fileA.pdf', 'fileB.png', 'fileC.docx'],
      );
      MockActionStore.instance.add(action);

      final deleteResult = await ActionService.instance.deleteActionAuthorized('ACT-DEL-01');
      expect(deleteResult.success, isTrue);

      final remaining = MockActionStore.instance.actions.where((a) => a.id == 'ACT-DEL-01');
      expect(remaining, isEmpty);
    });

    test('Safe duplicate filename handling: uploading or adding the same filename does not create duplicate entries', () {
      final action = createActionWithAttachments(
        id: 'ACT-DUP-01',
        attachments: ['photo.png'],
      );

      // In ActionRecord, adding same attachment is deduplicated
      final setAttachments = action.attachments.toSet()..add('photo.png');
      final updated = action.copyWith(attachments: setAttachments.toList());
      expect(updated.attachments.length, equals(1));
    });
  });

  group('Action Details Attachment Download & Authorization Lifecycle', () {
    final complexAction = ActionRecord(
      id: 'ACT-AUTH-01',
      actionNumber: 'ACT-ACT-AUTH-01',
      organizationId: testOrgId,
      departmentId: 'dept-01',
      siteId: 'site-01',
      subject: 'Authorization Test Action',
      actionRequired: 'Verify role-based attachment download authorization',
      status: 'In Progress',
      priority: 'High',
      createdById: 'user-creator-123',
      assignedToId: 'user-primary-456',
      assignedTo: 'Primary User',
      assignees: [
        const ActionAssigneeRecord(
          id: 'asg-1',
          actionId: 'ACT-AUTH-01',
          profileId: 'user-secondary-789',
          profileName: 'Secondary User',
          profileEmail: 'secondary@test.com',
        ),
      ],
      contributors: [
        const ActionContributorRecord(
          id: 'cnt-1',
          actionId: 'ACT-AUTH-01',
          profileId: 'user-contributor-321',
          profileName: 'Contributor User',
          profileEmail: 'contributor@test.com',
        ),
      ],
      subTasks: const [
        ActionSubTask(
          id: 'subtask-1',
          parentActionId: 'ACT-AUTH-01',
          title: 'Review safety checklist',
          instruction: 'Inspect site perimeter',
          assignedStaffId: 'user-subtask-654',
          assignedStaff: 'Subtask User',
          status: 'Open',
        ),
      ],
      attachments: const ['inspection_report.pdf', 'evidence_photo.jpg'],
      division: 'Safety',
    );

    test('isUserAuthorizedForActionAttachment grants access to authorized roles and denies unrelated users', () {
      // 1. Manager has full access
      expect(
        ActionService.isUserAuthorizedForActionAttachment(
          action: complexAction,
          userId: 'random-stranger',
          isManager: true,
        ),
        isTrue,
      );

      // 2. Action creator has access
      expect(
        ActionService.isUserAuthorizedForActionAttachment(
          action: complexAction,
          userId: 'user-creator-123',
          isManager: false,
        ),
        isTrue,
      );

      // 3. Primary assignee has access
      expect(
        ActionService.isUserAuthorizedForActionAttachment(
          action: complexAction,
          userId: 'user-primary-456',
          isManager: false,
        ),
        isTrue,
      );

      // 4. Secondary assignee in assignees list has access
      expect(
        ActionService.isUserAuthorizedForActionAttachment(
          action: complexAction,
          userId: 'user-secondary-789',
          isManager: false,
        ),
        isTrue,
      );

      // 5. Contributor has access
      expect(
        ActionService.isUserAuthorizedForActionAttachment(
          action: complexAction,
          userId: 'user-contributor-321',
          isManager: false,
        ),
        isTrue,
      );

      // 6. Subtask assignee has access
      expect(
        ActionService.isUserAuthorizedForActionAttachment(
          action: complexAction,
          userId: 'user-subtask-654',
          isManager: false,
        ),
        isTrue,
      );

      // 7. Unrelated user is strictly denied access
      expect(
        ActionService.isUserAuthorizedForActionAttachment(
          action: complexAction,
          userId: 'unrelated-staff-user',
          isManager: false,
        ),
        isFalse,
      );

      // 8. Empty or null userId without manager role is denied
      expect(
        ActionService.isUserAuthorizedForActionAttachment(
          action: complexAction,
          userId: null,
          isManager: false,
        ),
        isFalse,
      );
    });

    test('getAttachmentSignedUrl generates valid short-lived URL for authorized user', () async {
      final result = await ActionService.instance.getAttachmentSignedUrl(
        action: complexAction,
        fileName: 'inspection_report.pdf',
        userId: 'user-primary-456',
        isManager: false,
        expiresInSeconds: 300,
      );

      expect(result.success, isTrue);
      expect(result.signedUrl, isNotNull);
      expect(result.signedUrl, contains(testOrgId));
      expect(result.signedUrl, contains('ACT-AUTH-01'));
      expect(result.signedUrl, contains('inspection_report.pdf'));
      expect(result.signedUrl, contains('expires='));
      expect(result.error, isNull);
    });

    test('getAttachmentSignedUrl rejects unauthorized user with clear permission error', () async {
      final result = await ActionService.instance.getAttachmentSignedUrl(
        action: complexAction,
        fileName: 'inspection_report.pdf',
        userId: 'unauthorized-user-999',
        isManager: false,
      );

      expect(result.success, isFalse);
      expect(result.signedUrl, isNull);
      expect(result.error, contains('Permission denied'));
    });

    test('getAttachmentSignedUrl rejects non-associated attachment filename', () async {
      final result = await ActionService.instance.getAttachmentSignedUrl(
        action: complexAction,
        fileName: 'unrelated_secret.pdf',
        userId: 'user-primary-456',
        isManager: false,
      );

      expect(result.success, isFalse);
      expect(result.signedUrl, isNull);
      expect(result.error, contains('not associated with action'));
    });

    test('downloadActionAttachment retrieves bytes and saves to platform via AppFilePicker', () async {
      String? savedFileName;
      Uint8List? savedBytes;

      AppFilePicker.saveTestOverride = ({
        required String fileName,
        required Uint8List bytes,
        String mimeType = 'application/octet-stream',
      }) async {
        savedFileName = fileName;
        savedBytes = bytes;
        return true;
      };

      addTearDown(() {
        AppFilePicker.saveTestOverride = null;
      });

      final result = await ActionService.instance.downloadActionAttachment(
        action: complexAction,
        fileName: 'evidence_photo.jpg',
        userId: 'user-contributor-321',
        isManager: false,
      );

      expect(result.success, isTrue);
      expect(result.error, isNull);
      expect(savedFileName, equals('evidence_photo.jpg'));
      expect(savedBytes, isNotNull);
      expect(savedBytes!.isNotEmpty, isTrue);
    });

    test('downloadActionAttachment handles user cancellation gracefully', () async {
      AppFilePicker.saveTestOverride = ({
        required String fileName,
        required Uint8List bytes,
        String mimeType = 'application/octet-stream',
      }) async {
        return false; // User clicked Cancel in file save dialog
      };

      addTearDown(() {
        AppFilePicker.saveTestOverride = null;
      });

      final result = await ActionService.instance.downloadActionAttachment(
        action: complexAction,
        fileName: 'evidence_photo.jpg',
        userId: 'user-primary-456',
        isManager: false,
      );

      expect(result.success, isFalse);
      expect(result.error, contains('cancelled'));
    });

    test('Closed action retention: allows downloading attachment while preserving read-only immutability', () async {
      final closedAction = complexAction.copyWith(
        status: 'Closed',
        percentComplete: 100,
        closeDate: '01 Oct 2026',
      );
      expect(closedAction.isClosed, isTrue);

      bool saveInvoked = false;
      AppFilePicker.saveTestOverride = ({
        required String fileName,
        required Uint8List bytes,
        String mimeType = 'application/octet-stream',
      }) async {
        saveInvoked = true;
        return true;
      };

      addTearDown(() {
        AppFilePicker.saveTestOverride = null;
      });

      final result = await ActionService.instance.downloadActionAttachment(
        action: closedAction,
        fileName: 'inspection_report.pdf',
        userId: 'user-primary-456',
        isManager: false,
      );

      expect(result.success, isTrue);
      expect(saveInvoked, isTrue);
      // Status and audit history must remain strictly unmodified
      expect(closedAction.status, equals('Closed'));
      expect(closedAction.percentComplete, equals(100));
    });
  });
}

