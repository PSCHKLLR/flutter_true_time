import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'persistence.dart';

/// One encrypted complete-record value, isolated by the host's namespace.
/// Reuses the backend object so the engine's serial writer survives facade reset.
class SecureAnchorStore implements AnchorStore {
  SecureAnchorStore._(this.config)
    : _storage = FlutterSecureStorage(
        aOptions: AndroidOptions(
          storageNamespace: '${config.namespace}.true_time',
        ),
        iOptions: IOSOptions(
          accountName: config.namespace,
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
        mOptions: MacOsOptions(
          accountName: config.namespace,
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );
  static final Map<String, SecureAnchorStore> _stores = {};
  factory SecureAnchorStore.open(PersistenceConfig config) =>
      _stores.putIfAbsent(config.namespace, () => SecureAnchorStore._(config));
  final PersistenceConfig config;
  final FlutterSecureStorage _storage;
  String get _key => '${config.namespace}.flutter_true_time.anchor.v2';
  @override
  Future<Map<String, Object?>?> load() async {
    final encoded = await _storage.read(key: _key);
    return encoded == null
        ? null
        : Map<String, Object?>.from(jsonDecode(encoded) as Map);
  }

  @override
  Future<void> save(Map<String, Object?> record) =>
      _storage.write(key: _key, value: jsonEncode(record));
}
