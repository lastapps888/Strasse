import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iOS native bridge templates', () {
    test('the copied AppDelegate keeps MusicKit restore and local audio metadata', () async {
      final source = await File('platform_assets/native/AppDelegate.swift').readAsString();

      expect(source, contains('case "status":'));
      expect(source, contains('case "metadataForFile":'));
      expect(source, contains('case "set":'));
    });

    test('the checked-in iOS bundle declares the MusicKit privacy purpose', () async {
      final infoPlist = await File('ios/Runner/Info.plist').readAsString();

      expect(infoPlist, contains('<key>NSAppleMusicUsageDescription</key>'));
    });

    test('the platform preparation script refuses an incomplete native template', () async {
      final script = await File('tool/patch_platforms.py').readAsString();

      expect(script, contains('required_handlers = (\'case "status":\', \'case "metadataForFile":\')'));
      expect(script, contains('Refus de l\'appliquer pour ne pas supprimer la restauration MusicKit'));
    });
  });
}
