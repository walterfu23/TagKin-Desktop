import 'package:flutter/material.dart';

/// Deep-link Clerk must allowlist for macOS Google (and other OAuth) return.
/// Operator-only — never shown in the signed-out UI.
const String kTagkinOauthCallbackUri = 'tagkindesktop://oauth/callback';

/// How long to wait for Safari Allow / Always Allow after the browser opens.
const Duration kMacOsOauthReturnTimeout = Duration(seconds: 60);

/// Shown on the signed-out screen while the system browser owns Google SSO.
class MacOsOauthReturnHint extends StatelessWidget {
  const MacOsOauthReturnHint({
    super.key,
    this.timedOut = false,
    this.repeatMiss = false,
    this.onRetry,
  });

  final bool timedOut;
  final bool repeatMiss;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (timedOut) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            repeatMiss
                ? 'Sign-in didn’t finish. Quit TagKin and open it again, '
                    'then sign in.'
                : 'Sign-in didn’t finish.',
            key: const Key('oauth-browser-timeout'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.error,
                ),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('oauth-browser-retry'),
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ],
      );
    }
    return Text(
      'Finish in the browser. If macOS asks, choose Allow.',
      key: const Key('oauth-browser-wait'),
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}
