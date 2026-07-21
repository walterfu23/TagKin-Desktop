import 'package:clerk_auth/clerk_auth.dart' show RetryOptions;
import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/api/jobs_repository.dart';
import 'package:tagkin_desktop/api/me_repository.dart';
import 'package:tagkin_desktop/api/usage_repository.dart';
import 'package:tagkin_desktop/auth/secure_persistor.dart';
import 'package:tagkin_desktop/config/app_config.dart';
import 'package:tagkin_desktop/contract/contract.dart';

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

/// Fake signed-in session for tests — supplies a bearer token + optional /me
/// result without talking to Clerk or the network.
class TestSession {
  const TestSession({
    required this.token,
    this.account,
    this.meError,
  });

  final String token;
  final Account? account;

  /// When set, [AccountBootstrap] surfaces this instead of calling /me.
  final Object? meError;
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
  });

  final Future<Account> Function() loadAccount;
  final Future<void> Function()? onSignOut;
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
          child: widget.signedInHome,
        );
      },
    );
  }
}

class _SignedInScaffold extends StatelessWidget {
  const _SignedInScaffold({
    required this.account,
    required this.child,
    this.onSignOut,
  });

  final Account account;
  final Widget child;
  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TagKin'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                account.email ?? account.id,
                key: const Key('account-label'),
              ),
            ),
          ),
          if (onSignOut != null)
            IconButton(
              key: const Key('sign-out'),
              tooltip: 'Sign out',
              onPressed: () => onSignOut!(),
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: child,
    );
  }
}
