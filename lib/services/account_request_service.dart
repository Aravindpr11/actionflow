import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/features/auth/data/mock_auth_store.dart';
import 'package:action_flow/features/auth/models/auth_models.dart';

/// Service managing administrative review, approval, and rejection of account requests
/// connected directly to public.account_requests, public.account_request_scopes, and public.profiles.
class AccountRequestService {
  AccountRequestService({SupabaseClient? client}) : _clientOverride = client;

  static final AccountRequestService instance = AccountRequestService();

  final SupabaseClient? _clientOverride;

  SupabaseClient? get _client => _clientOverride ?? SupabaseConfig.clientOrNull;

  /// Fetches all registration account requests.
  /// When Supabase is initialized, queries public.account_requests and resolves
  /// organizational references (departments, sites, teams, roles, scopes).
  /// Falls back to MockAuthStore only when Supabase is not initialized (e.g. mock test mode).
  Future<List<SignupRequest>> fetchAccountRequests({
    String? organizationId,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      if (organizationId != null && organizationId.isNotEmpty) {
        return MockAuthStore.instance.registrations
            .where(
              (r) =>
                  r.organizationId == null ||
                  r.organizationId == organizationId,
            )
            .toList();
      }
      return MockAuthStore.instance.registrations;
    }

    try {
      var query = client.from('account_requests').select();
      if (organizationId != null && organizationId.isNotEmpty) {
        query = query.eq('organization_id', organizationId);
      }
      final dynamic rawRequests = await query.order(
        'created_at',
        ascending: false,
      );

      if (rawRequests == null || (rawRequests is List && rawRequests.isEmpty)) {
        return [];
      }

      final requestRows = List<Map<String, dynamic>>.from(
        (rawRequests as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );

      // Fetch lookup tables and scopes in parallel
      final results = await Future.wait([
        client.from('roles').select('id, name, code'),
        client.from('departments').select('id, name, code, division'),
        client.from('sites').select('id, name'),
        client.from('teams').select('id, name, department_id'),
        client.from('profiles').select('id, full_name'),
        client.from('account_request_scopes').select(),
      ]);

      // Map roles
      final rolesMap = <String, Map<String, dynamic>>{};
      for (final r in results[0] as List) {
        final m = Map<String, dynamic>.from(r as Map);
        final id = m['id'] as String?;
        if (id != null) rolesMap[id] = m;
      }

      // Map departments
      final departmentsMap = <String, Map<String, dynamic>>{};
      for (final d in results[1] as List) {
        final m = Map<String, dynamic>.from(d as Map);
        final id = m['id'] as String?;
        if (id != null) departmentsMap[id] = m;
      }

      // Map sites
      final sitesMap = <String, Map<String, dynamic>>{};
      for (final s in results[2] as List) {
        final m = Map<String, dynamic>.from(s as Map);
        final id = m['id'] as String?;
        if (id != null) sitesMap[id] = m;
      }

      // Map teams
      final teamsMap = <String, Map<String, dynamic>>{};
      for (final t in results[3] as List) {
        final m = Map<String, dynamic>.from(t as Map);
        final id = m['id'] as String?;
        if (id != null) teamsMap[id] = m;
      }

      // Map profiles (reviewers)
      final profilesMap = <String, Map<String, dynamic>>{};
      for (final p in results[4] as List) {
        final m = Map<String, dynamic>.from(p as Map);
        final id = m['id'] as String?;
        if (id != null) profilesMap[id] = m;
      }

      // Map manager scopes by account_request_id
      final scopesByRequestId = <String, List<Map<String, dynamic>>>{};
      for (final sc in results[5] as List) {
        final m = Map<String, dynamic>.from(sc as Map);
        final reqId = m['account_request_id'] as String?;
        if (reqId != null) {
          scopesByRequestId.putIfAbsent(reqId, () => []).add(m);
        }
      }

      final requests = <SignupRequest>[];
      for (final row in requestRows) {
        final reqId = (row['id'] as String?) ?? '';
        final authUserId = (row['auth_user_id'] as String?) ?? '';
        final fullName = (row['full_name'] as String?) ?? '';
        final email = (row['email'] as String?) ?? '';
        final phone = (row['phone'] as String?) ?? '';
        final designation = (row['designation'] as String?) ?? '';
        final deptId = row['department_id'] as String?;
        final siteId = row['site_id'] as String?;
        final teamId = row['team_id'] as String?;
        final requestedRoleId = row['requested_role_id'] as String?;
        final rawStatus =
            (row['status'] as String?) ?? 'pending_email_verification';
        final isEmailVerified = row['is_email_verified'] == true;
        final rejectionReason = row['rejection_reason'] as String?;
        final reviewedBy = row['reviewed_by'] as String?;
        final reviewedAtStr = row['reviewed_at'] as String?;
        final createdAtStr = row['created_at'] as String?;
        final orgId =
            (row['organization_id'] as String?) ?? Organization.sobhaId;

        // Determine role
        final roleMap = requestedRoleId != null
            ? rolesMap[requestedRoleId]
            : null;
        final roleCode = ((roleMap?['code'] as String?) ?? '').toLowerCase();
        final requestedType = roleCode == 'manager'
            ? RequestedAccountType.manager
            : RequestedAccountType.staff;

        // Map database status string to enum
        AuthAccountStatus status;
        switch (rawStatus) {
          case 'pending_email_verification':
            status = AuthAccountStatus.pendingVerification;
            break;
          case 'pending_admin_approval':
            status = AuthAccountStatus.pendingApproval;
            break;
          case 'approved':
            status = AuthAccountStatus.active;
            break;
          case 'rejected':
            status = AuthAccountStatus.rejected;
            break;
          default:
            status = AuthAccountStatus.pendingVerification;
        }

        // Reviewer profile lookup
        String? reviewerName;
        if (reviewedBy != null && profilesMap.containsKey(reviewedBy)) {
          reviewerName = profilesMap[reviewedBy]!['full_name'] as String?;
        }

        // Manager scopes
        final managerScopes = <ManagerScopeItemView>[];
        final rawScopes = scopesByRequestId[reqId] ?? [];
        for (final s in rawScopes) {
          final dId = s['department_id'] as String?;
          final sId = s['site_id'] as String?;
          final dName =
              (departmentsMap[dId]?['name'] as String?) ?? 'Unknown Department';
          final sName = (sitesMap[sId]?['name'] as String?) ?? 'Unknown Site';
          managerScopes.add(
            ManagerScopeItemView(
              departmentName: dName,
              siteName: sName,
              departmentId: dId,
              siteId: sId,
            ),
          );
        }

        // Staff primary placement
        final deptName = (departmentsMap[deptId]?['name'] as String?) ?? '';
        final division =
            (departmentsMap[deptId]?['division'] as String?) ??
            'Operations & HSSE';
        final siteName = (sitesMap[siteId]?['name'] as String?) ?? '';
        final teamName = (teamsMap[teamId]?['name'] as String?) ?? '';

        requests.add(
          SignupRequest(
            id: reqId,
            authUserId: authUserId,
            fullName: fullName,
            email: email,
            phone: phone,
            designation: designation,
            department: deptName,
            departmentId: deptId,
            division: division,
            site: siteName,
            siteId: siteId,
            team: teamName,
            teamId: teamId,
            supervisor: '',
            requestedType: requestedType,
            requestedRoleId: requestedRoleId,
            managerScopes: managerScopes,
            status: status,
            isEmailVerified: isEmailVerified,
            rejectionReason: rejectionReason,
            rejectedBy: status == AuthAccountStatus.rejected
                ? reviewerName
                : null,
            rejectedAt:
                status == AuthAccountStatus.rejected && reviewedAtStr != null
                ? DateTime.tryParse(reviewedAtStr)
                : null,
            approvedBy: status == AuthAccountStatus.active
                ? reviewerName
                : null,
            approvedAt:
                status == AuthAccountStatus.active && reviewedAtStr != null
                ? DateTime.tryParse(reviewedAtStr)
                : null,
            createdAt: createdAtStr != null
                ? DateTime.tryParse(createdAtStr)
                : null,
            organizationId: orgId,
          ),
        );
      }

      return requests;
    } catch (e) {
      debugPrint('Error fetching account requests from Supabase: $e');
      rethrow;
    }
  }

  /// Approves an account request.
  /// Strict Preconditions:
  /// - Status must be `pending_admin_approval` AND `isEmailVerified` must be true.
  /// Contract:
  /// 1. Upserts into public.profiles for auth_user_id.
  /// 2. If Staff with team_id, upserts into public.team_members.
  /// 3. Updates public.account_requests with status='approved', created_profile_id=auth_user_id,
  ///    reviewed_by=adminUserId, reviewed_at=now().
  ///    (Database trigger `trg_sync_approved_manager_scopes` automatically copies
  ///    account_request_scopes into public.manager_scopes for Manager requests).
  Future<void> approveAccountRequest(
    SignupRequest req, {
    required String adminUserId,
    String? overrideDepartmentId,
    String? overrideSiteId,
    String? overrideTeamId,
    String? overrideRoleId,
    String? overrideRoleCode,
  }) async {
    // Precondition verification
    if (req.status != AuthAccountStatus.pendingApproval ||
        !req.isEmailVerified) {
      throw Exception(
        'Account request cannot be approved until email verification is complete.',
      );
    }

    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      MockAuthStore.instance.approveRegistration(
        req.email,
        approvedBy: 'Administrator',
      );
      return;
    }

    try {
      final roleCode = (overrideRoleCode != null && overrideRoleCode.isNotEmpty)
          ? overrideRoleCode
          : ((overrideRoleId != null &&
                    [
                      'staff',
                      'manager',
                      'admin',
                    ].contains(overrideRoleId.toLowerCase()))
                ? overrideRoleId.toLowerCase()
                : null);

      final params = <String, dynamic>{'p_request_id': req.id};
      if (overrideDepartmentId != null && overrideDepartmentId.isNotEmpty) {
        params['p_override_department_id'] = overrideDepartmentId;
      }
      if (overrideSiteId != null && overrideSiteId.isNotEmpty) {
        params['p_override_site_id'] = overrideSiteId;
      }
      if (overrideTeamId != null && overrideTeamId.isNotEmpty) {
        params['p_override_team_id'] = overrideTeamId;
      }
      if (roleCode != null && roleCode.isNotEmpty) {
        params['p_override_role_code'] = roleCode;
      }

      await client.rpc('approve_account_request', params: params);
    } catch (e) {
      debugPrint('Error approving account request via RPC: $e');
      rethrow;
    }
  }

  /// Rejects an account request with a mandatory explanation reason.
  /// Strict Preconditions:
  /// - reason must be non-empty and at least 5 characters.
  Future<void> rejectAccountRequest(
    SignupRequest req, {
    required String reason,
    required String adminUserId,
  }) async {
    final trimmedReason = reason.trim();
    if (trimmedReason.length < 5) {
      throw Exception('Rejection reason must be at least 5 characters.');
    }

    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      MockAuthStore.instance.rejectRegistration(
        req.email,
        reason: trimmedReason,
        rejectedBy: 'Administrator',
      );
      return;
    }

    try {
      await client.rpc(
        'reject_account_request',
        params: {'p_request_id': req.id, 'p_reason': trimmedReason},
      );
    } catch (e) {
      debugPrint('Error rejecting account request via RPC: $e');
      rethrow;
    }
  }
}
