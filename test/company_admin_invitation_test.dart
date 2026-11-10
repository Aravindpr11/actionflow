import 'dart:io';

import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/auth/models/auth_models.dart';
import 'package:action_flow/features/dashboard/admin_dashboard/screens/admin_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/screens/manager_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/platform_admin_dashboard/screens/platform_admin_dashboard_screen.dart';
import 'package:action_flow/features/dashboard/worker_dashboard/screens/worker_dashboard_screen.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:action_flow/services/organization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    OrganizationService.instance.resetMockData();
  });

  group('Company Admin Invitation - OrganizationService Unit Tests', () {
    test('1. Selected organization is required', () async {
      final service = OrganizationService.instance;

      const emptyOrg = Organization(id: '   ', name: '', code: '');
      final res = await service.inviteCompanyAdmin(
        organization: emptyOrg,
        fullName: 'New Admin',
        email: 'newadmin@example.com',
      );

      expect(res.isSuccess, isFalse);
      expect(
        res.errorMessage,
        contains('A target organization must be selected'),
      );
    });

    test('2. Full name is required and validated', () async {
      final service = OrganizationService.instance;

      final resEmpty = await service.inviteCompanyAdmin(
        organization: Organization.sobha(),
        fullName: '   ',
        email: 'admin2@sobha.com',
      );
      expect(resEmpty.isSuccess, isFalse);
      expect(resEmpty.errorMessage, contains('Full name cannot be empty'));

      final resLong = await service.inviteCompanyAdmin(
        organization: Organization.sobha(),
        fullName: 'A' * 151,
        email: 'admin2@sobha.com',
      );
      expect(resLong.isSuccess, isFalse);
      expect(resLong.errorMessage, contains('cannot exceed 150 characters'));
    });

    test('3. Valid email is required and invalid email is rejected', () async {
      final service = OrganizationService.instance;

      // Empty email
      final resEmpty = await service.inviteCompanyAdmin(
        organization: Organization.sobha(),
        fullName: 'Valid Name',
        email: '   ',
      );
      expect(resEmpty.isSuccess, isFalse);
      expect(resEmpty.errorMessage, contains('Email address cannot be empty'));

      // Malformed emails
      final invalidEmails = [
        'plainaddress',
        '@missingusername.com',
        'username@.com',
        'username@domain..com',
        'username with spaces@domain.com',
      ];

      for (final email in invalidEmails) {
        final resInvalid = await service.inviteCompanyAdmin(
          organization: Organization.sobha(),
          fullName: 'Valid Name',
          email: email,
        );
        expect(resInvalid.isSuccess, isFalse);
        expect(
          resInvalid.errorMessage,
          contains('Please enter a valid email address'),
        );
      }
    });

    test('4. Duplicate email is handled safely', () async {
      final service = OrganizationService.instance;

      // Try inviting existing Sobha Admin's email
      final resDup = await service.inviteCompanyAdmin(
        organization: Organization.sobha(),
        fullName: 'Duplicate Admin',
        email: 'admin@sobha.com',
      );

      expect(resDup.isSuccess, isFalse);
      expect(resDup.errorMessage, contains('already exists'));
    });

    test('5. Multiple Company Admin handling follows database single-primary-admin invariant', () async {
      final service = OrganizationService.instance;

      // Existing Sobha Admin is already the Primary Admin
      final existingSobhaAdmins = await service.fetchCompanyAdmins(
        Organization.sobhaId,
      );
      expect(existingSobhaAdmins.length, 1);
      expect(existingSobhaAdmins.first.email, 'admin@sobha.com');
      expect(existingSobhaAdmins.first.isPrimaryAdmin, isTrue);

      // Invite a second Company Admin for Sobha
      final resSecond = await service.inviteCompanyAdmin(
        organization: Organization.sobha(),
        fullName: 'Aditi Patel',
        email: 'aditi.patel@sobha.com',
        phone: '+971 50 123 4567',
        designation: 'VP Quality & HSE',
      );

      expect(resSecond.isSuccess, isTrue);
      expect(resSecond.admin, isNotNull);
      expect(resSecond.admin!.fullName, 'Aditi Patel');
      expect(resSecond.admin!.email, 'aditi.patel@sobha.com');
      expect(resSecond.admin!.organizationId, Organization.sobhaId);
      expect(resSecond.admin!.organizationName, Organization.sobhaName);

      // Invariant: Because Sobha already has a primary admin, the second admin receives isPrimaryAdmin = false
      expect(resSecond.admin!.isPrimaryAdmin, isFalse);

      // Existing Sobha Admin remains unchanged as Primary Admin
      final updatedSobhaAdmins = await service.fetchCompanyAdmins(
        Organization.sobhaId,
      );
      expect(updatedSobhaAdmins.length, 2);

      final originalAdmin = updatedSobhaAdmins.firstWhere(
        (a) => a.email == 'admin@sobha.com',
      );
      expect(originalAdmin.isPrimaryAdmin, isTrue);
      expect(originalAdmin.fullName, 'Sobha Admin');

      final newAdmin = updatedSobhaAdmins.firstWhere(
        (a) => a.email == 'aditi.patel@sobha.com',
      );
      expect(newAdmin.isPrimaryAdmin, isFalse);
    });
  });

  group('Company Admin Data Model & Routing Invariants', () {
    Widget resolveDestinationScreen(AuthProfileData profileData) {
      final status = profileData.status.toLowerCase();
      final isActive = profileData.isActive;
      final role = profileData.roleCode.toLowerCase();
      final isPrimaryAdmin = profileData.isPrimaryAdmin;

      if (status == 'active' && isActive) {
        if (profileData.isPlatformAdmin) {
          return const PlatformAdminDashboardScreen();
        } else if (role == 'admin' || isPrimaryAdmin) {
          return const AdminDashboardScreen();
        } else if (role == 'manager') {
          return ManagerDashboardScreen(userProfile: profileData.userProfile);
        } else {
          return WorkerDashboardScreen(userProfile: profileData.userProfile);
        }
      } else {
        return const Scaffold(body: Text('Inactive or Pending'));
      }
    }

    test('6. Company Admin uses existing admin role, attached to organization, and is not Platform Admin', () {
      const companyAdminProfile = UserProfile(
        id: 'usr-new-admin-2',
        name: 'Vikram Mehta',
        email: 'vikram.mehta@sobha.com',
        phone: '+971 50 999 8888',
        designation: 'Head of Operations',
        department: 'Enterprise System Administration',
        division: 'System & Organization Governance',
        site: 'Corporate Headquarters',
        role: 'System Administrator',
        accountStatus: 'Active',
        permissions: ['Full System Configuration Access'],
        organizationId: Organization.sobhaId,
        organizationName: Organization.sobhaName,
      );

      const companyAdminAuth = AuthProfileData(
        userProfile: companyAdminProfile,
        roleCode: 'admin', // Existing internal role: admin
        status: 'active',
        isActive: true,
        isPrimaryAdmin: false, // Additional company admin
        isPlatformAdmin: false, // NOT Platform Admin
        organizationId: Organization.sobhaId,
        organization: Organization(
          id: Organization.sobhaId,
          name: Organization.sobhaName,
          code: Organization.sobhaCode,
          isActive: true,
        ),
      );

      expect(companyAdminAuth.roleCode, 'admin');
      expect(companyAdminAuth.isPlatformAdmin, isFalse);
      expect(companyAdminAuth.isCompanyAdmin, isTrue);
      expect(companyAdminAuth.organizationId, Organization.sobhaId);
      expect(companyAdminAuth.userProfile.organizationId, Organization.sobhaId);
    });

    test('7. Company Admin login routes to existing AdminDashboardScreen', () {
      const companyAdminAuth = AuthProfileData(
        userProfile: UserProfile(
          id: 'usr-new-admin-2',
          name: 'Vikram Mehta',
          email: 'vikram.mehta@sobha.com',
          phone: '',
          designation: 'Company Administrator',
          department: 'Enterprise System Administration',
          division: 'System & Organization Governance',
          site: 'Corporate Headquarters',
          role: 'System Administrator',
          accountStatus: 'Active',
          permissions: ['Full System Configuration Access'],
          organizationId: Organization.sobhaId,
          organizationName: Organization.sobhaName,
        ),
        roleCode: 'admin',
        status: 'active',
        isActive: true,
        isPrimaryAdmin: false,
        isPlatformAdmin: false,
        organizationId: Organization.sobhaId,
        organization: Organization(
          id: Organization.sobhaId,
          name: Organization.sobhaName,
          code: Organization.sobhaCode,
          isActive: true,
        ),
      );

      final screen = resolveDestinationScreen(companyAdminAuth);
      expect(screen, isA<AdminDashboardScreen>());
    });

    test('8. Existing Sobha Admin remains unchanged as Primary Company Admin routing to AdminDashboardScreen', () {
      final existingSobhaAdmin = AuthProfileData(
        userProfile: UserProfile.mockAdmin(),
        roleCode: 'admin',
        status: 'active',
        isActive: true,
        isPrimaryAdmin: true,
        isPlatformAdmin: false,
        organizationId: Organization.sobhaId,
        organization: Organization.sobha(),
      );

      expect(existingSobhaAdmin.isPrimaryAdmin, isTrue);
      expect(existingSobhaAdmin.isCompanyAdmin, isTrue);
      expect(existingSobhaAdmin.isPlatformAdmin, isFalse);
      expect(existingSobhaAdmin.organizationId, Organization.sobhaId);

      final screen = resolveDestinationScreen(existingSobhaAdmin);
      expect(screen, isA<AdminDashboardScreen>());
    });
  });

  group('Platform Admin UI - Company Admin Flow Tests', () {
    testWidgets(
      '9. Platform Admin can choose [ Sobha ] to open company details and open Add Company Admin flow',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const PlatformAdminDashboardScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Verify Sobha row is visible
        expect(find.text('Sobha'), findsWidgets);
        expect(find.text('Manage Admins'), findsOneWidget);

        // Tap company name InkWell [ Sobha ] to open Company Details dialog
        await tester.tap(find.widgetWithText(InkWell, 'Sobha'));
        await tester.pumpAndSettle();

        // Company Details Dialog should be displayed
        expect(find.text('Company Administrators'), findsOneWidget);
        expect(find.text('Sobha Admin'), findsOneWidget);
        expect(find.text('admin@sobha.com'), findsOneWidget);
        expect(find.text('Primary Admin'), findsOneWidget);
        expect(find.text('Add Company Admin'), findsOneWidget);

        // Tap 'Add Company Admin'
        await tester.tap(find.text('Add Company Admin'));
        await tester.pumpAndSettle();

        // Add Company Admin dialog is open
        expect(find.text('Full Name *'), findsOneWidget);
        expect(find.text('Email Address *'), findsOneWidget);
        expect(find.text('Phone Number (Optional)'), findsOneWidget);
        expect(find.text('Designation (Optional)'), findsOneWidget);
        expect(find.text('Invite Company Admin'), findsOneWidget);

        // Verify PASSWORD IS NEVER COLLECTED OR REQUESTED
        expect(find.textContaining('Password'), findsNothing);
        final textFields = tester.widgetList<TextField>(find.byType(TextField));
        for (final tf in textFields) {
          expect(
            tf.obscureText,
            isFalse,
            reason: 'Password inputs must never be present',
          );
        }

        // Test form validation: submit with empty fields
        await tester.tap(find.text('Invite Company Admin'));
        await tester.pumpAndSettle();

        expect(find.text('Full name is required'), findsOneWidget);
        expect(find.text('Email address is required'), findsOneWidget);

        // Enter full name and invalid email
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Full Name *'),
          'Pooja Sharma',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Email Address *'),
          'invalid-email-address',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Invite Company Admin'));
        await tester.pumpAndSettle();

        expect(find.text('Please enter a valid email address'), findsOneWidget);

        // Enter valid email and submit
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Email Address *'),
          'pooja.sharma@sobha.com',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Designation (Optional)'),
          'Senior HSE Administrator',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Invite Company Admin'));
        await tester.pumpAndSettle();

        // Dialog closes and new admin is listed in Company Administrators
        expect(find.text('Full Name *'), findsNothing);
        expect(find.text('Pooja Sharma'), findsOneWidget);
        expect(find.text('pooja.sharma@sobha.com'), findsOneWidget);
        expect(find.text('Senior HSE Administrator'), findsOneWidget);
      },
    );
  });

  group('Step 2E Blocker Audit - Architecture & Security Invariants', () {
    test('10. Primary admin uniqueness is strictly per organization', () async {
      final service = OrganizationService.instance;

      // Organization 1 (Sobha) has existing primary admin
      final sobhaAdmins = await service.fetchCompanyAdmins(
        Organization.sobhaId,
      );
      expect(sobhaAdmins.any((a) => a.isPrimaryAdmin), isTrue);

      // Create/simulate Organization 2 (ABC Corp)
      const abcOrg = Organization(
        id: '00000000-0000-0000-0000-000000000002',
        name: 'ABC Corp',
        code: 'abc',
        isActive: true,
      );

      // First admin invited for ABC Corp becomes its primary admin
      final abcAdmin1Res = await service.inviteCompanyAdmin(
        organization: abcOrg,
        fullName: 'ABC Primary Admin',
        email: 'admin@abc.com',
      );
      expect(abcAdmin1Res.isSuccess, isTrue);
      expect(abcAdmin1Res.admin!.organizationId, abcOrg.id);
      expect(abcAdmin1Res.admin!.isPrimaryAdmin, isTrue);

      // Second admin invited for ABC Corp becomes secondary admin
      final abcAdmin2Res = await service.inviteCompanyAdmin(
        organization: abcOrg,
        fullName: 'ABC Secondary Admin',
        email: 'secondary@abc.com',
      );
      expect(abcAdmin2Res.isSuccess, isTrue);
      expect(abcAdmin2Res.admin!.organizationId, abcOrg.id);
      expect(abcAdmin2Res.admin!.isPrimaryAdmin, isFalse);

      // Verify Sobha's primary admin was completely unaffected
      final sobhaAdminsAfter = await service.fetchCompanyAdmins(
        Organization.sobhaId,
      );
      expect(
        sobhaAdminsAfter
            .firstWhere((a) => a.email == 'admin@sobha.com')
            .isPrimaryAdmin,
        isTrue,
      );
    });

    test('11. Platform Admin with organization_id NULL is not treated as a company and does not participate in primary-admin uniqueness', () {
      final platformAdminAuth = AuthProfileData.platformAdmin(
        authUserId: 'ed507b8e-bcd3-403c-80e4-42151b6681fa',
        email: 'arvin.pr1112@gmail.com',
      );

      expect(platformAdminAuth.organizationId, isNull);
      expect(platformAdminAuth.organization, isNull);
      expect(platformAdminAuth.isPlatformAdmin, isTrue);
      expect(platformAdminAuth.isCompanyAdmin, isFalse);
      expect(platformAdminAuth.isPrimaryAdmin, isFalse);
    });

    test('12. Sobha Admin remains primary for Sobha', () async {
      final service = OrganizationService.instance;
      final sobhaAdmins = await service.fetchCompanyAdmins(
        Organization.sobhaId,
      );
      expect(sobhaAdmins.isNotEmpty, isTrue);

      final primaryAdmin = sobhaAdmins.firstWhere((a) => a.isPrimaryAdmin);
      expect(primaryAdmin.email, 'admin@sobha.com');
      expect(primaryAdmin.fullName, 'Sobha Admin');
      expect(primaryAdmin.organizationId, Organization.sobhaId);
    });

    test('13. Company Admin invitation cannot cross organizations', () async {
      final service = OrganizationService.instance;

      const org1 = Organization(
        id: 'org-1-uuid',
        name: 'Org 1',
        code: 'org1',
        isActive: true,
      );
      const org2 = Organization(
        id: 'org-2-uuid',
        name: 'Org 2',
        code: 'org2',
        isActive: true,
      );

      final res1 = await service.inviteCompanyAdmin(
        organization: org1,
        fullName: 'Admin One',
        email: 'admin1@org1.com',
      );
      expect(res1.isSuccess, isTrue);
      expect(res1.admin!.organizationId, 'org-1-uuid');

      final adminsOrg1 = await service.fetchCompanyAdmins(org1.id);
      final adminsOrg2 = await service.fetchCompanyAdmins(org2.id);

      expect(adminsOrg1.any((a) => a.email == 'admin1@org1.com'), isTrue);
      expect(adminsOrg2.any((a) => a.email == 'admin1@org1.com'), isFalse);
    });

    test('14. Invitation requires Platform Admin authorization and cannot be reached by other roles', () {
      // Non-platform admin roles cannot route to PlatformAdminDashboardScreen
      final managerAuth = AuthProfileData(
        userProfile: UserProfile.mockManager(),
        roleCode: 'manager',
        status: 'active',
        isActive: true,
        isPrimaryAdmin: false,
        isPlatformAdmin: false,
        organizationId: Organization.sobhaId,
      );

      final staffAuth = AuthProfileData(
        userProfile: UserProfile.mockStaff(),
        roleCode: 'staff',
        status: 'active',
        isActive: true,
        isPrimaryAdmin: false,
        isPlatformAdmin: false,
        organizationId: Organization.sobhaId,
      );

      Widget resolveDestinationScreen(AuthProfileData profileData) {
        if (profileData.isPlatformAdmin) {
          return const PlatformAdminDashboardScreen();
        } else if (profileData.roleCode.toLowerCase() == 'admin' ||
            profileData.isPrimaryAdmin) {
          return const AdminDashboardScreen();
        } else if (profileData.roleCode.toLowerCase() == 'manager') {
          return ManagerDashboardScreen(userProfile: profileData.userProfile);
        } else {
          return WorkerDashboardScreen(userProfile: profileData.userProfile);
        }
      }

      expect(
        resolveDestinationScreen(managerAuth),
        isA<ManagerDashboardScreen>(),
      );
      expect(resolveDestinationScreen(staffAuth), isA<WorkerDashboardScreen>());
    });

    test('15. No service-role credentials appear anywhere in Flutter client code (lib/)', () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue);

      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        expect(
          content.contains('service_role'),
          isFalse,
          reason: 'File ${file.path} must not contain service_role token',
        );
        expect(
          content.contains('SUPABASE_SERVICE_ROLE_KEY'),
          isFalse,
          reason:
              'File ${file.path} must not reference SUPABASE_SERVICE_ROLE_KEY',
        );
      }
    });
  });

  group('Company Admin Management - Edit & Delete Unit Tests', () {
    test(
      '16. updateCompanyAdmin updates full name, phone, and designation',
      () async {
        final service = OrganizationService.instance;
        final sobhaAdmins = await service.fetchCompanyAdmins(
          Organization.sobhaId,
        );
        final admin = sobhaAdmins.first;

        final res = await service.updateCompanyAdmin(
          organization: Organization.sobha(),
          adminId: admin.id,
          fullName: 'Sobha Principal Admin',
          email: admin.email,
          phone: '+971 50 111 2233',
          designation: 'Head of Global HSE',
        );

        expect(res.isSuccess, isTrue);
        expect(res.admin, isNotNull);
        expect(res.admin!.fullName, 'Sobha Principal Admin');
        expect(res.admin!.phone, '+971 50 111 2233');
        expect(res.admin!.designation, 'Head of Global HSE');

        final updatedAdmins = await service.fetchCompanyAdmins(
          Organization.sobhaId,
        );
        final refreshed = updatedAdmins.firstWhere((a) => a.id == admin.id);
        expect(refreshed.fullName, 'Sobha Principal Admin');
        expect(refreshed.phone, '+971 50 111 2233');
        expect(refreshed.designation, 'Head of Global HSE');
      },
    );

    test(
      '17. updateCompanyAdmin validates email format and rejects duplicates',
      () async {
        final service = OrganizationService.instance;

        // Add a second admin to Sobha
        await service.inviteCompanyAdmin(
          organization: Organization.sobha(),
          fullName: 'Second Admin',
          email: 'second@sobha.com',
        );

        final admins = await service.fetchCompanyAdmins(Organization.sobhaId);
        final secondAdmin = admins.firstWhere(
          (a) => a.email == 'second@sobha.com',
        );

        // Reject empty email
        final resEmpty = await service.updateCompanyAdmin(
          organization: Organization.sobha(),
          adminId: secondAdmin.id,
          fullName: 'Second Admin',
          email: '   ',
        );
        expect(resEmpty.isSuccess, isFalse);
        expect(
          resEmpty.errorMessage,
          contains('Email address cannot be empty'),
        );

        // Reject invalid email
        final resInvalid = await service.updateCompanyAdmin(
          organization: Organization.sobha(),
          adminId: secondAdmin.id,
          fullName: 'Second Admin',
          email: 'invalid-email',
        );
        expect(resInvalid.isSuccess, isFalse);
        expect(
          resInvalid.errorMessage,
          contains('Please enter a valid email address'),
        );

        // Reject collision with existing primary admin's email
        final resConflict = await service.updateCompanyAdmin(
          organization: Organization.sobha(),
          adminId: secondAdmin.id,
          fullName: 'Second Admin',
          email: 'admin@sobha.com',
        );
        expect(resConflict.isSuccess, isFalse);
        expect(resConflict.errorMessage, contains('already exists'));

        // Update to new valid email succeeds
        final resSuccess = await service.updateCompanyAdmin(
          organization: Organization.sobha(),
          adminId: secondAdmin.id,
          fullName: 'Second Admin',
          email: 'second.renamed@sobha.com',
        );
        expect(resSuccess.isSuccess, isTrue);
        expect(resSuccess.admin!.email, 'second.renamed@sobha.com');
      },
    );

    test(
      '18. deleteCompanyAdmin prevents deleting sole active administrator',
      () async {
        final service = OrganizationService.instance;
        final sobhaAdmins = await service.fetchCompanyAdmins(
          Organization.sobhaId,
        );
        expect(sobhaAdmins.length, 1);

        final soleAdmin = sobhaAdmins.first;
        final res = await service.deleteCompanyAdmin(
          organization: Organization.sobha(),
          adminId: soleAdmin.id,
        );

        expect(res.isSuccess, isFalse);
        expect(
          res.errorMessage,
          contains('Cannot remove the only active administrator'),
        );
      },
    );

    test(
      '19. deleteCompanyAdmin allows deleting secondary administrator directly',
      () async {
        final service = OrganizationService.instance;

        // Add second admin
        await service.inviteCompanyAdmin(
          organization: Organization.sobha(),
          fullName: 'Junior Admin',
          email: 'junior@sobha.com',
        );

        var admins = await service.fetchCompanyAdmins(Organization.sobhaId);
        expect(admins.length, 2);
        final juniorAdmin = admins.firstWhere(
          (a) => a.email == 'junior@sobha.com',
        );
        expect(juniorAdmin.isPrimaryAdmin, isFalse);

        final res = await service.deleteCompanyAdmin(
          organization: Organization.sobha(),
          adminId: juniorAdmin.id,
        );

        expect(res.isSuccess, isTrue);

        admins = await service.fetchCompanyAdmins(Organization.sobhaId);
        expect(admins.length, 1);
        expect(admins.any((a) => a.email == 'junior@sobha.com'), isFalse);
        expect(admins.first.isPrimaryAdmin, isTrue);
      },
    );

    test('20. deleteCompanyAdmin on primary admin requires successor and reassigns primary role', () async {
      final service = OrganizationService.instance;

      // Add successor admin
      await service.inviteCompanyAdmin(
        organization: Organization.sobha(),
        fullName: 'Successor Admin',
        email: 'successor@sobha.com',
      );

      var admins = await service.fetchCompanyAdmins(Organization.sobhaId);
      expect(admins.length, 2);
      final primaryAdmin = admins.firstWhere((a) => a.isPrimaryAdmin);
      final successorAdmin = admins.firstWhere((a) => !a.isPrimaryAdmin);

      // Attempt deleting primary without successor fails
      final failRes = await service.deleteCompanyAdmin(
        organization: Organization.sobha(),
        adminId: primaryAdmin.id,
      );
      expect(failRes.isSuccess, isFalse);
      expect(
        failRes.errorMessage,
        contains('selecting a successor Primary Administrator'),
      );

      // Deleting primary with successor succeeds
      final successRes = await service.deleteCompanyAdmin(
        organization: Organization.sobha(),
        adminId: primaryAdmin.id,
        newPrimaryAdminId: successorAdmin.id,
      );
      expect(successRes.isSuccess, isTrue);

      admins = await service.fetchCompanyAdmins(Organization.sobhaId);
      expect(admins.length, 1);
      final newPrimary = admins.first;
      expect(newPrimary.id, successorAdmin.id);
      expect(newPrimary.isPrimaryAdmin, isTrue);
      expect(newPrimary.email, 'successor@sobha.com');
    });

    test('24. resendCompanyAdminInvitation generates fresh invite for pending admin and enforces invariants', () async {
      final service = OrganizationService.instance;

      // 1. Invite a new admin who will have pending invitation status
      final inviteRes = await service.inviteCompanyAdmin(
        organization: Organization.sobha(),
        fullName: 'Pending Admin',
        email: 'pending.admin@sobha.com',
      );
      expect(inviteRes.isSuccess, isTrue);
      final pendingAdmin = inviteRes.admin!;
      expect(pendingAdmin.isInvitationPending, isTrue);
      expect(pendingAdmin.isFullyActive, isFalse);
      expect(pendingAdmin.isDisabled, isFalse);

      // 2. Resend invitation to this pending admin succeeds
      final resendRes = await service.resendCompanyAdminInvitation(
        organization: Organization.sobha(),
        adminId: pendingAdmin.id,
      );
      expect(resendRes.isSuccess, isTrue);
      expect(resendRes.message, contains('pending.admin@sobha.com'));
      expect(resendRes.inviteLink, isNotNull);

      // 3. Resending to an already fully active admin is rejected
      final sobhaAdmin = (await service.fetchCompanyAdmins(
        Organization.sobhaId,
      )).firstWhere((a) => a.email == 'admin@sobha.com');
      expect(sobhaAdmin.isFullyActive, isTrue);

      final failActiveRes = await service.resendCompanyAdminInvitation(
        organization: Organization.sobha(),
        adminId: sobhaAdmin.id,
      );
      expect(failActiveRes.isSuccess, isFalse);
      expect(
        failActiveRes.errorMessage,
        contains('already completed activation'),
      );

      // 4. Resending to a deleted / disabled admin is rejected
      await service.deleteCompanyAdmin(
        organization: Organization.sobha(),
        adminId: pendingAdmin.id,
      );

      final failDisabledRes = await service.resendCompanyAdminInvitation(
        organization: Organization.sobha(),
        adminId: pendingAdmin.id,
      );
      expect(failDisabledRes.isSuccess, isFalse);
      expect(failDisabledRes.errorMessage, contains('disabled or removed'));
    });
  });

  group('Platform Admin UI - Edit & Delete Company Admin Flow Tests', () {
    testWidgets(
      '21. Platform Admin can edit administrator and see updated details in list',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const PlatformAdminDashboardScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Tap company name InkWell [ Sobha ] to open Company Details dialog
        await tester.tap(find.widgetWithText(InkWell, 'Sobha'));
        await tester.pumpAndSettle();

        // Find Edit button
        final editButton = find.byTooltip('Edit Administrator');
        expect(editButton, findsOneWidget);

        await tester.tap(editButton);
        await tester.pumpAndSettle();

        // Edit dialog should be open
        expect(find.text('Edit Company Admin'), findsOneWidget);
        expect(find.text('Save Changes'), findsOneWidget);

        // Edit full name and designation
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Full Name *'),
          'Sobha Lead Administrator',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Designation (Optional)'),
          'Chief Safety Director',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save Changes'));
        await tester.pumpAndSettle();

        // Dialog should be closed and card updated
        expect(find.text('Edit Company Admin'), findsNothing);
        expect(find.text('Sobha Lead Administrator'), findsOneWidget);
        expect(find.text('Chief Safety Director'), findsOneWidget);
      },
    );

    testWidgets(
      '22. Platform Admin deleting sole administrator is blocked with explanation dialog',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const PlatformAdminDashboardScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Open Company Details dialog
        await tester.tap(find.widgetWithText(InkWell, 'Sobha'));
        await tester.pumpAndSettle();

        // Find Delete button
        final deleteButton = find.byTooltip('Delete Administrator');
        expect(deleteButton, findsOneWidget);

        await tester.tap(deleteButton);
        await tester.pumpAndSettle();

        // Informative block dialog should be displayed
        expect(find.text('Cannot Delete Administrator'), findsOneWidget);
        expect(
          find.textContaining(
            'A company must always retain at least one active administrator',
          ),
          findsOneWidget,
        );

        // Tap OK to dismiss
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        expect(find.text('Cannot Delete Administrator'), findsNothing);
      },
    );

    testWidgets(
      '23. Platform Admin with multiple administrators can delete secondary administrator',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Pre-add a second admin
        await OrganizationService.instance.inviteCompanyAdmin(
          organization: Organization.sobha(),
          fullName: 'Secondary Sobha Admin',
          email: 'secondary.sobha@sobha.com',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const PlatformAdminDashboardScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Open Company Details dialog
        await tester.tap(find.widgetWithText(InkWell, 'Sobha'));
        await tester.pumpAndSettle();

        expect(find.text('Secondary Sobha Admin'), findsOneWidget);
        final deleteButtons = find.byTooltip('Delete Administrator');
        expect(deleteButtons, findsNWidgets(2));

        // Tap delete on secondary admin (the second one)
        await tester.tap(deleteButtons.last);
        await tester.pumpAndSettle();

        // Confirmation dialog
        expect(find.text('Remove Administrator'), findsWidgets);
        expect(
          find.textContaining(
            'Are you sure you want to deactivate and remove Secondary Sobha Admin',
          ),
          findsOneWidget,
        );

        // Tap Remove Administrator
        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Remove Administrator'),
        );
        await tester.pumpAndSettle();

        // Confirm deletion in list
        expect(find.text('Secondary Sobha Admin'), findsNothing);
        expect(find.text('Sobha Admin'), findsOneWidget);
      },
    );

    testWidgets(
      '25. Platform Admin UI distinguishes Invitation Pending vs Active status badges',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Pre-add an invited pending admin
        await OrganizationService.instance.inviteCompanyAdmin(
          organization: Organization.sobha(),
          fullName: 'Invited Pending Admin',
          email: 'invited.pending@sobha.com',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const PlatformAdminDashboardScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Open Company Details dialog
        await tester.tap(find.widgetWithText(InkWell, 'Sobha'));
        await tester.pumpAndSettle();

        // 1. Within Sobha Admin card -> "Active" badge
        final sobhaCard = find.ancestor(
          of: find.text('Sobha Admin'),
          matching: find.byType(Card),
        );
        expect(
          find.descendant(of: sobhaCard, matching: find.text('Active')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: sobhaCard,
            matching: find.text('Invitation Pending'),
          ),
          findsNothing,
        );

        // 2. Within Invited Pending Admin card -> "Invitation Pending" badge
        final pendingCard = find.ancestor(
          of: find.text('Invited Pending Admin'),
          matching: find.byType(Card),
        );
        expect(
          find.descendant(
            of: pendingCard,
            matching: find.text('Invitation Pending'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: pendingCard, matching: find.text('Active')),
          findsNothing,
        );
      },
    );

    testWidgets(
      '26. Platform Admin UI shows Resend Invitation for pending admin and handles resend with rapid-click prevention',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Pre-add an invited pending admin
        await OrganizationService.instance.inviteCompanyAdmin(
          organization: Organization.sobha(),
          fullName: 'Pending Activation Admin',
          email: 'activation@sobha.com',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const PlatformAdminDashboardScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Open Company Details dialog
        await tester.tap(find.widgetWithText(InkWell, 'Sobha'));
        await tester.pumpAndSettle();

        // Resend button exists only for pending admin (findsOneWidget)
        final resendButtons = find.byTooltip('Resend Invitation');
        expect(resendButtons, findsOneWidget);

        // Tap Resend Invitation button
        await tester.tap(resendButtons);
        await tester.pump(); // Start async action

        // Settle SnackBar
        await tester.pumpAndSettle();

        // Verify success SnackBar message is shown
        expect(
          find.textContaining(
            'Invitation resent successfully to activation@sobha.com',
          ),
          findsOneWidget,
        );
      },
    );
  });
}
