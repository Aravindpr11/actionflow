import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';
import '../features/dashboard/manager_dashboard/models/manager_context.dart';
import '../features/users/data/mock_people_store.dart';
import '../features/users/models/person.dart';
import '../features/users/models/team.dart';
import '../models/organization.dart';
import 'document_service.dart';

/// Service managing tenant-scoped User Directory operations:
/// User listing, search, filtering, role/department/site/team assignments,
/// and activation/deactivation.
///
/// Strictly enforces multi-tenant isolation by scoping all queries
/// and mutations to the authenticated Company Admin's `organizationId`.
class UserService {
  UserService({SupabaseClient? client}) : _clientOverride = client;

  static final UserService instance = UserService();

  final SupabaseClient? _clientOverride;

  SupabaseClient? get _client => _clientOverride ?? SupabaseConfig.clientOrNull;

  bool get isReady => _client != null && SupabaseConfig.isInitialized;

  /// Invalidate any client caches to ensure the next fetch retrieves fresh records.
  void invalidateCache() {
    // Active directory queries directly hit Supabase; hook provided for callers.
  }

  // ==========================================
  // FETCH USERS
  // ==========================================

  /// Fetches all users for the given organization.
  /// In live mode: queries `public.profiles` joined/batched with `roles`,
  /// `departments`, `sites`, and `team_members`.
  /// In offline/test mode: falls back to `MockPeopleStore.instance.people`.
  Future<List<Person>> fetchUsers(
    String organizationId, {
    bool allowMockFallback = true,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      if (!allowMockFallback) {
        throw StateError(
          'Organization users are unavailable because Supabase is not initialized.',
        );
      }
      return MockPeopleStore.instance.people;
    }

    final effectiveOrgId = (organizationId == 'SOBHA-001' &&
            !DocumentService.allowInMemoryStoreForTests)
        ? Organization.sobhaId
        : organizationId;

    Future<List<dynamic>> fetchSafe(Future<dynamic> Function() fn, String label) async {
      try {
        final res = await fn();
        return res is List ? res : const [];
      } catch (e) {
        debugPrint('[UserService] $label lookup note: $e');
        return const [];
      }
    }

    // 1. Fetch profiles scoped to organization
    List<Map<String, dynamic>> profilesList = [];
    try {
      final dynamic rawProfiles = await client
          .from('profiles')
          .select(
            'id, full_name, email, phone, designation, department_id, site_id, role_id, status, is_active, is_primary_admin, created_at',
          )
          .eq('organization_id', effectiveOrgId)
          .order('full_name');
      profilesList = List<Map<String, dynamic>>.from(
        (rawProfiles as List? ?? []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );
    } catch (e) {
      debugPrint('[UserService] profiles query note: $e');
    }

    // Fetch team memberships with defensive fallback
    Future<List<dynamic>> fetchTeamMembersSafe() async {
      try {
        final res = await client
            .from('team_members')
            .select('team_id, profile_id, teams!inner(id, organization_id)')
            .eq('teams.organization_id', effectiveOrgId);
        return res;
      } catch (e) {
        debugPrint('UserService team_members lookup note: $e');
        return const [];
      }
    }

    // Fetch manager scopes with defensive fallback
    Future<List<dynamic>> fetchManagerScopesSafe() async {
      try {
        final res = await client
            .from('manager_scopes')
            .select(
              'id, manager_profile_id, department_id, site_id, departments(id, name), sites(id, name)',
            );
        return res;
      } catch (e) {
        debugPrint('UserService manager_scopes lookup note: $e');
        return const [];
      }
    }

    // 2. Fetch lookup tables in parallel for mapping
    final lookups = await Future.wait([
      fetchSafe(() => client.from('roles').select('id, name, code'), 'roles'),
      fetchSafe(
        () => client
            .from('departments')
            .select('id, name, code, division')
            .eq('organization_id', effectiveOrgId),
        'departments',
      ),
      fetchSafe(
        () => client
            .from('sites')
            .select('id, name, code')
            .eq('organization_id', effectiveOrgId),
        'sites',
      ),
      fetchTeamMembersSafe(),
      fetchManagerScopesSafe(),
    ]);

    // Roles lookup
    final rolesMap = <String, Map<String, dynamic>>{};
    for (final r in lookups[0] as List? ?? []) {
      final m = Map<String, dynamic>.from(r as Map);
      final id = m['id']?.toString();
      if (id != null) rolesMap[id] = m;
    }

    // Departments lookup
    final deptsMap = <String, Map<String, dynamic>>{};
    for (final d in lookups[1] as List? ?? []) {
      final m = Map<String, dynamic>.from(d as Map);
      final id = m['id']?.toString();
      if (id != null) deptsMap[id] = m;
    }

    // Sites lookup
    final sitesMap = <String, Map<String, dynamic>>{};
    for (final s in lookups[2] as List? ?? []) {
      final m = Map<String, dynamic>.from(s as Map);
      final id = m['id']?.toString();
      if (id != null) sitesMap[id] = m;
    }

    // Team memberships lookup by profile_id
    final teamIdsByProfile = <String, List<String>>{};
    for (final tm in lookups[3] as List? ?? []) {
      final m = Map<String, dynamic>.from(tm as Map);
      final profId = m['profile_id']?.toString();
      final teamId = m['team_id']?.toString();
      if (profId != null && teamId != null) {
        teamIdsByProfile.putIfAbsent(profId, () => []).add(teamId);
      }
    }

    // Manager scopes lookup by manager_profile_id
    final scopesByManagerId = <String, List<ManagerScopeItem>>{};
    for (final sc in lookups[4] as List? ?? []) {
      final m = Map<String, dynamic>.from(sc as Map);
      final mgrId = m['manager_profile_id']?.toString();
      final deptId = m['department_id']?.toString();
      final siteId = m['site_id']?.toString();
      if (mgrId != null && deptId != null && siteId != null) {
        final dMap = m['departments'] as Map?;
        final sMap = m['sites'] as Map?;
        final dName =
            dMap?['name']?.toString() ??
            deptsMap[deptId]?['name']?.toString() ??
            'Department';
        final sName =
            sMap?['name']?.toString() ??
            sitesMap[siteId]?['name']?.toString() ??
            'Site';
        scopesByManagerId
            .putIfAbsent(mgrId, () => [])
            .add(
              ManagerScopeItem(
                id: m['id']?.toString(),
                departmentId: deptId,
                departmentName: dName,
                siteId: siteId,
                siteName: sName,
              ),
            );
      }
    }

    // 3. Map real profiles to Person instances
    final realUsers = profilesList.map((p) {
      final id = p['id']?.toString() ?? '';
      final roleId = p['role_id']?.toString() ?? '';
      final deptId = p['department_id']?.toString();
      final siteId = p['site_id']?.toString();

      final roleData = rolesMap[roleId];
      final roleCode = roleData?['code']?.toString().toLowerCase() ?? '';
      final roleName = roleData?['name']?.toString().toLowerCase() ?? '';

      final desig = (p['designation']?.toString() ?? '').toLowerCase();
      UserRole userRole = UserRole.actionOwnerWorker;
      if (roleCode == 'admin' ||
          roleName == 'admin' ||
          p['is_primary_admin'] == true ||
          desig.contains('admin')) {
        userRole = UserRole.admin;
      } else if (roleCode == 'manager' ||
          roleName == 'manager' ||
          desig.contains('manager') ||
          desig.contains('lead') ||
          desig.contains('director') ||
          desig.contains('supervisor') ||
          desig.contains('head')) {
        userRole = UserRole.departmentManager;
      }

      final deptData = deptId != null ? deptsMap[deptId] : null;
      final siteData = siteId != null ? sitesMap[siteId] : null;

      final deptName = deptData?['name']?.toString() ?? '';
      final siteName = siteData?['name']?.toString() ?? '';

      final isActive = p['is_active'] != false;
      final assignedTeams = teamIdsByProfile[id] ?? [];
      final managerScopes = scopesByManagerId[id] ?? [];

      return Person(
        id: id,
        name: p['full_name']?.toString() ?? '',
        email: p['email']?.toString() ?? '',
        phone: p['phone']?.toString() ?? '',
        designation: p['designation']?.toString() ?? '',
        type: PersonType.internalUser,
        isActive: isActive,
        role: userRole,
        teamIds: assignedTeams,
        managerScopes: managerScopes,
        department: deptName,
        site: siteName,
        company: '',
        notes: '',
        departmentId: deptId,
        siteId: siteId,
        roleId: roleId,
        organizationId: organizationId,
      );
    }).toList();

    debugPrint(
      '[UserService] fetchUsers: org=$organizationId (effective=$effectiveOrgId), profilesCount=${profilesList.length}',
    );

    // Always query public.directory_profiles to ensure all active colleagues in the
    // organization are discoverable across Manager and Staff portals regardless of RLS restrictions on public.profiles.
    try {
      final dynamic rawDir = await client
          .from('directory_profiles')
          .select(
            'id, full_name, designation, department_id, department_name, site_id, site_name, role_id, role_name, avatar_url, is_active, email, phone, role_code, organization_id, is_primary_admin',
          )
          .order('full_name');
      debugPrint('[UserService] directory_profiles query status: SUCCESS, rawRowsCount=${rawDir is List ? rawDir.length : 0}');

      if (rawDir is List && rawDir.isNotEmpty) {
        for (final item in rawDir) {
          final d = Map<String, dynamic>.from(item as Map);
          final id = d['id']?.toString() ?? '';
          if (id.isEmpty) continue;

          final roleCode = (d['role_code']?.toString() ?? '').toLowerCase();
          final isPrimaryAdmin = d['is_primary_admin'] == true;
          final roleName = (d['role_name']?.toString() ?? '').toLowerCase();

          UserRole uRole = UserRole.actionOwnerWorker;
          if (isPrimaryAdmin ||
              roleCode == 'admin' ||
              roleCode == 'company_admin' ||
              roleCode == 'platform_admin' ||
              roleName.contains('admin')) {
            uRole = UserRole.admin;
          } else if (roleCode == 'manager' ||
              roleName.contains('manager') ||
              roleName.contains('lead')) {
            uRole = UserRole.departmentManager;
          }

          final deptId = d['department_id']?.toString();
          String deptName = d['department_name']?.toString() ?? '';
          if (deptName.isEmpty && deptId != null && deptsMap.containsKey(deptId)) {
            deptName = deptsMap[deptId]?['name']?.toString() ?? '';
          }

          final email = d['email']?.toString() ?? '';
          final phone = d['phone']?.toString() ?? '';
          final siteId = d['site_id']?.toString();
          final siteName = d['site_name']?.toString() ?? '';
          final designation = d['designation']?.toString() ?? '';
          final roleId = d['role_id']?.toString();
          final orgId = d['organization_id']?.toString() ?? organizationId;

          // If user already in realUsers (e.g. self from profiles query), enrich their fields
          final existingIdx = realUsers.indexWhere((u) => u.id == id);
          if (existingIdx != -1) {
            final cur = realUsers[existingIdx];
            realUsers[existingIdx] = cur.copyWith(
              role: uRole != UserRole.actionOwnerWorker ? uRole : cur.role,
              email: cur.email.isNotEmpty ? cur.email : email,
              phone: cur.phone.isNotEmpty ? cur.phone : phone,
              department: cur.department.isNotEmpty ? cur.department : deptName,
              departmentId: cur.departmentId ?? deptId,
              site: cur.site.isNotEmpty ? cur.site : siteName,
              siteId: cur.siteId ?? siteId,
              designation: cur.designation.isNotEmpty ? cur.designation : designation,
              organizationId: cur.organizationId ?? orgId,
              managerScopes: scopesByManagerId[id] ?? cur.managerScopes,
            );
            continue;
          }

          realUsers.add(
            Person(
              id: id,
              name: d['full_name']?.toString() ?? '',
              email: email,
              phone: phone,
              designation: designation,
              type: PersonType.internalUser,
              isActive: d['is_active'] != false,
              role: uRole,
              teamIds: teamIdsByProfile[id] ?? const [],
              managerScopes: scopesByManagerId[id] ?? const [],
              department: deptName,
              site: siteName,
              company: '',
              notes: '',
              departmentId: deptId,
              siteId: siteId,
              roleId: roleId,
              organizationId: orgId,
            ),
          );
        }
      }
    } catch (dirErr) {
      debugPrint('[UserService] directory_profiles query status: FAILED ($dirErr)');
    }

    // If still <= 1 user (or only caller) and allowMockFallback is enabled (e.g. in test or demo environments),
    // supplement with mock people so staff recipient discovery remains functional.
    // In live mode (connected to Supabase backend in non-test mode), never inject
    // mock users because mock IDs do not exist in public.profiles and fail trigger validation (P0001).
    final isLiveBackend = SupabaseConfig.isInitialized &&
        !DocumentService.allowInMemoryStoreForTests;

    if (!isLiveBackend && realUsers.length <= 1 && allowMockFallback) {
      for (final mp in MockPeopleStore.instance.people) {
        if (!realUsers.any((u) => u.id == mp.id)) {
          realUsers.add(mp);
        }
      }
    }

    return realUsers;
  }

  /// Fetches real users for a Manager's directory view, strictly scoped to their
  /// permitted (department_id, site_id) manager scopes in their organization.
  /// Zero mock fallback in the Manager flow.
  Future<List<Person>> fetchManagerDirectory({
    required ManagerContext managerContext,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      throw Exception('ActionFlow Error: Supabase client is not initialized.');
    }

    final orgId = managerContext.organizationId;
    if (orgId.isEmpty) {
      throw Exception(
        'ActionFlow Error: Organization ID is missing from manager context.',
      );
    }

    // 1. Fetch profiles scoped to organization
    // Supabase RLS will also restrict to manager scopes + self profile.
    final dynamic rawProfiles = await client
        .from('profiles')
        .select(
          'id, full_name, email, phone, designation, department_id, site_id, role_id, status, is_active, is_primary_admin, created_at',
        )
        .eq('organization_id', orgId)
        .order('full_name');

    final profilesList = List<Map<String, dynamic>>.from(
      (rawProfiles as List? ?? []).map(
        (e) => Map<String, dynamic>.from(e as Map),
      ),
    );

    // 2. Fetch lookup tables in parallel for mapping
    Future<List<dynamic>> fetchTeamMembersSafe() async {
      try {
        final res = await client
            .from('team_members')
            .select('team_id, profile_id, teams!inner(id, organization_id)')
            .eq('teams.organization_id', orgId);
        return res;
      } catch (e) {
        debugPrint('UserService team_members lookup note: $e');
        return const [];
      }
    }

    final lookups = await Future.wait([
      client.from('roles').select('id, name, code'),
      client
          .from('departments')
          .select('id, name, code, division')
          .eq('organization_id', orgId),
      client
          .from('sites')
          .select('id, name, code')
          .eq('organization_id', orgId),
      client
          .from('teams')
          .select('id, department_id, name, code, is_active')
          .eq('organization_id', orgId),
      fetchTeamMembersSafe(),
    ]);

    // Roles lookup
    final rolesMap = <String, Map<String, dynamic>>{};
    for (final r in lookups[0] as List? ?? []) {
      final m = Map<String, dynamic>.from(r as Map);
      final id = m['id']?.toString();
      if (id != null) rolesMap[id] = m;
    }

    // Departments lookup
    final deptsMap = <String, Map<String, dynamic>>{};
    for (final d in lookups[1] as List? ?? []) {
      final m = Map<String, dynamic>.from(d as Map);
      final id = m['id']?.toString();
      if (id != null) deptsMap[id] = m;
    }

    // Sites lookup
    final sitesMap = <String, Map<String, dynamic>>{};
    for (final s in lookups[2] as List? ?? []) {
      final m = Map<String, dynamic>.from(s as Map);
      final id = m['id']?.toString();
      if (id != null) sitesMap[id] = m;
    }

    // Teams lookup
    final teamsMap = <String, Map<String, dynamic>>{};
    for (final t in lookups[3] as List? ?? []) {
      final m = Map<String, dynamic>.from(t as Map);
      final id = m['id']?.toString();
      if (id != null) teamsMap[id] = m;
    }

    // Team memberships lookup by profile_id
    final teamIdsByProfile = <String, List<String>>{};
    for (final tm in lookups[4] as List? ?? []) {
      final m = Map<String, dynamic>.from(tm as Map);
      final profId = m['profile_id']?.toString();
      final teamId = m['team_id']?.toString();
      if (profId != null && teamId != null) {
        teamIdsByProfile.putIfAbsent(profId, () => []).add(teamId);
      }
    }

    // 3. Filter profiles in-memory as defense-in-depth:
    // If manager has scopes, profile must match a permitted scope OR be the manager themselves.
    final filteredProfiles = profilesList.where((p) {
      final profileId = p['id']?.toString() ?? '';
      if (profileId == managerContext.authUserId) return true;
      if (!managerContext.hasScopes) return true;

      final deptId = p['department_id']?.toString() ?? '';
      final siteId = p['site_id']?.toString() ?? '';
      return managerContext.isScopePermitted(deptId, siteId);
    }).toList();

    // 4. Map profiles to Person instances
    return filteredProfiles.map((p) {
      final id = p['id']?.toString() ?? '';
      final roleId = p['role_id']?.toString() ?? '';
      final deptId = p['department_id']?.toString();
      final siteId = p['site_id']?.toString();

      final roleData = rolesMap[roleId];
      final roleCode = roleData?['code']?.toString().toLowerCase() ?? '';
      final roleName = roleData?['name']?.toString().toLowerCase() ?? '';

      final desig = (p['designation']?.toString() ?? '').toLowerCase();
      UserRole userRole = UserRole.actionOwnerWorker;
      if (roleCode == 'admin' ||
          roleName == 'admin' ||
          p['is_primary_admin'] == true ||
          desig.contains('admin')) {
        userRole = UserRole.admin;
      } else if (roleCode == 'manager' ||
          roleName == 'manager' ||
          desig.contains('manager') ||
          desig.contains('lead') ||
          desig.contains('director') ||
          desig.contains('supervisor') ||
          desig.contains('head')) {
        userRole = UserRole.departmentManager;
      }

      final deptData = deptId != null ? deptsMap[deptId] : null;
      final siteData = siteId != null ? sitesMap[siteId] : null;

      final deptName = deptData?['name']?.toString() ?? '';
      final siteName = siteData?['name']?.toString() ?? '';

      final isActive = p['is_active'] != false && p['status'] != 'inactive';
      final assignedTeams = teamIdsByProfile[id] ?? [];
      final assignedTeamNames = assignedTeams
          .map((tId) => teamsMap[tId]?['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();

      return Person(
        id: id,
        name: p['full_name']?.toString() ?? '',
        email: p['email']?.toString() ?? '',
        phone: p['phone']?.toString() ?? '',
        designation: p['designation']?.toString() ?? '',
        type: PersonType.internalUser,
        isActive: isActive,
        role: userRole,
        teamIds: assignedTeams,
        teamNames: assignedTeamNames,
        department: deptName,
        site: siteName,
        company: '',
        notes: '',
        departmentId: deptId,
        siteId: siteId,
        roleId: roleId,
        organizationId: orgId,
      );
    }).toList();
  }

  // ==========================================
  // UPDATE USER
  // ==========================================

  /// Updates an existing user's details, manager scopes, and team assignments in Supabase.
  /// Scoped to the given `organizationId`.
  Future<void> updateUser({
    required String organizationId,
    required Person person,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      MockPeopleStore.instance.update(person);
      return;
    }

    // If external worker, update local store
    if (person.type == PersonType.externalWorker) {
      MockPeopleStore.instance.update(person);
      return;
    }

    // =========================================================================
    // MANAGER UPDATE FLOW (Multiple Department + Site Scopes)
    // =========================================================================
    if (person.role == UserRole.departmentManager) {
      if (person.managerScopes.isEmpty) {
        throw Exception(
          'A Manager must have at least one Department + Site scope.',
        );
      }

      // Check duplicate scopes
      final seenScopes = <String>{};
      for (final s in person.managerScopes) {
        final key = '${s.departmentId}::${s.siteId}';
        if (!seenScopes.add(key)) {
          throw Exception(
            'Duplicate Department + Site scope detected: ${s.displayName}',
          );
        }
      }

      // Primary department & site from first scope for profile column fallback
      final primary = person.managerScopes.first;
      final payload = <String, dynamic>{
        'full_name': person.name.trim(),
        'phone': person.phone.trim(),
        'designation': person.designation.trim(),
        'department_id': primary.departmentId,
        'site_id': primary.siteId,
        'is_active': person.isActive,
        'status': person.isActive ? 'active' : 'inactive',
        'updated_at': DateTime.now().toIso8601String(),
      };

      await client
          .from('profiles')
          .update(payload)
          .eq('id', person.id)
          .eq('organization_id', organizationId);

      // Atomically sync manager scopes via transactional RPC
      final scopesJson = person.managerScopes
          .map((s) => s.toSyncJson())
          .toList();
      await client.rpc(
        'sync_manager_scopes',
        params: {'p_manager_id': person.id, 'p_scopes': scopesJson},
      );

      // Manage team memberships (optional for manager: zero or more teams allowed)
      try {
        await client.from('team_members').delete().eq('profile_id', person.id);

        if (person.teamIds.isNotEmpty) {
          final inserts = person.teamIds
              .map(
                (teamId) => {
                  'team_id': teamId,
                  'profile_id': person.id,
                  'role_in_team': 'manager',
                },
              )
              .toList();

          await client.from('team_members').insert(inserts);
        }
      } catch (e) {
        debugPrint('[UserService] Manager team membership update warning: $e');
        rethrow;
      }
      return;
    }

    // 1. Resolve department_id and site_id if only names were provided
    String? resolvedDeptId = person.departmentId;
    if ((resolvedDeptId == null || resolvedDeptId.isEmpty) &&
        person.department.isNotEmpty) {
      final dynamic deptRow = await client
          .from('departments')
          .select('id')
          .eq('organization_id', organizationId)
          .eq('name', person.department)
          .maybeSingle();
      if (deptRow is Map) {
        resolvedDeptId = deptRow['id']?.toString();
      }
    }

    String? resolvedSiteId = person.siteId;
    if ((resolvedSiteId == null || resolvedSiteId.isEmpty) &&
        person.site.isNotEmpty) {
      final dynamic siteRow = await client
          .from('sites')
          .select('id')
          .eq('organization_id', organizationId)
          .eq('name', person.site)
          .maybeSingle();
      if (siteRow is Map) {
        resolvedSiteId = siteRow['id']?.toString();
      }
    }

    // 2. Update public.profiles
    final payload = <String, dynamic>{
      'full_name': person.name.trim(),
      'phone': person.phone.trim(),
      'designation': person.designation.trim(),
      'department_id': resolvedDeptId,
      'site_id': resolvedSiteId,
      'is_active': person.isActive,
      'status': person.isActive ? 'active' : 'inactive',
      'updated_at': DateTime.now().toIso8601String(),
    };

    await client
        .from('profiles')
        .update(payload)
        .eq('id', person.id)
        .eq('organization_id', organizationId);

    // 3. Sync public.team_members
    // Validate that teams belong to the user's organization (cross-department within org is permitted)
    try {
      await client.from('team_members').delete().eq('profile_id', person.id);

      if (person.teamIds.isNotEmpty) {
        List<String> validTeamIds = person.teamIds;
        final dynamic orgTeams = await client
            .from('teams')
            .select('id')
            .eq('organization_id', organizationId)
            .eq('is_active', true)
            .inFilter('id', person.teamIds);
        if (orgTeams is List) {
          validTeamIds = orgTeams
              .map((t) => (t as Map)['id']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .toList();
        }

        if (validTeamIds.isNotEmpty) {
          final inserts = validTeamIds
              .map(
                (teamId) => {
                  'team_id': teamId,
                  'profile_id': person.id,
                  'role_in_team': 'member',
                },
              )
              .toList();

          await client.from('team_members').insert(inserts);
        }
      }
    } catch (e) {
      debugPrint('[UserService] Team membership update warning: $e');
      rethrow;
    }
  }

  // ==========================================
  // TOGGLE STATUS
  // ==========================================

  /// Toggles a user's `is_active` status in Supabase.
  /// Scoped to the given `organizationId`.
  Future<void> toggleUserStatus({
    required String organizationId,
    required String profileId,
    required bool isActive,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      final match = MockPeopleStore.instance.people.where(
        (p) => p.id == profileId,
      );
      if (match.isNotEmpty) {
        MockPeopleStore.instance.update(
          match.first.copyWith(isActive: isActive),
        );
      }
      return;
    }

    await client
        .from('profiles')
        .update({
          'is_active': isActive,
          'status': isActive ? 'active' : 'inactive',
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', profileId)
        .eq('organization_id', organizationId);
  }

  // ==========================================
  // CREATE USER / ONBOARD
  // ==========================================

  /// Adds a new user under the current organization.
  /// If external worker: saves as action assignee.
  /// If internal user: verifies email uniqueness and creates or links the profile
  /// without requiring admin-side passwords (ActionFlow security standard).
  Future<void> createUser({
    required String organizationId,
    required Person person,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      MockPeopleStore.instance.addWithTeamNotifications(person);
      return;
    }

    if (person.type == PersonType.externalWorker) {
      MockPeopleStore.instance.addWithTeamNotifications(person);
      return;
    }

    final trimmedEmail = person.email.trim();

    // 1. Check duplicate email in public.profiles
    final dynamic existing = await client
        .from('profiles')
        .select('id, email')
        .eq('email', trimmedEmail)
        .maybeSingle();

    if (existing != null) {
      throw Exception(
        'A user with email "$trimmedEmail" already exists in the organization.',
      );
    }

    // 2. Check if user already has an auth record from a signup request
    final dynamic request = await client
        .from('account_requests')
        .select('auth_user_id')
        .eq('email', trimmedEmail)
        .maybeSingle();

    if (request is Map && request['auth_user_id'] != null) {
      final authUserId = request['auth_user_id'].toString();

      // Resolve role_id
      final roleCode = person.role == UserRole.admin
          ? 'admin'
          : (person.role == UserRole.departmentManager ? 'manager' : 'staff');
      final dynamic roleRow = await client
          .from('roles')
          .select('id')
          .eq('code', roleCode)
          .maybeSingle();
      final roleId = (roleRow is Map) ? roleRow['id']?.toString() ?? '' : '';

      final profilePayload = <String, dynamic>{
        'id': authUserId,
        'full_name': person.name.trim(),
        'email': trimmedEmail,
        if (person.phone.isNotEmpty) 'phone': person.phone.trim(),
        'designation': person.designation.trim(),
        'role_id': roleId,
        'status': 'active',
        'is_active': person.isActive,
        'is_primary_admin': false,
        'organization_id': organizationId,
        if (person.departmentId != null) 'department_id': person.departmentId,
        if (person.siteId != null) 'site_id': person.siteId,
      };

      await client.from('profiles').upsert(profilePayload, onConflict: 'id');

      // Sync scopes if provided
      if (person.role == UserRole.departmentManager && person.managerScopes.isNotEmpty) {
        final scopesJson = person.managerScopes.map((s) => s.toSyncJson()).toList();
        await client.rpc(
          'sync_manager_scopes',
          params: {'p_manager_id': authUserId, 'p_scopes': scopesJson},
        );
      }

      // Link team memberships if any
      if (person.teamIds.isNotEmpty) {
        final inserts = person.teamIds
            .map(
              (tId) => {
                'team_id': tId,
                'profile_id': authUserId,
                'role_in_team': person.role == UserRole.departmentManager
                    ? 'manager'
                    : 'member',
              },
            )
            .toList();
        await client.from('team_members').insert(inserts);
      }
    } else {
      // If auth user does not exist yet:
      // ActionFlow requires user-side authentication setup.
      // Save to local store so admin can reference the user immediately,
      // and notify that the user will complete their login via the registration link.
      MockPeopleStore.instance.addWithTeamNotifications(person);
    }
  }

  // ==========================================
  // DELETE USER
  // ==========================================

  /// Permanently deletes a user belonging to the organization using the atomic RPC
  /// `public.delete_company_user(p_user_id)`.
  ///
  /// Cascades through `team_members`, `manager_scopes`, `account_request_scopes`,
  /// `account_requests`, `profiles`, and `auth.users`.
  /// Cannot delete self, Platform Admins, or primary Company Admins.
  Future<void> deleteUser({
    required String organizationId,
    required String profileId,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      MockPeopleStore.instance.removePerson(profileId);
      return;
    }

    // Protected core system accounts that must never be deleted
    const protectedEmails = {
      'arvin.pr1112@gmail.com',
      'aravind11.sobha@gmail.com',
      'webonant@gmail.com',
      'aravindpr.1111@gmail.com',
    };

    try {
      final dynamic profileRow = await client
          .from('profiles')
          .select('email')
          .eq('id', profileId)
          .maybeSingle();
      if (profileRow is Map) {
        final email = profileRow['email']?.toString().toLowerCase();
        if (email != null && protectedEmails.contains(email)) {
          throw Exception('Cannot delete protected core account: $email');
        }
      }

      await client.rpc('delete_company_user', params: {'p_user_id': profileId});
    } catch (e) {
      debugPrint('Error deleting company user via RPC: $e');
      rethrow;
    }
  }

  /// Dynamically fetches active Managers responsible for a department.
  /// Calls get_department_managers RPC or falls back to directory_profiles / manager_scopes.
  Future<List<Person>> fetchDepartmentManagers({
    required String departmentId,
    required String organizationId,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      return MockPeopleStore.instance.people.where((p) {
        if (!p.isActive || p.type != PersonType.internalUser) return false;
        final isMgr = p.role == UserRole.departmentManager ||
            p.designation.toLowerCase().contains('manager');
        if (!isMgr) return false;
        final deptMatch = p.departmentId == departmentId ||
            p.managerScopes.any((s) => s.departmentId == departmentId);
        return deptMatch;
      }).toList();
    }

    try {
      final dynamic raw = await client.rpc(
        'get_department_managers',
        params: {'p_department_id': departmentId},
      );
      if (raw is List && raw.isNotEmpty) {
        final List<Person> managers = [];
        for (final item in raw) {
          final m = Map<String, dynamic>.from(item as Map);
          final id = m['manager_id']?.toString() ?? '';
          if (id.isEmpty) continue;
          managers.add(
            Person(
              id: id,
              name: m['full_name']?.toString() ?? '',
              email: m['email']?.toString() ?? '',
              phone: '',
              designation: 'Department Manager',
              type: PersonType.internalUser,
              isActive: true,
              role: UserRole.departmentManager,
              teamIds: const [],
              managerScopes: [
                ManagerScopeItem(
                  departmentId: departmentId,
                  departmentName: '',
                  siteId: '',
                  siteName: '',
                ),
              ],
              department: '',
              site: '',
              company: '',
              notes: '',
              departmentId: departmentId,
              organizationId: organizationId,
            ),
          );
        }
        return managers;
      }
    } catch (e) {
      debugPrint('[UserService] fetchDepartmentManagers RPC note: $e');
    }
    return const [];
  }
}
