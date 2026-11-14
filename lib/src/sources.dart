import 'dart:convert';
import 'cancellation.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'clock.dart';
import 'models.dart';
import 'ntp_stub.dart' if (dart.library.io) 'ntp_io.dart' as ntp;

class TimeSample {
  TimeSample({
    required this.utc,
    required this.at,
    required this.uncertainty,
    this.endpointIdentity,
  });
  final String? endpointIdentity;
  final DateTime utc;
  final ClockSnapshot at;
  final Duration uncertainty;
}

abstract interface class TimeSource {
  String get id;

  /// Canonical endpoint identity. Aliases must not inflate quorum.
  String get endpoint;

  /// Operator identity. Empty/unknown groups cannot satisfy diversity.
  String get providerGroup;

  /// Stable identity of immutable source configuration (including trust options).
  String get configurationKey;
  Future<TimeSample> query(
    MonotonicClock clock,
    Duration timeout, {
    CancellationSignal? cancellation,
  });
}

class NtpSource implements TimeSource {
  const NtpSource(this.host, {required this.providerGroup, this.port = 123});
  final String host;
  final int port;
  @override
  final String providerGroup;
  @override
  String get id => 'ntp:$host:$port';
  @override
  String get endpoint => id.toLowerCase();
  @override
  String get configurationKey =>
      jsonEncode(['ntp', host.toLowerCase(), port, providerGroup.trim()]);
  @override
  Future<TimeSample> query(
    MonotonicClock clock,
    Duration timeout, {
    CancellationSignal? cancellation,
  }) => ntp.queryNtp(host, port, clock, timeout, cancellation: cancellation);
}

/// Coarse HTTPS Date time. Requires HEAD, no-store, and CORS-exposed headers.
class HttpsDateSource implements TimeSource {
  HttpsDateSource(
    this.url, {
    required this.providerGroup,
    http.Client Function()? clientFactory,
    String? configurationIdentity,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _configurationIdentity =
           configurationIdentity ??
           (clientFactory == null
               ? 'default-client'
               : identityHashCode(clientFactory).toString()) {
    if (url.scheme != 'https' ||
        url.userInfo.isNotEmpty ||
        !url.hasAuthority ||
        url.fragment.isNotEmpty) {
      throw ArgumentError('Require HTTPS without credentials or fragments');
    }
  }
  final Uri url;
  final http.Client Function() _clientFactory;
  final String _configurationIdentity;
  @override
  final String providerGroup;
  @override
  String get id => 'https:$url';
  @override
  String get endpoint => 'https://${url.host.toLowerCase()}:${url.port}';
  @override
  String get configurationKey => jsonEncode([
    'https-date',
    url.toString(),
    providerGroup.trim(),
    _configurationIdentity,
  ]);
  @override
  Future<TimeSample> query(
    MonotonicClock clock,
    Duration timeout, {
    CancellationSignal? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final client = _clientFactory();
    final detach = cancellation?.onCancel(client.close);
    try {
      final start = clock.snapshot();
      final request = http.Request('HEAD', url)..followRedirects = false;
      final operation = client.send(request);
      final response =
          await (cancellation == null
                  ? operation
                  : cancellation.race(operation))
              .timeout(timeout);
      cancellation?.throwIfCancelled();
      final end = clock.snapshot();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const TrueTimeException(
          'httpStatus',
          'HTTPS source did not succeed',
        );
      }
      final age = response.headers['age'];
      final cache = response.headers['cache-control']?.toLowerCase() ?? '';
      if (!cache.split(',').map((s) => s.trim()).contains('no-store') ||
          (age != null && int.tryParse(age) != 0)) {
        throw const TrueTimeException(
          'cachedResponse',
          'Require no-store and absent/zero Age',
        );
      }
      final utc = parseHttpDate(response.headers['date']);
      if (start.sessionId != end.sessionId || end.elapsed < start.elapsed) {
        throw const TrueTimeException(
          'continuityLost',
          'Clock changed during request',
        );
      }
      final rtt = end.elapsed - start.elapsed;
      return TimeSample(
        utc: utc,
        at: ClockSnapshot(
          start.elapsed + rtt ~/ 2,
          start.sessionId,
          uncertainty: start.uncertainty > end.uncertainty
              ? start.uncertainty
              : end.uncertainty,
        ),
        uncertainty: const Duration(seconds: 1) + rtt ~/ 2,
      );
    } finally {
      detach?.call();
      client.close();
    }
  }
}

DateTime parseHttpDate(String? value) {
  final parts = (value ?? '').split(' ');
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  const days = ['Mon,', 'Tue,', 'Wed,', 'Thu,', 'Fri,', 'Sat,', 'Sun,'];
  if (parts.length != 6 || !days.contains(parts[0]) || parts[5] != 'GMT') {
    throw const TrueTimeException(
      'invalidDate',
      'Missing or invalid HTTP Date',
    );
  }
  final time = parts[4].split(':');
  final month = months.indexOf(parts[2]) + 1;
  final day = int.tryParse(parts[1]), year = int.tryParse(parts[3]);
  final hour = time.length == 3 ? int.tryParse(time[0]) : null;
  final minute = time.length == 3 ? int.tryParse(time[1]) : null;
  final second = time.length == 3 ? int.tryParse(time[2]) : null;
  if (month == 0 ||
      day == null ||
      year == null ||
      hour == null ||
      minute == null ||
      second == null ||
      year < 2020 ||
      year > 2100 ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59 ||
      second < 0 ||
      second > 59) {
    throw const TrueTimeException(
      'invalidDate',
      'Invalid HTTP calendar fields',
    );
  }
  final date = DateTime.utc(year, month, day, hour, minute, second);
  if (date.day != day || days[date.weekday - 1] != parts[0]) {
    throw const TrueTimeException('invalidDate', 'Invalid HTTP calendar date');
  }
  return date;
}
