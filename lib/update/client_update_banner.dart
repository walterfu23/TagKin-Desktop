import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/credits/checkout_launcher.dart';
import 'package:tagkin_desktop/update/client_support_providers.dart';

/// Dismissible banner when `/me` reports `clientSupport.status = warn`.
class ClientUpdateBanner extends ConsumerWidget {
  const ClientUpdateBanner({super.key, this.launchUrl});

  final CheckoutUrlLauncher? launchUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final support = ref.watch(clientSupportProvider);
    final dismissed = ref.watch(clientWarnDismissedProvider);
    if (support == null ||
        support.status != ClientSupportStatus.warn ||
        dismissed) {
      return const SizedBox.shrink();
    }
    final latest = support.latestVersion;
    final message = latest == null
        ? 'A newer version of TagKin is available.'
        : 'A newer version of TagKin is available ($latest).';
    return Material(
      key: const Key('client-update-banner'),
      color: Colors.amber.shade100,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.system_update, color: Colors.amber.shade900),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: Colors.amber.shade900),
              ),
            ),
            if (support.downloadUrl != null)
              TextButton(
                key: const Key('client-update-banner-download'),
                onPressed: () {
                  final url = Uri.tryParse(support.downloadUrl!);
                  if (url != null) {
                    (launchUrl ?? launchCheckoutUrl)(url);
                  }
                },
                child: const Text('Download'),
              ),
            TextButton(
              key: const Key('client-update-banner-dismiss'),
              onPressed: () {
                ref.read(clientWarnDismissedProvider.notifier).state = true;
              },
              child: const Text('Dismiss'),
            ),
          ],
        ),
      ),
    );
  }
}
