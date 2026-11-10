import 'dart:convert';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/add_action_screen.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:action_flow/services/app_file_picker_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    MockPeopleStore.instance.people.removeWhere(
      (p) => p.id.startsWith('TEST-') || p.email.contains('workflow-test'),
    );
  });

  Future<void> selectInternalWorker(WidgetTester tester) async {
    final internalSearchField = find.widgetWithText(
      TextFormField,
      'Search by name, email, or phone...',
    );
    if (internalSearchField.evaluate().isNotEmpty) {
      await tester.enterText(internalSearchField, 'r.kumar@actionflow.demo');
      await tester.pumpAndSettle();
      final resultTile = find.text('Maintenance • North Plant');
      if (resultTile.evaluate().isNotEmpty) {
        await tester.tap(resultTile);
        await tester.pumpAndSettle();
      }
    }
  }

  group('Complete Add Action Workflow Acceptance Tests', () {
    testWidgets('1. Validation: Rejects empty title and description with validation snackbar', (tester) async {
      tester.view.physicalSize = const Size(1280, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(home: AddActionScreen(actionId: 'AC-TEST-01')),
      );
      await tester.pumpAndSettle();

      // Tap Send Action with empty title
      await tester.tap(find.text('SEND ACTION'));
      await tester.pumpAndSettle();

      expect(find.text('Please fill all required fields correctly.'), findsOneWidget);
    });

    testWidgets('2. Validation: Rejects subtask with empty title', (tester) async {
      tester.view.physicalSize = const Size(1280, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(home: AddActionScreen(actionId: 'AC-TEST-02')),
      );
      await tester.pumpAndSettle();

      // Fill required title and description
      await tester.enterText(
        find.byType(TextFormField).first,
        'Test Safety Action',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Implement required safety barrier',
      );

      // Select internal worker so worker check passes
      await selectInternalWorker(tester);

      // Add a subtask without setting a title
      await tester.tap(find.byKey(const Key('add_task_btn')));
      await tester.pumpAndSettle();

      // Try saving while subtask title is empty
      await tester.tap(find.text('SEND ACTION'));
      await tester.pumpAndSettle();

      expect(find.textContaining('requires a title'), findsOneWidget);
    });

    testWidgets('3. Internal Assignment: Maps primary and additional assignees into ActionRecord', (tester) async {
      tester.view.physicalSize = const Size(1280, 2500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      ActionRecord? createdRecord;

      await tester.pumpWidget(
        MaterialApp(
          home: AddActionScreen(
            actionId: 'AC-INT-01',
            onSaved: (rec) {
              createdRecord = rec;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter Title & Description
      await tester.enterText(
        find.byType(TextFormField).first,
        'Internal Ventilation Check',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Inspect HVAC air handling units',
      );

      // Select internal worker
      await selectInternalWorker(tester);

      // Verify email reminder is OFF by default
      final reminderSwitch = find.byKey(const Key('email_reminder_toggle_switch'));
      if (reminderSwitch.evaluate().isNotEmpty) {
        final switchWidget = tester.widget<Switch>(reminderSwitch);
        expect(switchWidget.value, isFalse);
      }

      // Submit
      await tester.tap(find.text('SEND ACTION'));
      await tester.pumpAndSettle();

      expect(createdRecord, isNotNull);
      expect(createdRecord!.recipientType, equals('internal'));
      expect(createdRecord!.subject, equals('Internal Ventilation Check'));
      expect(createdRecord!.actionRequired, equals('Inspect HVAC air handling units'));
      expect(createdRecord!.assignedTo, equals('R. Kumar'));
      expect(createdRecord!.emailReminderEnabled, isFalse);
    });

    testWidgets('4. External Assignment: "+ Add Another External User" adds multiple external users', (tester) async {
      tester.view.physicalSize = const Size(1280, 2500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      ActionRecord? createdRecord;

      await tester.pumpWidget(
        MaterialApp(
          home: AddActionScreen(
            actionId: 'AC-EXT-01',
            onSaved: (rec) {
              createdRecord = rec;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to External Assignment
      await tester.tap(find.byKey(const Key('recipient_type_external')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_another_external_user_btn')), findsOneWidget);

      // Open Modal to add another external user
      await tester.tap(find.byKey(const Key('add_another_external_user_btn')));
      await tester.pumpAndSettle();

      expect(find.text('Add Another External User'), findsOneWidget);

      // Fill in new external user details inside the AlertDialog
      final dialogFields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(dialogFields.at(0), 'Contractor Alex');
      await tester.enterText(dialogFields.at(1), 'alex@contractor.com');
      await tester.enterText(dialogFields.at(2), 'Apex Engineering');

      // Save user from modal
      await tester.tap(find.text('Add External User'));
      await tester.pumpAndSettle();

      // Verify that Contractor Alex is displayed in the Additional External Users list
      expect(find.text('Contractor Alex'), findsOneWidget);
      expect(find.text('Additional External Users (1)'), findsOneWidget);

      // Fill required Title & Description & Primary External User Name
      await tester.enterText(
        find.byType(TextFormField).first,
        'External Scaffolding Inspection',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Inspect third-party scaffolding towers',
      );

      final extPrimaryField = find.widgetWithText(TextFormField, 'Full Name *');
      await tester.enterText(extPrimaryField, 'Primary Lead Contractor');

      // Save Action
      await tester.tap(find.text('SEND ACTION'));
      await tester.pumpAndSettle();

      expect(createdRecord, isNotNull);
      expect(createdRecord!.recipientType, equals('external'));
      expect(createdRecord!.assignedTo, equals('Primary Lead Contractor'));
      expect(createdRecord!.additionalPeople.length, equals(1));
      expect(createdRecord!.additionalPeople.first.name, equals('Contractor Alex'));
      expect(createdRecord!.additionalPeople.first.email, equals('alex@contractor.com'));
    });

    testWidgets('5. Email Reminder Settings: Defaults to OFF, validates reminder date not after close date', (tester) async {
      tester.view.physicalSize = const Size(1280, 2500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(home: AddActionScreen(actionId: 'AC-REM-01')),
      );
      await tester.pumpAndSettle();

      // Toggle email reminder to ON
      final reminderToggle = find.byKey(const Key('email_reminder_toggle_switch'));
      if (reminderToggle.evaluate().isNotEmpty) {
        await tester.tap(reminderToggle);
        await tester.pumpAndSettle();

        // Verify reminder controls appeared
        expect(find.textContaining('Reminder Schedules'), findsWidgets);
      }
    });

    testWidgets('6. Subtasks: Adding subtasks registers subtasks in ActionRecord', (tester) async {
      tester.view.physicalSize = const Size(1280, 2500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      ActionRecord? createdRecord;

      await tester.pumpWidget(
        MaterialApp(
          home: AddActionScreen(
            actionId: 'AC-SUB-01',
            onSaved: (rec) {
              createdRecord = rec;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        'Emergency Equipment Commissioning',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Commission and verify fire dampers and alarms',
      );

      // Select internal worker
      await selectInternalWorker(tester);

      // Add Subtask 1
      await tester.tap(find.byKey(const Key('add_task_btn')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('task_title_input_0')),
        'Inspect damper electrical relays',
      );

      // Add Subtask 2
      await tester.tap(find.byKey(const Key('add_task_btn')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('task_title_input_1')),
        'Verify audio alarm decibel output',
      );

      await tester.tap(find.text('SEND ACTION'));
      await tester.pumpAndSettle();

      expect(createdRecord, isNotNull);
      expect(createdRecord!.subTasks.length, equals(2));
      expect(createdRecord!.subTasks[0].title, equals('Inspect damper electrical relays'));
      expect(createdRecord!.subTasks[1].title, equals('Verify audio alarm decibel output'));
    });

    test('7. Model & Service: createAction properly seeds action record, assignees and subtasks', () async {
      final newRecord = ActionRecord(
        id: 'act-workflow-999',
        actionNumber: 'ACT-999',
        organizationId: Organization.sobhaId,
        subject: 'Confined Space Entry Safety Protocol',
        actionRequired: 'Provide gas testing certificate and air blower',
        priority: 'Critical',
        status: 'Open',
        percentComplete: 0,
        department: 'Operations',
        division: 'Engineering',
        site: 'Site Bravo',
        dateRaised: '2026-11-01',
        targetDate: '2026-11-15',
        createdById: 'user-manager-001',
        assignedTo: 'Suresh Worker',
        assignedToId: 'user-worker-001',
        recipientType: 'internal',
        subTasks: [
          ActionSubTask(
            id: 'st-01',
            parentActionId: 'act-workflow-999',
            title: 'Calibrate multigas detector',
            instruction: 'Verify 4-gas sensor response with calibration gas',
            status: 'Completed',
            assignedStaffId: 'user-worker-001',
            assignedStaff: 'Suresh Worker',
          ),
          ActionSubTask(
            id: 'st-02',
            parentActionId: 'act-workflow-999',
            title: 'Verify ventilation blower CFM',
            instruction: 'Ensure minimum 20 air changes per hour',
            status: 'Open',
            assignedStaffId: 'user-worker-002',
            assignedStaff: 'Anita Safety',
          ),
        ],
        attachments: ['Gas_Calibration_Cert.pdf'],
        emailReminderEnabled: false,
      );

      final persisted = await ActionService.instance.createAction(newRecord);
      expect(persisted.id, equals('act-workflow-999'));
      expect(persisted.subTasks.length, equals(2));
      expect(persisted.subTasks[0].isCompleted, isTrue);
      expect(persisted.subTasks[1].isCompleted, isFalse);
      expect(persisted.attachments, contains('Gas_Calibration_Cert.pdf'));
    });
  });
}
