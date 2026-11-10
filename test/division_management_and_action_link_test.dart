import 'package:action_flow/features/dashboard/admin_dashboard/screens/admin_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/add_action_screen.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/models/division.dart';
import 'package:action_flow/services/division_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Division Model Tests', () {
    test('instantiates with required and default fields', () {
      final now = DateTime.now();
      final division = Division(
        id: 'div-1',
        organizationId: 'org-1',
        name: 'Operations',
        code: 'OPS',
        createdAt: now,
        updatedAt: now,
      );

      expect(division.id, 'div-1');
      expect(division.organizationId, 'org-1');
      expect(division.name, 'Operations');
      expect(division.code, 'OPS');
      expect(division.description, '');
      expect(division.isActive, isTrue);
      expect(division.actionCount, 0);
    });

    test('deserializes from Supabase row map', () {
      final map = {
        'id': 'div-2',
        'organization_id': 'org-100',
        'name': 'Projects',
        'code': 'PRJ',
        'description': 'Real estate & construction projects',
        'is_active': false,
        'created_at': '2026-09-21T10:00:00Z',
        'updated_at': '2026-09-21T10:30:00Z',
        'action_count': 14,
      };

      final division = Division.fromSupabase(map);

      expect(division.id, 'div-2');
      expect(division.organizationId, 'org-100');
      expect(division.name, 'Projects');
      expect(division.code, 'PRJ');
      expect(division.description, 'Real estate & construction projects');
      expect(division.isActive, isFalse);
      expect(division.createdAt, DateTime.parse('2026-09-21T10:00:00Z'));
      expect(division.updatedAt, DateTime.parse('2026-09-21T10:30:00Z'));
      expect(division.actionCount, 14);
    });

    test('serializes to insert and update maps', () {
      final now = DateTime.now();
      final division = Division(
        id: 'div-3',
        organizationId: 'org-200',
        name: 'Corporate',
        code: 'CORP',
        description: 'Corporate affairs and legal',
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      final insertMap = division.toInsertMap();
      expect(insertMap['organization_id'], 'org-200');
      expect(insertMap['name'], 'Corporate');
      expect(insertMap['code'], 'CORP');
      expect(insertMap['description'], 'Corporate affairs and legal');
      expect(insertMap['is_active'], isTrue);

      final updateMap = division.toUpdateMap();
      expect(updateMap['name'], 'Corporate');
      expect(updateMap['code'], 'CORP');
      expect(updateMap['description'], 'Corporate affairs and legal');
      expect(updateMap['is_active'], isTrue);
      expect(updateMap.containsKey('id'), isFalse);
      expect(updateMap.containsKey('organization_id'), isFalse);
    });

    test('copyWith properly overrides selected fields', () {
      final now = DateTime.now();
      final division = Division(
        id: 'div-4',
        organizationId: 'org-300',
        name: 'Operations',
        code: 'OPS',
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      final updated = division.copyWith(
        name: 'Global Operations',
        code: 'GL-OPS',
        isActive: false,
        actionCount: 22,
      );

      expect(updated.id, 'div-4');
      expect(updated.organizationId, 'org-300');
      expect(updated.name, 'Global Operations');
      expect(updated.code, 'GL-OPS');
      expect(updated.isActive, isFalse);
      expect(updated.actionCount, 22);
    });

    test('equality and hashCode match for identical instances', () {
      final now = DateTime.now();
      final div1 = Division(
        id: 'div-5',
        organizationId: 'org-1',
        name: 'Engineering',
        code: 'ENG',
        createdAt: now,
        updatedAt: now,
      );
      final div2 = Division(
        id: 'div-5',
        organizationId: 'org-1',
        name: 'Engineering',
        code: 'ENG',
        createdAt: now,
        updatedAt: now,
      );

      expect(div1, equals(div2));
      expect(div1.hashCode, equals(div2.hashCode));
    });
  });

  group('ActionRecord Division Integration Tests', () {
    test('ActionRecord supports divisionId and division fields', () {
      final record = ActionRecord(
        id: 'ACT-4001',
        organizationId: 'org-1',
        departmentId: 'dept-1',
        siteId: 'site-1',
        divisionId: 'div-99',
        division: 'Projects',
        createdById: 'user-1',
        subject: 'Review Facade Safety',
        actionRequired: 'Inspect brackets',
        priority: 'High',
        status: 'Open',
        assignedTo: 'Jane Smith',
        primaryAssignee: ActionPersonReference(
          personId: 'user-3',
          name: 'Jane Smith',
          type: PersonType.internalUser,
        ),
      );

      expect(record.divisionId, 'div-99');
      expect(record.division, 'Projects');

      // Test toSupabaseInsertMap contains division_id
      final insertMap = record.toSupabaseInsertMap();
      expect(insertMap['division_id'], 'div-99');

      // Test toSupabaseUpdateMap contains division_id
      final updateMap = record.toSupabaseUpdateMap();
      expect(updateMap['division_id'], 'div-99');

      // Test copyWith overrides division and divisionId
      final updated = record.copyWith(
        divisionId: 'div-100',
        division: 'Corporate',
      );
      expect(updated.divisionId, 'div-100');
      expect(updated.division, 'Corporate');
    });

    test('ActionRecord.fromSupabase maps division_id and joined divisions relation', () {
      final rawRow = {
        'id': 'ACT-4002',
        'organization_id': 'org-1',
        'department_id': 'dept-1',
        'site_id': 'site-1',
        'division_id': 'div-77',
        'created_by': 'user-1',
        'title': 'Safety Audit at Tower A',
        'description': 'Inspect crane anchor points',
        'priority': 'Critical',
        'status': 'Open',
        'percent_complete': 10,
        'divisions': {'id': 'div-77', 'name': 'Operations', 'code': 'OPS'},
      };

      final record = ActionRecord.fromSupabase(rawRow);
      expect(record.id, 'ACT-4002');
      expect(record.divisionId, 'div-77');
      expect(record.division, 'Operations');
    });

    test('ActionRecord.fromSupabase gracefully handles null division_id', () {
      final rawRow = {
        'id': 'ACT-4003',
        'organization_id': 'org-1',
        'department_id': 'dept-1',
        'site_id': 'site-1',
        'division_id': null,
        'created_by': 'user-1',
        'title': 'General Housekeeping',
        'description': 'Clean basement storage',
        'priority': 'Low',
        'status': 'Open',
        'percent_complete': 0,
      };

      final record = ActionRecord.fromSupabase(rawRow);
      expect(record.id, 'ACT-4003');
      expect(record.divisionId, isNull);
      expect(record.division, 'Operations'); // Legacy default fallback
    });
  });

  group('DivisionService Unit Tests', () {
    test('DivisionService exposes singleton and isReady getter', () {
      final service = DivisionService.instance;
      expect(service, isNotNull);
      // Supabase is not initialized in standard unit test environment, so isReady is false
      expect(service.isReady, isFalse);
    });

    test('returns empty list gracefully if client is uninitialized', () async {
      final service = DivisionService();
      final divisions = await service.fetchDivisions('org-any');
      expect(divisions, isEmpty);
    });

    test(
      'deleteDivision throws exception if client is uninitialized',
      () async {
        final service = DivisionService();
        expect(
          () => service.deleteDivision(divisionId: 'div-123'),
          throwsA(isA<Exception>()),
        );
      },
    );
  });

  group('Division UI & Screen Integration Tests', () {
    testWidgets(
      'AddActionScreen hides Division and Unit and renders Teams in WHERE IT BELONGS section',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          const MaterialApp(home: AddActionScreen(actionId: 'ACT-TEST-DIV')),
        );
        await tester.pumpAndSettle();

        // Section 2: WHERE IT BELONGS exists
        expect(find.text('WHERE IT BELONGS'), findsOneWidget);

        // Division & Unit are hidden from the Add Action UI
        expect(find.text('Division'), findsNothing);
        expect(find.text('Unit'), findsNothing);

        // Other fields in the section exist independently
        expect(find.text('Department'), findsWidgets);
        expect(find.text('Section'), findsWidgets);
        expect(find.text('Location / Site'), findsWidgets);
        expect(find.text('Teams'), findsWidgets);
      },
    );

    testWidgets(
      'AdminDashboardScreen renders Divisions tab (tab 7) and Add Division modal',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          const MaterialApp(home: AdminDashboardScreen(initialTabIndex: 7)),
        );
        await tester.pumpAndSettle();

        // Verify header and subtitle
        expect(find.text('Divisions'), findsWidgets);
        expect(
          find.text(
            'Configure organizational divisions and business lines for action tracking.',
          ),
          findsOneWidget,
        );
        expect(find.text('Add Division'), findsOneWidget);

        // Tap Add Division
        await tester.tap(find.text('Add Division'));
        await tester.pumpAndSettle();

        // Verify modal inputs inside AlertDialog
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Division Name *'), findsOneWidget);
        expect(find.text('Division Code *'), findsOneWidget);
        expect(find.text('Description (Optional)'), findsOneWidget);
        expect(find.text('Save Division'), findsOneWidget);

        // Close modal
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      },
    );
  });
}
