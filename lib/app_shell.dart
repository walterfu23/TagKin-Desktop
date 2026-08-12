import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show AppExitResponse;

import 'package:app_links/app_links.dart';
import 'package:clerk_auth/clerk_auth.dart' show RetryOptions, Strategy;
import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/api/comments_repository.dart';
import 'package:tagkin_desktop/api/corrections_repository.dart';
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/api/jobs_repository.dart';
import 'package:tagkin_desktop/api/me_repository.dart';
import 'package:tagkin_desktop/api/persons_repository.dart';
import 'package:tagkin_desktop/api/usage_repository.dart';
import 'package:tagkin_desktop/auth/secure_persistor.dart';
import 'package:tagkin_desktop/config/app_config.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/collection_navigation.dart';
import 'package:tagkin_desktop/persons/collection_start_gate.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/dirty_leave_prompt.dart';
import 'package:tagkin_desktop/persons/face_crop_folder_scope.dart';
import 'package:tagkin_desktop/persons/face_crop_trays_page.dart';
import 'package:tagkin_desktop/persons/persons_list_page.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/prefs/settings_navigation.dart';
import 'package:tagkin_desktop/ingest/folder_ingest_status_banner.dart';
import 'package:tagkin_desktop/shell/quit_navigation.dart';
import 'package:window_manager/window_manager.dart';

/// Top-level signed-in destinations (Folders / Faces / Persons).
enum TopLevelTab { folders, faces, persons }

/// Which top-level tab is visible in [_SignedInScaffold].
final activeTopLevelTabProvider =
    StateProvider<TopLevelTab>((ref) => TopLevelTab.folders);

/// App-wide config (overridable in tests).
final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.load());

/// Secure Clerk persistor (overridable with [MemorySecureKeyValueStore] in tests).
final securePersistorProvider = Provider<SecureStoragePersistor>((ref) {
  return SecureStoragePersistor();
});

/// Optional override: when non-null, the shell skips live Clerk and uses this
/// session (unit/widget/integration tests).
final testSessionProvider = Provider<TestSession?>((ref) => null);

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

/// Tagging & jobs lifecycle API (D7). Override in tests with a fake;
/// otherwise built from [apiClientProvider].
final jobsRepositoryProvider = Provider<JobsRepository>(
  (ref) => JobsRepository(ref.watch(apiClientProvider)),
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

/// Custom URL scheme macOS routes OAuth callbacks back into the app through
/// (registered in `macos/Runner/Info.plist` `CFBundleURLTypes`).
const _oauthRedirectScheme = 'tagkindesktop';

/// Deep-link target for [ClerkAuthConfig.redirectionGenerator] — only OAuth
/// strategies get a bespoke redirect; other strategies (password/email code)
/// return null so they're unaffected.
Uri? _oauthRedirectUri(BuildContext context, Strategy strategy) {
  if (!strategy.isOauth) return null;
  return Uri(scheme: _oauthRedirectScheme, host: 'oauth', path: '/callback');
}

/// Auth-gated shell: Clerk sign-in when configured, else a configure prompt;
/// signed-in users bootstrap `GET /me` then see [signedInHome].
class AuthShell extends ConsumerWidget {
  const AuthShell({
    super.key,
    required this.signedInHome,
  });

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
    if (!config.hasClerkKey) {
      return const _MissingClerkConfigPage();
    }

    final persistor = ref.watch(securePersistorProvider);
    return ClerkAuth(
      config: ClerkAuthConfig(
        publishableKey: config.clerkPublishableKey!,
        persistor: persistor,
        // Default httpConnectionTimeout is 500ms with 8 retries — a slightly
        // slow Clerk reachability check burns >5s before the login form appears.
        httpConnectionTimeout: const Duration(seconds: 15),
        retryOptions: const RetryOptions(maxAttempts: 3),
        sessionTokenPolling: false,
        loading: const _ClerkBootLoading(),
        // macOS only: send OAuth (Google, etc.) to the system browser instead
        // of the in-app WKWebView popup. The embedded webview hits an
        // unresolved Flutter/AppKit bug where an unhandled keyboard event can
        // be redispatched in an infinite loop, which can peg WindowServer
        // hard enough to freeze the whole desktop, not just this app (see
        // flutter/flutter#170316, #184557). Windows uses WebView2, not
        // WKWebView, so it is not affected and keeps the in-app popup.
        redirectionGenerator: Platform.isMacOS ? _oauthRedirectUri : null,
        deepLinkStream: Platform.isMacOS ? AppLinks().uriLinkStream : null,
      ),
      child: ClerkErrorListener(
        child: ClerkAuthBuilder(
          signedOutBuilder: (context, authState) {
            return const Scaffold(
              body: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(24),
                    child: ClerkAuthentication(),
                  ),
                ),
              ),
            );
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
}

/// Shown immediately while Clerk SDK initializes (network + secure store).
class _ClerkBootLoading extends StatelessWidget {
  const _ClerkBootLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'TagKin',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 16),
            CircularProgressIndicator(key: Key('clerk-boot-loading')),
            SizedBox(height: 16),
            Text(
              'Loading sign-in…',
              key: Key('clerk-boot-loading-label'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingClerkConfigPage extends StatelessWidget {
  const _MissingClerkConfigPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Set CLERK_PUBLISHABLE_KEY in .env (see mac/103_clerk-env.sh).',
            key: const Key('missing-clerk-config'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
    );
  }
}

class _TestSignedInHost extends ConsumerStatefulWidget {
  const _TestSignedInHost({
    required this.session,
    required this.signedInHome,
  });

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
      overrides: [
        apiClientProvider.overrideWithValue(_client),
      ],
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

class _ClerkSignedInHost extends StatefulWidget {
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
  State<_ClerkSignedInHost> createState() => _ClerkSignedInHostState();
}

class _ClerkSignedInHostState extends State<_ClerkSignedInHost> {
  late final ApiClient _client = ApiClient(
    baseUrl: widget.config.apiUrl,
    tokenProvider: () async {
      final token = await widget.authState.sessionToken();
      return token.jwt;
    },
  );

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
      overrides: [
        apiClientProvider.overrideWithValue(_client),
      ],
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
class AccountBootstrap extends StatefulWidget {
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
  State<AccountBootstrap> createState() => _AccountBootstrapState();
}

class _AccountBootstrapState extends State<AccountBootstrap> {
  late Future<Account> _future = widget.loadAccount();

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
          if (error is UnauthorizedException) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Could not authorize with tagkin-api (401): $error\n\n'
                        'Confirm tagkin-api is running with the same Clerk JWT '
                        'public key, then Retry. If this persists after an API '
                        'restart, Sign out and sign in again.',
                        key: const Key('auth-unauthorized'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        key: const Key('account-retry'),
                        onPressed: () {
                          setState(() {
                            _future = widget.loadAccount();
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
                ),
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
                          _future = widget.loadAccount();
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
  /// In-app gear is Windows-only; macOS uses TagKin → Settings… in the menu bar.
  bool get _showSettingsGear => !kIsWeb && Platform.isWindows;

  bool _settingsOpen = false;

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
      windowManager.addListener(this);
      _windowCloseGateActive = true;
      signedInQuitHandlerReady = true;
    } catch (_) {
      // Plugin missing or not ready — fall back to didRequestAppExit only.
    }
  }

  /// Disarm the close gate, then terminate. Must clear [_windowCloseGateActive]
  /// and set [_quitConfirmed] before [windowManager.destroy]: on macOS destroy
  /// is NSApp.terminate, which re-enters [didRequestAppExit]; leaving the gate
  /// armed cancels that exit (Save/Discard appear to "work" but the app stays).
  Future<void> _allowCloseAndQuit() async {
    if (!_windowCloseGateActive && !_quitConfirmed) return;
    _quitConfirmed = true;
    if (_windowCloseGateActive) {
      windowManager.removeListener(this);
      _windowCloseGateActive = false;
    }
    signedInQuitHandlerReady = false;
    try {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (_) {
      try {
        await windowManager.destroy();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKeyForFacesSelectAll);
    if (_windowCloseGateActive) {
      windowManager.removeListener(this);
      _windowCloseGateActive = false;
    }
    signedInQuitHandlerReady = false;
    _libraryLookSource?.removeListener(_onLibraryLookChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _ensureLibraryLookSync(LibraryTableController table) {
    if (identical(_libraryLookSource, table)) return;
    _libraryLookSource?.removeListener(_onLibraryLookChanged);
    _libraryLookSource = table;
    table.addListener(_onLibraryLookChanged);
  }

  void _onLibraryLookChanged() {
    if (!mounted || _applyingCollectionUi) return;
    final cols = ref.read(collectionsControllerProvider);
    if (!cols.sessionReady) return;
    cols.updateLibraryLook(
      ref.read(libraryTableControllerProvider).captureCollectionLibraryUi(),
    );
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
      await table.ensureLoaded();
      if (!mounted) return;
      await table.applyCollectionLibraryUi(cols.current.ui.library);
      if (!mounted) return;
      // Auto-expand may change expandedDirs; fold into baseline, not dirty.
      cols.adoptLibraryLook(table.captureCollectionLibraryUi());
    } finally {
      _applyingCollectionUi = false;
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
      if (!cols.dirty) {
        _quitConfirmed = true;
        windowManager.removeListener(this);
        _windowCloseGateActive = false;
        signedInQuitHandlerReady = false;
        try {
          await windowManager.setPreventClose(false);
        } catch (_) {}
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
    _collectionBootstrapRequested = false;
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
    final cols = ref.read(collectionsControllerProvider);
    await runCollectionMenuCommand(
      context: context,
      cols: cols,
      command: req.command,
      libraryFolders: _libraryFolders(),
      recentCollectionId: req.recentCollectionId,
    );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not copy token: $e')),
      );
    }
  }

  Future<void> _openSettings() async {
    if (_settingsOpen) return;
    _settingsOpen = true;
    try {
      await pushSettingsPage(context);
    } finally {
      _settingsOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(openSettingsTickProvider, (previous, next) {
      if (previous == null || previous == next) return;
      if (!mounted) return;
      _openSettings();
    });

    ref.listen<int>(quitAppTickProvider, (previous, next) {
      if (previous == null || previous == next) return;
      if (!mounted) return;
      unawaited(_handleWindowClose());
    });

    ref.listen<CollectionMenuRequest?>(collectionMenuRequestProvider,
        (previous, next) {
      if (next == null) return;
      if (previous?.nonce == next.nonce) return;
      if (!mounted) return;
      unawaited(_runCollectionCommand(next));
    });

    final cols = ref.watch(collectionsControllerProvider);
    final table = ref.watch(libraryTableControllerProvider);
    final libraryFolders = distinctLeafFolders(table.allRows.map((r) => r.item));

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
        onSignOut: widget.onSignOut == null ? null : _signOut,
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
      final folders =
          distinctLeafFolders(lib.allRows.map((r) => r.item)).toSet();
      if (c.current.leafFolders.isEmpty && folders.isNotEmpty) {
        await c.fillMembershipIfEmpty(folders.toList());
        if (!mounted) return;
      } else {
        c.adoptUnownedFolders(folders);
      }
      ref.read(libraryTableControllerProvider).setCollectionLeafFolders(
            c.current.leafFolders.toSet(),
          );
    });

    final showWindowsFileMenu = !kIsWeb && Platform.isWindows;

    return Scaffold(
      appBar: AppBar(
        title: SelectionContainer.disabled(
          child: Row(
          children: [
            const Text('TagKin'),
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
                    enabled: cols.dirty,
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
                ];
              },
              icon: const Icon(Icons.menu),
            ),
          IconButton(
            key: const Key('nav-folders'),
            tooltip: 'Folders',
            onPressed: () => _selectTab(TopLevelTab.folders),
            icon: Icon(
              activeTab == TopLevelTab.folders
                  ? Icons.folder
                  : Icons.folder_outlined,
            ),
          ),
          IconButton(
            key: const Key('nav-face-crops'),
            tooltip: 'Faces',
            onPressed: () => _selectTab(TopLevelTab.faces),
            icon: Icon(
              activeTab == TopLevelTab.faces
                  ? Icons.face_retouching_natural
                  : Icons.face_retouching_natural_outlined,
            ),
          ),
          IconButton(
            key: const Key('nav-persons'),
            tooltip: 'Persons',
            onPressed: () => _selectTab(TopLevelTab.persons),
            icon: Icon(
              activeTab == TopLevelTab.persons
                  ? Icons.people
                  : Icons.people_outline,
            ),
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
          if (widget.onSignOut != null)
            IconButton(
              key: const Key('sign-out'),
              tooltip: 'Sign out',
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
            ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
