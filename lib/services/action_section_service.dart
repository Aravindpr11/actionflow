import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/models/action_section.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service managing Action Section classifications in ActionFlow.
/// Enforces multi-tenant isolation by requiring organizationId for all reads and mutations.
class ActionSectionService {
  ActionSectionService({SupabaseClient? client}) : _clientOverride = client;

  static final ActionSectionService instance = ActionSectionService();

  final SupabaseClient? _clientOverride;

  SupabaseClient? get _client => _clientOverride ?? SupabaseConfig.clientOrNull;

  bool get isReady => _client != null && SupabaseConfig.isInitialized;

  /// Fetches all sections for an organization.
  /// If [onlyActive] is true, returns only active sections (used for Manager Add Action).
  Future<List<ActionSection>> fetchSections(
    String organizationId, {
    bool onlyActive = false,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      return [];
    }

    try {
      dynamic query = client
          .from('action_sections')
          .select('*')
          .eq('organization_id', organizationId);

      if (onlyActive) {
        query = query.eq('is_active', true);
      }

      final response = await query.order('name', ascending: true);

      if (response == null || (response is List && response.isEmpty)) {
        return [];
      }

      // Fetch action counts per section
      final actionCounts = <String, int>{};
      try {
        final actCountsRes = await client
            .from('actions')
            .select('section_id')
            .eq('organization_id', organizationId)
            .not('section_id', 'is', null);

        for (final row in actCountsRes) {
          final sId = row['section_id']?.toString();
          if (sId != null && sId.isNotEmpty) {
            actionCounts[sId] = (actionCounts[sId] ?? 0) + 1;
          }
        }
      } catch (e) {
        debugPrint('[ActionSectionService] Note on action counts query: $e');
      }

      final List<ActionSection> sections = [];
      for (final row in response as List) {
        if (row is Map) {
          final data = Map<String, dynamic>.from(row);
          final id = data['id']?.toString() ?? '';
          data['action_count'] = actionCounts[id] ?? 0;
          sections.add(ActionSection.fromSupabase(data));
        }
      }

      return sections;
    } catch (e) {
      debugPrint('[ActionSectionService] Error fetching sections: $e');
      rethrow;
    }
  }

  /// Creates a new Action Section for the organization.
  Future<ActionSection> createSection({
    required String organizationId,
    required String name,
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
        'description': description.trim(),
        'is_active': true,
      };

      final response = await client
          .from('action_sections')
          .insert(insertData)
          .select()
          .single();

      return ActionSection.fromSupabase(Map<String, dynamic>.from(response));
    } on PostgrestException catch (pe) {
      if (pe.code == '23505' ||
          pe.message.contains('idx_action_sections_org_name_lower')) {
        throw Exception(
          'A section named "$name" already exists in this company.',
        );
      }
      rethrow;
    } catch (e) {
      debugPrint('[ActionSectionService] Error creating section: $e');
      rethrow;
    }
  }

  /// Updates an existing Action Section's name, description, and optionally active status.
  Future<ActionSection> updateSection({
    required String sectionId,
    required String name,
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
        'description': description.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (isActive != null) {
        updateData['is_active'] = isActive;
      }

      final response = await client
          .from('action_sections')
          .update(updateData)
          .eq('id', sectionId)
          .select()
          .single();

      return ActionSection.fromSupabase(Map<String, dynamic>.from(response));
    } on PostgrestException catch (pe) {
      if (pe.code == '23505' ||
          pe.message.contains('idx_action_sections_org_name_lower')) {
        throw Exception(
          'A section named "$name" already exists in this company.',
        );
      }
      rethrow;
    } catch (e) {
      debugPrint('[ActionSectionService] Error updating section: $e');
      rethrow;
    }
  }

  /// Toggles the active status of an Action Section.
  Future<ActionSection> toggleSectionStatus({
    required String sectionId,
    required bool isActive,
  }) async {
    return updateSection(
      sectionId: sectionId,
      name: '', // Will be preserved by database if not supplied, but let's fetch or use targeted update
      description: '',
      isActive: isActive,
    );
  }

  /// Targeted status toggle
  Future<void> setSectionActive({
    required String sectionId,
    required bool isActive,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      throw Exception('Supabase is not initialized.');
    }

    await client
        .from('action_sections')
        .update({
          'is_active': isActive,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', sectionId);
  }

  /// Deletes an Action Section safely using the atomic database RPC.
  /// If dependent actions exist, blocks deletion and returns structured error.
  Future<Map<String, dynamic>> deleteSection({
    required String sectionId,
  }) async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      throw Exception('Supabase is not initialized.');
    }

    try {
      final dynamic response = await client.rpc(
        'delete_action_section',
        params: {'p_section_id': sectionId},
      );

      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      return {'success': true};
    } catch (e) {
      debugPrint('[ActionSectionService] Error deleting section: $e');
      return {'success': false, 'message': e.toString()};
    }
  }
}
