import 'dart:convert';
import 'dart:io';
import 'release_support.dart';

/// Read-only: never updates manifests, prepares builds, stages files or publishes.
void main(List<String> args) {
  if (args.any(
    (a) => !['--development', '--technical', '--candidate'].contains(a),
  )) {
    throw ArgumentError('Use --development, --technical, or --candidate');
  }
  final manifest =
      jsonDecode(File('docs/release_gates.json').readAsStringSync())
          as Map<String, dynamic>;
  final problems = checkRelease(
    Directory.current,
    manifest,
    developmentInputs: args.contains('--development'),
    technicalOnly: args.contains('--technical'),
    candidate: args.contains('--candidate'),
  );
  for (final problem in problems) {
    stderr.writeln(problem);
  }
  if (problems.isNotEmpty) {
    stderr.writeln('Release blocked. No publication was attempted.');
    exitCode = 1;
  } else {
    stdout.writeln(
      'Selected recorded gates passed. Publishing still requires explicit owner instruction.',
    );
  }
}
