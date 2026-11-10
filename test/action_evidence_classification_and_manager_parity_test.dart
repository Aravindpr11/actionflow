import 'dart:typed_data';
import 'package:action_flow/features/auth/models/manager_scope_item.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/action_details_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_action_update_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_action_update_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/services/app_file_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testManagerProfile = const UserProfile(
    id: 'mgr-user-uuid-101',
    name: 'David Manager',
    email: 'david.mgr@sobha.com',
    phone: '+971501234567',
    designation: 'HSE Manager',
    department: 'Safety Operations',
    site: 'Main Plant Facility',
    role: 'manager',
    organizationId: 'org-sobha-01',
    organizationName: 'Sobha Constructions',
  );

  final testManagerContext = ManagerContext(
    authUserId: 'mgr-user-uuid-101',
    profile: testManagerProfile,
    organizationId: 'org-sobha-01',
    organizationName: 'Sobha Constructions',
    scopes: const [
      ManagerScopeItem(
        departmentId: 'dept-safety-01',
        departmentName: 'Safety Operations',
        siteId: 'site-plant-01',
        siteName: 'Main Plant Facility',
      ),
    ],
  );

  final testActionWithClassifiedEvidence = ActionRecord(
    id: 'act-parity-01',
    actionNumber: 'ACT-PARITY-100',
    organizationId: 'org-sobha-01',
    departmentId: 'dept-safety-01',
    siteId: 'site-plant-01',
    subject: 'Safety Valve Pressure Recalibration and Relief Test',
    actionRequired: 'Inspect and recalibrate safety relief valves on line 3.',
    division: 'Operations',
    department: 'Safety Operations',
    site: 'Main Plant Facility',
    assignedTo: 'John Worker',
    assignedToId: 'worker-user-uuid-201',
    assignedBy: 'David Manager',
    priority: 'High',
    status: 'In Progress',
    percentComplete: 65,
    targetDate: '25 Sep 2026',
    // Original documents attached during action creation:
    attachments: [
      'Original_Safety_Valve_Specs.pdf',
      'Site_Inspection_Permit.png',
    ],
    // Progress updates submitted by Staff and Manager:
    progressUpdates: [
      ActionProgressUpdate(
        id: 'upd-mgr-01',
        actionId: 'act-parity-01',
        updatedById: 'mgr-user-uuid-101',
        updatedByName: 'David Manager',
        updateDate: '22 Sep 2026',
        progress: 65,
        status: 'In Progress',
        comments: 'Manager site verification: Calibrated gauge readings confirmed within tolerance.',
        attachments: ['Manager_Verification_Report.pdf'],
        roleInAction: 'manager',
        createdAt: DateTime(2026, 9, 22, 11, 0),
      ),
      ActionProgressUpdate(
        id: 'upd-staff-01',
        actionId: 'act-parity-01',
        updatedById: 'worker-user-uuid-201',
        updatedByName: 'John Worker',
        updateDate: '20 Sep 2026',
        progress: 40,
        status: 'In Progress',
        comments: 'Disassembled valve casing and replaced primary gasket ring.',
        attachments: ['Gasket_Replacement_Photo.jpg', 'Initial_Torque_Test.pdf'],
        roleInAction: 'assignee',
        createdAt: DateTime(2026, 9, 20, 14, 30),
      ),
    ],
  );

  Widget createTestWidget(Widget child, {Size size = const Size(1280, 1000)}) {
    return MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        home: child,
      ),
    );
  }

  void configureTesterView(
    WidgetTester tester, {
    Size size = const Size(1280, 1000),
  }) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
    });
  }

  group('Task 3: Document Classification in ActionRecord Models', () {
    test('Correctly separates Original, Staff, and Manager evidence items', () {
      final action = testActionWithClassifiedEvidence;

      // Original documents
      expect(action.originalDocuments.length, 2);
      expect(action.originalDocuments[0].fileName, 'Original_Safety_Valve_Specs.pdf');
      expect(action.originalDocuments[0].fileType, 'PDF');
      expect(action.originalDocuments[0].classification, EvidenceClassification.originalActionDocument);
      expect(action.originalDocuments[1].fileName, 'Site_Inspection_Permit.png');
      expect(action.originalDocuments[1].fileType, 'PNG Image');
      expect(action.originalDocuments[1].classification, EvidenceClassification.originalActionDocument);

      // Staff update evidence
      expect(action.staffUpdateEvidence.length, 2);
      expect(action.staffUpdateEvidence[0].fileName, 'Gasket_Replacement_Photo.jpg');
      expect(action.staffUpdateEvidence[0].fileType, 'JPEG Image');
      expect(action.staffUpdateEvidence[0].classification, EvidenceClassification.staffUpdateEvidence);
      expect(action.staffUpdateEvidence[0].uploadedBy, 'John Worker');
      expect(action.staffUpdateEvidence[1].fileName, 'Initial_Torque_Test.pdf');
      expect(action.staffUpdateEvidence[1].fileType, 'PDF');
      expect(action.staffUpdateEvidence[1].classification, EvidenceClassification.staffUpdateEvidence);

      // Manager update evidence
      expect(action.managerUpdateEvidence.length, 1);
      expect(action.managerUpdateEvidence[0].fileName, 'Manager_Verification_Report.pdf');
      expect(action.managerUpdateEvidence[0].fileType, 'PDF');
      expect(action.managerUpdateEvidence[0].classification, EvidenceClassification.managerUpdateEvidence);
      expect(action.managerUpdateEvidence[0].uploadedBy, 'David Manager');

      // Total classified items
      expect(action.allClassifiedEvidence.length, 5);
    });
  });

  group('Task 2 & 5: Staff Update Action Screen — Evidence Isolation and Parity', () {
    testWidgets('WorkerActionUpdateScreen isolates new uploads and shows previous staff evidence', (tester) async {
      configureTesterView(tester);

      await tester.pumpWidget(
        createTestWidget(
          WorkerActionUpdateScreen(
            action: testActionWithClassifiedEvidence,
            currentUserId: 'worker-user-uuid-201',
            currentUserName: 'John Worker',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Evidence tab (tab index 1)
      final evidenceTab = find.textContaining('Evidence');
      expect(evidenceTab, findsWidgets);
      await tester.tap(evidenceTab.first);
      await tester.pumpAndSettle();

      // Verify that New Evidence starts empty with guidance
      expect(find.textContaining('No new evidence files selected for this update'), findsOneWidget);
      expect(
        find.textContaining('Previously attached documents remain preserved in Action Details'),
        findsOneWidget,
      );

      // Verify Previously Submitted Evidence section exists and shows staff evidence
      expect(find.textContaining('PREVIOUSLY SUBMITTED EVIDENCE'), findsOneWidget);
      expect(find.text('Gasket_Replacement_Photo.jpg'), findsOneWidget);
      expect(find.text('Initial_Torque_Test.pdf'), findsOneWidget);

      // Manager verification report should NOT be in the staff update evidence list
      expect(find.text('Manager_Verification_Report.pdf'), findsNothing);
    });
  });

  group('Task 1, 2 & 5: Manager Update Action Screen — 3-Tab Workflow and Evidence Isolation', () {
    testWidgets('ManagerActionUpdateScreen renders 3 tabs (Update, Evidence, History) matching Staff screen', (tester) async {
      configureTesterView(tester);

      await tester.pumpWidget(
        createTestWidget(
          ManagerActionUpdateScreen(
            action: testActionWithClassifiedEvidence,
            currentUserId: 'mgr-user-uuid-101',
            currentUserName: 'David Manager',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify 3 tabs exist: Update, Evidence, History (Requirements & Suggestions removed)
      expect(find.text('Update'), findsWidgets);
      expect(find.textContaining('Evidence'), findsWidgets);
      expect(find.textContaining('History'), findsWidgets);
      expect(find.text('Requirements'), findsNothing);
      expect(find.text('Suggestions'), findsNothing);

      // Verify Hero card and Action summary details
      expect(find.text('ACT-PARITY-100'), findsOneWidget);
      expect(find.text('Safety Valve Pressure Recalibration and Relief Test'), findsOneWidget);
      expect(find.text('ACTION DETAILS SUMMARY'), findsOneWidget);
      expect(find.text('QUICK ACTIONS'), findsOneWidget);

      // Navigate to Evidence tab
      final evidenceTab = find.textContaining('Evidence');
      await tester.tap(evidenceTab.first);
      await tester.pumpAndSettle();

      // Verify new evidence dropzone is present and empty
      expect(find.text('No attachments added for this update.'), findsOneWidget);
      expect(find.textContaining('No new documents selected for this update'), findsOneWidget);
      expect(find.text('Add File'), findsWidgets);

      // Verify previously submitted evidence section is present with preview & download
      expect(find.textContaining('PREVIOUSLY SUBMITTED EVIDENCE'), findsOneWidget);
      expect(find.text('Manager_Verification_Report.pdf'), findsOneWidget);
      expect(find.text('Gasket_Replacement_Photo.jpg'), findsOneWidget);
      expect(find.text('Initial_Torque_Test.pdf'), findsOneWidget);
    });

    testWidgets('ManagerActionUpdateScreen allows adding and removing new attachments', (tester) async {
      configureTesterView(tester, size: const Size(1280, 2500));
      AppFilePicker.testOverride = ({required allowedExtensions}) async {
        return AppPickedFile(
          name: 'New_Manager_Calibration_Audit.pdf',
          bytes: Uint8List.fromList([1, 2, 3]),
          size: 3,
        );
      };
      addTearDown(() => AppFilePicker.testOverride = null);

      await tester.pumpWidget(
        createTestWidget(
          ManagerActionUpdateScreen(
            action: testActionWithClassifiedEvidence,
            currentUserId: 'mgr-user-uuid-101',
            currentUserName: 'David Manager',
          ),
          size: const Size(1280, 2500),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Add File on Tab 0
      final addFileBtn = find.text('Add File').first;
      await tester.ensureVisible(addFileBtn);
      await tester.tap(addFileBtn);
      await tester.pumpAndSettle();

      // Verify newly picked document appears in current update list
      expect(find.text('New_Manager_Calibration_Audit.pdf'), findsOneWidget);

      // Remove newly picked document
      final removeIcon = find.byIcon(Icons.close_rounded);
      expect(removeIcon, findsOneWidget);
      await tester.tap(removeIcon);
      await tester.pumpAndSettle();

      // Verify empty state is restored
      expect(find.text('No attachments added for this update.'), findsOneWidget);
    });
  });

  group('Task 4: Action Details Screen — Two Distinct Evidence Columns', () {
    testWidgets('ActionDetailsScreen displays Original Docs and Two Separate Evidence Columns on Desktop', (tester) async {
      configureTesterView(tester, size: const Size(1280, 2500));

      await tester.pumpWidget(
        createTestWidget(
          ActionDetailsScreen(
            action: testActionWithClassifiedEvidence,
            managerContext: testManagerContext,
          ),
          size: const Size(1280, 2500),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Evidence & Attachments tab
      final evidenceTab = find.text('Evidence & Attachments');
      await tester.ensureVisible(evidenceTab);
      await tester.tap(evidenceTab);
      await tester.pumpAndSettle();

      // 1. Verify Original Action Documents section
      expect(find.textContaining('ORIGINAL ACTION DOCUMENTS'), findsOneWidget);
      expect(find.text('Original_Safety_Valve_Specs.pdf'), findsOneWidget);
      expect(find.text('Site_Inspection_Permit.png'), findsOneWidget);

      // 2. Verify Two Separate Columns: Staff Update Evidence & Manager Update Evidence
      expect(find.textContaining('STAFF UPDATE EVIDENCE'), findsOneWidget);
      expect(find.textContaining('MANAGER UPDATE EVIDENCE'), findsOneWidget);

      // Verify Staff column contents
      expect(find.text('Gasket_Replacement_Photo.jpg'), findsOneWidget);
      expect(find.text('Initial_Torque_Test.pdf'), findsOneWidget);

      // Verify Manager column contents
      expect(find.text('Manager_Verification_Report.pdf'), findsOneWidget);

      // Verify Preview and Download buttons exist for documents
      expect(find.byKey(const Key('preview_attachment_Original_Safety_Valve_Specs.pdf_btn')), findsOneWidget);
      expect(find.byKey(const Key('download_attachment_Original_Safety_Valve_Specs.pdf_btn')), findsOneWidget);
      expect(find.byKey(const Key('preview_attachment_Manager_Verification_Report.pdf_btn')), findsOneWidget);
      expect(find.byKey(const Key('download_attachment_Manager_Verification_Report.pdf_btn')), findsOneWidget);
    });

    testWidgets('ActionDetailsScreen stacks Staff and Manager evidence sections responsively on Mobile', (tester) async {
      configureTesterView(tester, size: const Size(600, 2500));

      await tester.pumpWidget(
        createTestWidget(
          ActionDetailsScreen(
            action: testActionWithClassifiedEvidence,
            managerContext: testManagerContext,
          ),
          size: const Size(600, 2500),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Evidence & Attachments tab
      final evidenceTab = find.text('Evidence & Attachments');
      await tester.ensureVisible(evidenceTab);
      await tester.tap(evidenceTab);
      await tester.pumpAndSettle();

      // Verify both sections render properly without layout errors
      expect(find.textContaining('ORIGINAL ACTION DOCUMENTS'), findsOneWidget);
      expect(find.textContaining('STAFF UPDATE EVIDENCE'), findsOneWidget);
      expect(find.textContaining('MANAGER UPDATE EVIDENCE'), findsOneWidget);
      expect(find.text('Gasket_Replacement_Photo.jpg'), findsOneWidget);
      expect(find.text('Manager_Verification_Report.pdf'), findsOneWidget);
    });
  });
}
