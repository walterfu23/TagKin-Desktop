import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/contract/contract.dart';

/// Typed client for owner-scoped credit pack / purchase / Trial / redeem routes (D6).
///
/// Never estimates cost or debt client-side and never sends `ownerUserId` (R9/R10).
class CreditsRepository {
  CreditsRepository(this._client);

  final ApiClient _client;

  Future<CreditPackOfferList> listPacks() async {
    final response = await _client.get('/credits/packs');
    return CreditPackOfferList.fromJson(_client.decodeMap(response, '/credits/packs'));
  }

  Future<CreditPurchaseView> createPurchase({required String packId}) async {
    final response = await _client.post(
      '/credits/purchases',
      body: CreditPurchaseCreate(packId: packId).toJson(),
    );
    return CreditPurchaseView.fromJson(
      _client.decodeMap(response, '/credits/purchases'),
    );
  }

  Future<CreditPurchaseView> getPurchase(String purchaseId) async {
    final response = await _client.get('/credits/purchases/$purchaseId');
    return CreditPurchaseView.fromJson(
      _client.decodeMap(response, '/credits/purchases'),
    );
  }

  Future<CreditPurchaseView> cancelPurchase(String purchaseId) async {
    final response = await _client.post('/credits/purchases/$purchaseId/cancel');
    return CreditPurchaseView.fromJson(
      _client.decodeMap(response, '/credits/purchases/cancel'),
    );
  }

  Future<TrialSummary> getTrial() async {
    final response = await _client.get('/credits/trial');
    return TrialSummary.fromJson(_client.decodeMap(response, '/credits/trial'));
  }

  Future<TrialVerificationCreated> startTrialVerification() async {
    final response = await _client.post('/credits/trial/verifications');
    return TrialVerificationCreated.fromJson(
      _client.decodeMap(response, '/credits/trial/verifications'),
    );
  }

  Future<TrialGrantResult> claimTrialVerification(String verificationId) async {
    final response = await _client.post(
      '/credits/trial/verifications/$verificationId/claim',
    );
    return TrialGrantResult.fromJson(
      _client.decodeMap(response, '/credits/trial/claim'),
    );
  }

  Future<RedeemPreview> previewRedeem(String code) async {
    final response = await _client.post(
      '/credits/redemptions/preview',
      body: RedeemCodeSubmit(code: code).toJson(),
    );
    return RedeemPreview.fromJson(
      _client.decodeMap(response, '/credits/redemptions/preview'),
    );
  }

  Future<RedeemResult> redeem(String code) async {
    final response = await _client.post(
      '/credits/redemptions',
      body: RedeemCodeSubmit(code: code).toJson(),
    );
    return RedeemResult.fromJson(
      _client.decodeMap(response, '/credits/redemptions'),
    );
  }
}
