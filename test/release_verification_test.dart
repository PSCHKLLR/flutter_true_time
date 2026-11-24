import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../tool/release_support.dart';
import '../tool/update_release_manifest.dart' as manifest_tool;

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
      'version': readReleaseVersion(
        File('${root.path}/pubspec.yaml').readAsStringSync(),
      ),
      'developmentInputs': false,
      'sourceDigest': digest,
      'inputs': inputs,
      'gates': <String, dynamic>{
        for (final g in requiredGates)
          g: <String, dynamic>{
            'status': 'passed',
            'sourceDigest': digest,
            'evidence': 'docs/evidence/check.txt',
            'sha256': bytesHash(evidence),
          },
      },
    };
  }

  test('only physical lifecycle can be waived for the first prerelease', () {
    final manifest = readyManifest()..['version'] = '0.1.0-dev.1';
    final gates = manifest['gates'] as Map;
    gates['physical_lifecycle'] = {'status': 'waived'};
    expect(checkRelease(root, manifest), isEmpty);
    gates['persistence_native'] = {'status': 'waived'};
    expect(checkRelease(root, manifest), ['Pending gate: persistence_native']);
    manifest['version'] = '0.1.0';
    expect(checkRelease(root, manifest), [
      'Manifest package version does not match pubspec; regenerate manifest',
      'Pending gate: physical_lifecycle',
      'Pending gate: persistence_native',
    ]);
    put(
      'pubspec.yaml',
      utf8.encode(
        'name: flutter_true_time\nversion: 2.0.4\npublish_to: none\n',
      ),
    );
    final stable = readyManifest();
    (stable['gates'] as Map)['physical_lifecycle'] = {'status': 'waived'};
    expect(checkRelease(root, stable), ['Pending gate: physical_lifecycle']);
    stable['version'] = '0.1.0-dev.1';
    expect(checkRelease(root, stable), [
      'Manifest package version does not match pubspec; regenerate manifest',
      'Pending gate: physical_lifecycle',
    ]);
  });

  test('release scripts are included in source fingerprints', () {
    final before = sourceDigest(snapshot());
    put('.github/scripts/release.py', utf8.encode('print("release")\n'));
    git(['add', '.github/scripts/release.py']);
    final first = sourceDigest(snapshot());
    expect(first, isNot(before));
    put('.github/scripts/release.py', utf8.encode('print("changed")\n'));
    expect(sourceDigest(snapshot()), isNot(first));
  });

  test('current stable versions are not rejected as an unexpected package', () {
    put(
      'pubspec.yaml',
      utf8.encode(
        'name: flutter_true_time\nversion: 2.0.4\npublish_to: none\n',
      ),
    );
    final manifest = readyManifest()..['version'] = '2.0.4';
    expect(checkRelease(root, manifest), isEmpty);
  });

  test('manifest version must match the actual package version', () {
    final manifest = readyManifest()..['version'] = '9.9.9';
    expect(
      checkRelease(root, manifest).join(' '),
      contains('Manifest package version'),
    );
  });

  test('canonical package metadata accepts stable and prerelease versions', () {
    for (final version in ['2.0.4', '2.1.0-dev.1', '3.0.0-rc.2+build.4']) {
      expect(
        readReleaseVersion('name: flutter_true_time\r\nversion: $version\r\n'),
        version,
      );
    }
  });

  test('canonical metadata rejects malformed or ambiguous identity', () {
    for (final version in ['02.0.4', '2.0', '2.0.4-dev.01', '2.0.4-']) {
      expect(
        () =>
            readReleaseVersion('name: flutter_true_time\nversion: $version\n'),
        throwsFormatException,
      );
    }
    for (final pubspec in [
      'name: other\nversion: 2.0.4\n',
      'name: flutter_true_time\nversion: 2.0.4\nversion: 2.0.5\n',
      'name: flutter_true_time\nversion: 2.0.4\nversion:\t2.0.5\n',
      'name: flutter_true_time\nname: other\nversion: 2.0.4\n',
      'name: flutter_true_time\n',
    ]) {
      expect(() => readReleaseVersion(pubspec), throwsFormatException);
    }
  });

  test('current versions still require current qualification evidence', () {
    for (final version in ['2.0.4', '2.1.0-dev.1']) {
      put(
        'pubspec.yaml',
        utf8.encode(
          'name: flutter_true_time\nversion: $version\npublish_to: none\n',
        ),
      );
      final manifest = readyManifest();
      (manifest['gates'] as Map)['minimum_sdk']['status'] = 'pending';
      expect(checkRelease(root, manifest), ['Pending gate: minimum_sdk']);
      (manifest['gates'] as Map)['minimum_sdk']['status'] = 'passed';
      (manifest['gates'] as Map)['minimum_sdk']['sourceDigest'] = 'old';
      expect(checkRelease(root, manifest), [
        'Stale source evidence: minimum_sdk',
      ]);
    }
  });

  test('candidate headers are bound to the expected package and version', () {
    const tree =
        "'-- pubspec.yaml (<1 KB)\n\nTotal compressed archive size: 1 KB.";
    for (final version in ['2.0.4', '2.1.0-dev.1', '3.0.0-rc.2+build.4']) {
      for (final registry in ['', ' to https://pub.dev']) {
        final header = 'Publishing flutter_true_time $version$registry:';
        expect(
          parseCandidateFiles('$header\n$tree', expectedVersion: version),
          ['pubspec.yaml'],
        );
        expect(
          () => parseCandidateFiles(
            '$header\n$tree',
            expectedVersion: '0.1.0-dev.1',
          ),
          throwsFormatException,
        );
      }
    }
    for (final header in [
      'Publishing other 2.0.4:',
      'Publishing flutter_true_time 2x0x4:',
      'Publishing flutter_true_time 2.0.4 to https://other.example:',
      'Publishing flutter_true_time 2.0.3:\nPublishing flutter_true_time 2.0.4:',
    ]) {
      expect(
        () => parseCandidateFiles('$header\n$tree', expectedVersion: '2.0.4'),
        throwsFormatException,
      );
    }
  });

  for (final version in ['2.0.4', '2.1.0-dev.1']) {
    test('manifest writer records $version without a legacy waiver', () {
      put(
        'pubspec.yaml',
        utf8.encode(
          'name: flutter_true_time\nversion: $version\npublish_to: none\n',
        ),
      );
      final manifest = readyManifest()..['version'] = '0.1.0-dev.1';
      (manifest['gates'] as Map)['physical_lifecycle'] = {
        'status': 'waived',
        'historicalEvidence': {'note': 'Waiver for the first prerelease only'},
      };
      put('docs/release_gates.json', utf8.encode(jsonEncode(manifest)));
      manifest_tool.updateReleaseManifest(root);
      final updated =
          jsonDecode(
                File('${root.path}/docs/release_gates.json').readAsStringSync(),
              )
              as Map;
      expect(updated['version'], version);
      final physical = (updated['gates'] as Map)['physical_lifecycle'] as Map;
      expect(physical['status'], 'pending');
      expect(physical['historicalEvidence'], {
        'note': 'Waiver for the first prerelease only',
      });
    });
  }

  test('manifest writer preserves the original prerelease waiver only', () {
    final manifest = readyManifest();
    (manifest['gates'] as Map)['physical_lifecycle'] = {'status': 'waived'};
    put('docs/release_gates.json', utf8.encode(jsonEncode(manifest)));
    put('lib/clock.dart', utf8.encode('const time = 2;\n'));
    final result = manifest_tool.updateReleaseManifest(root);
    expect(result.changed, isTrue);
    final updated =
        jsonDecode(
              File('${root.path}/docs/release_gates.json').readAsStringSync(),
            )
            as Map;
    expect(updated['version'], '0.1.0-dev.1');
    final gates = updated['gates'] as Map;
    expect((gates['physical_lifecycle'] as Map)['status'], 'waived');
    expect((gates['minimum_sdk'] as Map)['status'], 'pending');
    expect((gates['minimum_sdk'] as Map)['historicalEvidence'], isNotNull);
  });

  test(
    'manifest writer rejects invalid versions without changing evidence',
    () {
      final original = jsonEncode(readyManifest());
      put('docs/release_gates.json', utf8.encode(original));
      put(
        'pubspec.yaml',
        utf8.encode('name: flutter_true_time\nversion: 2.0\n'),
      );
      expect(
        () => manifest_tool.updateReleaseManifest(root),
        throwsFormatException,
      );
      expect(
        File('${root.path}/docs/release_gates.json').readAsStringSync(),
        original,
      );
    },
  );

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
      expect(
        checkRelease(root, manifest, candidate: true, technicalOnly: true),
        isEmpty,
      );
    },
  );

  test('parses ASCII and Unicode pub trees and rejects incomplete trees', () {
    const header =
        'Publishing flutter_true_time 0.1.0-dev.1 to https://pub.dev:';
    const footer = 'Total compressed archive size: 3 KB.';
    const ascii = "|-- lib\n|   '-- a.dart (<1 KB)\n'-- pubspec.yaml (<1 KB)";
    const unicode = '├── lib\n│   └── a.dart (<1 KB)\n└── pubspec.yaml (<1 KB)';
    for (final tree in [ascii, unicode]) {
      expect(
        parseCandidateFiles(
          '$header\n$tree\n\n$footer',
          expectedVersion: '0.1.0-dev.1',
        ),
        ['lib/a.dart', 'pubspec.yaml'],
      );
      expect(
        () => parseCandidateFiles(
          '$header\n$tree',
          expectedVersion: '0.1.0-dev.1',
        ),
        throwsFormatException,
      );
    }
    expect(
      () => parseCandidateFiles(
        '$header\n|-- lib\n$footer',
        expectedVersion: '0.1.0-dev.1',
      ),
      throwsFormatException,
    );
  });

  test(
    'candidate check requires a fresh exact selection and both approvals',
    () {
      final manifest = readyManifest();
      put(
        'pubspec.yaml',
        utf8.encode('name: flutter_true_time\nversion: 0.1.0-dev.1\n'),
      );
      final selected = {...requiredCandidateFiles};
      for (final path in selected.difference({'pubspec.yaml'})) {
        put(path, utf8.encode('$path\n'));
      }
      git(['add', '.']);
      final inputs = snapshot();
      final runtimeDigest = sourceDigest(inputs);
      manifest['sourceDigest'] = runtimeDigest;
      manifest['inputs'] = inputs;
      final gates = manifest['gates'] as Map;
      for (final record in gates.values) {
        record['sourceDigest'] = runtimeDigest;
      }
      final approved = sourceDigest(readCandidate(root, selected));
      void approve(String gate, String digest) {
        final evidence = utf8.encode(jsonEncode({'candidateDigest': digest}));
        final path = 'docs/evidence/$gate.json';
        put(path, evidence);
        gates[gate]['evidence'] = path;
        gates[gate]['sha256'] = bytesHash(evidence);
      }

      for (final gate in candidateGates) {
        approve(gate, approved);
      }
      List<String> check() => checkRelease(
        root,
        manifest,
        candidate: true,
        selectFiles: (_) => selected.toList(),
      );

      expect(check(), isEmpty);
      approve('owner_archive_approval', 'stale');
      expect(check(), ['Stale candidate evidence: owner_archive_approval']);
      approve('owner_archive_approval', approved);
      put('README.md', utf8.encode('README.md\r\n'));
      expect(sourceDigest(snapshot()), runtimeDigest);
      expect(check(), hasLength(2));
      put('README.md', utf8.encode('README.md\n'));
      put('extra.md', utf8.encode('new publishable file'));
      selected.add('extra.md');
      expect(check(), hasLength(2));
      selected.remove('extra.md');
      expect(check(), isEmpty);
      File('${root.path}/README.md').deleteSync();
      expect(check().first, contains('Candidate verification failed'));
      selected.remove('README.md');
      expect(check().first, contains('Incomplete candidate files'));
    },
  );
}
