import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:flutter_true_time/core.dart';
import 'helpers.dart';

void main() {
  test('native platform clock produces same-epoch nondecreasing readings', () {
    final clock = createPlatformClock();
    final first = clock.snapshot(), second = clock.snapshot();
    expect(second.sessionId, first.sessionId);
    expect(second.elapsed >= first.elapsed, isTrue);
  });
  for (final badOrigin in [false, true]) {
    test(
      'loopback NTP ${badOrigin ? 'rejects nonce mismatch' : 'validates a complete response'}',
      () async {
        final server = await RawDatagramSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final subscription = server.listen((event) {
          if (event != RawSocketEvent.read) return;
          final request = server.receive();
          if (request == null) return;
          final bytes = Uint8List(48);
          bytes[0] = 0x24;
          bytes[1] = 2;
          bytes[3] = 236;
          bytes.setRange(24, 32, request.data.sublist(40, 48));
          if (badOrigin) bytes[24] ^= 1;
          final sec =
              DateTime.utc(2026, 11, 11).millisecondsSinceEpoch ~/ 1000 +
              2208988800;
          final fields = ByteData.sublistView(bytes);
          fields.setUint32(32, sec);
          fields.setUint32(40, sec);
          server.send(bytes, request.address, request.port);
        });
        try {
          final source = NtpSource(
            '127.0.0.1',
            port: server.port,
            providerGroup: 'loopback',
          );
          final future = source.query(FakeClock(), const Duration(seconds: 1));
          if (badOrigin) {
            await expectLater(future, throwsA(isA<TrustedTimeException>()));
          } else {
            final sample = await future;
            expect(sample.utc, DateTime.utc(2026, 11, 11));
            expect(sample.endpointIdentity, contains('127.0.0.1'));
          }
        } finally {
          server.close();
          await subscription.cancel();
        }
      },
    );
  }
  test('silent loopback source times out and releases its socket', () async {
    final server = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    try {
      await expectLater(
        NtpSource(
          '127.0.0.1',
          port: server.port,
          providerGroup: 'loopback',
        ).query(FakeClock(), const Duration(milliseconds: 20)),
        throwsA(isA<Exception>()),
      );
    } finally {
      server.close();
    }
  });

  test('NTP cancellation closes its UDP socket before returning', () async {
    final received = Completer<Datagram>();
    final server = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final subscription = server.listen((event) {
      if (event == RawSocketEvent.read) {
        final packet = server.receive();
        if (packet != null && !received.isCompleted) received.complete(packet);
      }
    });
    final signal = CancellationSignal();
    try {
      final result = NtpSource(
        '127.0.0.1',
        port: server.port,
        providerGroup: 'local',
      ).query(FakeClock(), const Duration(seconds: 3), cancellation: signal);
      final expected = expectLater(
        result,
        throwsA(isA<TrustedTimeException>()),
      );
      final packet = await received.future;
      signal.cancel('test');
      await expected;
      final rebound = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        packet.port,
        reuseAddress: false,
      );
      rebound.close();
    } finally {
      signal.cancel();
      server.close();
      await subscription.cancel();
    }
  });
}
