import 'dart:io';
import 'dart:ui' as ui;
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/platform_admin_dashboard/screens/platform_admin_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/external_update/models/external_action_payload.dart';
import 'package:action_flow/features/external_update/screens/external_action_update_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final String artifactDir = Directory(r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23').existsSync()
      ? r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23'
      : Directory.systemTemp.path;

  final testActions = [
    ActionRecord(
      id: 'act-001',
      actionNumber: 'ACT-1001',
      subject: 'Critical Scaffolding Inspection',
      actionRequired: 'Inspect and tag scaffolding on Block B, 4th floor.',
      division: 'Construction',
      department: 'HSE',
      section: 'Safety',
      site: 'Site Alpha',
      assignedTo: 'Arun Kumar',
      priority: 'High',
      status: 'Open',
      percentComplete: 30,
      scopeType: 'department',
      dateRaised: '2026-11-10',
      targetDate: '2026-11-20',
    ),
    ActionRecord(
      id: 'act-002',
      actionNumber: 'ACT-1002',
      subject: 'Fire Extinguisher Recertification',
      actionRequired: 'Replace tags and test discharge pressure.',
      division: 'Operations',
      department: 'Safety',
      section: 'Fire Safety',
      site: 'Site Beta',
      assignedTo: 'Niyas Ali',
      priority: 'Medium',
      status: 'In Progress',
      percentComplete: 70,
      scopeType: 'department',
      dateRaised: '2026-11-12',
      targetDate: '2026-11-22',
    ),
  ];

  final managerProfile = const UserProfile(
    id: 'mgr-001',
    name: 'David Miller',
    email: 'david.miller@sobha.com',
    phone: '+971 50 123 4567',
    designation: 'Operations Lead',
    organizationName: 'Sobha Constructions',
    department: 'Operations',
    site: 'Site Alpha',
    role: 'manager',
  );

  final workerProfile = const UserProfile(
    id: 'wrk-001',
    name: 'Arun Kumar',
    email: 'arun.kumar@sobha.com',
    phone: '+971 50 987 6543',
    designation: 'Safety Inspector',
    organizationName: 'Sobha Constructions',
    department: 'HSE',
    site: 'Site Alpha',
    role: 'staff',
  );

  final managerContext = ManagerContext(
    authUserId: 'mgr-001',
    profile: managerProfile,
    organizationId: Organization.sobhaId,
    organizationName: 'Sobha Constructions',
    scopes: const [],
  );

  final testExternalPayload = ExternalActionPayload(
    actionId: 'act-ext-001',
    actionNumber: 'ACT-9001',
    title: 'HVAC Ducting Fire Damper Installation',
    description: 'Install motorized fire dampers in main corridor supply ductwork.',
    actionRequired: 'Mount dampers, wire actuator to fire alarm panel, and test trip function.',
    category: 'Mechanical',
    priority: 'High',
    status: 'In Progress',
    percentComplete: 60,
    dateRaised: '2026-11-10',
    startDate: '2026-11-11',
    targetDate: '2026-11-25',
    dueDate: '2026-11-25',
    nextFollowUpDate: '2026-11-18',
    department: 'Mechanical',
    site: 'Tower 3, Level 14',
    organizationName: 'Sobha Constructions',
    isClosed: false,
    recentHistory: const [],
    subTasks: const [],
    recipientId: 'rec-001',
    recipientName: 'Vikram Patel',
    recipientEmail: 'vikram@coolaircontractors.com',
    companyName: 'CoolAir HVAC Solutions LLC',
    phone: '+971 55 432 1098',
    expiresAt: DateTime.now().add(const Duration(days: 7)),
    accessCount: 3,
  );

  Future<void> captureScreen(
    WidgetTester tester,
    Widget screen,
    double width,
    double height,
    String filename,
  ) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
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
            body: screen,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final boundary = repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final file = File('$artifactDir\\$filename');
      await file.writeAsBytes(byteData.buffer.asUint8List());
    });
  }

  tearDown(() {
    AuthService.instance.setProfileDataForTesting(null);
  });

  group('Priority Screens Screenshot Suite (393px, 768px, 1280px)', () {
    testWidgets('1. Manager Dashboard at 393px, 768px, 1280px', (tester) async {
      final screen = ManagerDashboardScreen(
        userProfile: managerProfile,
        managerContext: managerContext,
        initialActions: testActions,
        initialMyActions: testActions,
      );

      await captureScreen(tester, screen, 393, 852, 'screen_manager_dashboard_393.png');
      await captureScreen(tester, screen, 768, 1024, 'screen_manager_dashboard_tablet.png');
      await captureScreen(tester, screen, 1280, 900, 'screen_manager_dashboard_desktop.png');

      expect(File('$artifactDir\\screen_manager_dashboard_393.png').existsSync(), isTrue);
      expect(File('$artifactDir\\screen_manager_dashboard_tablet.png').existsSync(), isTrue);
      expect(File('$artifactDir\\screen_manager_dashboard_desktop.png').existsSync(), isTrue);
    });

    testWidgets('2. Worker Dashboard at 393px, 768px, 1280px', (tester) async {
      final screen = WorkerDashboardScreen(
        userProfile: workerProfile,
        initialActions: testActions,
      );

      await captureScreen(tester, screen, 393, 852, 'screen_worker_dashboard_393.png');
      await captureScreen(tester, screen, 768, 1024, 'screen_worker_dashboard_tablet.png');
      await captureScreen(tester, screen, 1280, 900, 'screen_worker_dashboard_desktop.png');

      expect(File('$artifactDir\\screen_worker_dashboard_393.png').existsSync(), isTrue);
      expect(File('$artifactDir\\screen_worker_dashboard_tablet.png').existsSync(), isTrue);
      expect(File('$artifactDir\\screen_worker_dashboard_desktop.png').existsSync(), isTrue);
    });

    testWidgets('3. Platform Admin Dashboard at 393px, 768px, 1280px', (tester) async {
      AuthService.instance.setProfileDataForTesting(
        const AuthProfileData(
          userProfile: UserProfile(
            id: 'plat-admin-001',
            email: 'platform.admin@actionflow.cc',
            name: 'Platform Administrator',
            phone: '+971 50 000 0000',
            designation: 'Platform Administrator',
            department: 'Platform Operations',
            site: 'HQ',
            role: 'admin',
          ),
          roleCode: 'admin',
          status: 'active',
          isActive: true,
          isPrimaryAdmin: true,
          isPlatformAdmin: true,
        ),
      );

      const screen = PlatformAdminDashboardScreen(
        overrideName: 'Platform Administrator',
        overrideEmail: 'platform.admin@actionflow.cc',
      );

      await captureScreen(tester, screen, 393, 852, 'screen_platform_admin_dashboard_393.png');
      await captureScreen(tester, screen, 768, 1024, 'screen_platform_admin_dashboard_tablet.png');
      await captureScreen(tester, screen, 1280, 900, 'screen_platform_admin_dashboard_desktop.png');

      expect(File('$artifactDir\\screen_platform_admin_dashboard_393.png').existsSync(), isTrue);
      expect(File('$artifactDir\\screen_platform_admin_dashboard_tablet.png').existsSync(), isTrue);
      expect(File('$artifactDir\\screen_platform_admin_dashboard_desktop.png').existsSync(), isTrue);
    });

    testWidgets('4. External Action Update at 393px, 768px, 1280px', (tester) async {
      final screen = ExternalActionUpdateScreen(
        token: 'test-external-token-hash',
        initialPayload: testExternalPayload,
      );

      await captureScreen(tester, screen, 393, 852, 'screen_external_action_update_393.png');
      await captureScreen(tester, screen, 768, 1024, 'screen_external_action_update_tablet.png');
      await captureScreen(tester, screen, 1280, 900, 'screen_external_action_update_desktop.png');

      expect(File('$artifactDir\\screen_external_action_update_393.png').existsSync(), isTrue);
      expect(File('$artifactDir\\screen_external_action_update_tablet.png').existsSync(), isTrue);
      expect(File('$artifactDir\\screen_external_action_update_desktop.png').existsSync(), isTrue);
    });
  });
}
