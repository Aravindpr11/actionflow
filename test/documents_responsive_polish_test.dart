import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/models/document_record.dart';

void main() {
  const artifactDir = r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23';

  final testProfile = UserProfile(
    id: 'usr-mgr-test',
    email: 'manager@actionflow.com',
    name: 'Safety Manager',
    phone: '+971 50 123 4567',
    designation: 'HSE Manager',
    department: 'HSE',
    site: 'North Yard',
    role: 'manager',
    organizationId: 'SOBHA-001',
    organizationName: 'Sobha Constructions',
  );

  final testActions = [
    ActionRecord(
      id: 'ACT-1001',
      actionNumber: 'ACT-1001',
      subject: 'Review Lifting Operations Plan',
      assignedTo: 'Safety Manager',
      division: 'Operations',
      actionRequired: 'Inspect site crane permits',
      priority: 'High',
      targetDate: '2026-12-01',
      status: 'In Progress',
      percentComplete: 60,
    ),
  ];

  Future<void> saveScreenshot(WidgetTester tester, GlobalKey key, String filename) async {
    await tester.runAsync(() async {
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      final image = await boundary?.toImage(pixelRatio: 1.0);
      final byteData = await image?.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final file = File('$artifactDir\\$filename');
      await file.writeAsBytes(byteData.buffer.asUint8List());
    });
  }

  group('Documents Section Responsive Polish Verification (320px–1280px)', () {
    final viewports = <double, String>{
      320.0: 'Small Mobile (320px - iPhone SE 1st Gen)',
      360.0: 'Compact Android (360px)',
      393.0: 'Standard Mobile (393px - iPhone 16 / 15 Pro)',
      414.0: 'Large Mobile (414px - iPhone 11 / Plus)',
      768.0: 'Tablet Portrait (768px - iPad Mini)',
      1280.0: 'Desktop (1280px)',
    };

    for (final entry in viewports.entries) {
      final width = entry.key;
      final label = entry.value;

      testWidgets('Documents Section renders cleanly at $label with ZERO overflow', (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final key = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.light(),
            home: RepaintBoundary(
              key: key,
              child: Scaffold(
                body: ManagerDashboardScreen(
                  userProfile: testProfile,
                  initialActions: testActions,
                  initialNavIndex: 7, // Open directly to Documents Portal
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // 1. Verify zero RenderFlex overflows occurred
        expect(tester.takeException(), isNull);

        // 2. Verify heading is present
        expect(find.text('Safety Documents & Guidelines'), findsOneWidget);

        // 3. Verify controls are present
        expect(find.byKey(const Key('documents_upload_button')), findsOneWidget);
        expect(find.byTooltip('Refresh Documents'), findsOneWidget);

        // 4. Verify document category chips are all accessible
        expect(find.text('All'), findsOneWidget);
        for (final cat in DocumentCategory.all) {
          expect(find.widgetWithText(ChoiceChip, cat), findsOneWidget);
        }

        // Capture screenshot at 393px and 1280px
        if (width == 393.0) {
          await saveScreenshot(tester, key, 'screen_documents_393.png');
        } else if (width == 1280.0) {
          await saveScreenshot(tester, key, 'screen_documents_1280.png');
        }
      });
    }
  });
}
