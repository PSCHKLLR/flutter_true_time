class WallClockSample {
  const WallClockSample(this.utc, this.offset, this.zone);
  final DateTime utc;
  final Duration offset;
  final String zone;
}

abstract interface class WallClockReader {
  WallClockSample read();
}

/// Used only for informational diagnostics; never to advance a UTC anchor.
class SystemWallClockReader implements WallClockReader {
  @override
  WallClockSample read() {
    final local = DateTime.now();
    return WallClockSample(
      local.toUtc(),
      local.timeZoneOffset,
      local.timeZoneName,
    );
  }
}
