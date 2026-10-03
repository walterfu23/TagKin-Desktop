import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:tagkin_desktop/auth/auth_bootstrap.dart';
import 'package:tagkin_desktop/auth/firebase_identity.dart';
import 'package:tagkin_desktop/auth/login_hero.dart';
import 'package:url_launcher/url_launcher.dart';

/// Email/password Firebase sign-in, plus Google when a public client id is set.
class FirebaseSignInPage extends StatefulWidget {
  const FirebaseSignInPage({
    super.key,
    required this.config,
    required this.onSession,
  });

  final FirebasePublicConfig config;
  final ValueChanged<FirebaseSession> onSession;

  @override
  State<FirebaseSignInPage> createState() => _FirebaseSignInPageState();
}

class _FirebaseSignInPageState extends State<FirebaseSignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _signUp = false;
  var _busy = false;
  String? _error;
  PkcePair? _pendingPkce;
  StreamSubscription<Uri>? _links;

  @override
  void dispose() {
    _links?.cancel();
    _email.dispose();
    _password.dispose();
    super.dispose();
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
      );
      if (!mounted) return;
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

  Future<void> _google() async {
    final clientId = widget.config.googleClientId;
    if (clientId == null) return;
    final pkce = createPkcePair();
    _pendingPkce = pkce;
    _links ??= AppLinks().uriLinkStream.listen(_onLink);
    final uri = googleAuthorizeUri(
      clientId: clientId,
      redirectUri: kFirebaseOauthRedirect,
      codeChallenge: pkce.challenge,
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      setState(() => _error = 'Could not open the browser for Google sign-in.');
    }
  }

  Future<void> _onLink(Uri uri) async {
    final code = oauthCodeFromRedirect(uri);
    final pkce = _pendingPkce;
    if (code == null || pkce == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await signInWithGoogleCode(
        config: widget.config,
        code: code,
        codeVerifier: pkce.verifier,
        redirectUri: kFirebaseOauthRedirect,
      );
      if (!mounted) return;
      widget.onSession(session);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Google sign-in failed.');
    } finally {
      _pendingPkce = null;
      if (mounted) setState(() => _busy = false);
    }
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
            _signUp ? 'Create account' : 'Sign in',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
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
            child: Text(_signUp
                ? 'Have an account? Sign in'
                : 'New here? Create account'),
          ),
          if (!kIsWeb &&
              Platform.isMacOS &&
              widget.config.googleClientId != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('firebase-google'),
              onPressed: _busy ? null : _google,
              child: const Text('Continue with Google'),
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
