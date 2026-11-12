import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clerk_auth/clerk_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/prefs/desktop_prefs_store.dart';

/// File name for the macOS session, next to `accounts.json`.
const String kSessionFileName = 'session.json';

/// macOS keeps the session in Application Support. Other platforms use
/// Credential Manager. Launch on macOS does not open the login Keychain.
SecureKeyValueStore defaultSecureStore() {
  if (Platform.isMacOS) return FileSecureKeyValueStore();
  return FlutterSecureKeyValueStore();
}

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

/// True when the OS secure-store prompt was dismissed (macOS Keychain -128).
bool isSecureStoreUserCanceled(Object error) {
  if (error is! PlatformException) return false;
  if (error.code == '-128') return true;
  final message = error.message ?? '';
  return message.contains('User canceled') ||
      message.contains('User cancelled');
}

/// True for Keychain errSecMissingEntitlement (-34018).
///
/// The macOS plugin reports it as
/// `PlatformException(Unexpected security result code, Code: -34018, ...)`,
/// so the status is in the message and details, not [PlatformException.code].
bool isSecureStoreMissingEntitlement(Object error) {
  if (error is! PlatformException) return false;
  if (error.code == '-34018') return true;
  final details = error.details;
  if (details == -34018 || details == '-34018') return true;
  final message = error.message ?? '';
  return message.contains('-34018') ||
      message.contains('required entitlement is not present');
}

/// Windows (and any non-macOS) store → Credential Manager via [FlutterSecureStorage].
///
/// macOS does not use this. Ad-hoc signed builds cannot read the login
/// Keychain without a password prompt, so they use [FileSecureKeyValueStore].
class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  FlutterSecureKeyValueStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(
                // Prefer a TagKin-specific service name (maps to kSecAttrService)
                // so Keychain Access doesn't pile up generic
                // "flutter_secure_storage_service" rows shared with other apps.
                accountName: 'tagkin.desktop.secure',
                accessibility: KeychainAccessibility.first_unlock,
              ),
              // Login Keychain. The app-private Keychain needs
              // keychain-access-groups, and that entitlement requires an
              // Apple development certificate. Debug and Release here are
              // ad-hoc signed (CODE_SIGN_IDENTITY = "-"), so that entitlement
              // fails the build. The login Keychain can ask for the Mac
              // password when a new build reads an older item.
              mOptions: MacOsOptions(
                accountName: 'tagkin.desktop.secure',
                accessibility: KeychainAccessibility.first_unlock,
                usesDataProtectionKeychain: false,
              ),
              wOptions: WindowsOptions(),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<void> write({required String key, required String? value}) async {
    try {
      await _storage.write(key: key, value: value);
    } on PlatformException catch (e) {
      if (isSecureStoreUserCanceled(e)) return;
      rethrow;
    }
  }

  @override
  Future<String?> read({required String key}) async {
    try {
      return await _storage.read(key: key);
    } on PlatformException catch (e) {
      if (isSecureStoreUserCanceled(e)) return null;
      rethrow;
    }
  }

  @override
  Future<void> delete({required String key}) async {
    try {
      await _storage.delete(key: key);
    } on PlatformException catch (e) {
      if (isSecureStoreUserCanceled(e)) return;
      // The plugin also queries the iCloud keychain. On this sandboxed Mac
      // that half returns -34018. When the login-keychain entry is already
      // gone, the plugin reports that error instead of "not found".
      if (isSecureStoreMissingEntitlement(e)) {
        try {
          final stillThere = await _storage.read(key: key);
          if (stillThere == null) return;
        } on PlatformException {
          // A failed read is not proof the entry is gone.
        }
      }
      rethrow;
    }
  }
}

/// macOS session file under Application Support (`session.json`).
///
/// Directory mode 0700, file mode 0600. Writes are serialized and replaced
/// by rename so two overlapping updates cannot drop a key. A missing, empty,
/// or unreadable file is an empty store and does not throw.
class FileSecureKeyValueStore implements SecureKeyValueStore {
  FileSecureKeyValueStore({Directory? supportDir, String? fileName})
      : _supportDirOverride = supportDir,
        _fileName = fileName ?? kSessionFileName;

  final Directory? _supportDirOverride;
  final String _fileName;
  Future<void> _tail = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<File> _file({required bool restrict}) async {
    final dir = await tagkinAppSupportDir(override: _supportDirOverride);
    if (restrict) await _chmod(dir.path, '700');
    return File(p.join(dir.path, _fileName));
  }

  /// Missing, empty, and unreadable files are an empty map.
  Future<Map<String, String>> _load() async {
    try {
      final file = await _file(restrict: false);
      if (!file.existsSync()) return <String, String>{};
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return <String, String>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      final out = <String, String>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is String) out[entry.key.toString()] = value;
      }
      return out;
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _store(Map<String, String> map) async {
    final file = await _file(restrict: true);
    if (map.isEmpty) {
      if (file.existsSync()) await file.delete();
      return;
    }
    final tmp = File('${file.path}.$pid.tmp');
    try {
      await tmp.writeAsString(jsonEncode(map), flush: true);
      await _chmod(tmp.path, '600');
      await tmp.rename(file.path);
      await _chmod(file.path, '600');
    } catch (_) {
      if (tmp.existsSync()) await tmp.delete();
      rethrow;
    }
  }

  @override
  Future<void> write({required String key, required String? value}) {
    return _serialized(() async {
      final map = await _load();
      if (value == null) {
        map.remove(key);
      } else {
        map[key] = value;
      }
      await _store(map);
    });
  }

  @override
  Future<String?> read({required String key}) {
    return _serialized(() async {
      final map = await _load();
      return map[key];
    });
  }

  @override
  Future<void> delete({required String key}) {
    return write(key: key, value: null);
  }
}

Future<void> _chmod(String path, String mode) async {
  if (Platform.isWindows) return;
  final result = await Process.run('chmod', [mode, path]);
  if (result.exitCode != 0) {
    throw StateError('chmod $mode failed: ${result.stderr}');
  }
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

/// [Persistor] backed by a [SecureKeyValueStore].
///
/// Windows keeps the token in Credential Manager. macOS keeps it in
/// Application Support `session.json` (mode 0600) so launch does not prompt
/// for the login Keychain. A process running as the same user can read that
/// file. Tokens are not written to prefs or logs.
class SecureStoragePersistor implements Persistor {
  SecureStoragePersistor({SecureKeyValueStore? store})
      : _store = store ?? defaultSecureStore();

  final SecureKeyValueStore _store;
  final Set<String> _knownKeys = <String>{};

  /// Test/inspection access to the underlying store.
  SecureKeyValueStore get store => _store;

  String _prefixed(String key) => '$kSecurePersistorPrefix$key';

  @override
  Future<void> initialize() async {
    String? index;
    try {
      index = await _store.read(key: kSecurePersistorIndexKey);
    } catch (e) {
      if (isSecureStoreUserCanceled(e)) return;
      rethrow;
    }
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
    String? raw;
    try {
      raw = await _store.read(key: _prefixed(key));
    } catch (e) {
      if (isSecureStoreUserCanceled(e)) return null;
      rethrow;
    }
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
    try {
      await _store.write(key: _prefixed(key), value: encoded);
    } catch (e) {
      if (isSecureStoreUserCanceled(e)) return;
      rethrow;
    }
    if (_knownKeys.add(key)) {
      await _persistIndex();
    }
  }

  @override
  FutureOr<void> delete(String key) async {
    try {
      await _store.delete(key: _prefixed(key));
    } catch (e) {
      if (isSecureStoreUserCanceled(e)) return;
      rethrow;
    }
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
