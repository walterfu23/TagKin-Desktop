import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:tagkin_desktop/auth/auth_bootstrap.dart';
import 'package:tagkin_desktop/auth/firebase_identity.dart';
import 'package:tagkin_desktop/auth/firebase_mfa.dart';
import 'package:tagkin_desktop/auth/google_loopback.dart';
import 'package:tagkin_desktop/auth/login_hero.dart';
import 'package:tagkin_desktop/auth/phone_number.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shown when a stored session belonged to an account that was removed.
const String kAccountRemovedNotice =
    'That account was removed. Set it up again.';

/// Email/password Firebase sign-in, plus Google (macOS and Windows) when
/// bootstrap carries a public Google client id.
class FirebaseSignInPage extends StatefulWidget {
  const FirebaseSignInPage({
    super.key,
    required this.config,
    required this.apiUrl,
    required this.onSession,
    this.onAddAuthenticator,
    this.onAddPhone,
    this.notice,
    this.initialEmail,
    this.onCancel,
    this.onAttempt,
    this.httpClient,
  });

  final FirebasePublicConfig config;
  final String apiUrl;
  final ValueChanged<FirebaseSession> onSession;

  /// One-shot line above the form, such as after a removed account.
  final String? notice;

  /// Prefills the email when putting an account back after the secure-store
  /// entry is gone.
  final String? initialEmail;

  /// Returns to the account list when this computer already has accounts.
  final VoidCallback? onCancel;

  /// A sign-in attempt started. The shell clears [notice].
  final VoidCallback? onAttempt;

  /// Called just before [onSession] when the text code was for adding an
  /// authenticator app.
  final VoidCallback? onAddAuthenticator;

  /// Called just before [onSession] with the number to enroll after the
  /// authenticator code.
  final ValueChanged<String>? onAddPhone;
  final http.Client? httpClient;

  @override
  State<FirebaseSignInPage> createState() => _FirebaseSignInPageState();
}

class _FirebaseSignInPageState extends State<FirebaseSignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _phone = TextEditingController();
  var _signUp = false;
  var _busy = false;
  String? _error;
  var _emailCode = false;
  String? _emailMasked;
  MfaChallenge? _mfa;
  var _factorIndex = 0;
  var _factorChosen = false;
  var _addAuthenticator = false;
  var _addPhone = false;
  String? _phoneE164;
  var _phoneStep = false;
  var _usePassword = false;
  String? _smsSession;
  GoogleLoopback? _loopback;
  var _googleCancelled = false;

  @override
  void initState() {
    super.initState();
    final email = widget.initialEmail;
    if (email != null && email.isNotEmpty) _email.text = email;
  }

  @override
  void dispose() {
    _loopback?.cancel();
    _email.dispose();
    _password.dispose();
    _code.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _showMfa(MfaChallenge challenge) {
    setState(() {
      _mfa = challenge;
      _factorIndex = 0;
      _factorChosen = false;
      _addAuthenticator = false;
      _addPhone = false;
      _phoneE164 = null;
      _phone.clear();
      _phoneStep = false;
      _smsSession = null;
      _emailCode = false;
      _error = null;
      _code.clear();
    });
  }

  Future<void> _submit() async {
    widget.onAttempt?.call();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await signInWithPassword(
        config: widget.config,
        email: _email.text,
        password: _password.text,
        signUp: _signUp,
        httpClient: widget.httpClient,
      );
      if (!mounted) return;
      widget.onSession(session);
    } on FirebaseAccountMissing catch (e) {
      if (!mounted) return;
      setState(() {
        _signUp = true;
        _error = e.message;
      });
    } on MfaRequired catch (e) {
      if (!mounted) return;
      _showMfa(e.challenge);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Sign-in failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _emailMe() async {
    widget.onAttempt?.call();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final start = await requestEmailSignInCode(
        apiUrl: widget.apiUrl,
        email: _email.text,
        httpClient: widget.httpClient,
      );
      if (!mounted) return;
      setState(() {
        _emailCode = true;
        _emailMasked = start.emailMasked;
        _code.clear();
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Sign-in failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _googleWaiting => _loopback != null;

  Future<void> _google() async {
    final clientId = widget.config.googleClientId;
    if (clientId == null || _busy) return;
    widget.onAttempt?.call();
    setState(() {
      _busy = true;
      _error = null;
      _googleCancelled = false;
    });
    GoogleLoopback? loopback;
    try {
      final pkce = createPkcePair();
      loopback = await GoogleLoopback.start();
      if (!mounted) {
        await loopback.cancel();
        return;
      }
      setState(() => _loopback = loopback);
      final uri = googleAuthorizeUri(
        clientId: clientId,
        redirectUri: loopback.redirectUri,
        codeChallenge: pkce.challenge,
        state: loopback.state,
      );
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        await loopback.cancel();
        throw GoogleLoopbackException(
          'Could not open the browser for Google sign-in.',
        );
      }
      final code = await loopback.code;
      try {
        final session = await signInWithGoogleCode(
          config: widget.config,
          apiUrl: widget.apiUrl,
          code: code,
          codeVerifier: pkce.verifier,
          redirectUri: loopback.redirectUri,
          httpClient: widget.httpClient,
        );
        if (!mounted) return;
        widget.onSession(session);
      } on MfaRequired catch (e) {
        if (!mounted) return;
        _showMfa(e.challenge);
      }
    } on GoogleLoopbackException catch (e) {
      if (!mounted) return;
      if (!_googleCancelled) setState(() => _error = e.message);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e, st) {
      if (!mounted) return;
      debugPrint('Google sign-in failed: $e\n$st');
      setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() {
          _loopback = null;
          _busy = false;
        });
      }
    }
  }

  Future<void> _submitCode() async {
    if (!_emailCode || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final oob = await verifyEmailSignInCode(
        apiUrl: widget.apiUrl,
        email: _email.text,
        code: _code.text,
        httpClient: widget.httpClient,
      );
      final session = await signInWithEmailLink(
        config: widget.config,
        email: _email.text,
        oobCode: oob,
        httpClient: widget.httpClient,
      );
      if (!mounted) return;
      widget.onSession(session);
    } on MfaRequired catch (e) {
      if (!mounted) return;
      _showMfa(e.challenge);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Sign-in failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendCode() async {
    if (!_emailCode || _busy) return;
    await _emailMe();
  }

  Future<void> _submitMfa() async {
    final challenge = _mfa;
    if (challenge == null || _busy || challenge.factors.isEmpty) return;
    final factor =
        challenge.factors[_factorIndex.clamp(0, challenge.factors.length - 1)];
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (factor.kind == 'phone' && _smsSession == null) {
        final check = await solveRecaptcha(
          config: widget.config,
          action: kMfaSmsSignInAction,
          httpClient: widget.httpClient,
        );
        final session = await startSmsSignIn(
          config: widget.config,
          challenge: challenge,
          factor: factor,
          recaptchaToken: check.token,
          enterprise: check.enterprise,
          httpClient: widget.httpClient,
        );
        if (!mounted) return;
        setState(() => _smsSession = session);
        return;
      }
      final session = await finishMfaSignIn(
        config: widget.config,
        challenge: challenge,
        factor: factor,
        code: _code.text,
        smsSessionInfo: _smsSession,
        httpClient: widget.httpClient,
      );
      if (!mounted) return;
      if (_addAuthenticator) widget.onAddAuthenticator?.call();
      final phone = _phoneE164;
      if (_addPhone && phone != null) widget.onAddPhone?.call(phone);
      widget.onSession(session);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Sign-in failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _smsPrompt {
    final factor = _selectedFactor;
    if (factor?.kind == 'phone' && _smsSession == null) {
      return 'You will get a text after you continue';
    }
    return 'Code';
  }

  String get _mfaButton {
    final factor = _selectedFactor;
    if (factor?.kind == 'phone' && _smsSession == null) return 'Send text';
    return 'Continue';
  }

  String _factorChoiceLabel(MfaFactor factor) =>
      factor.kind == 'phone' ? 'Text ${factor.label}' : 'Authenticator app';

  bool get _phoneWithoutAuthenticator {
    final factors = _mfa?.factors;
    if (factors == null || factors.isEmpty) return false;
    return factors.any((factor) => factor.kind == 'phone') &&
        factors.every((factor) => factor.kind != 'totp');
  }

  bool get _authenticatorWithoutPhone {
    final factors = _mfa?.factors;
    if (factors == null || factors.isEmpty) return false;
    return factors.any((factor) => factor.kind == 'totp') &&
        factors.every((factor) => factor.kind != 'phone');
  }

  MfaFactor? get _selectedFactor {
    final factors = _mfa?.factors;
    if (factors == null || factors.isEmpty) return null;
    return factors[_factorIndex.clamp(0, factors.length - 1)];
  }

  void _acceptPhone() {
    final phone = normalizePhone(_phone.text);
    setState(() {
      if (phone.e164 == null) {
        _error = phone.error;
        return;
      }
      _phoneE164 = phone.e164;
      _error = null;
      _code.clear();
    });
  }

  void _skipPhone() {
    setState(() {
      _addPhone = false;
      _phoneE164 = null;
      _factorChosen = true;
      _error = null;
      _code.clear();
    });
  }

  Future<void> _cancelGoogle() async {
    _googleCancelled = true;
    await _loopback?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final form = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.notice != null) ...[
            Text(widget.notice!, key: const Key('firebase-sign-in-notice')),
            const SizedBox(height: 12),
          ],
          Text(
            _mfa != null && _addPhone && _phoneE164 == null
                ? 'Add a phone number'
                : _mfa != null
                ? 'Second factor'
                : _emailCode
                ? 'Check your email'
                : (_signUp ? 'Create account' : 'Set up account'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          if (_mfa != null && _addPhone && _phoneE164 == null) ...[
            const Text(
              'Enter your phone number. FamFace texts a code to it.',
              key: Key('firebase-mfa-hint'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('firebase-mfa-phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                helperText: kPhoneNumberExample,
              ),
              onSubmitted: (_) => _busy ? null : _acceptPhone(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('firebase-auth-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('firebase-mfa-phone-continue'),
              onPressed: _busy ? null : _acceptPhone,
              child: const Text('Continue'),
            ),
            TextButton(
              key: const Key('firebase-mfa-phone-skip'),
              onPressed: _busy ? null : _skipPhone,
              child: const Text('Skip'),
            ),
            TextButton(
              key: const Key('firebase-mfa-choice-back'),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _addPhone = false;
                      _phoneE164 = null;
                      _error = null;
                    }),
              child: const Text('Back'),
            ),
          ] else if (_mfa != null && _addPhone) ...[
            const Text(
              'Enter the code from your authenticator app. The text is sent after this.',
              key: Key('firebase-mfa-hint'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('firebase-mfa-code'),
              controller: _code,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Code'),
              onSubmitted: (_) => _busy ? null : _submitMfa(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('firebase-auth-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('firebase-mfa-submit'),
              onPressed: _busy ? null : _submitMfa,
              child: const Text('Continue'),
            ),
            TextButton(
              key: const Key('firebase-mfa-choice-back'),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _phoneE164 = null;
                      _error = null;
                      _code.clear();
                    }),
              child: const Text('Back'),
            ),
          ] else if (_mfa != null && !_factorChosen) ...[
            const Text(
              'Choose a second factor.',
              key: Key('firebase-mfa-hint'),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _mfa!.factors.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              OutlinedButton(
                key: Key('firebase-mfa-factor-$i'),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _factorIndex = i;
                        _addAuthenticator = false;
                        _addPhone = false;
                        _smsSession = null;
                        _error = null;
                        _code.clear();
                        if (_phoneWithoutAuthenticator) {
                          _phoneStep = true;
                          _factorChosen = false;
                        } else {
                          _factorChosen = true;
                        }
                      }),
                child: Text(
                  _phoneWithoutAuthenticator && _mfa!.factors[i].kind == 'phone'
                      ? 'Send text ${_mfa!.factors[i].label}'
                      : _factorChoiceLabel(_mfa!.factors[i]),
                ),
              ),
            ],
            if (_phoneWithoutAuthenticator) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('firebase-mfa-add-authenticator'),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _factorIndex = _mfa!.factors.indexWhere(
                          (factor) => factor.kind == 'phone',
                        );
                        _factorChosen = false;
                        _addAuthenticator = true;
                        _phoneStep = true;
                        _smsSession = null;
                        _error = null;
                        _code.clear();
                      }),
                child: const Text('Add authenticator app'),
              ),
            ],
            if (_authenticatorWithoutPhone) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('firebase-mfa-add-phone'),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _factorIndex = _mfa!.factors.indexWhere(
                          (factor) => factor.kind == 'totp',
                        );
                        _factorChosen = false;
                        _addPhone = true;
                        _phoneE164 = null;
                        _addAuthenticator = false;
                        _smsSession = null;
                        _error = null;
                        _code.clear();
                      }),
                child: const Text('Add phone number'),
              ),
            ],
            if (_phoneWithoutAuthenticator && _phoneStep) ...[
              const SizedBox(height: 12),
              if (_addAuthenticator)
                const Text(
                  'Enter the code from the text first. Then you can add an authenticator app.',
                ),
              if (!_addAuthenticator || _smsSession != null) ...[
                if (_addAuthenticator) const SizedBox(height: 12),
                TextField(
                  key: const Key('firebase-mfa-code'),
                  controller: _code,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: _addAuthenticator
                        ? 'Code from the text'
                        : _smsPrompt,
                  ),
                  onSubmitted: (_) => _busy ? null : _submitMfa(),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const Key('firebase-auth-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('firebase-mfa-submit'),
                onPressed: _busy ? null : _submitMfa,
                child: Text(_mfaButton),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              key: const Key('firebase-mfa-choice-back'),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _mfa = null;
                      _addAuthenticator = false;
                      _addPhone = false;
                      _phoneE164 = null;
                      _phoneStep = false;
                      _smsSession = null;
                      _error = null;
                      _code.clear();
                    }),
              child: const Text('Back'),
            ),
          ] else if (_mfa != null) ...[
            Text(
              _addAuthenticator
                  ? 'Enter the code from the text first. Then you can add an authenticator app.'
                  : 'Enter the code from ${_selectedFactor?.label ?? 'your second factor'}.',
              key: const Key('firebase-mfa-hint'),
            ),
            if (!_addAuthenticator || _smsSession != null) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('firebase-mfa-code'),
                controller: _code,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _addAuthenticator
                      ? 'Code from the text'
                      : _smsPrompt,
                ),
                onSubmitted: (_) => _busy ? null : _submitMfa(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('firebase-auth-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('firebase-mfa-submit'),
              onPressed: _busy ? null : _submitMfa,
              child: Text(_mfaButton),
            ),
            TextButton(
              key: const Key('firebase-mfa-back'),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      if (_mfa!.factors.length > 1 ||
                          _phoneWithoutAuthenticator ||
                          _authenticatorWithoutPhone) {
                        _factorChosen = false;
                        _addAuthenticator = false;
                        _addPhone = false;
                        _phoneE164 = null;
                      } else {
                        _mfa = null;
                      }
                      _smsSession = null;
                      _error = null;
                      _code.clear();
                    }),
              child: const Text('Back'),
            ),
          ] else if (_emailCode) ...[
            Text(
              'Enter the code sent to ${_emailMasked ?? 'your email'}. This signs you in instead of a password.',
              key: const Key('firebase-email-code-hint'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('firebase-email-code'),
              controller: _code,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Code'),
              onSubmitted: (_) => _busy ? null : _submitCode(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('firebase-auth-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('firebase-email-code-submit'),
              onPressed: _busy ? null : _submitCode,
              child: const Text('Continue'),
            ),
            TextButton(
              key: const Key('firebase-email-code-resend'),
              onPressed: _busy ? null : _resendCode,
              child: const Text('Resend code'),
            ),
            TextButton(
              key: const Key('firebase-email-code-back'),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _emailCode = false;
                      _emailMasked = null;
                      _error = null;
                      _code.clear();
                    }),
              child: const Text('Back'),
            ),
          ] else ...[
            if (!kIsWeb && widget.config.googleClientId != null) ...[
              if (_googleWaiting) ...[
                const Text(
                  'Finish signing in with Google in your browser.',
                  key: Key('firebase-google-waiting'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const Key('firebase-google-cancel'),
                  onPressed: _cancelGoogle,
                  child: const Text('Cancel'),
                ),
              ] else
                OutlinedButton(
                  key: const Key('firebase-google'),
                  onPressed: _busy ? null : _google,
                  child: const Text('Continue with Google'),
                ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('or'),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 4),
            ],
            TextField(
              key: const Key('firebase-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            if (_signUp || _usePassword) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('firebase-password'),
                controller: _password,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(labelText: 'Password'),
                onSubmitted: (_) => _busy ? null : _submit(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('firebase-auth-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            if (_signUp || _usePassword)
              OutlinedButton(
                key: const Key('firebase-submit'),
                onPressed: _busy ? null : _submit,
                child: Text(_signUp ? 'Create account' : 'Continue'),
              )
            else
              OutlinedButton(
                key: const Key('firebase-use-password'),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _usePassword = true;
                        _error = null;
                      }),
                child: const Text('Use a password'),
              ),
            if (!_signUp) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('firebase-email-me'),
                onPressed: _busy ? null : _emailMe,
                child: const Text('Email me a code'),
              ),
            ],
            TextButton(
              key: const Key('firebase-toggle-mode'),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _signUp = !_signUp;
                      _usePassword = false;
                      _error = null;
                    }),
              child: Text(
                _signUp
                    ? 'Have an account? Use a password'
                    : 'New here? Create account',
              ),
            ),
            if (widget.onCancel != null) ...[
              const SizedBox(height: 8),
              TextButton(
                key: const Key('firebase-setup-cancel'),
                onPressed: _busy ? null : widget.onCancel,
                child: const Text('Back'),
              ),
            ],
          ],
        ],
      ),
    );

    return SignedOutFrame(
      scaffoldKey: const Key('firebase-sign-in'),
      child: form,
    );
  }
}
