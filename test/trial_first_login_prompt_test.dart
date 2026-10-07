import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/credits/trial_first_login_prompt.dart';

TrialSummary _summary({
  bool available = true,
  bool neverHadCredits = true,
  TrialStatus status = TrialStatus.notstarted,
}) {
  return TrialSummary(
    status: status,
    eligible: status != TrialStatus.granted,
    available: available,
    neverHadCredits: neverHadCredits,
    publishableKey: 'pk_test_stub',
  );
}

void main() {
  test('prompts only when the pack is available and credits were never added',
      () {
    expect(
      TrialFirstLoginPrompt.shouldPrompt(_summary()),
      isTrue,
    );
    expect(
      TrialFirstLoginPrompt.shouldPrompt(_summary(available: false)),
      isFalse,
    );
    expect(
      TrialFirstLoginPrompt.shouldPrompt(_summary(neverHadCredits: false)),
      isFalse,
    );
    expect(
      TrialFirstLoginPrompt.shouldPrompt(
        _summary(status: TrialStatus.granted, neverHadCredits: false),
      ),
      isFalse,
    );
  });
}
