import 'dart:async';
import 'dart:convert';

import 'package:clerk_auth/clerk_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Key prefix so Clerk session data is namespaced in the OS secure store.
const String kSecurePersistorPrefix = 'tagkin.clerk.';

/// Index key listing every namespaced entry we wrote (so sign-out can wipe all).
const String kSecurePersistorIndexKey = '${kSecurePersistorPrefix}_keys';

/// Minimal key/value surface used by [SecureStoragePersistor].
abstract class SecureKeyValueStore {
  Future<void> write({required String key, required String? value});
  Future<String?> read({required String key});
  Future<void> delete({required String key});
}

/// Production store → OS Keychain / Credential Manager via [FlutterSecureStorage].
class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  FlutterSecureKeyValueStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
              mOptions: MacOsOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
              wOptions: WindowsOptions(),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<void> write({required String key, required String? value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

/// In-memory store for unit tests (never hits the OS secure store).
class MemorySecureKeyValueStore implements SecureKeyValueStore {
  final Map<String, String> entries = <String, String>{};

  @override
  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      entries.remove(key);
    } else {
      entries[key] = value;
    }
  }

  @override
  Future<String?> read({required String key}) async => entries[key];

  @override
  Future<void> delete({required String key}) async {
    entries.remove(key);
  }
}

/// [Persistor] backed by a [SecureKeyValueStore] (Keychain / Credential Manager).
///
/// Tokens and Clerk client state never land in plaintext prefs or a cache file
/// (D1 regression + R8).
class SecureStoragePersistor implements Persistor {
  SecureStoragePersistor({SecureKeyValueStore? store})
      : _store = store ?? FlutterSecureKeyValueStore();

  final SecureKeyValueStore _store;
  final Set<String> _knownKeys = <String>{};

  /// Test/inspection access to the underlying store.
  SecureKeyValueStore get store => _store;

  String _prefixed(String key) => '$kSecurePersistorPrefix$key';

  @override
  Future<void> initialize() async {
    final index = await _store.read(key: kSecurePersistorIndexKey);
    if (index == null || index.isEmpty) return;
    try {
      final decoded = jsonDecode(index);
      if (decoded is List) {
        for (final e in decoded) {
          if (e is String) _knownKeys.add(e);
        }
      }
    } on FormatException {
      // Corrupt index — start fresh; individual keys may still be readable.
    }
  }

  @override
  void terminate() {}

  @override
  FutureOr<T?> read<T>(String key) async {
    final raw = await _store.read(key: _prefixed(key));
    if (raw == null) return null;
    if (T == String) return raw as T;
    try {
      final decoded = jsonDecode(raw);
      return decoded as T?;
    } on FormatException {
      return null;
    }
  }

  @override
  FutureOr<void> write<T>(String key, T value) async {
    final encoded = value is String ? value : jsonEncode(value);
    await _store.write(key: _prefixed(key), value: encoded);
    if (_knownKeys.add(key)) {
      await _persistIndex();
    }
  }

  @override
  FutureOr<void> delete(String key) async {
    await _store.delete(key: _prefixed(key));
    if (_knownKeys.remove(key)) {
      await _persistIndex();
    }
  }

  /// Wipe every namespaced Clerk key (defense-in-depth after Clerk sign-out).
  Future<void> clearAll() async {
    for (final key in List<String>.from(_knownKeys)) {
      await _store.delete(key: _prefixed(key));
    }
    _knownKeys.clear();
    await _store.delete(key: kSecurePersistorIndexKey);
  }

  Future<void> _persistIndex() async {
    await _store.write(
      key: kSecurePersistorIndexKey,
      value: jsonEncode(_knownKeys.toList(growable: false)),
    );
  }
}
