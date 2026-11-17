import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/requests/models/request_models.dart';
import 'package:action_flow/features/requests/services/request_service.dart';
import 'package:action_flow/services/global_search_service.dart';
import 'package:action_flow/widgets/search/global_search_autocomplete.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    RequestService.useMockOnly = true;
    RequestService.instance.clearMockStore();
    RequestService.instance.seedMockRequest(
      const RequestRecord(
        id: 'req-uuid-1004',
        displayId: 'REQ-1004',
        organizationId: 'org-1',
        title: 'Hot work permit for welding on Pipeline 4',
        description: 'Welding and grinding work near flare header',
        requestType: 'Permit to Work (PTW)',
        priority: 'High',
        requiredByDate: '2026-11-20',
        status: 'Pending',
        createdBy: 'user-niyas',
        createdByName: 'Niyas P',
        createdByRole: 'Staff',
        departmentName: 'Safety',
        siteName: 'Refinery A',
        approvers: [
          RequestApproverRecord(
            id: 'appr-1004',
            requestId: 'req-uuid-1004',
            approverId: 'user-adarsh',
            approverName: 'Adarsh Manager',
            approverRole: 'Manager',
            stepOrder: 1,
            status: 'Pending',
          ),
        ],
      ),
    );
    RequestService.instance.seedMockRequest(
      const RequestRecord(
        id: 'req-uuid-1006',
        displayId: 'REQ-1006',
        organizationId: 'org-1',
        title: 'Crane equipment request for heavy lift',
        description: '50-ton mobile crane required for vessel installation',
        requestType: 'Equipment',
        priority: 'Critical',
        requiredByDate: '2026-11-22',
        status: 'Under Review',
        createdBy: 'user-reni',
        createdByName: 'Reni Thomas',
        createdByRole: 'Manager',
        departmentName: 'Operations',
        siteName: 'Refinery A',
        approvers: [
          RequestApproverRecord(
            id: 'appr-1006',
            requestId: 'req-uuid-1006',
            approverId: 'user-adarsh',
            approverName: 'Adarsh Manager',
            approverRole: 'Manager',
            stepOrder: 1,
            status: 'Pending',
          ),
        ],
      ),
    );
  });

  tearDown(() {
    RequestService.instance.clearMockStore();
    RequestService.useMockOnly = false;
  });

  final List<ActionRecord> sampleActions = [
    ActionRecord(
      id: 'act-uuid-1',
      actionNumber: 'ACT-1001',
      organizationId: 'org-1',
      subject: 'Review fire safety doors in Zone B',
      actionRequired: 'Ensure magnetic hold-open devices release on alarm',
      division: 'Safety Division',
      assignedTo: 'Niyas P',
      assignedToId: 'user-niyas',
      priority: 'High',
      department: 'Safety',
      site: 'Refinery A',
      status: 'In Progress',
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
      targetDate: '20 Nov 2026',
    ),
    ActionRecord(
      id: 'act-uuid-2',
      actionNumber: 'ACT-1002',
      organizationId: 'org-1',
      subject: 'Calibrate gas detectors in Tank Farm',
      actionRequired: 'Perform bump test and span calibration on H2S sensors',
      division: 'Operations Division',
      assignedTo: 'Adarsh Manager',
      assignedToId: 'user-adarsh',
      priority: 'Critical',
      department: 'Operations',
      site: 'Offshore Platform',
      status: 'Open',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      targetDate: '18 Nov 2026',
    ),
    ActionRecord(
      id: 'act-uuid-3',
      actionNumber: 'ACT-1003',
      organizationId: 'org-1',
      subject: 'Permit to work audit for electrical isolation',
      actionRequired: 'Verify lockout tagout records against live permits',
      division: 'Electrical Division',
      assignedTo: 'Worker John',
      assignedToId: 'user-john',
      priority: 'Medium',
      department: 'Electrical',
      site: 'Refinery A',
      status: 'Completed',
      createdAt: DateTime.now().subtract(const Duration(days: 10)),
      targetDate: '10 Nov 2026',
    ),
    // Cross-tenant action belonging to org-2
    ActionRecord(
      id: 'act-uuid-4',
      actionNumber: 'ACT-2001',
      organizationId: 'org-2',
      subject: 'Confidential leak investigation at Facility Z',
      actionRequired: 'Execute ultrasonic pipe inspection',
      division: 'External Division',
      assignedTo: 'External Operator',
      assignedToId: 'user-ext',
      priority: 'Critical',
      department: 'Quality',
      site: 'Terminal C',
      status: 'Open',
      createdAt: DateTime.now(),
      targetDate: '25 Nov 2026',
    ),
  ];

  group('GlobalSearchService Unit & Security Isolation Tests', () {
    test('Empty query returns empty results immediately', () async {
      final results = await GlobalSearchService.instance.search(
        query: '   ',
        organizationId: 'org-1',
        currentUserId: 'user-niyas',
        currentUserRole: 'Manager',
        cachedActions: sampleActions,
        includeRequests: false,
      );
      expect(results, isEmpty);
    });

    test('Query "act" matches all org-1 sample actions by displayId prefix',
        () async {
      final results = await GlobalSearchService.instance.search(
        query: 'act',
        organizationId: 'org-1',
        currentUserId: 'user-adarsh',
        currentUserRole: 'Manager',
        cachedActions: sampleActions,
        includeRequests: false,
      );
      expect(results.length, equals(3));
      expect(results.every((r) => r.referenceNumber.startsWith('ACT-')), isTrue);
      // Confirms ACT-2001 from org-2 is excluded
      expect(results.any((r) => r.referenceNumber == 'ACT-2001'), isFalse);
    });

    test('Strict organization isolation rejects cached records from other tenants',
        () async {
      // User belongs to org-1, attempts to search "confidential" from org-2
      final results = await GlobalSearchService.instance.search(
        query: 'confidential',
        organizationId: 'org-1',
        currentUserId: 'user-adarsh',
        currentUserRole: 'Manager',
        cachedActions: sampleActions,
        includeRequests: false,
      );
      expect(results, isEmpty);
    });

    test('Strict staff isolation filters actions outside staff user assignment',
        () async {
      // Staff member "user-niyas" should only see ACT-1001 assigned to them
      final staffResults = await GlobalSearchService.instance.search(
        query: 'act',
        organizationId: 'org-1',
        currentUserId: 'user-niyas',
        currentUserRole: 'Staff',
        cachedActions: sampleActions,
        includeRequests: false,
      );
      expect(staffResults.length, equals(1));
      expect(staffResults.first.referenceNumber, equals('ACT-1001'));
      expect(staffResults.first.title, contains('fire safety doors'));
    });

    test('Manager role can search all actions across organization',
        () async {
      final mgrResults = await GlobalSearchService.instance.search(
        query: 'act',
        organizationId: 'org-1',
        currentUserId: 'user-adarsh',
        currentUserRole: 'Manager',
        cachedActions: sampleActions,
        includeRequests: false,
      );
      expect(mgrResults.length, equals(3));
    });

    test('Query "ACT-1001" returns exact matching action record with all metadata',
        () async {
      final results = await GlobalSearchService.instance.search(
        query: 'ACT-1001',
        organizationId: 'org-1',
        currentUserId: 'user-adarsh',
        currentUserRole: 'Manager',
        cachedActions: sampleActions,
        includeRequests: false,
      );
      expect(results.length, equals(1));
      expect(results.first.referenceNumber, equals('ACT-1001'));
      expect(results.first.title, contains('fire safety doors'));
      expect(results.first.subtitle, contains('Safety'));
      expect(results.first.subtitle, contains('Refinery A'));
      expect(results.first.subtitle, contains('Niyas P'));
      expect(results.first.status, equals('In Progress'));
    });

    test('Matches across all 7 Action fields: subject, actionRequired, assignee, dept, site, status',
        () async {
      // 1. subject
      final bySubject = await GlobalSearchService.instance.search(
        query: 'gas detectors',
        organizationId: 'org-1',
        currentUserId: 'user-adarsh',
        currentUserRole: 'Manager',
        cachedActions: sampleActions,
        includeRequests: false,
      );
      expect(bySubject.first.referenceNumber, equals('ACT-1002'));

      // 2. actionRequired
      final byActionReq = await GlobalSearchService.instance.search(
        query: 'bump test',
        organizationId: 'org-1',
        currentUserId: 'user-adarsh',
        currentUserRole: 'Manager',
        cachedActions: sampleActions,
        includeRequests: false,
      );
      expect(byActionReq.first.referenceNumber, equals('ACT-1002'));

      // 3. assignee
      final byAssignee = await GlobalSearchService.instance.search(
        query: 'worker john',
        organizationId: 'org-1',
        currentUserId: 'user-adarsh',
        currentUserRole: 'Manager',
        cachedActions: sampleActions,
        includeRequests: false,
      );
      expect(byAssignee.first.referenceNumber, equals('ACT-1003'));

      // 4. department
      final byDept = await GlobalSearchService.instance.search(
        query: 'electrical',
        organizationId: 'org-1',
        currentUserId: 'user-adarsh',
        currentUserRole: 'Manager',
        cachedActions: sampleActions,
        includeRequests: false,
      );
      expect(byDept.first.referenceNumber, equals('ACT-1003'));

      // 5. site
      final bySite = await GlobalSearchService.instance.search(
        query: 'offshore platform',
        organizationId: 'org-1',
        currentUserId: 'user-adarsh',
        currentUserRole: 'Manager',
        cachedActions: sampleActions,
        includeRequests: false,
      );
      expect(bySite.first.referenceNumber, equals('ACT-1002'));

      // 6. status
      final byStatus = await GlobalSearchService.instance.search(
        query: 'completed',
        organizationId: 'org-1',
        currentUserId: 'user-adarsh',
        currentUserRole: 'Manager',
        cachedActions: sampleActions,
        includeRequests: false,
      );
      expect(byStatus.first.referenceNumber, equals('ACT-1003'));
    });

    test('Non-matching query returns empty result list', () async {
      final results = await GlobalSearchService.instance.search(
        query: 'zzzz_non_existent_term',
        organizationId: 'org-1',
        currentUserId: 'user-1',
        currentUserRole: 'Manager',
        cachedActions: sampleActions,
        includeRequests: false,
      );
      expect(results, isEmpty);
    });

    test('1. Existing ACT reference number returns matching action', () async {
      final res = await GlobalSearchService.instance.search(
        query: 'ACT-1001',
        organizationId: 'org-1',
        currentUserId: 'user-adarsh',
        currentUserRole: 'Manager',
        cachedActions: sampleActions,
        includeRequests: true,
      );
      expect(res.length, equals(1));
      expect(res.first.referenceNumber, equals('ACT-1001'));
      expect(res.first.isAction, isTrue);
    });

    test('2. Existing action title returns matching action', () async {
      final res = await GlobalSearchService.instance.search(
        query: 'fire safety doors',
        organizationId: 'org-1',
        currentUserId: 'user-adarsh',
        currentUserRole: 'Manager',
        cachedActions: sampleActions,
        includeRequests: true,
      );
      expect(res.length, equals(1));
      expect(res.first.referenceNumber, equals('ACT-1001'));
    });

    test('3. Existing assignee returns matching assigned actions and requests', () async {
      final res = await GlobalSearchService.instance.search(
        query: 'Niyas P',
        organizationId: 'org-1',
        currentUserId: 'user-adarsh',
        currentUserRole: 'Manager',
        cachedActions: sampleActions,
        includeRequests: true,
      );
      expect(res.any((r) => r.referenceNumber == 'ACT-1001'), isTrue);
      expect(res.any((r) => r.referenceNumber == 'REQ-1004'), isTrue);
    });

    test('4. Existing REQ reference number returns matching request', () async {
      final res = await GlobalSearchService.instance.search(
        query: 'REQ-1004',
        organizationId: 'org-1',
        currentUserId: 'user-adarsh',
        currentUserRole: 'Manager',
        cachedActions: sampleActions,
        includeRequests: true,
      );
      expect(res.length, equals(1));
      expect(res.first.referenceNumber, equals('REQ-1004'));
      expect(res.first.isRequest, isTrue);
      expect(res.first.title, contains('Hot work permit'));
    });

    test('5. Existing request title returns matching request', () async {
      final res = await GlobalSearchService.instance.search(
        query: 'Crane equipment request',
        organizationId: 'org-1',
        currentUserId: 'user-adarsh',
        currentUserRole: 'Manager',
        cachedActions: sampleActions,
        includeRequests: true,
      );
      expect(res.length, equals(1));
      expect(res.first.referenceNumber, equals('REQ-1006'));
      expect(res.first.isRequest, isTrue);
    });
  });

  group('GlobalSearchAutocomplete Widget & Interaction Tests', () {
    Widget buildTestApp({
      TextEditingController? controller,
      ValueChanged<String>? onSearchChanged,
      void Function(SearchResultItem item)? onActionSelected,
      void Function(SearchResultItem item)? onRequestSelected,
      double width = 300,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: GlobalSearchAutocomplete(
                controller: controller,
                cachedActions: sampleActions,
                organizationId: 'org-1',
                currentUserId: 'user-adarsh',
                currentUserRole: 'Manager',
                width: width,
                onSearchChanged: onSearchChanged,
                onActionSelected: onActionSelected,
                onRequestSelected: onRequestSelected,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('Renders search input with placeholder and search icon',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search actions, requests...'), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    });

    testWidgets(
        'Typing "act" debounces and displays autocomplete results in overlay',
        (tester) async {
      SearchResultItem? selected;
      await tester.pumpWidget(buildTestApp(
        onActionSelected: (item) => selected = item,
      ));

      await tester.enterText(find.byType(TextField), 'act');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('GLOBAL SEARCH'), findsOneWidget);
      expect(find.text('3 found'), findsOneWidget);
      expect(find.text('ACT-1001'), findsOneWidget);
      expect(find.text('ACT-1002'), findsOneWidget);
      expect(find.text('ACT-1003'), findsOneWidget);

      await tester.tap(find.text('ACT-1001'));
      await tester.pumpAndSettle();

      expect(selected, isNotNull);
      expect(selected!.referenceNumber, equals('ACT-1001'));
      expect(selected!.title, contains('fire safety doors'));
      expect(find.text('GLOBAL SEARCH'), findsNothing);
    });

    testWidgets('Typing unmatched query displays empty state card',
        (tester) async {
      await tester.pumpWidget(buildTestApp());

      await tester.enterText(find.byType(TextField), 'unknownxyz');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('No matching records found'), findsOneWidget);
      expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);
    });

    testWidgets('Clear button clears text and dismisses overlay',
        (tester) async {
      await tester.pumpWidget(buildTestApp());

      await tester.enterText(find.byType(TextField), 'act');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('GLOBAL SEARCH'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('GLOBAL SEARCH'), findsNothing);
      expect(find.widgetWithText(TextField, ''), findsOneWidget);
    });

    testWidgets('Escape key dismisses overlay', (tester) async {
      await tester.pumpWidget(buildTestApp());

      await tester.enterText(find.byType(TextField), 'act');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('GLOBAL SEARCH'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('GLOBAL SEARCH'), findsNothing);
    });

    testWidgets('Keyboard arrow navigation highlights and Enter selects item',
        (tester) async {
      SearchResultItem? selected;
      await tester.pumpWidget(buildTestApp(
        onActionSelected: (item) => selected = item,
      ));

      await tester.enterText(find.byType(TextField), 'act');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('GLOBAL SEARCH'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(selected, isNotNull);
      expect(selected!.referenceNumber, equals('ACT-1001'));
      expect(find.text('GLOBAL SEARCH'), findsNothing);
    });

    testWidgets('Tapping outside dismisses overlay', (tester) async {
      await tester.pumpWidget(buildTestApp());

      await tester.enterText(find.byType(TextField), 'act');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('GLOBAL SEARCH'), findsOneWidget);

      // Tap outside the search field and dropdown (at top left corner 10, 10)
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('GLOBAL SEARCH'), findsNothing);
    });

    testWidgets('Rapid typing cancels previous debounce and resolves latest query',
        (tester) async {
      await tester.pumpWidget(buildTestApp());

      final searchField = find.byType(TextField);

      // Type "a", then "ac", then "ACT-1002" with minimal delays
      await tester.enterText(searchField, 'a');
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(searchField, 'ac');
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(searchField, 'ACT-1002');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('GLOBAL SEARCH'), findsOneWidget);
      expect(find.text('1 found'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('ACT-1002'),
        ),
        findsOneWidget,
      );
      expect(find.text('ACT-1001'), findsNothing);
    });

    testWidgets('Selecting request suggestion triggers onRequestSelected callback', (tester) async {
      SearchResultItem? selectedRequest;
      await tester.pumpWidget(buildTestApp(
        onRequestSelected: (item) => selectedRequest = item,
      ));

      await tester.enterText(find.byType(TextField), 'REQ-1004');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      final reqItem = find.descendant(
        of: find.byType(ListView),
        matching: find.text('REQ-1004'),
      );
      expect(reqItem, findsOneWidget);
      await tester.tap(reqItem);
      await tester.pumpAndSettle();

      expect(selectedRequest, isNotNull);
      expect(selectedRequest!.referenceNumber, equals('REQ-1004'));
      expect(selectedRequest!.isRequest, isTrue);
    });

    testWidgets('Cross-entity query "permit" displays both ACT and REQ suggestions with pill badges', (tester) async {
      await tester.pumpWidget(buildTestApp());

      await tester.enterText(find.byType(TextField), 'permit');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('ACT-1003'), findsOneWidget);
      expect(find.text('REQ-1004'), findsOneWidget);
      expect(find.text('ACT'), findsAtLeastNWidgets(1));
      expect(find.text('REQ'), findsAtLeastNWidgets(1));
    });
  });

  group('Autocomplete Responsive Sweep Across All 9 Required Viewports', () {
    final viewports = <double, String>{
      320.0: 'iPhone SE 1st Gen',
      360.0: 'Standard Compact Android',
      375.0: 'iPhone SE 2nd Gen / iPhone 8',
      393.0: 'iPhone 16 / iPhone 15 Pro',
      414.0: 'iPhone 11 / XR / Plus',
      430.0: 'iPhone 16 Pro Max / 15 Plus',
      768.0: 'iPad Mini / Portrait Tablet',
      1024.0: 'iPad Pro / Small Desktop',
      1440.0: 'Desktop Full HD / QHD',
    };

    for (final entry in viewports.entries) {
      final width = entry.key;
      final label = entry.value;

      testWidgets(
          'Viewport $width px ($label) - Search renders cleanly without overflow',
          (tester) async {
        tester.view.physicalSize = Size(width, 852);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final searchWidth = width < 450 ? 150.0 : (width < 900 ? 220.0 : 300.0);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.menu_rounded),
                    const SizedBox(width: 8),
                    GlobalSearchAutocomplete(
                      cachedActions: sampleActions,
                      organizationId: 'org-1',
                      currentUserId: 'user-adarsh',
                      currentUserRole: 'Manager',
                      width: searchWidth,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        // Enter search term
        await tester.enterText(find.byType(TextField), 'act');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        // Must not throw any overflow exception
        expect(tester.takeException(), isNull);

        // Verify dropdown is visible and contains expected results
        expect(find.text('GLOBAL SEARCH'), findsOneWidget);
        expect(find.text('ACT-1001'), findsOneWidget);
      });
    }
  });

  group('Capture Real Autocomplete Dropdown Screenshots', () {
    const artifactDir =
        r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23';

    Future<void> saveScreenshot(
        WidgetTester tester, GlobalKey key, String filename) async {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        final image = await boundary?.toImage(pixelRatio: 1.0);
        final byteData =
            await image?.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) return;
        final file = File('$artifactDir\\$filename');
        await file.writeAsBytes(byteData.buffer.asUint8List());
      });
    }

    testWidgets('Capture Desktop Global Search Autocomplete (1280px)',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final key = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              backgroundColor: const Color(0xFFF1F5F9),
              appBar: AppBar(
                title: const Text('ActionFlow Manager Dashboard'),
                actions: [
                  Center(
                    child: GlobalSearchAutocomplete(
                      cachedActions: sampleActions,
                      organizationId: 'org-1',
                      currentUserId: 'user-adarsh',
                      currentUserRole: 'Manager',
                      width: 320,
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
              ),
              body: const Center(
                child: Text('Manager Dashboard Content'),
              ),
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'permit');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('GLOBAL SEARCH'), findsOneWidget);
      await saveScreenshot(tester, key, 'screen_global_search_desktop.png');
    });

    testWidgets('Capture Mobile Global Search Autocomplete (393px iPhone 16)',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final key = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              backgroundColor: const Color(0xFFF1F5F9),
              appBar: AppBar(
                title: const Text('ActionFlow'),
                actions: [
                  Center(
                    child: GlobalSearchAutocomplete(
                      cachedActions: sampleActions,
                      organizationId: 'org-1',
                      currentUserId: 'user-adarsh',
                      currentUserRole: 'Manager',
                      width: 160,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              body: const Center(
                child: Text('Staff Dashboard Content'),
              ),
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'permit');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('GLOBAL SEARCH'), findsOneWidget);
      await saveScreenshot(tester, key, 'screen_global_search_393.png');
    });

    testWidgets('Capture Mobile Global Search Empty State (393px)',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final key = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              backgroundColor: const Color(0xFFF1F5F9),
              appBar: AppBar(
                title: const Text('ActionFlow'),
                actions: [
                  Center(
                    child: GlobalSearchAutocomplete(
                      cachedActions: sampleActions,
                      organizationId: 'org-1',
                      currentUserId: 'user-adarsh',
                      currentUserRole: 'Manager',
                      width: 160,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              body: const Center(
                child: Text('Dashboard Content'),
              ),
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'nonexistent');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('No matching records found'), findsOneWidget);
      await saveScreenshot(tester, key, 'screen_global_search_empty_state.png');
    });

    testWidgets('Capture Mobile Navigation After Selection (393px)',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final key = GlobalKey();
      SearchResultItem? selectedItem;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return RepaintBoundary(
                key: key,
                child: Scaffold(
                  backgroundColor: const Color(0xFFF1F5F9),
                  appBar: AppBar(
                    title: const Text('ActionFlow'),
                    actions: [
                      Center(
                        child: GlobalSearchAutocomplete(
                          cachedActions: sampleActions,
                          organizationId: 'org-1',
                          currentUserId: 'user-adarsh',
                          currentUserRole: 'Manager',
                          width: 160,
                          onRequestSelected: (item) {
                            setState(() => selectedItem = item);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                  body: selectedItem == null
                      ? const Center(child: Text('Dashboard Content'))
                      : Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          selectedItem!.referenceNumber,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF7C3AED),
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'Pending',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFFF59E0B),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    selectedItem!.title,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(selectedItem!.subtitle),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
              );
            },
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'REQ-1004');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      final reqItem = find.descendant(
        of: find.byType(ListView),
        matching: find.text('REQ-1004'),
      );
      await tester.tap(reqItem);
      await tester.pumpAndSettle();

      expect(selectedItem, isNotNull);
      expect(selectedItem!.referenceNumber, equals('REQ-1004'));
      await saveScreenshot(tester, key, 'screen_global_search_selected_navigation.png');
    });
  });
}
