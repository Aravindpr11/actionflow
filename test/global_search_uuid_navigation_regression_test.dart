import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/requests/models/request_models.dart';
import 'package:action_flow/features/requests/screens/request_details_screen.dart';
import 'package:action_flow/features/requests/services/request_service.dart';
import 'package:action_flow/widgets/search/global_search_autocomplete.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const orgId = 'org-uuid-nav-test';
  const managerId = 'mgr-uuid-nav-0001';
  const staffId = 'stf-uuid-nav-0002';

  const actionUuidAlpha = '11111111-aaaa-4111-8111-111111111111';
  const actionUuidBeta = '22222222-bbbb-4222-8222-222222222222';
  const requestUuidGamma = '33333333-cccc-4333-8333-333333333333';

  final managerProfile = UserProfile(
    id: managerId,
    email: 'manager@actionflow.test',
    name: 'HSE Manager',
    phone: '+971 50 111 2222',
    designation: 'Safety Manager',
    department: 'HSE',
    site: 'Site A',
    role: 'manager',
    organizationId: orgId,
    organizationName: 'ActionFlow Test Org',
  );

  final staffProfile = UserProfile(
    id: staffId,
    email: 'staff@actionflow.test',
    name: 'Field Engineer',
    phone: '+971 50 333 4444',
    designation: 'Safety Officer',
    department: 'HSE',
    site: 'Site A',
    role: 'staff',
    organizationId: orgId,
    organizationName: 'ActionFlow Test Org',
  );

  // Two actions sharing the same reference number but distinct database UUIDs.
  // Selecting Beta proves UUID-based navigation rather than referenceNumber lookup.
  final duplicateRefActions = <ActionRecord>[
    ActionRecord(
      id: actionUuidAlpha,
      actionNumber: 'ACT-5555',
      organizationId: orgId,
      division: 'Operations',
      subject: 'Crane Permit Alpha Inspection',
      actionRequired: 'Verify lifting plan Alpha',
      assignedTo: 'Field Engineer',
      assignedToId: staffId,
      createdById: managerId,
      department: 'HSE',
      site: 'Site A',
      status: 'In Progress',
      priority: 'High',
      targetDate: '2026-12-15',
    ),
    ActionRecord(
      id: actionUuidBeta,
      actionNumber: 'ACT-5555',
      organizationId: orgId,
      division: 'Operations',
      subject: 'Crane Permit Beta Audit',
      actionRequired: 'Verify lifting plan Beta',
      assignedTo: 'Field Engineer',
      assignedToId: staffId,
      createdById: managerId,
      department: 'HSE',
      site: 'Site A',
      status: 'Open',
      priority: 'Urgent',
      targetDate: '2026-12-20',
    ),
  ];

  setUp(() {
    RequestService.useMockOnly = true;
    RequestService.instance.clearMockStore();
    RequestService.instance.seedMockRequest(
      const RequestRecord(
        id: requestUuidGamma,
        displayId: 'REQ-7777',
        organizationId: orgId,
        createdBy: staffId,
        createdByName: 'Field Engineer',
        createdByRole: 'Staff',
        requestType: 'Permit to Work (PTW)',
        title: 'Hot Work Permit UUID Test',
        description: 'Requires UUID-based request navigation verification',
        status: 'Pending',
        priority: 'High',
        requiredByDate: '2026-12-22',
        departmentName: 'HSE',
        siteName: 'Site A',
        approvers: [
          RequestApproverRecord(
            id: 'appr-7777',
            requestId: requestUuidGamma,
            approverId: managerId,
            approverName: 'HSE Manager',
            approverRole: 'Manager',
            stepOrder: 1,
            status: 'Pending',
          ),
        ],
      ),
    );
  });

  tearDown(() {
    RequestService.instance.clearMockStore();
    RequestService.useMockOnly = false;
  });

  group('Global Search UUID Navigation Regression Tests', () {
    testWidgets(
      'Selecting an action passes its database UUID (not referenceNumber)',
      (tester) async {
        String? navigatedActionId;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: GlobalSearchAutocomplete(
                  cachedActions: duplicateRefActions,
                  organizationId: orgId,
                  currentUserId: managerId,
                  currentUserRole: 'manager',
                  onActionSelected: (item) {
                    navigatedActionId =
                        item.id.isNotEmpty ? item.id : item.referenceNumber;
                  },
                ),
              ),
            ),
          ),
        );

        await tester.enterText(find.byType(TextField), 'Beta Audit');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        final betaSuggestion = find.descendant(
          of: find.byType(ListView),
          matching: find.text('Crane Permit Beta Audit'),
        );
        expect(betaSuggestion, findsOneWidget);

        await tester.tap(betaSuggestion);
        await tester.pumpAndSettle();

        expect(navigatedActionId, equals(actionUuidBeta));
        expect(navigatedActionId, isNot(equals('ACT-5555')));
      },
    );

    testWidgets(
      'Selecting a request passes its database UUID (not referenceNumber)',
      (tester) async {
        String? navigatedRequestId;
        RequestRecord? navigatedRequestRecord;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: GlobalSearchAutocomplete(
                  cachedActions: duplicateRefActions,
                  organizationId: orgId,
                  currentUserId: managerId,
                  currentUserRole: 'manager',
                  onRequestSelected: (item) {
                    navigatedRequestId = item.id;
                    navigatedRequestRecord = item.rawRecord is RequestRecord
                        ? item.rawRecord as RequestRecord
                        : null;
                  },
                ),
              ),
            ),
          ),
        );

        await tester.enterText(find.byType(TextField), 'REQ-7777');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        final reqSuggestion = find.descendant(
          of: find.byType(ListView),
          matching: find.text('Hot Work Permit UUID Test'),
        );
        expect(reqSuggestion, findsOneWidget);

        await tester.tap(reqSuggestion);
        await tester.pumpAndSettle();

        expect(navigatedRequestId, equals(requestUuidGamma));
        expect(navigatedRequestId, isNot(equals('REQ-7777')));
        expect(navigatedRequestRecord, isNotNull);
        expect(navigatedRequestRecord!.id, equals(requestUuidGamma));
      },
    );

    testWidgets(
      'Fallback referenceNumber is used ONLY when action UUID is empty',
      (tester) async {
        final emptyIdAction = ActionRecord(
          id: '',
          actionNumber: 'ACT-8888',
          organizationId: orgId,
          division: 'Operations',
          subject: 'Fallback Reference Safety Check',
          actionRequired: 'Verify fallback behavior when UUID is empty',
          assignedTo: 'Field Engineer',
          assignedToId: staffId,
          createdById: managerId,
          department: 'HSE',
          site: 'Site A',
          status: 'Open',
          priority: 'Medium',
          targetDate: '2026-12-25',
        );

        String? navigatedTarget;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: GlobalSearchAutocomplete(
                  cachedActions: [emptyIdAction],
                  organizationId: orgId,
                  currentUserId: managerId,
                  currentUserRole: 'manager',
                  onActionSelected: (item) {
                    navigatedTarget =
                        item.id.isNotEmpty ? item.id : item.referenceNumber;
                  },
                ),
              ),
            ),
          ),
        );

        await tester.enterText(find.byType(TextField), 'ACT-8888');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        final fallbackSuggestion = find.descendant(
          of: find.byType(ListView),
          matching: find.text('Fallback Reference Safety Check'),
        );
        expect(fallbackSuggestion, findsOneWidget);

        await tester.tap(fallbackSuggestion);
        await tester.pumpAndSettle();

        expect(navigatedTarget, equals('ACT-8888'));
      },
    );

    testWidgets(
      'ManagerDashboardScreen navigates by action UUID and request UUID',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: ManagerDashboardScreen(
              userProfile: managerProfile,
              initialActions: duplicateRefActions,
              initialMyActions: duplicateRefActions,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final headerSearchField = find.descendant(
          of: find.byType(GlobalSearchAutocomplete),
          matching: find.byType(TextField),
        );
        expect(headerSearchField, findsOneWidget);

        // 1. Search and select the SECOND action sharing ACT-5555 (UUID Beta)
        await tester.enterText(headerSearchField, 'Beta Audit');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        final betaSuggestion = find.descendant(
          of: find.byType(ListView),
          matching: find.text('Crane Permit Beta Audit'),
        );
        expect(betaSuggestion, findsOneWidget);
        await tester.tap(betaSuggestion);
        await tester.pumpAndSettle();

        // Must open ActionDetailsScreen for Beta (proves UUID lookup, not ACT-5555 -> Alpha)
        expect(find.byType(ActionDetailsScreen), findsOneWidget);
        expect(find.text('Crane Permit Beta Audit'), findsAtLeastNWidgets(1));
        expect(find.text('Crane Permit Alpha Inspection'), findsNothing);

        // Pop back to Manager Dashboard
        Navigator.of(tester.element(find.byType(ActionDetailsScreen))).pop();
        await tester.pumpAndSettle();

        // 2. Search and select Request by UUID
        await tester.enterText(headerSearchField, 'REQ-7777');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        final reqSuggestion = find.descendant(
          of: find.byType(ListView),
          matching: find.text('Hot Work Permit UUID Test'),
        );
        expect(reqSuggestion, findsOneWidget);
        await tester.tap(reqSuggestion);
        await tester.pumpAndSettle();

        expect(find.byType(RequestDetailsScreen), findsOneWidget);
        expect(find.text('Hot Work Permit UUID Test'), findsAtLeastNWidgets(1));
      },
    );

    testWidgets(
      'WorkerDashboardScreen navigates by action UUID and request UUID',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: WorkerDashboardScreen(
              userProfile: staffProfile,
              initialActions: duplicateRefActions,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final headerSearchField = find.descendant(
          of: find.byType(GlobalSearchAutocomplete),
          matching: find.byType(TextField),
        );
        expect(headerSearchField, findsOneWidget);

        // 1. Search and select the SECOND action sharing ACT-5555 (UUID Beta)
        await tester.enterText(headerSearchField, 'Beta Audit');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        final betaSuggestion = find.descendant(
          of: find.byType(ListView),
          matching: find.text('Crane Permit Beta Audit'),
        );
        expect(betaSuggestion, findsOneWidget);
        await tester.tap(betaSuggestion);
        await tester.pumpAndSettle();

        // Must navigate to Beta action (not Alpha)
        expect(find.text('Crane Permit Beta Audit'), findsAtLeastNWidgets(1));
        expect(find.text('Crane Permit Alpha Inspection'), findsNothing);

        // Pop back to Worker Dashboard
        final navigator = Navigator.of(
          tester.element(find.text('Crane Permit Beta Audit').first),
        );
        if (navigator.canPop()) {
          navigator.pop();
          await tester.pumpAndSettle();
        }

        // 2. Search and select Request by UUID
        await tester.enterText(headerSearchField, 'REQ-7777');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        final reqSuggestion = find.descendant(
          of: find.byType(ListView),
          matching: find.text('Hot Work Permit UUID Test'),
        );
        expect(reqSuggestion, findsOneWidget);
        await tester.tap(reqSuggestion);
        await tester.pumpAndSettle();

        expect(find.byType(RequestDetailsScreen), findsOneWidget);
        expect(find.text('Hot Work Permit UUID Test'), findsAtLeastNWidgets(1));
      },
    );
  });
}
