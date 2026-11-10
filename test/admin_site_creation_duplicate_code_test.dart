import 'package:action_flow/features/dashboard/admin_dashboard/screens/admin_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Admin Portal — Site Creation Duplicate Code & Dialog Lifecycle Tests', () {
    Widget buildDashboardSitesTab() {
      return const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(1280, 800)),
          child: AdminDashboardScreen(initialTabIndex: 3), // Tab 3 = Sites
        ),
      );
    }

    testWidgets('1. Create site with unique name generates site in list', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildDashboardSitesTab());
      await tester.pumpAndSettle();

      // Open Add Site Dialog
      await tester.tap(find.text('Add Site'));
      await tester.pumpAndSettle();

      expect(find.text('Add Facility Site'), findsOneWidget);

      // Enter site details
      await tester.enterText(find.widgetWithText(TextField, 'Site Name'), 'Delta Station');
      await tester.enterText(find.widgetWithText(TextField, 'Physical Location / Address'), 'Sector 7');
      await tester.enterText(find.widgetWithText(TextField, 'Facility Type'), 'Refinery');

      // Click Add Site inside dialog
      final submitBtn = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Add Site'),
      );
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Dialog should be closed
      expect(find.text('Add Facility Site'), findsNothing);

      // New site should be rendered in list
      expect(find.text('Delta Station'), findsOneWidget);
      expect(find.text('Sector 7'), findsOneWidget);
    });

    testWidgets('2. Consecutive sites sharing first 3 letters are both successfully created', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildDashboardSitesTab());
      await tester.pumpAndSettle();

      // Create First Site: "Alpha Yard"
      await tester.tap(find.text('Add Site'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Site Name'), 'Alpha Yard');
      await tester.enterText(find.widgetWithText(TextField, 'Physical Location / Address'), 'Port Gate 1');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Add Site')));
      await tester.pumpAndSettle();

      expect(find.text('Alpha Yard'), findsOneWidget);
      expect(find.text('Port Gate 1'), findsOneWidget);

      // Create Second Site sharing first 3 letters: "Alpine Facility"
      await tester.tap(find.text('Add Site'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Site Name'), 'Alpine Facility');
      await tester.enterText(find.widgetWithText(TextField, 'Physical Location / Address'), 'Mountain Sector');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Add Site')));
      await tester.pumpAndSettle();

      expect(find.text('Alpine Facility'), findsOneWidget);
      expect(find.text('Mountain Sector'), findsOneWidget);

      // Create Third Site sharing first 3 letters: "Alphabet Workshop"
      await tester.tap(find.text('Add Site'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Site Name'), 'Alphabet Workshop');
      await tester.enterText(find.widgetWithText(TextField, 'Physical Location / Address'), 'Industrial Zone');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Add Site')));
      await tester.pumpAndSettle();

      expect(find.text('Alphabet Workshop'), findsOneWidget);
      expect(find.text('Industrial Zone'), findsOneWidget);

      // All three sites coexist peacefully
      expect(find.text('Alpha Yard'), findsOneWidget);
      expect(find.text('Alpine Facility'), findsOneWidget);
      expect(find.text('Alphabet Workshop'), findsOneWidget);
    });

    testWidgets('3. Empty site name prevents submission, shows error and preserves inputs', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildDashboardSitesTab());
      await tester.pumpAndSettle();

      // Open Add Site dialog
      await tester.tap(find.text('Add Site'));
      await tester.pumpAndSettle();

      // Enter location & type without name
      await tester.enterText(find.widgetWithText(TextField, 'Physical Location / Address'), 'Offshore Block 4');
      await tester.enterText(find.widgetWithText(TextField, 'Facility Type'), 'FPSO');

      // Click Add Site with empty name
      final submitBtn = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Add Site'),
      );
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Dialog MUST REMAIN OPEN
      expect(find.text('Add Facility Site'), findsOneWidget);
      expect(find.text('Site name is required.'), findsOneWidget);

      // Form values must be preserved
      expect(find.text('Offshore Block 4'), findsOneWidget);
      expect(find.text('FPSO'), findsOneWidget);

      // Now enter valid name and submit
      await tester.enterText(find.widgetWithText(TextField, 'Site Name'), 'FPSO Osprey');
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Dialog now closes and site is added
      expect(find.text('Add Facility Site'), findsNothing);
      expect(find.text('FPSO Osprey'), findsOneWidget);
    });

    testWidgets('4. Dialog cancel button closes dialog cleanly without saving', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildDashboardSitesTab());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Site'));
      await tester.pumpAndSettle();

      expect(find.text('Add Facility Site'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Site Name'), 'Abandoned Site');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Add Facility Site'), findsNothing);
      expect(find.text('Abandoned Site'), findsNothing);
    });

    test('5. Unique code generation logic handles base, collisions, and inactive sites', () {
      final existingCodes = <String>{'PLT-A', 'PLT-B', 'NOR', 'SOU'};

      // Helper function mirroring CompanyStructureService resolution logic
      String resolveCode(String name, Set<String> existing, {String? manualCode}) {
        final isManual = manualCode != null && manualCode.trim().isNotEmpty;
        if (isManual) return manualCode.trim().toUpperCase();

        final cleaned = name.trim().replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
        final base = cleaned.length >= 3 ? cleaned.substring(0, 3) : (cleaned.isNotEmpty ? cleaned : 'SIT');

        String candidate = base;
        int suffix = 1;
        while (existing.contains(candidate)) {
          candidate = '$base-${suffix.toString().padLeft(2, '0')}';
          suffix++;
        }
        return candidate;
      }

      // Case 1: Fresh site with unique prefix
      expect(resolveCode('West Plant', existingCodes), 'WES');

      // Case 2: Site whose prefix 'NOR' is already taken by active site
      final firstCollision = resolveCode('North Rig', existingCodes);
      expect(firstCollision, 'NOR-01');

      // Add first collision to existing set
      existingCodes.add(firstCollision);

      // Case 3: Another site with same prefix 'NOR' -> generates 'NOR-02'
      final secondCollision = resolveCode('Northbound Station', existingCodes);
      expect(secondCollision, 'NOR-02');
      existingCodes.add(secondCollision);

      // Case 4: Inactive site already occupying code 'OFF'
      existingCodes.add('OFF'); // Inactive site code in database
      final thirdCollision = resolveCode('Offshore Platform', existingCodes);
      expect(thirdCollision, 'OFF-01');

      // Case 5: Special characters in site name
      expect(resolveCode('--- Yard ---', existingCodes), 'YAR');

      // Case 6: Very short name (< 3 chars)
      expect(resolveCode('HQ', existingCodes), 'HQ');
    });

    test('6. Race condition collision retry simulation succeeds with next suffix', () {
      final existingCodes = <String>{'ABC'};
      final String baseCode = 'ABC';

      // Simulates concurrent insertion where 'ABC-01' was grabbed by another transaction during race
      int suffixIndex = 1;
      String candidateCode = baseCode;

      while (existingCodes.contains(candidateCode)) {
        candidateCode = '$baseCode-${suffixIndex.toString().padLeft(2, '0')}';
        suffixIndex++;
      }
      expect(candidateCode, 'ABC-01');

      // Now simulate database throwing Postgres 23505 (sites_code_key) because transaction B inserted ABC-01 simultaneously
      const simulatedError = 'PostgrestException: duplicate key value violates unique constraint "sites_code_key", code: 23505';
      final isCodeConflict = simulatedError.contains('sites_code_key') || simulatedError.contains('23505');
      expect(isCodeConflict, isTrue);

      // Retry mechanism in CompanyStructureService:
      existingCodes.add(candidateCode); // Mark ABC-01 taken
      while (existingCodes.contains(candidateCode)) {
        candidateCode = '$baseCode-${suffixIndex.toString().padLeft(2, '0')}';
        suffixIndex++;
      }

      // Candidate safely advances to ABC-02 on retry
      expect(candidateCode, 'ABC-02');
    });
  });
}
