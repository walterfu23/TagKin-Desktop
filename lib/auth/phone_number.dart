/// Shown under the code field after Firebase accepts the send.
const String kTextCodeDelayNote =
    'The text can take a minute. Check your messages, including filtered ones.';

/// Shown under the phone field and when the text cannot be sent.
const String kPhoneNumberExample =
    'Enter a phone number, such as (650) 555-0100 or +1 650 555 0100.';

/// A number ready for Firebase (E.164) or a sentence explaining why not.
class PhoneNumberInput {
  const PhoneNumberInput.ok(this.e164) : error = null;
  const PhoneNumberInput.bad(this.error) : e164 = null;

  final String? e164;
  final String? error;
}

/// Turns common typed forms into E.164.
///
/// A 10-digit number, or 11 digits starting with 1, is treated as US/Canada.
/// A value that already starts with `+` keeps that country code. `011` is
/// not rewritten.
PhoneNumberInput normalizePhone(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed.startsWith('011')) {
    return const PhoneNumberInput.bad(kPhoneNumberExample);
  }
  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  if (trimmed.startsWith('+')) {
    if (digits.length < 8 || digits.length > 15) {
      return const PhoneNumberInput.bad(kPhoneNumberExample);
    }
    return PhoneNumberInput.ok('+$digits');
  }
  var national = digits;
  if (national.length == 11 && national.startsWith('1')) {
    national = national.substring(1);
  }
  if (national.length != 10 || national.startsWith(RegExp('[01]'))) {
    return const PhoneNumberInput.bad(kPhoneNumberExample);
  }
  return PhoneNumberInput.ok('+1$national');
}
