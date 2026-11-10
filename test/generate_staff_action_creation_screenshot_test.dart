import 'dart:io';
import 'dart:ui' as ui;

import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/add_action_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/models/team.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const staffUserId = '9a78ceaa-cc3d-47a2-b1d3-e41d5e90a868';
  const staffUserName = 'Staff Alice';
  const staffEmail = 'alice@alpha.com';
  const staffDept = 'HSE Department';
  const staffDeptId = 'd7372e89-b1a7-4fe1-9e3b-c4daae804198';
  const staffSite = 'Site Alpha';
  const staffSiteId = '046686d0-33a0-4764-bcc0-2e439c7dfd36';

  final staffUserProfile = UserProfile(
    id: staffUserId,
    name: staffUserName,
    email: staffEmail,
    phone: '+91 90000 10001',
    designation: 'Safety Officer',
    department: staffDept,
    departmentId: staffDeptId,
    site: staffSite,
    siteId: staffSiteId,
    role: 'Staff',
    accountStatus: 'Active',
    permissions: const ['Staff Actions'],
  );

  setUp(() {
    MockPeopleStore.instance.people.removeWhere((p) => p.id.startsWith('AFU-TEST-MGR'));
    MockPeopleStore.instance.people.add(
      Person(
        id: 'AFU-TEST-MGR-001',
        name: 'Manager Bob',
        email: 'mgr.bob@alpha.com',
        phone: '+91 98765 43210',
        designation: 'HSE Department Manager',
        type: PersonType.internalUser,
        isActive: true,
        role: UserRole.departmentManager,
        department: staffDept,
        departmentId: staffDeptId,
        site: staffSite,
        siteId: staffSiteId,
      ),
    );
  });

  testWidgets('Capture Staff Add Action Form Screenshot', (tester) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final authProfile = AuthProfileData(
      userProfile: staffUserProfile,
      roleCode: 'staff',
      status: 'active',
      isActive: true,
      isPrimaryAdmin: false,
    );
    AuthService.instance.setProfileDataForTesting(authProfile);
    addTearDown(() {
      AuthService.instance.setProfileDataForTesting(null);
    });

    final repaintKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E3A8A)),
        ),
        home: RepaintBoundary(
          key: repaintKey,
          child: const Scaffold(
            body: AddActionScreen(
              actionId: 'ACT-2026-STAFF-01',
              isManager: false,
              isStaff: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Fill subject and required fields
    final subjectFinder = find.widgetWithText(TextFormField, 'Action Subject *');
    if (subjectFinder.evaluate().isNotEmpty) {
      await tester.enterText(subjectFinder, 'Corrective Guard Installation on Conveyor #2');
    }
    final reqFinder = find.widgetWithText(TextFormField, 'Action Description');
    if (reqFinder.evaluate().isNotEmpty) {
      await tester.enterText(reqFinder, 'Fabricate and secure safety mesh cover before machine restart.');
    }
    await tester.pumpAndSettle();

    // Capture screenshot
    await tester.runAsync(() async {
      final boundary = repaintKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final screenshotFile = File(
        r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23\staff_add_action_form.png',
      );
      await screenshotFile.writeAsBytes(pngBytes);
    });

    final file = File(r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23\staff_add_action_form.png');
    expect(file.existsSync(), isTrue);
  });

  testWidgets('Capture Staff Action Register Screenshot', (tester) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final authProfile = AuthProfileData(
      userProfile: staffUserProfile,
      roleCode: 'staff',
      status: 'active',
      isActive: true,
      isPrimaryAdmin: false,
    );
    AuthService.instance.setProfileDataForTesting(authProfile);
    addTearDown(() {
      AuthService.instance.setProfileDataForTesting(null);
    });

    final repaintKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E3A8A)),
        ),
        home: RepaintBoundary(
          key: repaintKey,
          child: Scaffold(
            body: WorkerDashboardScreen(
              userProfile: staffUserProfile,
              initialNavIndex: 1, // Action Register
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Capture screenshot
    await tester.runAsync(() async {
      final boundary = repaintKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final screenshotFile = File(
        r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23\staff_action_register.png',
      );
      await screenshotFile.writeAsBytes(pngBytes);
    });

    final file = File(r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23\staff_action_register.png');
    expect(file.existsSync(), isTrue);
  });
}
