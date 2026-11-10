import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/add_action_screen.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    MockActionStore.instance.actions.clear();
  });

  tearDown(() {
    ActionService.instance.mockAssigneePersistenceShouldFail = false;
  });

  testWidgets(
    'AddActionScreen persists created action via ActionService and updates MockActionStore',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      ActionRecord? receivedSavedRecord;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddActionScreen(
              actionId: 'AUTO',
              onSaved: (record) => receivedSavedRecord = record,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Fill in Action Title
      final titleFinder = find.widgetWithText(TextFormField, 'Action Title *');
      await tester.ensureVisible(titleFinder);
      await tester.enterText(titleFinder, 'Test Fire Extinguisher Inspection');

      // Fill in Action Description
      final descFinder = find.widgetWithText(TextFormField, 'Action Description');
      await tester.ensureVisible(descFinder);
      await tester.enterText(descFinder, 'Ensure monthly inspection tag is verified');

      // Assign R. Kumar
      final internalSearch = find.widgetWithText(
        TextFormField,
        'Search by name, email, or phone...',
      );
      await tester.ensureVisible(internalSearch);
      await tester.enterText(internalSearch, 'Kumar');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maintenance • North Plant').first);
      await tester.pumpAndSettle();

      // Submit
      final sendBtn = find.text('SEND ACTION');
      await tester.ensureVisible(sendBtn);
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      // Verify success snackbar and callback
      expect(find.textContaining('created successfully!'), findsOneWidget);
      expect(receivedSavedRecord, isNotNull);
      expect(receivedSavedRecord!.subject, equals('Test Fire Extinguisher Inspection'));
      expect(receivedSavedRecord!.assignedTo, equals('R. Kumar'));

      // Verify persisted in MockActionStore
      final storedAction = MockActionStore.instance.actions
          .firstWhere((a) => a.subject == 'Test Fire Extinguisher Inspection');
      expect(storedAction, isNotNull);
      expect(storedAction.actionRequired, equals('Ensure monthly inspection tag is verified'));
    },
  );

  testWidgets(
    'Created action is retrievable by Staff Portal fetchMyActions for the assigned staff user',
    (tester) async {
      // 1. Create action assigned to R. Kumar (id: a1000000-0000-0000-0000-000000000001)
      final action = ActionRecord(
        id: 'ACT-PERSIST-001',
        actionNumber: 'ACT-001',
        subject: 'Inspect Safety Harnesses',
        actionRequired: 'Verify safety clip integrity',
        division: 'Operations',
        priority: 'High',
        status: 'Open',
        department: 'Maintenance',
        site: 'North Plant',
        assignedTo: 'R. Kumar',
        assignedToId: 'a1000000-0000-0000-0000-000000000001',
        organizationId: Organization.sobhaId,
        dateRaised: '01 Jan 2026',
        targetDate: '15 Jan 2026',
      );

      final created = await ActionService.instance.createAction(action);
      expect(created, isNotNull);

      // 2. Fetch via fetchMyActions for R. Kumar
      final myActions = await ActionService.instance.fetchMyActions(
        organizationId: Organization.sobhaId,
        userId: 'a1000000-0000-0000-0000-000000000001',
      );

      expect(myActions.any((a) => a.id == 'ACT-PERSIST-001'), isTrue);
      expect(myActions.firstWhere((a) => a.id == 'ACT-PERSIST-001').subject, equals('Inspect Safety Harnesses'));
    },
  );

  testWidgets(
    'Database error on createAction displays error SnackBar and prevents false-positive success',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Simulate a failure in ActionService
      ActionService.instance.mockAssigneePersistenceShouldFail = true;

      bool saveCallbackFired = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddActionScreen(
              actionId: 'AUTO',
              onSaved: (_) => saveCallbackFired = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Fill in Action Title
      final titleFinder = find.widgetWithText(TextFormField, 'Action Title *');
      await tester.ensureVisible(titleFinder);
      await tester.enterText(titleFinder, 'Action That Fails Persistence');

      // Fill in Action Description
      final descFinder = find.widgetWithText(TextFormField, 'Action Description');
      await tester.ensureVisible(descFinder);
      await tester.enterText(descFinder, 'This should show an error SnackBar');

      // Assign R. Kumar
      final internalSearch = find.widgetWithText(
        TextFormField,
        'Search by name, email, or phone...',
      );
      await tester.ensureVisible(internalSearch);
      await tester.enterText(internalSearch, 'Kumar');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maintenance • North Plant').first);
      await tester.pumpAndSettle();

      // Submit
      final sendBtn = find.text('SEND ACTION');
      await tester.ensureVisible(sendBtn);
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      // MUST NOT call onSaved or show success
      expect(saveCallbackFired, isFalse);
      expect(find.textContaining('created successfully!'), findsNothing);

      // MUST show error snackbar
      expect(find.textContaining('Failed to save action:'), findsOneWidget);
    },
  );

  testWidgets(
    'Editing existing action calls updateAction and persists changes in MockActionStore',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final initialAction = ActionRecord(
        id: 'ACT-EDIT-001',
        actionNumber: 'ACT-001',
        subject: 'Initial Subject',
        actionRequired: 'Initial Description',
        division: 'Operations',
        priority: 'Low',
        status: 'Open',
        department: 'Maintenance',
        site: 'North Plant',
        assignedTo: 'R. Kumar',
        assignedToId: 'a1000000-0000-0000-0000-000000000001',
        organizationId: Organization.sobhaId,
        dateRaised: '01 Jan 2026',
        targetDate: '15 Jan 2026',
      );
      MockActionStore.instance.add(initialAction);

      ActionRecord? updatedRecord;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddActionScreen(
              actionId: initialAction.id,
              existingAction: initialAction,
              onSaved: (r) => updatedRecord = r,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Change title
      final titleFinder = find.widgetWithText(TextFormField, 'Action Title *');
      await tester.ensureVisible(titleFinder);
      await tester.enterText(titleFinder, 'Updated Subject Title');

      // Tap SAVE
      final saveBtn = find.text('SAVE CHANGES');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(updatedRecord, isNotNull);
      expect(updatedRecord!.id, equals('ACT-EDIT-001'));
      expect(updatedRecord!.subject, equals('Updated Subject Title'));

      final stored = MockActionStore.instance.actions
          .firstWhere((a) => a.id == 'ACT-EDIT-001');
      expect(stored.subject, equals('Updated Subject Title'));
    },
  );
}
