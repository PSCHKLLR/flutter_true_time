import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
// Retain compatibility with the minimum Flutter SDK's built-in Material API.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'src/native_read_fixture.dart';

/// Standalone release entry point; does not require a VM-service driver.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: _BenchmarkPage()));
}

Future<String> _measure() async {
  const device = String.fromEnvironment('BENCHMARK_DEVICE');
  const revision = String.fromEnvironment('BENCHMARK_REVISION');
  const foreground = bool.fromEnvironment(
    'BENCHMARK_FOREGROUND',
    defaultValue: true,
  );
  if (kDebugMode || device.isEmpty || revision.isEmpty) {
    throw StateError(
      'Use release/profile and record BENCHMARK_DEVICE and BENCHMARK_REVISION',
    );
  }
  final results = <Map<String, Object?>>[];
  for (final mode in ['baseline', 'snapshot', 'read', 'now']) {
    results.add(await benchmarkReads(mode: mode, foreground: foreground));
  }
  return const JsonEncoder.withIndent('  ').convert({
    'schema': 1,
    'device': device,
    'revision': revision,
    'buildMode': kReleaseMode ? 'release' : 'profile',
    'runtime': Platform.version,
    'os': Platform.operatingSystem,
    'osVersion': Platform.operatingSystemVersion,
    'results': results,
    'qualification': 'latency only; allocation/GC trace remains separate',
  });
}

class _BenchmarkPage extends StatefulWidget {
  const _BenchmarkPage();
  @override
  State<_BenchmarkPage> createState() => _BenchmarkPageState();
}

class _BenchmarkPageState extends State<_BenchmarkPage> {
  late final Future<String> _report = _measure();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Native read benchmark')),
    body: FutureBuilder<String>(
      future: _report,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SelectableText(snapshot.error.toString());
        }
        final report = snapshot.data;
        if (report == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          children: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: report)),
              child: const Text('Copy benchmark JSON'),
            ),
            Expanded(
              child: SingleChildScrollView(child: SelectableText(report)),
            ),
          ],
        );
      },
    ),
  );
}
