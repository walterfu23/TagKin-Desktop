import 'dart:async';

import 'package:tagkin_desktop/auth/secure_persistor.dart';

const String kActiveAuthProviderKey = 'tagkin.auth.activeProvider';
const String kFirebaseSessionKey = 'tagkin.firebase.session';

/// Clears the previous provider's local session when the global selection changes.
/// Returns true when a stored provider was replaced.
Future<bool> reconcileStoredProvider({
  required SecureKeyValueStore store,
  required String? nextProviderId,
  required Future<void> Function() clearClerk,
}) async {
  final previous = await store.read(key: kActiveAuthProviderKey);
  final changed = previous != null &&
      previous.isNotEmpty &&
      nextProviderId != null &&
      previous != nextProviderId;
  if (changed) {
    await clearClerk();
    await store.delete(key: kFirebaseSessionKey);
  }
  if (nextProviderId != null && nextProviderId.isNotEmpty) {
    await store.write(key: kActiveAuthProviderKey, value: nextProviderId);
  }
  return changed;
}
