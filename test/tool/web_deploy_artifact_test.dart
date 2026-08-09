import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the two Vercel configurations and, above all, that they stay apart.
///
/// They look alike and mean opposite things. `vercel.json` at the repository
/// root is a *policy* for the Git integration — it must never deploy the app
/// automatically (DEPLOY-DRIFT-01). `web/vercel.json` is *routing* for the
/// artifact that gets deployed; it lives under `web/` because `flutter build
/// web` copies that directory verbatim into `build/web`, which is the whole
/// reason no copy step is needed and nothing can be forgotten after a build.
///
/// Swapping their contents would either re-enable the drift or leave the
/// deployed app without a SPA fallback, and neither fails loudly on its own.
void main() {
  Map<String, Object?> readJson(String path) {
    final file = File(path);
    expect(
      file.existsSync(),
      isTrue,
      reason: '$path is missing; the deploy path depends on it.',
    );
    return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  }

  group('repository root vercel.json is the git policy only', () {
    test('keeps automatic git deployments disabled', () {
      final config = readJson('vercel.json');
      final git = config['git'] as Map<String, Object?>?;

      expect(
        git?['deploymentEnabled'],
        isFalse,
        reason:
            'Automatic Vercel git deployments must stay off. Re-enabling them '
            'reproduces the drift DEPLOY-DRIFT-01 removed: empty 404 '
            'deployments on every push and every Dependabot branch.',
      );
    });

    test('carries no build or routing configuration', () {
      final config = readJson('vercel.json');

      // The app is built in GitHub Actions with a pinned Flutter toolchain;
      // Vercel has no Flutter and must not try.
      for (final key in const <String>[
        'buildCommand',
        'outputDirectory',
        'framework',
        'installCommand',
        'rewrites',
      ]) {
        expect(
          config.containsKey(key),
          isFalse,
          reason:
              'The root config declares "$key". Routing belongs in '
              'web/vercel.json, and building belongs in CI.',
        );
      }
    });
  });

  group('web/vercel.json is the deployed artifact routing', () {
    test('rewrites every path to index.html', () {
      final config = readJson('web/vercel.json');
      final rewrites = config['rewrites'] as List<Object?>?;

      expect(
        rewrites,
        isNotNull,
        reason:
            'Without a SPA fallback a direct hit or reload on a path route '
            'like /properties returns 404 on any static host.',
      );
      final rewrite = rewrites!.single as Map<String, Object?>;
      expect(rewrite['source'], '/(.*)');
      expect(rewrite['destination'], '/index.html');
    });

    test('carries no git policy', () {
      final config = readJson('web/vercel.json');

      // This file ships inside the deployment. A git policy here would be
      // read from the wrong place and suggest the root file is unnecessary.
      expect(
        config.containsKey('git'),
        isFalse,
        reason:
            'The git deployment policy belongs to the repository root, not to '
            'the deployed artifact.',
      );
    });

    test('sits where the web build picks it up', () {
      // `flutter build web` copies web/ into build/web verbatim. That is what
      // makes the artifact configuration deterministic without a prepare step,
      // so the file has to stay in this directory.
      expect(File('web/index.html').existsSync(), isTrue);
      expect(File('web/vercel.json').existsSync(), isTrue);
    });
  });
}
