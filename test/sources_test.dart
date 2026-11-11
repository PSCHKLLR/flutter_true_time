import 'dart:async';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_true_time/core.dart';
import 'helpers.dart';

void main() {
  final url = Uri.parse('https://clock.example/time');
  test('HTTPS Date produces a UTC sample with coarse uncertainty', () async {
    final source = HttpsDateSource(
      url,
      providerGroup: 'example',
      clientFactory: () => MockClient((request) async {
        expect(request.method, 'HEAD');
        expect(request.followRedirects, isFalse);
        return http.Response(
          '',
          200,
          headers: {
            'date': 'Wed, 11 Nov 2026 00:00:00 GMT',
            'cache-control': 'no-store',
            'age': '0',
          },
        );
      }),
    );
    final sample = await source.query(FakeClock(), const Duration(seconds: 1));
    expect(sample.utc, DateTime.utc(2026, 11, 11));
    expect(sample.uncertainty, const Duration(seconds: 1));
  });
  for (final headers in <Map<String, String>>[
    {'date': 'Wed, 11 Nov 2026 00:00:00 GMT'},
    {
      'date': 'Wed, 11 Nov 2026 00:00:00 GMT',
      'cache-control': 'no-store',
      'age': '42',
    },
    {'cache-control': 'no-store'},
    {'date': 'Wed, 31 Feb 2026 00:00:00 GMT', 'cache-control': 'no-store'},
  ]) {
    test('HTTPS excludes absent or cached time evidence $headers', () async {
      final source = HttpsDateSource(
        url,
        providerGroup: 'example',
        clientFactory: () =>
            MockClient((_) async => http.Response('', 200, headers: headers)),
      );
      await expectLater(
        source.query(FakeClock(), const Duration(seconds: 1)),
        throwsA(isA<TrustedTimeException>()),
      );
    });
  }
  test('HTTPS redirects and insecure URLs are rejected', () async {
    expect(
      () =>
          HttpsDateSource(Uri.parse('http://example.com'), providerGroup: 'x'),
      throwsArgumentError,
    );
    final source = HttpsDateSource(
      url,
      providerGroup: 'x',
      clientFactory: () => MockClient((_) async => http.Response('', 302)),
    );
    await expectLater(
      source.query(FakeClock(), const Duration(seconds: 1)),
      throwsA(isA<TrustedTimeException>()),
    );
  });
  test('HTTP Date rejects weekday mismatch and normalized overflow', () {
    expect(
      () => parseHttpDate('Mon, 11 Nov 2026 00:00:00 GMT'),
      throwsA(isA<TrustedTimeException>()),
    );
    expect(
      () => parseHttpDate('Wed, 11 Nov 2026 24:00:00 GMT'),
      throwsA(isA<TrustedTimeException>()),
    );
  });

  test('HTTPS cancellation closes the owned client immediately', () async {
    final client = PendingClient();
    final signal = CancellationSignal();
    final source = HttpsDateSource(
      url,
      providerGroup: 'example',
      clientFactory: () => client,
    );
    final result = source.query(
      FakeClock(),
      const Duration(seconds: 3),
      cancellation: signal,
    );
    final expected = expectLater(result, throwsA(isA<Exception>()));
    signal.cancel('test');
    await expected;
    expect(client.closed, isTrue);
  });
}

class PendingClient extends http.BaseClient {
  final pending = Completer<http.StreamedResponse>();
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      pending.future;
  @override
  void close() {
    closed = true;
    if (!pending.isCompleted) {
      pending.completeError(http.ClientException('closed'));
    }
  }
}
