import 'package:intl/intl.dart';
import 'package:tagkin_desktop/contract/contract.dart';

final NumberFormat _creditsFormat = NumberFormat.decimalPattern('en_US');

/// Display-only sticker from server pack fields. Does not compute debt or net.
String packSticker({required int priceUsdCents, required int credits}) {
  final dollars = priceUsdCents ~/ 100;
  return '\$$dollars — ${_creditsFormat.format(credits)} credits';
}

String formatCreditCount(int credits) => _creditsFormat.format(credits);

String creditDebtDisclosure({
  required int debtCreditsToClear,
  required int netCredits,
}) {
  if (debtCreditsToClear <= 0) {
    return '${formatCreditCount(netCredits)} credits will become remaining.';
  }
  return '${formatCreditCount(debtCreditsToClear)} credits will clear refund debt; '
      '${formatCreditCount(netCredits)} will become remaining.';
}

String packDebtDisclosure(CreditPackOffer offer) => creditDebtDisclosure(
      debtCreditsToClear: offer.debtCreditsToClear,
      netCredits: offer.netCredits,
    );

String redeemDebtDisclosure(RedeemPreview preview) => creditDebtDisclosure(
      debtCreditsToClear: preview.debtCreditsToClear,
      netCredits: preview.netCredits,
    );
