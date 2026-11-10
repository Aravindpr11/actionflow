import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Critical Bug Fix: closure_comment NOT NULL constraint (code 23502)', () {
    test('toSupabaseUpdateMap on active action with empty closureComment does NOT set closure_comment to null', () {
      final action = ActionRecord(
        id: 'act-uuid-001',
        actionNumber: 'ACT-1001',
        subject: 'Active Safety Inspection',
        actionRequired: 'Inspect crane hooks',
        division: 'Construction',
        department: 'HSE',
        site: 'Downtown Tower',
        team: 'Rigging Team',
        assignedTo: 'John Doe',
        status: 'In Progress',
        percentComplete: 45,
        closureComment: '',
      );

      final updateMap = action.toSupabaseUpdateMap();

      // Crucial: Must NEVER send null for closure_comment to Postgres
      expect(updateMap.containsKey('closure_comment'), isFalse,
          reason: 'Active action with empty closure comment should omit key so Postgres column default is untouched');

      // Nullable closure columns should be cleared
      expect(updateMap['close_date'], isNull);
      expect(updateMap['closed_at'], isNull);
      expect(updateMap['closed_by'], isNull);
    });

    test('toSupabaseUpdateMap on active action with non-empty closureComment includes string value', () {
      final action = ActionRecord(
        id: 'act-uuid-002',
        actionNumber: 'ACT-1002',
        subject: 'Active Safety Inspection',
        actionRequired: 'Inspect crane hooks',
        division: 'Construction',
        department: 'HSE',
        site: 'Downtown Tower',
        assignedTo: 'John Doe',
        status: 'Open',
        percentComplete: 10,
        closureComment: 'Reopened by HSE Manager after review',
      );

      final updateMap = action.toSupabaseUpdateMap();

      expect(updateMap['closure_comment'], equals('Reopened by HSE Manager after review'));
      expect(updateMap['close_date'], isNull);
      expect(updateMap['closed_at'], isNull);
      expect(updateMap['closed_by'], isNull);
    });

    test('toSupabaseUpdateMap on closed action always sets non-null string for closure_comment', () {
      final closedWithComment = ActionRecord(
        id: 'act-uuid-003',
        actionNumber: 'ACT-1003',
        subject: 'Completed Action',
        actionRequired: 'Fix lighting',
        division: 'Facilities',
        department: 'Maintenance',
        site: 'Main Plant',
        assignedTo: 'Jane Smith',
        status: 'Closed',
        percentComplete: 100,
        closureComment: 'Verified by HSE Lead',
      );

      final updateMap1 = closedWithComment.toSupabaseUpdateMap();
      expect(updateMap1['closure_comment'], equals('Verified by HSE Lead'));
      expect(updateMap1['closed_at'], isNotNull);

      final closedWithoutComment = ActionRecord(
        id: 'act-uuid-004',
        actionNumber: 'ACT-1004',
        subject: 'Completed Action',
        actionRequired: 'Fix lighting',
        division: 'Facilities',
        department: 'Maintenance',
        site: 'Main Plant',
        assignedTo: 'Jane Smith',
        status: 'Closed',
        percentComplete: 100,
        closureComment: '',
      );

      final updateMap2 = closedWithoutComment.toSupabaseUpdateMap();
      expect(updateMap2['closure_comment'], equals(''),
          reason: 'Postgres TEXT NOT NULL requires non-null empty string fallback, never null');
      expect(updateMap2['closed_at'], isNotNull);
    });
  });

  group('Action Information Mapping: Team and Division Handling', () {
    test('fromSupabase parses team name from joined teams object', () {
      final supabaseData = <String, dynamic>{
        'id': 'act-uuid-101',
        'action_number': 'ACT-2001',
        'title': 'Scaffolding Inspection',
        'action_required': 'Check toe boards and guardrails',
        'status': 'In Progress',
        'progress': 60,
        'department_id': 'dept-uuid-1',
        'site_id': 'site-uuid-1',
        'team_id': 'team-uuid-1',
        'teams': {
          'id': 'team-uuid-1',
          'name': 'Scaffolding & Rigging Team',
        },
        'departments': {
          'id': 'dept-uuid-1',
          'name': 'Civil Engineering',
          'division': 'Construction',
        },
        'sites': {
          'id': 'site-uuid-1',
          'name': 'Plot 42 Sector B',
        },
        'action_sections': {
          'id': 'sec-uuid-1',
          'name': 'Work at Height',
        },
      };

      final record = ActionRecord.fromSupabase(supabaseData);

      expect(record.team, equals('Scaffolding & Rigging Team'));
      expect(record.teamId, equals('team-uuid-1'));
      expect(record.section, equals('Work at Height'));
      expect(record.department, equals('Civil Engineering'));
      expect(record.site, equals('Plot 42 Sector B'));
    });

    test('fromSupabase falls back gracefully when team name is missing', () {
      final supabaseData = <String, dynamic>{
        'id': 'act-uuid-102',
        'action_number': 'ACT-2002',
        'title': 'General Housekeeping',
        'action_required': 'Clean up work area',
        'status': 'Open',
        'progress': 0,
      };

      final record = ActionRecord.fromSupabase(supabaseData);

      expect(record.team, equals(''));
      expect(record.teamId, isNull);
    });

    test('copyWith updates team and preserves existing values', () {
      final original = ActionRecord(
        id: 'act-uuid-103',
        actionNumber: 'ACT-2003',
        subject: 'HVAC Maintenance',
        actionRequired: 'Replace air filters',
        division: 'Facilities',
        department: 'MEP',
        site: 'Tower 1',
        team: 'HVAC Team',
        assignedTo: 'Alex Worker',
      );

      final updated = original.copyWith(team: 'Mechanical Team');
      expect(updated.team, equals('Mechanical Team'));
      expect(updated.department, equals('MEP'));

      final untouched = original.copyWith(percentComplete: 50);
      expect(untouched.team, equals('HVAC Team'));
    });
  });
}
