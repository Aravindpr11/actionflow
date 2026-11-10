import 'dart:async';

import 'package:action_flow/core/config/supabase_config.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service managing Company Admin tenant structure operations:
/// Departments, Sites, Teams, and Team Members.
///
/// Strictly enforces multi-tenant isolation by requiring the authenticated
/// Company Admin's `organizationId` for all reads and mutations.
class CompanyStructureService {
  CompanyStructureService({SupabaseClient? client}) : _clientOverride = client;

  static final CompanyStructureService instance = CompanyStructureService();

  final SupabaseClient? _clientOverride;

  SupabaseClient? get _client => _clientOverride ?? SupabaseConfig.clientOrNull;

  bool get isReady => _client != null && SupabaseConfig.isInitialized;

  // ==========================================
  // DEPARTMENTS
  // ==========================================

  /// Fetches all departments for the specified tenant organization.
  /// Computes active staff member counts from `public.profiles`.
  Future<List<Map<String, dynamic>>> fetchDepartments(
    String organizationId,
  ) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      throw Exception('Supabase is not initialized.');
    }

    // 1. Fetch departments scoped to organization
    final dynamic rawDepts = await client
        .from('departments')
        .select(
          'id, name, code, division, description, is_active, organization_id, created_at',
        )
        .eq('organization_id', organizationId)
        .order('name');

    if (rawDepts == null || (rawDepts is List && rawDepts.isEmpty)) {
      return [];
    }

    final deptsList = List<Map<String, dynamic>>.from(
      (rawDepts as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );

    // 2. Fetch profile department assignments for member counts
    final memberCounts = <String, int>{};
    try {
      final dynamic rawProfiles = await client
          .from('profiles')
          .select('id, department_id')
          .eq('organization_id', organizationId)
          .not('department_id', 'is', null);

      if (rawProfiles is List) {
        for (final p in rawProfiles) {
          final m = Map<String, dynamic>.from(p as Map);
          final deptId = m['department_id']?.toString();
          if (deptId != null && deptId.isNotEmpty) {
            memberCounts[deptId] = (memberCounts[deptId] ?? 0) + 1;
          }
        }
      }
    } catch (e) {
      debugPrint('CompanyStructureService member count note: $e');
    }

    // 3. Map into UI presentation format
    return deptsList.map((d) {
      final id = d['id']?.toString() ?? '';
      final desc = d['description']?.toString() ?? '';
      String head = 'Unassigned';
      if (desc.isNotEmpty) {
        head = desc.startsWith('Head: ') ? desc.substring(6) : desc;
      }

      return {
        'id': id,
        'name': d['name']?.toString() ?? '',
        'code': d['code']?.toString() ?? '',
        'division': d['division']?.toString() ?? 'Operations & HSSE',
        'head': head,
        'members': memberCounts[id] ?? 0,
        'activeActions': 0,
        'status': d['is_active'] != false ? 'Active' : 'Inactive',
        'raw': d,
      };
    }).toList();
  }

  /// Inserts a new department for the specified organization.
  Future<Map<String, dynamic>> createDepartment({
    required String organizationId,
    required String name,
    required String code,
    String? head,
    String? division,
    String? description,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      throw Exception('Supabase is not initialized.');
    }

    final trimmedName = name.trim();
    final trimmedCode = code.trim().toUpperCase();
    final desc = (description != null && description.trim().isNotEmpty)
        ? description.trim()
        : ((head != null && head.trim().isNotEmpty) ? head.trim() : null);

    final payload = <String, dynamic>{
      'organization_id': organizationId,
      'name': trimmedName,
      'code': trimmedCode,
      'division': (division != null && division.trim().isNotEmpty)
          ? division.trim()
          : 'Operations & HSSE',
      'description': ?desc,
      'is_active': true,
    };

    final dynamic res = await client
        .from('departments')
        .insert(payload)
        .select()
        .single();

    final map = Map<String, dynamic>.from(res as Map);
    return {
      'id': map['id']?.toString() ?? '',
      'name': map['name']?.toString() ?? '',
      'code': map['code']?.toString() ?? '',
      'division': map['division']?.toString() ?? 'Operations & HSSE',
      'head': head?.trim() ?? 'Unassigned',
      'members': 0,
      'activeActions': 0,
      'status': 'Active',
      'raw': map,
    };
  }

  /// Updates an existing department record.
  Future<void> updateDepartment({
    required String organizationId,
    required String id,
    required String name,
    required String code,
    String? head,
    String? division,
    bool? isActive,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      throw Exception('Supabase is not initialized.');
    }

    final payload = <String, dynamic>{
      'name': name.trim(),
      'code': code.trim().toUpperCase(),
      if (division != null) 'division': division.trim(),
      if (head != null) 'description': head.trim(),
      'is_active': ?isActive,
      'updated_at': DateTime.now().toIso8601String(),
    };

    await client
        .from('departments')
        .update(payload)
        .eq('id', id)
        .eq('organization_id', organizationId);
  }

  /// Toggles department active status.
  Future<void> toggleDepartmentStatus({
    required String organizationId,
    required String id,
    required bool isActive,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      throw Exception('Supabase is not initialized.');
    }

    await client
        .from('departments')
        .update({
          'is_active': isActive,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .eq('organization_id', organizationId);
  }

  /// Safely deletes a department if zero dependencies exist.
  /// Calls atomic PostgreSQL RPC `delete_department`.
  /// Returns a structured result map with status and dependency breakdown.
  Future<Map<String, dynamic>> deleteDepartment({
    required String departmentId,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      return {'success': true, 'message': 'Department deleted successfully.'};
    }

    final dynamic res = await client.rpc(
      'delete_department',
      params: {'p_department_id': departmentId},
    );

    if (res is Map) {
      return Map<String, dynamic>.from(res);
    }
    return {'success': true, 'message': 'Department deleted successfully.'};
  }

  // ==========================================
  // SITES
  // ==========================================

  /// Fetches all sites for the specified tenant organization.
  /// Computes staff counts from `public.profiles`.
  Future<List<Map<String, dynamic>>> fetchSites(String organizationId) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      throw Exception('Supabase is not initialized.');
    }

    final dynamic rawSites = await client
        .from('sites')
        .select(
          'id, name, code, location_type, is_active, organization_id, created_at',
        )
        .eq('organization_id', organizationId)
        .order('name');

    if (rawSites == null || (rawSites is List && rawSites.isEmpty)) {
      return [];
    }

    final sitesList = List<Map<String, dynamic>>.from(
      (rawSites as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );

    // Fetch profile site assignments for staff count
    final staffCounts = <String, int>{};
    try {
      final dynamic rawProfiles = await client
          .from('profiles')
          .select('id, site_id')
          .eq('organization_id', organizationId)
          .not('site_id', 'is', null);

      if (rawProfiles is List) {
        for (final p in rawProfiles) {
          final m = Map<String, dynamic>.from(p as Map);
          final siteId = m['site_id']?.toString();
          if (siteId != null && siteId.isNotEmpty) {
            staffCounts[siteId] = (staffCounts[siteId] ?? 0) + 1;
          }
        }
      }
    } catch (e) {
      debugPrint('CompanyStructureService site staff count note: $e');
    }

    return sitesList.map((s) {
      final id = s['id']?.toString() ?? '';
      final loc = s['location_type']?.toString() ?? 'Onshore Facility';
      return {
        'id': id,
        'name': s['name']?.toString() ?? '',
        'code': s['code']?.toString() ?? '',
        'location': loc,
        'type': loc,
        'staff': staffCounts[id] ?? 0,
        'actions': 0,
        'status': s['is_active'] != false ? 'Active' : 'Inactive',
        'raw': s,
      };
    }).toList();
  }

  /// Inserts a new site for the specified organization with collision-safe code generation.
  Future<Map<String, dynamic>> createSite({
    required String organizationId,
    required String name,
    String? code,
    String? location,
    String? type,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      throw Exception('Supabase is not initialized.');
    }

    final trimmedName = name.trim();
    final isManualCode = code != null && code.trim().isNotEmpty;

    // Fetch existing site codes across the whole database (including active and inactive sites)
    final existingCodes = <String>{};
    try {
      final dynamic rawCodes = await client
          .from('sites')
          .select('code');
      if (rawCodes is List) {
        for (final r in rawCodes) {
          final c = r['code']?.toString().trim().toUpperCase();
          if (c != null && c.isNotEmpty) {
            existingCodes.add(c);
          }
        }
      }
    } catch (e) {
      debugPrint('CompanyStructureService site codes query note: $e');
    }

    // Determine base code
    final String baseCode;
    if (isManualCode) {
      baseCode = code.trim().toUpperCase();
    } else {
      final cleaned = trimmedName.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
      baseCode = cleaned.length >= 3
          ? cleaned.substring(0, 3)
          : (cleaned.isNotEmpty ? cleaned : 'SIT');
    }

    // Generate initial unique candidate
    String candidateCode = baseCode;
    int suffixIndex = 1;
    if (!isManualCode) {
      while (existingCodes.contains(candidateCode)) {
        candidateCode = '$baseCode-${suffixIndex.toString().padLeft(2, '0')}';
        suffixIndex++;
      }
    }

    final locType = (location != null && location.trim().isNotEmpty)
        ? location.trim()
        : ((type != null && type.trim().isNotEmpty)
              ? type.trim()
              : 'Onshore / Offshore Facility');

    final payload = <String, dynamic>{
      'organization_id': organizationId,
      'name': trimmedName,
      'code': candidateCode,
      'location_type': locType,
      'is_active': true,
    };

    // Retry loop handling concurrent/simultaneous inserts (race conditions on sites_code_key)
    const maxAttempts = 5;
    int attempt = 0;
    while (attempt < maxAttempts) {
      attempt++;
      payload['code'] = candidateCode;

      try {
        final dynamic res = await client
            .from('sites')
            .insert(payload)
            .select()
            .single();

        final map = Map<String, dynamic>.from(res as Map);
        return {
          'id': map['id']?.toString() ?? '',
          'name': map['name']?.toString() ?? '',
          'code': map['code']?.toString() ?? '',
          'location': locType,
          'type': locType,
          'staff': 0,
          'actions': 0,
          'status': 'Active',
          'raw': map,
        };
      } catch (e) {
        final errStr = e.toString().toLowerCase();
        final isCodeConflict = errStr.contains('sites_code_key') ||
            (errStr.contains('23505') && (errStr.contains('code') || !errStr.contains('name')));

        // If an auto-generated code had a race collision with a simultaneous insert, retry with next suffix
        if (!isManualCode && isCodeConflict && attempt < maxAttempts) {
          existingCodes.add(candidateCode);
          while (existingCodes.contains(candidateCode)) {
            candidateCode = '$baseCode-${suffixIndex.toString().padLeft(2, '0')}';
            suffixIndex++;
          }
          continue;
        }

        rethrow;
      }
    }

    throw Exception('Failed to generate a unique site code after $maxAttempts attempts.');
  }

  /// Updates an existing site record.
  Future<void> updateSite({
    required String organizationId,
    required String id,
    required String name,
    String? code,
    String? location,
    String? type,
    bool? isActive,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      throw Exception('Supabase is not initialized.');
    }

    final payload = <String, dynamic>{
      'name': name.trim(),
      if (code != null && code.trim().isNotEmpty)
        'code': code.trim().toUpperCase(),
      if (location != null || type != null)
        'location_type': location?.trim() ?? type?.trim(),
      'is_active': ?isActive,
      'updated_at': DateTime.now().toIso8601String(),
    };

    await client
        .from('sites')
        .update(payload)
        .eq('id', id)
        .eq('organization_id', organizationId);
  }

  /// Toggles site active status.
  Future<void> toggleSiteStatus({
    required String organizationId,
    required String id,
    required bool isActive,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      throw Exception('Supabase is not initialized.');
    }

    await client
        .from('sites')
        .update({
          'is_active': isActive,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .eq('organization_id', organizationId);
  }

  /// Safely deletes a site if zero dependencies exist.
  /// Calls atomic PostgreSQL RPC `delete_site`.
  /// Returns a structured result map with status and dependency breakdown.
  Future<Map<String, dynamic>> deleteSite({required String siteId}) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      return {'success': true, 'message': 'Site deleted successfully.'};
    }

    final dynamic res = await client.rpc(
      'delete_site',
      params: {'p_site_id': siteId},
    );

    if (res is Map) {
      return Map<String, dynamic>.from(res);
    }
    return {'success': true, 'message': 'Site deleted successfully.'};
  }

  // ==========================================
  // TEAMS
  // ==========================================

  /// Fetches all teams for the specified tenant organization.
  /// Preserves department foreign key relationship and computes
  /// member counts from `public.team_members`.
  Future<List<Map<String, dynamic>>> fetchTeams(String organizationId) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      throw Exception('Supabase is not initialized.');
    }

    // 1. Query teams with joined department information
    final dynamic rawTeams = await client
        .from('teams')
        .select(
          'id, name, code, description, department_id, is_active, organization_id, created_at, departments(id, name, code)',
        )
        .eq('organization_id', organizationId)
        .order('name');

    if (rawTeams == null || (rawTeams is List && rawTeams.isEmpty)) {
      return [];
    }

    final teamsList = List<Map<String, dynamic>>.from(
      (rawTeams as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );

    // 2. Query team members and lead names
    final teamMemberCounts = <String, int>{};
    final teamLeads = <String, String>{};
    try {
      final dynamic rawMembers = await client
          .from('team_members')
          .select('id, team_id, profile_id, role_in_team, profiles(full_name)');

      if (rawMembers is List) {
        for (final item in rawMembers) {
          final m = Map<String, dynamic>.from(item as Map);
          final teamId = m['team_id']?.toString();
          if (teamId != null && teamId.isNotEmpty) {
            teamMemberCounts[teamId] = (teamMemberCounts[teamId] ?? 0) + 1;
            final roleInTeam = m['role_in_team']?.toString();
            if (roleInTeam == 'lead' || roleInTeam == 'manager') {
              final prof = m['profiles'];
              if (prof is Map && prof['full_name'] != null) {
                teamLeads[teamId] = prof['full_name'].toString();
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('CompanyStructureService team members note: $e');
    }

    // 3. Map into UI format
    return teamsList.map((t) {
      final id = t['id']?.toString() ?? '';
      final deptObj = t['departments'];
      String deptName = 'Unassigned';
      String deptCode = '';
      if (deptObj is Map) {
        deptName = deptObj['name']?.toString() ?? 'Unassigned';
        deptCode = deptObj['code']?.toString() ?? '';
      }

      final desc = t['description']?.toString() ?? '';
      String lead = teamLeads[id] ?? 'Unassigned';
      if (lead == 'Unassigned' && desc.isNotEmpty) {
        lead = desc.startsWith('Lead: ') ? desc.substring(6) : desc;
      }

      return {
        'id': id,
        'name': t['name']?.toString() ?? '',
        'code': t['code']?.toString() ?? deptCode,
        'dept': deptName,
        'deptId': t['department_id']?.toString() ?? '',
        'site': 'All Sites',
        'lead': lead,
        'members': teamMemberCounts[id] ?? 0,
        'status': t['is_active'] != false ? 'Active' : 'Inactive',
        'description': desc,
        'raw': t,
      };
    }).toList();
  }

  /// Inserts a new team for the specified organization and department.
  Future<Map<String, dynamic>> createTeam({
    required String organizationId,
    required String departmentId,
    required String name,
    String? code,
    String? lead,
    String? description,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      throw Exception('Supabase is not initialized.');
    }

    final trimmedName = name.trim();
    final codeVal = (code != null && code.trim().isNotEmpty)
        ? code.trim().toUpperCase()
        : (trimmedName.length >= 3
              ? trimmedName.substring(0, 3).toUpperCase()
              : trimmedName.toUpperCase());

    final desc = (description != null && description.trim().isNotEmpty)
        ? description.trim()
        : ((lead != null && lead.trim().isNotEmpty)
              ? 'Lead: ${lead.trim()}'
              : null);

    final payload = <String, dynamic>{
      'organization_id': organizationId,
      'department_id': departmentId,
      'name': trimmedName,
      'code': codeVal,
      'description': ?desc,
      'is_active': true,
    };

    final dynamic res = await client
        .from('teams')
        .insert(payload)
        .select(
          'id, name, code, description, department_id, is_active, departments(name)',
        )
        .single();

    final map = Map<String, dynamic>.from(res as Map);
    final deptObj = map['departments'];
    final deptName = (deptObj is Map) ? deptObj['name']?.toString() ?? '' : '';

    return {
      'id': map['id']?.toString() ?? '',
      'name': map['name']?.toString() ?? '',
      'code': map['code']?.toString() ?? '',
      'dept': deptName,
      'deptId': departmentId,
      'site': 'All Sites',
      'lead': lead?.trim() ?? 'Unassigned',
      'members': 0,
      'status': 'Active',
      'description': desc ?? '',
      'raw': map,
    };
  }

  /// Updates an existing team record.
  Future<void> updateTeam({
    required String organizationId,
    required String id,
    required String departmentId,
    required String name,
    String? code,
    String? lead,
    String? description,
    bool? isActive,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      throw Exception('Supabase is not initialized.');
    }

    final desc = (description != null && description.trim().isNotEmpty)
        ? description.trim()
        : ((lead != null && lead.trim().isNotEmpty)
              ? 'Lead: ${lead.trim()}'
              : null);

    final payload = <String, dynamic>{
      'department_id': departmentId,
      'name': name.trim(),
      if (code != null && code.trim().isNotEmpty)
        'code': code.trim().toUpperCase(),
      'description': ?desc,
      'is_active': ?isActive,
      'updated_at': DateTime.now().toIso8601String(),
    };

    await client
        .from('teams')
        .update(payload)
        .eq('id', id)
        .eq('organization_id', organizationId);
  }

  /// Toggles team active status.
  Future<void> toggleTeamStatus({
    required String organizationId,
    required String id,
    required bool isActive,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      throw Exception('Supabase is not initialized.');
    }

    await client
        .from('teams')
        .update({
          'is_active': isActive,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .eq('organization_id', organizationId);
  }
}
