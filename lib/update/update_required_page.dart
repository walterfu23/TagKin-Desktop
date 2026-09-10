import 'package:flutter/material.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/credits/checkout_launcher.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

/// Full-screen block when this desktop build is below the API minimum.
class UpdateRequiredPage extends StatelessWidget {
  const UpdateRequiredPage({
    super.key,
    this.support,
    this.onSignOut,
    this.launchUrl,
  });

  final ClientSupport? support;
  final Future<void> Function()? onSignOut;
  final CheckoutUrlLauncher? launchUrl;

  @override
  Widget build(BuildContext context) {
    final min = support?.minVersion;
    final message = min == null
        ? 'This version of TagKin is no longer supported. Download the latest version to continue.'
        : 'This version of TagKin is no longer supported. Update to $min or newer to continue.';
    final url = support?.downloadUrl;
    return SelectableScope(
      child: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Update required',
                    key: const Key('update-required-title'),
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    key: const Key('update-required-message'),
                    textAlign: TextAlign.center,
                  ),
                  if (url != null) ...[
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const Key('update-required-download'),
                      onPressed: () {
                        final parsed = Uri.tryParse(url);
                        if (parsed != null) {
                          (launchUrl ?? launchCheckoutUrl)(parsed);
                        }
                      },
                      child: const Text('Download TagKin'),
                    ),
                  ],
                  if (onSignOut != null) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      key: const Key('update-required-sign-out'),
                      onPressed: () => onSignOut!(),
                      child: const Text('Sign out'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
