import 'dart:async';

import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/services/platform_audit_service.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Represents a configurable platform setting.
class PlatformSetting {
  final String key;
  final String category;
  final dynamic value;
  final String? description;
  final bool isSecret;
  final DateTime? updatedAt;
  final String? updatedBy;

  const PlatformSetting({
    required this.key,
    required this.category,
    required this.value,
    this.description,
    this.isSecret = false,
    this.updatedAt,
    this.updatedBy,
  });

  factory PlatformSetting.fromJson(Map<String, dynamic> json) {
    dynamic val = json['value'];
    if (val is Map && val.containsKey('value')) {
      val = val['value'];
    }

    return PlatformSetting(
      key: json['key']?.toString() ?? '',
      category: json['category']?.toString() ?? 'general',
      value: val,
      description: json['description']?.toString(),
      isSecret: json['is_secret'] == true,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
      updatedBy: json['updated_by']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'category': category,
      'value': {'value': value},
      'description': description,
      'is_secret': isSecret,
      'updated_at': updatedAt?.toIso8601String(),
      'updated_by': updatedBy,
    };
  }
}

/// Service layer for loading and persisting platform configuration settings in public.platform_settings.
class PlatformSettingsService {
  PlatformSettingsService._();
  static final PlatformSettingsService instance = PlatformSettingsService._();

  SupabaseClient? _customClient;

  @visibleForTesting
  void setClientForTesting(SupabaseClient? client) {
    _customClient = client;
  }

  SupabaseClient? get _client => _customClient ?? SupabaseConfig.clientOrNull;

  final Map<String, PlatformSetting> _cachedSettings = {
    'platform_name': const PlatformSetting(
      key: 'platform_name',
      category: 'general',
      value: 'ActionFlow HSE Multi-Tenant Portal',
      description: 'Public name of the ActionFlow multi-tenant platform',
    ),
    'primary_support_email': const PlatformSetting(
      key: 'primary_support_email',
      category: 'general',
      value: 'platform-support@actionflow.internal',
      description: 'Global system and support contact email',
    ),
    'maintenance_mode': const PlatformSetting(
      key: 'maintenance_mode',
      category: 'general',
      value: false,
      description: 'Emergency maintenance mode switch',
    ),
    'session_timeout_minutes': const PlatformSetting(
      key: 'session_timeout_minutes',
      category: 'security',
      value: 60,
      description: 'Idle session timeout in minutes for administrative portals',
    ),
    'require_mfa_for_admins': const PlatformSetting(
      key: 'require_mfa_for_admins',
      category: 'security',
      value: true,
      description:
          'Mandatory 2FA enforcement policy for all Company Administrators',
    ),
    'allow_cross_tenant_view': const PlatformSetting(
      key: 'allow_cross_tenant_view',
      category: 'security',
      value: false,
      description: 'Strict multi-tenant isolation switch',
    ),
    'audit_retention_days': const PlatformSetting(
      key: 'audit_retention_days',
      category: 'governance',
      value: 365,
      description:
          'Immutability and retention period in days for global audit logs',
    ),
  };

  /// Loads all platform settings from public.platform_settings.
  Future<Map<String, PlatformSetting>> fetchSettings() async {
    final client = _client;

    if (client != null && SupabaseConfig.isInitialized) {
      try {
        final dynamic rows = await client.from('platform_settings').select();
        if (rows is List) {
          for (final r in rows) {
            final setting = PlatformSetting.fromJson(
              Map<String, dynamic>.from(r as Map),
            );
            _cachedSettings[setting.key] = setting;
          }
        }
      } catch (e) {
        debugPrint('[PlatformSettingsService] fetchSettings note: $e');
      }
    }

    return Map<String, PlatformSetting>.unmodifiable(_cachedSettings);
  }

  /// Updates a specific platform setting and records a traceability audit event.
  Future<void> updateSetting({
    required String key,
    required dynamic value,
  }) async {
    final client = _client;
    final existing = _cachedSettings[key];
    final category = existing?.category ?? 'general';
    final description = existing?.description;
    final now = DateTime.now();

    final updated = PlatformSetting(
      key: key,
      category: category,
      value: value,
      description: description,
      isSecret: existing?.isSecret ?? false,
      updatedAt: now,
      updatedBy: client?.auth.currentUser?.id,
    );

    _cachedSettings[key] = updated;

    if (client != null && SupabaseConfig.isInitialized) {
      try {
        await client.from('platform_settings').upsert({
          'key': key,
          'category': category,
          'value': {'value': value},
          'updated_at': now.toIso8601String(),
          'updated_by': client.auth.currentUser?.id,
        });

        // Record audit event for setting change
        await PlatformAuditService.instance.recordAuditEvent(
          eventType: 'setting_updated',
          category: 'configuration',
          severity: 'info',
          description: 'Platform setting "$key" updated to: $value',
          targetType: 'setting',
          targetId: key,
          metadata: {'previous_value': existing?.value, 'new_value': value},
        );
      } catch (e) {
        debugPrint('[PlatformSettingsService] updateSetting error: $e');
        rethrow;
      }
    }
  }

  /// Gets a cached setting value or fallback.
  T? getSettingValue<T>(String key, {T? defaultValue}) {
    final val = _cachedSettings[key]?.value;
    if (val is T) return val;
    return defaultValue;
  }
}
