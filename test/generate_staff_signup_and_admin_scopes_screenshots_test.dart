import 'dart:io';
import 'dart:ui' as ui;
import 'package:action_flow/features/auth/models/manager_scope_item.dart';
import 'package:action_flow/features/auth/screens/staff_account_setup_screen.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/models/team.dart';
import 'package:action_flow/features/users/screens/person_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const artifactDir = r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23';

  testWidgets('Generate Staff Signup Screen Screenshot', (tester) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const depts = [
      DepartmentOption(id: '00000000-0000-0000-0001-000000000001', name: 'HSE / Safety', code: 'HSE'),
      DepartmentOption(id: '00000000-0000-0000-0001-000000000002', name: 'Operations', code: 'OPS'),
      DepartmentOption(id: '00000000-0000-0000-0001-000000000003', name: 'Maintenance', code: 'MAINT'),
    ];
    const sites = [
      SiteOption(id: '00000000-0000-0000-0002-000000000001', name: 'Downtown Project', code: 'DTP'),
      SiteOption(id: '00000000-0000-0000-0002-000000000002', name: 'Marina Heights', code: 'MH'),
      SiteOption(id: '00000000-0000-0000-0002-000000000003', name: 'Platform Bravo', code: 'PB'),
    ];
    const teams = [
      TeamOption(
        id: '00000000-0000-0000-0003-000000000001',
        name: 'HSE Rapid Response',
        departmentId: '00000000-0000-0000-0001-000000000001',
      ),
    ];

    final repaintKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Inter',
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D9488)),
        ),
        home: RepaintBoundary(
          key: repaintKey,
          child: const StaffAccountSetupScreen(
            initialDepartments: depts,
            initialSites: sites,
            initialTeams: teams,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Fill form with single primary department and site
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full Name *'),
      'Marcus Aurelius',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email *'),
      'marcus.staff@sobha.local',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Phone (Optional)'),
      '+971 50 111 2233',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Designation *'),
      'Senior Safety Officer',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password *'),
      'StrongPassword123!',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm Password *'),
      'StrongPassword123!',
    );

    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final boundary = repaintKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final screenshotFile = File(
        '$artifactDir\\staff_signup_screen.png',
      );
      await screenshotFile.writeAsBytes(pngBytes);
    });

    final file = File('$artifactDir\\staff_signup_screen.png');
    expect(file.existsSync(), isTrue);
  });

  testWidgets('Generate Admin Manager Multi-Scope PersonFormScreen Screenshot', (tester) async {
    tester.view.physicalSize = const Size(1280, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final mockDepts = [
      {'id': 'dept-hse', 'name': 'HSE / Safety', 'is_active': true},
      {'id': 'dept-ops', 'name': 'Operations', 'is_active': true},
      {'id': 'dept-maint', 'name': 'Maintenance', 'is_active': true},
    ];
    final mockSites = [
      {'id': 'site-np', 'name': 'North Plant', 'is_active': true},
      {'id': 'site-pb', 'name': 'Platform Bravo', 'is_active': true},
      {'id': 'site-sp', 'name': 'South Plant', 'is_active': true},
    ];
    final mockTeams = [
      {'id': 'team-1', 'name': 'HSE Emergency Team', 'deptId': 'dept-hse', 'dept': 'HSE / Safety'},
      {'id': 'team-2', 'name': 'Ops Alpha', 'deptId': 'dept-ops', 'dept': 'Operations'},
    ];

    final managerPerson = Person(
      id: 'mgr-101',
      name: 'Elena Rostova',
      email: 'elena.rostova@sobha.local',
      phone: '+971 52 333 4455',
      designation: 'Operations Manager',
      type: PersonType.internalUser,
      isActive: true,
      role: UserRole.departmentManager,
      department: 'HSE / Safety',
      departmentId: 'dept-hse',
      site: 'North Plant',
      siteId: 'site-np',
      managerScopes: const [
        ManagerScopeItem(
          departmentId: 'dept-hse',
          departmentName: 'HSE / Safety',
          siteId: 'site-np',
          siteName: 'North Plant',
        ),
        ManagerScopeItem(
          departmentId: 'dept-ops',
          departmentName: 'Operations',
          siteId: 'site-pb',
          siteName: 'Platform Bravo',
        ),
      ],
      teamIds: const ['team-1', 'team-2'],
    );

    final repaintKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Inter',
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E3A8A)),
        ),
        home: RepaintBoundary(
          key: repaintKey,
          child: Scaffold(
            body: PersonFormScreen(
              person: managerPerson,
              availableDepartments: mockDepts,
              availableSites: mockSites,
              availableTeams: mockTeams,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final boundary = repaintKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final screenshotFile = File(
        '$artifactDir\\admin_manager_multiscope_form.png',
      );
      await screenshotFile.writeAsBytes(pngBytes);
    });

    final file = File('$artifactDir\\admin_manager_multiscope_form.png');
    expect(file.existsSync(), isTrue);
  });
}
