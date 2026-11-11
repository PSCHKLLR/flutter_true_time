import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

/// Read-only, fail-closed release readiness check. Never publishes or edits files.
void main() {
  final problems = <String>[];
  final pubspec = File('pubspec.yaml').readAsStringSync();
  if (!RegExp(
    r'^name: flutter_true_time$',
    multiLine: true,
  ).hasMatch(pubspec)) {
    problems.add('Unexpected package name');
  }
  if (!RegExp(r'^version: 0.1.0-dev.1$', multiLine: true).hasMatch(pubspec)) {
    problems.add('Release version changed: re-review gates');
  }
  final manifest =
      jsonDecode(File('docs/release_gates.json').readAsStringSync())
          as Map<String, dynamic>;
  final required = <String>{
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
  };
  final gates = Map<String, dynamic>.from(manifest['gates'] as Map);
  for (final name in required) {
    final gate = gates[name];
    if (gate is! Map || gate['status'] != 'passed') {
      problems.add('Pending gate: $name');
      continue;
    }
    final evidence = gate['evidence'];
    final expected = gate['sha256'];
    if (evidence is! String ||
        !RegExp(r'^docs/evidence/[a-zA-Z0-9_.-]+$').hasMatch(evidence) ||
        expected is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(expected)) {
      problems.add('Missing verified evidence: $name');
      continue;
    }
    final file = File(evidence);
    if (!file.existsSync() ||
        sha256.convert(file.readAsBytesSync()).toString() != expected) {
      problems.add('Evidence hash mismatch: $name');
    }
  }
  // Evidence is tied to the reviewed runtime and host configuration.
  final expectedFiles = Map<String, dynamic>.from(
    manifest['sourceSha256'] as Map,
  );
  final actual = <String, String>{};
  for (final root in [
    'lib',
    'android',
    'example/lib',
    'example/android',
    'example/ios',
    'example/macos',
    'example/linux',
    'example/windows',
    'example/web',
  ]) {
    for (final entity in Directory(
      root,
    ).listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.path.replaceAll('\\', '/');
      if (name
              .split('/')
              .any(
                (part) => [
                  'build',
                  '.gradle',
                  'ephemeral',
                  '.plugin_symlinks',
                  'Pods',
                  '.idea',
                ].contains(part),
              ) ||
          name.endsWith('/local.properties') ||
          name.endsWith('/Generated.xcconfig') ||
          name.endsWith('/flutter_export_environment.sh') ||
          name.endsWith('.iml') ||
          name.split('/').last.startsWith('GeneratedPluginRegistrant.')) {
        continue;
      }
      actual[name] = sha256.convert(entity.readAsBytesSync()).toString();
    }
  }
  for (final name in [
    'pubspec.yaml',
    'example/pubspec.yaml',
    'LICENSE',
    'THIRD_PARTY_NOTICES.md',
  ]) {
    actual[name] = sha256.convert(File(name).readAsBytesSync()).toString();
  }
  if (actual.length != expectedFiles.length ||
      actual.entries.any((entry) => expectedFiles[entry.key] != entry.value)) {
    problems.add(
      'Reviewed source fingerprint changed; invalidate and rerun evidence',
    );
  }
  for (final problem in problems) {
    stderr.writeln(problem);
  }
  if (problems.isNotEmpty) {
    stderr.writeln(
      'Release blocked. Keep publish_to: none; no publication was attempted.',
    );
    exitCode = 1;
  } else {
    stdout.writeln(
      'Recorded gates passed. Owner must inspect the exact archive before an explicit publishing instruction.',
    );
  }
}
