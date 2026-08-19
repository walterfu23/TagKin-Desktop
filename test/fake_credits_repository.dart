import 'package:tagkin_desktop/api/credits_repository.dart';
import 'package:tagkin_desktop/contract/contract.dart';

class FakeCreditsRepository implements CreditsRepository {
  FakeCreditsRepository({
    List<CreditPackOffer>? packs,
    this.purchase,
    this.trial,
    this.verification,
    this.grant,
    this.createError,
    this.claimError,
  }) : packs = packs ??
            [
              const CreditPackOffer(
                packId: 'pack20',
                priceUsdCents: 2000,
                credits: 2000,
                debtCreditsToClear: 0,
                netCredits: 2000,
              ),
            ];

  List<CreditPackOffer> packs;
  CreditPurchaseView? purchase;
  TrialSummary? trial;
  TrialVerificationCreated? verification;
  TrialGrantResult? grant;
  Object? createError;
  Object? claimError;

  final launched = <String>[];
  int listPacksCount = 0;
  int getPurchaseCount = 0;

  @override
  Future<CreditPackOfferList> listPacks() async {
    listPacksCount++;
    return CreditPackOfferList(packs: packs);
  }

  @override
  Future<CreditPurchaseView> createPurchase({required String packId}) async {
    if (createError != null) throw createError!;
    purchase ??= CreditPurchaseView(
      purchaseId: 'pur_1',
      status: CreditPurchaseStatus.pending,
      packId: packId,
      priceUsdCents: 2000,
      currency: 'usd',
      credits: 2000,
      maxDebtCreditsToClear: 0,
      quotedNetCredits: 2000,
      checkoutUrl: 'https://checkout.stripe.test/cs_test_1',
      remainingCredits: 0,
    );
    return purchase!;
  }

  @override
  Future<CreditPurchaseView> getPurchase(String purchaseId) async {
    getPurchaseCount++;
    return purchase ??
        CreditPurchaseView(
          purchaseId: purchaseId,
          status: CreditPurchaseStatus.pending,
          packId: 'pack20',
          priceUsdCents: 2000,
          currency: 'usd',
          credits: 2000,
          maxDebtCreditsToClear: 0,
          quotedNetCredits: 2000,
          checkoutUrl: 'https://checkout.stripe.test/cs_test_1',
          remainingCredits: 0,
        );
  }

  @override
  Future<CreditPurchaseView> cancelPurchase(String purchaseId) async {
    purchase = CreditPurchaseView(
      purchaseId: purchaseId,
      status: CreditPurchaseStatus.expired,
      packId: 'pack20',
      priceUsdCents: 2000,
      currency: 'usd',
      credits: 2000,
      maxDebtCreditsToClear: 0,
      quotedNetCredits: 2000,
      remainingCredits: 0,
    );
    return purchase!;
  }

  @override
  Future<TrialSummary> getTrial() async {
    return trial ??
        const TrialSummary(
          status: TrialStatus.notstarted,
          eligible: true,
          publishableKey: 'pk_test_stub',
        );
  }

  @override
  Future<TrialVerificationCreated> startTrialVerification() async {
    return verification ??
        const TrialVerificationCreated(
          verificationId: 'ver_1',
          intentKind: TrialIntentKind.setupintent,
          cardSetupUrl: 'https://checkout.stripe.test/cs_setup',
          publishableKey: 'pk_test_stub',
        );
  }

  @override
  Future<TrialGrantResult> claimTrialVerification(String verificationId) async {
    if (claimError != null) throw claimError!;
    return grant ??
        const TrialGrantResult(
          status: 'granted',
          creditsApplied: 1000,
          remainingCredits: 1000,
        );
  }
}
