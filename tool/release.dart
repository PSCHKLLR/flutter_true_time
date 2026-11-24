import 'dart:convert';
import 'dart:io';

import 'release_support.dart';
import 'update_release_manifest.dart';

const releaseUsage =
    '''Usage: dart run tool/release.dart <patch|minor|major|current> [options]

Default: preview the release without changing files or Git refs.
  --notes <text>  Add a changelog bullet (or use existing Unreleased notes).
  --write         Update versions, changelog, and qualification manifest locally.
  --publish       Commit a bump, push main, then create and push an annotated
                  tag to origin, starting the publishing workflow.

Use current --publish to tag an already-committed version without bumping.
Writes require a clean checkout. Publishing also requires main at origin/main.
--publish is explicit authorization to publish through GitHub Actions.''';

class ReleasePlan {
  ReleasePlan._(
    this.previousVersion,
    this.version,
    Map<String, String> files,
    Map<String, String> originals,
  ) : files = Map.unmodifiable(files),
      originals = Map.unmodifiable(originals);

  final String previousVersion;
  final String version;
  final Map<String, String> files;
  final Map<String, String> originals;
  String get tag => 'v$version';
}

String _notes(String changelog, String heading) {
  final sections = RegExp(
    r'^## ([^\r\n]+)\r?$',
    multiLine: true,
  ).allMatches(changelog).toList();
  final matches = sections.where((m) => m[1] == heading).toList();
  if (matches.length != 1) {
    throw StateError('Require one changelog heading: ## $heading');
  }
  final index = sections.indexOf(matches.single);
  return changelog
      .substring(
        matches.single.end,
        index + 1 < sections.length ? sections[index + 1].start : null,
      )
      .trim();
}

ReleasePlan planRelease(Directory root, String bump, {String? notes}) {
  if (!['patch', 'minor', 'major', 'current'].contains(bump)) {
    throw ArgumentError('Expected patch, minor, major, or current');
  }
  final pubspec = File('${root.path}/pubspec.yaml').readAsStringSync();
  final previous = readReleaseVersion(pubspec);
  final example = File('${root.path}/example/pubspec.yaml').readAsStringSync();
  final exampleVersions = RegExp(
    r'^version:([^\r\n]*)',
    multiLine: true,
  ).allMatches(example).toList();
  if (exampleVersions.length != 1 ||
      exampleVersions.single[1] != ' $previous') {
    throw StateError('Package and example versions must match before release');
  }
  final changelog = File('${root.path}/CHANGELOG.md').readAsStringSync();
  final originals = {
    'pubspec.yaml': pubspec,
    'example/pubspec.yaml': example,
    'CHANGELOG.md': changelog,
  };
  if (bump == 'current') {
    if (notes != null) throw ArgumentError('current does not accept --notes');
    if (_notes(changelog, previous).isEmpty) {
      throw StateError('Release notes must not be empty');
    }
    return ReleasePlan._(previous, previous, const {}, originals);
  }
  final stable = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(previous);
  if (stable == null) {
    throw StateError(
      'Automatic bumps require a stable version; use current '
      'for a manually prepared prerelease',
    );
  }
  final parts = [for (var i = 1; i <= 3; i++) int.parse(stable[i]!)];
  final index = ['major', 'minor', 'patch'].indexOf(bump);
  parts[index]++;
  for (var i = index + 1; i < parts.length; i++) {
    parts[i] = 0;
  }
  final version = parts.join('.');
  final normalized = changelog.replaceAll('\r\n', '\n');
  final headings = RegExp(
    r'^## (.+)$',
    multiLine: true,
  ).allMatches(normalized).toList();
  if (headings.any((m) => m[1] == version)) {
    throw StateError('Changelog already contains $version');
  }
  final unreleased = headings.where((m) => m[1] == 'Unreleased').toList();
  if (unreleased.length > 1 ||
      (unreleased.isNotEmpty && unreleased.single != headings.first)) {
    throw StateError('Require at most one Unreleased section, before releases');
  }
  final existing = unreleased.isEmpty ? '' : _notes(normalized, 'Unreleased');
  final supplied = notes?.trim() ?? '';
  if (notes != null && supplied.isEmpty) {
    throw ArgumentError('--notes must not be empty');
  }
  if (RegExp(r'^## ', multiLine: true).hasMatch(supplied)) {
    throw ArgumentError('--notes must not contain release headings');
  }
  final body = [
    if (existing.isNotEmpty) existing,
    if (supplied.isNotEmpty)
      supplied.startsWith('- ') ? supplied : '- $supplied',
  ].join('\n');
  if (body.isEmpty) {
    throw StateError('Add Unreleased changelog notes or supply --notes');
  }
  final start = unreleased.isNotEmpty
      ? unreleased.single.start
      : headings.isNotEmpty
      ? headings.first.start
      : normalized.length;
  final end = unreleased.isNotEmpty && headings.length > 1
      ? headings[1].start
      : unreleased.isNotEmpty
      ? normalized.length
      : start;
  final prefix = normalized.substring(0, start).trimRight();
  final updatedChangelog =
      '$prefix\n\n## $version\n\n$body\n\n'
      '${normalized.substring(end)}';
  String replaceVersion(String text) => text.replaceFirst(
    RegExp(r'^version: [^\r\n]+', multiLine: true),
    'version: $version',
  );
  return ReleasePlan._(previous, version, {
    'pubspec.yaml': replaceVersion(pubspec),
    'example/pubspec.yaml': replaceVersion(example),
    'CHANGELOG.md': updatedChangelog,
  }, originals);
}

String _git(Directory root, List<String> args) {
  final result = Process.runSync('git', ['-C', root.path, ...args]);
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed:\n${result.stderr}');
  }
  return (result.stdout as String).trim();
}

/// Applies an explicit release plan. Never uploads directly or changes a tag.
void executeRelease(Directory root, ReleasePlan plan, {bool publish = false}) {
  final top = _git(root, ['rev-parse', '--show-toplevel']);
  if (Directory(top).resolveSymbolicLinksSync() !=
      root.resolveSymbolicLinksSync()) {
    throw StateError('Run the release command from the repository root');
  }
  if (_git(root, [
    'status',
    '--porcelain',
    '--untracked-files=all',
  ]).isNotEmpty) {
    throw StateError('Require a clean checkout, including untracked files');
  }
  for (final entry in plan.originals.entries) {
    if (File('${root.path}/${entry.key}').readAsStringSync() != entry.value) {
      throw StateError('Package changed after release planning');
    }
  }
  if (publish) {
    final pubspec = File('${root.path}/pubspec.yaml').readAsStringSync();
    if (RegExp(r'^publish_to:', multiLine: true).hasMatch(pubspec)) {
      throw StateError('Publication requires pubspec to omit publish_to');
    }
    if (plan.files.isEmpty) {
      final manifest =
          jsonDecode(
                File('${root.path}/docs/release_gates.json').readAsStringSync(),
              )
              as Map;
      if (manifest['version'] != plan.version ||
          manifest['developmentInputs'] != false ||
          manifest['sourceDigest'] !=
              sourceDigest(readInputs(root, gitInputs(root)))) {
        throw StateError('Regenerate and commit the current release manifest');
      }
    }
    if (_git(root, ['branch', '--show-current']) != 'main') {
      throw StateError('Publish from main after merging reviewed changes');
    }
    _git(root, ['fetch', 'origin', 'main', '--tags']);
    if (_git(root, ['rev-parse', 'HEAD']) !=
        _git(root, ['rev-parse', 'refs/remotes/origin/main'])) {
      throw StateError('Require main to match origin/main before publishing');
    }
    if (_git(root, ['tag', '--list', plan.tag]).isNotEmpty) {
      throw StateError('${plan.tag} already exists; never move release tags');
    }
  }
  if (plan.files.isNotEmpty) {
    final originals = {
      for (final path in [...plan.files.keys, 'docs/release_gates.json'])
        path: File('${root.path}/$path').readAsBytesSync(),
    };
    try {
      for (final entry in plan.files.entries) {
        File('${root.path}/${entry.key}').writeAsStringSync(entry.value);
      }
      updateReleaseManifest(root);
    } catch (_) {
      for (final entry in originals.entries) {
        File('${root.path}/${entry.key}').writeAsBytesSync(entry.value);
      }
      rethrow;
    }
    if (publish) {
      final paths = [...plan.files.keys, 'docs/release_gates.json'];
      _git(root, ['add', '--', ...paths]);
      _git(root, [
        'commit',
        '-m',
        'chore: release ${plan.version}',
        '--',
        ...paths,
      ]);
    }
  }
  if (publish) {
    try {
      _git(root, ['push', 'origin', 'HEAD:refs/heads/main']);
    } on StateError catch (error) {
      throw StateError(
        '$error\nLocal release commit retained. '
        'The release tag was not created or pushed.',
      );
    }
    _git(root, ['tag', '-a', plan.tag, '-m', 'Release ${plan.version}']);
    try {
      _git(root, ['push', 'origin', 'refs/tags/${plan.tag}']);
    } on StateError catch (error) {
      throw StateError(
        '$error\nMain was pushed; local tag retained for review. '
        'No forced push or tag replacement was attempted.',
      );
    }
  }
}

void main(List<String> args) {
  if (args.isEmpty || args.contains('--help')) {
    stdout.writeln(releaseUsage);
    return;
  }
  try {
    String? notes;
    var write = false, publish = false;
    for (var i = 1; i < args.length; i++) {
      switch (args[i]) {
        case '--notes':
          if (notes != null || ++i >= args.length) {
            throw ArgumentError('Supply --notes once with a text argument');
          }
          notes = args[i];
        case '--write':
          write = true;
        case '--publish':
          publish = true;
        default:
          throw ArgumentError('Unknown option: ${args[i]}');
      }
    }
    if (write && publish) {
      throw ArgumentError('Choose --write or --publish');
    }
    if (args.first == 'current' && write) {
      throw ArgumentError('current supports preview or --publish');
    }
    final root = Directory.current;
    final plan = planRelease(root, args.first, notes: notes);
    stdout.writeln('${plan.previousVersion} -> ${plan.version} (${plan.tag})');
    if (!write && !publish) {
      stdout.writeln(
        plan.files.isEmpty
            ? 'Preview only. Would tag the existing commit without a bump.'
            : 'Preview only. Would update: '
                  '${[...plan.files.keys, 'docs/release_gates.json'].join(', ')}',
      );
      stdout.writeln(
        plan.files.isEmpty
            ? 'Use --publish to tag and push from a clean main checkout.'
            : 'Use --write to prepare files, or --publish to commit, '
                  'tag, and push from a clean main checkout.',
      );
      return;
    }
    executeRelease(root, plan, publish: publish);
    stdout.writeln(
      publish
          ? 'Pushed ${plan.tag}; follow the Publish package and GitHub Release workflow.'
          : 'Prepared ${plan.version}; review and commit the four release files.',
    );
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
