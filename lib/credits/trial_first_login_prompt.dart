import 'package:tagkin_desktop/contract/contract.dart';

/// Whether sign-in should open the page for getting the Trial pack.
///
/// True only when the pack is on and this account has never received credits
/// (redeem, admin grant, purchase, or Trial).
class TrialFirstLoginPrompt {
  const TrialFirstLoginPrompt._();

  static bool shouldPrompt(TrialSummary summary) =>
      summary.available && summary.neverHadCredits;
}
