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
    id: 'mgr-user-uuid-101',
    name: 'David Manager',
    email: 'david.mgr@sobha.com',
    phone: '+971501234567',
    designation: 'HSE Manager',
    department: 'Safety Operations',
    site: 'North Plant',
    role: 'manager',
    organizationId: 'org-sobha-01',
    organizationName: 'Sobha Constructions',
  );

  final testManagerContext = ManagerContext(
    authUserId: 'mgr-user-uuid-101',
    profile: testManagerProfile,
    organizationId: 'org-sobha-01',
    organizationName: 'Sobha Constructions',
    scopes: const [
      ManagerScopeItem(
        departmentId: 'dept-safety-01',
        departmentName: 'Safety Operations',
        siteId: 'site-plant-01',
        siteName: 'North Plant',
      ),
      ManagerScopeItem(
        departmentId: 'dept-maintenance-01',
        departmentName: 'Maintenance',
        siteId: 'site-plant-02',
        siteName: 'Warehouse B',
      ),
    ],
  );

  final action0Pct = ActionRecord(
    id: 'act-001',
    actionNumber: 'ACT-0001',
    organizationId: 'org-sobha-01',
    departmentId: 'dept-safety-01',
    siteId: 'site-plant-01',
    subject: 'Zero Percent Action',
    actionRequired: 'Beginning inspection',
    division: 'Operations',
    department: 'Safety Operations',
    site: 'North Plant',
    assignedTo: 'David Manager',
    assignedToId: 'mgr-user-uuid-101',
    priority: 'High',
    status: 'Open',
    percentComplete: 0,
    targetDate: '25 Sep 2026',
    dateRaised: '20 Sep 2026',
  );

  final action100PctReady = ActionRecord(
    id: 'act-100',
    actionNumber: 'ACT-0100',
    organizationId: 'org-sobha-01',
    departmentId: 'dept-safety-01',
    siteId: 'site-plant-01',
    subject: 'Completed Fire Damper Overhaul',
    actionRequired: 'Replace thermal links and verify auto shutoff.',
    division: 'Operations',
    department: 'Safety Operations',
    site: 'North Plant',
    assignedTo: 'R. Kumar',
    assignedToId: 'worker-01',
    priority: 'Critical',
    status: 'Pending Review',
    percentComplete: 100,
    targetDate: '22 Sep 2026',
    dateRaised: '15 Sep 2026',
    progressUpdates: [
      ActionProgressUpdate(
        id: 'upd-100',
        actionId: 'act-100',
        updatedById: 'worker-01',
        updatedByName: 'R. Kumar',
        updateDate: '22 Sep 2026',
        progress: 100,
        status: 'Pending Review',
        comments: 'All 14 thermal links replaced and physically tested.',
        createdAt: DateTime(2026, 9, 22, 11, 0),
      ),
    ],
  );

  final actionClosed = ActionRecord(
    id: 'act-closed',
    actionNumber: 'ACT-0999',
    organizationId: 'org-sobha-01',
    departmentId: 'dept-maintenance-01',
    siteId: 'site-plant-02',
    subject: 'High Voltage Transformer Oil Sampling',
    actionRequired: 'Extract dielectric breakdown test sample.',
    division: 'Maintenance',
    department: 'Maintenance',
    site: 'Warehouse B',
    assignedTo: 'M. Ali',
    assignedToId: 'worker-02',
    priority: 'Medium',
    status: 'Closed',
    percentComplete: 100,
    closedAt: DateTime(2026, 9, 21, 15, 30),
    closedById: 'mgr-user-uuid-101',
    closedByName: 'David Manager',
    closureComment:
        'Dielectric breakdown tested at 45kV, meets IEC 60156 standards.',
    targetDate: '21 Sep 2026',
    dateRaised: '10 Sep 2026',
    progressUpdates: [
      ActionProgressUpdate(
        id: 'upd-closed-1',
        actionId: 'act-closed',
        updatedById: 'worker-02',
        updatedByName: 'M. Ali',
        updateDate: '21 Sep 2026',
        progress: 100,
        status: 'Closed',
        comments: 'Final laboratory testing certificate attached.',
        createdAt: DateTime(2026, 9, 21, 14, 0),
      ),
    ],
  );

  void configureTesterView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 2500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  group('Action Closure Workflow & State Tests', () {
    testWidgets('1 & 2: 0% cannot close and 100% does not auto-close', (
      tester,
    ) async {
      configureTesterView(tester);

      // Verify model properties first
      expect(action0Pct.percentComplete, 0);
      expect(action0Pct.isClosed, isFalse);
      expect(action0Pct.isReadyForReview, isFalse);

      expect(action100PctReady.percentComplete, 100);
      expect(action100PctReady.status, 'Pending Review');
      expect(
        action100PctReady.isClosed,
        isFalse,
      ); // Reaching 100% does NOT auto-close
      expect(
        action100PctReady.isReadyForReview,
        isTrue,
      ); // Displays ready for review

      // Mount 0% action in ActionDetailsScreen
      await tester.pumpWidget(
        MaterialApp(
          home: ActionDetailsScreen(
            action: action0Pct,
            currentUserId: 'mgr-user-uuid-101',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ensure no closed banner is shown
      expect(find.text('Action Closed & Retained'), findsNothing);
    });

    testWidgets(
      '3 & 4: 100% displays prominent Ready for Review state and requires confirmation',
      (tester) async {
        configureTesterView(tester);

        await tester.pumpWidget(
          MaterialApp(
            home: ActionDetailsScreen(
              action: action100PctReady,
              currentUserId: 'mgr-user-uuid-101',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 3. Ready for review banner
        expect(
          find.text('Ready for Manager Review (100% Complete)'),
          findsOneWidget,
        );
        expect(find.text('Approve & Close'), findsWidgets);
        expect(find.text('Request More Info'), findsWidgets);

        // Tap Approve & Close
        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Approve & Close').first,
        );
        await tester.pumpAndSettle();

        // Dialog opens
        expect(
          find.text('Manager Closure & Verification Comments *'),
          findsOneWidget,
        );

        // Attempting to close without checkbox and without comment must fail validation
        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Approve & Close').last,
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Verification comment is required for closure.'),
          findsOneWidget,
        );

        // Enter comment but don't check checkbox
        await tester.enterText(
          find.widgetWithText(
            TextField,
            'Enter compliance verification and closure notes...',
          ),
          'Comprehensive physical inspection verified compliant.',
        );
        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Approve & Close').last,
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Please verify completion checkbox before closing.'),
          findsOneWidget,
        );

        // Check the verification checkbox
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();

        // Now tap Approve & Close inside dialog
        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Approve & Close').last,
        );
        await tester.pumpAndSettle();

        // Action is now closed and shows permanent retention banner
        expect(find.text('Action Closed & Retained'), findsOneWidget);
        expect(find.text('Closed (Read-Only)'), findsOneWidget);
        expect(
          find.text('Update Action'),
          findsNothing,
        ); // 9. Update Action button hidden on closed actions
      },
    );

    testWidgets(
      '8 & 9: Action Details displays closed banner, closed date, closed by, closure comments, and hides Update Action',
      (tester) async {
        configureTesterView(tester);

        await tester.pumpWidget(
          MaterialApp(
            home: ActionDetailsScreen(
              action: actionClosed,
              currentUserId: 'mgr-user-uuid-101',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 8. Displays closed banner
        expect(find.text('Action Closed & Retained'), findsOneWidget);
        expect(find.text('FORMAL CLOSURE VERIFICATION'), findsOneWidget);
        expect(find.textContaining('David Manager'), findsWidgets);
        expect(
          find.textContaining('Dielectric breakdown tested at 45kV'),
          findsWidgets,
        );

        // 9. Update Action button hidden
        expect(find.text('Update Action'), findsNothing);
        expect(find.text('Closed (Read-Only)'), findsOneWidget);
      },
    );

    testWidgets(
      '19: Request More Information reverts action to active status with comments',
      (tester) async {
        configureTesterView(tester);

        await tester.pumpWidget(
          MaterialApp(
            home: ActionDetailsScreen(
              action: action100PctReady,
              currentUserId: 'mgr-user-uuid-101',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap Request More Info button
        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Request More Info'),
        );
        await tester.pumpAndSettle();

        expect(find.text('Request More Information'), findsWidgets);
        expect(find.text('Target Reverted Status'), findsOneWidget);

        // Enter comment
        await tester.enterText(
          find.widgetWithText(
            TextField,
            'Specify what additional proof or rework is required...',
          ),
          'Please attach calibration certificate for torque wrench.',
        );

        // Submit return for revision
        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Return for Revision'),
        );
        await tester.pumpAndSettle();

        // Should show SnackBar feedback and status returned to In Progress
        expect(find.textContaining('returned to In Progress'), findsOneWidget);
      },
    );
  });

  group('Action Register Filtering & Retention Tests', () {
    final allActions = [action0Pct, action100PctReady, actionClosed];

    testWidgets(
      '6, 7 & 10: Closed actions permanently retained and filterable by Status = Closed',
      (tester) async {
        configureTesterView(tester);

        await tester.pumpWidget(
          MaterialApp(
            home: ManagerDashboardScreen(
              userProfile: testManagerProfile,
              managerContext: testManagerContext,
              initialActions: allActions,
              initialMyActions: [action0Pct],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Switch to Action Register tab (nav index 1)
        await tester.tap(find.text('Action Register').first);
        await tester.pumpAndSettle();

        // Initially all 3 actions are in the register
        expect(find.textContaining('ACT-0001'), findsWidgets);
        expect(find.textContaining('ACT-0100'), findsWidgets);
        expect(find.textContaining('ACT-0999'), findsWidgets);
        expect(find.text('3 Actions found'), findsOneWidget);

        // Filter by Status = Closed
        await tester.tap(find.byKey(const ValueKey('Status_All Status')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Closed').last);
        await tester.pumpAndSettle();

        // 10. Only closed action appears
        expect(find.textContaining('ACT-0999'), findsWidgets);
        expect(find.textContaining('ACT-0001'), findsNothing);
        expect(find.textContaining('ACT-0100'), findsNothing);
        expect(find.text('1 Action found'), findsOneWidget);
        expect(
          find.text('Status: Closed'),
          findsOneWidget,
        ); // Active filter chip
      },
    );

    testWidgets(
      '11: Filter by Status = Ready for Review shows only actions awaiting approval',
      (tester) async {
        configureTesterView(tester);

        await tester.pumpWidget(
          MaterialApp(
            home: ManagerDashboardScreen(
              userProfile: testManagerProfile,
              managerContext: testManagerContext,
              initialActions: allActions,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Action Register').first);
        await tester.pumpAndSettle();

        // Filter by Status = Ready for Review
        await tester.tap(find.byKey(const ValueKey('Status_All Status')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ready for Review').last);
        await tester.pumpAndSettle();

        // Only ACT-0100 is ready for review
        expect(find.textContaining('ACT-0100'), findsWidgets);
        expect(find.textContaining('ACT-0001'), findsNothing);
        expect(find.textContaining('ACT-0999'), findsNothing);
        expect(find.text('1 Action found'), findsOneWidget);
      },
    );

    testWidgets('12: Date filtering (September 2026)', (tester) async {
      configureTesterView(tester);

      await tester.pumpWidget(
        MaterialApp(
          home: ManagerDashboardScreen(
            userProfile: testManagerProfile,
            managerContext: testManagerContext,
            initialActions: allActions,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Action Register').first);
      await tester.pumpAndSettle();

      // Filter by Date = September 2026
      await tester.tap(find.byKey(const ValueKey('Date_Date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('September 2026').last);
      await tester.pumpAndSettle();

      // All 3 actions are in September 2026
      expect(find.text('3 Actions found'), findsOneWidget);
      expect(find.text('Date: September 2026'), findsOneWidget);
    });

    testWidgets(
      '13 & 14: Multi-dimensional combined filters and Clear All chips',
      (tester) async {
        configureTesterView(tester);

        await tester.pumpWidget(
          MaterialApp(
            home: ManagerDashboardScreen(
              userProfile: testManagerProfile,
              managerContext: testManagerContext,
              initialActions: allActions,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Action Register').first);
        await tester.pumpAndSettle();

        // Apply Department = Maintenance filter
        await tester.tap(
          find.byKey(const ValueKey('Department_All Departments')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Maintenance').last);
        await tester.pumpAndSettle();

        // Only ACT-0999 is Maintenance
        expect(find.text('1 Action found'), findsOneWidget);
        expect(find.text('Department: Maintenance'), findsOneWidget);

        // Tap 'Clear All'
        await tester.tap(find.text('Clear All'));
        await tester.pumpAndSettle();

        // Resets back to 3 actions
        expect(find.text('3 Actions found'), findsOneWidget);
        expect(find.text('Clear All'), findsNothing);
      },
    );
  });

  group('Filtered Excel Export Tests', () {
    test('15, 16, 17, 18: Excel workbook strictly contains filtered actions and generates 3 sheets', () {
      final exportService = ExcelExportService.instance;

      // Filter down to only 1 action: actionClosed
      final filteredList = [actionClosed];
      final activeFilters = {
        'Status': 'Closed',
        'Department': 'Maintenance',
        'Site': 'Warehouse B',
      };

      final workbook = exportService.buildExportWorkbook(
        filteredActions: filteredList,
        userName: 'David Manager',
        userRole: 'Manager',
        organizationName: 'Sobha Constructions',
        activeFilters: activeFilters,
      );

      // 16. Verify all 6 sheets exist
      expect(workbook.tables.containsKey('Dashboard'), isTrue);
      expect(workbook.tables.containsKey('Action Register'), isTrue);
      expect(workbook.tables.containsKey('Action Lifecycle'), isTrue);
      expect(workbook.tables.containsKey('Progress History'), isTrue);
      expect(workbook.tables.containsKey('Comments & Reviews'), isTrue);
      expect(workbook.tables.containsKey('Lists & Reference'), isTrue);

      // 17. Verify Sheet 1 (Dashboard) has metadata and active filters
      final summarySheet = workbook.tables['Dashboard']!;
      final summaryValues = summarySheet.rows
          .expand((r) => r.map((c) => c?.value.toString() ?? ''))
          .toList();
      expect(
        summaryValues.any((v) => v.contains('ACTIONFLOW EXECUTIVE DASHBOARD')),
        isTrue,
      );
      expect(summaryValues.any((v) => v.contains('David Manager')), isTrue);
      expect(
        summaryValues.any((v) => v.contains('Sobha Constructions')),
        isTrue,
      );
      expect(summaryValues.any((v) => v.contains('Closed')), isTrue);
      expect(summaryValues.any((v) => v.contains('Maintenance')), isTrue);

      // 15. Verify Sheet 2 (Action Register) contains ONLY the filtered action
      final actionsSheet = workbook.tables['Action Register']!;
      final actionValues = actionsSheet.rows
          .expand((r) => r.map((c) => c?.value.toString() ?? ''))
          .toList();
      expect(actionValues.any((v) => v.contains('ACT-0999')), isTrue);
      expect(
        actionValues.any(
          (v) => v.contains('High Voltage Transformer Oil Sampling'),
        ),
        isTrue,
      );
      expect(
        actionValues.any((v) => v.contains('ACT-0001')),
        isFalse,
      ); // Excluded!
      expect(
        actionValues.any((v) => v.contains('ACT-0100')),
        isFalse,
      ); // Excluded!

      // 18. Verify Sheet 4 (Progress History) contains ONLY history for filtered actions
      final historySheet = workbook.tables['Progress History']!;
      final historyValues = historySheet.rows
          .expand((r) => r.map((c) => c?.value.toString() ?? ''))
          .toList();
      expect(historyValues.any((v) => v.contains('ACT-0999')), isTrue);
      expect(
        historyValues.any(
          (v) => v.contains('Final laboratory testing certificate attached.'),
        ),
        isTrue,
      );
      expect(
        historyValues.any((v) => v.contains('ACT-0100')),
        isFalse,
      ); // Excluded!
    });

    testWidgets('Empty filter results display warning and cancel download', (
      tester,
    ) async {
      final exportService = ExcelExportService.instance;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    exportService.exportFilteredActions(
                      context: context,
                      filteredActions: const [], // 0 actions
                      userName: 'David Manager',
                      userRole: 'Manager',
                      organizationName: 'Sobha Constructions',
                      activeFilters: const {'Status': 'Overdue'},
                    );
                  },
                  child: const Text('Export Empty'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Export Empty'));
      await tester.pumpAndSettle();

      // Verify user warning
      expect(
        find.text('No actions match the selected filters.'),
        findsOneWidget,
      );
    });
  });
}
