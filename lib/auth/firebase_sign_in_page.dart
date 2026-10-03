import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:tagkin_desktop/auth/auth_bootstrap.dart';
import 'package:tagkin_desktop/auth/firebase_identity.dart';
import 'package:tagkin_desktop/auth/google_loopback.dart';
import 'package:tagkin_desktop/auth/login_hero.dart';
import 'package:url_launcher/url_launcher.dart';

/// Email/password Firebase sign-in, plus Google (macOS and Windows) when
/// bootstrap carries a public Google client id.
class FirebaseSignInPage extends StatefulWidget {
  const FirebaseSignInPage({
    super.key,
    required this.config,
    required this.apiUrl,
    required this.onSession,
    this.httpClient,
  });

  final FirebasePublicConfig config;
  final String apiUrl;
  final ValueChanged<FirebaseSession> onSession;
  final http.Client? httpClient;

  @override
  State<FirebaseSignInPage> createState() => _FirebaseSignInPageState();
}

class _FirebaseSignInPageState extends State<FirebaseSignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  var _signUp = false;
  var _busy = false;
  String? _error;
  FirebaseSession? _pending;
  String? _emailMasked;
  GoogleLoopback? _loopback;
  var _googleCancelled = false;

  @override
  void dispose() {
    _loopback?.cancel();
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _startEmailCode(FirebaseSession session) async {
    final start = await requestEmailSignInCode(
      apiUrl: widget.apiUrl,
      idToken: session.idToken,
      httpClient: widget.httpClient,
    );
    if (!mounted) return;
    if (start.alreadyVerified) {
      widget.onSession(session);
      return;
    }
    setState(() {
      _pending = session;
      _emailMasked = start.emailMasked;
      _error = null;
      _code.clear();
    });
  }

  Future<void> _submit() async {
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
      await _startEmailCode(session);
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
      final session = await signInWithGoogleCode(
        config: widget.config,
        apiUrl: widget.apiUrl,
        code: code,
        codeVerifier: pkce.verifier,
        redirectUri: loopback.redirectUri,
        httpClient: widget.httpClient,
      );
      if (!mounted) return;
      await _startEmailCode(session);
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
    final pending = _pending;
    if (pending == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await verifyEmailSignInCode(
        apiUrl: widget.apiUrl,
        idToken: pending.idToken,
        code: _code.text,
        httpClient: widget.httpClient,
      );
      if (!mounted) return;
      widget.onSession(pending);
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
    final pending = _pending;
    if (pending == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final start = await requestEmailSignInCode(
        apiUrl: widget.apiUrl,
        idToken: pending.idToken,
        httpClient: widget.httpClient,
      );
      if (!mounted) return;
      if (start.alreadyVerified) {
        widget.onSession(pending);
        return;
      }
      setState(() => _emailMasked = start.emailMasked);
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
          Text(
            _pending != null
                ? 'Check your email'
                : (_signUp ? 'Create account' : 'Sign in'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          if (_pending != null) ...[
            Text(
              'Enter the code sent to ${_emailMasked ?? 'your email'}.',
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
                      _pending = null;
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
            const SizedBox(height: 12),
            TextField(
              key: const Key('firebase-password'),
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Password'),
              onSubmitted: (_) => _busy ? null : _submit(),
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
              key: const Key('firebase-submit'),
              onPressed: _busy ? null : _submit,
              child: Text(_signUp ? 'Create account' : 'Sign in'),
            ),
            TextButton(
              key: const Key('firebase-toggle-mode'),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _signUp = !_signUp;
                      _error = null;
                    }),
              child: Text(
                _signUp
                    ? 'Have an account? Sign in'
                    : 'New here? Create account',
              ),
            ),
          ],
        ],
      ),
    );

    return Scaffold(
      key: const Key('firebase-sign-in'),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 800;
            if (!wide) {
              return Center(child: SingleChildScrollView(child: form));
            }
            return Row(
              children: [
                const Expanded(child: LoginHero()),
                Expanded(child: Center(child: form)),
              ],
            );
          },
        ),
      ),
    );
  }
}
