import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/notifications/models/app_notification.dart';
import 'package:action_flow/features/notifications/widgets/quick_alert_toast.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:action_flow/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    NotificationService.useMockOnly = true;
    MockNotificationStore.instance.clear();
    MockActionStore.instance.actions.clear();
    NotificationService.instance.clearReminderSessionCache();
  });

  tearDown(() {
    MockNotificationStore.instance.clear();
    MockActionStore.instance.actions.clear();
    NotificationService.instance.clearReminderSessionCache();
  });

  Widget buildStaffTestWidget({UserProfile? profile}) {
    return MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(1280, 850)),
        child: WorkerDashboardScreen(userProfile: profile),
      ),
    );
  }

  Widget buildManagerTestWidget({
    UserProfile? profile,
    List<ActionRecord>? initialActions,
    List<ActionRecord>? initialMyActions,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(1280, 850)),
        child: ManagerDashboardScreen(
          userProfile: profile ?? UserProfile.mockManager().copyWith(id: 'MGR-001'),
          initialActions: initialActions,
          initialMyActions: initialMyActions,
        ),
      ),
    );
  }

  group('A. ActionService.fetchActionById Resolution Tests', () {
    test('1. Resolves action by human-readable actionNumber (e.g. AC-1029)', () async {
      final record = ActionRecord(
        id: 'uuid-1029-abc',
        actionNumber: 'AC-1029',
        subject: 'Equipment Inspection',
        actionRequired: 'Update checklist',
        division: 'Operations',
        assignedTo: 'R. Kumar',
        assignedToId: 'EMP-2049',
        status: 'Open',
      );
      MockActionStore.instance.add(record);

      final result = await ActionService.instance.fetchActionById('AC-1029');
      expect(result, isNotNull);
      expect(result!.id, 'uuid-1029-abc');
      expect(result.actionNumber, 'AC-1029');
      expect(result.subject, 'Equipment Inspection');
    });

    test('2. Resolves action by database UUID', () async {
      final uuid = '3fa85f64-5717-4562-b3fc-2c963f66afa6';
      final record = ActionRecord(
        id: uuid,
        actionNumber: 'AC-7001',
        subject: 'Hazard Review',
        actionRequired: 'Inspect site',
        division: 'HSE',
        assignedTo: 'R. Kumar',
        status: 'In Progress',
      );
      MockActionStore.instance.add(record);

      final result = await ActionService.instance.fetchActionById(uuid);
      expect(result, isNotNull);
      expect(result!.id, uuid);
      expect(result.actionNumber, 'AC-7001');
    });

    test('3. Resolves with whitespace trimming and case insensitivity', () async {
      final record = ActionRecord(
        id: 'uuid-case-test',
        actionNumber: 'AC-1029',
        subject: 'Equipment Inspection',
        actionRequired: 'Check valve',
        division: 'Operations',
        assignedTo: 'R. Kumar',
      );
      MockActionStore.instance.add(record);

      final lowerResult = await ActionService.instance.fetchActionById('ac-1029');
      expect(lowerResult, isNotNull);
      expect(lowerResult!.id, 'uuid-case-test');

      final paddedResult = await ActionService.instance.fetchActionById('  AC-1029  ');
      expect(paddedResult, isNotNull);
      expect(paddedResult!.id, 'uuid-case-test');
    });

    test('4. Returns null for non-existent action without inventing fake records', () async {
      final result = await ActionService.instance.fetchActionById('AC-NONEXISTENT-999');
      expect(result, isNull);
    });

    test('5. Resolves action across different prefixes and raw numbers (AC-1048, ACT-2000, AF-1048, 1048)', () async {
      final record1 = ActionRecord(
        id: 'uuid-1048',
        actionNumber: 'AC-1048',
        subject: 'Fire Extinguisher Inspection',
        actionRequired: 'Inspect all extinguishers in Sector B',
        division: 'HSE',
        assignedTo: 'R. Kumar',
      );
      final record2 = ActionRecord(
        id: 'uuid-2000',
        actionNumber: 'ACT-2000',
        subject: 'Emergency Exit Lighting',
        actionRequired: 'Check battery backup',
        division: 'HSE',
        assignedTo: 'R. Kumar',
      );
      MockActionStore.instance.add(record1);
      MockActionStore.instance.add(record2);

      // Check direct lookup
      final res1 = await ActionService.instance.fetchActionById('AC-1048');
      expect(res1?.subject, 'Fire Extinguisher Inspection');

      // Check numeric-only query
      final resNum = await ActionService.instance.fetchActionById('1048');
      expect(resNum?.id, 'uuid-1048');

      // Check prefix-agnostic lookup (ACT vs AC)
      final resAlt = await ActionService.instance.fetchActionById('ACT-1048');
      expect(resAlt?.id, 'uuid-1048');

      // Check ACT-2000 lookup
      final res2 = await ActionService.instance.fetchActionById('ACT-2000');
      expect(res2?.subject, 'Emergency Exit Lighting');
    });

    test('6. Sanitizes noisy strings (#AC-1048, action: AC-1048, "AC-1048")', () {
      expect(ActionService.cleanActionId('#AC-1048'), 'AC-1048');
      expect(ActionService.cleanActionId('action: AC-1048'), 'AC-1048');
      expect(ActionService.cleanActionId('"AC-1048"'), 'AC-1048');
      expect(ActionService.cleanActionId("'AC-1048'"), 'AC-1048');
      expect(ActionService.cleanActionId('  action/AC-1048  '), 'AC-1048');
    });

    test('7. AppNotification.effectiveActionIdentifier recovers action reference from title or message', () {
      // Direct actionId present
      final direct = AppNotification(
        id: '1',
        userId: 'U1',
        title: 'Action Update',
        message: 'Details',
        eventType: 'action_assigned',
        actionId: 'AC-1029',
        createdAt: DateTime.now(),
      );
      expect(direct.effectiveActionIdentifier, 'AC-1029');

      // actionId null, extracted from title
      final fromTitle = AppNotification(
        id: '2',
        userId: 'U1',
        title: 'Action Assigned: AC-1048',
        message: 'Fire extinguisher inspection requires review.',
        eventType: 'action_assigned',
        createdAt: DateTime.now(),
      );
      expect(fromTitle.effectiveActionIdentifier, 'AC-1048');

      // actionId null, extracted from message
      final fromMessage = AppNotification(
        id: '3',
        userId: 'U1',
        title: 'Target Date Approaching',
        message: 'Action AC-1053 is due in 48 hours.',
        eventType: 'action_reminder',
        createdAt: DateTime.now(),
      );
      expect(fromMessage.effectiveActionIdentifier, 'AC-1053');

      // Non-action notification has null effectiveActionIdentifier
      final nonAction = AppNotification(
        id: '4',
        userId: 'U1',
        title: 'System Maintenance Scheduled',
        message: 'System will undergo maintenance tonight at 23:00.',
        eventType: 'system_alert',
        createdAt: DateTime.now(),
      );
      expect(nonAction.effectiveActionIdentifier, isNull);
    });

    test('8. AppNotification.isActionRelated correctly distinguishes action vs system announcements', () {
      final actionNotif = AppNotification(
        id: '1',
        userId: 'U1',
        title: 'Action Assigned',
        message: 'Inspection',
        eventType: 'action_assigned',
        createdAt: DateTime.now(),
      );
      expect(actionNotif.isActionRelated, isTrue);

      final systemNotif = AppNotification(
        id: '2',
        userId: 'U1',
        title: 'Company Announcement',
        message: 'Welcome to Q4',
        eventType: 'announcement',
        createdAt: DateTime.now(),
      );
      expect(systemNotif.isActionRelated, isFalse);
    });
  });

  group('B. Staff Portal Notification Navigation & Authorization', () {
    testWidgets('1. Clicking notification with action code AC-1029 opens ActionDetailsScreen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final action = ActionRecord(
        id: 'AF-1042',
        actionNumber: 'AC-1029',
        subject: 'Equipment Inspection',
        actionRequired: 'Complete inspection and upload the signed checklist.',
        division: 'Operations',
        department: 'Operations / Maintenance',
        site: 'North Plant',
        assignedTo: 'R. Kumar',
        assignedToId: 'EMP-2049',
        status: 'Open',
        priority: 'High',
      );
      MockActionStore.instance.add(action);

      // Seed notification for EMP-2049 (R. Kumar)
      final notif = AppNotification(
        id: 'notif-ac-1029',
        userId: 'EMP-2049',
        title: 'Action Update Required',
        message: 'Equipment Inspection finding needs an updated checklist.',
        eventType: 'action_updated',
        actionId: 'AC-1029',
        isRead: false,
        createdAt: DateTime.now(),
      );
      MockNotificationStore.instance.seed([notif]);

      await tester.pumpWidget(buildStaffTestWidget());
      await tester.pumpAndSettle();

      // Navigate to Notifications tab (index 5)
      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      expect(find.text('Notifications & Alerts'), findsOneWidget);
      expect(find.text('AC-1029'), findsOneWidget);

      // Tap on the notification item
      await tester.tap(find.text('Action Update Required').first);
      await tester.pumpAndSettle();

      // Verifies ActionDetailsScreen opened successfully
      expect(find.byType(ActionDetailsScreen), findsOneWidget);
      expect(find.text('Equipment Inspection'), findsWidgets);
      expect(find.text('AC-1029'), findsWidgets);
    });

    testWidgets('2. Clicking notification with database UUID opens ActionDetailsScreen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const actionUuid = 'e82b7c12-3456-4789-abcd-0123456789ab';
      final action = ActionRecord(
        id: actionUuid,
        actionNumber: 'AC-2049',
        subject: 'Pump Station Overhaul',
        actionRequired: 'Replace gaskets',
        division: 'Operations',
        assignedTo: 'R. Kumar',
        assignedToId: 'EMP-2049',
        status: 'In Progress',
      );
      MockActionStore.instance.add(action);

      final notif = AppNotification(
        id: 'notif-uuid-test',
        userId: 'EMP-2049',
        title: 'Action Assigned',
        message: 'Pump Station Overhaul assigned to you.',
        eventType: 'action_assigned',
        actionId: actionUuid,
        isRead: false,
        createdAt: DateTime.now(),
      );
      MockNotificationStore.instance.seed([notif]);

      await tester.pumpWidget(buildStaffTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pump Station Overhaul assigned to you.'));
      await tester.pumpAndSettle();

      expect(find.byType(ActionDetailsScreen), findsOneWidget);
      expect(find.text('Pump Station Overhaul'), findsWidgets);
    });

    testWidgets('3. Clicking notification for missing action shows informative error SnackBar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notif = AppNotification(
        id: 'notif-missing',
        userId: 'EMP-2049',
        title: 'Nonexistent Action Alert',
        message: 'Points to deleted action.',
        eventType: 'action_updated',
        actionId: 'AC-9999',
        isRead: false,
        createdAt: DateTime.now(),
      );
      MockNotificationStore.instance.seed([notif]);

      await tester.pumpWidget(buildStaffTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nonexistent Action Alert'));
      await tester.pumpAndSettle();

      // Does not open ActionDetailsScreen
      expect(find.byType(ActionDetailsScreen), findsNothing);
      // Shows user-friendly not found message
      expect(find.text('Action "AC-9999" could not be found.'), findsOneWidget);
    });

    testWidgets('4. Unauthorized staff action (assigned to another user) is rejected', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Action assigned strictly to another user (T. Reed) with no delegation
      final secretAction = ActionRecord(
        id: 'act-secret-reed',
        actionNumber: 'AC-5000',
        subject: 'Confidential Disciplinary Audit',
        actionRequired: 'Internal audit',
        division: 'Corporate',
        assignedTo: 'T. Reed',
        assignedToId: 'EMP-OTHER-REED',
        status: 'Open',
      );
      MockActionStore.instance.add(secretAction);

      final notif = AppNotification(
        id: 'notif-unauth',
        userId: 'EMP-2049',
        title: 'Cross-user leak test',
        message: 'Notification referencing another user action.',
        eventType: 'action_updated',
        actionId: 'AC-5000',
        isRead: false,
        createdAt: DateTime.now(),
      );
      MockNotificationStore.instance.seed([notif]);

      await tester.pumpWidget(buildStaffTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cross-user leak test'));
      await tester.pumpAndSettle();

      // Does not open ActionDetailsScreen
      expect(find.byType(ActionDetailsScreen), findsNothing);
      // Displays permission rejection SnackBar
      expect(
        find.text('You do not have permission to view action "AC-5000".'),
        findsOneWidget,
      );
    });

    testWidgets('5. Cross-organization action is rejected to enforce tenant isolation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Action in another organization (ORG-FOREIGN)
      final foreignAction = ActionRecord(
        id: 'act-foreign',
        actionNumber: 'AC-6000',
        organizationId: 'ORG-FOREIGN',
        subject: 'Foreign Organization Blueprint',
        actionRequired: 'Strict isolation',
        division: 'Operations',
        assignedTo: 'R. Kumar',
        assignedToId: 'EMP-2049',
        status: 'Open',
      );
      MockActionStore.instance.add(foreignAction);

      final notif = AppNotification(
        id: 'notif-foreign',
        userId: 'EMP-2049',
        title: 'Foreign Tenant Notification',
        message: 'Points to cross-tenant action.',
        eventType: 'action_assigned',
        actionId: 'AC-6000',
        isRead: false,
        createdAt: DateTime.now(),
      );
      MockNotificationStore.instance.seed([notif]);

      final staffProfile = UserProfile.mockStaff().copyWith(
        organizationId: 'ORG-SOBHA',
      );

      await tester.pumpWidget(buildStaffTestWidget(profile: staffProfile));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Foreign Tenant Notification'));
      await tester.pumpAndSettle();

      expect(find.byType(ActionDetailsScreen), findsNothing);
      expect(
        find.text('You do not have permission to view action "AC-6000".'),
        findsOneWidget,
      );
    });

    testWidgets('6. Clicking notification with action code AC-1048 opens ActionDetailsScreen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final action = ActionRecord(
        id: 'uuid-1048-xyz',
        actionNumber: 'AC-1048',
        subject: 'Fire Extinguisher Inspection',
        actionRequired: 'Inspect all units in Sector 4',
        division: 'HSE',
        assignedTo: 'R. Kumar',
        assignedToId: 'EMP-2049',
        status: 'Open',
      );
      MockActionStore.instance.add(action);

      final notif = AppNotification(
        id: 'notif-1048',
        userId: 'EMP-2049',
        title: 'Action Assigned',
        message: 'Fire Extinguisher Inspection has been assigned to you.',
        eventType: 'action_assigned',
        actionId: 'AC-1048',
        isRead: false,
        createdAt: DateTime.now(),
      );
      MockNotificationStore.instance.seed([notif]);

      await tester.pumpWidget(buildStaffTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fire Extinguisher Inspection has been assigned to you.').first);
      await tester.pumpAndSettle();

      expect(find.byType(ActionDetailsScreen), findsOneWidget);
      expect(find.text('Fire Extinguisher Inspection'), findsWidgets);
      expect(find.text('AC-1048'), findsWidgets);
    });

    testWidgets('7. Clicking notification with null actionId but action reference in title opens ActionDetailsScreen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final action = ActionRecord(
        id: 'uuid-1053-abc',
        actionNumber: 'AC-1053',
        subject: 'Emergency Lighting Inspection',
        actionRequired: 'Test backup batteries',
        division: 'HSE',
        assignedTo: 'R. Kumar',
        assignedToId: 'EMP-2049',
        status: 'In Progress',
      );
      MockActionStore.instance.add(action);

      // Notification with actionId null, but AC-1053 in title
      final notif = AppNotification(
        id: 'notif-title-extracted',
        userId: 'EMP-2049',
        title: 'Action Assigned: AC-1053',
        message: 'Emergency Lighting Inspection requires completion.',
        eventType: 'action_assigned',
        actionId: null,
        isRead: false,
        createdAt: DateTime.now(),
      );
      MockNotificationStore.instance.seed([notif]);

      await tester.pumpWidget(buildStaffTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Action Assigned: AC-1053').first);
      await tester.pumpAndSettle();

      expect(find.byType(ActionDetailsScreen), findsOneWidget);
      expect(find.text('Emergency Lighting Inspection'), findsWidgets);
    });

    testWidgets('8. Non-action notification (announcement / system alert) displays message without action lookup', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notif = AppNotification(
        id: 'notif-system-broadcast',
        userId: 'EMP-2049',
        title: 'Scheduled Maintenance Alert',
        message: 'The portal will undergo scheduled maintenance tonight at 23:00 GMT.',
        eventType: 'system_alert',
        actionId: null,
        isRead: false,
        createdAt: DateTime.now(),
      );
      MockNotificationStore.instance.seed([notif]);

      await tester.pumpWidget(buildStaffTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Scheduled Maintenance Alert').first);
      await tester.pumpAndSettle();

      // Does NOT open ActionDetailsScreen
      expect(find.byType(ActionDetailsScreen), findsNothing);
      // Displays the broadcast announcement message in SnackBar
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('The portal will undergo scheduled maintenance tonight at 23:00 GMT.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('9. Notification with missing action reference shows informative message', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notif = AppNotification(
        id: 'notif-no-ref',
        userId: 'EMP-2049',
        title: 'Action Follow-up Needed',
        message: 'Please review your open assigned items without delay.',
        eventType: 'action_assigned',
        actionId: '',
        isRead: false,
        createdAt: DateTime.now(),
      );
      MockNotificationStore.instance.seed([notif]);

      await tester.pumpWidget(buildStaffTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Action Follow-up Needed').first);
      await tester.pumpAndSettle();

      expect(find.byType(ActionDetailsScreen), findsNothing);
      expect(
        find.text('Action reference is missing from this notification.'),
        findsOneWidget,
      );
    });

    testWidgets('10. Staff member authorized as contributor or additional assignee can view action', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Primary assignee is somebody else, but EMP-2049 is added in additionalPeople
      final action = ActionRecord(
        id: 'act-contrib-test',
        actionNumber: 'AC-3001',
        subject: 'Confined Space Entry Protocol',
        actionRequired: 'Assist in review',
        division: 'HSE',
        assignedTo: 'Another Staff',
        assignedToId: 'EMP-OTHER',
        additionalPeople: [
          const ActionPersonReference(
            personId: 'EMP-2049',
            name: 'R. Kumar',
            type: PersonType.internalUser,
            email: 'r.kumar@sobha.com',
          ),
        ],
        status: 'Open',
      );
      MockActionStore.instance.add(action);

      final notif = AppNotification(
        id: 'notif-contrib',
        userId: 'EMP-2049',
        title: 'Added as Co-worker',
        message: 'You were added as a co-worker on AC-3001.',
        eventType: 'action_assigned',
        actionId: 'AC-3001',
        isRead: false,
        createdAt: DateTime.now(),
      );
      MockNotificationStore.instance.seed([notif]);

      await tester.pumpWidget(buildStaffTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Added as Co-worker').first);
      await tester.pumpAndSettle();

      expect(find.byType(ActionDetailsScreen), findsOneWidget);
      expect(find.text('Confined Space Entry Protocol'), findsWidgets);
    });
  });

  group('C. Manager Portal Notification Navigation', () {
    testWidgets('1. Manager selects notification and navigates to ActionDetailsScreen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final action = ActionRecord(
        id: 'act-mgr-1',
        actionNumber: 'AC-8001',
        subject: 'Annual Safety Protocol Audit',
        actionRequired: 'Verify certifications',
        division: 'Operations',
        assignedTo: 'R. Kumar',
        status: 'In Progress',
      );
      MockActionStore.instance.add(action);

      final notif = AppNotification(
        id: 'notif-mgr-test',
        userId: 'MGR-001',
        title: 'Action Update for Manager',
        message: 'Staff updated AC-8001',
        eventType: 'action_updated',
        actionId: 'AC-8001',
        isRead: false,
        createdAt: DateTime.now(),
      );
      MockNotificationStore.instance.seed([notif]);

      await tester.pumpWidget(
        buildManagerTestWidget(
          initialActions: [action],
          initialMyActions: const [],
        ),
      );
      await tester.pumpAndSettle();

      // Open Notifications tab in Manager Dashboard (index 6)
      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      expect(find.text('Notifications & Alerts'), findsOneWidget);
      await tester.tap(find.text('Action Update for Manager').first);
      await tester.pumpAndSettle();

      // Verified ActionDetailsScreen opened
      expect(find.byType(ActionDetailsScreen), findsOneWidget);
      expect(find.text('Annual Safety Protocol Audit'), findsWidgets);
    });

    testWidgets('2. Manager receives informative message if action does not exist', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notif = AppNotification(
        id: 'notif-mgr-miss',
        userId: 'MGR-001',
        title: 'Deleted Action Notice',
        message: 'Action was deleted',
        eventType: 'action_updated',
        actionId: 'AC-8888',
        isRead: false,
        createdAt: DateTime.now(),
      );
      MockNotificationStore.instance.seed([notif]);

      await tester.pumpWidget(
        buildManagerTestWidget(
          initialActions: const [],
          initialMyActions: const [],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Deleted Action Notice').first);
      await tester.pumpAndSettle();

      expect(find.byType(ActionDetailsScreen), findsNothing);
      expect(find.text('Action "AC-8888" could not be found.'), findsOneWidget);
    });

    testWidgets('3. Manager navigates to action when actionId is null but action code is in title', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final action = ActionRecord(
        id: 'act-mgr-extracted',
        actionNumber: 'AC-8002',
        subject: 'HVAC Duct Maintenance',
        actionRequired: 'Replace filter units',
        division: 'Facilities',
        assignedTo: 'R. Kumar',
        status: 'Open',
      );
      MockActionStore.instance.add(action);

      final notif = AppNotification(
        id: 'notif-mgr-title',
        userId: 'MGR-001',
        title: 'New Action Created: AC-8002',
        message: 'HVAC Duct Maintenance assigned to facilities team.',
        eventType: 'action_assigned',
        actionId: null,
        isRead: false,
        createdAt: DateTime.now(),
      );
      MockNotificationStore.instance.seed([notif]);

      await tester.pumpWidget(
        buildManagerTestWidget(
          initialActions: [action],
          initialMyActions: const [],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New Action Created: AC-8002').first);
      await tester.pumpAndSettle();

      expect(find.byType(ActionDetailsScreen), findsOneWidget);
      expect(find.text('HVAC Duct Maintenance'), findsWidgets);
    });

    testWidgets('4. Manager handles non-action broadcast announcement gracefully', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notif = AppNotification(
        id: 'notif-mgr-announcement',
        userId: 'MGR-001',
        title: 'Quarterly Executive Townhall',
        message: 'Join live broadcast on Teams at 15:00.',
        eventType: 'announcement',
        actionId: null,
        isRead: false,
        createdAt: DateTime.now(),
      );
      MockNotificationStore.instance.seed([notif]);

      await tester.pumpWidget(
        buildManagerTestWidget(
          initialActions: const [],
          initialMyActions: const [],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Quarterly Executive Townhall').first);
      await tester.pumpAndSettle();

      expect(find.byType(ActionDetailsScreen), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('Join live broadcast on Teams at 15:00.'),
        ),
        findsOneWidget,
      );
    });
  });

  group('D. Notification State & Read/Unread Isolation', () {
    testWidgets('1. Clicking an action does not mark unrelated notifications as read', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final action = ActionRecord(
        id: 'AF-1042',
        actionNumber: 'AC-1029',
        subject: 'Equipment Inspection',
        actionRequired: 'Update checklist',
        division: 'Operations',
        assignedTo: 'R. Kumar',
        assignedToId: 'EMP-2049',
      );
      MockActionStore.instance.add(action);

      final notif1 = AppNotification(
        id: 'notif-1',
        userId: 'EMP-2049',
        title: 'Action Update Required',
        message: 'First notification',
        eventType: 'action_updated',
        actionId: 'AC-1029',
        isRead: false,
        createdAt: DateTime.now(),
      );

      final notif2 = AppNotification(
        id: 'notif-2',
        userId: 'EMP-2049',
        title: 'Second Notification',
        message: 'Unrelated alert',
        eventType: 'action_assigned',
        actionId: 'AC-1048',
        isRead: false,
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      MockNotificationStore.instance.seed([notif1, notif2]);

      await tester.pumpWidget(buildStaffTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      // Tap first notification to open action
      await tester.tap(find.text('Action Update Required').first);
      await tester.pumpAndSettle();

      expect(find.byType(ActionDetailsScreen), findsOneWidget);

      // Verify notif2 is still unread
      final storeNotifs = MockNotificationStore.instance.getNotifications('EMP-2049');
      final secondNotif = storeNotifs.firstWhere((n) => n.id == 'notif-2');
      expect(secondNotif.isRead, isFalse);
    });
  });

  group('E. Interactive Dropdown and Quick Alert Navigation', () {
    testWidgets('1. QuickAlertToast View button opens action details', (
      tester,
    ) async {
      String? tappedActionId;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuickAlertToast(
              notification: AppNotification(
                id: 'notif-toast-1',
                userId: 'EMP-2049',
                title: 'Action Due Soon',
                message: 'Action AC-1029 is due today.',
                eventType: 'action_reminder',
                actionId: 'AC-1029',
                createdAt: DateTime.now(),
              ),
              onActionTap: (id) => tappedActionId = id,
              onDismiss: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('View'), findsOneWidget);
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();

      expect(tappedActionId, 'AC-1029');
    });

    testWidgets('2. QuickAlertToast resolves action from message when actionId is omitted', (
      tester,
    ) async {
      String? tappedActionId;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuickAlertToast(
              notification: AppNotification(
                id: 'notif-toast-2',
                userId: 'EMP-2049',
                title: 'Action Reminder',
                message: 'Action AC-1048 target date approaches.',
                eventType: 'action_reminder',
                actionId: null,
                createdAt: DateTime.now(),
              ),
              onActionTap: (id) => tappedActionId = id,
              onDismiss: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('View'), findsOneWidget);
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();

      expect(tappedActionId, 'AC-1048');
    });
  });
}
