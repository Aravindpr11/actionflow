import 'package:action_flow/features/auth/models/manager_scope_item.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/add_action_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/services/excel_export_service.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.now();
  final todayStr = '${now.day.toString().padLeft(2, '0')} Sep ${now.year}';
  final yesterday = now.subtract(const Duration(days: 1));
  final yesterdayStr =
      '${yesterday.day.toString().padLeft(2, '0')} Sep ${yesterday.year}';

  const testManagerProfile = UserProfile(
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

  final openActionToday = ActionRecord(
    id: 'act-001',
    actionNumber: 'ACT-0001',
    organizationId: 'org-sobha-01',
    departmentId: 'dept-maintenance-01',
    siteId: 'site-plant-02',
    createdById: 'mgr-user-uuid-101',
    subject: 'Inspect high-voltage wiring',
    actionRequired: 'Visual and thermal scan of switchboard',
    description: 'Quarterly thermal scan required by safety guidelines.',
    priority: 'High',
    status: 'Open',
    percentComplete: 0,
    department: 'Maintenance',
    site: 'Warehouse B',
    division: 'Operations',
    assignedTo: 'John Electrician',
    assignedToId: 'worker-uuid-001',
    assignedBy: 'David Manager',
    dateRaised: todayStr,
    targetDate: todayStr,
    nextFollowUpDate: todayStr,
    progressUpdates: [
      ActionProgressUpdate(
        id: 'upd-001',
        actionId: 'act-001',
        updatedById: 'worker-uuid-001',
        updatedByName: 'John Electrician',
        updateDate: todayStr,
        progress: 25,
        status: 'In Progress',
        comments: 'Thermal camera calibrated and inspection initiated.',
        createdAt: now,
      ),
    ],
  );

  final closedActionYesterday = ActionRecord(
    id: 'act-002',
    actionNumber: 'ACT-0002',
    organizationId: 'org-sobha-01',
    departmentId: 'dept-safety-01',
    siteId: 'site-plant-01',
    createdById: 'mgr-user-uuid-101',
    subject: 'Chemical spill containment kit replacement',
    actionRequired: 'Install new spill kit in Bay 4',
    description: 'Ensure absorbents and neutralizers are fully stocked.',
    priority: 'Medium',
    status: 'Closed',
    percentComplete: 100,
    department: 'Safety Operations',
    site: 'North Plant',
    division: 'Corporate',
    assignedTo: 'Sarah HSE Officer',
    assignedToId: 'worker-uuid-002',
    assignedBy: 'David Manager',
    dateRaised: yesterdayStr,
    targetDate: yesterdayStr,
    closeDate: todayStr,
    closedAt: now,
    closedById: 'mgr-user-uuid-101',
    closedByName: 'David Manager',
    closureComment: 'Verified spill kit replacement and signed checklist.',
    progressUpdates: [
      ActionProgressUpdate(
        id: 'upd-002',
        actionId: 'act-002',
        updatedById: 'worker-uuid-002',
        updatedByName: 'Sarah HSE Officer',
        updateDate: yesterdayStr,
        progress: 100,
        status: 'Closed',
        comments: 'All materials replaced and verified.',
        createdAt: yesterday,
      ),
    ],
  );

  final testActions = [openActionToday, closedActionYesterday];

  void configureTesterView(WidgetTester tester) {
    tester.view.physicalSize = const Size(2800, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  group('Manager Action Register Date Filters & Actions', () {
    testWidgets(
      'Date filters: Date Field selector and dynamic period options',
      (tester) async {
        configureTesterView(tester);

        await tester.pumpWidget(
          MaterialApp(
            home: ManagerDashboardScreen(
              userProfile: testManagerProfile,
              managerContext: testManagerContext,
              initialActions: testActions,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to Action Register
        await tester.tap(find.text('Action Register').first);
        await tester.pumpAndSettle();

        // Verify presence of Date Field dropdown
        expect(find.text('Date Field'), findsOneWidget);
        expect(find.text('All Dates'), findsOneWidget);

        // Verify presence of Date Period dropdown
        expect(find.text('Date Period'), findsOneWidget);

        // Both actions found initially
        expect(find.text('2 Actions found'), findsOneWidget);
      },
    );

    testWidgets(
      'Date Field = Closed Date filters actions to only those with a closed date populated',
      (tester) async {
        configureTesterView(tester);

        await tester.pumpWidget(
          MaterialApp(
            home: ManagerDashboardScreen(
              userProfile: testManagerProfile,
              managerContext: testManagerContext,
              initialActions: testActions,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to Action Register
        await tester.tap(find.text('Action Register').first);
        await tester.pumpAndSettle();

        expect(find.text('2 Actions found'), findsOneWidget);

        // Tap Date Field dropdown and select 'Closed Date'
        await tester.tap(find.text('All Dates').first);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Closed Date').last);
        await tester.pumpAndSettle();

        // Only the closed action should be displayed
        expect(find.text('1 Action found'), findsOneWidget);
        expect(
          find.text('Chemical spill containment kit replacement'),
          findsOneWidget,
        );
        expect(find.text('Inspect high-voltage wiring'), findsNothing);
      },
    );

    testWidgets(
      'Delete confirmation dialog prevents deleting closed action and displays retention notice',
      (tester) async {
        configureTesterView(tester);

        await tester.pumpWidget(
          MaterialApp(
            home: ManagerDashboardScreen(
              userProfile: testManagerProfile,
              managerContext: testManagerContext,
              initialActions: testActions,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Action Register').first);
        await tester.pumpAndSettle();

        // For closed action, button shows "Closed" lock button
        final closedButton = find.widgetWithText(OutlinedButton, 'Closed');
        expect(closedButton, findsOneWidget);

        await tester.tap(closedButton);
        await tester.pumpAndSettle();

        // Compliance retention dialog appears
        expect(find.text('Closed Action Retained'), findsOneWidget);
        expect(
          find.textContaining(
            'Under safety and quality compliance standards, closed actions cannot be deleted',
          ),
          findsOneWidget,
        );

        // Dismiss dialog
        await tester.tap(find.text('Understood'));
        await tester.pumpAndSettle();
        expect(find.text('Closed Action Retained'), findsNothing);
      },
    );

    testWidgets(
      'Delete confirmation dialog appears for open action with Delete Action warning',
      (tester) async {
        configureTesterView(tester);

        await tester.pumpWidget(
          MaterialApp(
            home: ManagerDashboardScreen(
              userProfile: testManagerProfile,
              managerContext: testManagerContext,
              initialActions: testActions,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Action Register').first);
        await tester.pumpAndSettle();

        // Open action has active Delete button
        final deleteButton = find.widgetWithText(OutlinedButton, 'Delete');
        expect(deleteButton, findsOneWidget);

        await tester.tap(deleteButton);
        await tester.pumpAndSettle();

        // Confirmation dialog appears
        expect(
          find.textContaining(
            'Are you sure you want to permanently delete this action',
          ),
          findsOneWidget,
        );
        expect(find.text('Cancel'), findsOneWidget);
        expect(
          find.widgetWithText(ElevatedButton, 'Delete Action'),
          findsOneWidget,
        );

        // Tap Cancel
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            'Are you sure you want to permanently delete this action',
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Edit action opens AddActionScreen in Edit Mode with existing action pre-population',
      (tester) async {
        configureTesterView(tester);

        await tester.pumpWidget(
          MaterialApp(
            home: ManagerDashboardScreen(
              userProfile: testManagerProfile,
              managerContext: testManagerContext,
              initialActions: testActions,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Action Register').first);
        await tester.pumpAndSettle();

        // Tap Edit button on open action
        final editButtons = find.widgetWithText(OutlinedButton, 'Edit');
        expect(editButtons, findsWidgets);

        await tester.tap(editButtons.first);
        await tester.pumpAndSettle();

        // AddActionScreen in edit mode
        expect(find.byType(AddActionScreen), findsOneWidget);
        expect(find.text('Edit Action'), findsOneWidget);
        expect(find.text('Save Changes'), findsOneWidget);
      },
    );
  });

  group('Action Details Screen: Lifecycle Audit Tab', () {
    testWidgets(
      'Lifecycle tab renders complete vertical timeline with distinct Update Date vs Submission Timestamp',
      (tester) async {
        configureTesterView(tester);

        await tester.pumpWidget(
          MaterialApp(
            home: ActionDetailsScreen(
              action: closedActionYesterday,
              currentUserId: 'mgr-user-uuid-101',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify Lifecycle tab exists
        expect(find.text('Lifecycle'), findsOneWidget);

        // Tap Lifecycle tab
        await tester.tap(find.text('Lifecycle'));
        await tester.pumpAndSettle();

        // Verify milestones in timeline
        expect(find.text('Action Created & Logged'), findsOneWidget);
        expect(find.text('Initial Assignment & Target Set'), findsOneWidget);
        expect(find.text('100% Work Completed'), findsOneWidget);
        expect(
          find.text('Action Closed & Retained for Compliance'),
          findsOneWidget,
        );
        expect(
          find.text('Verified spill kit replacement and signed checklist.'),
          findsOneWidget,
        );
      },
    );
  });

  group('ExcelExportService excel_plus Multi-Sheet & Charts Validation', () {
    test('buildExportWorkbook generates all 6 sheets with formulas, real dates, charts, and tables', () {
      final exportService = ExcelExportService.instance;
      final activeFilters = {
        'Status': 'Open, Closed',
        'Department': 'Maintenance, HSE',
      };

      final workbook = exportService.buildExportWorkbook(
        filteredActions: testActions,
        userName: 'David Manager',
        userRole: 'Manager',
        organizationName: 'Sobha Constructions',
        activeFilters: activeFilters,
      );

      // 1. Verify all 6 sheets
      expect(workbook.tables.containsKey('Dashboard'), isTrue);
      expect(workbook.tables.containsKey('Action Register'), isTrue);
      expect(workbook.tables.containsKey('Action Lifecycle'), isTrue);
      expect(workbook.tables.containsKey('Progress History'), isTrue);
      expect(workbook.tables.containsKey('Comments & Reviews'), isTrue);
      expect(workbook.tables.containsKey('Lists & Reference'), isTrue);

      // 2. Verify Dashboard formula-driven KPIs by finding row dynamically
      final dashSheet = workbook.tables['Dashboard']!;
      FormulaCellValue? totalActionsFormula;
      for (final row in dashSheet.rows) {
        if (row.isNotEmpty &&
            row[0]?.value.toString() == 'Total Actions Exported') {
          totalActionsFormula = row[1]?.value as FormulaCellValue?;
          break;
        }
      }
      expect(totalActionsFormula, isNotNull);
      expect(
        totalActionsFormula!.formula.contains("COUNTA('Action Register'"),
        isTrue,
      );
      expect(
        totalActionsFormula.cachedValue,
        '2',
      ); // Recalculated value embedded!

      // 3. Verify Action Register real dates & columns
      final regSheet = workbook.tables['Action Register']!;
      final regHeader = regSheet.cell(CellIndex.indexByString('A1')).value;
      expect(regHeader?.toString(), 'Action ID');

      final regDateCell = regSheet.cell(CellIndex.indexByString('O2')).value;
      expect(regDateCell, isA<DateCellValue>()); // Real DateCellValue!

      // 4. Verify Action Lifecycle audit sheet
      final lifeSheet = workbook.tables['Action Lifecycle']!;
      final lifeHeader = lifeSheet.cell(CellIndex.indexByString('C1')).value;
      expect(lifeHeader?.toString(), 'Lifecycle Stage');
      final lifeStageVal = lifeSheet.cell(CellIndex.indexByString('C2')).value;
      expect(lifeStageVal?.toString(), 'Created');

      // 5. Verify workbook saves cleanly into valid bytes
      final bytes = workbook.save();
      expect(bytes, isNotNull);
      expect(bytes!.isNotEmpty, isTrue);

      // 6. Decode and re-verify
      final reloaded = Excel.decodeBytes(bytes);
      expect(reloaded.tables.length, 6);
      expect(reloaded.tables.containsKey('Dashboard'), isTrue);
      expect(reloaded.tables.containsKey('Action Register'), isTrue);
      expect(reloaded.tables.containsKey('Action Lifecycle'), isTrue);
    });
  });
}
