import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/screens/person_form_screen.dart';
import 'package:action_flow/features/users/screens/users_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'PersonFormScreen loads and edits external person without duplicating',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final store = MockPeopleStore.instance;
      final initialCount = store.people.length;

      // Find an existing external person in store
      final externalPerson = store.people.firstWhere(
        (p) => p.type == PersonType.externalWorker,
      );

      Person? resultPerson;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  resultPerson = await Navigator.push<Person>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PersonFormScreen(person: externalPerson),
                    ),
                  );
                  if (resultPerson != null) {
                    store.update(resultPerson!);
                  }
                },
                child: const Text('Open Edit'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap button to open form
      await tester.tap(find.text('Open Edit'));
      await tester.pumpAndSettle();

      // Verify Title is Edit Person
      expect(find.text('Edit Person'), findsOneWidget);

      // Verify existing details loaded
      expect(find.text(externalPerson.name), findsOneWidget);
      expect(find.text(externalPerson.email), findsOneWidget);
      expect(find.text(externalPerson.company), findsOneWidget);

      // Edit Name
      await tester.enterText(
        find.widgetWithText(TextFormField, externalPerson.name),
        'Updated External Name',
      );
      await tester.pumpAndSettle();

      // Edit Company
      await tester.enterText(
        find.widgetWithText(TextFormField, externalPerson.company),
        'Updated Contractor Org',
      );
      await tester.pumpAndSettle();

      // Save changes
      await tester.tap(find.text('SAVE PERSON'));
      await tester.pumpAndSettle();

      // Verify returned person has updated details and preserved ID
      expect(resultPerson, isNotNull);
      expect(resultPerson!.id, externalPerson.id);
      expect(resultPerson!.name, 'Updated External Name');
      expect(resultPerson!.company, 'Updated Contractor Org');
      expect(resultPerson!.type, PersonType.externalWorker);

      // Verify store count unchanged (no duplication)
      expect(store.people.length, initialCount);

      // Verify store record was updated in-place
      final updatedInStore = store.people.firstWhere(
        (p) => p.id == externalPerson.id,
      );
      expect(updatedInStore.name, 'Updated External Name');
      expect(updatedInStore.company, 'Updated Contractor Org');
    },
  );

  testWidgets('UsersScreen renders people directory and details view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const MaterialApp(home: UsersScreen()));
    await tester.pumpAndSettle();

    expect(find.text('People / Workers Directory'), findsOneWidget);
    expect(find.text('Add Person'), findsWidgets);
    expect(find.text('All Departments'), findsOneWidget);
    expect(find.text('All Sites'), findsOneWidget);
  });

  testWidgets(
    'UsersScreen filters people by Department, Site, and Combined filters',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const MaterialApp(home: UsersScreen()));
      await tester.pumpAndSettle();

      // Initially all people are visible
      expect(find.text('M. Ali'), findsOneWidget);
      expect(find.text('R. Kumar'), findsOneWidget);
      expect(find.text('S. Jones'), findsOneWidget);

      // Filter by Department: HSE
      await tester.tap(find.text('All Departments'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HSE').last);
      await tester.pumpAndSettle();

      // Only HSE people visible (M. Ali and T. Reed)
      expect(find.text('M. Ali'), findsOneWidget);
      expect(find.text('T. Reed'), findsOneWidget);
      expect(find.text('R. Kumar'), findsNothing);
      expect(find.text('S. Jones'), findsNothing);

      // Reset Department back to All Departments
      await tester.tap(find.text('HSE'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Departments').last);
      await tester.pumpAndSettle();

      // Filter by Site: Warehouse B
      await tester.tap(find.text('All Sites'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Warehouse B').last);
      await tester.pumpAndSettle();

      // Only Warehouse B people visible (M. Ali)
      expect(find.text('M. Ali'), findsOneWidget);
      expect(find.text('R. Kumar'), findsNothing);
      expect(find.text('T. Reed'), findsNothing);

      // Now set Department to HSE while Site is Warehouse B
      await tester.tap(find.text('All Departments'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HSE').last);
      await tester.pumpAndSettle();

      // M. Ali matches both HSE + Warehouse B
      expect(find.text('M. Ali'), findsOneWidget);

      // Change Department to Maintenance while Site is Warehouse B -> No matches
      await tester.tap(find.text('HSE'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maintenance').last);
      await tester.pumpAndSettle();

      expect(find.text('M. Ali'), findsNothing);
      expect(find.text('R. Kumar'), findsNothing);
    },
  );

  testWidgets('UsersScreen combines Search with Department and Site filters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const MaterialApp(home: UsersScreen()));
    await tester.pumpAndSettle();

    // Filter by Department: HSE
    await tester.tap(find.text('All Departments'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HSE').last);
    await tester.pumpAndSettle();

    expect(find.text('M. Ali'), findsOneWidget);
    expect(find.text('T. Reed'), findsOneWidget);

    // Search for "Ali"
    await tester.enterText(find.byType(TextField).first, 'Ali');
    await tester.pumpAndSettle();

    expect(find.text('M. Ali'), findsOneWidget);
    expect(find.text('T. Reed'), findsNothing);

    // Search for "NonExistent"
    await tester.enterText(find.byType(TextField).first, 'NonExistent');
    await tester.pumpAndSettle();

    expect(find.text('M. Ali'), findsNothing);
    expect(find.text('T. Reed'), findsNothing);
  });

  testWidgets(
    'UsersScreen renders responsively on 400px mobile screen without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const MaterialApp(home: UsersScreen()));
      await tester.pumpAndSettle();

      expect(find.text('People / Workers Directory'), findsOneWidget);
      expect(find.text('All Departments'), findsOneWidget);
      expect(find.text('All Sites'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'PersonFormScreen detects exact email duplicate and allows using existing person',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final store = MockPeopleStore.instance;
      final existingKumar = store.people.firstWhere(
        (p) => p.email == 'r.kumar@actionflow.demo',
      );

      Person? resultPerson;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  resultPerson = await Navigator.push<Person>(
                    context,
                    MaterialPageRoute(builder: (_) => const PersonFormScreen()),
                  );
                },
                child: const Text('Open Add Person'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Add Person'));
      await tester.pumpAndSettle();

      // Enter details with existing email
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name *'),
        'New Worker Kumar',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email *'),
        'r.kumar@actionflow.demo',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Designation *'),
        'Technician',
      );

      // Select team
      await tester.tap(find.text('HSE').first);
      await tester.pumpAndSettle();

      // Tap Save Person in AppBar
      await tester.tap(find.text('SAVE PERSON'));
      await tester.pumpAndSettle();

      // Duplicate Dialog should appear
      expect(find.text('Person already exists'), findsOneWidget);
      expect(find.text(existingKumar.name), findsWidgets);
      expect(find.text('Use Existing Person'), findsOneWidget);

      // Tap Use Existing Person
      await tester.tap(find.text('Use Existing Person'));
      await tester.pumpAndSettle();

      expect(resultPerson, isNotNull);
      expect(resultPerson!.id, existingKumar.id);
      expect(resultPerson!.email, existingKumar.email);
    },
  );

  testWidgets(
    'PersonFormScreen detects normalized phone duplicate and prevents creating duplicate',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final store = MockPeopleStore.instance;
      final existingAli = store.people.firstWhere(
        (p) => p.email == 'm.ali@actionflow.demo',
      );

      Person? resultPerson;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  resultPerson = await Navigator.push<Person>(
                    context,
                    MaterialPageRoute(builder: (_) => const PersonFormScreen()),
                  );
                },
                child: const Text('Open Add Person'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Add Person'));
      await tester.pumpAndSettle();

      // Enter details with existing phone (+91 90000 10002 -> 90000 10002)
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name *'),
        'Ali Duplicate',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email *'),
        'unique.ali@actionflow.demo',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone'),
        '+91 90000 10002',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Designation *'),
        'Coordinator',
      );

      // Select team
      await tester.tap(find.text('HSE').first);
      await tester.pumpAndSettle();

      // Tap Save Person in AppBar
      await tester.tap(find.text('SAVE PERSON'));
      await tester.pumpAndSettle();

      // Duplicate Dialog should appear
      expect(find.text('Person already exists'), findsOneWidget);
      expect(find.text(existingAli.name), findsWidgets);

      // Dismiss duplicate dialog with Cancel / Edit
      await tester.tap(find.text('Cancel / Edit'));
      await tester.pumpAndSettle();

      expect(resultPerson, isNull);
    },
  );

  testWidgets(
    'PersonFormScreen allows same-name people when email and phone are distinct',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      Person? resultPerson;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  resultPerson = await Navigator.push<Person>(
                    context,
                    MaterialPageRoute(builder: (_) => const PersonFormScreen()),
                  );
                },
                child: const Text('Open Add Person'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Add Person'));
      await tester.pumpAndSettle();

      // Enter same name 'R. Kumar' but new unique email & phone
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name *'),
        'R. Kumar',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email *'),
        'r.kumar.new2@sobha.demo',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone'),
        '+91 98888 77777',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Designation *'),
        'Electrical Lead',
      );

      // Select team
      await tester.tap(find.text('Operations').first);
      await tester.pumpAndSettle();

      // Tap Save Person in AppBar
      await tester.tap(find.text('SAVE PERSON'));
      await tester.pumpAndSettle();

      // Dialog should not block, form pops with new person
      expect(find.text('Person already exists'), findsNothing);
      expect(resultPerson, isNotNull);
      expect(resultPerson!.name, 'R. Kumar');
      expect(resultPerson!.email, 'r.kumar.new2@sobha.demo');
    },
  );
}
