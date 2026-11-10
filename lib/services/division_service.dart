import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/models/division.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service managing Organizational Divisions in ActionFlow.
/// Enforces multi-tenant isolation by requiring organizationId for all reads and mutations.
class DivisionService {
  DivisionService({SupabaseClient? client}) : _clientOverride = client;

  static final DivisionService instance = DivisionService();

  final SupabaseClient? _clientOverride;

  SupabaseClient? get _client => _clientOverride ?? SupabaseConfig.clientOrNull;

  bool get isReady => _client != null && SupabaseConfig.isInitialized;

  /// Fetches all divisions for an organization.
  /// If [onlyActive] is true, returns only active divisions (used for Manager Add Action).
  Future<List<Division>> fetchDivisions(
    String organizationId, {
    bool onlyActive = false,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      return [];
    }

    try {
      dynamic query = client
          .from('divisions')
          .select('*')
          .eq('organization_id', organizationId);

      if (onlyActive) {
        query = query.eq('is_active', true);
      }

      final response = await query.order('name', ascending: true);

      if (response == null || (response is List && response.isEmpty)) {
        return [];
      }

      // Fetch action counts per division
      final actionCounts = <String, int>{};
      try {
        final actCountsRes = await client
            .from('actions')
            .select('division_id')
            .eq('organization_id', organizationId)
            .not('division_id', 'is', null);

        for (final row in actCountsRes) {
          final dId = row['division_id']?.toString();
          if (dId != null && dId.isNotEmpty) {
            actionCounts[dId] = (actionCounts[dId] ?? 0) + 1;
          }
        }
      } catch (e) {
        debugPrint('[DivisionService] Note on action counts query: $e');
      }

      final List<Division> divisions = [];
      for (final row in response as List) {
        if (row is Map) {
          final data = Map<String, dynamic>.from(row);
          final id = data['id']?.toString() ?? '';
          data['action_count'] = actionCounts[id] ?? 0;
          divisions.add(Division.fromSupabase(data));
        }
      }

      return divisions;
    } catch (e) {
      debugPrint('[DivisionService] Error fetching divisions: $e');
      rethrow;
    }
  }

  /// Creates a new Division for the organization.
  Future<Division> createDivision({
    required String organizationId,
    required String name,
    required String code,
    required String description,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      throw Exception('Supabase is not initialized.');
    }

    try {
      final insertData = {
        'organization_id': organizationId,
        'name': name.trim(),
        'code': code.trim().toUpperCase(),
        'description': description.trim(),
        'is_active': true,
      };

      final response = await client
          .from('divisions')
          .insert(insertData)
          .select()
          .single();

      return Division.fromSupabase(Map<String, dynamic>.from(response));
    } on PostgrestException catch (pe) {
      if (pe.code == '23505' ||
          pe.message.contains('idx_divisions_org_name_lower')) {
        throw Exception(
          'A division named "$name" already exists in this company.',
        );
      }
      if (pe.code == '23505' ||
          pe.message.contains('idx_divisions_org_code_lower')) {
        throw Exception(
          'A division with code "${code.trim().toUpperCase()}" already exists in this company.',
        );
      }
      rethrow;
    } catch (e) {
      debugPrint('[DivisionService] Error creating division: $e');
      rethrow;
    }
  }

  /// Updates an existing Division's name, code, description, and optionally active status.
  Future<Division> updateDivision({
    required String divisionId,
    required String name,
    required String code,
    required String description,
    bool? isActive,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      throw Exception('Supabase is not initialized.');
    }

    try {
      final updateData = <String, dynamic>{
        'name': name.trim(),
        'code': code.trim().toUpperCase(),
        'description': description.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (isActive != null) {
        updateData['is_active'] = isActive;
      }

      final response = await client
          .from('divisions')
          .update(updateData)
          .eq('id', divisionId)
          .select()
          .single();

      return Division.fromSupabase(Map<String, dynamic>.from(response));
    } on PostgrestException catch (pe) {
      if (pe.code == '23505' ||
          pe.message.contains('idx_divisions_org_name_lower')) {
        throw Exception(
          'A division named "$name" already exists in this company.',
        );
      }
      if (pe.code == '23505' ||
          pe.message.contains('idx_divisions_org_code_lower')) {
        throw Exception(
          'A division with code "${code.trim().toUpperCase()}" already exists in this company.',
        );
      }
      rethrow;
    } catch (e) {
      debugPrint('[DivisionService] Error updating division: $e');
      rethrow;
    }
  }

  /// Targeted status toggle
  Future<void> setDivisionActive({
    required String divisionId,
    required bool isActive,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      throw Exception('Supabase is not initialized.');
    }

    await client
        .from('divisions')
        .update({
          'is_active': isActive,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', divisionId);
  }

  /// Deletes a Division safely using the atomic database RPC.
  /// If dependent actions exist, blocks deletion and returns structured error.
  Future<Map<String, dynamic>> deleteDivision({
    required String divisionId,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      throw Exception('Supabase is not initialized.');
    }

    try {
      final dynamic response = await client.rpc(
        'delete_division',
        params: {'p_division_id': divisionId},
      );

      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      return {'success': true};
    } catch (e) {
      debugPrint('[DivisionService] Error deleting division: $e');
      return {'success': false, 'message': e.toString()};
    }
  }
}
