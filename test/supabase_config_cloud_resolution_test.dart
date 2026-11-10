import 'package:action_flow/core/config/supabase_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SupabaseConfig Cloud Resolution Tests', () {
    test('Default configuration resolves to Cloud Supabase URL and Publishable Key', () {
      expect(SupabaseConfig.productionProjectUrl, 'https://mxaptaudaqrtwiguosvt.supabase.co');
      expect(SupabaseConfig.productionAnonKey, 'sb_publishable_RUdq4T4DCvSNwPHx5cEaNQ_ppYiVTol');
      expect(SupabaseConfig.defaultProjectUrl, 'https://mxaptaudaqrtwiguosvt.supabase.co');
      expect(SupabaseConfig.defaultPublishableKey, 'sb_publishable_RUdq4T4DCvSNwPHx5cEaNQ_ppYiVTol');
      expect(SupabaseConfig.projectUrl, 'https://mxaptaudaqrtwiguosvt.supabase.co');
      expect(SupabaseConfig.publishableKey, 'sb_publishable_RUdq4T4DCvSNwPHx5cEaNQ_ppYiVTol');
      expect(SupabaseConfig.anonKey, 'sb_publishable_RUdq4T4DCvSNwPHx5cEaNQ_ppYiVTol');
    });

    test('Local configuration presets are preserved for explicit selection', () {
      expect(SupabaseConfig.localProjectUrl, 'http://127.0.0.1:54321');
      expect(SupabaseConfig.localAnonKey.isNotEmpty, isTrue);
      expect(SupabaseConfig.useLocalSupabase, isFalse);
    });
  });
}

