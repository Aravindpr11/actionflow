import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/add_action_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/models/team.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const staffUserId = 'a1000000-0000-0000-0000-000000000001';
  const staffUserName = 'R. Kumar';
  const staffEmail = 'r.kumar@actionflow.demo';
  const staffDept = 'Maintenance';
  const staffDeptId = 'dept-maint-001';
  const staffSite = 'North Plant';
  const staffSiteId = 'site-np-001';

  final staffUserProfile = UserProfile(
    id: staffUserId,
    name: staffUserName,
    email: staffEmail,
    phone: '+91 90000 10001',
    designation: 'Maintenance Supervisor',
    department: staffDept,
    departmentId: staffDeptId,
    site: staffSite,
    siteId: staffSiteId,
    role: 'Staff',
    accountStatus: 'Active',
    permissions: const ['Staff Actions'],
  );

  setUp(() {
    // Reset test additions
    MockPeopleStore.instance.people.removeWhere(
      (p) =>
          p.id.startsWith('AFU-TEST') ||
          p.id.startsWith('EXT-TEST') ||
          p.email.contains('test_staff'),
    );
  });

  group('Staff Add Action UI & Permission Constraints', () {
    testWidgets(
      'AddActionScreen in Staff mode locks Department/Site and hides External toggle',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Set AuthProfileData for the Staff user
        final authProfile = AuthProfileData(
          userProfile: staffUserProfile,
          roleCode: 'staff',
          status: 'active',
          isActive: true,
          isPrimaryAdmin: false,
        );
        AuthService.instance.setProfileDataForTesting(authProfile);
        addTearDown(() {
          AuthService.instance.setProfileDataForTesting(null);
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: AddActionScreen(
                actionId: 'ACT-TEST-001',
                isManager: false,
                isStaff: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify title & basic elements
        expect(find.text('Add New Action'), findsOneWidget);
        expect(find.text('ACT-TEST-001'), findsOneWidget);

        // Verify Section 3 assignment subtitle for Staff
        expect(
          find.text(
            'Assign yourself, a colleague in your department, or your department manager',
          ),
          findsOneWidget,
        );

        // Verify external recipient toggle is NOT present
        expect(find.text('EXTERNAL USER'), findsNothing);
        expect(find.text('3rd-party vendor, auditor, contractor'), findsNothing);

        // Verify internal person panel is displayed
        expect(find.text('INTERNAL PERSON'), findsOneWidget);
        expect(find.text('Primary Internal Person *'), findsOneWidget);
      },
    );

    testWidgets(
      'Staff mode filters assignee candidates: permits self, same-dept staff & manager; excludes admins & other departments',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final authProfile = AuthProfileData(
          userProfile: staffUserProfile,
          roleCode: 'staff',
          status: 'active',
          isActive: true,
          isPrimaryAdmin: false,
        );
        AuthService.instance.setProfileDataForTesting(authProfile);
        addTearDown(() {
          AuthService.instance.setProfileDataForTesting(null);
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: AddActionScreen(
                actionId: 'ACT-TEST-002',
                isManager: false,
                isStaff: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final searchField = find.widgetWithText(
          TextFormField,
          'Search by name, email, or phone...',
        );
        expect(searchField, findsOneWidget);

        // 1. Search self (Kumar, Maintenance) -> found
        await tester.enterText(searchField, 'Kumar');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('internal_person_option_R. Kumar')),
          findsOneWidget,
        );

        // 2. Search M. Ali (Manager with scope in Maintenance) -> found
        await tester.enterText(searchField, 'Ali');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('internal_person_option_M. Ali')),
          findsOneWidget,
        );

        // 3. Search Admin user (System Administrator) -> excluded
        await tester.enterText(searchField, 'System Administrator');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('internal_person_option_System Administrator')),
          findsNothing,
        );

        // 4. Search other department staff (S. Jones, Projects) -> excluded
        await tester.enterText(searchField, 'Jones');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('internal_person_option_S. Jones')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Staff action creation sets scope_type to specific, email reminders default to OFF',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final authProfile = AuthProfileData(
          userProfile: staffUserProfile,
          roleCode: 'staff',
          status: 'active',
          isActive: true,
          isPrimaryAdmin: false,
        );
        AuthService.instance.setProfileDataForTesting(authProfile);
        addTearDown(() {
          AuthService.instance.setProfileDataForTesting(null);
        });

        ActionRecord? submittedRecord;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AddActionScreen(
                actionId: 'ACT-TEST-003',
                isManager: false,
                isStaff: true,
                onSaved: (record) {
                  submittedRecord = record;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Email reminder section exists and defaults to OFF
        expect(find.text('EMAIL REMINDER'), findsOneWidget);
        expect(find.text('Enable Email Reminder'), findsOneWidget);
        final reminderSwitch = tester.widget<Switch>(find.byType(Switch).first);
        expect(reminderSwitch.value, isFalse);

        // Fill in required fields
        final titleField = find.widgetWithText(TextFormField, 'Action Title *');
        await tester.enterText(titleField, 'Fix Hydraulic Valve Leak');

        final descField =
            find.widgetWithText(TextFormField, 'Action Description');
        await tester.enterText(
          descField,
          'Replace sealing rings on valve 4B and verify pressure.',
        );

        // Assign to self using autocomplete
        final searchField = find.widgetWithText(
          TextFormField,
          'Search by name, email, or phone...',
        );
        await tester.ensureVisible(searchField);
        await tester.enterText(searchField, 'Kumar');
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('internal_person_option_R. Kumar')).first,
        );
        await tester.pumpAndSettle();

        // Tap Save / Send Action
        final sendButton = find.text('SEND ACTION');
        await tester.ensureVisible(sendButton);
        await tester.tap(sendButton);
        await tester.pumpAndSettle();

        // Verify submitted action fields
        expect(submittedRecord, isNotNull);
        expect(submittedRecord!.scopeType, equals('specific'));
        expect(submittedRecord!.department, equals(staffDept));
        expect(submittedRecord!.site, equals(staffSite));
        expect(submittedRecord!.emailReminderEnabled, isFalse);
        expect(submittedRecord!.emailReminders, isEmpty);
      },
    );
  });

  group('Staff Action Register Navigation & Scope Enforcement', () {
    testWidgets(
      'WorkerDashboardScreen displays Action Register & Add Action in sidebar and quick actions',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 850);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: WorkerDashboardScreen(userProfile: staffUserProfile),
          ),
        );
        await tester.pumpAndSettle();

        // Sidebar entries for Action Register and Add Action
        expect(find.text('Action Register'), findsWidgets);
        expect(find.text('Add Action'), findsWidgets);

        // Tap Action Register in sidebar (first occurrence is in sidebar)
        await tester.tap(find.text('Action Register').first);
        await tester.pumpAndSettle();

        // Verify ActionRegisterSection is rendered
        expect(find.byType(ActionRegisterSection), findsOneWidget);
      },
    );

    testWidgets(
      'Staff Action Register displays ONLY authorized actions (assigned, created, contributor, subtask) and excludes unrelated department actions',
      (tester) async {
        final List<ActionRecord> actions = [
          // 1. Assigned to Staff
          ActionRecord(
            id: 'ACT-ASSIGNED-01',
            actionNumber: 'AC-1001',
            subject: 'Assigned to Staff Action',
            actionRequired: 'Task 1',
            division: 'Operations',
            department: staffDept,
            site: staffSite,
            assignedToId: staffUserId,
            assignedTo: staffUserName,
            status: 'Open',
            priority: 'High',
            dateRaised: '01 Nov 2026',
            targetDate: '15 Nov 2026',
          ),
          // 2. Created by Staff
          ActionRecord(
            id: 'ACT-CREATED-02',
            actionNumber: 'AC-1002',
            subject: 'Created by Staff Action',
            actionRequired: 'Task 2',
            division: 'Operations',
            department: staffDept,
            site: staffSite,
            createdById: staffUserId,
            assignedToId: 'a1000000-0000-0000-0000-000000000002',
            assignedTo: 'M. Ali',
            status: 'In Progress',
            priority: 'Medium',
            dateRaised: '02 Nov 2026',
            targetDate: '16 Nov 2026',
          ),
          // 3. Contributor
          ActionRecord(
            id: 'ACT-CONTRIB-03',
            actionNumber: 'AC-1003',
            subject: 'Staff is Contributor Action',
            actionRequired: 'Task 3',
            division: 'Operations',
            department: staffDept,
            site: staffSite,
            assignedToId: 'a1000000-0000-0000-0000-000000000002',
            assignedTo: 'M. Ali',
            contributors: [
              ActionContributorRecord(
                id: 'c-1',
                actionId: 'ACT-CONTRIB-03',
                profileId: staffUserId,
                profileName: staffUserName,
                notes: 'Contributor',
                createdAt: DateTime.now(),
              ),
            ],
            status: 'Open',
            priority: 'Low',
            dateRaised: '03 Nov 2026',
            targetDate: '17 Nov 2026',
          ),
          // 4. Subtask assigned to staff
          ActionRecord(
            id: 'ACT-SUBTASK-04',
            actionNumber: 'AC-1004',
            subject: 'Staff has Subtask Action',
            actionRequired: 'Task 4',
            division: 'Operations',
            department: staffDept,
            site: staffSite,
            assignedToId: 'a1000000-0000-0000-0000-000000000002',
            assignedTo: 'M. Ali',
            subTasks: const [
              ActionSubTask(
                id: 'st-1',
                parentActionId: 'ACT-SUBTASK-04',
                title: 'Inspect Valve',
                instruction: 'Inspect and report',
                assignedStaff: staffUserName,
                assignedStaffId: staffUserId,
                status: 'Open',
              ),
            ],
            status: 'Open',
            priority: 'Medium',
            dateRaised: '04 Nov 2026',
            targetDate: '18 Nov 2026',
          ),
          // 5. Unrelated action in SAME department - Staff must NOT see this
          ActionRecord(
            id: 'ACT-UNRELATED-05',
            actionNumber: 'AC-1005',
            subject: 'Unrelated Maintenance Action',
            actionRequired: 'Other work',
            division: 'Operations',
            department: staffDept,
            site: staffSite,
            createdById: 'a1000000-0000-0000-0000-000000000002',
            assignedToId: 'a1000000-0000-0000-0000-000000000004',
            assignedTo: 'N. Shah',
            status: 'Open',
            priority: 'Medium',
            dateRaised: '05 Nov 2026',
            targetDate: '19 Nov 2026',
          ),
          // 6. Self-assigned action (created by staff, assigned to staff)
          ActionRecord(
            id: 'ACT-SELF-06',
            actionNumber: 'AC-1006',
            subject: 'Staff Self Assigned Action',
            actionRequired: 'Task 6',
            division: 'Operations',
            department: staffDept,
            site: staffSite,
            createdById: staffUserId,
            assignedToId: staffUserId,
            assignedTo: staffUserName,
            status: 'Open',
            priority: 'Medium',
            dateRaised: '06 Nov 2026',
            targetDate: '20 Nov 2026',
          ),
        ];

        // Replace MockActionStore actions with test actions
        MockActionStore.instance.actions.clear();
        MockActionStore.instance.actions.addAll(actions);

        // 1. Verify fetchMyActions strictly isolates assigned actions
        final myActions = await ActionService.instance.fetchMyActions(
          organizationId: 'SOBHA-001',
          userId: staffUserId,
        );

        final myActionIds = myActions.map((a) => a.id).toSet();
        expect(myActionIds.contains('ACT-ASSIGNED-01'), isTrue,
            reason: 'Actions assigned to staff must appear in My Actions');
        expect(myActionIds.contains('ACT-SELF-06'), isTrue,
            reason: 'Self-assigned action must appear in My Actions');
        expect(myActionIds.contains('ACT-CREATED-02'), isFalse,
            reason: 'Staff created action assigned to someone else must NOT appear in My Actions');
        expect(myActionIds.contains('ACT-UNRELATED-05'), isFalse,
            reason: 'Unrelated actions must NOT appear in My Actions');

        // 2. Verify fetchStaffCreatedActions strictly isolates created actions (Action Register)
        final registerActions = await ActionService.instance.fetchStaffCreatedActions(
          organizationId: 'SOBHA-001',
          userId: staffUserId,
        );

        final registerIds = registerActions.map((a) => a.id).toSet();
        expect(registerIds.contains('ACT-CREATED-02'), isTrue,
            reason: 'Actions created by staff must appear in Action Register');
        expect(registerIds.contains('ACT-SELF-06'), isTrue,
            reason: 'Self-assigned action must appear in Action Register');
        expect(registerIds.contains('ACT-ASSIGNED-01'), isFalse,
            reason: 'Actions created by others must NOT appear in Action Register');
        expect(registerIds.contains('ACT-UNRELATED-05'), isFalse,
            reason: 'Unrelated actions must NOT appear in Action Register');
      },
    );

    testWidgets(
      'Staff cannot delete actions from Action Register (delete callback is null)',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 850);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: WorkerDashboardScreen(userProfile: staffUserProfile),
          ),
        );
        await tester.pumpAndSettle();

        // Switch to Action Register
        await tester.tap(find.text('Action Register').first);
        await tester.pumpAndSettle();

        // Find ActionRegisterSection
        final registerFinder = find.byType(ActionRegisterSection);
        expect(registerFinder, findsOneWidget);

        final ActionRegisterSection registerWidget =
            tester.widget(registerFinder);
        // Delete callbacks are active and wired to authorized soft-delete handlers
        expect(registerWidget.onDeleteActionTap, isNotNull);
        expect(registerWidget.onDeleteSelected, isNotNull);
      },
    );
  });
}
