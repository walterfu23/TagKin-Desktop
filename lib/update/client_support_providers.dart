import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/update/client_identity.dart';

/// Installed desktop identity. Tests keep [ClientIdentity.testFallback];
/// `main()` overrides with [ClientIdentity.fromPlatform].
final clientIdentityProvider = Provider<ClientIdentity>(
  (ref) => ClientIdentity.testFallback,
);

/// Latest `/me` `clientSupport` (null when the API omitted it).
final clientSupportProvider = StateProvider<ClientSupport?>((ref) => null);

/// Session-only dismiss of the "newer version" banner.
final clientWarnDismissedProvider = StateProvider<bool>((ref) => false);

/// Mid-session 426 or a Check-for-updates result of `blocked`.
final forceUpdateRequiredProvider = StateProvider<bool>((ref) => false);
