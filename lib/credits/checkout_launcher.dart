import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the system browser. Injected in tests.
typedef CheckoutUrlLauncher = Future<bool> Function(Uri url);

/// Host the API stub uses when Stripe test keys are not set. It is not a real server.
const stubCheckoutHost = 'checkout.stripe.test';

const stubCheckoutMessage =
    'Stripe test keys are not set, so the card form cannot open.';

bool isStubCheckoutUrl(Uri url) => url.host == stubCheckoutHost;

Future<bool> launchCheckoutUrl(Uri url) {
  return launchUrl(url, mode: LaunchMode.externalApplication);
}
