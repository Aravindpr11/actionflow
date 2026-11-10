import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ActionRecord Assignment Type Data Getters', () {
    test('Purely internal action identifies as internal only', () {
      final record = ActionRecord(
        id: 'ACT-INT-1',
        subject: 'Internal Inspection',
        actionRequired: 'Check plant filters',
        division: 'Operations',
        assignedTo: 'R. Kumar',
        assignedBy: 'M. Ali',
        primaryAssignee: const ActionPersonReference(
          personId: 'user-internal-1',
          name: 'R. Kumar',
          email: 'r.kumar@actionflow.demo',
          type: PersonType.internalUser,
        ),
        recipientType: 'internal',
      );

      expect(record.hasInternalAssignee, isTrue);
      expect(record.hasExternalAssignee, isFalse);
    });

    test('Purely external action identifies as external only', () {
      final record = ActionRecord(
        id: 'ACT-EXT-1',
        subject: 'External Crane Service',
        actionRequired: 'Recertify crane cables',
        division: 'Operations',
        assignedTo: 'Jane External',
        assignedBy: 'M. Ali',
        primaryAssignee: const ActionPersonReference(
          personId: 'ext-user-1',
          name: 'Jane External',
          email: 'jane@contractor.demo',
          type: PersonType.externalWorker,
        ),
        recipientType: 'external',
        externalRecipientId: 'ext-user-1',
      );

      expect(record.hasInternalAssignee, isFalse);
      expect(record.hasExternalAssignee, isTrue);
    });

    test('Dual-assigned action (primary internal, secondary external) identifies as both', () {
      final record = ActionRecord(
        id: 'ACT-DUAL-1',
        subject: 'Joint Site Audit',
        actionRequired: 'Audit scaffolding alongside contractor team',
        division: 'Operations',
        assignedTo: 'M. Ali',
        assignedBy: 'System',
        primaryAssignee: const ActionPersonReference(
          personId: 'user-internal-2',
          name: 'M. Ali',
          email: 'm.ali@actionflow.demo',
          type: PersonType.internalUser,
        ),
        recipientType: 'internal',
        additionalPeople: const [
          ActionPersonReference(
            personId: 'ext-user-2',
            name: 'Bob Contractor',
            email: 'bob@scaffolding.demo',
            type: PersonType.externalWorker,
          ),
        ],
      );

      expect(record.hasInternalAssignee, isTrue);
      expect(record.hasExternalAssignee, isTrue);
    });

    test('Dual-assigned action (primary external, secondary internal) identifies as both', () {
      final record = ActionRecord(
        id: 'ACT-DUAL-2',
        subject: 'HVAC Overhaul',
        actionRequired: 'Replace chiller compresser',
        division: 'Operations',
        assignedTo: 'Cooling Specialist',
        assignedBy: 'M. Ali',
        primaryAssignee: const ActionPersonReference(
          personId: 'ext-user-3',
          name: 'Cooling Specialist',
          email: 'specialist@hvac.demo',
          type: PersonType.externalWorker,
        ),
        recipientType: 'external',
        externalRecipientId: 'ext-user-3',
        assignees: const [
          ActionAssigneeRecord(
            id: 'assignee-row-1',
            actionId: 'ACT-DUAL-2',
            profileId: 'internal-staff-3',
            assignedBy: 'M. Ali',
          ),
        ],
      );

      expect(record.hasInternalAssignee, isTrue);
      expect(record.hasExternalAssignee, isTrue);
    });

    test('Assignment determination is not influenced by user name or email string values', () {
      final record = ActionRecord(
        id: 'ACT-NAME-TEST',
        subject: 'String Invariance Test',
        actionRequired: 'Check assignees regardless of names/emails',
        division: 'Operations',
        assignedTo: 'External Vendor Guy',
        assignedBy: 'Admin',
        primaryAssignee: const ActionPersonReference(
          personId: 'real-internal-profile-uuid',
          name: 'External Vendor Guy',
          email: 'vendor@external-domain.org',
          type: PersonType.internalUser,
        ),
      );

      expect(record.hasInternalAssignee, isTrue);
      expect(record.hasExternalAssignee, isFalse);
    });
  });

  group('Manager Action Register Assignment Type Filter UI', () {
    testWidgets('Filters Action Register by All, Internal User, and External User correctly', (tester) async {
      tester.view.physicalSize = const Size(2600, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final internalAction = ActionRecord(
        id: 'AF-INT-101',
        actionNumber: 'AF-INT-101',
        subject: 'Internal Boiler Check',
        actionRequired: 'Check boiler sensors',
        division: 'Operations',
        department: 'Maintenance',
        site: 'North Plant',
        assignedBy: 'M. Ali',
        assignedTo: 'R. Kumar',
        dateRaised: '01 Aug 2026',
        targetDate: '12 Aug 2026',
        priority: 'Medium',
        status: 'Open',
        percentComplete: 0,
        primaryAssignee: const ActionPersonReference(
          personId: 'user-kumar',
          name: 'R. Kumar',
          email: 'r.kumar@actionflow.demo',
          type: PersonType.internalUser,
        ),
        recipientType: 'internal',
      );

      final externalAction = ActionRecord(
        id: 'AF-EXT-102',
        actionNumber: 'AF-EXT-102',
        subject: 'Contractor Scaffolding Fix',
        actionRequired: 'Repair scaffolding joints',
        division: 'Operations',
        department: 'HSE',
        site: 'Warehouse B',
        assignedBy: 'M. Ali',
        assignedTo: 'Jane External',
        dateRaised: '02 Aug 2026',
        targetDate: '15 Aug 2026',
        priority: 'High',
        status: 'Open',
        percentComplete: 10,
        primaryAssignee: const ActionPersonReference(
          personId: 'ext-jane',
          name: 'Jane External',
          email: 'jane@contractor.demo',
          type: PersonType.externalWorker,
        ),
        recipientType: 'external',
        externalRecipientId: 'ext-jane',
      );

      final dualAction = ActionRecord(
        id: 'AF-DUAL-103',
        actionNumber: 'AF-DUAL-103',
        subject: 'Joint Electrical Inspection',
        actionRequired: 'Review main breakers with external engineer',
        division: 'Operations',
        department: 'Maintenance',
        site: 'North Plant',
        assignedBy: 'M. Ali',
        assignedTo: 'R. Kumar',
        dateRaised: '03 Aug 2026',
        targetDate: '18 Aug 2026',
        priority: 'Critical',
        status: 'In Progress',
        percentComplete: 50,
        primaryAssignee: const ActionPersonReference(
          personId: 'user-kumar',
          name: 'R. Kumar',
          email: 'r.kumar@actionflow.demo',
          type: PersonType.internalUser,
        ),
        recipientType: 'internal',
        additionalPeople: const [
          ActionPersonReference(
            personId: 'ext-bob',
            name: 'Bob Electrical',
            email: 'bob@subcontractor.demo',
            type: PersonType.externalWorker,
          ),
        ],
      );

      const testManagerProfile = UserProfile(
        id: 'mgr-001',
        name: 'M. Ali',
        email: 'm.ali@actionflow.demo',
        phone: '+971501234567',
        designation: 'HSE Manager',
        department: 'HSE',
        site: 'Warehouse B',
        role: 'manager',
      );

      const testManagerContext = ManagerContext(
        authUserId: 'mgr-001',
        profile: testManagerProfile,
        organizationId: 'org-sobha',
        organizationName: 'Sobha Constructions',
        scopes: [
          ManagerScopeItem(
            departmentId: 'dept-hse',
            departmentName: 'HSE',
            siteId: 'site-whb',
            siteName: 'Warehouse B',
          ),
          ManagerScopeItem(
            departmentId: 'dept-maint',
            departmentName: 'Maintenance',
            siteId: 'site-np',
            siteName: 'North Plant',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ManagerDashboardScreen(
            userProfile: testManagerProfile,
            managerContext: testManagerContext,
            initialActions: [internalAction, externalAction, dualAction],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Action Register
      await tester.tap(find.text('Action Register').first);
      await tester.pumpAndSettle();

      expect(find.text('Internal Boiler Check'), findsOneWidget);
      expect(find.text('Contractor Scaffolding Fix'), findsOneWidget);
      expect(find.text('Joint Electrical Inspection'), findsOneWidget);

      // Filter by Internal User
      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Assignment Type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Internal User').last);
      await tester.pumpAndSettle();

      expect(find.text('Internal Boiler Check'), findsOneWidget);
      expect(find.text('Joint Electrical Inspection'), findsOneWidget);
      expect(find.text('Contractor Scaffolding Fix'), findsNothing);

      // Filter by External User
      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Assignment Type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('External User').last);
      await tester.pumpAndSettle();

      expect(find.text('Contractor Scaffolding Fix'), findsOneWidget);
      expect(find.text('Joint Electrical Inspection'), findsOneWidget);
      expect(find.text('Internal Boiler Check'), findsNothing);

      // Filter by All
      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Assignment Type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All').last);
      await tester.pumpAndSettle();

      expect(find.text('Internal Boiler Check'), findsOneWidget);
      expect(find.text('Contractor Scaffolding Fix'), findsOneWidget);
      expect(find.text('Joint Electrical Inspection'), findsOneWidget);
    });
  });
}

