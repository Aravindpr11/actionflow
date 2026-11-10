import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Configuration and initialization layer for ActionFlow Supabase backend
class SupabaseConfig {
  SupabaseConfig._();

  /// Production project URL
  static const String productionProjectUrl =
      'https://mxaptaudaqrtwiguosvt.supabase.co';

  /// Production public publishable anon key
  static const String productionAnonKey =
      'sb_publishable_RUdq4T4DCvSNwPHx5cEaNQ_ppYiVTol';

  /// Local development preset URL
  static const String localProjectUrl = 'http://127.0.0.1:54321';

  /// Local development anon key
  static const String localAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';

  /// Explicit flag to switch to local development stack:
  /// Pass --dart-define=USE_LOCAL_SUPABASE=true to connect to local Docker Supabase.
  static const bool useLocalSupabase = bool.fromEnvironment(
    'USE_LOCAL_SUPABASE',
    defaultValue: false,
  );

  /// Default project URL:
  /// Defaults to cloud Supabase so normal development, testing, and production connect to the cloud project.
  /// Local Supabase is selected only when USE_LOCAL_SUPABASE=true.
  static const String defaultProjectUrl =
      useLocalSupabase ? localProjectUrl : productionProjectUrl;

  /// Default publishable key:
  static const String defaultPublishableKey =
      useLocalSupabase ? localAnonKey : productionAnonKey;

  /// Supabase project URL (configurable via compile-time --dart-define=SUPABASE_URL=... or custom initializer)
  static String projectUrl = const String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: defaultProjectUrl,
  );

  /// Compile-time environment define for SUPABASE_PUBLISHABLE_KEY
  static const String _envPublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: '',
  );

  /// Compile-time environment define for SUPABASE_ANON_KEY
  static const String _envAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Supabase public publishable key (resolves SUPABASE_PUBLISHABLE_KEY, then SUPABASE_ANON_KEY, then defaultPublishableKey)
  static String publishableKey = _envPublishableKey.isNotEmpty
      ? _envPublishableKey
      : (_envAnonKey.isNotEmpty ? _envAnonKey : defaultPublishableKey);

  /// Supabase anonymous key (resolves SUPABASE_ANON_KEY, then SUPABASE_PUBLISHABLE_KEY, then defaultPublishableKey)
  static String anonKey = _envAnonKey.isNotEmpty
      ? _envAnonKey
      : (_envPublishableKey.isNotEmpty ? _envPublishableKey : defaultPublishableKey);

  /// Initializes the Supabase client connection (supports optional local testing overrides)
  static Future<void> initialize({
    String? url,
    String? customPublishableKey,
    String? customAnonKey,
  }) async {
    String targetUrl = url ?? projectUrl;
    if (useLocalSupabase && kIsWeb) {
      final host = Uri.base.host;
      if (host.isNotEmpty && host != 'localhost' && host != '127.0.0.1') {
        targetUrl = 'http://$host:54321';
      }
    }
    final effectiveKey = customPublishableKey ??
        customAnonKey ??
        (_envPublishableKey.isNotEmpty ? _envPublishableKey : null) ??
        (_envAnonKey.isNotEmpty ? _envAnonKey : null) ??
        publishableKey;

    await Supabase.initialize(
      url: targetUrl,
      publishableKey: effectiveKey,
    );
  }

  /// Global Supabase client instance
  static SupabaseClient get client => Supabase.instance.client;

  /// Optional testing override for isInitialized
  static bool? isInitializedForTesting;

  /// Safely checks if the Supabase instance has been initialized
  static bool get isInitialized {
    if (isInitializedForTesting != null) {
      return isInitializedForTesting!;
    }
    try {
      Supabase.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Returns the Supabase client instance if initialized, or null otherwise
  static SupabaseClient? get clientOrNull {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }
}

