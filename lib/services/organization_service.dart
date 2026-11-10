import 'dart:async';

import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/models/organization_counts.dart';
import 'package:action_flow/services/platform_audit_service.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'package:action_flow/models/organization_counts.dart';

/// Result object for tenant organization creation requests.
@immutable
class OrganizationCreateResult {
  final bool isSuccess;
  final Organization? organization;
  final String? errorMessage;

  const OrganizationCreateResult.success(this.organization)
    : isSuccess = true,
      errorMessage = null;

  const OrganizationCreateResult.failure(this.errorMessage)
    : isSuccess = false,
      organization = null;
}

/// Result object for tenant organization deletion requests.
@immutable
class OrganizationDeleteResult {
  final bool isSuccess;
  final String? message;
  final String? errorMessage;
  final bool isPartial;
  final List<String> failedAuthUserIds;

  const OrganizationDeleteResult.success({this.message})
    : isSuccess = true,
      errorMessage = null,
      isPartial = false,
      failedAuthUserIds = const [];

  const OrganizationDeleteResult.partial({
    required this.message,
    this.failedAuthUserIds = const [],
  }) : isSuccess = false,
       errorMessage = message,
       isPartial = true;

  const OrganizationDeleteResult.failure(this.errorMessage)
    : isSuccess = false,
      message = null,
      isPartial = false,
      failedAuthUserIds = const [];
}

/// Represents a company administrator summary profile for tenant governance.
@immutable
class CompanyAdminSummary {
  final String id;
  final String fullName;
  final String email;
  final String? phone;
  final String? designation;
  final String organizationId;
  final String organizationName;
  final bool isPrimaryAdmin;
  final bool isActive;
  final String status; // 'active', 'invited', 'pending_setup'
  final DateTime? createdAt;

  const CompanyAdminSummary({
    required this.id,
    required this.fullName,
    required this.email,
    this.phone,
    this.designation,
    required this.organizationId,
    required this.organizationName,
    this.isPrimaryAdmin = false,
    this.isActive = true,
    this.status = 'active',
    this.createdAt,
  });

  factory CompanyAdminSummary.fromJson(Map<String, dynamic> json) {
    return CompanyAdminSummary(
      id: json['id']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString(),
      designation: json['designation']?.toString(),
      organizationId: json['organization_id']?.toString() ?? '',
      organizationName: json['organization_name']?.toString() ?? '',
      isPrimaryAdmin: json['is_primary_admin'] == true,
      isActive: json['is_active'] != false,
      status: json['status']?.toString() ?? 'active',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'full_name': fullName,
    'email': email,
    if (phone != null) 'phone': phone,
    if (designation != null) 'designation': designation,
    'organization_id': organizationId,
    'organization_name': organizationName,
    'is_primary_admin': isPrimaryAdmin,
    'is_active': isActive,
    'status': status,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
  };

  CompanyAdminSummary copyWith({
    String? id,
    String? fullName,
    String? email,
    String? phone,
    String? designation,
    String? organizationId,
    String? organizationName,
    bool? isPrimaryAdmin,
    bool? isActive,
    String? status,
    DateTime? createdAt,
  }) {
    return CompanyAdminSummary(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      designation: designation ?? this.designation,
      organizationId: organizationId ?? this.organizationId,
      organizationName: organizationName ?? this.organizationName,
      isPrimaryAdmin: isPrimaryAdmin ?? this.isPrimaryAdmin,
      isActive: isActive ?? this.isActive,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// True if this administrator was invited and has not completed activation.
  bool get isInvitationPending =>
      !isDisabled &&
      (status == 'invited' ||
          status == 'pending_approval' ||
          status == 'pending_setup');

  /// True if this administrator is active and confirmed.
  bool get isFullyActive => isActive && status == 'active';

  /// True if this administrator is inactive, suspended, or disabled.
  bool get isDisabled =>
      !isActive || status == 'inactive' || status == 'suspended';
}

/// Result object for company admin invitation resend requests.
@immutable
class CompanyAdminResendResult {
  final bool isSuccess;
  final String? message;
  final String? inviteLink;
  final String? errorMessage;

  const CompanyAdminResendResult.success({this.message, this.inviteLink})
    : isSuccess = true,
      errorMessage = null;

  const CompanyAdminResendResult.failure(this.errorMessage)
    : isSuccess = false,
      message = null,
      inviteLink = null;
}

/// Result object for company admin update requests.
@immutable
class CompanyAdminUpdateResult {
  final bool isSuccess;
  final CompanyAdminSummary? admin;
  final String? errorMessage;

  const CompanyAdminUpdateResult.success(this.admin)
    : isSuccess = true,
      errorMessage = null;

  const CompanyAdminUpdateResult.failure(this.errorMessage)
    : isSuccess = false,
      admin = null;
}

/// Result object for company admin deletion/removal requests.
@immutable
class CompanyAdminDeleteResult {
  final bool isSuccess;
  final String? errorMessage;

  const CompanyAdminDeleteResult.success()
    : isSuccess = true,
      errorMessage = null;

  const CompanyAdminDeleteResult.failure(this.errorMessage) : isSuccess = false;
}

/// Result object for company admin invitation requests.
@immutable
class CompanyAdminInvitationResult {
  final bool isSuccess;
  final CompanyAdminSummary? admin;
  final String? errorMessage;
  final bool isBackendRequired;

  const CompanyAdminInvitationResult.success(this.admin)
    : isSuccess = true,
      errorMessage = null,
      isBackendRequired = false;

  const CompanyAdminInvitationResult.failure(this.errorMessage)
    : isSuccess = false,
      admin = null,
      isBackendRequired = false;

  const CompanyAdminInvitationResult.backendRequired({
    required this.admin,
    required this.errorMessage,
  }) : isSuccess = false,
       isBackendRequired = true;
}

/// Service managing tenant organizations (companies) and company administrator
/// governance in ActionFlow.
/// Directly communicates with public.organizations and public.profiles in Supabase,
/// with an in-memory fallback for test environments and offline development.
class OrganizationService {
  OrganizationService({SupabaseClient? client}) : _clientOverride = client;

  static final OrganizationService instance = OrganizationService();

  final SupabaseClient? _clientOverride;

  SupabaseClient? get _client => _clientOverride ?? SupabaseConfig.clientOrNull;

  /// Internal mock storage for testing and offline development
  final List<Organization> _mockOrganizations = [
    Organization.sobha().copyWith(
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ),
  ];

  /// Internal mock storage for company admins
  final List<CompanyAdminSummary> _mockCompanyAdmins = [
    CompanyAdminSummary(
      id: 'usr-sobha-admin-1',
      fullName: 'Sobha Admin',
      email: 'admin@sobha.com',
      phone: '+971 4 000 0000',
      designation: 'Enterprise System Administrator',
      organizationId: Organization.sobhaId,
      organizationName: Organization.sobhaName,
      isPrimaryAdmin: true,
      isActive: true,
      status: 'active',
      createdAt: DateTime(2026, 1, 1),
    ),
  ];

  /// Fetches all registered tenant organizations.
  /// When Supabase is initialized, queries public.organizations ordered by created_at.
  /// Falls back to mock organizations when Supabase is not initialized.
  Future<List<Organization>> fetchOrganizations() async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      final list = List<Organization>.from(_mockOrganizations);
      list.sort((a, b) {
        if (a.createdAt == null || b.createdAt == null) return 0;
        return a.createdAt!.compareTo(b.createdAt!);
      });
      return list;
    }

    final dynamic rawData = await client
        .from('organizations')
        .select()
        .order('created_at', ascending: true);

    if (rawData == null || (rawData is List && rawData.isEmpty)) {
      return [];
    }

    return (rawData as List)
        .map((e) => Organization.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Internal mock storage for organization counts (used in unit testing)
  final Map<String, OrganizationCounts> _mockOrganizationCounts = {};

  /// Pre-configures mock counts for an organization in unit testing environments.
  @visibleForTesting
  void setMockCounts(String organizationId, OrganizationCounts counts) {
    _mockOrganizationCounts[organizationId] = counts;
  }

  /// Fetches real Supabase aggregate counts for all organizations:
  /// - Users (from public.profiles)
  /// - Departments (from public.departments)
  /// - Sites (from public.sites)
  ///
  /// Concurrently queries organization_id from all three tables without pulling unneeded fields,
  /// aggregating them by tenant ID in a single roundtrip batch.
  Future<Map<String, OrganizationCounts>> fetchOrganizationCounts() async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      if (_mockOrganizationCounts.isNotEmpty) {
        return Map.unmodifiable(_mockOrganizationCounts);
      }
      return const {};
    }

    try {
      final results = await Future.wait([
        client.from('profiles').select('organization_id'),
        client.from('departments').select('organization_id'),
        client.from('sites').select('organization_id'),
      ]);

      final userCounts = <String, int>{};
      final deptCounts = <String, int>{};
      final siteCounts = <String, int>{};

      final profiles = results[0] as List;
      for (final p in profiles) {
        if (p is Map) {
          final orgId = p['organization_id']?.toString();
          if (orgId != null && orgId.isNotEmpty) {
            userCounts[orgId] = (userCounts[orgId] ?? 0) + 1;
          }
        }
      }

      final depts = results[1] as List;
      for (final d in depts) {
        if (d is Map) {
          final orgId = d['organization_id']?.toString();
          if (orgId != null && orgId.isNotEmpty) {
            deptCounts[orgId] = (deptCounts[orgId] ?? 0) + 1;
          }
        }
      }

      final sites = results[2] as List;
      for (final s in sites) {
        if (s is Map) {
          final orgId = s['organization_id']?.toString();
          if (orgId != null && orgId.isNotEmpty) {
            siteCounts[orgId] = (siteCounts[orgId] ?? 0) + 1;
          }
        }
      }

      final allOrgIds = <String>{
        ...userCounts.keys,
        ...deptCounts.keys,
        ...siteCounts.keys,
      };

      final countsMap = <String, OrganizationCounts>{};
      for (final id in allOrgIds) {
        countsMap[id] = OrganizationCounts(
          users: userCounts[id] ?? 0,
          departments: deptCounts[id] ?? 0,
          sites: siteCounts[id] ?? 0,
        );
      }

      return countsMap;
    } catch (e) {
      debugPrint('[OrganizationService] fetchOrganizationCounts error: $e');
      rethrow;
    }
  }

  /// Fetches real Supabase aggregate counts for a specific tenant organization.
  Future<OrganizationCounts> fetchCountsForOrganization(
    String organizationId,
  ) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      return _mockOrganizationCounts[organizationId] ??
          const OrganizationCounts();
    }

    try {
      final results = await Future.wait([
        client
            .from('profiles')
            .select('id')
            .eq('organization_id', organizationId),
        client
            .from('departments')
            .select('id')
            .eq('organization_id', organizationId),
        client.from('sites').select('id').eq('organization_id', organizationId),
      ]);

      final userCount = (results[0] as List).length;
      final deptCount = (results[1] as List).length;
      final siteCount = (results[2] as List).length;

      return OrganizationCounts(
        users: userCount,
        departments: deptCount,
        sites: siteCount,
      );
    } catch (e) {
      debugPrint('[OrganizationService] fetchCountsForOrganization error: $e');
      rethrow;
    }
  }

  /// Creates a new tenant organization in public.organizations.
  /// Enforces validation:
  /// - Name cannot be empty and max 150 characters
  /// - Code cannot be empty, max 50 characters, and must match `^[a-z0-9_-]+$`
  /// Catches duplicate violations (PostgREST 23505) and returns a user-friendly error.
  Future<OrganizationCreateResult> createOrganization({
    required String name,
    required String code,
    bool isActive = true,
  }) async {
    final trimmedName = name.trim();
    final trimmedCode = code.trim().toLowerCase();

    // Validation
    if (trimmedName.isEmpty) {
      return const OrganizationCreateResult.failure(
        'Company name cannot be empty.',
      );
    }
    if (trimmedName.length > 150) {
      return const OrganizationCreateResult.failure(
        'Company name cannot exceed 150 characters.',
      );
    }
    if (trimmedCode.isEmpty) {
      return const OrganizationCreateResult.failure(
        'Company code cannot be empty.',
      );
    }
    if (trimmedCode.length > 50) {
      return const OrganizationCreateResult.failure(
        'Company code cannot exceed 50 characters.',
      );
    }

    final codeRegex = RegExp(r'^[a-z0-9_-]+$');
    if (!codeRegex.hasMatch(trimmedCode)) {
      return const OrganizationCreateResult.failure(
        'Company code can only contain lowercase letters, numbers, hyphens, and underscores (e.g. acme-corp).',
      );
    }

    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      // Check in-memory duplicates
      if (_mockOrganizations.any((o) => o.code.toLowerCase() == trimmedCode)) {
        return OrganizationCreateResult.failure(
          'An organization with code "$trimmedCode" already exists.',
        );
      }
      if (_mockOrganizations.any(
        (o) => o.name.toLowerCase() == trimmedName.toLowerCase(),
      )) {
        return OrganizationCreateResult.failure(
          'An organization with name "$trimmedName" already exists.',
        );
      }

      final newOrg = Organization(
        id: 'mock-${DateTime.now().millisecondsSinceEpoch}',
        name: trimmedName,
        code: trimmedCode,
        isActive: isActive,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      _mockOrganizations.add(newOrg);
      unawaited(
        PlatformAuditService.instance.recordAuditEvent(
          eventType: 'organization_created',
          category: 'tenancy',
          severity: 'info',
          description:
              'Organization "${newOrg.name}" created (code: ${newOrg.code})',
          organizationId: newOrg.id,
          metadata: {'code': newOrg.code, 'name': newOrg.name},
        ),
      );
      return OrganizationCreateResult.success(newOrg);
    }

    try {
      final response = await client
          .from('organizations')
          .insert({
            'name': trimmedName,
            'code': trimmedCode,
            'is_active': isActive,
          })
          .select()
          .single();

      final createdOrg = Organization.fromJson(
        Map<String, dynamic>.from(response as Map),
      );
      unawaited(
        PlatformAuditService.instance.recordAuditEvent(
          eventType: 'organization_created',
          category: 'tenancy',
          severity: 'info',
          description:
              'Organization "${createdOrg.name}" created (code: ${createdOrg.code})',
          organizationId: createdOrg.id,
          metadata: {'code': createdOrg.code, 'name': createdOrg.name},
        ),
      );
      return OrganizationCreateResult.success(createdOrg);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        final detail = '${e.message} ${e.details ?? ''}'.toLowerCase();
        if (detail.contains('code') || detail.contains('organizations_code')) {
          return OrganizationCreateResult.failure(
            'An organization with code "$trimmedCode" already exists.',
          );
        } else if (detail.contains('name') ||
            detail.contains('organizations_name') ||
            detail.contains('uq_organizations_name')) {
          return OrganizationCreateResult.failure(
            'An organization with name "$trimmedName" already exists.',
          );
        }
        return const OrganizationCreateResult.failure(
          'An organization with this name or code already exists.',
        );
      }
      return OrganizationCreateResult.failure(
        e.message.isNotEmpty
            ? e.message
            : 'Database error creating organization.',
      );
    } catch (e) {
      return OrganizationCreateResult.failure(
        'Failed to create organization: $e',
      );
    }
  }

  /// Fetches all designated Company Administrators for a specific tenant organization.
  /// By default, returns active and pending administrators. Set [includeInactive]
  /// to true to include deactivated or disabled administrators.
  Future<List<CompanyAdminSummary>> fetchCompanyAdmins(
    String organizationId, {
    bool includeInactive = false,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      return List<CompanyAdminSummary>.unmodifiable(
        _mockCompanyAdmins.where(
          (a) =>
              a.organizationId == organizationId &&
              (includeInactive || a.isActive),
        ),
      );
    }

    try {
      // 1. Attempt to fetch via manage-company-admin Edge Function
      // to enrich with live Auth confirmation status (Invitation Pending vs Active)
      try {
        final response = await client.functions.invoke(
          'manage-company-admin',
          body: {
            'action': 'list_admins',
            'organization_id': organizationId,
            'include_inactive': includeInactive,
          },
        );
        if (response.status == 200 && response.data is List) {
          return (response.data as List).map((e) {
            return CompanyAdminSummary.fromJson(
              Map<String, dynamic>.from(e as Map),
            );
          }).toList();
        }
      } catch (_) {
        // Fall back to direct database query
      }

      var query = client
          .from('profiles')
          .select(
            'id, full_name, email, phone, designation, organization_id, is_primary_admin, is_active, status, created_at, roles!inner(code)',
          )
          .eq('organization_id', organizationId)
          .eq('roles.code', 'admin');

      if (!includeInactive) {
        query = query.eq('is_active', true);
      }

      final dynamic rawData = await query.order('created_at', ascending: true);

      if (rawData == null || (rawData is List && rawData.isEmpty)) {
        return [];
      }

      return (rawData as List).map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        return CompanyAdminSummary(
          id: map['id']?.toString() ?? '',
          fullName: map['full_name']?.toString() ?? '',
          email: map['email']?.toString() ?? '',
          phone: map['phone']?.toString(),
          designation: map['designation']?.toString(),
          organizationId: map['organization_id']?.toString() ?? organizationId,
          organizationName: '',
          isPrimaryAdmin: map['is_primary_admin'] == true,
          isActive: map['is_active'] != false,
          status: map['status']?.toString() ?? 'active',
          createdAt: map['created_at'] != null
              ? DateTime.tryParse(map['created_at'].toString())
              : null,
        );
      }).toList();
    } catch (_) {
      // Return empty if offline or query fails
      return [];
    }
  }

  /// Invites/provisions a new Company Administrator for a specific tenant organization.
  ///
  /// Enforces:
  /// - Target organization is required
  /// - Full Name is required and max 150 characters
  /// - Email is required and must follow standard email syntax
  /// - Phone and Designation are optional
  /// - Password is NEVER collected or persisted by Flutter
  /// - Assigns the existing internal 'admin' role
  /// - organization_id is permanently bound to the selected company
  /// - Respects the existing single-primary-admin database invariant
  Future<CompanyAdminInvitationResult> inviteCompanyAdmin({
    required Organization organization,
    required String fullName,
    required String email,
    String? phone,
    String? designation,
  }) async {
    final trimmedName = fullName.trim();
    final trimmedEmail = email.trim().toLowerCase();
    final trimmedPhone = phone?.trim();
    final trimmedDesignation = designation?.trim();

    // 1. Validation
    if (organization.id.trim().isEmpty) {
      return const CompanyAdminInvitationResult.failure(
        'A target organization must be selected.',
      );
    }
    if (trimmedName.isEmpty) {
      return const CompanyAdminInvitationResult.failure(
        'Full name cannot be empty.',
      );
    }
    if (trimmedName.length > 150) {
      return const CompanyAdminInvitationResult.failure(
        'Full name cannot exceed 150 characters.',
      );
    }
    if (trimmedEmail.isEmpty) {
      return const CompanyAdminInvitationResult.failure(
        'Email address cannot be empty.',
      );
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(trimmedEmail)) {
      return const CompanyAdminInvitationResult.failure(
        'Please enter a valid email address.',
      );
    }

    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      // In-memory mock checks and duplicate detection
      if (_mockCompanyAdmins.any(
        (a) => a.email.toLowerCase() == trimmedEmail,
      )) {
        return CompanyAdminInvitationResult.failure(
          'A user or administrator with email "$trimmedEmail" already exists.',
        );
      }

      // Check existing company admin in this organization to determine is_primary_admin
      // Invariant: exactly one active primary admin per company
      final orgAdmins = _mockCompanyAdmins
          .where((a) => a.organizationId == organization.id)
          .toList();
      final hasPrimaryAdmin = orgAdmins.any(
        (a) => a.isPrimaryAdmin && a.isActive,
      );

      final newAdmin = CompanyAdminSummary(
        id: 'mock-admin-${DateTime.now().millisecondsSinceEpoch}',
        fullName: trimmedName,
        email: trimmedEmail,
        phone: trimmedPhone?.isNotEmpty == true ? trimmedPhone : null,
        designation: trimmedDesignation?.isNotEmpty == true
            ? trimmedDesignation
            : 'Company Administrator',
        organizationId: organization.id,
        organizationName: organization.name,
        isPrimaryAdmin: !hasPrimaryAdmin,
        isActive: true,
        status: 'invited',
        createdAt: DateTime.now(),
      );

      _mockCompanyAdmins.add(newAdmin);
      unawaited(
        PlatformAuditService.instance.recordAuditEvent(
          eventType: 'admin_invited',
          category: 'governance',
          severity: 'info',
          description:
              'Company Admin "${newAdmin.fullName}" invited to "${organization.name}"',
          organizationId: organization.id,
          targetType: 'company_admin',
          targetId: newAdmin.id,
          metadata: {
            'admin_name': newAdmin.fullName,
            'email': newAdmin.email,
            'is_primary': newAdmin.isPrimaryAdmin,
          },
        ),
      );
      return CompanyAdminInvitationResult.success(newAdmin);
    }

    // In connected environment:
    // Notice: Client-side Supabase anon key cannot invoke auth.admin.inviteUserByEmail.
    // Privileged Auth user creation requires server-side service-role execution.
    try {
      debugPrint(
        '[inviteCompanyAdmin] Invoking Edge Function "invite-company-admin"...',
      );
      debugPrint(
        '[inviteCompanyAdmin] Target Organization ID: ${organization.id}',
      );
      debugPrint(
        '[inviteCompanyAdmin] Target Organization Name: ${organization.name}',
      );
      debugPrint(
        '[inviteCompanyAdmin] Caller user ID: ${client.auth.currentUser?.id}',
      );
      debugPrint(
        '[inviteCompanyAdmin] Caller session active: ${client.auth.currentSession != null}',
      );

      final response = await client.functions.invoke(
        'invite-company-admin',
        body: {
          'organization_id': organization.id,
          'organization_name': organization.name,
          'full_name': trimmedName,
          'email': trimmedEmail,
          'phone': trimmedPhone,
          'designation': trimmedDesignation,
        },
      );

      debugPrint(
        '[inviteCompanyAdmin] Functions response status: ${response.status}',
      );
      debugPrint(
        '[inviteCompanyAdmin] Functions response data: ${response.data}',
      );

      if (response.status == 200 && response.data != null) {
        final data = Map<String, dynamic>.from(response.data as Map);
        final created = CompanyAdminSummary.fromJson(data);
        unawaited(
          PlatformAuditService.instance.recordAuditEvent(
            eventType: 'admin_invited',
            category: 'governance',
            severity: 'info',
            description:
                'Company Admin "${created.fullName}" invited to "${organization.name}"',
            organizationId: organization.id,
            targetType: 'company_admin',
            targetId: created.id,
            metadata: {
              'admin_name': created.fullName,
              'email': created.email,
              'is_primary': created.isPrimaryAdmin,
            },
          ),
        );
        return CompanyAdminInvitationResult.success(created);
      } else {
        final err =
            response.data?['error']?.toString() ??
            response.data?['message']?.toString() ??
            'Server returned error ${response.status} during invitation.';
        debugPrint('[inviteCompanyAdmin] Non-200 response error: $err');
        return CompanyAdminInvitationResult.failure(err);
      }
    } on FunctionException catch (e) {
      debugPrint('[inviteCompanyAdmin] CAUGHT FunctionException:');
      debugPrint('[inviteCompanyAdmin]   status: ${e.status}');
      debugPrint('[inviteCompanyAdmin]   reasonPhrase: ${e.reasonPhrase}');
      debugPrint('[inviteCompanyAdmin]   details: ${e.details}');

      // Extract application error message from response payload if available
      String? appError;
      bool isGatewayNotFound = false;

      if (e.details is Map) {
        final detailsMap = e.details as Map;
        final code = detailsMap['code']?.toString();
        final message = detailsMap['message']?.toString();
        final error = detailsMap['error']?.toString();

        if (code == 'NOT_FOUND' ||
            message == 'Function not found' ||
            message == 'Requested function was not found') {
          isGatewayNotFound = true;
        }

        appError = error ?? message;
      } else if (e.details != null && e.details.toString().isNotEmpty) {
        final detailsStr = e.details.toString();
        if (detailsStr.contains('Function not found') ||
            detailsStr.contains('Requested function was not found')) {
          isGatewayNotFound = true;
        } else {
          appError = detailsStr;
        }
      } else {
        // e.details is null or empty
        isGatewayNotFound = true;
      }

      // Only treat HTTP 404 as "backend required / function missing" when
      // the response indicates the Supabase Edge Function gateway itself is missing.
      if (e.status == 404 &&
          (isGatewayNotFound || appError == null || appError.isEmpty)) {
        return CompanyAdminInvitationResult.backendRequired(
          admin: CompanyAdminSummary(
            id: 'pending-${DateTime.now().millisecondsSinceEpoch}',
            fullName: trimmedName,
            email: trimmedEmail,
            phone: trimmedPhone,
            designation: trimmedDesignation,
            organizationId: organization.id,
            organizationName: organization.name,
            isPrimaryAdmin: false,
            isActive: false,
            status: 'invited',
          ),
          errorMessage: 'A secure server-side invitation endpoint (Supabase Edge Function "invite-company-admin") is required to issue Auth user invitations with service-role authority. Client-side creation with anon keys is forbidden for security.',
        );
      }

      // For all other errors, including application 404s (e.g. "Target organization not found"),
      // surface the actual error from the Edge Function
      final errorMessage =
          appError ??
          e.reasonPhrase ??
          'Function invocation failed with status ${e.status}.';

      return CompanyAdminInvitationResult.failure(errorMessage);
    } catch (e, st) {
      debugPrint('[inviteCompanyAdmin] CAUGHT unexpected exception: $e');
      debugPrint('[inviteCompanyAdmin] StackTrace: $st');
      return CompanyAdminInvitationResult.failure(
        'An unexpected error occurred during invitation: $e',
      );
    }
  }

  /// Updates a Company Administrator's profile details and/or email identity.
  /// When email changes, delegates to the server-side manage-company-admin
  /// Edge Function to update Supabase Auth securely and trigger database synchronization.
  Future<CompanyAdminUpdateResult> updateCompanyAdmin({
    required String adminId,
    required Organization organization,
    required String fullName,
    required String email,
    String? phone,
    String? designation,
  }) async {
    final trimmedName = fullName.trim();
    final trimmedEmail = email.trim().toLowerCase();
    final trimmedPhone = phone?.trim();
    final trimmedDesignation = designation?.trim();

    // 1. Validation
    if (adminId.trim().isEmpty) {
      return const CompanyAdminUpdateResult.failure(
        'Administrator ID is required.',
      );
    }
    if (trimmedName.isEmpty) {
      return const CompanyAdminUpdateResult.failure(
        'Full name cannot be empty.',
      );
    }
    if (trimmedName.length > 150) {
      return const CompanyAdminUpdateResult.failure(
        'Full name cannot exceed 150 characters.',
      );
    }
    if (trimmedEmail.isEmpty) {
      return const CompanyAdminUpdateResult.failure(
        'Email address cannot be empty.',
      );
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(trimmedEmail)) {
      return const CompanyAdminUpdateResult.failure(
        'Please enter a valid email address.',
      );
    }

    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      // In-memory mock update
      final duplicate = _mockCompanyAdmins.any(
        (a) =>
            a.organizationId == organization.id &&
            a.id != adminId &&
            a.email.toLowerCase() == trimmedEmail &&
            a.isActive,
      );
      if (duplicate) {
        return CompanyAdminUpdateResult.failure(
          'Another administrator with email "$trimmedEmail" already exists.',
        );
      }

      final index = _mockCompanyAdmins.indexWhere(
        (a) => a.id == adminId && a.organizationId == organization.id,
      );
      if (index == -1) {
        return const CompanyAdminUpdateResult.failure(
          'Administrator profile not found.',
        );
      }

      final existing = _mockCompanyAdmins[index];
      final updated = existing.copyWith(
        fullName: trimmedName,
        email: trimmedEmail,
        phone: trimmedPhone?.isNotEmpty == true ? trimmedPhone : null,
        designation: trimmedDesignation?.isNotEmpty == true
            ? trimmedDesignation
            : existing.designation,
      );
      _mockCompanyAdmins[index] = updated;
      unawaited(
        PlatformAuditService.instance.recordAuditEvent(
          eventType: 'admin_updated',
          category: 'governance',
          severity: 'info',
          description:
              'Company Admin "${updated.fullName}" profile updated in "${organization.name}"',
          organizationId: organization.id,
          targetType: 'company_admin',
          targetId: updated.id,
          metadata: {'admin_name': updated.fullName, 'email': updated.email},
        ),
      );
      return CompanyAdminUpdateResult.success(updated);
    }

    // Connected Supabase environment
    try {
      final response = await client.functions.invoke(
        'manage-company-admin',
        body: {
          'action': 'update_admin',
          'organization_id': organization.id,
          'admin_id': adminId,
          'full_name': trimmedName,
          'email': trimmedEmail,
          'phone': trimmedPhone,
          'designation': trimmedDesignation,
        },
      );

      if (response.status == 200 && response.data != null) {
        final data = Map<String, dynamic>.from(response.data as Map);
        final updated = CompanyAdminSummary.fromJson(data);
        unawaited(
          PlatformAuditService.instance.recordAuditEvent(
            eventType: 'admin_updated',
            category: 'governance',
            severity: 'info',
            description:
                'Company Admin "${updated.fullName}" profile updated in "${organization.name}"',
            organizationId: organization.id,
            targetType: 'company_admin',
            targetId: updated.id,
            metadata: {'admin_name': updated.fullName, 'email': updated.email},
          ),
        );
        return CompanyAdminUpdateResult.success(updated);
      } else {
        final err =
            response.data?['error']?.toString() ??
            response.data?['message']?.toString() ??
            'Server returned error ${response.status} during update.';
        return CompanyAdminUpdateResult.failure(err);
      }
    } on FunctionException catch (e) {
      String? appError;
      if (e.details is Map) {
        final map = e.details as Map;
        appError = map['error']?.toString() ?? map['message']?.toString();
      } else if (e.details != null && e.details.toString().isNotEmpty) {
        appError = e.details.toString();
      }
      appError ??=
          e.reasonPhrase ??
          'Function invocation failed with status ${e.status}.';
      return CompanyAdminUpdateResult.failure(appError);
    } catch (e) {
      return CompanyAdminUpdateResult.failure(
        'Failed to update administrator: $e',
      );
    }
  }

  /// Removes/deactivates a Company Administrator from a tenant organization.
  /// Rules:
  /// - Company cannot have zero active Company Admins.
  /// - Secondary admins may be removed directly.
  /// - Removing the Primary Admin requires designating an active successor admin.
  /// - Preserves audit/history data by deactivating profile rather than hard-deleting.
  Future<CompanyAdminDeleteResult> deleteCompanyAdmin({
    required String adminId,
    required Organization organization,
    String? newPrimaryAdminId,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      final activeOrgAdmins = _mockCompanyAdmins
          .where((a) => a.organizationId == organization.id && a.isActive)
          .toList();

      if (activeOrgAdmins.length <= 1) {
        return const CompanyAdminDeleteResult.failure(
          'Cannot remove the only active administrator of this company. Every company must retain at least one active administrator.',
        );
      }

      final targetIndex = _mockCompanyAdmins.indexWhere(
        (a) => a.id == adminId && a.organizationId == organization.id,
      );
      if (targetIndex == -1) {
        return const CompanyAdminDeleteResult.failure(
          'Administrator profile not found.',
        );
      }

      final target = _mockCompanyAdmins[targetIndex];

      if (target.isPrimaryAdmin) {
        if (newPrimaryAdminId == null || newPrimaryAdminId.trim().isEmpty) {
          return const CompanyAdminDeleteResult.failure(
            'The Primary Administrator cannot be removed without selecting a successor Primary Administrator.',
          );
        }
        final successorIndex = _mockCompanyAdmins.indexWhere(
          (a) =>
              a.id == newPrimaryAdminId &&
              a.organizationId == organization.id &&
              a.isActive,
        );
        if (successorIndex == -1 || newPrimaryAdminId == adminId) {
          return const CompanyAdminDeleteResult.failure(
            'Selected successor administrator is invalid or not active.',
          );
        }

        // Reassign Primary Admin to successor
        _mockCompanyAdmins[successorIndex] = _mockCompanyAdmins[successorIndex]
            .copyWith(isPrimaryAdmin: true);
      }

      // Safe deactivation: preserves audit history while revoking active admin status
      _mockCompanyAdmins[targetIndex] = target.copyWith(
        isActive: false,
        isPrimaryAdmin: false,
        status: 'inactive',
      );

      unawaited(
        PlatformAuditService.instance.recordAuditEvent(
          eventType: 'admin_removed',
          category: 'governance',
          severity: 'warning',
          description: 'Company Admin removed from "${organization.name}"',
          organizationId: organization.id,
          targetType: 'company_admin',
          targetId: adminId,
          metadata: {'successor_id': newPrimaryAdminId},
        ),
      );

      return const CompanyAdminDeleteResult.success();
    }

    // Connected Supabase environment
    try {
      final response = await client.functions.invoke(
        'manage-company-admin',
        body: {
          'action': 'delete_admin',
          'organization_id': organization.id,
          'admin_id': adminId,
          'new_primary_admin_id': newPrimaryAdminId,
        },
      );

      if (response.status == 200) {
        unawaited(
          PlatformAuditService.instance.recordAuditEvent(
            eventType: 'admin_removed',
            category: 'governance',
            severity: 'warning',
            description: 'Company Admin removed from "${organization.name}"',
            organizationId: organization.id,
            targetType: 'company_admin',
            targetId: adminId,
            metadata: {'successor_id': newPrimaryAdminId},
          ),
        );
        return const CompanyAdminDeleteResult.success();
      } else {
        final err =
            response.data?['error']?.toString() ??
            response.data?['message']?.toString() ??
            'Server returned error ${response.status} during deletion.';
        return CompanyAdminDeleteResult.failure(err);
      }
    } on FunctionException catch (e) {
      String? appError;
      if (e.details is Map) {
        final map = e.details as Map;
        appError = map['error']?.toString() ?? map['message']?.toString();
      } else if (e.details != null && e.details.toString().isNotEmpty) {
        appError = e.details.toString();
      }
      appError ??=
          e.reasonPhrase ??
          'Function invocation failed with status ${e.status}.';
      return CompanyAdminDeleteResult.failure(appError);
    } catch (e) {
      return CompanyAdminDeleteResult.failure(
        'Failed to remove administrator: $e',
      );
    }
  }

  /// Resends an invitation email / link for an unconfirmed Company Administrator.
  /// Generates a fresh secure invite link via manage-company-admin Edge Function
  /// without creating duplicate Auth users or throwing conflicts.
  Future<CompanyAdminResendResult> resendCompanyAdminInvitation({
    required Organization organization,
    required String adminId,
    String? redirectTo,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      final targetIndex = _mockCompanyAdmins.indexWhere(
        (a) => a.id == adminId && a.organizationId == organization.id,
      );

      if (targetIndex == -1) {
        return const CompanyAdminResendResult.failure(
          'Administrator profile not found.',
        );
      }

      final target = _mockCompanyAdmins[targetIndex];

      if (target.isDisabled) {
        return const CompanyAdminResendResult.failure(
          'Cannot resend invitation to a disabled or removed administrator.',
        );
      }

      if (target.isFullyActive) {
        return const CompanyAdminResendResult.failure(
          'Administrator has already completed activation.',
        );
      }

      return CompanyAdminResendResult.success(
        message: 'Invitation resent successfully to ${target.email}.',
        inviteLink: 'http://localhost:8080/#/reset-password?mock_invite=true',
      );
    }

    try {
      final response = await client.functions.invoke(
        'manage-company-admin',
        body: {
          'action': 'resend_invitation',
          'organization_id': organization.id,
          'admin_id': adminId,
          'redirect_to': (redirectTo != null && redirectTo.trim().isNotEmpty)
              ? redirectTo.trim()
              : 'http://localhost:8080',
        },
      );

      if (response.status == 200 && response.data != null) {
        final data = Map<String, dynamic>.from(response.data as Map);
        return CompanyAdminResendResult.success(
          message:
              data['message']?.toString() ??
              'Invitation email resent successfully to administrator.',
          inviteLink: data['invite_link']?.toString(),
        );
      } else {
        final err =
            response.data?['error']?.toString() ??
            response.data?['message']?.toString() ??
            'Server returned status ${response.status} during invitation resend.';
        return CompanyAdminResendResult.failure(err);
      }
    } on FunctionException catch (e) {
      String? appError;
      if (e.details is Map) {
        final map = e.details as Map;
        appError = map['error']?.toString() ?? map['message']?.toString();
      } else if (e.details != null && e.details.toString().isNotEmpty) {
        appError = e.details.toString();
      }
      appError ??=
          e.reasonPhrase ??
          'Function invocation failed with status ${e.status}.';
      return CompanyAdminResendResult.failure(appError);
    } catch (e) {
      return CompanyAdminResendResult.failure(
        'Failed to resend invitation: $e',
      );
    }
  }

  /// Permanently deletes a tenant organization and all its relational records and
  /// associated auth users.
  /// Rules:
  /// - Only Platform Administrators can invoke this operation.
  /// - Sobha (#1) is permanent and cannot be deleted.
  /// - All associated auth users (except Platform Admins) are purged from Supabase Auth.
  Future<OrganizationDeleteResult> deleteOrganization(
    String organizationId,
  ) async {
    final trimmedId = organizationId.trim();
    if (trimmedId.isEmpty) {
      return const OrganizationDeleteResult.failure(
        'Organization ID is required.',
      );
    }

    // Invariant: Sobha (#1) is permanent and cannot be deleted
    if (trimmedId == Organization.sobhaId) {
      return const OrganizationDeleteResult.failure(
        'ActionFlow Security Violation: Default organization Sobha (#1) is permanent and cannot be deleted.',
      );
    }

    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      final index = _mockOrganizations.indexWhere((o) => o.id == trimmedId);
      if (index == -1) {
        return const OrganizationDeleteResult.failure(
          'Organization not found.',
        );
      }

      final org = _mockOrganizations[index];
      if (org.isSobha) {
        return const OrganizationDeleteResult.failure(
          'ActionFlow Security Violation: Default organization Sobha is permanent and cannot be deleted.',
        );
      }

      // Remove from mock organizations
      _mockOrganizations.removeAt(index);

      // Remove associated mock company admins
      _mockCompanyAdmins.removeWhere((a) => a.organizationId == trimmedId);

      unawaited(
        PlatformAuditService.instance.recordAuditEvent(
          eventType: 'organization_deleted',
          category: 'tenancy',
          severity: 'warning',
          description: 'Organization "${org.name}" deleted',
          organizationId: null,
          organizationName: org.name,
          organizationCode: org.code,
          metadata: {
            'status': 'deleted',
            'name': org.name,
            'code': org.code,
            'organization_id': trimmedId,
            'is_deleted': true,
          },
        ),
      );

      return OrganizationDeleteResult.success(
        message: 'Organization "${org.name}" deleted successfully.',
      );
    }

    // In connected environment, lookup target organization details before deletion
    String? orgName;
    String? orgCode;
    try {
      final dynamic orgRow = await client
          .from('organizations')
          .select('name, code')
          .eq('id', trimmedId)
          .maybeSingle();
      if (orgRow is Map) {
        orgName = orgRow['name']?.toString();
        orgCode = orgRow['code']?.toString();
      }
    } catch (_) {}

    // Connected Supabase environment: Delegate to privileged manage-company-admin Edge Function
    try {
      final response = await client.functions.invoke(
        'manage-company-admin',
        body: {'action': 'delete_organization', 'organization_id': trimmedId},
      );

      if (response.status == 200) {
        final data = response.data is Map
            ? Map<String, dynamic>.from(response.data as Map)
            : null;
        unawaited(
          PlatformAuditService.instance.recordAuditEvent(
            eventType: 'organization_deleted',
            category: 'tenancy',
            severity: 'warning',
            description: orgName != null
                ? 'Organization "$orgName" deleted'
                : 'Organization deleted (id: $trimmedId)',
            organizationId: null,
            organizationName: orgName,
            organizationCode: orgCode,
            metadata: {
              'status': 'deleted',
              'organization_id': trimmedId,
              'organization_name': orgName,
              'organization_code': orgCode,
              'is_deleted': true,
            },
          ),
        );
        return OrganizationDeleteResult.success(
          message:
              data?['message']?.toString() ??
              'Organization deleted successfully.',
        );
      } else if (response.status == 207) {
        // Partial deletion (DB records deleted, but some Auth users failed)
        final data = response.data is Map
            ? Map<String, dynamic>.from(response.data as Map)
            : null;
        final failedIds =
            (data?['failed_auth_user_ids'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [];
        unawaited(
          PlatformAuditService.instance.recordAuditEvent(
            eventType: 'organization_deleted_partial',
            category: 'tenancy',
            severity: 'error',
            description: orgName != null
                ? 'Organization "$orgName" deleted from DB, but some Auth users remained'
                : 'Organization deleted partially (id: $trimmedId)',
            organizationId: null,
            organizationName: orgName,
            organizationCode: orgCode,
            metadata: {
              'status': 'partial_delete',
              'organization_id': trimmedId,
              'failed_auth_user_ids': failedIds,
              'is_deleted': true,
            },
          ),
        );
        return OrganizationDeleteResult.partial(
          message: data?['message']?.toString() ?? 'Organization deleted from database, but some Auth users could not be removed.',
          failedAuthUserIds: failedIds,
        );
      } else {
        final err =
            response.data?['error']?.toString() ??
            response.data?['message']?.toString() ??
            'Server returned error ${response.status} during organization deletion.';
        return OrganizationDeleteResult.failure(err);
      }
    } on FunctionException catch (e) {
      String? appError;
      if (e.details is Map) {
        final map = e.details as Map;
        appError = map['error']?.toString() ?? map['message']?.toString();
      } else if (e.details != null && e.details.toString().isNotEmpty) {
        appError = e.details.toString();
      }
      appError ??=
          e.reasonPhrase ??
          'Function invocation failed with status ${e.status}.';
      return OrganizationDeleteResult.failure(appError);
    } catch (e) {
      return OrganizationDeleteResult.failure(
        'Failed to delete organization: $e',
      );
    }
  }

  /// Resets mock organizations and company admins (used in unit tests)
  @visibleForTesting
  void resetMockData() {
    _mockOrganizations.clear();
    _mockOrganizations.add(
      Organization.sobha().copyWith(
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );

    _mockCompanyAdmins.clear();
    _mockCompanyAdmins.add(
      const CompanyAdminSummary(
        id: 'usr-sobha-admin-1',
        fullName: 'Sobha Admin',
        email: 'admin@sobha.com',
        phone: '+971 4 000 0000',
        designation: 'Enterprise System Administrator',
        organizationId: Organization.sobhaId,
        organizationName: Organization.sobhaName,
        isPrimaryAdmin: true,
        isActive: true,
        status: 'active',
      ),
    );

    _mockOrganizationCounts.clear();
  }
}
