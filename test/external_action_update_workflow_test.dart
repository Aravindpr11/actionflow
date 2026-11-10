import 'package:action_flow/features/external_update/models/external_action_payload.dart';
import 'package:action_flow/features/external_update/screens/external_action_update_screen.dart';
import 'package:action_flow/features/external_update/services/external_action_service.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:action_flow/services/email_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const testRawToken = 'a1b2c3d4e5f67890123456789abcdef0123456789abcdef0123456789abcdef0';
  const testActionId = 'act-test-uuid-999';
  const testRecipientId = 'rec-test-uuid-888';

  final testPayload = ExternalActionPayload(
    actionId: testActionId,
    actionNumber: 'ACT-2026-0042',
    title: 'Replace damaged scaffolding planks on Tower B',
    description: 'Inspect and replace all weathered or cracked timber scaffold boards on levels 4 through 8.',
    actionRequired: 'Replace damaged planks, secure toe boards, and provide certification tag.',
    category: 'Work at Height',
    priority: 'High',
    status: 'In Progress',
    percentComplete: 40,
    dateRaised: '2026-09-20',
    startDate: '2026-09-21',
    targetDate: '2026-09-30',
    dueDate: '2026-09-30',
    nextFollowUpDate: '2026-09-25',
    department: 'Civil & Scaffolding',
    site: 'Tower B Construction',
    organizationName: 'Sobha Constructions',
    isClosed: false,
    recipientId: testRecipientId,
    recipientName: 'Robert Scaffolding Contractor',
    recipientEmail: 'robert@scaffoldingpro.com',
    companyName: 'Apex Scaffolding Services',
    phone: '+971555123456',
    expiresAt: DateTime.now().add(const Duration(days: 7)),
    recentHistory: [
      {
        'timestamp': DateTime(2026, 9, 21, 10, 0).toIso8601String(),
        'actor_type': 'manager',
        'actor_name': 'David Manager',
        'progress': 0,
        'status': 'Open',
        'action': 'Action assigned to external contractor Robert Scaffolding Contractor',
      },
    ],
  );

  setUp(() {
    MockExternalActionStore.instance.reset();
    EmailService.mockSendHandler = null;
    AuthService.clearCapturedExternalUpdateToken();
    AuthService.clearCapturedInitialAuthFlow();
  });

  group('A. Shared Email Service & Resend Edge Function Integration', () {
    test('1. SHA-256 token hashing produces 64-character lowercase hex digest', () {
      final hash1 = EmailService.hashToken(testRawToken);
      expect(hash1.length, 64);
      expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(hash1), isTrue);

      // Deterministic hashing
      final hash2 = EmailService.hashToken(testRawToken);
      expect(hash1, equals(hash2));

      // Different raw token produces different hash
      final hash3 = EmailService.hashToken('different-token-string');
      expect(hash1, isNot(equals(hash3)));
    });

    test('2. checkProviderStatus returns not_configured when secrets are unset', () async {
      final status = await EmailService.instance.checkProviderStatus();
      expect(status['configured'], isFalse);
      expect(status['status'], equals('not_configured'));
    });

    test('3. sendActionReminder respects reminder disabled state', () async {
      EmailService.mockSendHandler = (params) {
        return EmailSendResult.remindersDisabled();
      };

      final result = await EmailService.instance.sendActionReminder(
        actionId: testActionId,
      );

      expect(result.isSuccess, isFalse);
      expect(result.status, equals('reminders_disabled'));
      expect(result.errorMessage, contains('disabled'));
    });

    test('4. sendActionReminder handles both internal staff and external contractor recipients', () async {
      Map<String, dynamic>? capturedParams;
      EmailService.mockSendHandler = (params) {
        capturedParams = params;
        return EmailSendResult.sent('msg_resend_12345');
      };

      // Test external contractor recipient
      final extResult = await EmailService.instance.sendActionReminder(
        actionId: testActionId,
        recipientType: 'external',
      );
      expect(extResult.isSuccess, isTrue);
      expect(extResult.status, 'sent');
      expect(extResult.messageId, 'msg_resend_12345');
      expect(capturedParams!['recipient_type'], 'external');

      // Test internal staff recipient
      final intResult = await EmailService.instance.sendActionReminder(
        actionId: testActionId,
        recipientType: 'internal',
      );
      expect(intResult.isSuccess, isTrue);
      expect(capturedParams!['recipient_type'], 'internal');
    });

    test('5. sendSingleEmail records failure reason without falsely claiming success', () async {
      EmailService.mockSendHandler = (params) {
        return EmailSendResult.failed('Resend API domain unverified');
      };

      final result = await EmailService.instance.sendSingleEmail(
        to: 'vendor@contractor.com',
        subject: 'ActionFlow Notice',
        html: '<p>Test</p>',
      );

      expect(result.isSuccess, isFalse);
      expect(result.status, 'failed');
      expect(result.errorMessage, 'Resend API domain unverified');
    });
  });

  group('B. External Action Tokens & Data Access Security', () {
    test('1. Valid token retrieves action payload and tenant details', () async {
      MockExternalActionStore.instance.registerToken(
        rawToken: testRawToken,
        payload: testPayload,
      );

      final result = await ExternalActionService.instance.fetchActionByToken(testRawToken);
      expect(result, isA<ExternalActionFetchSuccess>());
      final payload = (result as ExternalActionFetchSuccess).payload;
      expect(payload.actionNumber, 'ACT-2026-0042');
      expect(payload.title, contains('scaffolding planks'));
      expect(payload.recipientName, 'Robert Scaffolding Contractor');
      expect(payload.organizationName, 'Sobha Constructions');
      expect(payload.percentComplete, 40);
    });

    test('2. Expired token is rejected with isExpired: true', () async {
      MockExternalActionStore.instance.registerToken(
        rawToken: testRawToken,
        payload: testPayload,
        expiry: const Duration(days: -1), // already expired
      );

      final result = await ExternalActionService.instance.fetchActionByToken(testRawToken);
      expect(result, isA<ExternalActionFetchFailure>());
      final failure = result as ExternalActionFetchFailure;
      expect(failure.isExpired, isTrue);
      expect(failure.errorMessage, contains('expired'));
    });

    test('3. Revoked token is rejected with isRevoked: true', () async {
      MockExternalActionStore.instance.registerToken(
        rawToken: testRawToken,
        payload: testPayload,
        isRevoked: true,
      );

      final result = await ExternalActionService.instance.fetchActionByToken(testRawToken);
      expect(result, isA<ExternalActionFetchFailure>());
      final failure = result as ExternalActionFetchFailure;
      expect(failure.isRevoked, isTrue);
      expect(failure.errorMessage, contains('revoked'));
    });

    test('4. Non-existent or unknown token cannot access any tenant data', () async {
      final result = await ExternalActionService.instance.fetchActionByToken(
        'unknown_attacker_crafted_token_1234567890',
      );
      expect(result, isA<ExternalActionFetchFailure>());
    });

    test('5. Empty or whitespace-only token is rejected upfront', () async {
      final result = await ExternalActionService.instance.fetchActionByToken('   ');
      expect(result, isA<ExternalActionFetchFailure>());
      expect((result as ExternalActionFetchFailure).errorMessage, contains('missing'));
    });
  });

  group('C. External Progress Submission & Privilege Guards', () {
    setUp(() {
      MockExternalActionStore.instance.registerToken(
        rawToken: testRawToken,
        payload: testPayload,
      );
    });

    test('1. Valid external contractor progress submission succeeds and updates history', () async {
      final submitResult = await ExternalActionService.instance.submitProgressUpdate(
        rawToken: testRawToken,
        progress: 75,
        status: 'In Progress',
        comments: 'Replaced 18 defective planks on level 4 and 5. Level 6 in progress.',
        attachments: ['photo_level4_planks.jpg', 'safety_tag_789.pdf'],
      );

      expect(submitResult, isA<ExternalActionSubmitSuccess>());
      final success = submitResult as ExternalActionSubmitSuccess;
      expect(success.progress, 75);
      expect(success.status, 'In Progress');

      // Verify the updated action has the new progress & history entry
      final fetchResult = await ExternalActionService.instance.fetchActionByToken(testRawToken);
      expect(fetchResult, isA<ExternalActionFetchSuccess>());
      final updated = (fetchResult as ExternalActionFetchSuccess).payload;
      expect(updated.percentComplete, 75);
      expect(updated.recentHistory.first['comment'], contains('Replaced 18 defective planks'));
      expect(updated.recentHistory.first['actor_name'], 'Robert Scaffolding Contractor');
    });

    test('2. SECURITY: External contractor setting status = Closed is strictly rejected', () async {
      final submitResult = await ExternalActionService.instance.submitProgressUpdate(
        rawToken: testRawToken,
        progress: 100,
        status: 'Closed',
        comments: 'All work finished, closing the action.',
      );

      expect(submitResult, isA<ExternalActionSubmitFailure>());
      final failure = submitResult as ExternalActionSubmitFailure;
      expect(failure.errorMessage, contains('Security Violation'));
      expect(failure.errorMessage, contains('cannot approve or close'));
    });

    test('3. Missing comments / notes is rejected', () async {
      final submitResult = await ExternalActionService.instance.submitProgressUpdate(
        rawToken: testRawToken,
        progress: 50,
        status: 'In Progress',
        comments: '   ',
      );

      expect(submitResult, isA<ExternalActionSubmitFailure>());
      expect((submitResult as ExternalActionSubmitFailure).errorMessage, contains('notes / comments are required'));
    });

    test('4. Progress percentage outside 0-100 is rejected', () async {
      final negativeResult = await ExternalActionService.instance.submitProgressUpdate(
        rawToken: testRawToken,
        progress: -5,
        status: 'In Progress',
        comments: 'Invalid negative progress',
      );
      expect(negativeResult, isA<ExternalActionSubmitFailure>());

      final overflowResult = await ExternalActionService.instance.submitProgressUpdate(
        rawToken: testRawToken,
        progress: 150,
        status: 'In Progress',
        comments: 'Invalid overflow progress',
      );
      expect(overflowResult, isA<ExternalActionSubmitFailure>());
    });

    test('5. Submission fails if token is revoked', () async {
      MockExternalActionStore.instance.revokeToken(testRawToken);

      final submitResult = await ExternalActionService.instance.submitProgressUpdate(
        rawToken: testRawToken,
        progress: 80,
        status: 'In Progress',
        comments: 'Late update submission',
      );

      expect(submitResult, isA<ExternalActionSubmitFailure>());
      expect((submitResult as ExternalActionSubmitFailure).errorMessage, contains('revoked'));
    });
  });

  group('D. Route Handling & Deep Link Parsing', () {
    test('1. captureInitialAuthFlow extracts token from query parameter', () {
      final uri = Uri.parse('http://localhost:8080/external-update?token=xyz987');
      AuthService.captureInitialAuthFlow(uri);

      expect(AuthService.capturedExternalUpdateToken, 'xyz987');
      expect(AuthService.capturedInitialAuthFlow, InitialAuthFlow.none);
    });

    test('2. captureInitialAuthFlow extracts token from Web hash fragment', () {
      final uri = Uri.parse('http://localhost:8080/#/external-update?token=hash_token_abc');
      AuthService.captureInitialAuthFlow(uri);

      expect(AuthService.capturedExternalUpdateToken, 'hash_token_abc');
      expect(AuthService.capturedInitialAuthFlow, InitialAuthFlow.none);
    });

    test('3. captureInitialAuthFlow handles /external-update route without token', () {
      final uri = Uri.parse('http://localhost:8080/#/external-update');
      AuthService.captureInitialAuthFlow(uri);

      expect(AuthService.capturedExternalUpdateToken, '');
    });

    test('4. clearCapturedExternalUpdateToken clears memory state', () {
      AuthService.setCapturedExternalUpdateTokenForTesting('token_to_clear');
      expect(AuthService.capturedExternalUpdateToken, 'token_to_clear');

      AuthService.clearCapturedExternalUpdateToken();
      expect(AuthService.capturedExternalUpdateToken, isNull);
    });
  });

  group('E. UI & Widget Tests: ExternalActionUpdateScreen', () {
    testWidgets('1. Renders Action details, contractor header, progress and form fields', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));

      await tester.pumpWidget(
        MaterialApp(
          home: ExternalActionUpdateScreen(
            token: testRawToken,
            initialPayload: testPayload,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Branding & badges
      expect(find.text('ActionFlow'), findsWidgets);
      expect(find.text('Contractor Portal'), findsOneWidget);
      expect(find.textContaining('Secure External Access'), findsOneWidget);

      // Action details
      expect(find.text('ACT-2026-0042'), findsOneWidget);
      expect(find.text('Replace damaged scaffolding planks on Tower B'), findsOneWidget);
      expect(find.textContaining('Sobha Constructions'), findsOneWidget);
      expect(find.textContaining('Robert Scaffolding Contractor'), findsOneWidget);
      expect(find.textContaining('Apex Scaffolding Services'), findsOneWidget);

      // Form fields
      expect(find.text('Submit Work Update'), findsOneWidget);
      expect(find.text('Work Update Notes / Evidence *'), findsOneWidget);
      expect(find.text('Submit Progress Update'), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('2. Status dropdown does NOT allow selecting "Closed"', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));

      await tester.pumpWidget(
        MaterialApp(
          home: ExternalActionUpdateScreen(
            token: testRawToken,
            initialPayload: testPayload,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open the status dropdown
      final dropdownFinder = find.byType(DropdownButtonFormField<String>);
      expect(dropdownFinder, findsOneWidget);
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      // 'Closed' must NEVER be an available option
      expect(find.text('Closed'), findsNothing);

      // Allowed options must be visible
      expect(find.text('In Progress'), findsWidgets);
      expect(find.text('Pending Review'), findsWidgets);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('3. Form validation requires work notes before submission', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));

      await tester.pumpWidget(
        MaterialApp(
          home: ExternalActionUpdateScreen(
            token: testRawToken,
            initialPayload: testPayload,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap submit with empty notes
      final submitButton = find.text('Submit Progress Update');
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // Validation error message appears
      expect(find.text('Please provide update notes describing your progress.'), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('4. Submitting valid form displays clear success confirmation screen', (tester) async {
      MockExternalActionStore.instance.registerToken(
        rawToken: testRawToken,
        payload: testPayload,
      );

      await tester.binding.setSurfaceSize(const Size(1200, 1000));

      await tester.pumpWidget(
        MaterialApp(
          home: ExternalActionUpdateScreen(
            token: testRawToken,
            initialPayload: testPayload,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter work notes
      final textFormField = find.byType(TextFormField);
      await tester.ensureVisible(textFormField);
      await tester.enterText(
        textFormField,
        'Completed scaffolding plank replacements on 4th floor. Tested with safety tags.',
      );
      await tester.pumpAndSettle();

      // Tap submit
      final submitButton = find.text('Submit Progress Update');
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // Clear success screen is shown
      expect(find.text('Progress Update Submitted Successfully'), findsOneWidget);
      expect(
        find.text('Your progress report has been saved and is now visible to the ActionFlow Manager.'),
        findsOneWidget,
      );
      expect(find.text('Submit Another Update'), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('5. Expired or invalid token displays clear security error card', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));

      // Load with an unknown token that fails to fetch
      await tester.pumpWidget(
        const MaterialApp(
          home: ExternalActionUpdateScreen(
            token: 'invalid_expired_token_000',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Error banner and instructions
      expect(find.text('Invalid Access Token'), findsOneWidget);
      expect(find.text('Retry Verification'), findsOneWidget);
      expect(find.textContaining('Please request a fresh action update link'), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });
  });
}
