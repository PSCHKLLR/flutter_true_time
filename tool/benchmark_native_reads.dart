// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
// The host tool deliberately shares the example's exact offline workload.
// ignore: avoid_relative_lib_imports
import '../example/lib/src/native_read_fixture.dart';

Future<void> main(List<String> args) async {
  const allowed = {
    'mode',
    'warmup',
    'count',
    'batches',
    'foreground',
    'revision',
  };
  final options = <String, String>{};
  for (final argument in args) {
    final match = RegExp(r'^--([a-z]+)=(.+)$').firstMatch(argument);
    if (match == null ||
        !allowed.contains(match[1]) ||
        options.containsKey(match[1])) {
      throw ArgumentError(
        'Use unique --mode=baseline|snapshot|read|now|all, --warmup=N, --count=N, --batches=N, --foreground=true|false, --revision=SHA',
      );
    }
    options[match[1]!] = match[2]!;
  }
  final mode = options['mode'] ?? 'all';
  final foreground = options['foreground'] ?? 'true';
  if (!['all', 'baseline', 'snapshot', 'read', 'now'].contains(mode) ||
      !['true', 'false'].contains(foreground)) {
    throw ArgumentError('Invalid mode or foreground value');
  }
  final results = <Map<String, Object?>>[];
  for (final selected
      in mode == 'all' ? ['baseline', 'snapshot', 'read', 'now'] : [mode]) {
    results.add(
      await benchmarkReads(
        mode: selected,
        warmup: int.parse(options['warmup'] ?? '10000'),
        count: int.parse(options['count'] ?? '10000'),
        batches: int.parse(options['batches'] ?? '25'),
        foreground: foreground == 'true',
      ),
    );
  }
  print(
    const JsonEncoder.withIndent('  ').convert({
      'schema': 1,
      'runtime': Platform.version,
      'os': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'revision': options['revision'] ?? 'unrecorded',
      'fixture': 'offline native reads; no epoch or storage I/O',
      'results': results,
    }),
  );
}
