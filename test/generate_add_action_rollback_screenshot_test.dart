import 'dart:io';
import 'dart:ui' as ui;
import 'package:action_flow/features/dashboard/manager_dashboard/screens/add_action_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Capture AddActionScreen Scoped Rollback Screenshot', (tester) async {
    tester.view.physicalSize = const Size(1440, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final repaintKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Inter',
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E3A8A)),
        ),
        builder: (context, child) => RepaintBoundary(
          key: repaintKey,
          child: child ?? const SizedBox(),
        ),
        home: const Scaffold(
          body: AddActionScreen(actionId: 'AC-102'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Section 2 shows single specific department and site fields
    expect(find.text('WHERE IT BELONGS'), findsOneWidget);
    expect(find.text('Department'), findsWidgets);
    expect(find.text('Location / Site'), findsWidgets);

    // Capture main Add Action screen
    await tester.runAsync(() async {
      final boundary = repaintKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final screenshotFile = File(
        r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23\add_action_scoped_rollback.png',
      );
      await screenshotFile.writeAsBytes(pngBytes);
    });

    final file = File(r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23\add_action_scoped_rollback.png');
    expect(file.existsSync(), isTrue);

    // Open Add New Internal Person dialog to also capture preserved additional internal assignee selector
    await tester.tap(find.text('Add New Internal Person'));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final boundary = repaintKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final screenshotFile = File(
        r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23\add_action_preserved_internal_dialog.png',
      );
      await screenshotFile.writeAsBytes(pngBytes);
    });

    final dialogFile = File(r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23\add_action_preserved_internal_dialog.png');
    expect(dialogFile.existsSync(), isTrue);
  });
}
