import 'dart:convert';
import 'dart:io';
import 'release_support.dart';

/// Explicit development operation. Never changes Git's index or publishes.
void main(List<String> args) {
  if (args.any((a) => a != '--development')) {
    throw ArgumentError('Only --development is supported');
  }
  try {
    final result = updateReleaseManifest(
      Directory.current,
      development: args.contains('--development'),
    );
    stdout.writeln(
      'Canonical source digest: ${result.sourceDigest} (${result.inputCount} inputs). Changed: ${result.changed}.',
    );
  } on StateError catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  }
}

/// Regenerates qualification inputs for [root] without changing Git's index.
({String sourceDigest, int inputCount, bool changed}) updateReleaseManifest(
  Directory root, {
  bool development = false,
}) {
  final version = readReleaseVersion(
    File('${root.path}/pubspec.yaml').readAsStringSync(),
  );
  final tracked = gitInputs(root), untracked = gitInputs(root, untracked: true);
  if (untracked.isNotEmpty && !development) {
    throw StateError(
      'Stage new release inputs first, or use --development for a non-release snapshot.',
    );
  }
  final inputs = readInputs(root, {...tracked, ...untracked}),
      digest = sourceDigest(inputs);
  final file = File('${root.path}/docs/release_gates.json');
  final previous = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final gates = Map<String, dynamic>.from(previous['gates'] as Map);
  final changed =
      previous['sourceDigest'] != digest || previous['version'] != version;
  if (changed) {
    for (final name in requiredGates) {
      final gate = Map<String, dynamic>.from(gates[name] as Map? ?? {});
      if (gate['evidence'] != null) {
        gate['historicalEvidence'] = {
          'evidence': gate['evidence'],
          'sha256': gate['sha256'],
          'sourceDigest': gate['sourceDigest'],
        };
      }
      gate.remove('evidence');
      gate.remove('sha256');
      gate.remove('sourceDigest');
      if (name == 'physical_lifecycle' &&
          gate['status'] == 'waived' &&
          version == '0.1.0-dev.1') {
        gates[name] = gate;
        continue;
      }
      if (gate['status'] != 'blocked') gate['status'] = 'pending';
      gate['note'] = 'Source changed; fresh qualification evidence required.';
      gates[name] = gate;
    }
  }
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'schema': 2, 'version': version, 'developmentInputs': untracked.isNotEmpty, 'sourceDigest': digest, 'inputs': inputs, 'gates': gates})}\n',
  );
  return (sourceDigest: digest, inputCount: inputs.length, changed: changed);
}
