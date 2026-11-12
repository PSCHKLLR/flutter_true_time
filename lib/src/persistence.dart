import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'clock.dart';
import 'provider_group.dart';

class BootEpoch {
  const BootEpoch({
    required this.id,
    required this.installationScope,
    required this.clockDomain,
  });
  final String id, installationScope, clockDomain;
  bool get isValid =>
      id.isNotEmpty && installationScope.isNotEmpty && clockDomain.isNotEmpty;
  Map<String, Object?> toMap() => {
    'id': id,
    'scope': installationScope,
    'domain': clockDomain,
  };
  factory BootEpoch.fromMap(Map<String, Object?> value) => BootEpoch(
    id: value['id'] as String,
    installationScope: value['scope'] as String,
    clockDomain: value['domain'] as String,
  );
  @override
  bool operator ==(Object other) =>
      other is BootEpoch &&
      id == other.id &&
      installationScope == other.installationScope &&
      clockDomain == other.clockDomain;
  @override
  int get hashCode => Object.hash(id, installationScope, clockDomain);
}

abstract interface class BootEpochProvider {
  Future<BootEpoch?> currentEpoch(ClockCapabilities clock);
}

class UnknownBootEpochProvider implements BootEpochProvider {
  const UnknownBootEpochProvider();
  @override
  Future<BootEpoch?> currentEpoch(ClockCapabilities clock) async => null;
}

class PersistenceConfig {
  PersistenceConfig({required this.namespace}) {
    if (!RegExp(r'^[a-zA-Z0-9_.-]{3,128}$').hasMatch(namespace)) {
      throw ArgumentError(
        'Use a unique application namespace (3–128 safe characters)',
      );
    }
  }
  final String namespace;
  @override
  bool operator ==(Object other) =>
      other is PersistenceConfig && namespace == other.namespace;
  @override
  int get hashCode => namespace.hashCode;
}

abstract interface class AnchorStore {
  Future<Map<String, Object?>?> load();

  /// Implement a complete-record atomic write. Caller timeouts never cancel it.
  Future<void> save(Map<String, Object?> record);
}

/// Shares a writer queue for engines using the same store object. The queue is
/// released only when the REAL backend write settles, never by a caller timeout.
class SerializingAnchorStore implements AnchorStore {
  SerializingAnchorStore._(this.backend);
  static final Expando<SerializingAnchorStore> _shared = Expando();
  factory SerializingAnchorStore.wrap(AnchorStore backend) {
    if (backend is SerializingAnchorStore) return backend;
    return _shared[backend] ??= SerializingAnchorStore._(backend);
  }
  final AnchorStore backend;
  Future<void> _tail = Future<void>.value();
  @override
  Future<Map<String, Object?>?> load() async {
    await _tail;
    return backend.load();
  }

  @override
  Future<void> save(Map<String, Object?> record) {
    // Snapshot before queueing: callers cannot mutate delayed writes.
    final copy = Map<String, Object?>.from(
      jsonDecode(jsonEncode(record)) as Map,
    );
    final operation = _tail.then((_) => backend.save(copy));
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }
}

class AnchorRecord {
  AnchorRecord({
    required this.utc,
    required this.monotonic,
    required this.uncertainty,
    required this.clockDomain,
    required this.policyFingerprint,
    required this.sequence,
    required List<String> sourceIds,
    required List<String> providerGroups,
    this.epoch,
  }) : sourceIds = List.unmodifiable(sourceIds),
       providerGroups = List.unmodifiable(providerGroups);
  final DateTime utc;
  final Duration monotonic, uncertainty;
  final String clockDomain, policyFingerprint;
  final int sequence;
  final List<String> sourceIds, providerGroups;
  final BootEpoch? epoch;
  Map<String, Object?> toMap() => {
    'version': 2,
    'utcUs': utc.microsecondsSinceEpoch,
    'monoUs': monotonic.inMicroseconds,
    'uncertaintyUs': uncertainty.inMicroseconds,
    'clockDomain': clockDomain,
    'policy': policyFingerprint,
    'sequence': sequence,
    'sources': sourceIds,
    'groups': providerGroups,
    'epoch': epoch?.toMap(),
  };
  factory AnchorRecord.fromMap(Map<String, Object?> value) {
    if (value['version'] != 2) {
      throw const FormatException('Unsupported anchor schema');
    }
    final utc = DateTime.fromMicrosecondsSinceEpoch(
      value['utcUs'] as int,
      isUtc: true,
    );
    final mono = value['monoUs'] as int,
        uncertainty = value['uncertaintyUs'] as int,
        sequence = value['sequence'] as int;
    final ids = List<String>.from(value['sources'] as List),
        groups = List<String>.from(value['groups'] as List);
    final domain = value['clockDomain'] as String,
        policy = value['policy'] as String;
    if (utc.year < 2020 ||
        utc.year > 2100 ||
        mono < 0 ||
        uncertainty < 0 ||
        sequence < 1 ||
        domain.isEmpty ||
        policy.isEmpty ||
        ids.isEmpty ||
        ids.toSet().length != ids.length ||
        groups.isEmpty ||
        groups.toSet().length != groups.length ||
        ids.any((s) => s.trim().isEmpty) ||
        groups.any((s) => knownProviderGroup(s) != s)) {
      throw const FormatException('Invalid persisted anchor');
    }
    final epoch = value['epoch'] == null
        ? null
        : BootEpoch.fromMap(Map<String, Object?>.from(value['epoch'] as Map));
    if (epoch != null && (!epoch.isValid || epoch.clockDomain != domain)) {
      throw const FormatException('Invalid epoch');
    }
    return AnchorRecord(
      utc: utc,
      monotonic: Duration(microseconds: mono),
      uncertainty: Duration(microseconds: uncertainty),
      clockDomain: domain,
      policyFingerprint: policy,
      sequence: sequence,
      sourceIds: ids,
      providerGroups: groups,
      epoch: epoch,
    );
  }
}

String trustPolicyFingerprint(List<String> sourceKeys, List<Object?> policy) {
  final sorted = [...sourceKeys]..sort();
  return sha256.convert(utf8.encode(jsonEncode([sorted, policy]))).toString();
}
