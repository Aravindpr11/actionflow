import 'dart:typed_data';
import 'package:action_flow/features/auth/models/manager_scope_item.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_action_update_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/services/app_file_picker_service.dart';
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
    site: 'Main Plant Facility',
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
        siteName: 'Main Plant Facility',
      ),
    ],
  );

  final assignedAction = ActionRecord(
    id: 'act-101',
    actionNumber: 'ACT-1001',
    organizationId: 'org-sobha-01',
    departmentId: 'dept-safety-01',
    siteId: 'site-plant-01',
    subject: 'Safety Valve Pressure Calibration',
    actionRequired: 'Inspect and recalibrate safety relief valves on line 3.',
    division: 'Operations',
    department: 'Safety Operations',
    site: 'Main Plant Facility',
    assignedTo: 'David Manager',
    assignedToId: 'mgr-user-uuid-101',
    priority: 'High',
    status: 'In Progress',
    percentComplete: 40,
    targetDate: '25 Sep 2026',
    progressUpdates: [
      ActionProgressUpdate(
        id: 'upd-01',
        actionId: 'act-101',
        updatedById: 'mgr-user-uuid-101',
        updatedByName: 'David Manager',
        updateDate: '20 Sep 2026',
        progress: 40,
        status: 'In Progress',
        comments: 'Initial valve disassembly completed. Gaskets inspected.',
        createdAt: DateTime(2026, 9, 20, 14, 30),
      ),
    ],
  );

  final unassignedAction = ActionRecord(
    id: 'act-102',
    actionNumber: 'ACT-1002',
    organizationId: 'org-sobha-01',
    departmentId: 'dept-safety-01',
    siteId: 'site-plant-01',
    subject: 'Emergency Lighting Inspection',
    actionRequired: 'Test backup batteries and replace failed fixtures.',
    division: 'Operations',
    department: 'Safety Operations',
    site: 'Main Plant Facility',
    assignedTo: 'Unassigned',
    assignedToId: null,
    priority: 'Medium',
    status: 'Open',
    percentComplete: 0,
    targetDate: '30 Sep 2026',
  );

  void configureTesterView(
    WidgetTester tester, {
    Size size = const Size(1280, 2500),
  }) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Widget createTestWidget(Widget child) {
    return MaterialApp(home: Material(child: child));
  }

  group('Manager Portal: Action Register vs My Actions button distinctions', () {
    testWidgets('Action Register renders Add Action button', (tester) async {
      configureTesterView(tester);

      await tester.pumpWidget(
        createTestWidget(
          ManagerDashboardScreen(
            userProfile: testManagerProfile,
            managerContext: testManagerContext,
            initialActions: [assignedAction, unassignedAction],
            initialMyActions: [assignedAction],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // On initial load (Index 0: Dashboard), switch to Action Register (Nav item 1)
      final actionRegisterNav = find.text('Action Register');
      expect(actionRegisterNav, findsWidgets);
      await tester.tap(actionRegisterNav.first);
      await tester.pumpAndSettle();

      // In Action Register, Add Action button MUST be present
      expect(find.widgetWithText(ElevatedButton, 'Add Action'), findsOneWidget);
    });

    testWidgets(
      'My Actions hides Add Action button and displays Update Action',
      (tester) async {
        configureTesterView(tester);

        await tester.pumpWidget(
          createTestWidget(
            ManagerDashboardScreen(
              userProfile: testManagerProfile,
              managerContext: testManagerContext,
              initialActions: [assignedAction, unassignedAction],
              initialMyActions: [assignedAction],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Switch to My Actions (Nav item 3)
        final myActionsNav = find.text('My Actions');
        expect(myActionsNav, findsWidgets);
        await tester.tap(myActionsNav.first);
        await tester.pumpAndSettle();

        // Header must NOT contain Add Action button
        expect(find.widgetWithText(ElevatedButton, 'Add Action'), findsNothing);

        // Table row must contain Update Action button
        expect(
          find.widgetWithText(ElevatedButton, 'Update Action'),
          findsOneWidget,
        );
        expect(find.widgetWithText(OutlinedButton, 'Details'), findsOneWidget);
      },
    );

    testWidgets(
      'My Actions empty state retains "No actions assigned to you." without Add Action',
      (tester) async {
        configureTesterView(tester);

        await tester.pumpWidget(
          createTestWidget(
            ManagerDashboardScreen(
              userProfile: testManagerProfile,
              managerContext: testManagerContext,
              initialActions: [unassignedAction],
              initialMyActions: const [],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Switch to My Actions
        final myActionsNav = find.text('My Actions');
        await tester.tap(myActionsNav.first);
        await tester.pumpAndSettle();

        // Verify empty state
        expect(find.text('No actions assigned to you.'), findsOneWidget);
        expect(
          find.text('You currently have no actions assigned to your account.'),
          findsOneWidget,
        );

        // Must not show Add Action anywhere
        expect(find.widgetWithText(ElevatedButton, 'Add Action'), findsNothing);
      },
    );

    testWidgets(
      'Mobile view for My Actions shows Details and Update Action buttons',
      (tester) async {
        configureTesterView(tester, size: const Size(400, 900));

        await tester.pumpWidget(
          createTestWidget(
            ManagerDashboardScreen(
              userProfile: testManagerProfile,
              managerContext: testManagerContext,
              initialActions: [assignedAction],
              initialMyActions: [assignedAction],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // In mobile view (width < 1100), open drawer to navigate to My Actions
        await tester.tap(find.byIcon(Icons.menu_rounded));
        await tester.pumpAndSettle();

        final myActionsNav = find.descendant(
          of: find.byType(Drawer),
          matching: find.text('My Actions'),
        );
        await tester.tap(myActionsNav);
        await tester.pumpAndSettle();

        expect(
          find.widgetWithText(ElevatedButton, 'Update Action'),
          findsOneWidget,
        );
        expect(find.widgetWithText(OutlinedButton, 'Details'), findsOneWidget);
      },
    );
  });

  group(
    'Manager Action Details: Progress display and Update Action workflow',
    () {
      testWidgets(
        'ActionDetailsScreen displays current progress, latest update, and Update Action button',
        (tester) async {
          configureTesterView(tester);

          await tester.pumpWidget(
            createTestWidget(
              ActionDetailsScreen(
                action: assignedAction,
                currentUserId: 'mgr-user-uuid-101',
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Verify Update Action button in toolbar
          expect(
            find.widgetWithText(ElevatedButton, 'Update Action'),
            findsWidgets,
          );

          // Verify Overview displays Current Progress & Status card
          expect(find.text('Current Progress & Status'), findsOneWidget);
          expect(find.text('Completion: 40%'), findsOneWidget);
          expect(find.text('Latest Update: 20 Sep 2026'), findsOneWidget);
          expect(find.text('Updated by: David Manager'), findsOneWidget);
          expect(
            find.text(
              'Initial valve disassembly completed. Gaskets inspected.',
            ),
            findsWidgets,
          );
        },
      );

      testWidgets(
        'ActionDetailsScreen History tab displays Progress Updates History',
        (tester) async {
          configureTesterView(tester);

          await tester.pumpWidget(
            createTestWidget(
              ActionDetailsScreen(
                action: assignedAction,
                currentUserId: 'mgr-user-uuid-101',
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Tap on History tab
          final historyTab = find.text('History');
          expect(historyTab, findsOneWidget);
          await tester.tap(historyTab);
          await tester.pumpAndSettle();

          // Verify Progress Updates History card exists
          expect(find.text('Progress Updates History'), findsOneWidget);
          expect(find.text('40%'), findsWidgets);
          expect(
            find.text(
              'Initial valve disassembly completed. Gaskets inspected.',
            ),
            findsWidgets,
          );
        },
      );
    },
  );

  group('ManagerActionUpdateScreen: Fields and Interactions', () {
    testWidgets('Renders all update action fields properly', (tester) async {
      configureTesterView(tester);

      await tester.pumpWidget(
        createTestWidget(
          ManagerActionUpdateScreen(
            action: assignedAction,
            currentUserId: 'mgr-user-uuid-101',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify header info
      expect(find.text('ACT-1001'), findsOneWidget);
      expect(find.text('Safety Valve Pressure Calibration'), findsOneWidget);

      // Verify section titles
      expect(find.text('Update Date *'), findsOneWidget);
      expect(find.text('Progress: 40% *'), findsOneWidget);
      expect(find.text('Status *'), findsOneWidget);
      expect(find.text('Work Completed & Description *'), findsOneWidget);
      expect(find.text('Attachments'), findsOneWidget);

      // Verify 100% non-closure banner
      expect(
        find.textContaining(
          'Setting progress to 100% indicates all operational tasks are done, but does NOT automatically close',
        ),
        findsOneWidget,
      );

      // Verify buttons
      expect(
        find.widgetWithText(ElevatedButton, 'Save Update'),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
    });

    testWidgets('Progress quick chips update progress value', (tester) async {
      configureTesterView(tester);

      await tester.pumpWidget(
        createTestWidget(
          ManagerActionUpdateScreen(
            action: assignedAction,
            currentUserId: 'mgr-user-uuid-101',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap 75% chip
      final chip75 = find.widgetWithText(ChoiceChip, '75%');
      expect(chip75, findsOneWidget);
      await tester.tap(chip75);
      await tester.pumpAndSettle();

      expect(find.text('Progress: 75% *'), findsOneWidget);
    });

    testWidgets('Comments field validation triggers on empty submission', (
      tester,
    ) async {
      configureTesterView(tester);

      await tester.pumpWidget(
        createTestWidget(
          ManagerActionUpdateScreen(
            action: assignedAction.copyWith(
              id: 'act-validation-check',
              actionNumber: 'ACT-9999',
              progressUpdates: const [],
              workerMessage: '',
              managerMessage: '',
              remarks: '',
            ),
            currentUserId: 'mgr-user-uuid-101',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Save Update without typing comments
      final saveBtn = find.widgetWithText(ElevatedButton, 'Save Update');
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verify validation error
      expect(
        find.text('Please provide a description of the work completed.'),
        findsOneWidget,
      );
    });

    testWidgets('Attachments can be added and removed', (tester) async {
      configureTesterView(tester);
      AppFilePicker.testOverride = ({required allowedExtensions}) async {
        return AppPickedFile(
          name: 'Update_Doc_1.pdf',
          bytes: Uint8List.fromList([1, 2, 3]),
          size: 3,
        );
      };
      addTearDown(() => AppFilePicker.testOverride = null);

      await tester.pumpWidget(
        createTestWidget(
          ManagerActionUpdateScreen(
            action: assignedAction,
            currentUserId: 'mgr-user-uuid-101',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('No attachments added for this update.'),
        findsOneWidget,
      );

      // Tap Add File (triggers real file picker)
      final addFileBtn = find.text('Add File');
      await tester.tap(addFileBtn);
      await tester.pumpAndSettle();

      // Verify attachment was added
      expect(find.text('Update_Doc_1.pdf'), findsOneWidget);

      // Remove attachment
      final removeIcon = find.byIcon(Icons.close_rounded);
      expect(removeIcon, findsOneWidget);
      await tester.tap(removeIcon);
      await tester.pumpAndSettle();

      expect(
        find.text('No attachments added for this update.'),
        findsOneWidget,
      );
    });
  });

  group('ActionRecord & ActionProgressUpdate Model Serialization', () {
    test('ActionProgressUpdate fromJson and toJson roundtrip', () {
      final json = {
        'id': 'upd-99',
        'action_id': 'act-99',
        'updated_by': 'user-123',
        'updated_by_name': 'Test Updater',
        'update_date': '2026-09-22',
        'progress': 60,
        'status': 'In Progress',
        'comments': 'Completed phase 2 wiring.',
        'attachments': ['schematic.pdf'],
        'created_at': '2026-09-22T10:00:00.000Z',
      };

      final update = ActionProgressUpdate.fromJson(json);
      expect(update.id, 'upd-99');
      expect(update.progress, 60);
      expect(update.status, 'In Progress');
      expect(update.comments, 'Completed phase 2 wiring.');
      expect(update.updatedByName, 'Test Updater');
      expect(update.attachments, contains('schematic.pdf'));

      final outJson = update.toJson();
      expect(outJson['progress'], 60);
      expect(outJson['action_id'], 'act-99');
    });

    test(
      'ActionRecord parses progressUpdates and calculates latestProgressUpdate',
      () {
        final record = ActionRecord(
          id: 'act-1',
          subject: 'Test Subject',
          actionRequired: 'Required',
          division: 'Ops',
          assignedTo: 'User A',
          progressUpdates: [
            ActionProgressUpdate(
              id: 'upd-1',
              actionId: 'act-1',
              updatedById: 'user-1',
              updatedByName: 'User 1',
              updateDate: '10 Sep 2026',
              progress: 25,
              status: 'In Progress',
              comments: 'First update',
              createdAt: DateTime(2026, 9, 10),
            ),
            ActionProgressUpdate(
              id: 'upd-2',
              actionId: 'act-1',
              updatedById: 'user-1',
              updatedByName: 'User 1',
              updateDate: '18 Sep 2026',
              progress: 75,
              status: 'In Progress',
              comments: 'Second update with 75%',
              createdAt: DateTime(2026, 9, 18),
            ),
          ],
        );

        expect(record.latestProgressUpdate?.id, 'upd-2');
        expect(record.latestUpdateDate, '18 Sep 2026');
        expect(record.latestWorkUpdate, 'Second update with 75%');
        expect(record.lastUpdatedBy, 'User 1');
      },
    );
  });
}
