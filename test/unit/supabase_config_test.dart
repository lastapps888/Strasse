import 'package:flutter_test/flutter_test.dart';
import 'package:strasse/core/config/app_config.dart';

void main() {
  test('la configuration publique Supabase par défaut est cohérente', () {
    expect(AppConfig.fromEnvironment.supabaseUrl, AppConfig.defaultSupabaseUrl);
    expect(AppConfig.fromEnvironment.supabaseAnonKey, AppConfig.defaultSupabasePublishableKey);
    expect(AppConfig.defaultSupabasePublishableKey, startsWith('sb_publishable_'));
  });
}
