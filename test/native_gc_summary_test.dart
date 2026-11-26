import 'package:test/test.dart';
import '../tool/summarize_native_gc.dart';

void main() {
  const log = '''
NATIVE_GC_BEGIN read false 2000000 windows.qpc.us.v1
[ main , Scavenge(new space), 12, 0.01, 0.2, 2.0, 0.1, ]
[ main , Scavenge(new space), 13, 0.02, 0.3, 2.0, 0.0, ]
NATIVE_GC_END 123
''';
  test('counts only complete marked intervals and preserves rounded rows', () {
    final result = summarizeNativeGc(log);
    expect(result['scavenges'], 2);
    expect(result['observedIntervals'], 1);
    expect(result['observedYoungGrowthMiB'], closeTo(1.9, 1e-10));
    expect(result['observedYoungGrowthBytesPerCall'], closeTo(.9961472, 1e-10));
    expect(
      result['maximumRoundingErrorBytesPerCall'],
      closeTo(.0524288, 1e-10),
    );
    expect(result['sumReportedGcMs'], .5);
    expect(result['checksum'], 123);
  });
  test('baseline without collections makes no allocation claim', () {
    final result = summarizeNativeGc(
      'NATIVE_GC_BEGIN baseline true 10 test\nNATIVE_GC_END 0\n',
    );
    expect(result['observedYoungGrowthBytesPerCall'], isNull);
  });
  test('rejects missing, unsupported, or ambiguous collection evidence', () {
    for (final invalid in [
      log.replaceFirst('13,', '14,'),
      log.replaceFirst('Scavenge(', 'MarkSweep('),
      '$log$log',
      log.replaceFirst('NATIVE_GC_END', 'MISSING'),
    ]) {
      expect(() => summarizeNativeGc(invalid), throwsFormatException);
    }
  });
}
