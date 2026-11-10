import 'dart:async';

import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/models/platform_audit_log.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Typedef alias for backwards compatibility
typedef PlatformAuditEvent = PlatformAuditLog;

/// Service layer for recording and querying platform governance and security audit events.
class PlatformAuditService {
  PlatformAuditService._();
  static final PlatformAuditService instance = PlatformAuditService._();

  SupabaseClient? _customClient;

  @visibleForTesting
  void setClientForTesting(SupabaseClient? client) {
    _customClient = client;
  }

  SupabaseClient? get _client => _customClient ?? SupabaseConfig.clientOrNull;

  final List<PlatformAuditLog> _inMemoryLogs = [];

  @visibleForTesting
  void clearInMemoryLogs() {
    _inMemoryLogs.clear();
  }

  /// Fetches platform audit events, filtered by category and search query.
  /// Re-queries the live Supabase database whenever connected.
  Future<List<PlatformAuditLog>> fetchAuditLogs({
    String? category,
    String? searchQuery,
    int limit = 100,
  }) async {
    final client = _client;

    if (client != null && SupabaseConfig.isInitialized) {
      try {
        var query = client.from('platform_audit_logs').select();

        if (category != null &&
            category.trim().isNotEmpty &&
            category.toLowerCase() != 'all' &&
            category.toLowerCase() != 'all events') {
          final catLower = category.trim().toLowerCase();
          if (catLower == 'tenancy_delete') {
            query = query.eq('event_type', 'organization_deleted');
          } else {
            query = query.eq('category', catLower);
          }
        }

        final dynamic response = await query
            .order('created_at', ascending: false)
            .limit(limit);

        if (response is List) {
          var events = response
              .map(
                (row) => PlatformAuditLog.fromJson(
                  Map<String, dynamic>.from(row as Map),
                ),
              )
              .toList();

          if (searchQuery != null && searchQuery.trim().isNotEmpty) {
            final q = searchQuery.trim().toLowerCase();
            events = events.where((e) {
              final detailsStr = e.details.values.join(' ').toLowerCase();
              return e.description.toLowerCase().contains(q) ||
                  (e.actorEmail?.toLowerCase().contains(q) ?? false) ||
                  (e.actorId?.toLowerCase().contains(q) ?? false) ||
                  (e.action.toLowerCase().contains(q)) ||
                  (e.eventType.toLowerCase().contains(q)) ||
                  (e.organizationName?.toLowerCase().contains(q) ?? false) ||
                  (e.organizationCode?.toLowerCase().contains(q) ?? false) ||
                  (e.displayOrganization.toLowerCase().contains(q)) ||
                  (e.organizationId?.toLowerCase().contains(q) ?? false) ||
                  (e.targetType?.toLowerCase().contains(q) ?? false) ||
                  (e.targetId?.toLowerCase().contains(q) ?? false) ||
                  detailsStr.contains(q);
            }).toList();
          }

          // Keep in-memory cache synchronized with live events
          for (final ev in events) {
            if (!_inMemoryLogs.any((m) => m.id == ev.id)) {
              _inMemoryLogs.add(ev);
            }
          }
          _inMemoryLogs.sort((a, b) => b.createdAt.compareTo(a.createdAt));

          return events;
        }
      } catch (e) {
        debugPrint('[PlatformAuditService] fetchAuditLogs error: $e');
        // If query failed due to offline/mock environment, fall through to in-memory
      }
    }

    // Offline / testing fallback
    var list = List<PlatformAuditLog>.from(_inMemoryLogs);
    if (category != null &&
        category.trim().isNotEmpty &&
        category.toLowerCase() != 'all' &&
        category.toLowerCase() != 'all events') {
      final cat = category.trim().toLowerCase();
      if (cat == 'tenancy_delete') {
        list = list
            .where((e) => e.eventType == 'organization_deleted')
            .toList();
      } else {
        list = list.where((e) => e.category.toLowerCase() == cat).toList();
      }
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      list = list.where((e) {
        final detailsStr = e.details.values.join(' ').toLowerCase();
        return e.description.toLowerCase().contains(q) ||
            (e.actorEmail?.toLowerCase().contains(q) ?? false) ||
            (e.actorId?.toLowerCase().contains(q) ?? false) ||
            (e.action.toLowerCase().contains(q)) ||
            (e.eventType.toLowerCase().contains(q)) ||
            (e.organizationName?.toLowerCase().contains(q) ?? false) ||
            (e.organizationCode?.toLowerCase().contains(q) ?? false) ||
            (e.displayOrganization.toLowerCase().contains(q)) ||
            (e.organizationId?.toLowerCase().contains(q) ?? false) ||
            (e.targetType?.toLowerCase().contains(q) ?? false) ||
            (e.targetId?.toLowerCase().contains(q) ?? false) ||
            detailsStr.contains(q);
      }).toList();
    }

    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.take(limit).toList();
  }

  /// Records an immutable platform audit event into public.platform_audit_logs.
  Future<void> recordAuditEvent({
    required String eventType,
    String category = 'governance',
    String severity = 'info',
    required String description,
    String? organizationId,
    String? organizationName,
    String? organizationCode,
    String? targetType,
    String? targetId,
    Map<String, dynamic> metadata = const {},
  }) async {
    final client = _client;
    final now = DateTime.now();

    // Sanitize organizationId: must be a valid 36-char UUID or null
    final trimmedOrg = organizationId?.trim();
    final bool isValidUuid =
        trimmedOrg != null &&
        RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(trimmedOrg);
    final String? validOrgId = isValidUuid ? trimmedOrg : null;

    final enrichedMeta = Map<String, dynamic>.from(metadata);
    if (trimmedOrg != null && !isValidUuid) {
      enrichedMeta['organization_id_raw'] = trimmedOrg;
    }
    if (organizationName != null && organizationName.trim().isNotEmpty) {
      enrichedMeta['organization_name'] = organizationName.trim();
    }
    if (organizationCode != null && organizationCode.trim().isNotEmpty) {
      enrichedMeta['organization_code'] = organizationCode.trim();
    }

    final localEvent = PlatformAuditLog(
      id: 'local-${now.millisecondsSinceEpoch}',
      createdAt: now,
      eventType: eventType,
      category: category,
      severity: severity,
      actorId: client?.auth.currentUser?.id,
      actorEmail: client?.auth.currentUser?.email,
      organizationId: validOrgId,
      organizationName: organizationName?.trim(),
      organizationCode: organizationCode?.trim(),
      targetType: targetType,
      targetId: targetId,
      description: description,
      details: enrichedMeta,
    );

    _inMemoryLogs.insert(0, localEvent);

    if (client != null && SupabaseConfig.isInitialized) {
      final payload = {
        'event_type': eventType,
        'category': category,
        'severity': severity,
        'actor_id': client.auth.currentUser?.id,
        'actor_email': client.auth.currentUser?.email,
        'organization_id': validOrgId,
        'organization_name': organizationName?.trim(),
        'organization_code': organizationCode?.trim(),
        'target_type': targetType,
        'target_id': targetId,
        'description': description,
        'metadata': enrichedMeta,
      };

      try {
        await client.from('platform_audit_logs').insert(payload);
      } catch (insertErr) {
        debugPrint(
          '[PlatformAuditService] Direct insert note: $insertErr. Attempting RPC fallback...',
        );
        try {
          await client.rpc(
            'record_platform_audit_event',
            params: {
              'p_event_type': eventType,
              'p_category': category,
              'p_severity': severity,
              'p_description': description,
              'p_organization_id': validOrgId,
              'p_target_type': targetType,
              'p_target_id': targetId,
              'p_metadata': enrichedMeta,
              'p_organization_name': organizationName?.trim(),
              'p_organization_code': organizationCode?.trim(),
            },
          );
        } catch (rpcErr) {
          debugPrint(
            '[PlatformAuditService] record_platform_audit_event RPC note: $rpcErr',
          );
        }
      }
    }
  }
}
