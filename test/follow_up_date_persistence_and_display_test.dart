import 'package:flutter_test/flutter_test.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/services/action_service.dart';

void main() {
  setUp(() {
    MockActionStore.instance.actions.clear();
  });

  group('Follow-up Date Persistence & Display Reconciliation Tests', () {
    test('1. ActionRecord.fromSupabase parses next_follow_up_date when explicitly present', () {
      final json = {
        'id': 'ACT-FU-01',
        'title': 'Test Action',
        'status': 'In Progress',
        'next_follow_up_date': '2026-11-15',
        'last_follow_up_date': '2026-10-15',
      };
      final action = ActionRecord.fromSupabase(json);
      expect(action.nextFollowUpDate, equals('15 Nov 2026'));
      expect(action.lastFollowUpDate, equals('15 Oct 2026'));
      expect(action.followUp, equals('15 Nov 2026'));
    });

    test('2. ActionRecord.fromSupabase falls back to scheduled action_follow_ups when next_follow_up_date is null', () {
      final json = {
        'id': 'ACT-FU-02',
        'title': 'Test Action Fallback',
        'status': 'In Progress',
        'next_follow_up_date': null,
        'action_follow_ups': [
          {
            'id': 'fu-1',
            'action_id': 'ACT-FU-02',
            'follow_up_date': '2026-11-20',
            'status': 'Scheduled',
            'notes': 'Upcoming checkpoint',
          }
        ],
      };
      final action = ActionRecord.fromSupabase(json);
      expect(action.nextFollowUpDate, equals('20 Nov 2026'));
      expect(action.followUp, equals('20 Nov 2026'));
    });

    test('3. ActionRecord.fromSupabase falls back to last_follow_up_date when follow-up list is empty', () {
      final json = {
        'id': 'ACT-FU-03',
        'title': 'Test Action Last Fallback',
        'status': 'In Progress',
        'next_follow_up_date': null,
        'last_follow_up_date': '2026-10-25',
      };
      final action = ActionRecord.fromSupabase(json);
      expect(action.nextFollowUpDate, equals('25 Oct 2026'));
      expect(action.followUp, equals('25 Oct 2026'));
    });

    test('4. ActionRecord.followUp returns "Not set" when no follow-up dates are scheduled', () {
      final json = {
        'id': 'ACT-FU-04',
        'title': 'Test Action No Follow-Up',
        'status': 'In Progress',
        'next_follow_up_date': null,
        'last_follow_up_date': null,
      };
      final action = ActionRecord.fromSupabase(json);
      expect(action.nextFollowUpDate, isEmpty);
      expect(action.followUp, equals('Not set'));
    });

    test('5. ActionService.addFollowUp adds follow-up to mock store and updates nextFollowUpDate', () async {
      final action = ActionRecord(
        id: 'ACT-FU-TEST',
        actionNumber: 'ACT-FU-TEST',
        organizationId: '00000000-0000-0000-0000-000000000001',
        subject: 'Scheduled Follow-Up Action',
        actionRequired: 'Verify follow-up checkpoint',
        division: 'Operations',
        status: 'In Progress',
        percentComplete: 30,
        dateRaised: '01 Nov 2026',
        targetDate: '30 Nov 2026',
        assignedTo: 'Staff Member',
        nextFollowUpDate: '',
      );
      MockActionStore.instance.add(action);

      final result = await ActionService.instance.addFollowUp(
        actionId: 'ACT-FU-TEST',
        followUpDate: DateTime(2026, 11, 18),
        notes: 'Mid-sprint checkpoint',
      );

      expect(result.success, isTrue);
      expect(result.followUpId, isNotNull);

      final updated = MockActionStore.instance.actions.firstWhere((a) => a.id == 'ACT-FU-TEST');
      expect(updated.nextFollowUpDate, equals('18 Nov 2026'));
      expect(updated.followUp, equals('18 Nov 2026'));
      expect(updated.followUps.length, equals(1));
      expect(updated.followUps.first.notes, equals('Mid-sprint checkpoint'));
    });
  });
}
