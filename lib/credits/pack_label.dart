import 'package:intl/intl.dart';
import 'package:tagkin_desktop/contract/contract.dart';

final NumberFormat _creditsFormat = NumberFormat.decimalPattern('en_US');

/// Display-only sticker from server pack fields. Does not compute debt or net.
String packSticker({required int priceUsdCents, required int credits}) {
  final dollars = priceUsdCents ~/ 100;
  return '\$$dollars — ${_creditsFormat.format(credits)} credits';
}

String formatCreditCount(int credits) => _creditsFormat.format(credits);

String packDebtDisclosure(CreditPackOffer offer) {
  if (offer.debtCreditsToClear <= 0) {
    return '${formatCreditCount(offer.netCredits)} credits will become remaining.';
  }
  return '${formatCreditCount(offer.debtCreditsToClear)} credits will clear refund debt; '
      '${formatCreditCount(offer.netCredits)} will become remaining.';
}
