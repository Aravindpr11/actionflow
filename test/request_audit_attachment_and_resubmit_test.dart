import 'package:action_flow/features/requests/models/request_models.dart';
import 'package:action_flow/features/requests/services/request_service.dart';
import 'package:action_flow/services/document_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Issue 1: Audit Trail Human-Readable Details', () {
    test('parses JSON Submitted metadata into readable summary', () {
      const record = RequestHistoryRecord(
        id: 'h-1',
        requestId: 'r-1',
        actorId: 'u-1',
        actorName: 'Manager',
        actorRole: 'Manager',
        action: 'Submitted',
        details:
            '{"title":"test","approval_type":"Sequential","approvers_count":1,"attachments_count":0}',
      );
      expect(
        record.formattedDetails,
        'Submitted for Sequential approval • 1 Approver',
      );
    });

    test('parses JSON with attachments cleanly', () {
      const record = RequestHistoryRecord(
        id: 'h-2',
        requestId: 'r-1',
        actorId: 'u-1',
        actorName: 'Reni',
        actorRole: 'Manager',
        action: 'Submitted',
        details:
            '{"title":"test","approval_type":"Sequential","approvers_count":2,"attachments_count":3}',
      );
      expect(
        record.formattedDetails,
        'Submitted for Sequential approval • 2 Approvers • 3 Attachments',
      );
    });

    test('preserves plain text details unmodified', () {
      const record = RequestHistoryRecord(
        id: 'h-3',
        requestId: 'r-1',
        actorId: 'u-2',
        actorName: 'Approver',
        actorRole: 'Manager',
        action: 'Rejected',
        details: 'Request rejected: Budget exceeds department limit.',
      );
      expect(
        record.formattedDetails,
        'Request rejected: Budget exceeds department limit.',
      );
    });
  });

  group('Issue 2 & 3: Request Attachment Helpers', () {
    test('identifies image and PDF file types correctly', () {
      const imgAtt = RequestAttachmentRecord(
        id: 'att-1',
        requestId: 'r-1',
        fileName: 'photo.PNG',
        filePath: 'org/requests/photo.png',
        fileSize: 1024,
      );
      expect(imgAtt.isImage, isTrue);
      expect(imgAtt.isPdf, isFalse);
      expect(imgAtt.fileExtension, 'png');

      const pdfAtt = RequestAttachmentRecord(
        id: 'att-2',
        requestId: 'r-1',
        fileName: 'report.pdf',
        filePath: 'org/requests/report.pdf',
        fileSize: 2048,
      );
      expect(pdfAtt.isImage, isFalse);
      expect(pdfAtt.isPdf, isTrue);
      expect(pdfAtt.fileExtension, 'pdf');
    });
  });

  group('Issue 4: Requester Resubmit Workflow', () {
    test('resubmits rejected request and resets approval state', () async {
      RequestService.useMockOnly = true;
      final service = RequestService.instance;
      service.clearMockStore();

      final now = DateTime.now();
      final req = RequestRecord(
        id: 'req-test-resubmit',
        displayId: 'REQ-1006',
        organizationId: '00000000-0000-0000-0000-000000000001',
        title: 'Safety Equipment Request',
        description: 'Need new harnesses',
        requestType: RequestType.equipment,
        priority: RequestPriority.high,
        status: RequestStatus.rejected,
        requiredByDate: '2026-11-20',
        createdBy: 'usr-requester-1',
        createdByName: 'Reni Thomas',
        createdByRole: 'Manager',
        rejectionReason: 'Needs specification sheet',
        rejectedBy: 'usr-approver-1',
        rejectedAt: now,
        approvers: [
          RequestApproverRecord(
            id: 'appr-1',
            requestId: 'req-test-resubmit',
            approverId: 'usr-approver-1',
            approverName: 'Director',
            approverRole: 'Admin',
            stepOrder: 1,
            status: 'Rejected',
            decisionComments: 'Needs specification sheet',
            decidedAt: now,
          ),
        ],
        history: [
          RequestHistoryRecord(
            id: 'h-1',
            requestId: 'req-test-resubmit',
            actorId: 'usr-requester-1',
            actorName: 'Reni Thomas',
            actorRole: 'Manager',
            action: 'Submitted',
            details: 'Initial submission',
            createdAt: now,
          ),
          RequestHistoryRecord(
            id: 'h-2',
            requestId: 'req-test-resubmit',
            actorId: 'usr-approver-1',
            actorName: 'Director',
            actorRole: 'Admin',
            action: 'Rejected',
            details: 'Request rejected: Needs specification sheet',
            createdAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      service.seedMockRequest(req);

      final resubmitted = await service.resubmitRequest(
        requestId: 'req-test-resubmit',
        currentUserId: 'usr-requester-1',
        currentUserName: 'Reni Thomas',
        currentUserRole: 'Manager',
        comments: 'Attached manufacturer specification sheet',
        additionalNotes: 'Updated with full compliance specs',
      );

      expect(resubmitted.status, RequestStatus.pending);
      expect(resubmitted.rejectionReason, isNull);
      expect(resubmitted.rejectedBy, isNull);
      expect(resubmitted.additionalNotes, 'Updated with full compliance specs');
      expect(resubmitted.approvers.first.status, 'Pending');
      expect(resubmitted.history.last.action, 'Resubmitted');
      expect(
        resubmitted.history.last.details,
        'Requester responded and resubmitted: Attached manufacturer specification sheet',
      );
    });
  });

  group('Document Upload Error Diagnostics', () {
    test('formatUploadError provides clear upload-specific messages', () {
      final permErr = DocumentService.formatUploadError(
        'permission denied for table documents (42501)',
      );
      expect(permErr, contains('Upload permission denied'));
      expect(permErr, isNot(contains('download')));

      final netErr = DocumentService.formatUploadError(
        'SocketException: Failed host lookup',
      );
      expect(netErr, contains('Network error connecting to storage'));
    });
  });
}
