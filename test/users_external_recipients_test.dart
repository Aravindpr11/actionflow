import 'package:action_flow/features/auth/models/manager_scope_item.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/external_recipient.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/screens/users_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    MockActionStore.instance.externalRecipients.clear();
  });

  tearDown(() {
    MockActionStore.instance.externalRecipients.clear();
  });

  testWidgets(
    'UsersScreen displays saved external recipients and filters by Person Type (All Types, External, Internal)',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Add a dedicated external recipient to MockActionStore
      MockActionStore.instance.externalRecipients.add(
        const ExternalRecipient(
          id: 'ext-recip-101',
          fullName: 'Jane External',
          email: 'jane.ext@globalcontractors.demo',
          phone: '+1 555 0199',
          companyName: 'Global Contractors Ltd',
          organizationId: 'sobha-test-org',
          isActive: true,
        ),
      );

      await tester.pumpWidget(const MaterialApp(home: UsersScreen()));
      await tester.pumpAndSettle();

      // In "All Types", both internal (R. Kumar) and external (Jane External) are visible
      expect(find.text('R. Kumar'), findsOneWidget);
      expect(find.text('Jane External'), findsOneWidget);
      expect(find.text('External User'), findsWidgets);
      expect(find.text('Internal User'), findsWidgets);

      // Filter by Person Type: External
      await tester.tap(find.text('All Types'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('External').last);
      await tester.pumpAndSettle();

      // Only external users are visible
      expect(find.text('Jane External'), findsOneWidget);
      expect(find.text('Global Contractors Ltd'), findsOneWidget);
      expect(find.text('R. Kumar'), findsNothing);
      expect(find.text('M. Ali'), findsNothing);
      expect(find.text('Internal User'), findsNothing);

      // Filter by Person Type: Internal
      await tester.tap(find.text('External'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Internal').last);
      await tester.pumpAndSettle();

      // Only internal staff are visible
      expect(find.text('R. Kumar'), findsOneWidget);
      expect(find.text('M. Ali'), findsOneWidget);
      expect(find.text('Jane External'), findsNothing);
      expect(find.text('External User'), findsNothing);
    },
  );

  testWidgets(
    'UsersScreen searches external company name and displays external contact details',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      MockActionStore.instance.externalRecipients.add(
        const ExternalRecipient(
          id: 'ext-recip-102',
          fullName: 'Robert External',
          email: 'robert@apexengineering.demo',
          phone: '+1 555 0288',
          companyName: 'Apex Engineering Group',
          organizationId: 'sobha-test-org',
          isActive: true,
        ),
      );

      await tester.pumpWidget(const MaterialApp(home: UsersScreen()));
      await tester.pumpAndSettle();

      // Search by company name "Apex Engineering"
      await tester.enterText(
        find.widgetWithText(TextField, 'Search name, email, phone, designation...'),
        'Apex Engineering',
      );
      await tester.pumpAndSettle();

      expect(find.text('Robert External'), findsOneWidget);
      expect(find.text('R. Kumar'), findsNothing);

      // Tap on the external person row to open bottom sheet details
      await tester.tap(find.text('Robert External'));
      await tester.pumpAndSettle();

      // Details sheet renders
      expect(find.text('External User'), findsWidgets);
      expect(find.text('Company / Organization'), findsOneWidget);
      expect(find.text('Apex Engineering Group'), findsWidgets);
    },
  );

  testWidgets(
    'UsersScreen with ManagerContext loads external users, shows disclaimer and respects department filter',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      MockActionStore.instance.externalRecipients.add(
        const ExternalRecipient(
          id: 'ext-recip-103',
          fullName: 'Alice External Specialist',
          email: 'alice@safeprotect.demo',
          phone: '+1 555 0377',
          companyName: 'SafeProtect Global',
          organizationId: 'org-test-sobha',
          isActive: true,
        ),
      );

      const managerContext = ManagerContext(
        authUserId: 'mgr-001',
        profile: UserProfile(
          id: 'mgr-001',
          name: 'Manager Smith',
          email: 'smith@actionflow.demo',
          phone: '+1 234 5678',
          designation: 'HSE Manager',
          department: 'HSE',
          site: 'Warehouse B',
          role: 'Manager',
        ),
        organizationId: 'org-test-sobha',
        organizationName: 'Sobha Test',
        scopes: [
          ManagerScopeItem(
            departmentId: 'dept-hse-id',
            departmentName: 'HSE',
            siteId: 'site-whb-id',
            siteName: 'Warehouse B',
          ),
        ],
        isActive: true,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: UsersScreen(managerContext: managerContext),
        ),
      );
      await tester.pumpAndSettle();

      // Both internal staff in offline mock and external users should be loaded
      expect(find.text('People / Staff Directory'), findsOneWidget);

      // Filter by Person Type: External
      await tester.tap(find.text('All Types'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('External').last);
      await tester.pumpAndSettle();

      // External user should be present
      expect(find.text('Alice External Specialist'), findsOneWidget);
      expect(find.text('External User'), findsWidgets);

      // Open details for Alice External Specialist in manager mode
      await tester.tap(find.text('Alice External Specialist'));
      await tester.pumpAndSettle();

      // Check external contact profile badge and disclaimer note
      expect(find.text('External Contact Profile'), findsOneWidget);
      expect(
        find.text(
          'External user records are contact references without ActionFlow login accounts or internal scopes.',
        ),
        findsOneWidget,
      );

      // Close bottom sheet
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      // Switch back to All Types
      await tester.tap(find.text('External'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Types').last);
      await tester.pumpAndSettle();

      // Filter by Department: HSE
      // External users do not have internal departments, so filtering by HSE should exclude external users
      await tester.tap(find.text('All Departments'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HSE').last);
      await tester.pumpAndSettle();

      // Alice External Specialist should NOT be shown under HSE department filter
      expect(find.text('Alice External Specialist'), findsNothing);
    },
  );

  testWidgets(
    'External user classification is determined strictly by data type, not by name or email strings',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // An external user with an email and name that sound like internal staff
      MockActionStore.instance.externalRecipients.add(
        const ExternalRecipient(
          id: 'ext-recip-104',
          fullName: 'Internal Department Supervisor',
          email: 'supervisor@actionflow.internal',
          phone: '+1 555 0466',
          companyName: 'External Vendor Corp',
          organizationId: 'sobha-test-org',
          isActive: true,
        ),
      );

      await tester.pumpWidget(const MaterialApp(home: UsersScreen()));
      await tester.pumpAndSettle();

      // Filter by Person Type: External
      await tester.tap(find.text('All Types'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('External').last);
      await tester.pumpAndSettle();

      // Identified as external user despite having "Internal" in their name and email
      expect(find.text('Internal Department Supervisor'), findsOneWidget);
      expect(find.text('External User'), findsWidgets);
    },
  );
}

