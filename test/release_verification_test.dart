import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../tool/release_support.dart';

void main() {
  late Directory root;
  void git(List<String> args) {
    final result = Process.runSync('git', [
      '-c',
      'safe.directory=${root.path.replaceAll('\\', '/')}',
      '-C',
      root.path,
      ...args,
    ]);
    if (result.exitCode != 0) throw StateError(result.stderr.toString());
  }

  void put(String name, List<int> bytes) {
    final file = File('${root.path}/$name');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('true_time_release_');
    git(['init', '-q']);
    put(
      'pubspec.yaml',
      utf8.encode(
        'name: flutter_true_time\nversion: 0.1.0-dev.1\npublish_to: none\n',
      ),
    );
    put('lib/clock.dart', utf8.encode('const time = 1;\n'));
    put('example/web/icon.png', [137, 80, 78, 71, 0, 1]);
    put(
      'example/android/.gitignore',
      utf8.encode('gradlew\ngradle-wrapper.jar\n'),
    );
    git(['add', '.']);
  });
  tearDown(() {
    final resolved = root.resolveSymbolicLinksSync();
    final temp = Directory.systemTemp.resolveSymbolicLinksSync();
    if (Directory(resolved).parent.path != temp ||
        !resolved
            .split(Platform.pathSeparator)
            .last
            .startsWith('true_time_release_')) {
      throw StateError('Unexpected test cleanup target');
    }
    root.deleteSync(recursive: true);
  });
  Map<String, dynamic> snapshot() => readInputs(root, gitInputs(root));
  Map<String, dynamic> readyManifest() {
    final inputs = snapshot(), digest = sourceDigest(inputs);
    final evidence = utf8.encode(
      'All required checks reviewed for this fixture.',
    );
    put('docs/evidence/check.txt', evidence);
    return {
      'schema': 2,
      'developmentInputs': false,
      'sourceDigest': digest,
      'inputs': inputs,
      'gates': {
        for (final g in requiredGates)
          g: {
            'status': 'passed',
            'sourceDigest': digest,
            'evidence': 'docs/evidence/check.txt',
            'sha256': bytesHash(evidence),
          },
      },
    };
  }

  test('tracked LF/CRLF checkouts produce identical digests', () {
    final before = sourceDigest(snapshot());
    put('lib/clock.dart', utf8.encode('const time = 1;\r\n'));
    expect(sourceDigest(snapshot()), before);
  });
  test('ignored wrappers and generated registrants do not affect inputs', () {
    final before = sourceDigest(snapshot());
    put('example/android/gradlew', utf8.encode('generated wrapper'));
    put('example/android/gradle-wrapper.jar', [0, 1, 2]);
    put(
      'example/android/GeneratedPluginRegistrant.java',
      utf8.encode('generated'),
    );
    git(['add', '-f', 'example/android/GeneratedPluginRegistrant.java']);
    expect(sourceDigest(snapshot()), before);
  });
  test('binary and real text changes invalidate fingerprints', () {
    final before = sourceDigest(snapshot());
    put('example/web/icon.png', [137, 80, 78, 71, 0, 2]);
    expect(sourceDigest(snapshot()), isNot(before));
    put('example/web/icon.png', [137, 80, 78, 71, 0, 1]);
    put('lib/clock.dart', utf8.encode('const time = 2;\n'));
    expect(sourceDigest(snapshot()), isNot(before));
  });
  test('checker is read-only and accepts matching reviewed evidence', () {
    final manifest = readyManifest();
    final before = sourceDigest(snapshot());
    expect(checkRelease(root, manifest), isEmpty);
    expect(sourceDigest(snapshot()), before);
  });
  test(
    'untracked runtime files cannot silently bypass release verification',
    () {
      final manifest = readyManifest();
      put('lib/new_clock.dart', utf8.encode('new source'));
      expect(
        checkRelease(root, manifest).join(' '),
        contains('Untracked release inputs'),
      );
    },
  );
  test('development snapshots remain blocked even with passed evidence', () {
    expect(
      checkRelease(root, readyManifest(), developmentInputs: true).join(' '),
      contains('not release eligible'),
    );
  });
  test('stale source and corrupted evidence fail closed', () {
    final manifest = readyManifest();
    (manifest['gates'] as Map)['minimum_sdk']['sourceDigest'] = 'old';
    expect(
      checkRelease(root, manifest).join(' '),
      contains('Stale source evidence'),
    );
    put('docs/evidence/check.txt', utf8.encode('altered evidence'));
    expect(
      checkRelease(root, manifest).join(' '),
      contains('Evidence hash mismatch'),
    );
  });
  test(
    'development guard removal preserves runtime digest but requires candidate mode',
    () {
      final manifest = readyManifest();
      final before = sourceDigest(snapshot());
      put(
        'pubspec.yaml',
        utf8.encode('name: flutter_true_time\nversion: 0.1.0-dev.1\n'),
      );
      expect(sourceDigest(snapshot()), before);
      expect(
        checkRelease(root, manifest).join(' '),
        contains('publication guard'),
      );
      expect(checkRelease(root, manifest, candidate: true), isEmpty);
    },
  );
}
