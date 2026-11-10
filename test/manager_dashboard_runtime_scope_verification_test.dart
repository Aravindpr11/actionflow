import 'dart:io';
import 'dart:ui' as ui;
import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  setUpAll(() {
    HttpOverrides.global = _RealHttpOverrides();
  });

  testWidgets('Manager Dashboard loads live actions from local Supabase without scope_type error', (tester) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // 1. Create live SupabaseClient targeting local Docker Supabase
    final client = SupabaseClient(
      SupabaseConfig.localProjectUrl,
      SupabaseConfig.localAnonKey,
    );
    ActionService.instance.clientOverride = client;
    addTearDown(() {
      client.auth.stopAutoRefresh();
      ActionService.instance.clientOverride = null;
      client.dispose();
    });

    // 2. Sign in as webonant@gmail.com and fetch actions using ActionService
    final liveActions = await tester.runAsync(() async {
      await client.auth.signInWithPassword(
        email: 'webonant@gmail.com',
        password: 'Password123!',
      );
      client.auth.stopAutoRefresh();

      final actions = await ActionService.instance.fetchManagerActions(
        organizationId: '00000000-0000-0000-0000-000000000001',
      );
      return actions;
    });

    expect(liveActions, isNotNull);
    expect(liveActions!.isNotEmpty, isTrue);

    // Verify scope_type column is successfully parsed without 42703 error
    final orgWideAction = liveActions.firstWhere((a) => a.actionNumber == 'ACT-1107');
    expect(orgWideAction.scopeType, 'organization');
    expect(orgWideAction.isOrganizationWide, isTrue);

    final specificAction = liveActions.firstWhere((a) => a.actionNumber == 'ACT-1106');
    expect(specificAction.scopeType, 'specific');
    expect(specificAction.isSpecificScope, isTrue);

    final currentUser = client.auth.currentUser!;
    final testProfile = UserProfile(
      id: currentUser.id,
      name: 'Webonant Manager',
      email: 'webonant@gmail.com',
      phone: '+971 50 123 4567',
      designation: 'Operations Lead',
      department: 'Operations',
      site: 'Site Alpha',
      organizationName: 'Sobha Constructions',
      organizationId: '00000000-0000-0000-0000-000000000001',
      role: 'manager',
    );

    final managerContext = ManagerContext(
      authUserId: currentUser.id,
      profile: testProfile,
      organizationId: '00000000-0000-0000-0000-000000000001',
      organizationName: 'Sobha Constructions',
      scopes: const [],
    );

    final repaintKey = GlobalKey();

    // 3. Mount ManagerDashboardScreen with live loaded actions
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
              managerContext: managerContext,
              initialActions: liveActions,
              initialMyActions: liveActions,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 4. Assert NO missing scope_type error and actions are rendered
    expect(find.textContaining('Unable to load actions'), findsNothing);
    expect(find.textContaining('scope_type does not exist'), findsNothing);
    expect(find.textContaining('Test Org-Wide Action'), findsOneWidget);
    expect(find.textContaining('Test Manager Scope Action'), findsOneWidget);

    // 5. Capture live screenshot of Manager Dashboard & Action Register
    await tester.runAsync(() async {
      final boundary = repaintKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final screenshotFile = File(
        r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23\manager_dashboard_live_loaded.png',
      );
      await screenshotFile.writeAsBytes(pngBytes);
    });

    final file = File(r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23\manager_dashboard_live_loaded.png');
    expect(file.existsSync(), isTrue);

    // 6. Switch to Action Register and verify table loads with org-wide and specific actions
    final actionRegisterNav = find.text('Action Register');
    if (actionRegisterNav.evaluate().isNotEmpty) {
      await tester.tap(actionRegisterNav.first);
      await tester.pumpAndSettle();

      expect(find.textContaining('Unable to load actions'), findsNothing);
      expect(find.textContaining('ACT-1107'), findsOneWidget);
      expect(find.textContaining('ACT-1106'), findsOneWidget);

      await tester.runAsync(() async {
        final boundary = repaintKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        final pngBytes = byteData!.buffer.asUint8List();

        final screenshotFile = File(
          r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23\manager_action_register_live_loaded.png',
        );
        await screenshotFile.writeAsBytes(pngBytes);
      });

      final regFile = File(r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23\manager_action_register_live_loaded.png');
      expect(regFile.existsSync(), isTrue);
    }
  });
}
