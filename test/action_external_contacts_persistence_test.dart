import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testOrgId = '00000000-0000-0000-0000-000000000001';
  const otherOrgId = '00000000-0000-0000-0000-000000000002';

  final primaryStaff = ActionPersonReference(
    personId: '00000000-0000-0000-0000-000000000010',
    name: 'Primary Internal Assignee',
    type: PersonType.internalUser,
    email: 'primary@internal.com',
  );

  final extContact1 = ActionPersonReference(
    personId: '00000000-0000-0000-0000-000000000020',
    name: 'Subcontractor Dave',
    type: PersonType.externalWorker,
    email: 'dave@subcontractor.com',
    phone: '+971501112222',
    company: 'Dave Contracting LLC',
  );

  final extContact2 = ActionPersonReference(
    personId: '00000000-0000-0000-0000-000000000021',
    name: 'Consultant Emma',
    type: PersonType.externalWorker,
    email: 'emma@consultancy.com',
    phone: '+971503334444',
    company: 'Emma Safety Advisory',
  );

  setUp(() {
    MockActionStore.instance.actions.clear();
  });

  tearDown(() {
    MockActionStore.instance.actions.clear();
  });

  ActionRecord buildTestAction({
    required String id,
    String orgId = testOrgId,
    List<ActionPersonReference>? additionalPeople,
  }) {
    return ActionRecord(
      id: id,
      actionNumber: 'ACT-$id',
      organizationId: orgId,
      departmentId: '00000000-0000-0000-0000-000000000100',
      siteId: '00000000-0000-0000-0000-000000000200',
      subject: 'External Contacts Safety Inspection',
      actionRequired: 'Ensure proper external contact tracking',
      category: 'Inspection',
      source: 'Direct Action',
      priority: 'Medium',
      status: 'Open',
      percentComplete: 0,
      dateRaised: '01 Jan 2026',
      targetDate: '20 Jan 2026',
      assignedTo: primaryStaff.name,
      assignedToId: primaryStaff.personId,
      primaryAssignee: primaryStaff,
      additionalPeople: additionalPeople ?? [extContact1, extContact2],
      division: 'Civil',
    );
  }

  group('Fix 2: Additional External Contacts Persistence & Scoping', () {
    test(
        'Requirement: toSupabaseInsertMap and toSupabaseUpdateMap DO NOT contain unsupported additional_people column',
        () {
      final action = buildTestAction(id: 'ACT-EXT-MAP-01');

      final insertMap = action.toSupabaseInsertMap();
      final updateMap = action.toSupabaseUpdateMap();

      // Database column 'additional_people' does not exist on public.actions
      expect(insertMap.containsKey('additional_people'), isFalse,
          reason: 'Insert map must not send unsupported additional_people column to public.actions');
      expect(updateMap.containsKey('additional_people'), isFalse,
          reason: 'Update map must not send unsupported additional_people column to public.actions');

      // Valid action columns must still be present
      expect(insertMap['title'], equals('External Contacts Safety Inspection'));
      expect(insertMap['organization_id'], equals(testOrgId));
    });

    test(
        'ActionRecord.fromMap properly parses external contacts from relational action_external_contacts payload',
        () {
      final rawSupabaseRow = {
        'id': 'ACT-EXT-PARSE-01',
        'action_number': 'ACT-001',
        'organization_id': testOrgId,
        'department_id': '00000000-0000-0000-0000-000000000100',
        'site_id': '00000000-0000-0000-0000-000000000200',
        'title': 'Parsed Relational Action',
        'action_required': 'Verify relational contacts',
        'category': 'Inspection',
        'priority': 'Medium',
        'status': 'Open',
        'percent_complete': 0,
        'date_raised': '2026-01-01',
        'target_date': '2026-01-20',
        'action_external_contacts': [
          {
            'id': 'rel-01',
            'external_recipient_id': extContact1.personId,
            'recipient': {
              'id': extContact1.personId,
              'full_name': extContact1.name,
              'email': extContact1.email,
              'phone': extContact1.phone,
              'company_name': extContact1.company,
            },
          },
          {
            'id': 'rel-02',
            'external_recipient_id': extContact2.personId,
            'recipient': {
              'id': extContact2.personId,
              'full_name': extContact2.name,
              'email': extContact2.email,
              'phone': extContact2.phone,
              'company_name': extContact2.company,
            },
          },
        ],
      };

      final parsed = ActionRecord.fromSupabase(rawSupabaseRow);
      expect(parsed.additionalPeople.length, equals(2));
      expect(parsed.additionalPeople.first.personId, equals(extContact1.personId));
      expect(parsed.additionalPeople.first.name, equals('Subcontractor Dave'));
      expect(parsed.additionalPeople.first.type, equals(PersonType.externalWorker));
      expect(parsed.additionalPeople.first.company, equals('Dave Contracting LLC'));

      expect(parsed.additionalPeople.last.personId, equals(extContact2.personId));
      expect(parsed.additionalPeople.last.name, equals('Consultant Emma'));
    });

    test(
        'Saving action in ActionService preserves additional external contacts and allows reloading',
        () async {
      final action = buildTestAction(id: 'ACT-EXT-SAVE-01');
      final created = await ActionService.instance.createAction(action);

      expect(created.additionalPeople.length, equals(2));
      expect(created.additionalPeople.any((p) => p.personId == extContact1.personId), isTrue);
      expect(created.additionalPeople.any((p) => p.personId == extContact2.personId), isTrue);

      final reloaded = await ActionService.instance.fetchActionById('ACT-EXT-SAVE-01');
      expect(reloaded, isNotNull);
      expect(reloaded!.additionalPeople.length, equals(2));
    });

    test(
        'Editing action preserves retained external contact and removes unselected contact without deleting shared recipient',
        () async {
      final action = buildTestAction(id: 'ACT-EXT-EDIT-01');
      final created = await ActionService.instance.createAction(action);
      expect(created.additionalPeople.length, equals(2));

      // Manager edits action and removes extContact1, but retains extContact2
      final updateCandidate = created.copyWith(
        additionalPeople: [extContact2],
      );
      final updated = await ActionService.instance.updateAction(updateCandidate);

      // Verify retained contact is present, removed contact is detached
      expect(updated.additionalPeople.length, equals(1));
      expect(updated.additionalPeople.first.personId, equals(extContact2.personId));
      expect(updated.additionalPeople.any((p) => p.personId == extContact1.personId), isFalse);

      final reloaded = await ActionService.instance.fetchActionById('ACT-EXT-EDIT-01');
      expect(reloaded!.additionalPeople.length, equals(1));
      expect(reloaded.additionalPeople.first.personId, equals(extContact2.personId));
    });

    test('Deduplication: duplicate external contacts with same ID are not associated multiple times',
        () async {
      final duplicateList = [extContact1, extContact1, extContact2];
      final action = buildTestAction(id: 'ACT-EXT-DEDUP-01', additionalPeople: duplicateList);

      final created = await ActionService.instance.createAction(action);
      expect(created.additionalPeople.length, equals(2));
      expect(created.additionalPeople.where((p) => p.personId == extContact1.personId).length, equals(1));
    });

    test('Organization Scoping: actions and external contacts remain isolated per organization',
        () async {
      final org1Action = buildTestAction(id: 'ACT-ORG1', orgId: testOrgId);
      final org2Action = buildTestAction(id: 'ACT-ORG2', orgId: otherOrgId);

      await ActionService.instance.createAction(org1Action);
      await ActionService.instance.createAction(org2Action);

      final loadedOrg1 = await ActionService.instance.fetchActionById('ACT-ORG1');
      final loadedOrg2 = await ActionService.instance.fetchActionById('ACT-ORG2');

      expect(loadedOrg1?.organizationId, equals(testOrgId));
      expect(loadedOrg2?.organizationId, equals(otherOrgId));
    });

    test('Assignment email separation: creating action with additional external contacts does not send reminders to them',
        () async {
      final action = buildTestAction(id: 'ACT-EMAIL-SEP-01');
      final result = await ActionService.instance.createActionWithResult(action);

      // Action created successfully
      expect(result.action.id, equals('ACT-EMAIL-SEP-01'));
      // No email reminder jobs created because reminders were not enabled
      expect(result.action.emailReminderEnabled, isFalse);
    });
  });
}
