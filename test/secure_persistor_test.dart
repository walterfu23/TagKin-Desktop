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
  });
}
