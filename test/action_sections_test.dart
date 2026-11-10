import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/models/action_section.dart';
import 'package:action_flow/services/action_section_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ActionSection Model Tests', () {
    test('instantiates with required and default fields', () {
      final now = DateTime.now();
      final section = ActionSection(
        id: 'sec-1',
        organizationId: 'org-1',
        name: 'Inspection',
        createdAt: now,
        updatedAt: now,
      );

      expect(section.id, 'sec-1');
      expect(section.organizationId, 'org-1');
      expect(section.name, 'Inspection');
      expect(section.description, '');
      expect(section.isActive, isTrue);
      expect(section.actionCount, 0);
    });

    test('deserializes from Supabase row map', () {
      final map = {
        'id': 'sec-2',
        'organization_id': 'org-100',
        'name': 'Mechanical & Piping',
        'description': 'Piping, flanges, and valves',
        'is_active': false,
        'created_at': '2026-09-21T10:00:00Z',
        'updated_at': '2026-09-21T10:30:00Z',
        'action_count': 5,
      };

      final section = ActionSection.fromSupabase(map);

      expect(section.id, 'sec-2');
      expect(section.organizationId, 'org-100');
      expect(section.name, 'Mechanical & Piping');
      expect(section.description, 'Piping, flanges, and valves');
      expect(section.isActive, isFalse);
      expect(section.createdAt, DateTime.parse('2026-09-21T10:00:00Z'));
      expect(section.updatedAt, DateTime.parse('2026-09-21T10:30:00Z'));
      expect(section.actionCount, 5);
    });

    test('serializes to insert and update maps', () {
      final now = DateTime.now();
      final section = ActionSection(
        id: 'sec-3',
        organizationId: 'org-200',
        name: 'Electrical Safety',
        description: 'LOTO, panels, wiring',
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      final insertMap = section.toInsertMap();
      expect(insertMap['organization_id'], 'org-200');
      expect(insertMap['name'], 'Electrical Safety');
      expect(insertMap['description'], 'LOTO, panels, wiring');
      expect(insertMap['is_active'], isTrue);

      final updateMap = section.toUpdateMap();
      expect(updateMap['name'], 'Electrical Safety');
      expect(updateMap['description'], 'LOTO, panels, wiring');
      expect(updateMap['is_active'], isTrue);
      expect(updateMap.containsKey('id'), isFalse);
      expect(updateMap.containsKey('organization_id'), isFalse);
    });

    test('copyWith properly overrides selected fields', () {
      final now = DateTime.now();
      final section = ActionSection(
        id: 'sec-4',
        organizationId: 'org-300',
        name: 'Civil Works',
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      final updated = section.copyWith(
        name: 'Civil & Structural',
        isActive: false,
        actionCount: 12,
      );

      expect(updated.id, 'sec-4');
      expect(updated.organizationId, 'org-300');
      expect(updated.name, 'Civil & Structural');
      expect(updated.isActive, isFalse);
      expect(updated.actionCount, 12);
    });
  });

  group('ActionRecord Section Integration Tests', () {
    test('ActionRecord supports sectionId and section fields', () {
      final record = ActionRecord(
        id: 'ACT-2001',
        organizationId: 'org-1',
        departmentId: 'dept-1',
        siteId: 'site-1',
        sectionId: 'sec-99',
        section: 'HVAC Inspection',
        createdById: 'user-1',
        subject: 'Inspect Air Handler 4',
        actionRequired: 'Replace filters',
        division: 'Operations',
        priority: 'High',
        status: 'Open',
        assignedTo: 'John Doe',
        primaryAssignee: ActionPersonReference(
          personId: 'user-2',
          name: 'John Doe',
          type: PersonType.internalUser,
        ),
      );

      expect(record.sectionId, 'sec-99');
      expect(record.section, 'HVAC Inspection');

      // Test toSupabaseInsertMap contains section_id
      final insertMap = record.toSupabaseInsertMap();
      expect(insertMap['section_id'], 'sec-99');

      // Test toSupabaseUpdateMap contains section_id
      final updateMap = record.toSupabaseUpdateMap();
      expect(updateMap['section_id'], 'sec-99');

      // Test copyWith overrides section and sectionId
      final updated = record.copyWith(
        sectionId: 'sec-100',
        section: 'Electrical',
      );
      expect(updated.sectionId, 'sec-100');
      expect(updated.section, 'Electrical');
    });

    test('ActionRecord.fromSupabase maps section_id and joined action_sections name', () {
      final rawRow = {
        'id': 'ACT-3001',
        'organization_id': 'org-1',
        'department_id': 'dept-1',
        'site_id': 'site-1',
        'section_id': 'sec-55',
        'created_by': 'user-1',
        'title': 'Calibrate Gas Detectors',
        'description': 'Quarterly calibration',
        'priority': 'Medium',
        'status': 'Open',
        'percent_complete': 25,
        'action_sections': {'id': 'sec-55', 'name': 'Instrumentation'},
      };

      final record = ActionRecord.fromSupabase(rawRow);
      expect(record.id, 'ACT-3001');
      expect(record.sectionId, 'sec-55');
      expect(record.section, 'Instrumentation');
    });

    test('ActionRecord.fromSupabase gracefully handles null section_id', () {
      final rawRow = {
        'id': 'ACT-3002',
        'organization_id': 'org-1',
        'department_id': 'dept-1',
        'site_id': 'site-1',
        'section_id': null,
        'created_by': 'user-1',
        'title': 'General Housekeeping',
        'description': 'Clean corridor',
        'priority': 'Low',
        'status': 'Open',
        'percent_complete': 0,
      };

      final record = ActionRecord.fromSupabase(rawRow);
      expect(record.id, 'ACT-3002');
      expect(record.sectionId, isNull);
      expect(record.section, '');
    });
  });

  group('ActionSectionService Unit Tests', () {
    test('ActionSectionService exposes singleton and isReady getter', () {
      final service = ActionSectionService.instance;
      expect(service, isNotNull);
      // Supabase is not initialized in standard unit test environment, so isReady is false
      expect(service.isReady, isFalse);
    });

    test('returns empty list gracefully if client is uninitialized', () async {
      final service = ActionSectionService();
      final sections = await service.fetchSections('org-any');
      expect(sections, isEmpty);
    });
  });
}
