import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

const requiredGates = <String>[
  'minimum_sdk',
  'current_sdk',
  'android_baseline',
  'android_current',
  'android_builtin_kotlin',
  'apple_xcode',
  'windows_release',
  'linux_release',
  'web_js_wasm_browser',
  'physical_lifecycle',
  'persistence_native',
  'read_performance',
  'apple_privacy_archive',
  'provenance_dependencies',
  'owned_repository_security',
  'name_availability',
  'archive_consumer',
  'owner_archive_approval',
];
const candidateGates = {'archive_consumer', 'owner_archive_approval'};
const candidateDartVersion = '3.13.7';
const requiredCandidateFiles = {
  'pubspec.yaml',
  'README.md',
  'CHANGELOG.md',
  'LICENSE',
  'THIRD_PARTY_NOTICES.md',
  'lib/core.dart',
  'lib/flutter_true_time.dart',
  'android/src/main/AndroidManifest.xml',
  'android/src/main/java/dev/pschkllr/flutter_true_time/FlutterTrueTimePlugin.java',
  'example/lib/main.dart',
  'example/android/app/build.gradle.kts',
  'example/ios/Runner/Info.plist',
  'example/macos/Runner/Info.plist',
  'example/linux/runner/main.cc',
  'example/windows/runner/main.cpp',
  'example/web/index.html',
};

/// Parses the pinned pub CLI's ASCII or Unicode tree, including its end marker.
List<String> parseCandidateFiles(String output) {
  final lines = const LineSplitter().convert(output);
  final header = lines.indexWhere(
    (line) => RegExp(
      r'^Publishing flutter_true_time 0\.1\.0-dev\.1(?: to https://pub\.dev)?:$',
    ).hasMatch(line),
  );
  final footer = lines.indexWhere(
    (line) => line.startsWith('Total compressed archive size:'),
  );
  if (header < 0 || footer <= header + 1) {
    throw const FormatException('Incomplete pub dry-run file tree');
  }
  final files = <String>{}, seen = <String>{};
  final parents = <({String name, bool last, bool file})>[];
  final branch = RegExp(r"^((?: {4}|[│|] {3})*)(├── |└── |\|-- |'-- )(.+)$");
  final size = RegExp(r' \((?:<1|[0-9]+(?:\.[0-9]+)?) (?:B|KB|MB|GB)\)$');
  for (final line
      in lines.sublist(header + 1, footer).where((l) => l.isNotEmpty)) {
    final match = branch.firstMatch(line);
    if (match == null) throw FormatException('Invalid pub tree entry: $line');
    final prefix = match[1]!;
    final depth = prefix.length ~/ 4;
    if (depth > parents.length ||
        (depth < parents.length && parents[depth].last)) {
      throw FormatException('Invalid pub tree depth: $line');
    }
    parents.length = depth;
    for (var i = 0; i < depth; i++) {
      if (parents[i].file || parents[i].last != (prefix[i * 4] == ' ')) {
        throw FormatException('Invalid pub tree ancestry: $line');
      }
    }
    final entry = match[3]!;
    final isFile = size.hasMatch(entry);
    final name = entry.replaceFirst(size, '');
    if (name.trim() != name ||
        name.isEmpty ||
        name == '.' ||
        name == '..' ||
        RegExp(r'[/\\:\x00-\x1f]').hasMatch(name)) {
      throw FormatException('Invalid candidate path: $name');
    }
    final path = [...parents.map((parent) => parent.name), name].join('/');
    if (!seen.add(path)) {
      throw FormatException('Duplicate candidate path: $path');
    }
    if (isFile) files.add(path);
    final marker = match[2]!;
    parents.add((
      name: name,
      last: marker == '└── ' || marker == "'-- ",
      file: isFile,
    ));
  }
  if (parents.isEmpty || parents.any((entry) => !entry.last)) {
    throw const FormatException('Incomplete pub dry-run file tree');
  }
  return files.toList()..sort();
}

Map<String, String> readCandidate(Directory root, Iterable<String> files) {
  final names = files.toList()..sort();
  final required = {
    ...requiredCandidateFiles,
    ...gitInputs(root).where((name) => name.endsWith('.xcprivacy')),
  };
  if (names.toSet().length != names.length ||
      !names.toSet().containsAll(required)) {
    throw const FormatException(
      'Incomplete candidate files or duplicate paths',
    );
  }
  final result = <String, String>{};
  for (final name in names) {
    var current = root.path;
    for (final part in name.split('/')) {
      if (part.isEmpty ||
          part == '.' ||
          part == '..' ||
          RegExp(r'[\\:\x00-\x1f]').hasMatch(part)) {
        throw FormatException('Invalid candidate path: $name');
      }
      current = '$current/$part';
      if (FileSystemEntity.isLinkSync(current)) {
        throw FormatException('Symlink candidate input: $name');
      }
    }
    result[name] = bytesHash(File(current).readAsBytesSync());
  }
  return result;
}

List<String> selectCandidateFiles(Directory root) {
  if (Platform.version.split(' ').first != candidateDartVersion) {
    throw StateError('Use Dart $candidateDartVersion for candidate selection');
  }
  final pubspec = File('${root.path}/pubspec.yaml').readAsStringSync();
  if (RegExp(r'^publish_to:', multiLine: true).hasMatch(pubspec)) {
    throw StateError('Candidate must omit publish_to');
  }
  final result = Process.runSync(
    Platform.resolvedExecutable,
    ['pub', 'publish', '--dry-run'],
    workingDirectory: root.path,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw StateError(
      'Candidate dry run failed (${result.exitCode})\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
  return parseCandidateFiles(result.stdout as String);
}

const inputRoots = <String>[
  'lib/',
  'android/',
  'test/',
  'test_flutter/',
  'tool/',
  '.github/workflows/',
  '.github/scripts/',
  'example/lib/',
  'example/test/',
  'example/integration_test/',
  'example/android/',
  'example/ios/',
  'example/macos/',
  'example/linux/',
  'example/windows/',
  'example/web/',
];
bool isReleaseInput(String name) {
  if (name.startsWith('/') || name.split('/').any((p) => p == '..')) {
    return false;
  }
  final parts = name.split('/'), base = name.split('/').last;
  if (parts.any(
    (p) => [
      'build',
      '.dart_tool',
      '.gradle',
      'ephemeral',
      'Pods',
      '.plugin_symlinks',
      '.idea',
    ].contains(p),
  )) {
    return false;
  }
  if ([
        'gradlew',
        'gradlew.bat',
        'gradle-wrapper.jar',
        'local.properties',
        'Generated.xcconfig',
        'flutter_export_environment.sh',
        'generated_plugins.cmake',
      ].contains(base) ||
      base.startsWith('GeneratedPluginRegistrant.') ||
      base.startsWith('generated_plugin_registrant.') ||
      base.endsWith('.iml')) {
    return false;
  }
  return inputRoots.any(name.startsWith) ||
      [
        'pubspec.yaml',
        'example/pubspec.yaml',
        'example/analysis_options.yaml',
        'analysis_options.yaml',
        '.gitattributes',
        '.pubignore',
        'LICENSE',
        'THIRD_PARTY_NOTICES.md',
      ].contains(name);
}

String bytesHash(List<int> bytes) => sha256.convert(bytes).toString();
Map<String, String> canonicalInput(String name, List<int> bytes) {
  var mode = 'binary';
  var canonical = bytes;
  if (!bytes.contains(0)) {
    try {
      var text = utf8.decode(bytes).replaceAll('\r\n', '\n');
      mode = 'utf8-lf';
      // This guard affects publishing, not runtime compatibility. The exact
      // candidate bytes are separately bound by the archive manifest/hash.
      if (name == 'pubspec.yaml') {
        text = text.replaceAll(
          RegExp(r'^publish_to: none\n?', multiLine: true),
          '',
        );
        mode = 'utf8-lf-development-guard';
      }
      canonical = utf8.encode(text);
    } on FormatException {
      /* Preserve binary bytes. */
    }
  }
  return {'mode': mode, 'sha256': bytesHash(canonical)};
}

String sourceDigest(Map<String, dynamic> inputs) {
  final names = inputs.keys.toList()..sort();
  return bytesHash(
    utf8.encode(jsonEncode({for (final n in names) n: inputs[n]})),
  );
}

List<String> gitInputs(Directory root, {bool untracked = false}) {
  final result = Process.runSync('git', [
    '-c',
    'safe.directory=${root.absolute.path.replaceAll('\\', '/')}',
    '-C',
    root.absolute.path,
    'ls-files',
    '-z',
    if (untracked) ...['--others', '--exclude-standard'] else '--cached',
  ], stdoutEncoding: utf8);
  if (result.exitCode != 0) {
    throw StateError('Git input inventory unavailable: ${result.stderr}');
  }
  return (result.stdout as String)
      .split('\u0000')
      .where((n) => n.isNotEmpty && isReleaseInput(n))
      .toSet()
      .toList()
    ..sort();
}

Map<String, dynamic> readInputs(Directory root, Iterable<String> names) {
  final result = <String, dynamic>{};
  for (final name in names.toList()..sort()) {
    if (!isReleaseInput(name)) throw FormatException('Unexpected input: $name');
    var current = root.path;
    for (final part in name.split('/')) {
      current = '$current/$part';
      if (FileSystemEntity.isLinkSync(current)) {
        throw FormatException('Symlink input: $name');
      }
    }
    final file = File('${root.path}/$name');
    if (!file.existsSync()) throw FormatException('Missing input: $name');
    result[name] = canonicalInput(name, file.readAsBytesSync());
  }
  return result;
}

List<String> checkRelease(
  Directory root,
  Map<String, dynamic> manifest, {
  bool developmentInputs = false,
  bool technicalOnly = false,
  bool candidate = false,
  List<String> Function(Directory)? selectFiles,
}) {
  final problems = <String>[];
  if (developmentInputs) {
    problems.add('Development snapshot is not release eligible');
  }
  final pubspec = File(
    '${root.path}/pubspec.yaml',
  ).readAsStringSync().replaceAll('\r\n', '\n');
  if (!RegExp(
        r'^name: flutter_true_time$',
        multiLine: true,
      ).hasMatch(pubspec) ||
      !RegExp(r'^version: 0.1.0-dev.1$', multiLine: true).hasMatch(pubspec)) {
    problems.add('Unexpected package name/version');
  }
  final guarded = RegExp(
    r'^publish_to: none$',
    multiLine: true,
  ).hasMatch(pubspec);
  if (!candidate && !guarded) {
    problems.add('Development publication guard must remain enabled');
  }
  if (candidate && RegExp(r'^publish_to:', multiLine: true).hasMatch(pubspec)) {
    problems.add('Candidate must omit publish_to');
  }
  if (manifest['schema'] != 2) {
    return [...problems, 'Regenerate the version-2 release manifest'];
  }
  final expected = Map<String, dynamic>.from(manifest['inputs'] as Map);
  if (sourceDigest(expected) != manifest['sourceDigest']) {
    problems.add('Invalid manifest source digest');
  }
  try {
    final tracked = gitInputs(root),
        untracked = gitInputs(root, untracked: true);
    if (untracked.isNotEmpty && !developmentInputs) {
      problems.add('Untracked release inputs: ${untracked.join(', ')}');
    }
    final actual = readInputs(root, {...tracked, ...untracked});
    if (sourceDigest(actual) != manifest['sourceDigest']) {
      problems.add(
        'Reviewed source fingerprint changed; regenerate manifest and qualification evidence',
      );
    }
  } catch (e) {
    problems.add('Source verification failed: $e');
  }
  if (manifest['developmentInputs'] != false && !developmentInputs) {
    problems.add('Manifest includes development-only untracked inputs');
  }
  final gates = Map<String, dynamic>.from(manifest['gates'] as Map);
  String? candidateDigest;
  if (candidate && !technicalOnly && problems.isEmpty) {
    try {
      candidateDigest = sourceDigest(
        readCandidate(root, (selectFiles ?? selectCandidateFiles)(root)),
      );
    } catch (error) {
      problems.add('Candidate verification failed: $error');
    }
  }
  for (final name in requiredGates) {
    if (technicalOnly && candidateGates.contains(name)) {
      continue;
    }
    final gate = gates[name];
    if (name == 'physical_lifecycle' &&
        manifest['version'] == '0.1.0-dev.1' &&
        gate is Map &&
        gate['status'] == 'waived') {
      continue;
    }
    if (gate is! Map || gate['status'] != 'passed') {
      problems.add('Pending gate: $name');
      continue;
    }
    if (gate['sourceDigest'] != manifest['sourceDigest']) {
      problems.add('Stale source evidence: $name');
    }
    final evidence = gate['evidence'], hash = gate['sha256'];
    if (evidence is! String ||
        !RegExp(r'^docs/evidence/[a-zA-Z0-9_.-]+$').hasMatch(evidence) ||
        hash is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      problems.add('Missing evidence: $name');
      continue;
    }
    final file = File('${root.path}/$evidence');
    if (!file.existsSync() ||
        FileSystemEntity.isLinkSync(file.path) ||
        bytesHash(file.readAsBytesSync()) != hash) {
      problems.add('Evidence hash mismatch: $name');
      continue;
    }
    if (candidate && candidateGates.contains(name)) {
      try {
        final record = jsonDecode(file.readAsStringSync());
        if (candidateDigest == null ||
            record is! Map ||
            record['candidateDigest'] != candidateDigest) {
          problems.add('Stale candidate evidence: $name');
        }
      } on FormatException {
        problems.add('Invalid candidate evidence: $name');
      }
    }
  }
  return problems;
}
