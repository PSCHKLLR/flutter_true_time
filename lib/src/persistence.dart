import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'clock.dart';
import 'provider_group.dart';

/// Identifies a boot session within an installation and monotonic clock domain.
class BootEpoch {
  /// Creates a boot identity using values supplied by an epoch provider.
  const BootEpoch({
    required this.id,
    required this.installationScope,
    required this.clockDomain,
  });

  /// The identifier for this boot session.
  final String id;

  /// The application installation or storage scope that owns the epoch.
  final String installationScope;

  /// The clock domain in which elapsed times can be compared.
  final String clockDomain;

  /// Whether all three identity fields are present.
  bool get isValid =>
      id.isNotEmpty && installationScope.isNotEmpty && clockDomain.isNotEmpty;

  /// Encodes the identity as a map for persistence.
  Map<String, Object?> toMap() => {
    'id': id,
    'scope': installationScope,
    'domain': clockDomain,
  };

  /// Decodes the string fields written by [toMap].
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

/// Supplies boot identities for clocks that support restart validation.
abstract interface class BootEpochProvider {
  /// Returns the identity for [clock], or null if continuity cannot be proven.
  Future<BootEpoch?> currentEpoch(ClockCapabilities clock);
}

/// An epoch provider that makes no continuity claim across process restarts.
class UnknownBootEpochProvider implements BootEpochProvider {
  /// Creates a provider that returns null for every clock domain.
  const UnknownBootEpochProvider();
  @override
  Future<BootEpoch?> currentEpoch(ClockCapabilities clock) async => null;
}

/// Enables secure anchor storage under an application-specific namespace.
class PersistenceConfig {
  /// Creates a configuration with a [namespace] of 3–128 characters.
  ///
  /// Use ASCII letters, digits, underscores, hyphens, or periods.
  PersistenceConfig({required this.namespace}) {
    if (!RegExp(r'^[a-zA-Z0-9_.-]{3,128}$').hasMatch(namespace)) {
      throw ArgumentError(
        'Use a unique application namespace (3–128 safe characters)',
      );
    }
  }

  /// The storage namespace used to isolate this application's anchor.
  final String namespace;
  @override
  bool operator ==(Object other) =>
      other is PersistenceConfig && namespace == other.namespace;
  @override
  int get hashCode => namespace.hashCode;
}

/// Reads and writes the serialized record for one trusted time anchor.
abstract interface class AnchorStore {
  /// Returns the saved record, or null when the store is empty.
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

/// A version-2 persisted UTC anchor and the evidence needed to check a restore.
///
/// A decoded record still needs to pass the engine's continuity, policy,
/// freshness, and uncertainty checks before it can be used.
class AnchorRecord {
  /// Creates a record that associates [utc] with [monotonic].
  ///
  /// Supply a UTC timestamp and durations from the same clock domain.
  /// The constructor copies [sourceIds] and [providerGroups] into immutable lists.
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

  /// The UTC timestamp at the anchor.
  final DateTime utc;

  /// The elapsed time on the monotonic clock at the anchor.
  final Duration monotonic;

  /// The estimated uncertainty at the anchor before offline drift is added.
  final Duration uncertainty;

  /// The monotonic clock domain in which [monotonic] was measured.
  final String clockDomain;

  /// The fingerprint of the sources and time policy used to accept the anchor.
  final String policyFingerprint;

  /// The positive sequence number assigned to this anchor by the engine.
  final int sequence;

  /// Identifiers of the sources that contributed to the accepted anchor.
  final List<String> sourceIds;

  /// Distinct provider groups represented by the contributing sources.
  final List<String> providerGroups;

  /// The saved boot and installation identity, if the provider supplied one.
  final BootEpoch? epoch;

  /// Encodes a version-2 record with UTC and durations stored in microseconds.
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

  /// Decodes the version-2 format produced by [toMap].
  ///
  /// Rejects an unsupported schema, invalid anchor values, and an epoch from
  /// a different clock domain. The engine checks current continuity on restore.
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

/// Hashes the source configuration keys and policy values for restore checks.
///
/// Source key order is ignored. Policy values must be JSON encodable and
/// retain their order in the fingerprint.
String trustPolicyFingerprint(List<String> sourceKeys, List<Object?> policy) {
  final sorted = [...sourceKeys]..sort();
  return sha256.convert(utf8.encode(jsonEncode([sorted, policy]))).toString();
}
