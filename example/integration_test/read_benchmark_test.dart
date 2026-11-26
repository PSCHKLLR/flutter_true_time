import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_true_time_example/src/native_read_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('offline native snapshot/read/now benchmark', (tester) async {
    if (kDebugMode) {
      throw StateError('Use --release or --profile for benchmark evidence');
    }
    const device = String.fromEnvironment('BENCHMARK_DEVICE');
    const revision = String.fromEnvironment('BENCHMARK_REVISION');
    const foreground = bool.fromEnvironment(
      'BENCHMARK_FOREGROUND',
      defaultValue: true,
    );
    if (device.isEmpty || revision.isEmpty) {
      throw StateError(
        'Record BENCHMARK_DEVICE and BENCHMARK_REVISION dart-defines',
      );
    }
    final results = <Map<String, Object?>>[];
    for (final mode in ['baseline', 'snapshot', 'read', 'now']) {
      results.add(await benchmarkReads(mode: mode, foreground: foreground));
    }
    binding.reportData = {
      'schema': 1,
      'device': device,
      'revision': revision,
      'buildMode': kReleaseMode ? 'release' : 'profile',
      'platform': defaultTargetPlatform.name,
      'results': results,
      'qualification':
          'latency only; pair with allocation/GC trace and toolchain record',
    };
  });
}
