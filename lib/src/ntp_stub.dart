import 'cancellation.dart';
import 'clock.dart';
import 'models.dart';
import 'sources.dart';

Future<TimeSample> queryNtp(
  String host,
  int port,
  MonotonicClock clock,
  Duration timeout, {
  CancellationSignal? cancellation,
}) async {
  cancellation?.throwIfCancelled();
  throw const TrueTimeException(
    'unsupported',
    'NTP unavailable; configure HTTPS sources',
  );
}
