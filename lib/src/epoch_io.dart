import 'dart:io';
import 'package:flutter/services.dart';
import 'clock.dart';
import 'persistence.dart';

BootEpochProvider createProvider(PersistenceConfig config) =>
    _PlatformEpochProvider(config);

class _PlatformEpochProvider implements BootEpochProvider {
  _PlatformEpochProvider(this.config);
  final PersistenceConfig config;
  static const channel = MethodChannel('dev.pschkllr.flutter_true_time/epoch');
  @override
  Future<BootEpoch?> currentEpoch(ClockCapabilities clock) async {
    if (!clock.supportsBootEpoch || !clock.includesSleep) return null;
    if (Platform.isAndroid && clock.domain == 'android.clock_boottime.us.v1') {
      final value = await channel.invokeMapMethod<String, Object?>(
        'getBootEpoch',
        {'namespace': config.namespace},
      );
      if (value == null) return null;
      return BootEpoch(
        id: value['bootId'] as String,
        installationScope: value['installationScope'] as String,
        clockDomain: clock.domain,
      );
    }
    if (Platform.isLinux && clock.domain == 'linux.clock_boottime.us.v1') {
      final id = (await File(
        '/proc/sys/kernel/random/boot_id',
      ).readAsString()).trim().toLowerCase();
      if (!RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      ).hasMatch(id)) {
        return null;
      }
      return BootEpoch(
        id: id,
        installationScope: config.namespace,
        clockDomain: clock.domain,
      );
    }
    // No wall-clock boot estimate, private sysctl, or undocumented Windows API.
    return null;
  }
}
