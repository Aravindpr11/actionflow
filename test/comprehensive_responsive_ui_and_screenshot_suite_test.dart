import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:action_flow/features/auth/screens/login_screen.dart';
import 'package:action_flow/features/calendar/widgets/calendar_view.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/add_action_screen.dart';
import 'package:action_flow/features/notifications/models/app_notification.dart';
import 'package:action_flow/features/notifications/widgets/notification_centre_view.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/features/reports/screens/reports_screen.dart';
import 'package:action_flow/features/requests/models/request_models.dart';
import 'package:action_flow/features/requests/screens/my_requests_screen.dart';
import 'package:action_flow/features/requests/screens/new_request_screen.dart';
import 'package:action_flow/features/requests/screens/request_approval_screen.dart';
import 'package:action_flow/features/requests/screens/request_details_screen.dart';
import 'package:action_flow/features/requests/services/request_service.dart';
import 'package:action_flow/features/requests/widgets/forward_request_dialog.dart';
import 'package:action_flow/features/requests/widgets/request_filter_bar.dart';
import 'package:action_flow/features/users/data/mock_people_store.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:action_flow/features/users/models/team.dart';
import 'package:action_flow/services/notification_service.dart';

void main() {
  const artifactDir = r'C:\Users\aravi\.gemini\antigravity\brain\157d46af-d639-42a1-a30f-5e6c77727b23';
  const orgId = Organization.sobhaId;
  const testUserId = '7b3f384d-75ed-4201-9670-932950fb16b6'; // Reni Thomas
  const testUserName = 'Reni Thomas';
  const testUserEmail = 'renialavelil@gmail.com';

  final testUserProfile = UserProfile(
    id: testUserId,
    name: testUserName,
    email: testUserEmail,
    phone: '+91 98765 43210',
    designation: 'HSE Manager',
    department: 'Sobha Infra',
    departmentId: 'cc1c49b7-4d9a-4e94-be5b-0ddd89790d6b',
    site: 'Sobha Infra',
    siteId: 'b751354b-f0f8-4a49-9488-c8355588dcd6',
    role: 'Manager',
    accountStatus: 'Active',
    permissions: const ['Manage Actions', 'Approve Requests'],
  );

  final testAction = ActionRecord(
    id: 'act-001',
    actionNumber: 'ACT-1001',
    subject: 'Emergency Eye Wash Station Inspection & Flush',
    actionRequired: 'Perform weekly flush and certification for Zone 3 eye wash unit.',
    division: 'Infrastructure',
    department: 'Sobha Infra',
    section: 'Safety Systems',
    site: 'Sobha Infra',
    assignedTo: 'Reni Thomas',
    assignedToId: testUserId,
    priority: 'High',
    status: 'In Progress',
    percentComplete: 60,
    dateRaised: '2026-11-10',
    targetDate: '2026-11-20',
  );

  final testRequest = RequestRecord(
    id: 'req-001',
    displayId: 'REQ-1001',
    organizationId: orgId,
    title: 'Hot Work Permit for Pipeline Repair',
    description: 'Requires certified spark containment and continuous gas monitoring in Sector 4.',
    requestType: RequestType.ptw,
    priority: RequestPriority.high,
    requiredByDate: '2026-11-20',
    status: RequestStatus.underReview,
    departmentId: 'cc1c49b7-4d9a-4e94-be5b-0ddd89790d6b',
    departmentName: 'Sobha Infra',
    siteId: 'b751354b-f0f8-4a49-9488-c8355588dcd6',
    siteName: 'Sobha Infra',
    createdBy: testUserId,
    createdByName: testUserName,
    createdByRole: 'Manager',
    createdAt: DateTime.now().subtract(const Duration(days: 1)),
    approvers: const [
      RequestApproverRecord(
        id: 'appr-001',
        requestId: 'req-001',
        approverId: testUserId,
        approverName: testUserName,
        approverRole: 'Manager',
        stepOrder: 1,
        status: RequestStatus.pending,
      ),
    ],
  );

  setUp(() {
    RequestService.useMockOnly = true;
    RequestService.instance.clearMockStore();
    RequestService.instance.seedMockRequest(testRequest);

    NotificationService.useMockOnly = true;
    MockNotificationStore.instance.clear();
    MockNotificationStore.instance.createNotification(
      AppNotification(
        id: 'notif-001',
        userId: testUserId,
        organizationId: orgId,
        title: 'Action Assigned: ACT-1001',
        message: 'You have been assigned to Emergency Eye Wash Station Inspection.',
        eventType: 'action_assigned',
        actionId: 'act-001',
        createdAt: DateTime.now(),
      ),
    );

    MockPeopleStore.instance.people.clear();
    MockPeopleStore.instance.people.add(
      Person(
        id: testUserId,
        name: testUserName,
        email: testUserEmail,
        phone: '+91 98765 43210',
        designation: 'HSE Manager',
        type: PersonType.internalUser,
        isActive: true,
        role: UserRole.departmentManager,
        department: 'Sobha Infra',
        site: 'Sobha Infra',
      ),
    );

    final authProfile = AuthProfileData(
      userProfile: testUserProfile,
      roleCode: 'manager',
      status: 'active',
      isActive: true,
      isPrimaryAdmin: false,
    );
    AuthService.instance.setProfileDataForTesting(authProfile);
  });

  tearDown(() {
    RequestService.instance.clearMockStore();
    RequestService.useMockOnly = false;
    MockNotificationStore.instance.clear();
    NotificationService.useMockOnly = false;
    AuthService.instance.setProfileDataForTesting(null);
  });

  Future<void> saveScreenshot(WidgetTester tester, GlobalKey repaintKey, String filename) async {
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

  // Exact viewports mandated by Task 2
  final mobileWidths = [320.0, 360.0, 375.0, 390.0, 414.0, 430.0, 480.0];
  final tabletWidths = [600.0, 768.0, 820.0, 1024.0];
  final desktopWidths = [1024.0, 1280.0, 1366.0, 1440.0, 1600.0, 1920.0];

  group('Task 2 — Comprehensive Responsive Viewport Sweeps & Screenshots', () {
    testWidgets('1. NewRequestScreen across Mobile, Tablet, Desktop', (tester) async {
      final allWidths = [...mobileWidths, ...tabletWidths, ...desktopWidths];
      for (final w in allWidths) {
        tester.view.physicalSize = Size(w, 900);
        tester.view.devicePixelRatio = 1.0;
        final key = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: RepaintBoundary(
              key: key,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: NewRequestScreen(
                    currentUserId: testUserId,
                    currentUserName: testUserName,
                    currentUserRole: 'manager',
                    currentUserEmail: testUserEmail,
                    organizationId: orgId,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull, reason: 'NewRequestScreen overflow at width $w');

        if (w == 360.0) {
          await saveScreenshot(tester, key, 'screen_new_request_mobile.png');
        } else if (w == 768.0) {
          await saveScreenshot(tester, key, 'screen_new_request_tablet.png');
        } else if (w == 1280.0) {
          await saveScreenshot(tester, key, 'screen_new_request_desktop.png');
        }
      }
    });

    testWidgets('2. MyRequestsScreen across Mobile, Tablet, Desktop', (tester) async {
      final allWidths = [...mobileWidths, ...tabletWidths, ...desktopWidths];
      for (final w in allWidths) {
        tester.view.physicalSize = Size(w, 900);
        tester.view.devicePixelRatio = 1.0;
        final key = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: RepaintBoundary(
              key: key,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: MyRequestsScreen(
                    currentUserId: testUserId,
                    currentUserName: testUserName,
                    currentUserRole: 'manager',
                    currentUserEmail: testUserEmail,
                    organizationId: orgId,
                    isManager: true,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull, reason: 'MyRequestsScreen overflow at width $w');

        if (w == 360.0) {
          await saveScreenshot(tester, key, 'screen_my_requests_mobile.png');
        } else if (w == 768.0) {
          await saveScreenshot(tester, key, 'screen_my_requests_tablet.png');
        } else if (w == 1280.0) {
          await saveScreenshot(tester, key, 'screen_my_requests_desktop.png');
        }
      }
    });

    testWidgets('3. RequestApprovalScreen across Mobile, Tablet, Desktop', (tester) async {
      final allWidths = [...mobileWidths, ...tabletWidths, ...desktopWidths];
      for (final w in allWidths) {
        tester.view.physicalSize = Size(w, 900);
        tester.view.devicePixelRatio = 1.0;
        final key = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: RepaintBoundary(
              key: key,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: RequestApprovalScreen(
                    currentUserId: testUserId,
                    currentUserName: testUserName,
                    currentUserRole: 'manager',
                    currentUserEmail: testUserEmail,
                    organizationId: orgId,
                    isManager: true,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final ex = tester.takeException();
        if (ex != null && ex is FlutterError) {
          for (final prop in ex.diagnostics) {
            debugPrint('PROP: ${prop.name} = ${prop.toDescription()}');
          }
        }
        expect(ex, isNull, reason: 'RequestApprovalScreen overflow at width $w');

        if (w == 360.0) {
          await saveScreenshot(tester, key, 'screen_request_approval_mobile.png');
        } else if (w == 768.0) {
          await saveScreenshot(tester, key, 'screen_request_approval_tablet.png');
        } else if (w == 1280.0) {
          await saveScreenshot(tester, key, 'screen_request_approval_desktop.png');
        }
      }
    });

    testWidgets('4. RequestDetailsScreen across Mobile, Tablet, Desktop', (tester) async {
      final allWidths = [...mobileWidths, ...tabletWidths, ...desktopWidths];
      for (final w in allWidths) {
        tester.view.physicalSize = Size(w, 1000);
        tester.view.devicePixelRatio = 1.0;
        final key = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: RepaintBoundary(
              key: key,
              child: RequestDetailsScreen(
                requestId: 'req-001',
                currentUserId: testUserId,
                currentUserName: testUserName,
                currentUserRole: 'manager',
                currentUserEmail: testUserEmail,
                organizationId: orgId,
                isManager: true,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull, reason: 'RequestDetailsScreen overflow at width $w');

        if (w == 360.0) {
          await saveScreenshot(tester, key, 'screen_request_details_mobile.png');
        } else if (w == 768.0) {
          await saveScreenshot(tester, key, 'screen_request_details_tablet.png');
        } else if (w == 1280.0) {
          await saveScreenshot(tester, key, 'screen_request_details_desktop.png');
        }
      }
    });

    testWidgets('5. ManagerReportsScreen across Mobile, Tablet, Desktop', (tester) async {
      final allWidths = [...mobileWidths, ...tabletWidths, ...desktopWidths];
      for (final w in allWidths) {
        tester.view.physicalSize = Size(w, 900);
        tester.view.devicePixelRatio = 1.0;
        final key = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: RepaintBoundary(
              key: key,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: ManagerReportsScreen(
                    allActions: [testAction],
                    userProfile: testUserProfile,
                    onActionTap: (_) {},
                    onExportExcel: (_, [__]) {},
                    onRefresh: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull, reason: 'ManagerReportsScreen overflow at width $w');

        if (w == 360.0) {
          await saveScreenshot(tester, key, 'screen_reports_mobile.png');
        } else if (w == 768.0) {
          await saveScreenshot(tester, key, 'screen_reports_tablet.png');
        } else if (w == 1280.0) {
          await saveScreenshot(tester, key, 'screen_reports_desktop.png');
        }
      }
    });

    testWidgets('6. ActionFlowCalendarView across Mobile, Tablet, Desktop', (tester) async {
      final allWidths = [...mobileWidths, ...tabletWidths, ...desktopWidths];
      for (final w in allWidths) {
        tester.view.physicalSize = Size(w, 900);
        tester.view.devicePixelRatio = 1.0;
        final key = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: RepaintBoundary(
              key: key,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: ActionFlowCalendarView(
                    actions: [testAction],
                    currentUserId: testUserId,
                    isManager: true,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull, reason: 'ActionFlowCalendarView overflow at width $w');

        if (w == 360.0) {
          await saveScreenshot(tester, key, 'screen_calendar_mobile.png');
        } else if (w == 768.0) {
          await saveScreenshot(tester, key, 'screen_calendar_tablet.png');
        } else if (w == 1280.0) {
          await saveScreenshot(tester, key, 'screen_calendar_desktop.png');
        }
      }
    });

    testWidgets('7. NotificationCentreView across Mobile, Tablet, Desktop', (tester) async {
      final allWidths = [...mobileWidths, ...tabletWidths, ...desktopWidths];
      for (final w in allWidths) {
        tester.view.physicalSize = Size(w, 900);
        tester.view.devicePixelRatio = 1.0;
        final key = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: RepaintBoundary(
              key: key,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: NotificationCentreView(
                    userId: testUserId,
                    organizationId: orgId,
                    isManager: true,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull, reason: 'NotificationCentreView overflow at width $w');

        if (w == 360.0) {
          await saveScreenshot(tester, key, 'screen_notifications_mobile.png');
        } else if (w == 768.0) {
          await saveScreenshot(tester, key, 'screen_notifications_tablet.png');
        } else if (w == 1280.0) {
          await saveScreenshot(tester, key, 'screen_notifications_desktop.png');
        }
      }
    });

    testWidgets('8. AddActionScreen across Mobile, Tablet, Desktop', (tester) async {
      final allWidths = [...mobileWidths, ...tabletWidths, ...desktopWidths];
      for (final w in allWidths) {
        tester.view.physicalSize = Size(w, 900);
        tester.view.devicePixelRatio = 1.0;
        final key = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: RepaintBoundary(
              key: key,
              child: AddActionScreen(
                actionId: 'ACT-2026-001',
                isEmbedded: true,
                isManager: true,
                organizationId: orgId,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull, reason: 'AddActionScreen overflow at width $w');

        if (w == 360.0) {
          await saveScreenshot(tester, key, 'screen_add_action_mobile.png');
        } else if (w == 768.0) {
          await saveScreenshot(tester, key, 'screen_add_action_tablet.png');
        } else if (w == 1280.0) {
          await saveScreenshot(tester, key, 'screen_add_action_desktop.png');
        }
      }
    });

    testWidgets('9. ActionDetailsScreen across Mobile, Tablet, Desktop', (tester) async {
      final allWidths = [...mobileWidths, ...tabletWidths, ...desktopWidths];
      for (final w in allWidths) {
        tester.view.physicalSize = Size(w, 900);
        tester.view.devicePixelRatio = 1.0;
        final key = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: RepaintBoundary(
              key: key,
              child: Scaffold(
                body: ActionDetailsScreen(
                  action: testAction,
                  isWorker: false,
                  currentUserId: testUserId,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull, reason: 'ActionDetailsScreen overflow at width $w');

        if (w == 360.0) {
          await saveScreenshot(tester, key, 'screen_action_details_mobile.png');
        } else if (w == 768.0) {
          await saveScreenshot(tester, key, 'screen_action_details_tablet.png');
        } else if (w == 1280.0) {
          await saveScreenshot(tester, key, 'screen_action_details_desktop.png');
        }
      }
    });

    testWidgets('10. LoginScreen across Mobile, Tablet, Desktop', (tester) async {
      final allWidths = [...mobileWidths, ...tabletWidths, ...desktopWidths];
      for (final w in allWidths) {
        tester.view.physicalSize = Size(w, 900);
        tester.view.devicePixelRatio = 1.0;
        final key = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: RepaintBoundary(
              key: key,
              child: const LoginScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull, reason: 'LoginScreen overflow at width $w');

        if (w == 360.0) {
          await saveScreenshot(tester, key, 'screen_login_mobile.png');
        } else if (w == 768.0) {
          await saveScreenshot(tester, key, 'screen_login_tablet.png');
        } else if (w == 1280.0) {
          await saveScreenshot(tester, key, 'screen_login_desktop.png');
        }
      }
    });

    testWidgets('11. ForwardRequestDialog across Mobile, Tablet, Desktop', (tester) async {
      final allWidths = [...mobileWidths, ...tabletWidths, ...desktopWidths];
      for (final w in allWidths) {
        tester.view.physicalSize = Size(w, 900);
        tester.view.devicePixelRatio = 1.0;
        final key = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: RepaintBoundary(
              key: key,
              child: Scaffold(
                body: Center(
                  child: ForwardRequestDialog(
                    request: testRequest,
                    currentUserId: testUserId,
                    currentUserName: testUserName,
                    currentUserRole: 'Manager',
                    organizationId: orgId,
                    onForwardSuccess: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull, reason: 'ForwardRequestDialog overflow at width $w');

        if (w == 360.0) {
          await saveScreenshot(tester, key, 'dialog_forward_request_mobile.png');
        } else if (w == 1280.0) {
          await saveScreenshot(tester, key, 'dialog_forward_request_desktop.png');
        }
      }
    });
  });
}
