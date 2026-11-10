import 'dart:typed_data';
import 'package:action_flow/services/app_file_picker_service.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/external_recipient.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/add_action_screen.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    // Reset test additions from MockPeopleStore
    MockPeopleStore.instance.people.removeWhere(
      (p) =>
          p.id.startsWith('AFU-TEST') ||
          p.id.startsWith('EXT-TEST') ||
          p.email.contains('test') ||
          p.email.contains('rule') ||
          p.email.contains('anita'),
    );
  });

  testWidgets(
    'AddActionScreen renders all sections and handles UI interactions on desktop',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(home: AddActionScreen(actionId: 'AC-101')),
      );
      await tester.pumpAndSettle();

      // Verify Title & Action ID
      expect(find.text('Add New Action'), findsOneWidget);
      expect(find.text('AC-101'), findsOneWidget);
      expect(find.text('SEND ACTION'), findsOneWidget);

      // Verify Numbered Sections
      expect(find.text('WHAT THE ACTION IS'), findsOneWidget);
      expect(find.text('WHERE IT BELONGS'), findsOneWidget);
      expect(find.text('ASSIGNMENT'), findsOneWidget);
      expect(find.text('PRIORITY & STATUS'), findsOneWidget);
      expect(find.text('DATES'), findsOneWidget);
      expect(find.text('EVIDENCE / ATTACHMENTS'), findsOneWidget);

      // Verify Segmented Assignment Panels
      expect(find.text('INTERNAL PERSON'), findsOneWidget);
      expect(find.text('Add Internal Person'), findsOneWidget);
      expect(find.text('Add New Internal Person'), findsOneWidget);

      // Open "Add New Internal Person" Dialog
      await tester.tap(find.text('Add New Internal Person'));
      await tester.pumpAndSettle();

      expect(find.text('Select existing ActionFlow person'), findsOneWidget);
      expect(find.text('Save Person'), findsOneWidget);

      // Close Dialog with Cancel
      await tester.tap(
        find.descendant(of: find.byType(Dialog), matching: find.text('Cancel')),
      );
      await tester.pumpAndSettle();

      // Switch to External Assignment Panel via Segmented Toggle
      await tester.tap(find.byKey(const Key('recipient_type_external')));
      await tester.pumpAndSettle();

      expect(find.text('EXTERNAL USER / RECIPIENT'), findsOneWidget);
      expect(find.text('+ Add Another External User'), findsOneWidget);

      // Open "+ Add Another External User" Dialog
      await tester.tap(find.text('+ Add Another External User'));
      await tester.pumpAndSettle();

      expect(find.text('Add Another External User'), findsOneWidget);

      // Close Dialog with Cancel
      await tester.tap(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('Cancel')),
      );
      await tester.pumpAndSettle();

      // Verify Bottom Actions
      expect(find.text('Send Action'), findsWidgets);
    },
  );

  testWidgets(
    'AddActionScreen header renders without overflow on 400px mobile width',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(home: AddActionScreen(actionId: 'AC-101')),
      );
      await tester.pumpAndSettle();

      // Verify no RenderFlex errors and widgets exist
      expect(find.text('Add New Action'), findsOneWidget);
      expect(find.text('AC-101'), findsOneWidget);
      expect(find.text('SEND'), findsOneWidget);
    },
  );

  testWidgets(
    'AddActionScreen header renders without overflow on 320px ultra-compact width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(home: AddActionScreen(actionId: 'AC-101')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add New Action'), findsOneWidget);
      expect(find.text('AC-101'), findsOneWidget);
      expect(find.text('SEND'), findsOneWidget);
    },
  );

  testWidgets(
    'AddActionScreen internal person search by name, email, phone with suggestions and same-name separation',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Add a second person with same name but distinct department & email
      final store = MockPeopleStore.instance;
      final secondKumar = Person(
        id: 'AFU-TEST-KUMAR2',
        name: 'R. Kumar',
        email: 'r.kumar.hse@sobha.demo',
        phone: '+91 99999 22222',
        designation: 'Safety Engineer',
        department: 'HSE',
        site: 'Site 1',
        type: PersonType.internalUser,
        isActive: true,
      );
      if (!store.people.any((p) => p.id == secondKumar.id)) {
        store.people.add(secondKumar);
      }

      await tester.pumpWidget(
        const MaterialApp(home: AddActionScreen(actionId: 'AC-101')),
      );
      await tester.pumpAndSettle();

      // Search by name "Kumar"
      final searchField = find.widgetWithText(
        TextFormField,
        'Search by name, email, or phone...',
      );
      expect(searchField, findsOneWidget);

      await tester.enterText(searchField, 'Kumar');
      await tester.pumpAndSettle();

      // Verify suggestions appear with department and site badges
      expect(find.text('Maintenance • North Plant'), findsOneWidget);
      expect(find.text('HSE • Site 1'), findsOneWidget);

      // Select the first R. Kumar
      await tester.tap(find.text('Maintenance • North Plant'));
      await tester.pumpAndSettle();

      // Verify selected primary internal person card renders
      expect(find.text('R. Kumar'), findsOneWidget);
      expect(find.text('Primary'), findsOneWidget);
      expect(find.textContaining('Maintenance'), findsWidgets);
    },
  );

  testWidgets(
    'AddActionScreen external person selection auto-fills fields',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        MockActionStore.instance.externalRecipients.clear();
      });

      final kPatel = ExternalRecipient(
        id: 'rec-patel-1',
        organizationId: '00000000-0000-0000-0000-000000000001',
        fullName: 'K. Patel',
        email: 'k.patel@safecontractors.demo',
        phone: '+91 90000 20001',
        companyName: 'Safe Contractors Ltd',
      );
      MockActionStore.instance.externalRecipients.add(kPatel);

      await tester.pumpWidget(
        const MaterialApp(home: AddActionScreen(actionId: 'AC-101')),
      );
      await tester.pumpAndSettle();

      // Switch to External tab
      await tester.tap(find.byKey(const Key('recipient_type_external')));
      await tester.pumpAndSettle();

      final dropdown = find.byType(DropdownButtonFormField<String?>);
      expect(dropdown, findsOneWidget);

      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('K. Patel').last);
      await tester.pumpAndSettle();

      // External fields should be auto-filled
      expect(find.widgetWithText(TextFormField, 'K. Patel'), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'k.patel@safecontractors.demo'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextFormField, 'Safe Contractors Ltd'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextFormField, '+91 90000 20001'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'AddActionScreen Add New Internal Person dialog prevents duplicate email and allows reuse',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(home: AddActionScreen(actionId: 'AC-101')),
      );
      await tester.pumpAndSettle();

      // Open Add New Internal Person dialog
      await tester.tap(find.text('Add New Internal Person'));
      await tester.pumpAndSettle();

      // Fill with existing person's email
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full Name *'),
        'R. Kumar Duplicate',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email *'),
        'r.kumar@actionflow.demo',
      );

      // Tap Save Person
      await tester.tap(find.text('Save Person'));
      await tester.pumpAndSettle();

      // Duplicate Dialog appears
      expect(find.text('Person already exists'), findsOneWidget);
      expect(find.text('Use Existing Person'), findsOneWidget);

      // Tap Use Existing Person
      await tester.tap(find.text('Use Existing Person'));
      await tester.pumpAndSettle();

      // Verify Internal Primary selected R. Kumar
      expect(find.text('R. Kumar'), findsWidgets);
    },
  );

  testWidgets(
    'AddActionScreen Add Another External User dialog prevents duplicate email and allows selecting existing recipient',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        MockActionStore.instance.externalRecipients.clear();
      });

      final kPatel = ExternalRecipient(
        id: 'rec-patel-1',
        organizationId: '00000000-0000-0000-0000-000000000001',
        fullName: 'K. Patel',
        email: 'k.patel@safecontractors.demo',
        phone: '+91 90000 20001',
        companyName: 'Safe Contractors Ltd',
      );
      MockActionStore.instance.externalRecipients.add(kPatel);

      await tester.pumpWidget(
        const MaterialApp(home: AddActionScreen(actionId: 'AC-101')),
      );
      await tester.pumpAndSettle();

      // Switch to External tab
      await tester.tap(find.byKey(const Key('recipient_type_external')));
      await tester.pumpAndSettle();

      // Primary External
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full Name *'),
        'Contractor Alpha',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email Address *'),
        'alpha@contractor.com',
      );
      await tester.pumpAndSettle();

      // Open Add Another External User dialog
      final addAnotherBtn =
          find.byKey(const Key('add_another_external_user_btn'));
      await tester.tap(addAnotherBtn);
      await tester.pumpAndSettle();

      expect(find.text('Add Another External User'), findsOneWidget);

      // Select existing recipient (K. Patel) from dropdown
      final dialogDropdown = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(DropdownButtonFormField<String?>),
      );
      expect(dialogDropdown, findsOneWidget);
      await tester.tap(dialogDropdown);
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('K. Patel').last);
      await tester.pumpAndSettle();

      // Tap Add External User
      final submitBtn = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Add External User'),
      );
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Verify K. Patel is added to Additional External Users
      expect(find.text('Additional External Users (1)'), findsOneWidget);
      expect(find.text('K. Patel'), findsWidgets);

      // Attempt to add duplicate recipient with same email
      await tester.tap(addAnotherBtn);
      await tester.pumpAndSettle();

      final dialogName = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextFormField, 'Full Name *'),
      );
      final dialogEmail = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextFormField, 'Email Address *'),
      );
      await tester.enterText(dialogName, 'K. Patel Duplicate');
      await tester.enterText(dialogEmail, 'k.patel@safecontractors.demo');
      await tester.pumpAndSettle();

      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Verify duplicate was prevented, count remains 1
      expect(find.text('Additional External Users (1)'), findsOneWidget);
    },
  );

  testWidgets(
    'AddActionScreen allows editing Primary Internal Person and updates UI while preserving ID and MockPeopleStore',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final originalKumar = MockPeopleStore.instance.people.firstWhere(
        (p) => p.name == 'R. Kumar',
      );
      final originalDesignation = originalKumar.designation;

      await tester.pumpWidget(
        const MaterialApp(home: AddActionScreen(actionId: 'AC-101')),
      );
      await tester.pumpAndSettle();

      // Search and select R. Kumar
      final internalSearchField = find.widgetWithText(
        TextFormField,
        'Search by name, email, or phone...',
      );
      await tester.enterText(internalSearchField, 'r.kumar@actionflow.demo');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Maintenance • North Plant'));
      await tester.pumpAndSettle();

      expect(find.text('R. Kumar'), findsWidgets);

      // Tap Edit icon button on the primary internal person card
      final editButton = find.byTooltip('Edit Internal Person');
      expect(editButton, findsOneWidget);
      await tester.tap(editButton);
      await tester.pumpAndSettle();

      // Dialog opens with "Edit Internal Person"
      expect(find.text('Edit Internal Person'), findsOneWidget);
      expect(find.text('Save Person'), findsOneWidget);

      // Edit designation and site
      final designationField = find.widgetWithText(
        TextFormField,
        'Designation / Role',
      );
      await tester.enterText(designationField, 'Lead Safety Officer');

      final siteField = find.widgetWithText(TextFormField, 'Project / Site');
      await tester.enterText(siteField, 'West Yard');

      // Save
      await tester.tap(find.text('Save Person'));
      await tester.pumpAndSettle();

      // Verify the UI card reflects the edited details
      expect(find.textContaining('Lead Safety Officer'), findsOneWidget);
      expect(find.textContaining('West Yard'), findsOneWidget);

      // Verify official MockPeopleStore record was NOT mutated
      final storeKumar = MockPeopleStore.instance.people.firstWhere(
        (p) => p.name == 'R. Kumar',
      );
      expect(storeKumar.designation, equals(originalDesignation));
    },
  );

  testWidgets('AddActionScreen allows editing Additional Internal Person', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(home: AddActionScreen(actionId: 'AC-101')),
    );
    await tester.pumpAndSettle();

    // Set primary person first
    final internalSearchField = find.widgetWithText(
      TextFormField,
      'Search by name, email, or phone...',
    );
    await tester.enterText(internalSearchField, 'r.kumar@actionflow.demo');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maintenance • North Plant'));
    await tester.pumpAndSettle();

    // Click "Add New Internal Person" to add another person
    await tester.tap(find.text('Add New Internal Person'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full Name *'),
      'Anita Roy',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email *'),
      'anita.roy@actionflow.demo',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Designation / Role'),
      'Civil Inspector',
    );
    await tester.tap(find.text('Save Person'));
    await tester.pumpAndSettle();

    expect(find.text('Additional Internal Persons (1)'), findsOneWidget);

    // Edit the additional person
    final editButtons = find.byTooltip('Edit Internal Person');
    expect(editButtons, findsNWidgets(2));

    await tester.tap(editButtons.last);
    await tester.pumpAndSettle();

    expect(find.text('Edit Internal Person'), findsOneWidget);

    final desigField = find.widgetWithText(TextFormField, 'Designation / Role');
    await tester.enterText(desigField, 'Assistant Coordinator');

    await tester.tap(find.text('Save Person'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Assistant Coordinator'), findsOneWidget);
  });

  testWidgets(
    'AddActionScreen allows editing Primary and Additional External Person and removing them',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(home: AddActionScreen(actionId: 'AC-101')),
      );
      await tester.pumpAndSettle();

      // Switch to External tab
      await tester.tap(find.byKey(const Key('recipient_type_external')));
      await tester.pumpAndSettle();

      // Primary External
      final nameField = find.widgetWithText(TextFormField, 'Full Name *');
      final emailField = find.widgetWithText(TextFormField, 'Email Address *');
      final phoneField = find.widgetWithText(TextFormField, 'Phone');
      await tester.enterText(nameField, 'Contractor Alpha');
      await tester.enterText(emailField, 'alpha@contractor.com');
      await tester.enterText(phoneField, '+91 88888 77777');
      await tester.pumpAndSettle();

      expect(find.text('Contractor Alpha'), findsOneWidget);
      expect(find.text('+91 88888 77777'), findsOneWidget);

      // Add Additional External Person via dialog
      final addAnotherBtn =
          find.byKey(const Key('add_another_external_user_btn'));
      await tester.tap(addAnotherBtn);
      await tester.pumpAndSettle();

      final dialogName = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextFormField, 'Full Name *'),
      );
      final dialogEmail = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextFormField, 'Email Address *'),
      );
      await tester.enterText(dialogName, 'Contractor Beta');
      await tester.enterText(dialogEmail, 'beta@contractor.com');
      await tester.pumpAndSettle();

      final dialogSubmit = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Add External User'),
      );
      await tester.tap(dialogSubmit);
      await tester.pumpAndSettle();

      expect(find.text('Contractor Beta'), findsOneWidget);
      expect(find.text('Additional External Users (1)'), findsOneWidget);

      // Edit Additional External User
      final editBtn = find.byTooltip('Edit External User');
      expect(editBtn, findsOneWidget);
      await tester.tap(editBtn);
      await tester.pumpAndSettle();

      expect(find.text('Edit External User'), findsOneWidget);
      final editNameField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextFormField, 'Full Name *'),
      );
      await tester.enterText(editNameField, 'Contractor Beta Updated');
      await tester.pumpAndSettle();

      final editSaveBtn = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Save Changes'),
      );
      await tester.tap(editSaveBtn);
      await tester.pumpAndSettle();

      expect(find.text('Contractor Beta Updated'), findsOneWidget);

      // Remove Additional External User
      final removeBtn = find.byTooltip('Remove');
      expect(removeBtn, findsOneWidget);
      await tester.tap(removeBtn);
      await tester.pumpAndSettle();

      expect(find.text('Contractor Beta Updated'), findsNothing);
      expect(find.text('Additional External Users (1)'), findsNothing);
      expect(find.text('Contractor Alpha'), findsOneWidget);
    },
  );

  // ==========================================================================
  // BUSINESS RULES: FOCUSED EMAIL REMINDER VERIFICATION TESTS
  // ==========================================================================

  testWidgets(
    'Rule 10: Email Reminder toggle defaults to OFF on a new action',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(home: AddActionScreen(actionId: 'AC-101')),
      );
      await tester.pumpAndSettle();

      // Verify Email Reminder section exists
      expect(find.text('EMAIL REMINDER'), findsOneWidget);
      expect(find.text('Enable Email Reminder'), findsOneWidget);

      // Switch should be OFF
      final reminderSwitch = tester.widget<Switch>(find.byType(Switch).first);
      expect(reminderSwitch.value, isFalse);

      // Fields should be hidden by default
      expect(find.text('Reminder Date *'), findsNothing);
      expect(find.text('Reminder Time *'), findsNothing);
      expect(find.text('Send Reminder To'), findsNothing);
      expect(find.text('+ Add Another Reminder'), findsNothing);
    },
  );

  testWidgets(
    'Rule 9: If no people are assigned, Email Reminder shows clear warning and no directory users',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(home: AddActionScreen(actionId: 'AC-101')),
      );
      await tester.pumpAndSettle();

      // Turn on Email Reminder without assigning anyone
      final enableSwitch = find.byType(Switch).first;
      await tester.ensureVisible(enableSwitch);
      await tester.tap(enableSwitch);
      await tester.pumpAndSettle();

      // Clear warning appears
      expect(
        find.text(
          'Add at least one person in Assignment before selecting email reminder recipients.',
        ),
        findsOneWidget,
      );

      // No checkboxes or unrelated directory contacts appear
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('Sarah Jenkins'), findsNothing);
      expect(find.text('David Brown'), findsNothing);
      expect(find.text('Fatima Al-Zahra'), findsNothing);
    },
  );

  testWidgets(
    'Rule 1, 2, 3: Only assigned people (primary/additional internal and external) appear as reminder recipients, unassigned directory users do not',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(home: AddActionScreen(actionId: 'AC-101')),
      );
      await tester.pumpAndSettle();

      // 1. Primary Internal: R. Kumar
      final internalSearch = find.widgetWithText(
        TextFormField,
        'Search by name, email, or phone...',
      );
      await tester.enterText(internalSearch, 'Kumar');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maintenance • North Plant').first);
      await tester.pumpAndSettle();

      // 2. Additional Internal: Anita Roy via Add New Internal Person
      await tester.tap(find.text('Add New Internal Person'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full Name *'),
        'Anita Roy',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email *'),
        'anita.rule1@actionflow.demo',
      );
      await tester.tap(find.text('Save Person'));
      await tester.pumpAndSettle();

      // 3. Primary External: K. Patel
      await tester.tap(find.byKey(const Key('recipient_type_external')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full Name *'),
        'K. Patel',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email Address *'),
        'k.patel@safecontractors.demo',
      );
      await tester.pumpAndSettle();

      // 4. Additional External: John Smith via + Add Another External User
      final addExtBtn =
          find.byKey(const Key('add_another_external_user_btn'));
      await tester.ensureVisible(addExtBtn);
      await tester.tap(addExtBtn);
      await tester.pumpAndSettle();

      final dialogName = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextFormField, 'Full Name *'),
      );
      final dialogEmail = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextFormField, 'Email Address *'),
      );
      final dialogCompany = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextFormField, 'Company / Organization'),
      );
      await tester.enterText(dialogName, 'John Smith');
      await tester.enterText(dialogEmail, 'john.rule1@contractor.com');
      await tester.enterText(dialogCompany, 'Contractor Corp');
      await tester.pumpAndSettle();

      final dialogSubmit = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Add External User'),
      );
      await tester.tap(dialogSubmit);
      await tester.pumpAndSettle();

      // Turn on Email Reminder
      final enableSwitch = find.byType(Switch).first;
      await tester.ensureVisible(enableSwitch);
      await tester.tap(enableSwitch);
      await tester.pumpAndSettle();

      // Verify all 4 assigned people appear in the recipient list
      expect(find.text('R. Kumar'), findsWidgets);
      expect(find.text('Anita Roy'), findsWidgets);
      expect(find.text('K. Patel'), findsWidgets);
      expect(find.text('John Smith'), findsWidgets);

      // Verify exactly 4 checkboxes for the 4 assigned people
      expect(find.byType(Checkbox), findsNWidgets(4));

      // Verify unassigned People Directory users DO NOT appear
      expect(find.text('Sarah Jenkins'), findsNothing);
      expect(find.text('David Brown'), findsNothing);
      expect(find.text('Fatima Al-Zahra'), findsNothing);
    },
  );

  testWidgets(
    'Rule 4: Each reminder maintains independent recipient checkbox selections',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 4500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(home: AddActionScreen(actionId: 'AC-101')),
      );
      await tester.pumpAndSettle();

      // Assign Primary Internal: R. Kumar
      final internalSearch = find.widgetWithText(
        TextFormField,
        'Search by name, email, or phone...',
      );
      await tester.enterText(internalSearch, 'Kumar');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maintenance • North Plant').first);
      await tester.pumpAndSettle();

      // Assign Primary External: K. Patel
      await tester.tap(find.byKey(const Key('recipient_type_external')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full Name *'),
        'K. Patel',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email Address *'),
        'k.patel@safecontractors.demo',
      );
      await tester.pumpAndSettle();

      // Turn ON Email Reminder
      final enableSwitch = find.byType(Switch).first;
      await tester.ensureVisible(enableSwitch);
      await tester.tap(enableSwitch);
      await tester.pumpAndSettle();

      // Check R. Kumar in Reminder 1 (first checkbox)
      final r1Checkboxes = find.byType(Checkbox);
      expect(r1Checkboxes, findsNWidgets(2));
      await tester.tap(r1Checkboxes.first);
      await tester.pumpAndSettle();

      // Add Reminder 2
      final addAnotherBtn = find.text('+ Add Another Reminder');
      await tester.ensureVisible(addAnotherBtn);
      await tester.tap(addAnotherBtn);
      await tester.pumpAndSettle();

      final allCheckboxes = find.byType(Checkbox);
      expect(allCheckboxes, findsNWidgets(4));

      // In Reminder 2, check K. Patel (4th checkbox)
      await tester.tap(allCheckboxes.at(3));
      await tester.pumpAndSettle();

      // Verify Reminder 1: R. Kumar IS checked, K. Patel IS NOT checked
      expect(tester.widget<Checkbox>(allCheckboxes.at(0)).value, isTrue);
      expect(tester.widget<Checkbox>(allCheckboxes.at(1)).value, isFalse);

      // Verify Reminder 2: R. Kumar IS NOT checked, K. Patel IS checked
      expect(tester.widget<Checkbox>(allCheckboxes.at(2)).value, isFalse);
      expect(tester.widget<Checkbox>(allCheckboxes.at(3)).value, isTrue);
    },
  );

  testWidgets(
    'Rule 5: Adding a newly assigned person makes them dynamically available in existing reminders',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(home: AddActionScreen(actionId: 'AC-101')),
      );
      await tester.pumpAndSettle();

      // Assign Primary Internal: R. Kumar
      final internalSearch = find.widgetWithText(
        TextFormField,
        'Search by name, email, or phone...',
      );
      await tester.enterText(internalSearch, 'Kumar');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maintenance • North Plant').first);
      await tester.pumpAndSettle();

      // Turn ON Email Reminder
      final enableSwitch = find.byType(Switch).first;
      await tester.ensureVisible(enableSwitch);
      await tester.tap(enableSwitch);
      await tester.pumpAndSettle();

      // Exactly 1 recipient in Reminder 1
      expect(find.byType(Checkbox), findsNWidgets(1));

      // Now add Additional Internal Person: Anita Roy
      await tester.tap(find.text('Add New Internal Person'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full Name *'),
        'Anita Roy',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email *'),
        'anita.rule5@actionflow.demo',
      );
      await tester.tap(find.text('Save Person'));
      await tester.pumpAndSettle();

      // Verify Reminder 1 now dynamically presents 2 recipient checkboxes
      expect(find.byType(Checkbox), findsNWidgets(2));
      expect(find.text('Anita Roy'), findsWidgets);
    },
  );

  testWidgets(
    'Rule 6: Removing an assigned person synchronizes and removes them from all reminder recipient lists',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 4500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(home: AddActionScreen(actionId: 'AC-101')),
      );
      await tester.pumpAndSettle();

      // Assign R. Kumar and K. Patel
      final internalSearch = find.widgetWithText(
        TextFormField,
        'Search by name, email, or phone...',
      );
      await tester.enterText(internalSearch, 'Kumar');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maintenance • North Plant').first);
      await tester.pumpAndSettle();

      // Switch to External tab and assign Primary External: K. Patel
      await tester.tap(find.byKey(const Key('recipient_type_external')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full Name *'),
        'K. Patel',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email Address *'),
        'k.patel@safecontractors.demo',
      );
      await tester.pumpAndSettle();

      // Turn on Email Reminder & add Reminder 2
      final enableSwitch = find.byType(Switch).first;
      await tester.ensureVisible(enableSwitch);
      await tester.tap(enableSwitch);
      await tester.pumpAndSettle();

      final addAnotherBtn = find.text('+ Add Another Reminder');
      await tester.ensureVisible(addAnotherBtn);
      await tester.tap(addAnotherBtn);
      await tester.pumpAndSettle();

      // Check R. Kumar in both Reminder 1 (index 0) and Reminder 2 (index 2)
      final allCheckboxes = find.byType(Checkbox);
      await tester.tap(allCheckboxes.at(0));
      await tester.pumpAndSettle();
      await tester.tap(allCheckboxes.at(2));
      await tester.pumpAndSettle();

      // Switch back to Internal tab to remove R. Kumar from Assignment
      await tester.tap(find.byKey(const Key('recipient_type_internal')));
      await tester.pumpAndSettle();

      final removeButtons = find.byTooltip('Remove');
      expect(removeButtons, findsWidgets);
      await tester.tap(removeButtons.first);
      await tester.pumpAndSettle();

      // R. Kumar is removed from all reminders, only K. Patel remains (1 checkbox per reminder = 2 total)
      expect(find.byType(Checkbox), findsNWidgets(2));
      expect(find.text('K. Patel'), findsWidgets);
    },
  );

  testWidgets(
    'Rule 7: Reminder dates must not allow a date after the Action Close Date',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(home: AddActionScreen(actionId: 'AC-101')),
      );
      await tester.pumpAndSettle();

      // Fill in Action Title
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Action Title *'),
        'Fix Valve',
      );

      // Pick Target Date
      final targetDatePicker = find.widgetWithText(
        InkWell,
        'Target / Due Date *',
      );
      await tester.ensureVisible(targetDatePicker);
      await tester.tap(targetDatePicker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Assign R. Kumar
      final internalSearch = find.widgetWithText(
        TextFormField,
        'Search by name, email, or phone...',
      );
      await tester.enterText(internalSearch, 'Kumar');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maintenance • North Plant').first);
      await tester.pumpAndSettle();

      // Pick Follow-Up Date
      final followUpDatePicker = find.widgetWithText(InkWell, 'Follow-Up Date');
      await tester.ensureVisible(followUpDatePicker);
      await tester.tap(followUpDatePicker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Turn on Email Reminder
      final enableSwitch = find.byType(Switch).first;
      await tester.ensureVisible(enableSwitch);
      await tester.tap(enableSwitch);
      await tester.pumpAndSettle();

      // Open Edit Reminder Dialog
      final editReminderBtn = find.byTooltip('Edit Reminder');
      await tester.ensureVisible(editReminderBtn);
      await tester.tap(editReminderBtn);
      await tester.pumpAndSettle();

      expect(find.text('Edit Reminder 1'), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Rule 8: If the action is closed, pending reminders become inactive (isEnabled: false) on save',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      ActionRecord? savedRecord;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  final record = await Navigator.push<ActionRecord>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AddActionScreen(actionId: 'AC-101'),
                    ),
                  );
                  savedRecord = record;
                },
                child: const Text('Launch Add Action'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Launch screen
      await tester.tap(find.text('Launch Add Action'));
      await tester.pumpAndSettle();

      // Fill in Action Title
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Action Title *'),
        'Inspect Rig',
      );

      // Pick Target Date
      final targetDateBtn = find.widgetWithText(InkWell, 'Target / Due Date *');
      await tester.ensureVisible(targetDateBtn);
      await tester.tap(targetDateBtn);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Assign R. Kumar
      final internalSearch = find.widgetWithText(
        TextFormField,
        'Search by name, email, or phone...',
      );
      await tester.enterText(internalSearch, 'Kumar');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maintenance • North Plant').first);
      await tester.pumpAndSettle();

      // Set Status to 'Closed'
      final statusDropdown = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Status',
      );
      await tester.ensureVisible(statusDropdown);
      await tester.tap(statusDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Closed').last);
      await tester.pumpAndSettle();

      // Turn on Email Reminder
      final enableSwitch = find.byType(Switch).first;
      await tester.ensureVisible(enableSwitch);
      await tester.tap(enableSwitch);
      await tester.pumpAndSettle();

      // Check R. Kumar as recipient
      final reminderCheckboxes = find.byType(Checkbox);
      await tester.ensureVisible(reminderCheckboxes.first);
      await tester.tap(reminderCheckboxes.first);
      await tester.pumpAndSettle();

      // Tap Send Action
      final sendBtn = find.text('Send Action');
      await tester.ensureVisible(sendBtn);
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      // Verify the returned record is closed and its reminders are inactive (isEnabled: false)
      expect(savedRecord, isNotNull);
      expect(savedRecord!.status, equals('Closed'));
      expect(savedRecord!.emailReminders.isNotEmpty, isTrue);
      expect(savedRecord!.emailReminders.first.isEnabled, isFalse);
    },
  );

  testWidgets(
    'AddActionScreen Email Reminder has no layout overflow on mobile and narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 5000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(home: AddActionScreen(actionId: 'AC-101')),
      );
      await tester.pumpAndSettle();

      // Assign Primary Internal Person: R. Kumar
      final internalSearch = find.widgetWithText(
        TextFormField,
        'Search by name, email, or phone...',
      );
      await tester.enterText(internalSearch, 'Kumar');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maintenance • North Plant').first);
      await tester.pumpAndSettle();

      // Turn ON Email Reminder
      final emailReminderSwitch = find.byType(Switch).first;
      await tester.ensureVisible(emailReminderSwitch);
      await tester.tap(emailReminderSwitch);
      await tester.pumpAndSettle();

      // Verify no RenderFlex overflow
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'AddActionScreen header back button has proper key, tooltip, contrast, and handles onClose',
    (tester) async {
      bool closedCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          home: AddActionScreen(
            actionId: 'AC-101',
            onClose: () => closedCalled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final backBtnFinder = find.byKey(const Key('add_action_back_button'));
      expect(backBtnFinder, findsOneWidget);

      final iconBtn = tester.widget<IconButton>(backBtnFinder);
      expect(iconBtn.tooltip, equals('Back'));

      final iconWidget = tester.widget<Icon>(find.descendant(
        of: backBtnFinder,
        matching: find.byType(Icon),
      ));
      expect(iconWidget.color, isNotNull);
      expect(iconWidget.color, isNot(equals(Colors.white)));

      await tester.tap(backBtnFinder);
      await tester.pumpAndSettle();

      expect(closedCalled, isTrue);
    },
  );

  testWidgets(
    'Closed action immutability: Saving changes on a closed action displays security compliance warning and blocks modification',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final closedAction = ActionRecord(
        id: 'AC-CLOSED-01',
        subject: 'Closed Action for Immutability Test',
        actionRequired: 'Verify closed action immutability.',
        division: 'Operations',
        status: 'Closed',
        priority: 'High',
        percentComplete: 100,
        closeDate: '01 Jan 2026',
        assignedTo: 'Suresh Engineer',
        assignedToId: '00000000-0000-0000-0000-000000000001',
      );

      bool saveCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: AddActionScreen(
            actionId: closedAction.id,
            existingAction: closedAction,
            onSaved: (_) => saveCalled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final saveBtn = find.text('SAVE CHANGES');
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Closed actions are locked for audit compliance'),
        findsOneWidget,
      );
      expect(saveCalled, isFalse);
    },
  );

  testWidgets(
    'Attachment upload lifecycle: Rejects file exceeding 10 MB limit with clear SnackBar message',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        AppFilePicker.testOverride = null;
      });

      // Inject a mock file of 11 MB (> 10 MB)
      AppFilePicker.testOverride = ({required allowedExtensions}) async {
        return AppPickedFile(
          name: 'Heavy_Scan.pdf',
          bytes: Uint8List(0),
          size: 11 * 1024 * 1024,
        );
      };

      await tester.pumpWidget(
        const MaterialApp(home: AddActionScreen(actionId: 'AC-101')),
      );
      await tester.pumpAndSettle();

      final uploadBox = find.byKey(const Key('add_action_upload_evidence_box'));
      expect(uploadBox, findsOneWidget);
      await tester.ensureVisible(uploadBox);
      await tester.tap(uploadBox);
      await tester.pumpAndSettle();

      expect(find.textContaining('File size exceeds 10 MB limit'), findsOneWidget);
      expect(find.text('Heavy_Scan.pdf'), findsNothing);
    },
  );

  testWidgets(
    'Attachment upload lifecycle: Valid file adds to list with formatted size and can be removed',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        AppFilePicker.testOverride = null;
      });

      // Inject a valid 2.5 MB file
      AppFilePicker.testOverride = ({required allowedExtensions}) async {
        return AppPickedFile(
          name: 'Safety_Audit.pdf',
          bytes: Uint8List(100),
          size: (2.5 * 1024 * 1024).round(),
        );
      };

      await tester.pumpWidget(
        const MaterialApp(home: AddActionScreen(actionId: 'AC-101')),
      );
      await tester.pumpAndSettle();

      final uploadBox = find.byKey(const Key('add_action_upload_evidence_box'));
      await tester.ensureVisible(uploadBox);
      await tester.tap(uploadBox);
      await tester.pumpAndSettle();

      expect(find.textContaining('Safety_Audit.pdf • 2.5 MB'), findsOneWidget);

      final removeBtn = find.byKey(const Key('remove_attachment_0_btn'));
      expect(removeBtn, findsOneWidget);
      await tester.tap(removeBtn);
      await tester.pumpAndSettle();

      expect(find.textContaining('Safety_Audit.pdf'), findsNothing);
    },
  );
}
