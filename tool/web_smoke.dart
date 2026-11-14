// ignore_for_file: avoid_print
import 'package:flutter_true_time/core.dart';

void main() {
  final clock = createPlatformClock();
  final engine = TrueTimeEngine(
    sources: const [],
    clock: clock,
    autoRefresh: false,
  );
  print(engine.status.availability.name);
  engine.dispose();
}
