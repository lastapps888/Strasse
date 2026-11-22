import 'package:flutter_test/flutter_test.dart';
import 'package:strasse/features/updates/update_service.dart';

void main() {
  group('compareVersions (SemVer 2.0)', () {
    test('compare les composantes numériques sans ordre lexical', () {
      expect(compareVersions('1.10.0', '1.9.0'), greaterThan(0));
      expect(compareVersions('2.0.0', '1.99.99'), greaterThan(0));
    });

    test('une version stable est supérieure à sa préversion', () {
      expect(compareVersions('1.0.0', '1.0.0-beta.9'), greaterThan(0));
      expect(compareVersions('1.0.0-rc.1', '1.0.0'), lessThan(0));
    });

    test('les identifiants numériques de préversion sont comparés numériquement', () {
      expect(compareVersions('1.0.0-beta.10', '1.0.0-beta.2'), greaterThan(0));
      expect(compareVersions('1.0.0-beta.2', '1.0.0-beta.alpha'), lessThan(0));
    });

    test('les métadonnées de build ne changent pas la priorité', () {
      expect(compareVersions('1.2.3+build.4', '1.2.3+build.8'), 0);
    });
  });

  test('parseRelease conserve les préversions et l’intégrité de l’IPA', () {
    final release = UpdateService.parseRelease({
      'tag_name': 'v1.0.0-beta.6',
      'draft': false,
      'prerelease': true,
      'html_url': 'https://github.com/lastapps888/Strasse/releases/tag/v1.0.0-beta.6',
      'assets': [
        {
          'name': 'Strasse.ipa',
          'browser_download_url': 'https://example.invalid/Strasse.ipa',
          'size': 1234,
          'digest': 'sha256:' + 'a' * 64,
        },
      ],
    });
    expect(release, isNotNull);
    expect(release!.isPrerelease, isTrue);
    expect(release.version, '1.0.0-beta.6');
    expect(release.ipaSize, 1234);
    expect(release.ipaSha256, 'a' * 64);
  });
}
