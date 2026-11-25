import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/release.dart';
import '../tool/update_release_manifest.dart';

void main() {
  late Directory sandbox, root, remote;
  String git(List<String> args, {Directory? at}) {
    final result = Process.runSync('git', ['-C', (at ?? root).path, ...args]);
    if (result.exitCode != 0) throw StateError('${result.stderr}');
    return (result.stdout as String).trim();
  }

  void put(String path, String contents) {
    final file = File('${root.path}/$path');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  String read(String path) => File('${root.path}/$path').readAsStringSync();

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('true_time_command_');
    root = Directory('${sandbox.path}/repo')..createSync();
    remote = Directory('${sandbox.path}/origin.git')..createSync();
    git(['init', '--bare', '-q'], at: remote);
    git(['init', '--initial-branch=main', '-q']);
    git(['config', 'user.name', 'Release test']);
    git(['config', 'user.email', 'release@example.invalid']);
    put('pubspec.yaml', 'name: flutter_true_time\nversion: 2.0.5\n');
    put(
      'example/pubspec.yaml',
      'name: flutter_true_time_example\nversion: 2.0.5\npublish_to: none\n',
    );
    put(
      'CHANGELOG.md',
      '# Changes\n\n## Unreleased\n\n- Fix a bug.\n\n'
          '## 2.0.5\n\n- Previous release.\n',
    );
    put('lib/core.dart', 'const value = 1;\n');
    put(
      'docs/release_gates.json',
      jsonEncode({
        'version': '2.0.5',
        'sourceDigest': 'old',
        'gates': {
          'physical_lifecycle': {'status': 'waived'},
        },
      }),
    );
    git(['add', '.']);
    updateReleaseManifest(root);
    git(['add', '.']);
    git(['commit', '-qm', 'Initial fixture']);
    git(['remote', 'add', 'origin', remote.path]);
    git(['push', '-qu', 'origin', 'main']);
  });

  tearDown(() {
    final resolved = sandbox.resolveSymbolicLinksSync();
    if (Directory(resolved).parent.path !=
            Directory.systemTemp.resolveSymbolicLinksSync() ||
        !Directory(resolved).uri.pathSegments
            .where((part) => part.isNotEmpty)
            .last
            .startsWith('true_time_command_')) {
      throw StateError('Unexpected test cleanup target');
    }
    sandbox.deleteSync(recursive: true);
  });

  test('preview bumps all versions and preserves previous release notes', () {
    for (final entry in {
      'patch': '2.0.6',
      'minor': '2.1.0',
      'major': '3.0.0',
    }.entries) {
      final plan = planRelease(root, entry.key, notes: 'Add automation.');
      expect(plan.version, entry.value);
      expect(plan.files['pubspec.yaml'], contains('version: ${entry.value}\n'));
      expect(
        plan.files['example/pubspec.yaml'],
        contains('version: ${entry.value}\n'),
      );
      expect(
        plan.files['CHANGELOG.md'],
        contains('## ${entry.value}\n\n- Fix a bug.\n- Add automation.'),
      );
      expect(
        plan.files['CHANGELOG.md'],
        contains('## 2.0.5\n\n- Previous release.'),
      );
      expect(plan.files['CHANGELOG.md'], isNot(contains('## Unreleased')));
    }
    expect(git(['status', '--porcelain']), isEmpty);
    expect(git(['tag', '--list']), isEmpty);
  });

  test('requires notes, rejects duplicate sections and version mismatch', () {
    put('CHANGELOG.md', '# Changes\n\n## 2.0.5\n\n- Old.\n');
    expect(() => planRelease(root, 'patch'), throwsStateError);
    final plan = planRelease(root, 'patch', notes: 'New change.');
    expect(plan.files['CHANGELOG.md'], contains('## 2.0.6\n\n- New change.'));
    put(
      'CHANGELOG.md',
      '${read('CHANGELOG.md')}\n## 2.0.6\n\n- Already exists.\n',
    );
    expect(
      () => planRelease(root, 'patch', notes: 'Change.'),
      throwsStateError,
    );
    put('example/pubspec.yaml', 'version: 2.0.4\n');
    expect(() => planRelease(root, 'patch'), throwsStateError);
  });

  test('write invalidates qualification and leaves Git refs untouched', () {
    final head = git(['rev-parse', 'HEAD']);
    executeRelease(root, planRelease(root, 'patch'));
    final manifest = jsonDecode(read('docs/release_gates.json')) as Map;
    expect(manifest['version'], '2.0.6');
    expect(
      (manifest['gates'] as Map)['physical_lifecycle']['status'],
      'pending',
    );
    expect(git(['rev-parse', 'HEAD']), head);
    expect(git(['tag', '--list']), isEmpty);
    expect(git(['diff', '--cached', '--name-only']), isEmpty);
  });

  test('CLI guidance prepares a PR before publishing from updated main', () {
    final script = File('tool/release.dart').absolute.path;
    final packages = File('.dart_tool/package_config.json').absolute.path;
    for (final args in [
      ['--help'],
      ['patch'],
      ['patch', '--write'],
    ]) {
      final result = Process.runSync(Platform.resolvedExecutable, [
        '--packages=$packages',
        script,
        ...args,
      ], workingDirectory: root.path);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains('release branch'));
      expect(result.stdout, contains('PR'));
      expect(result.stdout, contains('current --publish'));
    }
    expect(git(['tag', '--list']), isEmpty);
    expect(git(['tag', '--list'], at: remote), isEmpty);
    expect(read('pubspec.yaml'), contains('version: 2.0.6\n'));
  });

  test(
    'branch preparation publishes only after its version commit is merged',
    () {
      git(['switch', '-c', 'codex/release-next']);
      executeRelease(root, planRelease(root, 'patch'));
      git([
        'add',
        'pubspec.yaml',
        'example/pubspec.yaml',
        'CHANGELOG.md',
        'docs/release_gates.json',
      ]);
      git(['commit', '-qm', 'Prepare reviewed release']);
      git(['push', '-qu', 'origin', 'codex/release-next']);
      final reviewed = git(['rev-parse', 'HEAD']);
      expect(
        () => executeRelease(root, planRelease(root, 'current'), publish: true),
        throwsStateError,
      );
      expect(git(['tag', '--list']), isEmpty);
      expect(git(['tag', '--list'], at: remote), isEmpty);

      // Simulate the reviewed PR merge in the isolated fixture remote.
      git(['update-ref', 'refs/heads/main', reviewed], at: remote);
      git(['switch', 'main']);
      git(['pull', '--ff-only', 'origin', 'main']);
      executeRelease(root, planRelease(root, 'current'), publish: true);
      expect(git(['rev-parse', 'HEAD']), reviewed);
      expect(git(['rev-parse', 'refs/tags/v2.0.6^{}'], at: remote), reviewed);
      expect(git(['status', '--porcelain']), isEmpty);
    },
  );

  test('refuses dirty files, staged files, and untracked files', () {
    for (final kind in ['unstaged', 'staged', 'untracked']) {
      final plan = planRelease(root, 'patch');
      final file = kind == 'untracked' ? 'scratch.txt' : 'lib/core.dart';
      put(file, 'Unrelated work.\n');
      if (kind == 'staged') git(['add', file]);
      expect(() => executeRelease(root, plan), throwsStateError);
      expect(read('pubspec.yaml'), contains('version: 2.0.5\n'));
      if (kind == 'untracked') {
        File('${root.path}/$file').deleteSync();
      } else {
        git(['restore', '--staged', '--worktree', file]);
      }
    }
  });

  test('failed manifest generation restores every original file', () {
    put('docs/release_gates.json', 'invalid JSON');
    git(['add', '.']);
    git(['commit', '-qm', 'Malformed manifest fixture']);
    final before = read('CHANGELOG.md');
    expect(
      () => executeRelease(root, planRelease(root, 'patch')),
      throwsFormatException,
    );
    expect(read('pubspec.yaml'), contains('version: 2.0.5\n'));
    expect(read('CHANGELOG.md'), before);
    expect(read('docs/release_gates.json'), 'invalid JSON');
    expect(git(['status', '--porcelain']), isEmpty);
  });

  test('legacy direct-push mode commits main before its annotated tag', () {
    executeRelease(root, planRelease(root, 'patch'), publish: true);
    final head = git(['rev-parse', 'HEAD']);
    expect(git(['rev-parse', 'refs/heads/main'], at: remote), head);
    expect(git(['rev-parse', 'refs/tags/v2.0.6^{}'], at: remote), head);
    expect(git(['cat-file', '-t', 'refs/tags/v2.0.6'], at: remote), 'tag');
    expect(git(['status', '--porcelain']), isEmpty);
    expect(
      git(['show', '--pretty=', '--name-only', 'HEAD']).split('\n')..sort(),
      [
        'CHANGELOG.md',
        'docs/release_gates.json',
        'example/pubspec.yaml',
        'pubspec.yaml',
      ],
    );
  });

  test('current publishes an existing commit without a second bump', () {
    final head = git(['rev-parse', 'HEAD']);
    executeRelease(root, planRelease(root, 'current'), publish: true);
    expect(git(['rev-parse', 'HEAD']), head);
    expect(git(['rev-parse', 'refs/tags/v2.0.5^{}'], at: remote), head);
    expect(read('pubspec.yaml'), contains('version: 2.0.5\n'));
  });

  test('CRLF metadata and notes work for current and bump modes', () {
    for (final path in [
      'pubspec.yaml',
      'example/pubspec.yaml',
      'CHANGELOG.md',
    ]) {
      put(path, read(path).replaceAll('\n', '\r\n'));
    }
    expect(planRelease(root, 'current').version, '2.0.5');
    expect(
      planRelease(root, 'patch').files['CHANGELOG.md'],
      contains('## 2.0.6\n\n- Fix a bug.'),
    );
  });

  test('current refuses a stale committed qualification manifest', () {
    put('lib/core.dart', 'const value = 2;\n');
    git(['add', '.']);
    git(['commit', '-qm', 'Change source without regenerating manifest']);
    git(['push', '-q', 'origin', 'main']);
    expect(
      () => executeRelease(root, planRelease(root, 'current'), publish: true),
      throwsStateError,
    );
    expect(git(['tag', '--list']), isEmpty);
  });

  test('publication guard and stale plans fail before writes', () {
    final plan = planRelease(root, 'patch');
    put('pubspec.yaml', '${read('pubspec.yaml')}publish_to: none\n');
    git(['add', '.']);
    git(['commit', '-qm', 'Guard publication']);
    git(['push', '-q', 'origin', 'main']);
    expect(() => executeRelease(root, plan), throwsStateError);
    final guarded = planRelease(root, 'patch');
    expect(
      () => executeRelease(root, guarded, publish: true),
      throwsStateError,
    );
    expect(read('pubspec.yaml'), contains('version: 2.0.5\n'));
    expect(git(['tag', '--list']), isEmpty);
  });

  test('rejected main push never creates or pushes a release tag', () {
    final before = git(['rev-parse', 'refs/heads/main'], at: remote);
    git(['config', 'receive.hideRefs', 'refs/heads/main'], at: remote);
    StateError? rejection;
    try {
      executeRelease(root, planRelease(root, 'patch'), publish: true);
    } on StateError catch (error) {
      rejection = error;
    }
    expect(rejection, isNotNull);
    expect(
      git(['rev-parse', 'refs/heads/main'], at: remote),
      before,
      reason: rejection.toString(),
    );
    expect(git(['tag', '--list'], at: remote), isEmpty);
    expect(git(['tag', '--list']), isEmpty);
    expect(read('pubspec.yaml'), contains('version: 2.0.6\n'));
    expect(git(['status', '--porcelain']), isEmpty);
    expect(rejection.toString(), contains('git switch -c codex/release-2.0.6'));
    expect(
      rejection.toString(),
      contains('git push -u origin codex/release-2.0.6'),
    );
    expect(rejection.toString(), contains('Open a PR to main'));
    expect(rejection.toString(), contains('current --publish'));
    expect(rejection.toString(), contains('Do not bypass protection'));

    // Follow the recovery guidance while the remote still rejects main pushes.
    final retained = git(['rev-parse', 'HEAD']);
    git(['switch', '-c', 'codex/release-2.0.6']);
    git(['push', '-u', 'origin', 'codex/release-2.0.6']);
    expect(
      git(['rev-parse', 'refs/heads/codex/release-2.0.6'], at: remote),
      retained,
    );
    expect(git(['rev-parse', 'refs/heads/main'], at: remote), before);
    expect(git(['tag', '--list'], at: remote), isEmpty);
    expect(git(['tag', '--list']), isEmpty);
  });

  test('rejected tag push retains the published main commit for recovery', () {
    git(['config', 'receive.hideRefs', 'refs/tags/'], at: remote);
    expect(
      () => executeRelease(root, planRelease(root, 'patch'), publish: true),
      throwsStateError,
    );
    expect(
      git(['rev-parse', 'refs/heads/main'], at: remote),
      git(['rev-parse', 'HEAD']),
    );
    expect(git(['tag', '--list'], at: remote), isEmpty);
    expect(git(['tag', '--list']), 'v2.0.6');
    expect(git(['status', '--porcelain']), isEmpty);
  });

  test(
    'publish rejects existing tags, wrong branch, and remote divergence',
    () {
      final plan = planRelease(root, 'patch');
      git(['tag', 'v2.0.6']);
      expect(() => executeRelease(root, plan, publish: true), throwsStateError);
      git(['tag', '-d', 'v2.0.6']);
      git(['switch', '-c', 'feature']);
      expect(() => executeRelease(root, plan, publish: true), throwsStateError);
      git(['switch', 'main']);
      git(['commit', '--allow-empty', '-qm', 'Ahead of origin']);
      expect(() => executeRelease(root, plan, publish: true), throwsStateError);
      expect(read('pubspec.yaml'), contains('version: 2.0.5\n'));
      expect(git(['tag', '--list']), isEmpty);
    },
  );
}
