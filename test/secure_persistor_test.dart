import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/auth/secure_persistor.dart';

void main() {
  group('SecureStoragePersistor', () {
    test('stores values only in the secure key-value store', () async {
      final memory = MemorySecureKeyValueStore();
      final persistor = SecureStoragePersistor(store: memory);
      await persistor.initialize();

      await persistor.write('client', {'id': 'c1'});
      await persistor.write('session_token', 'jwt-value');

      expect(memory.entries.keys, everyElement(startsWith(kSecurePersistorPrefix)));
      expect(
        memory.entries.keys.any((k) => k.contains('SharedPreferences')),
        isFalse,
      );

      final client = await persistor.read<Map<String, dynamic>>('client');
      expect(client?['id'], 'c1');
      expect(await persistor.read<String>('session_token'), 'jwt-value');
    });

    test('clearAll empties the secure store after sign-out', () async {
      final memory = MemorySecureKeyValueStore();
      final persistor = SecureStoragePersistor(store: memory);
      await persistor.initialize();
      await persistor.write('client', {'id': 'c1'});
      await persistor.write('session_token', 'jwt-value');
      expect(memory.entries, isNotEmpty);

      await persistor.clearAll();
      expect(memory.entries, isEmpty);
      expect(await persistor.read<String>('session_token'), isNull);
    });

    test('delete removes a single key', () async {
      final memory = MemorySecureKeyValueStore();
      final persistor = SecureStoragePersistor(store: memory);
      await persistor.initialize();
      await persistor.write('a', '1');
      await persistor.write('b', '2');
      await persistor.delete('a');
      expect(await persistor.read<String>('a'), isNull);
      expect(await persistor.read<String>('b'), '2');
    });

    test('initialize survives a canceled Keychain read', () async {
      final persistor = SecureStoragePersistor(store: _CancelingKeyValueStore());
      await persistor.initialize();
      expect(await persistor.read<String>('session_token'), isNull);
    });
  });

  group('FlutterSecureKeyValueStore.delete', () {
    final missing = PlatformException(
      code: 'Unexpected security result code',
      message:
          'Code: -34018, Message: A required entitlement is not present.',
      details: -34018,
    );

    test('a missing entry that reports -34018 is already deleted', () async {
      final store = FlutterSecureKeyValueStore(
        _ScriptedSecureStorage(deleteError: missing, readValue: null),
      );
      await store.delete(key: 'tagkin.firebase.gate');
    });

    test('a -34018 delete rethrows when the entry is still stored', () async {
      final store = FlutterSecureKeyValueStore(
        _ScriptedSecureStorage(deleteError: missing, readValue: 'kept'),
      );
      await expectLater(
        store.delete(key: 'tagkin.firebase.session'),
        throwsA(missing),
      );
    });

    test('a -34018 delete rethrows when the follow-up read fails', () async {
      final store = FlutterSecureKeyValueStore(
        _ScriptedSecureStorage(
          deleteError: missing,
          readError: PlatformException(code: 'read-failed'),
        ),
      );
      await expectLater(
        store.delete(key: 'tagkin.firebase.session'),
        throwsA(missing),
      );
    });
  });

  group('isSecureStoreUserCanceled', () {
    test('detects Keychain -128 cancel', () {
      expect(
        isSecureStoreUserCanceled(
          PlatformException(
            code: '-128',
            message: 'User canceled the operation.',
          ),
        ),
        isTrue,
      );
      expect(
        isSecureStoreUserCanceled(
          PlatformException(code: 'Unexpected security result code'),
        ),
        isFalse,
      );
    });
  });
}

/// [FlutterSecureStorage] stand-in. Overrides never touch the real Keychain.
class _ScriptedSecureStorage extends FlutterSecureStorage {
  _ScriptedSecureStorage({this.deleteError, this.readValue, this.readError});

  final PlatformException? deleteError;
  final String? readValue;
  final PlatformException? readError;

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final error = deleteError;
    if (error != null) throw error;
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final error = readError;
    if (error != null) throw error;
    return readValue;
  }
}

/// Secure store that always throws Keychain user-cancel (-128).
class _CancelingKeyValueStore implements SecureKeyValueStore {
  static PlatformException get _cancel => PlatformException(
        code: '-128',
        message: 'User canceled the operation.',
      );

  @override
  Future<void> write({required String key, required String? value}) async {
    throw _cancel;
  }

  @override
  Future<String?> read({required String key}) async {
    throw _cancel;
  }

  @override
  Future<void> delete({required String key}) async {
    throw _cancel;
  }
}
