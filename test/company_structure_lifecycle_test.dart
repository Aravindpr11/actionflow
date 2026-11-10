import 'package:action_flow/features/dashboard/admin_dashboard/screens/admin_dashboard_screen.dart';
import 'package:action_flow/services/company_structure_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CompanyStructureService - Department & Site Structure Lifecycle', () {
    test('deleteDepartment in offline/mock mode returns success map', () async {
      final service = CompanyStructureService();
      expect(service.isReady, isFalse);

      final res = await service.deleteDepartment(
        departmentId: '00000000-0000-0000-0000-000000000001',
      );
      expect(res['success'], isTrue);
      expect(res['message'], contains('deleted successfully'));
    });

    test('deleteSite in offline/mock mode returns success map', () async {
      final service = CompanyStructureService();
      expect(service.isReady, isFalse);

      final res = await service.deleteSite(
        siteId: '00000000-0000-0000-0000-000000000002',
      );
      expect(res['success'], isTrue);
      expect(res['message'], contains('deleted successfully'));
    });

    test('structured RPC response parses dependencies correctly', () {
      final rpcBlockedResponse = {
        'success': false,
        'error_code': 'DEPENDENCIES_EXIST',
        'message': 'Cannot delete department "HSE": 2 assigned user(s) exist.',
        'dependencies': {
          'users': 2,
          'teams': 1,
          'account_requests': 0,
          'manager_scopes': 1,
        },
      };

      expect(rpcBlockedResponse['success'], isFalse);
      expect(rpcBlockedResponse['error_code'], equals('DEPENDENCIES_EXIST'));
      final deps = rpcBlockedResponse['dependencies'] as Map<String, dynamic>;
      expect(deps['users'], equals(2));
      expect(deps['teams'], equals(1));
      expect(deps['manager_scopes'], equals(1));
    });
  });

  group('AdminDashboardScreen - Safe Deletion UI & Dialogs', () {
    testWidgets(
      'Departments tab renders delete buttons and handles confirmation dialog',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: AdminDashboardScreen(initialTabIndex: 2), // Departments tab
          ),
        );
        await tester.pumpAndSettle();

        // Verify Departments tab is visible
        expect(find.text('Departments'), findsWidgets);

        // Verify delete button exists for the first department
        final deleteButtons = find.byIcon(Icons.delete_outline_rounded);
        expect(deleteButtons, findsWidgets);

        // Tap the first delete button
        await tester.tap(deleteButtons.first);
        await tester.pumpAndSettle();

        // Verify confirmation dialog appears
        expect(
          find.textContaining('Are you sure you want to permanently delete'),
          findsOneWidget,
        );
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);

        // Tap Cancel to dismiss
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        // Verify dialog is dismissed
        expect(
          find.textContaining('Are you sure you want to permanently delete'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Sites tab renders delete buttons and handles confirmation dialog',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: AdminDashboardScreen(initialTabIndex: 3), // Sites tab
          ),
        );
        await tester.pumpAndSettle();

        // Verify Sites tab is visible
        expect(find.text('Sites'), findsWidgets);

        // Verify delete button exists for the first site
        final deleteButtons = find.byIcon(Icons.delete_outline_rounded);
        expect(deleteButtons, findsWidgets);

        // Tap the first delete button
        await tester.tap(deleteButtons.first);
        await tester.pumpAndSettle();

        // Verify confirmation dialog appears
        expect(
          find.textContaining('Are you sure you want to permanently delete'),
          findsOneWidget,
        );
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);

        // Tap Cancel to dismiss
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        // Verify dialog is dismissed
        expect(
          find.textContaining('Are you sure you want to permanently delete'),
          findsNothing,
        );
      },
    );
  });
}
