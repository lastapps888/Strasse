import 'package:flutter_test/flutter_test.dart';
import 'package:strasse/core/config/app_config.dart';
import 'package:strasse/features/services/provider_catalog.dart';
import 'package:strasse/features/services/provider_models.dart';

void main() {
  test('la configuration publique Supabase par défaut est cohérente', () {
    expect(AppConfig.fromEnvironment.supabaseUrl, AppConfig.defaultSupabaseUrl);
    expect(AppConfig.fromEnvironment.supabaseAnonKey, AppConfig.defaultSupabasePublishableKey);
    expect(AppConfig.defaultSupabasePublishableKey, startsWith('sb_publishable_'));
  });

  test('Supabase reste le backend de compte recommandé par défaut', () {
    expect(ProviderCatalog.recommendedFor(ServiceCategory.account).id, 'account-supabase');
  });
}
