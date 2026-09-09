import 'package:tagkin_desktop/api/api_client.dart';

/// User-facing copy for [ApiException] codes. Unknown codes use the server
/// `message`. Non-API errors fall back to [Object.toString].
String apiUserMessage(Object e) {
  if (e is ApiException) {
    switch (e.code) {
      case 'redeemCodeInvalid':
        return 'That code is not valid.';
      case 'redeemCodeExpired':
        return 'That code has expired.';
      case 'redeemCodeAlreadyUsed':
        return 'That code has already been used.';
      case 'redeemRateLimited':
        return 'Too many attempts. Try again later.';
      case 'trialAlreadyGranted':
        return 'This account already has Trial credits.';
      case 'trialCardBlocked':
        return 'That card cannot be used for Trial.';
      case 'trialFingerprintAlreadyUsed':
        return 'That card was already used for a Trial.';
      case 'trialVerificationPending':
        return 'Finish card verification in the browser, then return here.';
      case 'trialPackUnavailable':
        return 'Trial is not available right now.';
      case 'trialUnavailable':
        return 'Trial could not be completed.';
      case 'analyzeRateLimited':
        return 'Too many analyze requests. Try again shortly.';
      case 'purchase_failed':
        return e.message;
      default:
        return e.message;
    }
  }
  return e.toString();
}
