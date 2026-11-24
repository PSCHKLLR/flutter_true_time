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

class OwnershipSocket extends SendFailureSocket {
  OwnershipSocket({this.onSend, this.leakClose = false, this.backing})
    : super(false);

  final void Function()? onSend;
  final bool leakClose;
  final RawDatagramSocket? backing;
  final sent = Completer<void>(), released = Completer<void>();
  final received = Completer<void>();
  int listens = 0, sends = 0, receives = 0;
  bool open = true;
  Datagram? packet;

  @override
  int send(List<int> buffer, InternetAddress address, int port) {
    sends++;
    if (!sent.isCompleted) sent.complete();
    onSend?.call();
    return buffer.length;
  }

  @override
  Datagram? receive() {
    receives++;
    if (!received.isCompleted) received.complete();
    return packet;
  }

  @override
  StreamSubscription<RawSocketEvent> listen(
    void Function(RawSocketEvent)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    listens++;
    return super.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  void close() {
    if (leakClose) return;
    open = false;
    backing?.close();
    super.close();
    if (!released.isCompleted) released.complete();
  }

  void disposeFixture() {
    backing?.close();
    super.close();
  }
}

void expectReleased(OwnershipSocket socket, {required bool listened}) {
  expect(socket.open, isFalse, reason: 'The query must close its owned socket');
  expect(socket.listens, listened ? 1 : 0);
  expect(
    socket.cancelled,
    listened,
    reason: 'Every installed listener must be cancelled',
  );
}

Future<void> drainCallbacks() => Future<void>.delayed(Duration.zero);

void main() {
  final address = InternetAddress.loopbackIPv4;
  final cancelled = throwsA(
    isA<TrueTimeException>().having((error) => error.code, 'code', 'cancelled'),
  );

  test('cancellation during DNS never starts a socket bind', () async {
    final lookup = Completer<List<InternetAddress>>();
    final started = Completer<void>();
    final signal = CancellationSignal();
    var binds = 0;
    final query = transport.queryNtp(
      'test.invalid',
      123,
      FakeClock(),
      const Duration(seconds: 2),
      cancellation: signal,
      lookupHost: (_) {
        started.complete();
        return lookup.future;
      },
      bindSocket: (_, _) async {
        binds++;
        return OwnershipSocket();
      },
    );
    final assertion = expectLater(query, cancelled);
    await started.future;
    signal.cancel('test');
    await assertion;
    lookup.complete([address]);
    await drainCallbacks();
    expect(binds, 0);
  });

  test(
    'a socket returned after cancellation during bind is closed without a listener',
    () async {
      final binding = Completer<RawDatagramSocket>();
      final started = Completer<void>();
      final signal = CancellationSignal();
      final socket = OwnershipSocket();
      addTearDown(socket.disposeFixture);
      final query = transport.queryNtp(
        'test.invalid',
        123,
        FakeClock(),
        const Duration(seconds: 2),
        cancellation: signal,
        lookupHost: (_) async => [address],
        bindSocket: (_, _) {
          started.complete();
          return binding.future;
        },
      );
      final assertion = expectLater(query, cancelled);
      await started.future;
      signal.cancel('test');
      await assertion;
      binding.complete(socket);
      await socket.released.future.timeout(const Duration(seconds: 1));
      expectReleased(socket, listened: false);
      expect(socket.sends, 0);
    },
  );

  for (final phase in ['send', 'waiting', 'queued read', 'after receive']) {
    test(
      'cancellation during $phase releases the socket and listener',
      () async {
        final signal = CancellationSignal();
        final socket = OwnershipSocket(
          onSend: phase == 'send' ? () => signal.cancel('test') : null,
        );
        addTearDown(socket.disposeFixture);
        final query = transport.queryNtp(
          'test.invalid',
          123,
          FakeClock(),
          const Duration(seconds: 2),
          cancellation: signal,
          lookupHost: (_) async => [address],
          bindSocket: (_, _) async => socket,
        );
        final assertion = expectLater(query, cancelled);
        await socket.sent.future;
        if (phase == 'queued read' || phase == 'after receive') {
          // An empty receive is ignored, leaving the query waiting for evidence.
          socket.controller.add(RawSocketEvent.read);
          if (phase == 'after receive') await socket.received.future;
        }
        signal.cancel('test');
        await assertion;
        expect(
          socket.open,
          isFalse,
          reason: 'Close must precede cancellation completion',
        );
        await drainCallbacks();
        expectReleased(socket, listened: true);
        expect(socket.sends, 1);
        expect(socket.receives, phase == 'after receive' ? 1 : 0);
      },
    );
  }

  test('source deadline releases the socket and listener', () async {
    final socket = OwnershipSocket();
    addTearDown(socket.disposeFixture);
    await expectLater(
      transport.queryNtp(
        'test.invalid',
        123,
        FakeClock(),
        const Duration(milliseconds: 20),
        lookupHost: (_) async => [address],
        bindSocket: (_, _) async => socket,
      ),
      cancelled,
    );
    expect(
      socket.open,
      isFalse,
      reason: 'Close must precede timeout completion',
    );
    await drainCallbacks();
    expectReleased(socket, listened: true);
  });

  test(
    'ownership assertions reject a fixture that leaves its real socket open',
    () async {
      final backing = await RawDatagramSocket.bind(address, 0);
      final socket = OwnershipSocket(leakClose: true, backing: backing);
      addTearDown(socket.disposeFixture);
      final signal = CancellationSignal();
      final query = transport.queryNtp(
        'test.invalid',
        123,
        FakeClock(),
        const Duration(seconds: 2),
        cancellation: signal,
        lookupHost: (_) async => [address],
        bindSocket: (_, _) async => socket,
      );
      final assertion = expectLater(query, cancelled);
      await socket.sent.future;
      signal.cancel('test');
      await assertion;
      await drainCallbacks();
      expect(socket.cancelled, isTrue);
      // Prove that this negative fixture retains an actual OS socket, rather
      // than accepting/suppressing a port-rebind exception or only changing flags.
      expect(backing.send([1], address, 9), 1);
      expect(
        () => expectReleased(socket, listened: true),
        throwsA(isA<TestFailure>()),
      );
    },
  );

  test(
    'pre-cancelled NTP query starts no transport and emits no secondary error',
    () async {
      var bound = false, lookedUp = false;
      final signal = CancellationSignal()..cancel();
      await expectLater(
        transport.queryNtp(
          '127.0.0.1',
          123,
          FakeClock(),
          const Duration(seconds: 1),
          cancellation: signal,
          lookupHost: (_) async {
            lookedUp = true;
            return [address];
          },
          bindSocket: (_, _) async {
            bound = true;
            return SendFailureSocket(false);
          },
        ),
        throwsA(isA<TrueTimeException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(bound, isFalse);
      expect(lookedUp, isFalse);
    },
  );
  for (final phase in ['DNS', 'bind']) {
    test('late $phase failure after cancellation is still observed', () async {
      final lookup = Completer<List<InternetAddress>>();
      final binding = Completer<RawDatagramSocket>();
      final started = Completer<void>();
      final signal = CancellationSignal();
      final query = transport.queryNtp(
        'test.invalid',
        123,
        FakeClock(),
        const Duration(seconds: 2),
        cancellation: signal,
        lookupHost: (_) {
          if (phase == 'DNS') started.complete();
          return phase == 'DNS' ? lookup.future : Future.value([address]);
        },
        bindSocket: (_, _) {
          started.complete();
          return binding.future;
        },
      );
      final assertion = expectLater(query, cancelled);
      await started.future;
      signal.cancel('test');
      await assertion;
      if (phase == 'DNS') {
        lookup.completeError(StateError('late DNS failure'));
      } else {
        binding.completeError(const SocketException('late bind failure'));
      }
      // The test zone also fails if the detached operation leaks its error.
      await drainCallbacks();
    });
  }
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
