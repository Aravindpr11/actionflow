import 'package:flutter_test/flutter_test.dart';
import 'package:action_flow/features/auth/models/manager_scope_item.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/action_service.dart';

void main() {
  group('Manager Context & Authority Tests', () {
    const managerId = '878d9145-7764-411f-8d26-f30f01e99e79';
    const orgId = Organization.sobhaId;
    const hseDeptId = 'f0ad05aa-c85a-40e5-b309-19f1e6629e7a';
    const testDeptId = '6000544e-dfe7-4911-b2cc-4c4bebead468';
    const siteTestId = '6abf4ba5-e8b7-4076-8c97-80f4a354f94b';
    const siteNorthPlantId = '46a89a44-c577-47d6-bb95-3488c1f7562e';
    const unauthorizedDeptId = 'ffffffff-0000-0000-0000-000000000001';
    const unauthorizedSiteId = 'ffffffff-0000-0000-0000-000000000002';

    final managerProfile = UserProfile(
      id: managerId,
      name: 'Operations Manager',
      email: 'webonant@gmail.com',
      phone: '+971 50 123 4567',
      designation: 'Safety & Operations Manager',
      department: 'HSE',
      site: 'test',
      role: 'Manager',
      organizationId: orgId,
      organizationName: 'Sobha',
    );

    final scopes = [
      const ManagerScopeItem(
        departmentId: hseDeptId,
        departmentName: 'HSE / Safety',
        siteId: siteTestId,
        siteName: 'test',
      ),
      const ManagerScopeItem(
        departmentId: testDeptId,
        departmentName: 'test',
        siteId: siteNorthPlantId,
        siteName: 'North Plant',
      ),
    ];

    final context = ManagerContext(
      authUserId: managerId,
      profile: managerProfile,
      organizationId: orgId,
      organizationName: 'Sobha',
      scopes: scopes,
    );

    test('Derives unique scoped department and site IDs correctly', () {
      expect(context.scopedDepartmentIds, containsAll([hseDeptId, testDeptId]));
      expect(context.scopedDepartmentIds.length, 2);
      expect(
        context.scopedSiteIds,
        containsAll([siteTestId, siteNorthPlantId]),
      );
      expect(context.scopedSiteIds.length, 2);
    });

    test('Derives sorted scoped department and site names', () {
      expect(context.scopedDepartmentNames, ['HSE / Safety', 'test']);
      expect(context.scopedSiteNames, ['North Plant', 'test']);
    });

    test('Enforces strict department and site scope permission', () {
      // In-scope checks
      expect(context.isScopePermitted(hseDeptId, siteTestId), isTrue);
      expect(context.isScopePermitted(testDeptId, siteNorthPlantId), isTrue);

      // Mismatched scopes (valid dept with wrong site, or vice versa)
      expect(context.isScopePermitted(hseDeptId, siteNorthPlantId), isFalse);
      expect(context.isScopePermitted(testDeptId, siteTestId), isFalse);

      // Unauthorized IDs
      expect(context.isScopePermitted(unauthorizedDeptId, siteTestId), isFalse);
      expect(context.isScopePermitted(hseDeptId, unauthorizedSiteId), isFalse);
      expect(context.isScopePermitted('', ''), isFalse);
    });

    test('Returns permitted sites for a given department name', () {
      final hseSites = context.permittedSiteNamesForDepartmentName(
        'HSE / Safety',
      );
      expect(hseSites, ['test']);

      final testSites = context.permittedSiteNamesForDepartmentName('test');
      expect(testSites, ['North Plant']);

      final allDeptSites = context.permittedSiteNamesForDepartmentName(
        'All Departments',
      );
      expect(allDeptSites, ['North Plant', 'test']);

      final unknownDeptSites = context.permittedSiteNamesForDepartmentName(
        'Finance',
      );
      expect(unknownDeptSites, isEmpty);
    });

    test('Finds scope by names and IDs', () {
      final foundByName = context.findScopeByNames('HSE / Safety', 'test');
      expect(foundByName, isNotNull);
      expect(foundByName!.departmentName, 'HSE / Safety');

      final foundByIds = context.findScopeByIds(testDeptId, siteNorthPlantId);
      expect(foundByIds, isNotNull);
      expect(foundByIds!.siteName, 'North Plant');

      final notFound = context.findScopeByNames('Nonexistent', 'Site');
      expect(notFound, isNull);
    });
  });

  group('ActionRecord Serialization & Conversion Tests', () {
    test('Correctly serializes to and deserializes from Supabase payload', () {
      final rawSupabaseRow = {
        'id': 'b13a7bbd-986c-482a-a53d-240eef92e70e',
        'action_number': 'ACT-1001',
        'organization_id': Organization.sobhaId,
        'department_id': 'f0ad05aa-c85a-40e5-b309-19f1e6629e7a',
        'site_id': '6abf4ba5-e8b7-4076-8c97-80f4a354f94b',
        'team_id': null,
        'created_by': '878d9145-7764-411f-8d26-f30f01e99e79',
        'assigned_to': '878d9145-7764-411f-8d26-f30f01e99e79',
        'verified_by': null,
        'title': 'Safety Inspection Remediation',
        'action_required': 'Install secondary guardrail on scaffold',
        'description': 'Scaffold inspection found missing safety lock pin',
        'division': 'Operations & HSSE',
        'priority': 'Critical',
        'status': 'Open',
        'percent_complete': 40,
        'date_raised': '2026-09-21',
        'due_date': '2026-09-28',
        'last_follow_up_date': null,
        'next_follow_up_date': '2026-09-25',
        'closed_at': null,
        'departments': {'name': 'HSE / Safety'},
        'sites': {'name': 'test'},
        'profiles_assigned': {
          'id': '878d9145-7764-411f-8d26-f30f01e99e79',
          'full_name': 'Operations Manager',
          'email': 'webonant@gmail.com',
          'phone': '+971 50 123 4567',
        },
        'sub_tasks': [
          {
            'id': 'st-1',
            'parent_action_id': 'b13a7bbd-986c-482a-a53d-240eef92e70e',
            'title': 'Procure guardrails',
            'instruction': 'Contact warehouse',
            'assigned_staff': 'Operations Manager',
            'assigned_staff_id': '878d9145-7764-411f-8d26-f30f01e99e79',
            'due_date': '2026-09-24',
            'status': 'Open',
            'progress_weight': 50,
          },
        ],
      };

      final record = ActionRecord.fromSupabase(rawSupabaseRow);

      expect(record.id, 'b13a7bbd-986c-482a-a53d-240eef92e70e');
      expect(record.actionNumber, 'ACT-1001');
      expect(record.displayId, 'ACT-1001');
      expect(record.subject, 'Safety Inspection Remediation');
      expect(record.actionRequired, 'Install secondary guardrail on scaffold');
      expect(record.department, 'HSE / Safety');
      expect(record.site, 'test');
      expect(record.priority, 'Critical');
      expect(record.status, 'Open');
      expect(record.percentComplete, 40);
      expect(record.assignedTo, 'Operations Manager');
      expect(record.targetDate, '28 Sep 2026');
      expect(record.targetDateTime, isNotNull);
      expect(record.subTasks.length, 1);
      expect(record.subTasks.first.title, 'Procure guardrails');

      // Test Insert Map serialization
      final insertMap = record.toSupabaseInsertMap();
      expect(insertMap['organization_id'], Organization.sobhaId);
      expect(
        insertMap['department_id'],
        'f0ad05aa-c85a-40e5-b309-19f1e6629e7a',
      );
      expect(insertMap['site_id'], '6abf4ba5-e8b7-4076-8c97-80f4a354f94b');
      expect(insertMap['title'], 'Safety Inspection Remediation');
      expect(insertMap['priority'], 'Critical');
      expect(insertMap['status'], 'Open');
      expect(insertMap['percent_complete'], 40);
      expect(insertMap['due_date'], '2026-09-28');
    });

    test(
      'Date formatting helpers handle both ISO and UI formats Bidirectionally',
      () {
        expect(ActionRecord.formatDateForDb('28 Sep 2026'), '2026-09-28');
        expect(ActionRecord.formatDateForDb('05 Jan 2027'), '2027-01-05');
        expect(ActionRecord.formatDateForDb('2026-09-28'), '2026-09-28');

        expect(ActionRecord.formatDateForUi('2026-09-28'), '28 Sep 2026');
        expect(
          ActionRecord.formatDateForUi(DateTime(2026, 9, 28)),
          '28 Sep 2026',
        );
        expect(ActionRecord.formatDateForUi('28 Sep 2026'), '28 Sep 2026');
      },
    );
  });

  group('Dashboard Metrics Calculation Tests', () {
    test('Computes correct operational summary metrics', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final in3Days = today.add(const Duration(days: 3));
      final in30Days = today.add(const Duration(days: 30));

      final actions = [
        ActionRecord(
          id: '1',
          actionNumber: 'ACT-1001',
          subject: 'Critical Overdue Action',
          actionRequired: 'Fix leak',
          division: 'Operations',
          assignedTo: 'Engineer A',
          priority: 'Critical',
          status: 'Open',
          targetDate: ActionRecord.formatDateForUi(yesterday),
        ),
        ActionRecord(
          id: '2',
          actionNumber: 'ACT-1002',
          subject: 'Due Soon High Priority Action',
          actionRequired: 'Inspect harness',
          division: 'Operations',
          assignedTo: 'Engineer B',
          priority: 'High',
          status: 'In Progress',
          targetDate: ActionRecord.formatDateForUi(in3Days),
          nextFollowUpDate: ActionRecord.formatDateForUi(today),
        ),
        ActionRecord(
          id: '3',
          actionNumber: 'ACT-1003',
          subject: 'Medium Pending Review Action',
          actionRequired: 'Review logs',
          division: 'Operations',
          assignedTo: 'Engineer C',
          priority: 'Medium',
          status: 'Pending Review',
          targetDate: ActionRecord.formatDateForUi(in30Days),
        ),
        ActionRecord(
          id: '4',
          actionNumber: 'ACT-1004',
          subject: 'Completed Action',
          actionRequired: 'Fire drill',
          division: 'Operations',
          assignedTo: 'Engineer D',
          priority: 'Low',
          status: 'Closed',
          targetDate: ActionRecord.formatDateForUi(yesterday),
        ),
      ];

      final metrics = ActionService.instance.computeDashboardMetrics(actions);

      expect(metrics.total, 4);
      expect(metrics.open, 1);
      expect(metrics.inProgress, 1);
      expect(metrics.pendingReview, 1);
      expect(metrics.overdue, 1); // Only ACT-1001 (ACT-1004 is closed)
      expect(metrics.dueSoon, 1); // ACT-1002 (within 7 days)
      expect(metrics.followUpDue, 1); // ACT-1002 (follow-up date is today)
      expect(metrics.criticalHigh, 2); // ACT-1001 (Critical) + ACT-1002 (High)
      expect(metrics.closed, 1); // ACT-1004
    });
  });
}
