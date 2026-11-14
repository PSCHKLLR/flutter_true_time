import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_true_time/flutter_true_time.dart';

void main() => runApp(const MaterialApp(home: ClockDemo()));

class ClockDemo extends StatefulWidget {
  const ClockDemo({
    super.key,
    this.sources,
    this.clock,
    this.enablePersistence = true,
  });
  final bool enablePersistence;
  final List<TimeSource>? sources;
  final MonotonicClock? clock;
  @override
  State<ClockDemo> createState() => _ClockDemoState();
}

class _ClockDemoState extends State<ClockDemo> {
  Timer? _ticker;
  bool _started = false, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  List<TimeSource>? _sources() {
    if (widget.sources != null || !kIsWeb) return widget.sources;
    const endpointA = String.fromEnvironment('TRUE_TIME_HTTPS_A');
    const endpointB = String.fromEnvironment('TRUE_TIME_HTTPS_B');
    const providerA = String.fromEnvironment('TRUE_TIME_PROVIDER_A');
    const providerB = String.fromEnvironment('TRUE_TIME_PROVIDER_B');
    if ([endpointA, endpointB, providerA, providerB].any((s) => s.isEmpty)) {
      throw const TrueTimeException(
        'sourcesRequired',
        'Configure two independent HTTPS endpoints and provider names with TRUE_TIME_HTTPS_A/B and TRUE_TIME_PROVIDER_A/B dart-defines.',
      );
    }
    return [
      HttpsDateSource(Uri.parse(endpointA), providerGroup: providerA),
      HttpsDateSource(Uri.parse(endpointB), providerGroup: providerB),
    ];
  }

  Future<void> _start() async {
    try {
      await TrueTime.initialize(
        sources: _sources(),
        clock: widget.clock,
        persistence: widget.enablePersistence
            ? PersistenceConfig(
                namespace: 'dev.pschkllr.flutter_true_time_example',
              )
            : null,
      );
      if (!mounted) return;
      setState(() => _started = true);
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      await TrueTime.waitUntilReady();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _sync() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final outcome = await TrueTime.forceResync();
      if (!outcome.success && mounted) {
        setState(() => _error = outcome.error.toString());
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(TrueTime.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reading = _started ? TrueTime.estimate() : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Trusted UTC clock')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              reading?.utc.toIso8601String() ?? 'UTC time unavailable',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Text('Status: ${reading?.availability.name ?? 'unavailable'}'),
            if (reading != null) ...[
              Text(
                'Estimated uncertainty: ±${reading.uncertainty.inMilliseconds} ms',
              ),
              Text('Anchor age: ${reading.anchorAge.inSeconds} seconds'),
              Text(
                'Independent provider labels: ${reading.providerGroupCount}',
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Network-derived estimate. Not cryptographically authenticated.',
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_error!),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _started && !_busy ? _sync : null,
              child: Text(_busy ? 'Synchronizing…' : 'Synchronize'),
            ),
          ],
        ),
      ),
    );
  }
}
