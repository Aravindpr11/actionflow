import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:action_flow/features/requests/models/request_models.dart';
import 'package:action_flow/features/requests/widgets/request_card_header.dart';
import 'package:action_flow/features/notifications/models/app_notification.dart';
import 'package:action_flow/features/notifications/widgets/quick_alert_toast.dart';
import 'package:action_flow/widgets/notifications/browser_notification_dialogs.dart';

void main() {
  const testUserId = 'user-001';
  final sampleRequest = RequestRecord(
    id: 'req-1004',
    displayId: 'REQ-1004',
    organizationId: 'org-001',
    title: 'Permit to Work and Confined Space Entry',
    description: 'Detailed inspection of storage vessel #4 with gas monitoring.',
    requestType: 'Permit to Work (PTW)',
    priority: 'Medium',
    requiredByDate: '2026-11-20',
    status: 'Pending',
    departmentId: 'dept-01',
    departmentName: 'Sobha Infra',
    siteId: 'site-01',
    siteName: 'Sobha Infra',
    createdBy: testUserId,
    createdByName: 'Reni Thomas',
    createdByRole: 'Manager',
    createdAt: DateTime.now(),
    approvers: const [
      RequestApproverRecord(
        id: 'appr-01',
        requestId: 'req-1004',
        approverId: testUserId,
        approverName: 'Reni Thomas',
        approverRole: 'Manager',
        stepOrder: 1,
        status: 'pending',
      ),
    ],
  );

  group('RequestCardHeader Responsive Behavior Across Viewports', () {
    final viewports = [
      320.0,
      360.0,
      375.0,
      393.0,
      414.0,
      430.0,
      600.0,
      768.0,
      950.0,
      1024.0,
      1280.0,
      1440.0,
      1920.0,
    ];

    for (final width in viewports) {
      testWidgets('Renders cleanly without overflow at width $width (showDecisionNeeded = true)', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RequestCardHeader(
                          request: sampleRequest,
                          showDecisionNeeded: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'RequestCardHeader overflowed at width $width');
        expect(find.text('REQ-1004'), findsOneWidget);
        expect(find.text('Permit to Work (PTW)'), findsOneWidget);
        expect(find.text('Medium'), findsOneWidget);
        expect(find.text('Your Decision Needed'), findsOneWidget);
        expect(find.text('Pending'), findsOneWidget);

        if (width >= 580) {
          expect(find.byType(Row), findsWidgets);
        } else {
          expect(find.byType(Wrap), findsOneWidget);
        }
      });

      testWidgets('Renders cleanly without overflow at width $width (showDecisionNeeded = false)', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RequestCardHeader(
                          request: sampleRequest,
                          showDecisionNeeded: false,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('REQ-1004'), findsOneWidget);
        expect(find.text('Your Decision Needed'), findsNothing);
        expect(find.text('Pending'), findsOneWidget);
      });
    }

    testWidgets('Extremely long request type does not overflow at 320px viewport', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;

      final longTypeRequest = sampleRequest.copyWith(
        requestType: 'Complex Environmental & Hazardous Waste Disposal Authorization Permit',
      );

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RequestCardHeader(
                        request: longTypeRequest,
                        showDecisionNeeded: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'Long request type overflowed at 320px');
    });
  });

  group('Dialog Responsive Constraint Verification', () {
    testWidgets('BrowserNotificationDialog adapts to narrow 320px and 360px mobile viewports', (tester) async {
      for (final w in [320.0, 360.0, 393.0]) {
        tester.view.physicalSize = Size(w, 800);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => BrowserNotificationDialogs.showBlockedInstructions(context),
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Permission blocked dialog overflowed at $w');
        expect(find.text('Browser Notifications Blocked'), findsOneWidget);

        await tester.tap(find.text('Got it, Close'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('QuickAlertToast renders within screen boundaries at 320px and 393px without overflow', (tester) async {
      for (final w in [320.0, 360.0, 375.0, 393.0, 1024.0]) {
        tester.view.physicalSize = Size(w, 800);
        tester.view.devicePixelRatio = 1.0;

        final notif = AppNotification(
          id: 'notif-001',
          userId: testUserId,
          title: 'Action Item Assigned',
          message: 'You have been assigned to inspection ACT-1004.',
          eventType: 'action_assigned',
          createdAt: DateTime.now(),
        );

        OverlayEntry? toastEntry;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    toastEntry = QuickAlertToast.show(context, notification: notif);
                  },
                  child: const Text('Show Toast'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Toast'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'QuickAlertToast overflowed at width $w');
        expect(find.text('Action Item Assigned'), findsOneWidget);

        final toastFinder = find.byType(QuickAlertToast);
        final toastSize = tester.getSize(toastFinder);
        expect(toastSize.width, lessThanOrEqualTo(math.min(380.0, w)));

        toastEntry?.remove();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Generic ConstrainedBox dialog pattern test at 320px viewport', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: ctx,
                    builder: (dCtx) => AlertDialog(
                      title: const Text('Confirm Action'),
                      content: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Are you sure you want to proceed with this operation?'),
                            SizedBox(height: 12),
                            Text('This action will apply immediately across the workspace.'),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Confirm')),
                      ],
                    ),
                  );
                },
                child: const Text('Open Constrained Dialog'),
              ),
            ),
          ),
        ),
      );

        await tester.tap(find.text('Open Constrained Dialog'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Confirm Action'), findsOneWidget);

        final dialogFinder = find.byType(AlertDialog);
        final dialogSize = tester.getSize(dialogFinder);
        expect(dialogSize.width, lessThanOrEqualTo(320.0));

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      });
  });
}
