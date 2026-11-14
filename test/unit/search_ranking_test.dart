import 'package:flutter_test/flutter_test.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/geo_backend.dart';
import 'package:strasse/data/providers/search_ranking.dart';
import 'package:strasse/domain/domain.dart';

Place _p(String id, String name, double lat, double lon, [String? addr]) => Place(id: id, name: name, point: GeoPoint(lat, lon), address: addr);

void main() {
  group('TextMatch', () {
    test('ignore accents, casse et abréviations', () {
      expect(TextMatch.normalize('Bd St-Michel'), 'boulevard saint michel');
      expect(TextMatch.fold('Écully'), 'ecully');
    });
    test('tolère les fautes de frappe', () {
      expect(TextMatch.similarity('strasbourg', 'Strasbourg'), 1);
      expect(TextMatch.similarity('strasbuorg', 'Strasbourg'), greaterThan(0.75));
      expect(TextMatch.similarity('montpelier', 'Montpellier'), greaterThan(0.85));
      expect(TextMatch.similarity('paris', 'Marseille'), lessThan(0.4));
    });
    test('un préfixe compte comme une correspondance', () {
      expect(TextMatch.similarity('stras', 'Strasbourg'), greaterThan(0.9));
    });
    test('variantes : lettres doublées et mot tronqué', () {
      expect(TextMatch.variants('rue de la republique lyon'), isNotEmpty);
      expect(TextMatch.variants('anneccy'), contains('anecy'));
    });
  });

  group('SearchRanking', () {
    test('classe par ressemblance puis proximité, sans doublons', () {
      final res = SearchRanking.rank('lyon', [
        _p('a', 'Lyon', 45.76, 4.83),
        _p('b', 'Lyon', 45.76, 4.83),
        _p('c', 'Lyonnel', 10, 10),
        _p('d', 'Saint-Étienne', 45.43, 4.39),
      ], near: const GeoPoint(45.7, 4.8));
      expect(res.first.id, 'a');
      expect(res.where((p) => p.name == 'Lyon').length, 1);
    });
  });

  group('FailoverRunner', () {
    test('un 404 passe au fournisseur suivant quand retryClientErrors est actif', () async {
      final r = await FailoverRunner.run(['t1', 't2'], (i) async {
        if (i == 0) throw const Failure(FailureKind.client, 'x', code: 'unavailable');
        return 'ok';
      }, retryClientErrors: true);
      expect(r, 'ok');
    });
    test('sans l\'option, une erreur client est renvoyée', () async {
      expect(
        FailoverRunner.run(['u1', 'u2'], (i) async => throw const Failure(FailureKind.client, 'x')),
        throwsA(isA<Failure>()),
      );
    });
  });
}
