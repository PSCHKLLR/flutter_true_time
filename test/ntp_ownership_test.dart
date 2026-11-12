import 'dart:async';
import 'dart:io';
import 'package:test/test.dart';
import 'package:flutter_true_time/core.dart';
import 'package:flutter_true_time/src/ntp_io.dart' as transport;
import 'helpers.dart';

class SendFailureSocket extends Stream<RawSocketEvent>
    implements RawDatagramSocket {
  SendFailureSocket(this.throwsOnSend) {
    controller = StreamController<RawSocketEvent>(
      onCancel: () {
        cancelled = true;
      },
    );
  }
  final bool throwsOnSend;
  late final StreamController<RawSocketEvent> controller;
  bool closed = false, cancelled = false;
  @override
  set writeEventsEnabled(bool value) {}
  @override
  int send(List<int> buffer, InternetAddress address, int port) {
    if (throwsOnSend) throw const SocketException('injected send failure');
    return 0;
  }

  @override
  void close() {
    closed = true;
    unawaited(controller.close());
  }

  @override
  StreamSubscription<RawSocketEvent> listen(
    void Function(RawSocketEvent)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => controller.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'pre-cancelled NTP query starts no transport and emits no secondary error',
    () async {
      var bound = false;
      final signal = CancellationSignal()..cancel();
      await expectLater(
        transport.queryNtp(
          '127.0.0.1',
          123,
          FakeClock(),
          const Duration(seconds: 1),
          cancellation: signal,
          bindSocket: (_, _) async {
            bound = true;
            return SendFailureSocket(false);
          },
        ),
        throwsA(isA<TrustedTimeException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(bound, isFalse);
    },
  );
  for (final port in [0, -1, 65536]) {
    test('reject invalid NTP port $port before transport setup', () async {
      await expectLater(
        NtpSource(
          '127.0.0.1',
          providerGroup: 'local',
          port: port,
        ).query(FakeClock(), const Duration(seconds: 1)),
        throwsArgumentError,
      );
      await Future<void>.delayed(Duration.zero);
    });
  }
  for (final timeout in [Duration.zero, const Duration(microseconds: -1)]) {
    test('reject nonpositive NTP timeout $timeout', () async {
      await expectLater(
        NtpSource(
          '127.0.0.1',
          providerGroup: 'local',
        ).query(FakeClock(), timeout),
        throwsArgumentError,
      );
    });
  }
  for (final throwsOnSend in [false, true]) {
    test(
      'NTP send failure ($throwsOnSend) is observed once and releases resources',
      () async {
        final socket = SendFailureSocket(throwsOnSend);
        await expectLater(
          transport.queryNtp(
            '127.0.0.1',
            123,
            FakeClock(),
            const Duration(seconds: 1),
            bindSocket: (_, _) async => socket,
          ),
          throwsA(isA<Exception>()),
        );
        await Future<void>.delayed(Duration.zero);
        expect(socket.closed, isTrue);
        expect(socket.cancelled, isTrue);
      },
    );
  }
}
