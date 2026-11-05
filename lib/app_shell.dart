import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show AppExitResponse;

import 'package:clerk_auth/clerk_auth.dart' show RetryOptions, Strategy;
import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:tagkin_desktop/auth/account_chooser.dart';
import 'package:tagkin_desktop/auth/account_roster.dart';
import 'package:tagkin_desktop/auth/auth_bootstrap.dart';
import 'package:tagkin_desktop/auth/firebase_desk.dart';
import 'package:tagkin_desktop/auth/firebase_identity.dart';
import 'package:tagkin_desktop/auth/firebase_sign_in_page.dart';
import 'package:tagkin_desktop/auth/login_hero.dart';
import 'package:tagkin_desktop/auth/macos_oauth_deep_links.dart';
import 'package:tagkin_desktop/auth/macos_oauth_return_hint.dart';
import 'package:tagkin_desktop/auth/provider_session.dart';
import 'package:tagkin_desktop/auth/secure_persistor.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/api/comments_repository.dart';
import 'package:tagkin_desktop/api/corrections_repository.dart';
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/api/jobs_repository.dart';
import 'package:tagkin_desktop/api/item_lists_repository.dart';
import 'package:tagkin_desktop/api/me_repository.dart';
import 'package:tagkin_desktop/api/persons_repository.dart';
import 'package:tagkin_desktop/api/usage_repository.dart';
import 'package:tagkin_desktop/api/credits_repository.dart';
import 'package:tagkin_desktop/branding.g.dart';
import 'package:tagkin_desktop/config/app_config.dart';
import 'package:tagkin_desktop/contract/contract.dart' hide AuthBootstrap;
import 'package:tagkin_desktop/credits/checkout_launcher.dart';
import 'package:tagkin_desktop/credits/credits_navigation.dart';
import 'package:tagkin_desktop/credits/trial_first_login_prompt.dart';
import 'package:tagkin_desktop/persons/collection_navigation.dart';
import 'package:tagkin_desktop/persons/collection_start_gate.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/dirty_leave_prompt.dart';
import 'package:tagkin_desktop/persons/face_crop_folder_scope.dart';
import 'package:tagkin_desktop/persons/face_crop_trays_page.dart';
import 'package:tagkin_desktop/persons/persons_list_page.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/library/views_menu.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/prefs/settings_navigation.dart';
import 'package:tagkin_desktop/ingest/folder_ingest_queue.dart';
import 'package:tagkin_desktop/ingest/folder_ingest_status_banner.dart';
import 'package:tagkin_desktop/item_lists/item_list_export_controller.dart';
import 'package:tagkin_desktop/item_lists/item_list_navigation.dart';
import 'package:tagkin_desktop/item_lists/item_list_music.dart';
import 'package:tagkin_desktop/shell/app_nav_tab_buttons.dart';
import 'package:tagkin_desktop/shell/quit_navigation.dart';
import 'package:tagkin_desktop/update/client_support_providers.dart';
import 'package:tagkin_desktop/update/client_update_banner.dart';
import 'package:tagkin_desktop/update/update_required_page.dart';
import 'package:window_manager/window_manager.dart';

export 'package:tagkin_desktop/shell/app_nav_tab_buttons.dart'
    show AppNavTabButtons, TopLevelTab, activeTopLevelTabProvider;

/// Signed-in [Account.id] for crash-resume ingest checkpoints. Null until the
/// signed-in shell's first frame (after `GET /me`).
final signedInAccountIdProvider = StateProvider<String?>((ref) => null);

/// App-wide config (overridable in tests).
final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.load());

/// Non-secret account list (email and id). Tests get an in-memory list so
/// widget tests do not write Application Support.
final accountDirectoryProvider = Provider<AccountDirectory>((ref) {
  if (Platform.environment['FLUTTER_TEST'] == 'true') {
    return MemoryAccountDirectory();
  }
  return FileAccountDirectory();
});

/// Secure Clerk persistor (overridable with [MemorySecureKeyValueStore] in tests).
final securePersistorProvider = Provider<SecureStoragePersistor>((ref) {
  if (Platform.environment['FLUTTER_TEST'] == 'true') {
    return SecureStoragePersistor(store: MemorySecureKeyValueStore());
  }
  return SecureStoragePersistor();
});

/// Optional override: when non-null, the shell skips live auth and uses this
/// session (unit/widget/integration tests).
final testSessionProvider = Provider<TestSession?>((ref) => null);

/// Active consumer auth provider from `GET /auth/bootstrap`.
/// Widget tests skip the network and fall back to the local Clerk key.
final authBootstrapProvider = Provider<Future<AuthBootstrap?>>((ref) {
  if (Platform.environment['FLUTTER_TEST'] == 'true') {
    return Future<AuthBootstrap?>.value(null);
  }
  final config = ref.watch(appConfigProvider);
  return fetchAuthBootstrap(config.apiUrl);
});

/// Shared client for Firebase sign-in, token refresh, and the signed-in API.
/// Null in the app. Tests override it so those calls stay off the network.
final authHttpClientProvider = Provider<http.Client?>((ref) => null);

/// Authenticated [ApiClient] — overridden inside the signed-in host.
final apiClientProvider = Provider<ApiClient>((ref) {
  throw StateError('apiClientProvider must be overridden when signed in');
});

/// Library items API (D2). Override in tests with a fake; otherwise built from
/// [apiClientProvider]. Declares that dependency so nested [ProviderScope]
/// overrides of [apiClientProvider] (signed-in host) are valid.
final itemsRepositoryProvider = Provider<ItemsRepository>(
  (ref) => ItemsRepository(ref.watch(apiClientProvider)),
  dependencies: [apiClientProvider],
);

/// Cost usage API (D6). Override in tests with a fake; otherwise built from
/// [apiClientProvider].
final usageRepositoryProvider = Provider<UsageRepository>(
  (ref) => UsageRepository(ref.watch(apiClientProvider)),
  dependencies: [apiClientProvider],
);

/// Credits pack/purchase/Trial API (D6). Override in tests with a fake.
final creditsRepositoryProvider = Provider<CreditsRepository>(
  (ref) => CreditsRepository(ref.watch(apiClientProvider)),
  dependencies: [apiClientProvider],
);

/// Bumped when a page pushed over the shell closes on Folders, so the
/// folder list reloads remaining credits without a new sign-in.
final foldersUsageRefreshTickProvider = StateProvider<int>((ref) => 0);

/// System-browser Checkout launcher. Override in tests.
final checkoutUrlLauncherProvider = Provider<CheckoutUrlLauncher>(
  (ref) => launchCheckoutUrl,
);

/// Tagging & jobs lifecycle API (D7). Override in tests with a fake;
/// otherwise built from [apiClientProvider].
final jobsRepositoryProvider = Provider<JobsRepository>(
  (ref) => JobsRepository(ref.watch(apiClientProvider)),
  dependencies: [apiClientProvider],
);

/// Item-list filter API (D13 / S12). Override in tests with a fake.
final itemListsRepositoryProvider = Provider<ItemListsRepository>(
  (ref) => ItemListsRepository(ref.watch(apiClientProvider)),
  dependencies: [apiClientProvider],
);

/// Soundtrack generate/estimate (S13). Override in tests with a fake.
final musicRepositoryProvider = Provider<MusicRepository>(
  (ref) => MusicRepository(ref.watch(apiClientProvider)),
  dependencies: [apiClientProvider],
);

/// Person linking API (D9). Override in tests with a fake; otherwise built
/// from [apiClientProvider].
final personsRepositoryProvider = Provider<PersonsRepository>(
  (ref) => PersonsRepository(ref.watch(apiClientProvider)),
  dependencies: [apiClientProvider],
);

/// Knowledge corrections API (D10 / S8). Override in tests with a fake.
final correctionsRepositoryProvider = Provider<CorrectionsRepository>(
  (ref) => CorrectionsRepository(ref.watch(apiClientProvider)),
  dependencies: [apiClientProvider],
);

/// Comments API (D10 / S9). Override in tests with a fake.
final commentsRepositoryProvider = Provider<CommentsRepository>(
  (ref) => CommentsRepository(ref.watch(apiClientProvider)),
  dependencies: [apiClientProvider],
);

/// Fake signed-in session for tests — supplies a bearer token + optional /me
/// result without talking to Clerk or the network.
class TestSession {
  const TestSession({
    required this.token,
    this.account,
    this.meError,
    this.onSignOut,
  });

  final String token;
  final Account? account;

  /// When set, [AccountBootstrap] surfaces this instead of calling /me.
  final Object? meError;

  /// Test-only sign-out hook so widget/integration tests can exercise the
  /// Sign out button (and the dirty-collection confirm gate in front of it).
  final Future<void> Function()? onSignOut;
}

/// Deep-link target for [ClerkAuthConfig.redirectionGenerator] — only OAuth
/// strategies get a bespoke redirect; other strategies (password/email code)
/// return null so they're unaffected.
Uri? _oauthRedirectUri(BuildContext context, Strategy strategy) {
  if (!strategy.isOauth) return null;
  return Uri(scheme: kOauthRedirectScheme, host: 'oauth', path: '/callback');
}

/// Auth-gated shell: Clerk sign-in when configured, else a configure prompt;
/// signed-in users bootstrap `GET /me` then see [signedInHome].
class AuthShell extends ConsumerWidget {
  const AuthShell({super.key, required this.signedInHome});

  /// Post-auth home (D2 library list).
  final Widget signedInHome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final testSession = ref.watch(testSessionProvider);
    if (testSession != null) {
      return _TestSignedInHost(
        session: testSession,
        signedInHome: signedInHome,
      );
    }

    final config = ref.watch(appConfigProvider);
    final persistor = ref.watch(securePersistorProvider);
    return _ProviderAuthGate(
      config: config,
      persistor: persistor,
      signedInHome: signedInHome,
    );
  }
}

/// A token refresh often has no email. Keep the one already saved.
FirebaseSession _withKnownEmail(FirebaseSession next, String? email) {
  if (next.email != null && next.email!.trim().isNotEmpty) return next;
  final known = email?.trim() ?? '';
  if (known.isEmpty) return next;
  return FirebaseSession(
    idToken: next.idToken,
    refreshToken: next.refreshToken,
    expiresAt: next.expiresAt,
    localId: next.localId,
    email: known,
    isNewUser: next.isNewUser,
  );
}

/// Loads the global auth provider, then mounts Clerk or Firebase.
class _ProviderAuthGate extends ConsumerStatefulWidget {
  const _ProviderAuthGate({
    required this.config,
    required this.persistor,
    required this.signedInHome,
  });

  final AppConfig config;
  final SecureStoragePersistor persistor;
  final Widget signedInHome;

  @override
  ConsumerState<_ProviderAuthGate> createState() => _ProviderAuthGateState();
}

class _ProviderAuthGateState extends ConsumerState<_ProviderAuthGate> {
  AuthBootstrap? _bootstrap;
  FirebaseSession? _firebaseSession;
  var _ready = false;
  var _startupRefreshDone = false;
  String? _setupEmail;

  /// The list is up. A reload must not open a library over it.
  var _showList = false;

  /// The sign-in form was opened from the list (Add account, or Back).
  var _returnToList = false;
  var _savedWithSession = 0;
  List<SavedAccount> _chooserAccounts = const [];
  String? _signInNotice;
  Timer? _watch;

  FirebaseAccountRoster _roster() {
    return FirebaseAccountRoster(
      secure: widget.persistor.store,
      directory: ref.read(accountDirectoryProvider),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
    if (Platform.environment['FLUTTER_TEST'] != 'true') {
      _watch = Timer.periodic(const Duration(seconds: 20), (_) => _load());
    }
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final bootstrap = await ref.read(authBootstrapProvider);
    if (!mounted) return;
    if (bootstrap == null && _bootstrap != null) return;
    final providerId =
        bootstrap?.providerId ?? (widget.config.hasClerkKey ? 'clerk' : null);
    final previous = _bootstrap?.providerId;
    if (previous != null && providerId != null && previous != providerId) {
      await widget.persistor.clearAll();
      await _roster().clear();
    }
    await reconcileStoredProvider(
      store: widget.persistor.store,
      nextProviderId: providerId,
      clearClerk: widget.persistor.clearAll,
    );
    FirebaseSession? restored = _firebaseSession;
    var notice = _signInNotice;
    String? setupEmail = _setupEmail;
    var showList = _showList;
    var savedWithSession = _savedWithSession;
    var chooser = _chooserAccounts;
    if (bootstrap?.isFirebase == true &&
        !_showList &&
        !_returnToList &&
        _firebaseSession == null) {
      final roster = _roster();
      final listed = await roster.accounts();
      final signedIn = [
        for (final account in listed)
          if (account.hasSession) account,
      ];
      savedWithSession = signedIn.length;
      chooser = signedIn;
      if (signedIn.length == 1) {
        restored = await roster.sessionFor(signedIn.single.localId);
        final firebase = bootstrap?.firebase;
        if (restored != null && !_startupRefreshDone && firebase != null) {
          _startupRefreshDone = true;
          final next = await _refreshSession(restored, firebase);
          if (next == null && _signInNotice != null) {
            notice = _signInNotice;
            setupEmail = restored.email ?? setupEmail;
            restored = null;
            showList = false;
            final again = await roster.accounts();
            final still = [
              for (final account in again)
                if (account.hasSession) account,
            ];
            savedWithSession = still.length;
            chooser = still;
            if (still.length >= 2) showList = true;
          } else if (next != null) {
            restored = next;
            showList = false;
          }
        }
      } else if (signedIn.length >= 2) {
        restored = null;
        showList = true;
      } else {
        restored = null;
        showList = false;
        if (setupEmail == null || setupEmail.isEmpty) {
          if (listed.length == 1) setupEmail = listed.single.email;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _bootstrap = bootstrap ?? _bootstrap;
      _firebaseSession = restored;
      _signInNotice = notice;
      _setupEmail = setupEmail;
      _showList = showList;
      _savedWithSession = savedWithSession;
      _chooserAccounts = chooser;
      _ready = true;
    });
  }

  Future<FirebaseSession?> _refreshSession(
    FirebaseSession session,
    FirebasePublicConfig firebase,
  ) async {
    try {
      final refreshed = await refreshFirebaseSession(
        config: firebase,
        refreshToken: session.refreshToken,
        httpClient: ref.read(authHttpClientProvider),
      ).timeout(const Duration(seconds: 5));
      final next = _withKnownEmail(refreshed, session.email);
      await _roster().remember(next);
      return next;
    } on FirebaseSessionRevoked {
      await _roster().dropSession(session.localId);
      _signInNotice = kAccountRemovedNotice;
      _setupEmail = session.email;
      return null;
    } on Object {
      // A timeout or a network error keeps the stored session.
      return session;
    }
  }

  Future<void> _onFirebaseSession(FirebaseSession session) async {
    await _roster().remember(session);
    final listed = await _roster().accounts();
    final signedIn = [
      for (final account in listed)
        if (account.hasSession) account,
    ];
    if (!mounted) return;
    setState(() {
      _returnToList = false;
      _showList = false;
      _setupEmail = null;
      _firebaseSession = session;
      _signInNotice = null;
      _savedWithSession = signedIn.length;
      _chooserAccounts = signedIn;
    });
  }

  /// Leaves the library for the account list. Tokens stay.
  Future<void> _showAccountList() async {
    final listed = await _roster().accounts();
    final signedIn = [
      for (final account in listed)
        if (account.hasSession) account,
    ];
    if (!mounted) return;
    setState(() {
      _chooserAccounts = signedIn;
      _savedWithSession = signedIn.length;
      _firebaseSession = null;
      _returnToList = false;
      _showList = signedIn.isNotEmpty;
      _signInNotice = null;
      _setupEmail = null;
    });
  }

  void _startAddAccount() {
    setState(() {
      _showList = false;
      _returnToList = _chooserAccounts.isNotEmpty;
      _firebaseSession = null;
      _signInNotice = null;
      _setupEmail = null;
    });
  }

  Future<void> _openSaved(SavedAccount account) async {
    final session = await _roster().sessionFor(account.localId);
    if (session == null || !mounted) return;
    final firebase = _bootstrap?.firebase;
    final next = firebase == null
        ? session
        : await _refreshSession(session, firebase);
    if (!mounted) return;
    if (next == null) {
      final listed = await _roster().accounts();
      final signedIn = [
        for (final saved in listed)
          if (saved.hasSession) saved,
      ];
      setState(() {
        _firebaseSession = null;
        _showList = false;
        _returnToList = signedIn.isNotEmpty;
        _chooserAccounts = signedIn;
        _savedWithSession = signedIn.length;
        _signInNotice = kAccountRemovedNotice;
        _setupEmail = account.email;
      });
      return;
    }
    setState(() {
      _firebaseSession = next;
      _showList = false;
      _returnToList = false;
      _signInNotice = null;
      _setupEmail = null;
    });
  }

  Future<void> _removeFromComputer(SavedAccount account) async {
    await _roster().removeFromComputer(account.localId);
    final listed = await _roster().accounts();
    final signedIn = [
      for (final saved in listed)
        if (saved.hasSession) saved,
    ];
    if (!mounted) return;
    setState(() {
      _chooserAccounts = signedIn;
      _savedWithSession = signedIn.length;
      _firebaseSession = null;
      if (signedIn.isEmpty) {
        _showList = false;
        _returnToList = false;
        _setupEmail = account.email;
        _signInNotice = null;
      } else {
        _showList = true;
      }
    });
  }

  Future<void> _showRemovedAccount(FirebaseSession? session) async {
    final id = session?.localId;
    if (id != null) await _roster().dropSession(id);
    final listed = await _roster().accounts();
    final signedIn = [
      for (final saved in listed)
        if (saved.hasSession) saved,
    ];
    if (!mounted) return;
    setState(() {
      _firebaseSession = null;
      _showList = false;
      _returnToList = signedIn.isNotEmpty;
      _chooserAccounts = signedIn;
      _savedWithSession = signedIn.length;
      _signInNotice = kAccountRemovedNotice;
      _setupEmail = session?.email;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const SignedOutFrame(
        child: CircularProgressIndicator(key: Key('auth-boot')),
      );
    }
    final bootstrap = _bootstrap;
    if (bootstrap != null && bootstrap.isFirebase) {
      final firebase = bootstrap.firebase;
      if (firebase == null) {
        return const _MissingFirebaseConfigPage();
      }
      final session = _firebaseSession;
      if (session == null && _showList) {
        return AccountChooserPage(
          accounts: _chooserAccounts,
          allowAdd: ref.watch(desktopPrefsProvider).allowAddAccount,
          onOpen: (account) => unawaited(_openSaved(account)),
          onRemove: (account) => unawaited(_removeFromComputer(account)),
          onAdd: _startAddAccount,
        );
      }
      if (session == null) {
        return FirebaseSignInPage(
          config: firebase,
          apiUrl: widget.config.apiUrl,
          notice: _signInNotice,
          initialEmail: _setupEmail,
          onCancel: _returnToList ? () => unawaited(_showAccountList()) : null,
          onAttempt: () {
            if (_signInNotice == null || !mounted) return;
            setState(() => _signInNotice = null);
          },
          httpClient: ref.watch(authHttpClientProvider),
          onSession: _onFirebaseSession,
        );
      }
      return _FirebaseSignedInHost(
        key: ValueKey(session.localId),
        config: widget.config,
        firebase: firebase,
        session: session,
        savedAccountCount: _savedWithSession,
        onSession: _onFirebaseSession,
        onSignOut: _showAccountList,
        onSessionRevoked: () => _showRemovedAccount(session),
        signedInHome: widget.signedInHome,
      );
    }

    final publishableKey =
        bootstrap?.clerkPublishableKey ?? widget.config.clerkPublishableKey;
    if (publishableKey == null || publishableKey.trim().isEmpty) {
      return const _MissingClerkConfigPage();
    }
    return _clerkAuthTree(
      publishableKey: publishableKey,
      persistor: widget.persistor,
      config: widget.config,
      signedInHome: widget.signedInHome,
    );
  }
}

Widget _clerkAuthTree({
  required String publishableKey,
  required SecureStoragePersistor persistor,
  required AppConfig config,
  required Widget signedInHome,
}) {
  return ClerkAuth(
    config: ClerkAuthConfig(
      publishableKey: publishableKey,
      persistor: persistor,
      httpConnectionTimeout: const Duration(seconds: 15),
      retryOptions: const RetryOptions(maxAttempts: 3),
      sessionTokenPolling: false,
      clientRefreshPeriod: Duration.zero,
      loading: const _ClerkBootLoading(),
      redirectionGenerator: Platform.isMacOS ? _oauthRedirectUri : null,
      deepLinkStream: Platform.isMacOS ? macosOauthDeepLinks() : null,
    ),
    child: ClerkErrorListener(
      child: ClerkAuthBuilder(
        signedOutBuilder: (context, authState) {
          return _ClerkSignedOutPage(authState: authState);
        },
        signedInBuilder: (context, authState) {
          return _ClerkSignedInHost(
            authState: authState,
            persistor: persistor,
            config: config,
            signedInHome: signedInHome,
          );
        },
      ),
    ),
  );
}

class _MissingFirebaseConfigPage extends StatelessWidget {
  const _MissingFirebaseConfigPage();

  @override
  Widget build(BuildContext context) {
    return const SignedOutFrame(
      child: Text(
        'Firebase is the sign-in provider, but its public client config is missing on the API.',
        key: Key('missing-firebase-config'),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _FirebaseSignedInHost extends ConsumerStatefulWidget {
  const _FirebaseSignedInHost({
    super.key,
    required this.config,
    required this.firebase,
    required this.session,
    required this.savedAccountCount,
    required this.onSession,
    required this.onSignOut,
    required this.onSessionRevoked,
    required this.signedInHome,
  });

  final AppConfig config;
  final FirebasePublicConfig firebase;
  final FirebaseSession session;
  final int savedAccountCount;
  final ValueChanged<FirebaseSession> onSession;
  final Future<void> Function() onSignOut;
  final Future<void> Function() onSessionRevoked;
  final Widget signedInHome;

  @override
  ConsumerState<_FirebaseSignedInHost> createState() =>
      _FirebaseSignedInHostState();
}

class _FirebaseSignedInHostState extends ConsumerState<_FirebaseSignedInHost> {
  late final ApiClient _client;
  late FirebaseSession _session;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _bindCatalog();
    _client = ApiClient(
      baseUrl: widget.config.apiUrl,
      tokenProvider: _token,
      httpClient: ref.read(authHttpClientProvider),
      clientIdentity: ref.read(clientIdentityProvider).headerValue,
      onClientTooOld: (_) {
        ref.read(forceUpdateRequiredProvider.notifier).state = true;
      },
    );
  }

  void _bindCatalog() {
    final store = ref.read(collectionsStoreProvider);
    store.accountKey = widget.session.localId;
    final cols = ref.read(collectionsControllerProvider);
    if (cols.loaded) {
      unawaited(cols.load());
    }
  }

  Future<String?> _token() async {
    final fresh = _session.expiresAt.isAfter(
      DateTime.now().toUtc().add(const Duration(seconds: 60)),
    );
    if (fresh) return _session.idToken;
    try {
      final next = _withKnownEmail(
        await refreshFirebaseSession(
          config: widget.firebase,
          refreshToken: _session.refreshToken,
          httpClient: ref.read(authHttpClientProvider),
        ),
        _session.email,
      );
      _session = next;
      widget.onSession(next);
      return next.idToken;
    } on FirebaseSessionRevoked {
      await widget.onSessionRevoked();
      return null;
    } on FirebaseAuthException {
      return null;
    }
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(_client),
        firebaseDeskProvider.overrideWithValue(
          FirebaseDesk(
            apiUrl: widget.config.apiUrl,
            config: widget.firebase,
            session: _session,
            savedAccountCount: widget.savedAccountCount,
            onSession: (next) {
              setState(() => _session = next);
              widget.onSession(next);
            },
            onSignOut: widget.onSignOut,
            onSwitchAccount: widget.onSignOut,
          ),
        ),
      ],
      child: AccountBootstrap(
        loadAccount: () => MeRepository(_client).getMe(),
        onUnauthorized: () {},
        onSignOut: () => widget.onSignOut(),
        signedInHome: widget.signedInHome,
      ),
    );
  }
}

/// Signed-out Clerk form, or a spinner while FAPI env is still empty.
///
/// `clerk_auth` times out the *first* `/environment` + `/client` fetch at 1s.
/// A cold Keychain (first launch, or after `./118_clear_secure_store.sh`)
/// makes a slightly slow Clerk reply leave [ClerkAuthentication] with
/// `isNotAvailable` (blank widget) and only retries every 10s — still with
/// that 1s cap. Refresh here uses the 15s HTTP timeout instead.
class _ClerkSignedOutPage extends StatefulWidget {
  const _ClerkSignedOutPage({required this.authState});

  final ClerkAuthState authState;

  @override
  State<_ClerkSignedOutPage> createState() => _ClerkSignedOutPageState();
}

class _ClerkSignedOutPageState extends State<_ClerkSignedOutPage> {
  Timer? _oauthWait;
  var _oauthTimedOut = false;
  var _oauthWasPending = false;
  var _oauthMisses = 0;
  var _oauthRetrying = false;

  @override
  void initState() {
    super.initState();
    widget.authState.addListener(_onAuth);
    _onAuth();
  }

  @override
  void didUpdateWidget(covariant _ClerkSignedOutPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.authState, widget.authState)) {
      oldWidget.authState.removeListener(_onAuth);
      widget.authState.addListener(_onAuth);
      _onAuth();
    }
  }

  @override
  void dispose() {
    widget.authState.removeListener(_onAuth);
    _oauthWait?.cancel();
    super.dispose();
  }

  bool get _oauthPending {
    if (kIsWeb || !Platform.isMacOS) return false;
    final signIn = widget.authState.signIn;
    if (signIn == null) return false;
    final verification = signIn.firstFactorVerification ?? signIn.verification;
    if (verification == null || verification.status.isVerified) {
      return false;
    }
    if (!verification.strategy.isOauth) return false;
    final url = verification.externalVerificationRedirectUrl;
    return url != null && url.isNotEmpty;
  }

  void _onAuth() {
    if (!mounted) return;
    if (_oauthRetrying) {
      setState(() {});
      return;
    }
    final pending = _oauthPending;
    if (pending && !_oauthWasPending) {
      _oauthWait?.cancel();
      _oauthTimedOut = false;
      _oauthWait = Timer(kMacOsOauthReturnTimeout, () {
        if (mounted && _oauthPending) {
          setState(() => _oauthTimedOut = true);
        }
      });
    } else if (!pending && _oauthWasPending) {
      _oauthWait?.cancel();
      _oauthTimedOut = false;
    }
    _oauthWasPending = pending;
    setState(() {});
  }

  Future<void> _retryOauth() async {
    _oauthWait?.cancel();
    setState(() {
      _oauthTimedOut = false;
      _oauthMisses += 1;
      _oauthRetrying = true;
    });
    try {
      await widget.authState.resetClient();
    } catch (e, st) {
      debugPrint('OAuth retry reset failed: $e\n$st');
    }
    if (!mounted) return;
    setState(() {
      _oauthRetrying = false;
      _oauthWasPending = _oauthPending;
      _oauthTimedOut = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.authState.isNotAvailable) {
      return _ClerkEnvRetry(authState: widget.authState);
    }
    final showOauthHint = _oauthPending || _oauthTimedOut;
    final clerkColumn = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ClerkAuthentication(),
        if (showOauthHint) ...[
          const SizedBox(height: 16),
          MacOsOauthReturnHint(
            timedOut: _oauthTimedOut,
            repeatMiss: _oauthMisses >= 1,
            onRetry: _retryOauth,
          ),
        ],
      ],
    );
    return SignedOutFrame(formWidth: 420, child: clerkColumn);
  }
}

class _ClerkEnvRetry extends StatefulWidget {
  const _ClerkEnvRetry({required this.authState});

  final ClerkAuthState authState;

  @override
  State<_ClerkEnvRetry> createState() => _ClerkEnvRetryState();
}

class _ClerkEnvRetryState extends State<_ClerkEnvRetry> {
  static const _retryDelay = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    unawaited(_retryUntilReady());
  }

  Future<void> _retryUntilReady() async {
    while (mounted && widget.authState.isNotAvailable) {
      try {
        await widget.authState.refreshEnvironment();
        if (!mounted) return;
        if (widget.authState.client.isEmpty) {
          await widget.authState.resetClient();
        } else {
          await widget.authState.refreshClient();
        }
      } catch (e, st) {
        debugPrint('Clerk env retry failed: $e\n$st');
      }
      if (!mounted || !widget.authState.isNotAvailable) return;
      await Future<void>.delayed(_retryDelay);
    }
  }

  @override
  Widget build(BuildContext context) => const _ClerkBootLoading();
}

/// Shown immediately while Clerk SDK initializes (network + secure store).
class _ClerkBootLoading extends StatelessWidget {
  const _ClerkBootLoading();

  @override
  Widget build(BuildContext context) {
    return const SignedOutFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            kAppName,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 16),
          CircularProgressIndicator(key: Key('clerk-boot-loading')),
          SizedBox(height: 16),
          Text('Loading sign-in…', key: Key('clerk-boot-loading-label')),
        ],
      ),
    );
  }
}

class _MissingClerkConfigPage extends StatelessWidget {
  const _MissingClerkConfigPage();

  @override
  Widget build(BuildContext context) {
    return SignedOutFrame(
      child: Text(
        'Set CLERK_PUBLISHABLE_KEY in .env (see mac/103_clerk-env.sh).',
        key: const Key('missing-clerk-config'),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _TestSignedInHost extends ConsumerStatefulWidget {
  const _TestSignedInHost({required this.session, required this.signedInHome});

  final TestSession session;
  final Widget signedInHome;

  @override
  ConsumerState<_TestSignedInHost> createState() => _TestSignedInHostState();
}

class _TestSignedInHostState extends ConsumerState<_TestSignedInHost> {
  late final ApiClient _client;

  @override
  void initState() {
    super.initState();
    _client = ApiClient(
      baseUrl: ref.read(appConfigProvider).apiUrl,
      tokenProvider: () => widget.session.token,
      clientIdentity: ref.read(clientIdentityProvider).headerValue,
      onClientTooOld: (_) {
        ref.read(forceUpdateRequiredProvider.notifier).state = true;
      },
    );
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(_client)],
      child: AccountBootstrap(
        loadAccount: () async {
          if (widget.session.meError != null) {
            throw widget.session.meError!;
          }
          if (widget.session.account != null) {
            return widget.session.account!;
          }
          return MeRepository(_client).getMe();
        },
        onUnauthorized: () {},
        onSignOut: widget.session.onSignOut,
        signedInHome: widget.signedInHome,
      ),
    );
  }
}

class _ClerkSignedInHost extends ConsumerStatefulWidget {
  const _ClerkSignedInHost({
    required this.authState,
    required this.persistor,
    required this.config,
    required this.signedInHome,
  });

  final ClerkAuthState authState;
  final SecureStoragePersistor persistor;
  final AppConfig config;
  final Widget signedInHome;

  @override
  ConsumerState<_ClerkSignedInHost> createState() => _ClerkSignedInHostState();
}

class _ClerkSignedInHostState extends ConsumerState<_ClerkSignedInHost> {
  late final ApiClient _client;

  @override
  void initState() {
    super.initState();
    _client = ApiClient(
      baseUrl: widget.config.apiUrl,
      tokenProvider: () async {
        final token = await widget.authState.sessionToken();
        return token.jwt;
      },
      clientIdentity: ref.read(clientIdentityProvider).headerValue,
      onClientTooOld: (_) {
        ref.read(forceUpdateRequiredProvider.notifier).state = true;
      },
    );
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _signOut() async {
    await widget.authState.signOut();
    await widget.persistor.clearAll();
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(_client)],
      child: AccountBootstrap(
        loadAccount: () => MeRepository(_client).getMe(),
        // Do not auto-sign-out on /me 401 — that flashes back to Clerk login and
        // hides the real failure (often CLERK_AUTHORIZED_PARTIES / azp mismatch).
        onUnauthorized: () {},
        onSignOut: _signOut,
        // Debug-only: copy Clerk session JWT for local scripts (e.g. person link loop).
        fetchApiToken: () async {
          final token = await widget.authState.sessionToken();
          return token.jwt;
        },
        signedInHome: widget.signedInHome,
      ),
    );
  }
}

/// Loads `GET /me` once, then shows [signedInHome] with account chrome.
class AccountBootstrap extends ConsumerStatefulWidget {
  const AccountBootstrap({
    super.key,
    required this.loadAccount,
    required this.onUnauthorized,
    required this.signedInHome,
    this.onSignOut,
    this.fetchApiToken,
  });

  final Future<Account> Function() loadAccount;
  final Future<void> Function()? onSignOut;

  /// Debug helper for local scripts — returns current Clerk session JWT.
  final Future<String?> Function()? fetchApiToken;
  final VoidCallback onUnauthorized;
  final Widget signedInHome;

  @override
  ConsumerState<AccountBootstrap> createState() => _AccountBootstrapState();
}

class _AccountBootstrapState extends ConsumerState<AccountBootstrap> {
  late Future<Account> _future = _load();

  Future<Account> _load() {
    return widget.loadAccount().then((account) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(clientSupportProvider.notifier).state = account.clientSupport;
      });
      return account;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Account>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(key: Key('account-loading')),
            ),
          );
        }
        if (snapshot.hasError) {
          final error = snapshot.error!;
          if (error is ClientTooOldException) {
            return UpdateRequiredPage(
              support: null,
              onSignOut: widget.onSignOut,
              launchUrl: ref.read(checkoutUrlLauncherProvider),
            );
          }
          if (error is UnauthorizedException) {
            return SignedOutFrame(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Could not authorize with tagkin-api (401): $error\n\n'
                    'Confirm tagkin-api is running with the same sign-in '
                    'provider, then Retry. If an operator switched the '
                    'provider, Sign out and sign in again.',
                    key: const Key('auth-unauthorized'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('account-retry'),
                    onPressed: () {
                      setState(() {
                        _future = _load();
                      });
                    },
                    child: const Text('Retry'),
                  ),
                  if (widget.onSignOut != null) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      key: const Key('auth-sign-out'),
                      onPressed: () => widget.onSignOut!(),
                      child: const Text('Sign out'),
                    ),
                  ],
                ],
              ),
            );
          }
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Could not load account: $error',
                      key: const Key('account-error'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const Key('account-retry'),
                      onPressed: () {
                        setState(() {
                          _future = _load();
                        });
                      },
                      child: const Text('Retry'),
                    ),
                    if (widget.onSignOut != null) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => widget.onSignOut!(),
                        child: const Text('Sign out'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }

        final account = snapshot.data!;
        if (account.clientSupport?.status == ClientSupportStatus.blocked) {
          return UpdateRequiredPage(
            support: account.clientSupport,
            onSignOut: widget.onSignOut,
            launchUrl: ref.read(checkoutUrlLauncherProvider),
          );
        }
        return _SignedInScaffold(
          account: account,
          onSignOut: widget.onSignOut,
          fetchApiToken: widget.fetchApiToken,
          child: widget.signedInHome,
        );
      },
    );
  }
}

class _SignedInScaffold extends ConsumerStatefulWidget {
  const _SignedInScaffold({
    required this.account,
    required this.child,
    this.onSignOut,
    this.fetchApiToken,
  });

  final Account account;
  final Widget child;
  final Future<void> Function()? onSignOut;
  final Future<String?> Function()? fetchApiToken;

  @override
  ConsumerState<_SignedInScaffold> createState() => _SignedInScaffoldState();
}

class _SignedInScaffoldState extends ConsumerState<_SignedInScaffold>
    with WidgetsBindingObserver, WindowListener {
  /// In-app gear is Windows-only; macOS uses the app menu → Settings… in the menu bar.
  bool get _showSettingsGear => !kIsWeb && Platform.isWindows;

  bool _settingsOpen = false;
  bool _itemListExportOpen = false;

  /// Lazily mount Faces/Persons the first time the user visits them so their
  /// [State] survives subsequent tab switches (scroll, filters, selections).
  final Set<TopLevelTab> _mountedTabs = {TopLevelTab.folders};

  /// Avoid re-scheduling first-run mint every frame while the spinner shows.
  bool _collectionBootstrapRequested = false;

  /// Last applied collection uiEpoch (Folders look restore).
  int _lastAppliedUiEpoch = -1;
  bool _applyingCollectionUi = false;
  LibraryTableController? _libraryLookSource;

  bool _windowCloseGateActive = false;

  /// Set before [windowManager.destroy] so [didRequestAppExit] allows terminate
  /// (macOS destroy → NSApp.terminate; gate alone would cancel exit).
  bool _quitConfirmed = false;
  Future<bool>? _leavePromptFuture;
  Future<void>? _windowCloseInFlight;

  bool get _desktopWindowCloseSupported =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onHardwareKeyForFacesSelectAll);
    unawaited(_enableWindowCloseGate());
    // Riverpod forbids provider writes in initState. Set account id first,
    // then restore checkpoints + unfinished library items.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(signedInAccountIdProvider.notifier).state = widget.account.id;
      if (Platform.environment.containsKey('FLUTTER_TEST')) return;
      unawaited(ref.read(folderIngestQueueProvider).restoreOnSignIn());
      unawaited(_promptTrialIfNeverHadCredits());
    });
  }

  /// Opens **Get your free credits** when the pack is available and this
  /// account has never received credits. A failed fetch leaves the library up.
  Future<void> _promptTrialIfNeverHadCredits() async {
    try {
      final summary = await ref.read(creditsRepositoryProvider).getTrial();
      if (!mounted || !TrialFirstLoginPrompt.shouldPrompt(summary)) return;
      await pushTrialCardPage(context);
    } catch (_) {
      // A failed fetch leaves the library up.
    }
  }

  /// Cmd+A on Faces must expand loose face selection even when focus is not
  /// under Faces (face taps do not take focus; SelectionArea would steal it).
  bool _onHardwareKeyForFacesSelectAll(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyA) return false;
    if (!HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isControlPressed) {
      return false;
    }
    if (!mounted) return false;
    if (ref.read(activeTopLevelTabProvider) != TopLevelTab.faces) {
      return false;
    }
    final focusCtx = FocusManager.instance.primaryFocus?.context;
    if (focusCtx != null &&
        (focusCtx.widget is EditableText ||
            focusCtx.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return false;
    }
    final selectAll = facesSelectAllLooseHandler;
    if (selectAll == null) return false;
    selectAll();
    return true;
  }

  Future<void> _enableWindowCloseGate() async {
    if (!_desktopWindowCloseSupported) return;
    // Widget tests pump the shell without window_manager.ensureInitialized.
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      await windowManager.setPreventClose(true);
      if (!mounted) {
        try {
          await windowManager.setPreventClose(false);
        } catch (_) {}
        return;
      }
      windowManager.addListener(this);
      _windowCloseGateActive = true;
      signedInQuitHandlerReady = true;
    } catch (_) {
      // Plugin missing or not ready — fall back to didRequestAppExit only.
    }
  }

  /// Drop the signed-in close intercept. Sign-out must call this: otherwise
  /// [windowManager.setPreventClose] stays true with no [WindowListener], and
  /// the traffic-light / title-bar close button appears to do nothing.
  Future<void> _disarmWindowCloseGate() async {
    if (_windowCloseGateActive) {
      try {
        windowManager.removeListener(this);
      } catch (_) {}
      _windowCloseGateActive = false;
    }
    signedInQuitHandlerReady = false;
    if (!_desktopWindowCloseSupported) return;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      await windowManager.setPreventClose(false);
    } catch (_) {}
  }

  /// Disarm the close gate, then terminate. Must clear [_windowCloseGateActive]
  /// and set [_quitConfirmed] before [windowManager.destroy]: on macOS destroy
  /// is NSApp.terminate, which re-enters [didRequestAppExit]; leaving the gate
  /// armed cancels that exit (Save/Discard appear to "work" but the app stays).
  Future<void> _allowCloseAndQuit() async {
    if (!_windowCloseGateActive && !_quitConfirmed) return;
    _quitConfirmed = true;
    await _disarmWindowCloseGate();
    try {
      await windowManager.destroy();
    } catch (_) {}
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKeyForFacesSelectAll);
    unawaited(_disarmWindowCloseGate());
    _libraryLookSource?.removeListener(_onLibraryLookChanged);
    _libraryLookSource?.onViewFiltersChanged = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _ensureLibraryLookSync(LibraryTableController table) {
    if (identical(_libraryLookSource, table)) return;
    _libraryLookSource?.removeListener(_onLibraryLookChanged);
    _libraryLookSource?.onViewFiltersChanged = null;
    _libraryLookSource = table;
    table.addListener(_onLibraryLookChanged);
    table.onViewFiltersChanged = _onViewFiltersChanged;
    table.ensureLoaded();
  }

  void _onLibraryLookChanged() {
    _syncActiveViewDirty();
    if (!mounted || _applyingCollectionUi) return;
    final cols = ref.read(collectionsControllerProvider);
    if (!cols.sessionReady) return;
    final table = _libraryLookSource;
    if (table == null) return;
    cols.updateLibraryLook(table.captureCollectionLibraryUi());
  }

  void _syncActiveViewDirty() {
    if (!mounted) return;
    var dirty = false;
    try {
      dirty = ref.read(libraryTableControllerProvider).isActiveViewModified;
    } catch (_) {}
    if (ref.read(activeViewDirtyProvider) != dirty) {
      ref.read(activeViewDirtyProvider.notifier).state = dirty;
    }
  }

  Future<void> _persistDirtyNamedView() async {
    try {
      final table = ref.read(libraryTableControllerProvider);
      final cols = ref.read(collectionsControllerProvider);
      if (table.isActiveViewModified) {
        await saveNamedActiveView(table: table, cols: cols);
      }
    } catch (_) {}
    _syncActiveViewDirty();
  }

  Future<void> _onViewFiltersChanged() async {
    if (!mounted || _applyingCollectionUi) return;
    final cols = ref.read(collectionsControllerProvider);
    if (!cols.sessionReady) return;
    final table = _libraryLookSource;
    if (table == null) return;
    if (table.activeViewId != null) return;
    await commitActiveView(table: table, cols: cols);
  }

  /// Applies the collection's saved Folders look and folds any auto-expand
  /// into the baseline (not dirty). Must wait for the table's first real
  /// [LibraryTableController.load] first: computing/adopting a baseline
  /// against zero rows (login is faster than the initial library fetch),
  /// then having real rows trigger auto-expand moments later, made every
  /// fresh session look dirty immediately after sign-in.
  Future<void> _applyCollectionUiIfNeeded(CollectionsController cols) async {
    if (!cols.sessionReady) return;
    if (cols.uiEpoch == _lastAppliedUiEpoch) return;
    _lastAppliedUiEpoch = cols.uiEpoch;
    _applyingCollectionUi = true;
    try {
      final table = ref.read(libraryTableControllerProvider);
      await table.runViewCommitPaused(() async {
        await table.ensureLoaded();
        if (!mounted) return;
        await table.applyCollectionLibraryUi(cols.current.ui.library);
        if (!mounted) return;
        await applyCurrentCollectionView(
          table: table,
          prefs: ref.read(desktopPrefsControllerProvider),
          cols: cols,
        );
        if (!mounted) return;
        // Open folders live on the view. Capture keeps the collection's
        // saved expand list so auto-expand and a user toggle do not dirty it.
        cols.adoptLibraryLook(table.captureCollectionLibraryUi());
      });
    } finally {
      _applyingCollectionUi = false;
      _syncActiveViewDirty();
    }
  }

  /// Shared leave prompt so Sign out / window close / Quit await one dialog.
  ///
  /// Must `await` the inner call before returning: a bare `return future;`
  /// inside try/finally lets `finally` run synchronously (before
  /// `_leavePromptFuture` is even assigned below), latching a stale resolved
  /// Future in `_leavePromptFuture` forever and making every later Sign
  /// out / window-close / Quit short-circuit on the first cached answer.
  Future<bool> _confirmLeaveIfDirty() {
    final existing = _leavePromptFuture;
    if (existing != null) return existing;
    final future = () async {
      try {
        final confirmExport = itemListConfirmLeaveIfBusy;
        if (confirmExport != null) {
          final exportOk = await confirmExport();
          if (!exportOk) return false;
        }
        final exports = ref.read(itemListExportJobManagerProvider);
        if (exports.hasActive) {
          if (!mounted) return false;
          final quitExports = await confirmQuitItemListExports(
            context: context,
            activeCount: exports.activeCount,
          );
          if (!quitExports) return false;
          await exports.cancelAll();
        }
        final viewOk = await _confirmLeaveIfViewDirty();
        if (!viewOk) return false;
        final cols = ref.read(collectionsControllerProvider);
        if (!cols.dirty) return true;
        if (!mounted) return false;
        return await cols.confirmLeaveIfDirty(
          resolveDirty: _presentDirtyPrompt,
        );
      } finally {
        _leavePromptFuture = null;
      }
    }();
    _leavePromptFuture = future;
    return future;
  }

  Future<DirtyPromptChoice> _presentDirtyPrompt() {
    if (!mounted) return Future.value(DirtyPromptChoice.cancel);
    return showDirtyLeaveOverlayPrompt(context);
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    // Prefer onWindowClose / custom Quit for dirty confirm (avoids poisoning
    // after Cancel — flutter#141377). System Shut Down / Restart / Log Out
    // often terminate here without onWindowClose; blanket-cancel blocks macOS.
    if (_quitConfirmed) return AppExitResponse.exit;
    if (_windowCloseGateActive) {
      final cols = ref.read(collectionsControllerProvider);
      final viewDirty = _isActiveViewModified();
      if (appExitCanSkipLeavePrompt(
        collectionDirty: cols.dirty,
        viewDirty: viewDirty,
        exportBusy:
            itemListExportBusy ||
            ref.read(itemListExportJobManagerProvider).hasActive,
      )) {
        _quitConfirmed = true;
        await _disarmWindowCloseGate();
        return AppExitResponse.exit;
      }
      unawaited(_handleWindowClose());
      return AppExitResponse.cancel;
    }
    final ok = await _confirmLeaveIfDirty();
    return ok ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  @override
  void onWindowClose() {
    unawaited(_handleWindowClose());
  }

  @override
  void onWindowFocus() {
    _requestFoldersUsageRefresh();
  }

  Future<void> _handleWindowClose() {
    final existing = _windowCloseInFlight;
    if (existing != null) return existing;
    final future = () async {
      try {
        if (!_windowCloseGateActive) return;
        final ok = await _confirmLeaveIfDirty();
        if (!ok) return;
        if (!mounted) return;
        await _allowCloseAndQuit();
      } finally {
        _windowCloseInFlight = null;
      }
    }();
    _windowCloseInFlight = future;
    return future;
  }

  Future<void> _signOut() async {
    final handler = widget.onSignOut;
    if (handler == null) return;
    final ok = await _confirmLeaveIfDirty();
    if (!ok) return;
    if (!mounted) return;
    ref.read(collectionsControllerProvider).clearSession();
    ref.read(activeViewDirtyProvider.notifier).state = false;
    _collectionBootstrapRequested = false;
    await _disarmWindowCloseGate();
    await handler();
  }

  List<String> _libraryFolders() {
    try {
      final table = ref.read(libraryTableControllerProvider);
      return distinctLeafFolders(table.allRows.map((r) => r.item));
    } catch (_) {
      return const [];
    }
  }

  Future<void> _runCollectionCommand(CollectionMenuRequest req) async {
    const switchers = {
      CollectionMenuCommand.newCollection,
      CollectionMenuCommand.open,
      CollectionMenuCommand.openRecent,
      CollectionMenuCommand.delete,
    };
    if (switchers.contains(req.command)) {
      final ok = await _confirmLeaveIfViewDirty();
      if (!ok) return;
      if (!mounted) return;
    }
    if (req.command == CollectionMenuCommand.save ||
        req.command == CollectionMenuCommand.saveAs) {
      await _persistDirtyNamedView();
      if (!mounted) return;
    }
    final cols = ref.read(collectionsControllerProvider);
    await runCollectionMenuCommand(
      context: context,
      cols: cols,
      command: req.command,
      libraryFolders: _libraryFolders(),
      recentCollectionId: req.recentCollectionId,
    );
  }

  bool _isActiveViewModified() {
    try {
      return ref.read(libraryTableControllerProvider).isActiveViewModified;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _confirmLeaveIfViewDirty() async {
    if (!mounted) return false;
    try {
      final table = ref.read(libraryTableControllerProvider);
      final cols = ref.read(collectionsControllerProvider);
      final prefs = ref.read(desktopPrefsControllerProvider);
      return await confirmLeaveIfViewDirty(
        context: context,
        table: table,
        cols: cols,
        prefs: prefs,
      );
    } catch (_) {
      return true;
    }
  }

  Future<bool> _confirmLeaveFoldersIfViewDirty(TopLevelTab tab) async {
    final current = ref.read(activeTopLevelTabProvider);
    if (current != TopLevelTab.folders || tab == TopLevelTab.folders) {
      return true;
    }
    return _confirmLeaveIfViewDirty();
  }

  void _selectTab(TopLevelTab tab) {
    if (!_mountedTabs.contains(tab)) {
      setState(() => _mountedTabs.add(tab));
    }
    ref.read(activeTopLevelTabProvider.notifier).state = tab;
  }

  Future<void> _copyApiToken() async {
    final fetch = widget.fetchApiToken;
    if (fetch == null) return;
    try {
      final jwt = await fetch();
      if (!mounted) return;
      if (jwt == null || jwt.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No API token (signed out?)')),
        );
        return;
      }
      await Clipboard.setData(ClipboardData(text: jwt));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'API token copied — expires quickly; paste into TAGKIN_API_TOKEN now',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not copy token: $e')));
    }
  }

  void _requestFoldersUsageRefresh() {
    if (!mounted) return;
    if (ref.read(activeTopLevelTabProvider) != TopLevelTab.folders) return;
    ref.read(foldersUsageRefreshTickProvider.notifier).update((n) => n + 1);
  }

  Future<void> _openSettings() async {
    if (_settingsOpen) return;
    _settingsOpen = true;
    try {
      await pushSettingsPage(context);
    } finally {
      _settingsOpen = false;
      _requestFoldersUsageRefresh();
    }
  }

  Future<void> _openItemListExport() async {
    if (_itemListExportOpen) return;
    _itemListExportOpen = true;
    try {
      await pushItemListExportPage(context);
    } finally {
      _itemListExportOpen = false;
      _requestFoldersUsageRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(openSettingsTickProvider, (previous, next) {
      if (previous == null || previous == next) return;
      if (!mounted) return;
      _openSettings();
    });

    ref.listen<int>(openItemListExportTickProvider, (previous, next) {
      if (previous == null || previous == next) return;
      if (!mounted) return;
      unawaited(_openItemListExport());
    });

    ref.listen<int>(quitAppTickProvider, (previous, next) {
      if (previous == null || previous == next) return;
      if (!mounted) return;
      unawaited(_handleWindowClose());
    });

    ref.listen<CollectionMenuRequest?>(collectionMenuRequestProvider, (
      previous,
      next,
    ) {
      if (next == null) return;
      if (previous?.nonce == next.nonce) return;
      if (!mounted) return;
      unawaited(_runCollectionCommand(next));
    });

    final support =
        ref.watch(clientSupportProvider) ?? widget.account.clientSupport;
    final blocked =
        ref.watch(forceUpdateRequiredProvider) ||
        support?.status == ClientSupportStatus.blocked;
    final desk = ref.watch(firebaseDeskProvider);
    final allowAdd = ref.watch(desktopPrefsProvider).allowAddAccount;
    final offerSwitch =
        desk != null && (desk.savedAccountCount >= 2 || allowAdd);
    final offerClerkSignOut = widget.onSignOut != null && desk == null;
    if (blocked) {
      return UpdateRequiredPage(
        support: support,
        onSignOut: (offerSwitch || offerClerkSignOut) ? widget.onSignOut : null,
        leaveLabel: offerSwitch ? 'Switch account' : 'Sign out',
        launchUrl: ref.watch(checkoutUrlLauncherProvider),
      );
    }
    final cols = ref.watch(collectionsControllerProvider);
    final table = ref.watch(libraryTableControllerProvider);
    final libraryFolders = distinctLeafFolders(
      table.allRows.map((r) => r.item),
    );

    // Empty → mint Collection1; else resume currentCollectionId; else start gate.
    if (cols.loaded && !cols.sessionReady && !_collectionBootstrapRequested) {
      _collectionBootstrapRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final c = ref.read(collectionsControllerProvider);
        if (c.sessionReady) return;
        await c.bootstrapSession(libraryFolders);
      });
    } else if (cols.sessionReady &&
        cols.current.leafFolders.isEmpty &&
        libraryFolders.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await ref
            .read(collectionsControllerProvider)
            .fillMembershipIfEmpty(libraryFolders);
      });
    }

    final activeTab = ref.watch(activeTopLevelTabProvider);
    if (!_mountedTabs.contains(activeTab)) {
      _mountedTabs.add(activeTab);
    }

    if (cols.loaded && !cols.sessionReady && cols.collections.isNotEmpty) {
      return CollectionStartGate(
        libraryFolders: libraryFolders,
        onSignOut: (offerSwitch || offerClerkSignOut) ? _signOut : null,
        leaveLabel: offerSwitch ? 'Switch account' : 'Sign out',
      );
    }

    if (!cols.sessionReady) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            key: Key('collection-session-loading'),
          ),
        ),
      );
    }

    // Sync collection membership to library grow, then filter.
    // Also restore Folders look when the collection uiEpoch advances.
    // Do not shrink membership from allRows — that list follows the table
    // status filter and would drop pending ingest leaves. Ingest publishes
    // membership from an unfiltered listItems when registering finishes.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final c = ref.read(collectionsControllerProvider);
      if (!c.sessionReady) return;
      final lib = ref.read(libraryTableControllerProvider);
      _ensureLibraryLookSync(lib);
      unawaited(_applyCollectionUiIfNeeded(c));
      final folders = distinctLeafFolders(
        lib.allRows.map((r) => r.item),
      ).toSet();
      if (c.current.leafFolders.isEmpty && folders.isNotEmpty) {
        await c.fillMembershipIfEmpty(folders.toList());
        if (!mounted) return;
      } else {
        c.adoptUnownedFolders(folders);
      }
      ref
          .read(libraryTableControllerProvider)
          .setCollectionLeafFolders(c.current.leafFolders.toSet());
    });

    final showWindowsFileMenu = !kIsWeb && Platform.isWindows;

    return Scaffold(
      appBar: AppBar(
        title: SelectionContainer.disabled(
          child: Row(
            children: [
              const Text(kAppName),
              if (cols.chromeLabel.isNotEmpty) ...[
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    cols.chromeLabel,
                    key: const Key('shell-collection-label'),
                    style: Theme.of(context).textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          SelectionContainer.disabled(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (kDebugMode && widget.fetchApiToken != null)
                  IconButton(
                    key: const Key('nav-copy-api-token'),
                    tooltip: 'Copy API token (debug)',
                    onPressed: _copyApiToken,
                    icon: const Icon(Icons.key_outlined),
                  ),
                if (_showSettingsGear)
                  IconButton(
                    key: const Key('nav-settings'),
                    tooltip: 'Settings',
                    onPressed: _openSettings,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                IconButton(
                  key: const Key('nav-item-list-export'),
                  tooltip: 'Export Views',
                  onPressed: () => unawaited(_openItemListExport()),
                  icon: const Icon(Icons.ios_share_outlined),
                ),
                if (showWindowsFileMenu)
                  PopupMenuButton<CollectionMenuCommand>(
                    key: const Key('windows-file-menu'),
                    tooltip: 'File',
                    onSelected: (cmd) {
                      requestCollectionMenu(ref, cmd);
                    },
                    itemBuilder: (context) {
                      final recents = cols.recentCollections;
                      return [
                        const PopupMenuItem(
                          value: CollectionMenuCommand.newCollection,
                          child: Text('New Collection…'),
                        ),
                        const PopupMenuItem(
                          value: CollectionMenuCommand.open,
                          child: Text('Open Collection…'),
                        ),
                        for (final c in recents)
                          PopupMenuItem<CollectionMenuCommand>(
                            onTap: () {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                requestCollectionMenu(
                                  ref,
                                  CollectionMenuCommand.openRecent,
                                  recentCollectionId: c.id,
                                );
                              });
                            },
                            child: Text('Recent: ${c.name}'),
                          ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: CollectionMenuCommand.save,
                          enabled:
                              cols.dirty || ref.watch(activeViewDirtyProvider),
                          child: const Text('Save Collection'),
                        ),
                        const PopupMenuItem(
                          value: CollectionMenuCommand.saveAs,
                          child: Text('Save Collection as…'),
                        ),
                        const PopupMenuItem(
                          value: CollectionMenuCommand.rename,
                          child: Text('Rename Collection…'),
                        ),
                        const PopupMenuItem(
                          value: CollectionMenuCommand.delete,
                          child: Text('Delete Collection…'),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: CollectionMenuCommand.addFolder,
                          child: Text('Add Folder to Collection…'),
                        ),
                        const PopupMenuItem(
                          value: CollectionMenuCommand.removeFolder,
                          child: Text('Remove Folder from Collection…'),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem<CollectionMenuCommand>(
                          onTap: () {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              requestOpenItemListExport(ref);
                            });
                          },
                          child: const Text('Export Views…'),
                        ),
                      ];
                    },
                    icon: const Icon(Icons.menu),
                  ),
                AppNavTabButtons(
                  onSelected: _selectTab,
                  onBeforeNavigate: _confirmLeaveFoldersIfViewDirty,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Center(
                    child: Text(
                      widget.account.email ?? widget.account.id,
                      key: const Key('account-label'),
                    ),
                  ),
                ),
                if (offerClerkSignOut)
                  IconButton(
                    key: const Key('sign-out'),
                    tooltip: 'Sign out',
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout),
                  ),
                if (offerSwitch)
                  IconButton(
                    key: const Key('switch-account'),
                    tooltip: 'Switch account',
                    onPressed: _signOut,
                    icon: const Icon(Icons.switch_account),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClientUpdateBanner(launchUrl: ref.watch(checkoutUrlLauncherProvider)),
          const FolderIngestStatusBanner(),
          Expanded(
            // Offstage IndexedStack siblings must not participate in
            // app-wide SelectionArea (Cmd+A / right-click Copy on Faces).
            child: SelectionContainer.disabled(
              child: IndexedStack(
                index: activeTab.index,
                children: [
                  widget.child,
                  _mountedTabs.contains(TopLevelTab.faces)
                      ? const FaceCropTraysPage()
                      : const SizedBox.shrink(),
                  _mountedTabs.contains(TopLevelTab.persons)
                      ? const PersonsListPage()
                      : const SizedBox.shrink(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
