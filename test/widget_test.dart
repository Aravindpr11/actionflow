import 'package:action_flow/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'ActionFlow app launches to splash screen and transitions to login screen',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const ActionFlowApp());

      // Initially displays Splash Screen
      expect(find.text('ActionFlow'), findsOneWidget);
      expect(find.text('Streamline Actions • Track Progress'), findsOneWidget);

      // After splash elapses, transitions to Login Screen
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.text('ActionFlow'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
    },
  );
}
