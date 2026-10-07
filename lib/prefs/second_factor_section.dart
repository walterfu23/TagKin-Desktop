import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:tagkin_desktop/auth/firebase_desk.dart';
import 'package:tagkin_desktop/auth/firebase_identity.dart';
import 'package:tagkin_desktop/auth/firebase_mfa.dart';
import 'package:tagkin_desktop/auth/login_hero.dart';
import 'package:tagkin_desktop/auth/phone_number.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

/// Settings block for optional SMS and authenticator second factors.
class SecondFactorSection extends ConsumerStatefulWidget {
  const SecondFactorSection({
    super.key,
    this.gate = false,
    this.newAccount = false,
    this.onEnrolled,
    this.onSkip,
    this.authenticatorOnly = false,
    this.phoneOnly = false,
    this.initialPhone,
    this.httpClient,
    this.requireSecondFactor,
    this.onRequireChanged,
    this.showSmsCodeField = false,
  });

  /// Full-page enrollment after a fresh sign-in. Hides the on/off switch.
  final bool gate;

  /// This sign-in created the account. The step is titled as sign-up.
  final bool newAccount;

  final VoidCallback? onEnrolled;

  /// Opens the library without adding an authenticator.
  final VoidCallback? onSkip;

  /// QR setup only. No phone field.
  final bool authenticatorOnly;

  /// Phone setup only. No authenticator button.
  final bool phoneOnly;

  /// Number already collected at sign-in. Enrollment sends the text to it.
  final String? initialPhone;

  final http.Client? httpClient;

  /// Draft value for the Settings switch. Null hides the switch.
  final bool? requireSecondFactor;

  final ValueChanged<bool>? onRequireChanged;

  /// Test hook so the text-code field can be shown without sending a text.
  final bool showSmsCodeField;

  @override
  ConsumerState<SecondFactorSection> createState() =>
      _SecondFactorSectionState();
}

class _SecondFactorSectionState extends ConsumerState<SecondFactorSection> {
  final _code = TextEditingController();
  final _phone = TextEditingController();
  var _busy = false;
  String? _error;
  List<MfaFactor>? _factors;
  TotpEnrollment? _totp;
  var _totpCodeStep = false;
  String? _smsSession;

  @override
  void initState() {
    super.initState();
    if (widget.showSmsCodeField) _smsSession = 'pending';
    final initialPhone = widget.initialPhone;
    if (initialPhone != null && initialPhone.isNotEmpty) {
      _phone.text = initialPhone;
      if (widget.phoneOnly && !widget.showSmsCodeField) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startSms();
        });
      }
    }
    if (widget.authenticatorOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startTotp();
      });
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _phone.dispose();
    super.dispose();
  }

  FirebaseDesk? get _desk => ref.read(firebaseDeskProvider);

  Future<void> _load() async {
    final desk = _desk;
    if (desk == null) return;
    setState(() => _busy = true);
    try {
      final factors = await listFactors(
        config: desk.config,
        idToken: desk.session.idToken,
        httpClient: widget.httpClient,
      );
      if (!mounted) return;
      setState(() {
        _factors = factors;
        _error = null;
      });
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _replace(FirebaseSession session, {bool enrolled = false}) {
    _desk?.onSession(session);
    if (enrolled) {
      widget.onEnrolled?.call();
      return;
    }
    setState(() {
      _totp = null;
      _totpCodeStep = false;
      _smsSession = null;
      _code.clear();
    });
    _load();
  }

  Future<void> _startTotp() async {
    final desk = _desk;
    if (desk == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final totp = await startTotpEnrollment(
        config: desk.config,
        idToken: desk.session.idToken,
        accountLabel: desk.session.email ?? 'account',
        httpClient: widget.httpClient,
      );
      if (mounted) {
        setState(() {
          _totp = totp;
          _totpCodeStep = false;
        });
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishTotp() async {
    final desk = _desk;
    final totp = _totp;
    if (desk == null || totp == null) return;
    setState(() => _busy = true);
    try {
      final session = await finishTotpEnrollment(
        config: desk.config,
        idToken: desk.session.idToken,
        sessionInfo: totp.sessionInfo,
        code: _code.text,
        httpClient: widget.httpClient,
      );
      if (!mounted) return;
      _replace(session, enrolled: widget.gate);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startSms() async {
    final desk = _desk;
    if (desk == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final phone = normalizePhone(_phone.text);
    if (phone.e164 == null) {
      setState(() {
        _busy = false;
        _error = phone.error;
      });
      return;
    }
    try {
      final check = await solveRecaptcha(
        config: desk.config,
        action: kMfaSmsEnrollAction,
      );
      final session = await startSmsEnrollment(
        config: desk.config,
        idToken: desk.session.idToken,
        phoneNumber: phone.e164!,
        recaptchaToken: check.token,
        enterprise: check.enterprise,
      );
      if (mounted) setState(() => _smsSession = session);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishSms() async {
    final desk = _desk;
    final sessionInfo = _smsSession;
    if (desk == null || sessionInfo == null) return;
    setState(() => _busy = true);
    try {
      final session = await finishSmsEnrollment(
        config: desk.config,
        idToken: desk.session.idToken,
        sessionInfo: sessionInfo,
        code: _code.text,
      );
      if (!mounted) return;
      _replace(session, enrolled: widget.gate);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(MfaFactor factor) async {
    final desk = _desk;
    if (desk == null) return;
    setState(() => _busy = true);
    try {
      await withdrawFactor(
        config: desk.config,
        idToken: desk.session.idToken,
        enrollmentId: factor.enrollmentId,
      );
      if (mounted) await _load();
    } on FirebaseAuthException catch (e) {
      if (e.message.contains('user-token-expired')) {
        await desk.onSignOut();
        return;
      }
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyEmail() async {
    final desk = _desk;
    final email = desk?.session.email;
    if (desk == null || email == null || email.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await requestEmailSignInCode(
        apiUrl: desk.apiUrl,
        email: email,
        httpClient: widget.httpClient,
      );
      if (!mounted) return;
      final code = await _askCode('Enter the code emailed to $email');
      if (code == null) return;
      final oob = await verifyEmailSignInCode(
        apiUrl: desk.apiUrl,
        email: email,
        code: code,
        httpClient: widget.httpClient,
      );
      final session = await signInWithEmailLink(
        config: desk.config,
        email: email,
        oobCode: oob,
        httpClient: widget.httpClient,
      );
      if (!mounted) return;
      _replace(session);
    } on MfaRequired {
      if (mounted) {
        setState(
          () => _error = 'Finish signing in with your second factor first.',
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askCode(String title) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Code'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _goBack() {
    setState(() {
      if (_totpCodeStep) {
        _totpCodeStep = false;
        _code.clear();
        _error = null;
        return;
      }
      _totp = null;
      _smsSession = null;
      _code.clear();
      _error = null;
    });
  }

  /// In the gate Back is an outlined button under the filled one. The
  /// Settings card keeps the text link.
  Widget _backButton() {
    const key = Key('firebase-mfa-gate-back');
    final onPressed = _busy ? null : _goBack;
    if (!widget.gate) {
      return TextButton(
        key: key,
        onPressed: onPressed,
        child: const Text('Back'),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: OutlinedButton(
        key: key,
        onPressed: onPressed,
        child: const Text('Back'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desk = ref.watch(firebaseDeskProvider);
    if (desk == null) return const SizedBox.shrink();
    final verified = idTokenEmailVerified(desk.session.idToken);
    final factors = _factors;
    final requireSecondFactor = ref
        .watch(desktopPrefsProvider)
        .requireSecondFactor;
    // Mid-enrollment in the gate: the QR or a code field is on screen and the
    // page has its own title. Sign out and Continue stay on the choice page.
    final enrolling = widget.gate && (_totp != null || _smsSession != null);
    final title = widget.phoneOnly
        ? (_smsSession != null ? 'Enter the code' : 'Add a phone number')
        : widget.authenticatorOnly
        ? (_totpCodeStep ? 'Enter the code' : 'Add an authenticator app')
        : widget.gate && _totp != null
        ? (_totpCodeStep ? 'Enter the code' : 'Scan this code')
        : widget.gate && _smsSession != null
        ? 'Enter the code'
        : widget.newAccount
        ? 'Create your account'
        : widget.gate
        ? 'Add a second factor'
        : 'Second factor';
    final intro = _totp != null
        ? _totpCodeStep
              ? 'Open that entry. Type the 6-digit code it shows. '
                    'The code changes every 30 seconds.'
              : 'Scan this once in your authenticator app. '
                    'A new entry appears there. Do not scan this code again.'
        : widget.authenticatorOnly
        ? 'Scan the code with your authenticator app, then enter the code it shows.'
        : widget.gate && _smsSession != null
        ? 'Type the code from the text message.'
        : widget.phoneOnly
        ? 'Enter your phone number. FamFace texts a code to it.'
        : widget.newAccount
        ? 'Add an authenticator app to finish creating your account. '
              'A phone number is the other choice.'
        : widget.gate
        ? 'Add an authenticator app to finish signing in. '
              'A phone number is the other choice.'
        : 'Password, an emailed code, and Google stay ways to sign in. '
              'An enrolled phone or authenticator is asked for at the next sign-in.';
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: widget.gate
              ? Theme.of(context).textTheme.headlineSmall
              : Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(intro),
        if (!widget.gate &&
            widget.requireSecondFactor != null &&
            widget.onRequireChanged != null)
          SwitchListTile(
            key: const Key('settings-require-second-factor'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Require a second factor at sign-in'),
            subtitle: const Text(
              'When on, a sign-in without a second factor asks you to add one. '
              'Accounts that already have one are always asked for it.',
            ),
            value: widget.requireSecondFactor ?? true,
            onChanged: widget.onRequireChanged,
          ),
        if (!verified) ...[
          const SizedBox(height: 8),
          const Text('Verify your email before adding a second factor.'),
          TextButton(
            key: const Key('settings-verify-email'),
            onPressed: _busy ? null : _verifyEmail,
            child: const Text('Email me a code'),
          ),
        ],
        if (!widget.gate && factors == null)
          TextButton(
            key: const Key('settings-second-factor-load'),
            onPressed: _busy ? null : _load,
            child: const Text('Show second factors'),
          )
        else if (factors != null) ...[
          for (final factor in factors)
            ListTile(
              title: Text(factor.label),
              subtitle: Text(
                factor.kind == 'phone' ? 'Text message' : 'Authenticator app',
              ),
              trailing: TextButton(
                onPressed: _busy ? null : () => _remove(factor),
                child: const Text('Remove'),
              ),
            ),
          if (factors.isEmpty) const Text('No second factor yet.'),
        ],
        if (_totp != null && (_smsSession == null || !widget.gate)) ...[
          if (!_totpCodeStep) ...[
            const SizedBox(height: 8),
            QrImageView(data: _totp!.otpauthUrl, size: 160),
            SelectableScope(
              child: SelectableText(
                _totp!.sharedSecretKey,
                key: const Key('settings-totp-secret'),
              ),
            ),
            FilledButton(
              key: const Key('settings-totp-next'),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _totpCodeStep = true;
                      _error = null;
                    }),
              child: const Text('Next'),
            ),
          ] else ...[
            TextField(
              key: const Key('settings-totp-code'),
              controller: _code,
              decoration: const InputDecoration(labelText: 'Code from the app'),
            ),
            FilledButton(
              onPressed: _busy ? null : _finishTotp,
              child: const Text('Verify'),
            ),
          ],
        ] else if (!widget.phoneOnly && (_smsSession == null || !widget.gate))
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const Key('settings-add-totp'),
              onPressed: _busy || !verified ? null : _startTotp,
              child: const Text('Add authenticator app'),
            ),
          ),
        if (!widget.authenticatorOnly &&
            _smsSession == null &&
            _totp == null) ...[
          TextField(
            key: const Key('settings-phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone number',
              helperText: kPhoneNumberExample,
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const Key('settings-add-phone'),
              onPressed: _busy || !verified ? null : _startSms,
              child: const Text('Text me a code'),
            ),
          ),
        ] else if (_smsSession != null) ...[
          TextField(
            key: const Key('settings-sms-code'),
            controller: _code,
            decoration: const InputDecoration(
              labelText: 'Code from the text',
              helperText: kTextCodeDelayNote,
            ),
          ),
          FilledButton(
            onPressed: _busy ? null : _finishSms,
            child: const Text('Verify'),
          ),
        ],
        if (_error != null)
          Text(
            _error!,
            key: const Key('settings-second-factor-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_totpCodeStep ||
            (widget.gate &&
                !widget.authenticatorOnly &&
                (_totp != null || _smsSession != null)))
          _backButton(),
        if (widget.authenticatorOnly || widget.phoneOnly)
          TextButton(
            key: const Key('firebase-mfa-gate-skip'),
            onPressed: _busy ? null : widget.onSkip,
            child: const Text('Skip'),
          ),
        if (widget.newAccount && !requireSecondFactor && !enrolling)
          TextButton(
            key: const Key('firebase-mfa-gate-skip-new'),
            onPressed: _busy ? null : widget.onSkip,
            child: const Text('Continue'),
          ),
        if (widget.gate && !enrolling)
          TextButton(
            key: const Key('firebase-mfa-gate-sign-out'),
            onPressed: _busy ? null : () => desk.onSignOut(),
            child: const Text('Sign out'),
          ),
      ],
    );
    if (widget.gate) {
      return SignedOutFrame(
        scaffoldKey: const Key('firebase-mfa-gate'),
        child: body,
      );
    }
    return Card(
      key: const Key('settings-second-factor'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(padding: const EdgeInsets.all(16), child: body),
    );
  }
}

/// Stops a fresh Firebase sign-in until a second factor exists.
class SecondFactorGate extends ConsumerStatefulWidget {
  const SecondFactorGate({
    super.key,
    required this.active,
    this.newAccount = false,
    this.addAuthenticator = false,
    this.addPhone = false,
    this.enrollPhone,
    required this.onCleared,
    required this.child,
    this.httpClient,
  });

  /// True for a fresh sign-in that still needs this step.
  final bool active;

  /// Titles the step as creating the account.
  final bool newAccount;

  /// After a text code, show authenticator setup before the library.
  final bool addAuthenticator;

  /// After an authenticator code, show phone setup before the library.
  final bool addPhone;

  /// Number collected before sign-in. The phone page texts this number.
  final String? enrollPhone;

  final VoidCallback onCleared;
  final Widget child;
  final http.Client? httpClient;

  @override
  ConsumerState<SecondFactorGate> createState() => _SecondFactorGateState();
}

class _SecondFactorGateState extends ConsumerState<SecondFactorGate> {
  var _checking = false;
  var _enroll = false;

  @override
  void initState() {
    super.initState();
    if (widget.addAuthenticator || widget.addPhone) return;
    if (widget.active) _check();
  }

  @override
  void didUpdateWidget(SecondFactorGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.addAuthenticator || widget.addPhone) return;
    if (widget.active && !oldWidget.active) _check();
    if (!widget.active && _enroll) {
      setState(() => _enroll = false);
    }
  }

  Future<void> _check() async {
    final desk = ref.read(firebaseDeskProvider);
    if (desk == null) return;
    setState(() {
      _checking = true;
      _enroll = false;
    });
    try {
      final factors = await listFactors(
        config: desk.config,
        idToken: desk.session.idToken,
        httpClient: widget.httpClient,
      );
      if (!mounted) return;
      if (factors.isNotEmpty) {
        widget.onCleared();
        setState(() => _checking = false);
        return;
      }
      setState(() {
        _checking = false;
        _enroll = true;
      });
    } on FirebaseAuthException {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _enroll = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.addAuthenticator) {
      return SecondFactorSection(
        gate: true,
        authenticatorOnly: true,
        httpClient: widget.httpClient,
        onEnrolled: widget.onCleared,
        onSkip: widget.onCleared,
      );
    }
    if (widget.addPhone) {
      return SecondFactorSection(
        gate: true,
        phoneOnly: true,
        initialPhone: widget.enrollPhone,
        httpClient: widget.httpClient,
        onEnrolled: widget.onCleared,
        onSkip: widget.onCleared,
      );
    }
    if (!widget.active) return widget.child;
    if (_checking) {
      return const SignedOutFrame(
        child: CircularProgressIndicator(key: Key('firebase-mfa-gate-loading')),
      );
    }
    if (_enroll) {
      return SecondFactorSection(
        gate: true,
        newAccount: widget.newAccount,
        httpClient: widget.httpClient,
        onEnrolled: widget.onCleared,
        onSkip: widget.newAccount ? widget.onCleared : null,
      );
    }
    return widget.child;
  }
}
