import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tagkin_desktop/auth/auth_bootstrap.dart';
import 'package:tagkin_desktop/auth/firebase_identity.dart';
import 'package:tagkin_desktop/auth/firebase_mfa.dart';
import 'package:tagkin_desktop/auth/phone_number.dart';

void main() {
  test('US and Canada numbers become E.164', () {
    for (final raw in [
      '(650) 555-0100',
      '650-555-0100',
      '650.555.0100',
      '6505550100',
      '1 650 555 0100',
      '+1 650 555 0100',
    ]) {
      expect(normalizePhone(raw).e164, '+16505550100', reason: raw);
    }
  });

  test('a leading plus keeps its country code', () {
    expect(normalizePhone('+44 20 7946 0958').e164, '+442079460958');
  });

  test('011 and a bad area code are rejected', () {
    expect(normalizePhone('011 44 20 7946 0958').e164, isNull);
    expect(normalizePhone('050 555 0100').e164, isNull);
    expect(normalizePhone('150 555 0100').e164, isNull);
    expect(
      normalizePhone('650').error,
      kPhoneNumberExample,
    );
  });

  test('phone failures use a sentence', () {
    String message(String code) => mfaFailureMessage({
      'error': {'message': code},
    });
    expect(message('INVALID_PHONE_NUMBER'), 'That phone number is not valid.');
    expect(
      message('INVALID_APP_CREDENTIAL'),
      'The text message check was rejected. Try again.',
    );
    expect(
      message('OPERATION_NOT_ALLOWED'),
      'Texts to that number are not allowed.',
    );
    expect(message('TOO_MANY_ATTEMPTS_TRY_LATER'), 'Too many texts. Try again later.');
    expect(message('QUOTA_EXCEEDED'), 'Too many texts. Try again later.');
  });

  const _config = FirebasePublicConfig(
    apiKey: 'public-key',
    authDomain: 'app.firebaseapp.com',
    projectId: 'app',
  );

  test('the text-message check loads its Enterprise key with GET', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/v2/recaptchaConfig');
      return http.Response('{"recaptchaKey":"site-key"}', 200);
    });
    final setup = await recaptchaSetup(_config, httpClient: client);
    expect(setup.enterprise, isTrue);
    expect(setup.siteKey, 'site-key');
  });

  test('the Enterprise page posts its token', () {
    expect(recaptchaFormToken('token=abc'), 'abc');
    expect(recaptchaFormToken('token=a%2Bb'), 'a+b');
    expect(recaptchaFormToken('token=a+b'), 'a+b');
    expect(recaptchaFormToken('token='), isNull);
  });

  test('a missing Enterprise key uses the classic checkbox token', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/v2/recaptchaConfig') {
        return http.Response('{"recaptchaEnforcementState":[]}', 200);
      }
      expect(request.url.path, '/v1/recaptchaParams');
      return http.Response('{"recaptchaSiteKey":"classic-key"}', 200);
    });
    final setup = await recaptchaSetup(_config, httpClient: client);
    expect(setup.enterprise, isFalse);
    expect(setup.siteKey, 'classic-key');
    expect(smsDispatchFields('a+b', enterprise: false), {
      'recaptchaToken': 'a+b',
      'captchaResponse': 'NO_RECAPTCHA',
      'clientType': 'CLIENT_TYPE_WEB',
      'recaptchaVersion': 'RECAPTCHA_ENTERPRISE',
    });
  });

  test('a failed Enterprise key request uses the classic checkbox token', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/v2/recaptchaConfig') {
        return http.Response('internal', 500);
      }
      expect(request.url.path, '/v1/recaptchaParams');
      return http.Response('{"recaptchaSiteKey":"classic-key"}', 200);
    });
    final setup = await recaptchaSetup(_config, httpClient: client);
    expect(setup.enterprise, isFalse);
    expect(
      smsDispatchFields('tok', enterprise: setup.enterprise),
      {
        'recaptchaToken': 'tok',
        'captchaResponse': 'NO_RECAPTCHA',
        'clientType': 'CLIENT_TYPE_WEB',
        'recaptchaVersion': 'RECAPTCHA_ENTERPRISE',
      },
    );
  });

  test('sms enrollment sends the fields Firebase needs to dispatch a text', () async {
    late Map<String, dynamic> sent;
    final client = MockClient((request) async {
      expect(request.url.path, '/v2/accounts/mfaEnrollment:start');
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'phoneSessionInfo': {'sessionInfo': 'session-1'},
        }),
        200,
      );
    });
    final session = await startSmsEnrollment(
      config: _config,
      idToken: 'id-token',
      phoneNumber: '+16505550100',
      recaptchaToken: 'checkbox-token',
      enterprise: true,
      httpClient: client,
    );
    expect(session, 'session-1');
    expect(sent['phoneEnrollmentInfo'], {
      'phoneNumber': '+16505550100',
      'captchaResponse': 'checkbox-token',
      'clientType': 'CLIENT_TYPE_WEB',
      'recaptchaVersion': 'RECAPTCHA_ENTERPRISE',
    });
  });

  test('an HTML text-message check shows a sentence', () async {
    final client = MockClient(
      (_) async => http.Response('<!DOCTYPE html><p>no</p>', 200),
    );
    expect(
      () => recaptchaSetup(_config, httpClient: client),
      throwsA(
        isA<FirebaseAuthException>().having(
          (error) => error.message,
          'message',
          'Could not start the text message check.',
        ),
      ),
    );
  });
}
