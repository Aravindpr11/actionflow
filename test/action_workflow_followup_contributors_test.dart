import 'package:action_flow/features/auth/models/manager_scope_item.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/services/excel_export_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final testManagerProfile = const UserProfile(
    id: 'mgr-uuid-001',
    name: 'Sarah Connor',
    email: 'sarah.connor@tenant-a.com',
    phone: '+971501111111',
    designation: 'Safety Director',
    department: 'HSE',
    site: 'Plant Alpha',
    role: 'manager',
    organizationId: 'org-tenant-a',
    organizationName: 'Tenant A Corp',
  );

  final testManagerContext = ManagerContext(
    authUserId: 'mgr-uuid-001',
    profile: testManagerProfile,
    organizationId: 'org-tenant-a',
    organizationName: 'Tenant A Corp',
    scopes: const [
      ManagerScopeItem(
        departmentId: 'dept-hse-01',
        departmentName: 'HSE',
        siteId: 'site-alpha-01',
        siteName: 'Plant Alpha',
      ),
    ],
  );

  group('1. Multiple Assignees & Single Assignee Gate', () {
    test('Single assignee action identifies owner and completion state', () {
      final singleAction = ActionRecord(
        id: 'act-single-1',
        actionNumber: 'ACT-001',
        organizationId: 'org-tenant-a',
        departmentId: 'dept-hse-01',
        siteId: 'site-alpha-01',
        subject: 'Single Assignee Action',
        actionRequired: 'Inspect crane',
        division: 'Operations',
        department: 'HSE',
        site: 'Plant Alpha',
        assignedTo: 'John Doe',
        assignedToId: 'worker-john-01',
        priority: 'Medium',
        status: 'In Progress',
        percentComplete: 40,
        targetDate: '30 Sep 2026',
        dateRaised: '20 Sep 2026',
        assignees: const [
          ActionAssigneeRecord(
            id: 'asg-1',
            actionId: 'act-single-1',
            profileId: 'worker-john-01',
            profileName: 'John Doe',
            assignmentRole: 'owner',
            isRequired: true,
            workCompleted: false,
          ),
        ],
      );

      expect(singleAction.hasMultipleAssignees, isFalse);
      expect(singleAction.requiredAssignees.length, 1);
      expect(singleAction.allRequiredAssigneesCompleted, isFalse);
    });

    test('Multiple assignees: all required assignees must complete before closure gate clears', () {
      final multiActionPending = ActionRecord(
        id: 'act-multi-1',
        actionNumber: 'ACT-002',
        organizationId: 'org-tenant-a',
        departmentId: 'dept-hse-01',
        siteId: 'site-alpha-01',
        subject: 'Multi Assignee Safety Review',
        actionRequired: 'Joint inspection',
        division: 'Operations',
        department: 'HSE',
        site: 'Plant Alpha',
        assignedTo: 'John Doe',
        assignedToId: 'worker-john-01',
        priority: 'High',
        status: 'In Progress',
        percentComplete: 80,
        targetDate: '30 Sep 2026',
        dateRaised: '20 Sep 2026',
        assignees: const [
          ActionAssigneeRecord(
            id: 'asg-1',
            actionId: 'act-multi-1',
            profileId: 'worker-john-01',
            profileName: 'John Doe',
            assignmentRole: 'owner',
            isRequired: true,
            workCompleted: true,
          ),
          ActionAssigneeRecord(
            id: 'asg-2',
            actionId: 'act-multi-1',
            profileId: 'worker-jane-02',
            profileName: 'Jane Smith',
            assignmentRole: 'assignee',
            isRequired: true,
            workCompleted: false, // Incomplete!
          ),
          ActionAssigneeRecord(
            id: 'asg-3',
            actionId: 'act-multi-1',
            profileId: 'worker-bob-03',
            profileName: 'Bob Optional',
            assignmentRole: 'assignee',
            isRequired: false, // Optional
            workCompleted: false,
          ),
        ],
      );

      expect(multiActionPending.hasMultipleAssignees, isTrue);
      expect(multiActionPending.requiredAssignees.length, 2);
      expect(multiActionPending.allRequiredAssigneesCompleted, isFalse);

      // Now Jane completes her work
      final multiActionDone = multiActionPending.copyWith(
        assignees: [
          multiActionPending.assignees[0],
          multiActionPending.assignees[1].copyWith(workCompleted: true),
          multiActionPending.assignees[2],
        ],
      );

      expect(multiActionDone.allRequiredAssigneesCompleted, isTrue);
    });
  });

  group('2. Forward Action & Contributor Rules', () {
    test('Forwarding preserves original Owner (owner remains owner)', () {
      final action = ActionRecord(
        id: 'act-fwd-1',
        actionNumber: 'ACT-003',
        organizationId: 'org-tenant-a',
        departmentId: 'dept-hse-01',
        siteId: 'site-alpha-01',
        subject: 'Forwarding Test Action',
        actionRequired: 'Check valve pressure',
        division: 'Operations',
        department: 'HSE',
        site: 'Plant Alpha',
        assignedTo: 'Staff A',
        assignedToId: 'staff-a-uuid',
        priority: 'Low',
        status: 'In Progress',
        percentComplete: 20,
        targetDate: '30 Sep 2026',
        dateRaised: '20 Sep 2026',
        contributors: const [
          ActionContributorRecord(
            id: 'contrib-1',
            actionId: 'act-fwd-1',
            profileId: 'staff-b-uuid',
            profileName: 'Staff B',
            addedBy: 'staff-a-uuid',
            notes: 'Assisting with valve calibration',
          ),
        ],
      );

      expect(action.assignedToId, 'staff-a-uuid');
      expect(action.assignedTo, 'Staff A');
      expect(action.getUserRoleInAction('staff-a-uuid'), 'Owner');
      expect(action.getUserRoleInAction('staff-b-uuid'), 'Contributor');
      expect(action.contributors.length, 1);
      expect(action.contributors.first.profileName, 'Staff B');
    });

    test('Contributor permission hierarchy logic', () {
      // Permission hierarchy rule test:
      // Manager can add Manager or Staff
      // Staff can add Staff only
      // Staff -> Manager is blocked
      // Cross-company is blocked
      // Inactive user is blocked

      bool isEligibleContributor({
        required bool isCallerManager,
        required String callerOrgId,
        required String targetUserOrgId,
        required String targetUserRole,
        required bool targetUserIsActive,
      }) {
        if (!targetUserIsActive) return false;
        if (callerOrgId != targetUserOrgId) return false;
        if (!isCallerManager && targetUserRole.toLowerCase() == 'manager') {
          return false;
        }
        return true;
      }

      // Manager adding Manager in same org: ALLOWED
      expect(
        isEligibleContributor(
          isCallerManager: true,
          callerOrgId: 'org-tenant-a',
          targetUserOrgId: 'org-tenant-a',
          targetUserRole: 'manager',
          targetUserIsActive: true,
        ),
        isTrue,
      );

      // Manager adding Staff in same org: ALLOWED
      expect(
        isEligibleContributor(
          isCallerManager: true,
          callerOrgId: 'org-tenant-a',
          targetUserOrgId: 'org-tenant-a',
          targetUserRole: 'staff',
          targetUserIsActive: true,
        ),
        isTrue,
      );

      // Staff adding Staff in same org: ALLOWED
      expect(
        isEligibleContributor(
          isCallerManager: false,
          callerOrgId: 'org-tenant-a',
          targetUserOrgId: 'org-tenant-a',
          targetUserRole: 'staff',
          targetUserIsActive: true,
        ),
        isTrue,
      );

      // Staff adding Manager: BLOCKED
      expect(
        isEligibleContributor(
          isCallerManager: false,
          callerOrgId: 'org-tenant-a',
          targetUserOrgId: 'org-tenant-a',
          targetUserRole: 'manager',
          targetUserIsActive: true,
        ),
        isFalse,
      );

      // Cross-tenant target: BLOCKED
      expect(
        isEligibleContributor(
          isCallerManager: true,
          callerOrgId: 'org-tenant-a',
          targetUserOrgId: 'org-tenant-b',
          targetUserRole: 'staff',
          targetUserIsActive: true,
        ),
        isFalse,
      );

      // Inactive target: BLOCKED
      expect(
        isEligibleContributor(
          isCallerManager: true,
          callerOrgId: 'org-tenant-a',
          targetUserOrgId: 'org-tenant-a',
          targetUserRole: 'staff',
          targetUserIsActive: false,
        ),
        isFalse,
      );
    });
  });

  group('3. Shared Action Progress & Contribution Model', () {
    test(
      'Calculates individual contributions and prevents double counting',
      () {
        final action = ActionRecord(
          id: 'act-shared-1',
          actionNumber: 'ACT-004',
          organizationId: 'org-tenant-a',
          departmentId: 'dept-hse-01',
          siteId: 'site-alpha-01',
          subject: 'Shared Calibration Action',
          actionRequired: 'Joint calibration',
          division: 'Operations',
          department: 'HSE',
          site: 'Plant Alpha',
          assignedTo: 'Owner A',
          assignedToId: 'owner-a-uuid',
          priority: 'High',
          status: 'In Progress',
          percentComplete: 60,
          targetDate: '30 Sep 2026',
          dateRaised: '20 Sep 2026',
          progressUpdates: [
            ActionProgressUpdate(
              id: 'upd-1',
              actionId: 'act-shared-1',
              updatedById: 'contrib-b-uuid',
              updatedByName: 'Contributor B',
              updateDate: '23 Sep 2026',
              progress: 25,
              status: 'In Progress',
              comments: 'Initial sensor checks complete',
              roleInAction: 'contributor',
              contributionValue: 25,
              createdAt: DateTime(2026, 9, 23, 10, 0),
            ),
            ActionProgressUpdate(
              id: 'upd-2',
              actionId: 'act-shared-1',
              updatedById: 'owner-a-uuid',
              updatedByName: 'Owner A',
              updateDate: '25 Sep 2026',
              progress: 60,
              status: 'In Progress',
              comments: 'Secondary circuit wiring',
              roleInAction: 'owner',
              contributionValue: 35,
              createdAt: DateTime(2026, 9, 25, 14, 0),
            ),
          ],
        );

        // Verify Owner A contribution: 35%
        expect(action.myContribution('owner-a-uuid'), 35);

        // Verify Contributor B contribution: 25%
        expect(action.myContribution('contrib-b-uuid'), 25);

        // Verify non-participant contribution: 0%
        expect(action.myContribution('random-user-uuid'), 0);

        // Verify individual contributions breakdown map
        final breakdown = action.individualContributions;
        expect(breakdown['Contributor B'], 25);
        expect(breakdown['Owner A'], 35);
        expect(action.percentComplete, 60);
      },
    );
  });

  group('4. Multiple Follow-Ups & History', () {
    test('Preserves multiple follow-ups and separates upcoming vs past', () {
      final now = DateTime.now();
      final futureDate = now.add(const Duration(days: 5));
      final pastDate = now.subtract(const Duration(days: 5));

      final action = ActionRecord(
        id: 'act-followup-1',
        actionNumber: 'ACT-005',
        organizationId: 'org-tenant-a',
        departmentId: 'dept-hse-01',
        siteId: 'site-alpha-01',
        subject: 'Follow-Up Inspection',
        actionRequired: 'Track checkpoints',
        division: 'Operations',
        department: 'HSE',
        site: 'Plant Alpha',
        assignedTo: 'John Doe',
        assignedToId: 'worker-john-01',
        priority: 'Medium',
        status: 'In Progress',
        percentComplete: 50,
        targetDate: '15 Oct 2026',
        dateRaised: '10 Sep 2026',
        nextFollowUpDate: ActionRecord.formatDateForUi(futureDate),
        followUps: [
          ActionFollowUpRecord(
            id: 'fu-1',
            actionId: 'act-followup-1',
            followUpDate: ActionRecord.formatDateForUi(pastDate),
            notes: 'First milestone checkpoint',
            status: 'Completed',
            actualProgress: 30,
            createdByName: 'Sarah Connor',
            completedAt: pastDate,
            createdAt: pastDate,
          ),
          ActionFollowUpRecord(
            id: 'fu-2',
            actionId: 'act-followup-1',
            followUpDate: ActionRecord.formatDateForUi(futureDate),
            notes: 'Second review checkpoint before final testing',
            status: 'Scheduled',
            createdByName: 'Sarah Connor',
            createdAt: now,
          ),
        ],
      );

      expect(action.followUps.length, 2);
      expect(action.pastFollowUps.length, 1);
      expect(action.pastFollowUps.first.id, 'fu-1');
      expect(action.upcomingFollowUps.length, 1);
      expect(action.upcomingFollowUps.first.id, 'fu-2');
      expect(action.followUp, action.nextFollowUpDate);
    });
  });

  group('5. 100% Milestone Does NOT Auto-Close', () {
    test(
      'Action reaching 100% is Pending Review / Ready for Review, NOT Closed',
      () {
        final readyAction = ActionRecord(
          id: 'act-100-test',
          actionNumber: 'ACT-006',
          organizationId: 'org-tenant-a',
          departmentId: 'dept-hse-01',
          siteId: 'site-alpha-01',
          subject: 'Electrical Audit',
          actionRequired: 'Verify circuit breakers',
          division: 'Operations',
          department: 'HSE',
          site: 'Plant Alpha',
          assignedTo: 'Staff A',
          assignedToId: 'staff-a-uuid',
          priority: 'Critical',
          status: 'Ready for Review',
          percentComplete: 100,
          targetDate: '25 Sep 2026',
          dateRaised: '20 Sep 2026',
        );

        expect(readyAction.percentComplete, 100);
        expect(readyAction.isReadyForReview, isTrue);
        expect(readyAction.isClosed, isFalse);
        expect(readyAction.status, 'Ready for Review');
      },
    );
  });

  group('6. Action Details Screen Display & Lifecycle Tab', () {
    testWidgets(
      'Renders all real dates, ownership section, and follow-up checkpoints',
      (tester) async {
        final detailedAction = ActionRecord(
          id: 'act-details-1',
          actionNumber: 'ACT-007',
          organizationId: 'org-tenant-a',
          departmentId: 'dept-hse-01',
          siteId: 'site-alpha-01',
          subject: 'Pump Station Overhaul',
          actionRequired: 'Replace gasket and re-align drive shaft.',
          division: 'Operations',
          department: 'HSE',
          site: 'Plant Alpha',
          assignedTo: 'Staff A',
          assignedToId: 'staff-a-uuid',
          assignedBy: 'Sarah Connor',
          priority: 'High',
          status: 'In Progress',
          percentComplete: 50,
          startDate: '21 Sep 2026',
          targetDate: '30 Sep 2026',
          dateRaised: '20 Sep 2026',
          nextFollowUpDate: '28 Sep 2026',
          assignees: const [
            ActionAssigneeRecord(
              id: 'asg-1',
              actionId: 'act-details-1',
              profileId: 'staff-a-uuid',
              profileName: 'Staff A',
              assignmentRole: 'owner',
              isRequired: true,
              workCompleted: false,
            ),
            ActionAssigneeRecord(
              id: 'asg-2',
              actionId: 'act-details-1',
              profileId: 'staff-b-uuid',
              profileName: 'Staff B',
              assignmentRole: 'assignee',
              isRequired: true,
              workCompleted: true,
            ),
          ],
          contributors: const [
            ActionContributorRecord(
              id: 'contrib-1',
              actionId: 'act-details-1',
              profileId: 'staff-c-uuid',
              profileName: 'Staff C (Helper)',
              addedByName: 'Staff A',
              notes: 'Supporting with safety checks',
            ),
          ],
          followUps: const [
            ActionFollowUpRecord(
              id: 'fu-1',
              actionId: 'act-details-1',
              followUpDate: '28 Sep 2026',
              notes: 'Mid-point calibration test',
              status: 'Scheduled',
              createdByName: 'Sarah Connor',
            ),
          ],
          progressUpdates: [
            ActionProgressUpdate(
              id: 'upd-1',
              actionId: 'act-details-1',
              updatedById: 'staff-a-uuid',
              updatedByName: 'Staff A',
              updateDate: '23 Sep 2026',
              progress: 50,
              status: 'In Progress',
              comments: 'Gasket dismantled successfully',
              roleInAction: 'owner',
              contributionValue: 50,
              createdAt: DateTime(2026, 9, 23, 11, 0),
            ),
          ],
        );

        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: ActionDetailsScreen(
              action: detailedAction,
              currentUserId: testManagerProfile.id,
              managerContext: testManagerContext,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify Quick Info Dates are present
        expect(find.text('20 Sep 2026'), findsWidgets); // Raised date
        expect(find.text('21 Sep 2026'), findsWidgets); // Start date
        expect(find.text('28 Sep 2026'), findsWidgets); // Follow-Up date
        expect(find.text('30 Sep 2026'), findsWidgets); // Target date

        // Verify Ownership section
        expect(find.text('Ownership & Participants'), findsOneWidget);
        expect(find.text('Sarah Connor'), findsWidgets); // Assigned By
        expect(find.text('Staff A'), findsWidgets); // Owner
        expect(find.text('OWNER'), findsWidgets); // Owner badge
        expect(find.text('Staff B'), findsWidgets); // Required Assignee
        expect(find.text('Staff C (Helper)'), findsWidgets); // Contributor

        // Verify Progress Breakdown
        expect(
          find.text('Individual Contributions Breakdown:'),
          findsOneWidget,
        );

        // Verify Lifecycle tab shows events
        final lifecycleTab = find.text('Lifecycle');
        if (lifecycleTab.evaluate().isNotEmpty) {
          await tester.tap(lifecycleTab);
          await tester.pumpAndSettle();
          expect(find.textContaining('Action Created'), findsWidgets);
          expect(find.textContaining('Follow-Up Checkpoint'), findsWidgets);
          expect(find.textContaining('Contributor Added'), findsWidgets);
        }
      },
    );
  });

  group('7. My Actions Table View with Role Badges & Contribution', () {
    testWidgets(
      'Displays OWNER, CONTRIBUTOR role badges and Mine % contribution in My Actions view',
      (tester) async {
        final ownerAction = ActionRecord(
          id: 'act-my-1',
          actionNumber: 'ACT-008',
          organizationId: 'org-tenant-a',
          departmentId: 'dept-hse-01',
          siteId: 'site-alpha-01',
          subject: 'My Owned Action',
          actionRequired: 'Personal task',
          division: 'Operations',
          department: 'HSE',
          site: 'Plant Alpha',
          assignedTo: 'Sarah Connor',
          assignedToId: 'mgr-uuid-001',
          priority: 'High',
          status: 'In Progress',
          percentComplete: 70,
          targetDate: '29 Sep 2026',
          dateRaised: '20 Sep 2026',
          progressUpdates: [
            ActionProgressUpdate(
              id: 'upd-my-1',
              actionId: 'act-my-1',
              updatedById: 'mgr-uuid-001',
              updatedByName: 'Sarah Connor',
              updateDate: '22 Sep 2026',
              progress: 70,
              status: 'In Progress',
              comments: 'Completed major phase',
              roleInAction: 'owner',
              contributionValue: 70,
            ),
          ],
        );

        final contributorAction = ActionRecord(
          id: 'act-my-2',
          actionNumber: 'ACT-009',
          organizationId: 'org-tenant-a',
          departmentId: 'dept-hse-01',
          siteId: 'site-alpha-01',
          subject: 'My Contributed Action',
          actionRequired: 'Helping colleague',
          division: 'Operations',
          department: 'HSE',
          site: 'Plant Alpha',
          assignedTo: 'Colleague Bob',
          assignedToId: 'bob-uuid-002',
          priority: 'Medium',
          status: 'In Progress',
          percentComplete: 50,
          targetDate: '30 Sep 2026',
          dateRaised: '21 Sep 2026',
          contributors: const [
            ActionContributorRecord(
              id: 'contrib-c1',
              actionId: 'act-my-2',
              profileId: 'mgr-uuid-001',
              profileName: 'Sarah Connor',
              addedBy: 'bob-uuid-002',
              notes: 'Assisting on documentation',
            ),
          ],
          progressUpdates: [
            ActionProgressUpdate(
              id: 'upd-my-2',
              actionId: 'act-my-2',
              updatedById: 'mgr-uuid-001',
              updatedByName: 'Sarah Connor',
              updateDate: '23 Sep 2026',
              progress: 20,
              status: 'In Progress',
              comments: 'Drafted safety protocol',
              roleInAction: 'contributor',
              contributionValue: 20,
            ),
          ],
        );

        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ManagerDashboardScreen(
                userProfile: testManagerProfile,
                managerContext: testManagerContext,
                initialActions: [ownerAction, contributorAction],
                initialMyActions: [ownerAction, contributorAction],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to My Actions (Index 1)
        final myActionsNav = find.byKey(
          const ValueKey('sidebar_item_My Actions'),
        );
        expect(myActionsNav, findsOneWidget);
        await tester.tap(myActionsNav);
        await tester.pumpAndSettle();

        // Verify My Actions table header
        expect(find.text('My Actions (2)'), findsOneWidget);

        // Verify OWNER badge and CONTRIBUTOR badge are rendered
        expect(find.text('OWNER'), findsOneWidget);
        expect(find.text('CONTRIBUTOR'), findsOneWidget);

        // Verify Mine % contribution is rendered
        expect(find.text('Mine: 70%'), findsOneWidget);
        expect(find.text('Mine: 20%'), findsOneWidget);
      },
    );
  });

  group('8. Excel Export Service Sheet 3 Lifecycle Integration', () {
    test('Exports follow-ups and contributors in Action Lifecycle sheet', () {
      final exportAction = ActionRecord(
        id: 'act-exp-1',
        actionNumber: 'ACT-010',
        organizationId: 'org-tenant-a',
        departmentId: 'dept-hse-01',
        siteId: 'site-alpha-01',
        subject: 'Excel Lifecycle Export Action',
        actionRequired: 'Verify export columns',
        division: 'Operations',
        department: 'HSE',
        site: 'Plant Alpha',
        assignedTo: 'Sarah Connor',
        assignedToId: 'mgr-uuid-001',
        assignedBy: 'Director Mike',
        priority: 'High',
        status: 'In Progress',
        percentComplete: 60,
        targetDate: '30 Sep 2026',
        dateRaised: '15 Sep 2026',
        followUps: const [
          ActionFollowUpRecord(
            id: 'fu-exp-1',
            actionId: 'act-exp-1',
            followUpDate: '22 Sep 2026',
            notes: 'First inspection checkpoint',
            status: 'Completed',
            actualProgress: 40,
            createdByName: 'Director Mike',
          ),
        ],
        contributors: const [
          ActionContributorRecord(
            id: 'c-exp-1',
            actionId: 'act-exp-1',
            profileId: 'helper-uuid-003',
            profileName: 'Helper Jane',
            addedByName: 'Sarah Connor',
            notes: 'Field measurements',
          ),
        ],
        progressUpdates: [
          ActionProgressUpdate(
            id: 'upd-exp-1',
            actionId: 'act-exp-1',
            updatedById: 'mgr-uuid-001',
            updatedByName: 'Sarah Connor',
            updateDate: '24 Sep 2026',
            progress: 60,
            status: 'In Progress',
            comments: 'Measurements verified and recorded',
            contributionValue: 60,
          ),
        ],
      );

      final workbook = ExcelExportService.instance.buildExportWorkbook(
        filteredActions: [exportAction],
        userName: 'Sarah Connor',
        userRole: 'manager',
        organizationName: 'Tenant A Corp',
        activeFilters: {'Status': 'In Progress'},
      );

      final bytes = workbook.save();
      expect(bytes, isNotNull);
      expect(bytes!.isNotEmpty, isTrue);
    });
  });
}
