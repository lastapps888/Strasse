import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strasse/app/widgets/strasse_logo.dart';

void main() {
  testWidgets('le logo se dessine en clair et en sombre', (tester) async {
    for (final dark in [false, true]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: StrasseLogo(size: 120, dark: dark)))));
      expect(find.byType(StrasseLogo), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
