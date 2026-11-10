import 'package:action_flow/features/auth/models/manager_scope_item.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
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
    ],
  );

  final actionClosed = ActionRecord(
    id: 'act-closed-immutability-01',
    actionNumber: 'ACT-0999',
    organizationId: 'org-sobha-01',
    departmentId: 'dept-safety-01',
    siteId: 'site-plant-01',
    subject: 'High Voltage Transformer Oil Sampling',
    actionRequired: 'Extract dielectric breakdown test sample.',
    division: 'Maintenance',
    department: 'Safety Operations',
    site: 'North Plant',
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
    subTasks: const [
      ActionSubTask(
        id: 'subtask-closed-1',
        parentActionId: 'act-closed-immutability-01',
        title: 'Check oil level gauge',
        instruction: 'Inspect visual gauge glass',
        assignedStaff: 'M. Ali',
        assignedStaffId: 'worker-02',
        status: 'Completed',
        completedAt: '2026-09-21 14:00',
        completedBy: 'worker-02',
      ),
    ],
    attachments: const ['certificate.pdf'],
    progressUpdates: [
      ActionProgressUpdate(
        id: 'upd-closed-1',
        actionId: 'act-closed-immutability-01',
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

  group('Closed Action Immutability & Retention Tests', () {
    test('1. Model invariants: Closed action has isClosed=true and isReadyForReview=false', () {
      expect(actionClosed.isClosed, isTrue);
      expect(actionClosed.isReadyForReview, isFalse);
      expect(actionClosed.status.toLowerCase(), 'closed');
      expect(actionClosed.percentComplete, 100);
      expect(actionClosed.closureComment, isNotEmpty);
      expect(actionClosed.closedByName, 'David Manager');
    });

    testWidgets('2. UI Immutability: Displays Closed & Retained banner and Closed (Read-Only) badge', (
      tester,
    ) async {
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

      // Permanent closed retention banner
      expect(find.text('Action Closed & Retained'), findsOneWidget);
      expect(find.text('FORMAL CLOSURE VERIFICATION'), findsOneWidget);
      expect(find.text('Closed (Read-Only)'), findsOneWidget);
      expect(find.textContaining('David Manager'), findsWidgets);
      expect(find.textContaining('Dielectric breakdown tested at 45kV'), findsWidgets);
    });

    testWidgets('3. UI Immutability: Update Action button is strictly hidden for closed actions', (
      tester,
    ) async {
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

      // "Update Action" button must not exist
      expect(find.text('Update Action'), findsNothing);
    });

    testWidgets('4. UI Immutability: Attachment removal is strictly hidden for closed actions', (
      tester,
    ) async {
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

      // Attachment delete button must not be rendered when action is closed
      expect(find.byKey(const Key('remove_attachment_certificate.pdf_btn')), findsNothing);
    });

    testWidgets('5. UI Immutability: Subtask completion checkboxes cannot be toggled on closed action', (
      tester,
    ) async {
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

      // Checkbox is present but disabled or non-interactive
      final checkboxFinder = find.byType(Checkbox);
      if (checkboxFinder.evaluate().isNotEmpty) {
        final checkbox = tester.widget<Checkbox>(checkboxFinder.first);
        expect(checkbox.onChanged, isNull);
      }
    });

    testWidgets('6. Action Register Retention: Closed actions are permanently retained and filterable', (
      tester,
    ) async {
      configureTesterView(tester);

      await tester.pumpWidget(
        MaterialApp(
          home: ManagerDashboardScreen(
            managerContext: testManagerContext,
            initialActions: [actionClosed],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify the closed action is displayed in the register
      expect(find.text('ACT-0999'), findsOneWidget);
      expect(find.text('High Voltage Transformer Oil Sampling'), findsWidgets);
    });
  });
}
