import 'dart:convert';
import 'dart:typed_data';

import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_action_update_screen.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:action_flow/services/app_file_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baseAction = ActionRecord(
    id: 'ACT-1025',
    actionNumber: 'ACT-1025',
    organizationId: 'org-test-evidence',
    departmentId: 'dept-safety',
    siteId: 'site-alpha',
    subject: 'Safety Evidence Verification Test',
    actionRequired: 'Verify real file upload, storage, and cross-portal visibility',
    status: 'In Progress',
    priority: 'High',
    createdById: 'manager-user-01',
    assignedToId: 'staff-user-01',
    assignedTo: 'John Staff',
    division: 'HSE',
    attachments: const [
      'existing_document.pdf',
    ],
  );

  setUp(() {
    MockActionStore.instance.actions
      ..clear()
      ..add(baseAction);
    AppFilePicker.testOverride = null;
    AppFilePicker.saveTestOverride = null;
  });

  tearDown(() {
    AppFilePicker.testOverride = null;
    AppFilePicker.saveTestOverride = null;
  });

  group('Action Evidence & Supabase Storage Lifecycle', () {
    test('1. ActionService.uploadActionAttachment updates action attachments and mock store', () async {
      final sampleBytes = Uint8List.fromList(utf8.encode('Fake PNG binary content'));
      final result = await ActionService.instance.uploadActionAttachment(
        action: baseAction,
        fileName: 'new_site_photo.png',
        bytes: sampleBytes,
      );

      expect(result.success, isTrue);
      expect(result.error, isNull);
      expect(result.updatedAction, isNotNull);
      expect(result.updatedAction!.attachments, contains('new_site_photo.png'));
      expect(result.updatedAction!.attachments, contains('existing_document.pdf'));

      // Verify MockActionStore updated
      final storeAction = MockActionStore.instance.actions.firstWhere((a) => a.id == 'ACT-1025');
      expect(storeAction.attachments, contains('new_site_photo.png'));
      expect(storeAction.history.first, contains('new_site_photo.png'));
    });

    test('2. uploadActionAttachment rejects empty bytes or invalid filenames', () async {
      final emptyBytesResult = await ActionService.instance.uploadActionAttachment(
        action: baseAction,
        fileName: 'empty.pdf',
        bytes: Uint8List(0),
      );
      expect(emptyBytesResult.success, isFalse);
      expect(emptyBytesResult.error, contains('cannot be empty'));

      final invalidNameResult = await ActionService.instance.uploadActionAttachment(
        action: baseAction,
        fileName: '   ',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      expect(invalidNameResult.success, isFalse);
      expect(invalidNameResult.error, contains('Invalid attachment filename'));
    });

    test('3. ActionRecord.fromMap aggregates attachments from progress updates for cross-portal visibility', () {
      final mapData = {
        'id': 'ACT-1025',
        'action_number': 'ACT-1025',
        'organization_id': 'org-test-evidence',
        'title': 'Test Action Title',
        'action_required': 'Test Requirement',
        'status': 'In Progress',
        'priority': 'High',
        'division': 'HSE',
        'created_by': 'manager-user-01',
        'assigned_to': 'staff-user-01',
        'attachments': ['initial_photo.jpg'],
        'action_progress_updates': [
          {
            'id': 'update-01',
            'action_id': 'ACT-1025',
            'update_date': '2026-11-01',
            'progress': 50,
            'status': 'In Progress',
            'comments': 'Work started on site',
            'attachments': ['staff_evidence_report.pdf', 'initial_photo.jpg'],
          },
          {
            'id': 'update-02',
            'action_id': 'ACT-1025',
            'update_date': '2026-11-02',
            'progress': 80,
            'status': 'In Progress',
            'comments': 'Further progress',
            'attachments': ['secondary_measurement.xlsx'],
          },
        ],
      };

      final record = ActionRecord.fromSupabase(mapData);
      expect(record.attachments, contains('initial_photo.jpg'));
      expect(record.attachments, contains('staff_evidence_report.pdf'));
      expect(record.attachments, contains('secondary_measurement.xlsx'));
      expect(record.attachments.length, equals(3), reason: 'initial_photo.jpg must be deduplicated');
    });

    testWidgets('4. Manager Portal: Upload Evidence requires file selection, preventing false-positive success', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: ActionDetailsScreen(
              action: baseAction,
              currentUserId: 'manager-user-01',
              isWorker: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Go to Evidence & Attachments tab
      await tester.tap(find.text('Evidence & Attachments').first);
      await tester.pumpAndSettle();

      // Tap 'Upload Evidence' button
      final uploadBtn = find.text('Upload Evidence').first;
      await tester.tap(uploadBtn);
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.text('Upload Evidence File'), findsOneWidget);
      expect(find.text('Choose File from Computer'), findsOneWidget);

      // Attempt clicking "Upload" without selecting a file
      final dialogUploadBtn = find.widgetWithText(ElevatedButton, 'Upload');
      await tester.tap(dialogUploadBtn);
      await tester.pumpAndSettle();

      // Validation error appears, preventing false-positive success
      expect(find.text('Please choose a file from your computer first.'), findsOneWidget);
      expect(find.text('Uploaded successfully'), findsNothing);

      // Now inject a picked file via AppFilePicker.testOverride
      AppFilePicker.testOverride = ({required allowedExtensions}) async {
        return AppPickedFile(
          name: 'audit_certificate.pdf',
          bytes: Uint8List.fromList(utf8.encode('%PDF-1.4 Mock Audit Certificate')),
        );
      };

      // Tap 'Choose File from Computer'
      await tester.tap(find.text('Choose File from Computer'));
      await tester.pumpAndSettle();

      // File name is now prefilled and selected state displayed
      expect(find.textContaining('audit_certificate.pdf'), findsWidgets);

      // Tap 'Upload'
      await tester.tap(dialogUploadBtn);
      await tester.pumpAndSettle();

      // Dialog dismissed and success SnackBar shown
      expect(find.text('Upload Evidence File'), findsNothing);
      expect(find.textContaining('Uploaded "audit_certificate.pdf" successfully.'), findsOneWidget);
      expect(find.text('audit_certificate.pdf'), findsWidgets);
    });

    testWidgets('5. Staff Portal: Update Action allows picking file and enforces 10MB limit', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // 1. Test 10MB limit
      AppFilePicker.testOverride = ({required allowedExtensions}) async {
        return AppPickedFile(
          name: 'large_video.mp4',
          bytes: Uint8List(12 * 1024 * 1024), // 12 MB
        );
      };

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: WorkerActionUpdateScreen(
              action: baseAction,
              currentUserId: 'staff-user-01',
              currentUserName: 'John Staff',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Evidence Tab (Tab 1)
      await tester.tap(find.byIcon(Icons.attach_file_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('INSPECTION EVIDENCE & ATTACHMENTS'), findsOneWidget);
      final addEvidenceBtn = find.text('Add Evidence Document');
      expect(addEvidenceBtn, findsOneWidget);
      await tester.tap(addEvidenceBtn);
      await tester.pumpAndSettle();

      // Warning SnackBar for >10MB
      expect(find.textContaining('exceeds the 10MB limit'), findsOneWidget);

      // 2. Test valid file picking and saving update
      AppFilePicker.testOverride = ({required allowedExtensions}) async {
        return AppPickedFile(
          name: 'scaffold_photo.png',
          bytes: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
        );
      };

      await tester.tap(addEvidenceBtn);
      await tester.pumpAndSettle();

      // File is displayed in attachments list
      expect(find.text('scaffold_photo.png'), findsOneWidget);

      // Save update (top action bar button)
      final saveBtn = find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithText(OutlinedButton, 'Save Update'),
      );
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Action record updated in MockActionStore
      final updatedInStore = MockActionStore.instance.actions.firstWhere((a) => a.id == 'ACT-1025');
      expect(updatedInStore.attachments, contains('scaffold_photo.png'));
    });
  });
}
