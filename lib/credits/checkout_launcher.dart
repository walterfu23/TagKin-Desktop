import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the system browser. Injected in tests.
typedef CheckoutUrlLauncher = Future<bool> Function(Uri url);

Future<bool> launchCheckoutUrl(Uri url) {
  return launchUrl(url, mode: LaunchMode.externalApplication);
}
