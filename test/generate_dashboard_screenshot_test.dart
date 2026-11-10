import 'dart:io';
import 'dart:ui' as ui;
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Capture Manager Dashboard Screenshot', (tester) async {
    tester.view.physicalSize = const Size(1440, 2100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final yesterdayStr = '${now.subtract(const Duration(days: 2)).year}-${now.subtract(const Duration(days: 2)).month.toString().padLeft(2, '0')}-${now.subtract(const Duration(days: 2)).day.toString().padLeft(2, '0')}';
    final tomorrowStr = '${now.add(const Duration(days: 2)).year}-${now.add(const Duration(days: 2)).month.toString().padLeft(2, '0')}-${now.add(const Duration(days: 2)).day.toString().padLeft(2, '0')}';

    final testActions = [
      ActionRecord(
        id: 'act-org-1',
        actionNumber: 'ACT-1107',
        subject: 'Organization-Wide Safety Protocol Rollout',
        actionRequired: 'Ensure all departments and sites implement new HSE standard',
        division: 'All Divisions',
        department: 'All Departments',
        site: 'All Sites / Locations',
        assignedTo: 'Enterprise Staff',
        priority: 'High',
        status: 'Open',
        percentComplete: 15,
        scopeType: 'organization',
        dateRaised: yesterdayStr,
        targetDate: tomorrowStr,
      ),
      ActionRecord(
        id: 'act-1',
        actionNumber: 'ACT-001',
        subject: 'Overdue Valve Inspection',
        actionRequired: 'Inspect and calibrate valve #4',
        division: 'Operations',
        department: 'Engineering',
        section: 'Mechanical',
        site: 'Site Alpha',
        assignedTo: 'John Engineer',
        priority: 'Critical',
        status: 'Open',
        percentComplete: 20,
        dateRaised: yesterdayStr,
        targetDate: yesterdayStr,
        nextFollowUpDate: todayStr,
        followUps: [
          ActionFollowUpRecord(
            id: 'fu-1',
            actionId: 'act-1',
            followUpDate: todayStr,
            notes: 'Followed up on mechanical spare parts arrival.',
            status: 'Scheduled',
          ),
        ],
      ),
      ActionRecord(
        id: 'act-2',
        actionNumber: 'ACT-002',
        subject: 'Electrical Panel Thermal Audit',
        actionRequired: 'Perform thermographic scan',
        division: 'Maintenance',
        department: 'Electrical',
        section: 'HV Power',
        site: 'Site Beta',
        assignedTo: 'Alice Spark',
        priority: 'High',
        status: 'In Progress',
        percentComplete: 60,
        dateRaised: yesterdayStr,
        targetDate: tomorrowStr,
        nextFollowUpDate: tomorrowStr,
        progressUpdates: [
          ActionProgressUpdate(
            id: 'pu-1',
            actionId: 'act-2',
            updatedById: 'user-spark',
            updatedByName: 'Alice Spark',
            updateDate: todayStr,
            progress: 60,
            status: 'In Progress',
            comments: 'Thermography scan 60% complete; switchgear normal.',
          ),
        ],
      ),
      ActionRecord(
        id: 'act-3',
        actionNumber: 'ACT-003',
        subject: 'Fire Extinguisher Monthly Inspection',
        actionRequired: 'Check pressure tags and replace expired cylinders',
        division: 'HSE',
        department: 'Safety',
        section: 'Fire Safety',
        site: 'Site Alpha',
        assignedTo: 'Bob Shield',
        priority: 'Medium',
        status: 'Pending Review',
        percentComplete: 100,
        dateRaised: yesterdayStr,
        targetDate: tomorrowStr,
        progressUpdates: [
          ActionProgressUpdate(
            id: 'pu-2',
            actionId: 'act-3',
            updatedById: 'user-shield',
            updatedByName: 'Bob Shield',
            updateDate: todayStr,
            progress: 100,
            status: 'Pending Review',
            comments: 'All 42 fire extinguishers inspected and tagged. Ready for manager sign-off.',
          ),
        ],
      ),
      ActionRecord(
        id: 'act-4',
        actionNumber: 'ACT-004',
        subject: 'Emergency Exit Sign Illumination Fix',
        actionRequired: 'Replace battery backup on block C exit door',
        division: 'Facilities',
        department: 'Civil',
        section: 'Building Maint',
        site: 'Site Gamma',
        assignedTo: 'Charlie Builder',
        priority: 'Low',
        status: 'Closed',
        percentComplete: 100,
        dateRaised: yesterdayStr,
        targetDate: yesterdayStr,
        closeDate: todayStr,
        closedByName: 'David Miller',
        closureComment: 'Verified log sheets completed accurately.',
      ),
      ActionRecord(
        id: 'act-5',
        actionNumber: 'ACT-005',
        subject: 'Emergency Lighting Battery Replacement',
        actionRequired: 'Replace backup battery packs on 2nd floor corridor',
        division: 'Maintenance',
        department: 'Facilities',
        section: 'Building Services',
        site: 'Site Alpha',
        assignedTo: 'David Spark',
        priority: 'High',
        status: 'In Progress',
        percentComplete: 40,
        dateRaised: yesterdayStr,
        targetDate: tomorrowStr,
        nextFollowUpDate: todayStr,
        followUps: [
          ActionFollowUpRecord(
            id: 'fu-2',
            actionId: 'act-5',
            followUpDate: todayStr,
            notes: 'Vendor delivered battery units this morning.',
            status: 'Pending',
          ),
        ],
      ),
    ];

    final testProfile = const UserProfile(
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

    final testContext = ManagerContext(
      authUserId: 'mgr-001',
      profile: testProfile,
      organizationId: 'sobha-org-id',
      organizationName: 'Sobha Constructions',
      scopes: const [],
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
            body: ManagerDashboardScreen(
              userProfile: testProfile,
              managerContext: testContext,
              initialActions: testActions,
              initialMyActions: testActions,
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
        r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23\manager_dashboard_screenshot.png',
      );
      await screenshotFile.writeAsBytes(pngBytes);
    });

    final file = File(r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23\manager_dashboard_screenshot.png');
    expect(file.existsSync(), isTrue);
  });
}
