import 'dart:convert';
import 'dart:io';

/// Parses rounded VM scavenge telemetry, not exact allocation counters.
Map<String, Object?> summarizeNativeGc(String log) {
  final lines = const LineSplitter().convert(log);
  final begin = lines.where((s) => s.startsWith('NATIVE_GC_BEGIN ')).toList();
  final end = lines.where((s) => s.startsWith('NATIVE_GC_END ')).toList();
  if (begin.length != 1 || end.length != 1) {
    throw const FormatException('Require one begin/end marker');
  }
  final header = begin.single.split(' ');
  if (header.length != 5 ||
      !['baseline', 'snapshot', 'read', 'now'].contains(header[1]) ||
      !['true', 'false'].contains(header[2])) {
    throw const FormatException('Invalid workload marker');
  }
  final calls = int.parse(header[3]);
  final first = lines.indexOf(begin.single), last = lines.indexOf(end.single);
  if (calls < 1 || first >= last) {
    throw const FormatException('Invalid call count/marker order');
  }
  final rows = <List<num>>[];
  for (final line in lines.sublist(first + 1, last)) {
    if (!RegExp(r'^\[\s*main\s*,').hasMatch(line)) continue;
    final parts = line.split(',');
    if (parts.length < 7 || !parts[1].trim().startsWith('Scavenge(')) {
      throw const FormatException('Unsupported non-scavenge collection');
    }
    final row = <num>[
      int.parse(parts[2].trim()),
      double.parse(parts[4].trim()),
      double.parse(parts[5].trim()),
      double.parse(parts[6].trim()),
    ];
    if (rows.isNotEmpty && row[0] != rows.last[0] + 1) {
      throw const FormatException('Missing collection rows');
    }
    if (row.any((v) => !v.isFinite || v < 0)) {
      throw const FormatException('Invalid collection values');
    }
    rows.add(row);
  }
  var growthMiB = 0.0, gcMs = 0.0, maximumGcMs = 0.0;
  for (var i = 0; i < rows.length; i++) {
    gcMs += rows[i][1];
    if (rows[i][1] > maximumGcMs) maximumGcMs = rows[i][1].toDouble();
    if (i == 0) continue;
    final growth = rows[i][2] - rows[i - 1][3];
    if (growth < 0) throw const FormatException('Negative heap growth');
    growthMiB += growth;
  }
  final intervals = rows.isEmpty ? 0 : rows.length - 1;
  if ((header[1] == 'baseline' && rows.isNotEmpty) ||
      (header[1] != 'baseline' && intervals < 1)) {
    throw const FormatException('Insufficient/unexpected scavenge evidence');
  }
  return {
    'mode': header[1],
    'foreground': header[2] == 'true',
    'calls': calls,
    'clockDomain': header[4],
    'checksum': int.parse(end.single.substring('NATIVE_GC_END '.length)),
    'scavenges': rows.length,
    'observedIntervals': intervals,
    'observedYoungGrowthMiB': intervals == 0 ? null : growthMiB,
    'observedYoungGrowthBytesPerCall': intervals == 0
        ? null
        : growthMiB * 1048576 / calls,
    'maximumRoundingErrorBytesPerCall': intervals == 0
        ? null
        : intervals * 0.1 * 1048576 / calls,
    'sumReportedGcMs': gcMs,
    'maximumReportedGcMs': maximumGcMs,
    'rowColumns': ['gcId', 'gcMs', 'youngBeforeMiB', 'youngAfterMiB'],
    'rows': rows,
  };
}

void main(List<String> args) {
  if (args.isEmpty) throw ArgumentError('Supply verbose-GC log paths');
  final results = [
    for (final path in args)
      {
        'file': File(path).uri.pathSegments.last,
        ...summarizeNativeGc(File(path).readAsStringSync()),
      },
  ];
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(results));
}
