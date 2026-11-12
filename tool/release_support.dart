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
  'apple_privacy_archive',
  'provenance_dependencies',
  'owned_repository_security',
  'name_availability',
  'archive_consumer',
  'owner_archive_approval',
];
const inputRoots = <String>[
  'lib/',
  'android/',
  'test/',
  'test_flutter/',
  'tool/',
  '.github/workflows/',
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
  for (final name in requiredGates) {
    if (technicalOnly &&
        ['archive_consumer', 'owner_archive_approval'].contains(name)) {
      continue;
    }
    final gate = gates[name];
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
    }
  }
  return problems;
}
