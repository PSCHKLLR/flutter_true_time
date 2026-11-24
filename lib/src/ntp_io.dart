import 'cancellation.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'clock.dart';
import 'models.dart';
import 'sources.dart';

Future<TimeSample> queryNtp(
  String host,
  int port,
  MonotonicClock clock,
  Duration timeout, {
  CancellationSignal? cancellation,
  // Internal transport seams for deterministic DNS/bind/resource tests.
  // An injected bind transfers socket ownership even when it completes after
  // cancellation. Late lookup/bind failures remain observed by the query.
  Future<List<InternetAddress>> Function(String host)? lookupHost,
  Future<RawDatagramSocket> Function(InternetAddress address, int port)?
  bindSocket,
}) async {
  cancellation?.throwIfCancelled();
  if (port < 1 || port > 65535) throw ArgumentError.value(port, 'port');
  if (timeout <= Duration.zero) throw ArgumentError.value(timeout, 'timeout');
  RawDatagramSocket? socket;
  Completer<TimeSample>? pending;
  var expired = false;
  final signal = CancellationSignal();
  final detachParent = cancellation?.onCancel(
    () => signal.cancel(cancellation.reason),
  );
  final detachCleanup = signal.onCancel(() {
    expired = true;
    socket?.close();
    if (pending != null && !pending!.isCompleted) {
      pending!.completeError(TrueTimeException('cancelled', signal.reason));
    }
  });
  final timer = Timer(timeout, () => signal.cancel('sourceTimeout'));
  Future<TimeSample> query() async {
    signal.throwIfCancelled();
    final addresses = await (lookupHost ?? InternetAddress.lookup)(host);
    if (expired) throw TimeoutException('DNS deadline expired');
    if (addresses.isEmpty) {
      throw const TrueTimeException('dns', 'No server address');
    }
    final address = addresses.first;
    final bound = await (bindSocket ?? RawDatagramSocket.bind)(
      address.type == InternetAddressType.IPv6
          ? InternetAddress.anyIPv6
          : InternetAddress.anyIPv4,
      0,
    );
    socket = bound;
    if (expired) {
      bound.close();
      throw TimeoutException('Bind deadline expired');
    }
    final bytes = Uint8List(48)..[0] = 0x23;
    final random = Random.secure();
    for (var i = 40; i < 48; i++) {
      bytes[i] = random.nextInt(256);
    }
    bound.writeEventsEnabled = false;
    final start = clock.snapshot();
    final result = Completer<TimeSample>();
    // Observe errors even if send throws before the response is awaited.
    unawaited(
      result.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    pending = result;
    final subscription = bound.listen(
      (event) {
        if (event != RawSocketEvent.read || result.isCompleted) return;
        final packet = bound.receive();
        if (packet == null ||
            packet.address.address != address.address ||
            packet.port != port) {
          return;
        }
        try {
          final end = clock.snapshot();
          final data = packet.data;
          if (data.length < 48 ||
              (data[0] & 7) != 4 ||
              ((data[0] >> 3) & 7) < 3 ||
              ((data[0] >> 3) & 7) > 4 ||
              data[0] >> 6 == 3 ||
              data[1] < 1 ||
              data[1] > 15) {
            throw const TrueTimeException('invalidNtp', 'Invalid NTP header');
          }
          for (var i = 0; i < 8; i++) {
            if (data[24 + i] != bytes[40 + i]) {
              throw const TrueTimeException('invalidNtp', 'Originate mismatch');
            }
          }
          if (start.sessionId != end.sessionId || end.elapsed < start.elapsed) {
            throw const TrueTimeException(
              'continuityLost',
              'Clock changed during query',
            );
          }
          final receive = decodeNtpTimestamp(data, 32),
              transmit = decodeNtpTimestamp(data, 40);
          final rtt = end.elapsed - start.elapsed;
          if (transmit.isBefore(receive) ||
              transmit.difference(receive) >
                  rtt + const Duration(milliseconds: 1)) {
            throw const TrueTimeException(
              'invalidNtp',
              'Invalid processing interval',
            );
          }
          final fields = ByteData.sublistView(data);
          final rootDelay = fields.getInt32(4) / 65536,
              dispersion = fields.getUint32(8) / 65536;
          final exponent = data[3] > 127 ? data[3] - 256 : data[3];
          final precision = pow(2, exponent).toDouble();
          if (rootDelay < 0 ||
              rootDelay > 10 ||
              dispersion > 10 ||
              precision > 1) {
            throw const TrueTimeException(
              'invalidNtp',
              'Excessive server uncertainty',
            );
          }
          final uncertainty =
              Duration(
                microseconds:
                    ((rootDelay / 2 + dispersion + precision) * 1000000).ceil(),
              ) +
              rtt ~/ 2;
          result.complete(
            TimeSample(
              utc: receive.add(transmit.difference(receive) ~/ 2),
              at: ClockSnapshot(
                start.elapsed + rtt ~/ 2,
                start.sessionId,
                uncertainty: start.uncertainty > end.uncertainty
                    ? start.uncertainty
                    : end.uncertainty,
              ),
              uncertainty: uncertainty,
              endpointIdentity: 'udp:${address.address}:$port',
            ),
          );
        } catch (error, stack) {
          result.completeError(error, stack);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    try {
      if (bound.send(bytes, address, port) != bytes.length) {
        throw const TrueTimeException('sendFailed', 'Request not sent');
      }
      return await result.future;
    } finally {
      await subscription.cancel();
    }
  }

  try {
    return await signal.race(query());
  } finally {
    expired = true;
    timer.cancel();
    detachParent?.call();
    detachCleanup();
    if (pending != null && !pending!.isCompleted) {
      pending!.completeError(TimeoutException('NTP query expired'));
    }
    socket?.close();
  }
}

/// Unfold eras in a fixed 2020–2100 support window, without device wall time.
DateTime decodeNtpTimestamp(Uint8List data, int offset) {
  final view = ByteData.sublistView(data);
  final seconds = view.getUint32(offset), fraction = view.getUint32(offset + 4);
  if (seconds == 0 && fraction == 0) {
    throw const TrueTimeException('invalidNtp', 'Zero timestamp');
  }
  for (var era = 0; era <= 1; era++) {
    final micros =
        ((seconds + era * 4294967296) - 2208988800) * 1000000 +
        (fraction * 1000000 ~/ 4294967296);
    final utc = DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
    if (utc.year >= 2020 && utc.year <= 2100) return utc;
  }
  throw const TrueTimeException(
    'invalidNtp',
    'Timestamp outside 2020–2100 window',
  );
}
