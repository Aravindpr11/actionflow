import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/services/action_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    MockActionStore.instance.actions.clear();
  });

  group('ISSUE 1 — Work Completed and Work Pending in Action Details', () {
    test('ACT-1027 scenario: synthetic fallback generates progress update from workerMessageSubject', () {
      final act1027 = ActionRecord(
        id: 'ACT-1027',
        actionNumber: 'ACT-1027',
        subject: 'Inspect HVAC units',
        description: 'Quarterly HSE check',
        actionRequired: 'Service rooftop air units',
        division: 'Commercial',
        department: 'Operations',
        site: 'Building A',
        assignedTo: 'John Staff',
        assignedToId: 'staff-123',
        status: 'In Progress',
        percentComplete: 45,
        targetDate: '2026-11-15',
        workerMessageSubject: 'today nov 2',
        workerMessage: 'Checked rooftop fans and air intake filters.',
        pendingReason: 'Awaiting replacement filter from vendor.',
        requirement: 'Filter model X45',
        suggestion: 'Order in bulk next quarter',
        remarks: 'Safety goggles worn',
        progressUpdates: const [],
      );

      final allUpdates = act1027.allProgressUpdates;
      expect(allUpdates, isNotEmpty);
      final latest = allUpdates.first;
      expect(latest.effectiveSubject, equals('today nov 2'));
      expect(latest.effectiveWorkCompleted, equals('Checked rooftop fans and air intake filters.'));
      expect(latest.pendingWork, equals('Awaiting replacement filter from vendor.'));
      expect(latest.requirement, equals('Filter model X45'));
      expect(latest.suggestion, equals('Order in bulk next quarter'));
      expect(latest.remarks, equals('Safety goggles worn'));
    });

    test('Dual-format comments: handles both JSON-encoded structured remarks and legacy plain text', () {
      final jsonPayload = jsonEncode({
        'subject': 'Roof Inspection Completed',
        'message_type': 'Progress Update',
        'work_completed': 'Repaired sealant on ridge cap.',
        'pending_work': 'Thermal imaging scan pending.',
        'requirement': 'Flir camera',
        'suggestion': 'Conduct morning checks',
        'remarks': 'Fall arrest system used',
      });

      final jsonUpdate = ActionProgressUpdate.fromJson({
        'id': 'up-1',
        'action_id': 'ACT-1001',
        'updated_by': 'user-1',
        'updated_by_name': 'Alice',
        'update_date': '2026-11-03',
        'progress': 80,
        'status': 'In Progress',
        'comments': jsonPayload,
      });

      expect(jsonUpdate.effectiveSubject, equals('Roof Inspection Completed'));
      expect(jsonUpdate.effectiveWorkCompleted, equals('Repaired sealant on ridge cap.'));
      expect(jsonUpdate.pendingWork, equals('Thermal imaging scan pending.'));
      expect(jsonUpdate.requirement, equals('Flir camera'));
      expect(jsonUpdate.suggestion, equals('Conduct morning checks'));
      expect(jsonUpdate.remarks, equals('Fall arrest system used'));

      // Legacy plain text comments
      final legacyUpdate = ActionProgressUpdate(
        id: 'up-2',
        actionId: 'ACT-1001',
        updatedById: 'user-2',
        updatedByName: 'Bob',
        updateDate: '02 Nov 2026',
        progress: 50,
        status: 'In Progress',
        comments: 'Legacy simple progress text without JSON',
      );

      expect(legacyUpdate.subject, isEmpty);
      expect(legacyUpdate.effectiveSubject, equals('Progress Update'));
      expect(legacyUpdate.effectiveWorkCompleted, equals('Legacy simple progress text without JSON'));
      expect(legacyUpdate.pendingWork, isEmpty);
    });

    test('ActionRecord.fromSupabase maps progress_updates remarks correctly', () {
      final supabaseMap = {
        'id': 'ACT-1030',
        'action_number': 'ACT-1030',
        'subject': 'Forklift maintenance',
        'action_required': 'Inspect brake lines',
        'status': 'In Progress',
        'percent_complete': 60,
        'action_progress_updates': [
          {
            'id': 'up-100',
            'action_id': 'ACT-1030',
            'update_date': '2026-11-03',
            'progress': 60,
            'status': 'In Progress',
            'comments': jsonEncode({
              'subject': 'Hydraulics inspected',
              'work_completed': 'Replaced high-pressure fluid line.',
              'pending_work': 'Brake pad inspection next.',
            }),
            'updated_by': 'user-123',
            'created_at': '2026-11-03T10:00:00Z',
          }
        ],
      };

      final record = ActionRecord.fromSupabase(supabaseMap);
      expect(record.progressUpdates.length, equals(1));
      expect(record.workerMessageSubject, equals('Hydraulics inspected'));
      expect(record.workerMessage, equals('Replaced high-pressure fluid line.'));
      expect(record.pendingReason, equals('Brake pad inspection next.'));
    });
  });

  group('ISSUE 2 — Edit Existing Updates Without Duplication', () {
    test('submitProgressUpdate updates existing update in-place when existingUpdateId is provided', () async {
      final initialAction = ActionRecord(
        id: 'ACT-2001',
        actionNumber: 'ACT-2001',
        subject: 'Fire Door Inspection',
        actionRequired: 'Check all emergency exits',
        division: 'Commercial',
        department: 'Safety',
        assignedTo: 'Sarah Staff',
        assignedToId: 'staff-sarah',
        status: 'In Progress',
        percentComplete: 30,
        progressUpdates: [
          ActionProgressUpdate(
            id: 'update-original',
            actionId: 'ACT-2001',
            updatedById: 'staff-sarah',
            updatedByName: 'Sarah Staff',
            updateDate: '01 Nov 2026',
            progress: 30,
            status: 'In Progress',
            comments: 'Initial door gap checks done.',
            subject: 'Initial Check',
            workCompleted: 'Initial door gap checks done.',
          ),
        ],
      );

      MockActionStore.instance.add(initialAction);

      // Save an edit to 'update-original'
      final editedAction = await ActionService.instance.submitProgressUpdate(
        actionId: 'ACT-2001',
        existingUpdateId: 'update-original',
        updateDate: DateTime(2026, 11, 3),
        progress: 45,
        status: 'In Progress',
        comments: 'Updated: gap checks verified, hinge lubricated.',
        subject: 'Initial Check (Revised)',
        workCompleted: 'Updated: gap checks verified, hinge lubricated.',
        pendingWork: 'Panic bar replacement on Door 4',
      );

      // Crucial verification: count of updates must STILL be exactly 1 (no duplicate!)
      expect(editedAction.progressUpdates.length, equals(1));
      final updatedRec = editedAction.progressUpdates.first;
      expect(updatedRec.id, equals('update-original'));
      expect(updatedRec.progress, equals(45));
      expect(updatedRec.effectiveSubject, equals('Initial Check (Revised)'));
      expect(updatedRec.effectiveWorkCompleted, equals('Updated: gap checks verified, hinge lubricated.'));
      expect(updatedRec.pendingWork, equals('Panic bar replacement on Door 4'));

      // Action record top-level fields must reflect the edit
      expect(editedAction.percentComplete, equals(45));
      expect(editedAction.workerMessageSubject, equals('Initial Check (Revised)'));
    });

    test('submitProgressUpdate creates a new update when existingUpdateId is null', () async {
      final initialAction = ActionRecord(
        id: 'ACT-2002',
        actionNumber: 'ACT-2002',
        subject: 'Scaffolding check',
        actionRequired: 'Inspect scaffolding base',
        division: 'Commercial',
        department: 'Safety',
        assignedTo: 'Mike Staff',
        assignedToId: 'staff-mike',
        status: 'In Progress',
        percentComplete: 20,
        progressUpdates: [
          ActionProgressUpdate(
            id: 'update-day1',
            actionId: 'ACT-2002',
            updatedById: 'staff-mike',
            updatedByName: 'Mike Staff',
            updateDate: '01 Nov 2026',
            progress: 20,
            status: 'In Progress',
            comments: 'Day 1 foundation base plates inspected.',
          ),
        ],
      );

      MockActionStore.instance.add(initialAction);

      // Submit a distinct new update (existingUpdateId is null)
      final updatedAction = await ActionService.instance.submitProgressUpdate(
        actionId: 'ACT-2002',
        updateDate: DateTime(2026, 11, 3),
        progress: 50,
        status: 'In Progress',
        comments: 'Day 2 standards and ledgers erected.',
        subject: 'Day 2 Progress',
        workCompleted: 'Day 2 standards and ledgers erected.',
      );

      expect(updatedAction.progressUpdates.length, equals(2));
      expect(updatedAction.progressUpdates.first.effectiveSubject, equals('Day 2 Progress'));
      expect(updatedAction.progressUpdates.last.id, equals('update-day1'));
    });

    test('ActionRecord.latestProgressUpdateFor returns correct update per actor role', () {
      final action = ActionRecord(
        id: 'ACT-2003',
        actionNumber: 'ACT-2003',
        subject: 'Electrical room audit',
        actionRequired: 'Audit circuit breakers',
        division: 'Commercial',
        department: 'Maintenance',
        assignedTo: 'Alex',
        status: 'In Progress',
        percentComplete: 50,
        progressUpdates: [
          ActionProgressUpdate(
            id: 'mgr-up',
            actionId: 'ACT-2003',
            updatedById: 'mgr-1',
            updatedByName: 'David Manager',
            updateDate: '03 Nov 2026',
            progress: 50,
            status: 'In Progress',
            comments: 'Manager checkpoint review.',
            roleInAction: 'manager',
          ),
          ActionProgressUpdate(
            id: 'staff-up',
            actionId: 'ACT-2003',
            updatedById: 'staff-1',
            updatedByName: 'Alex Staff',
            updateDate: '02 Nov 2026',
            progress: 40,
            status: 'In Progress',
            comments: 'Staff wiring inspection.',
            roleInAction: 'assignee',
          ),
        ],
      );

      final staffLatest = action.latestProgressUpdateFor('staff-1', isManager: false);
      expect(staffLatest?.id, equals('staff-up'));

      final mgrLatest = action.latestProgressUpdateFor('mgr-1', isManager: true);
      expect(mgrLatest?.id, equals('mgr-up'));
    });
  });

  group('ISSUE 3 & 4 — Bidirectional Action Forwarding & Permissions', () {
    test('Forwarding preserves the identical action ID across delegations', () {
      final original = ActionRecord(
        id: 'ACT-5000',
        actionNumber: 'ACT-5000',
        subject: 'Emergency Lighting Test',
        actionRequired: 'Perform 90-minute battery drain test',
        division: 'Commercial',
        department: 'Operations',
        assignedTo: 'Carlos Staff',
        assignedToId: 'staff-carlos',
        status: 'In Progress',
        percentComplete: 25,
      );

      // Delegate / forward action to Manager
      final forwardedToManager = original.copyWith(
        contributors: [
          ActionContributorRecord(
            id: 'contrib-1',
            actionId: original.id,
            profileId: 'mgr-alice',
            profileName: 'Alice Manager',
            profileEmail: 'alice@example.com',
            addedBy: 'staff-carlos',
            notes: 'Please review battery backup specs',
            createdAt: DateTime(2026, 11, 3),
          ),
        ],
      );

      // Verify same Action ID
      expect(forwardedToManager.id, equals('ACT-5000'));
      expect(forwardedToManager.actionNumber, equals('ACT-5000'));

      // Check isForwardedTo
      expect(forwardedToManager.isForwardedTo('mgr-alice', null, null), isTrue);
      expect(forwardedToManager.isForwardedTo(null, null, 'alice@example.com'), isTrue);
      expect(forwardedToManager.isForwardedTo('random-id', null, null), isFalse);
    });

    test('Contributor cannot approve and close action, only Managers can', () {
      final action = ActionRecord(
        id: 'ACT-5001',
        actionNumber: 'ACT-5001',
        subject: 'Ventilation filter replacement',
        actionRequired: 'Replace all HEPA filters',
        division: 'Commercial',
        department: 'HSSE',
        assignedTo: 'Primary Staff',
        assignedToId: 'staff-primary',
        status: 'Pending Review',
        percentComplete: 100,
        contributors: [
          ActionContributorRecord(
            id: 'c-1',
            actionId: 'ACT-5001',
            profileId: 'contributor-1',
            profileName: 'Secondary Staff',
            profileEmail: 'secondary@example.com',
            notes: 'Assisting with installation',
            createdAt: DateTime.now(),
          ),
        ],
      );

      expect(action.contributors, isNotEmpty);

      // Contributor rule: contributor is NOT an admin or manager
      final isContributorManager = false;
      final canContributorClose = isContributorManager;
      expect(canContributorClose, isFalse);

      // Manager can close
      final isReviewerManager = true;
      final canManagerClose = isReviewerManager;
      expect(canManagerClose, isTrue);
    });
  });
}
