import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:flutter_true_time/src/ntp_io.dart';

void main() {
  for (final year in [2026, 2040, 2100]) {
    test('NTP unfolds era for $year without device time', () {
      final utc = DateTime.utc(year);
      final seconds = utc.millisecondsSinceEpoch ~/ 1000 + 2208988800;
      final data = Uint8List(48);
      ByteData.sublistView(data).setUint32(40, seconds % 4294967296);
      expect(decodeNtpTimestamp(data, 40), utc);
    });
  }
  test('zero timestamp is rejected', () {
    expect(() => decodeNtpTimestamp(Uint8List(48), 40), throwsException);
  });
}
