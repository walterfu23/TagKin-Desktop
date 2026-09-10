import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/main.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/collections_store.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_store.dart';
import 'package:tagkin_desktop/prefs/settings_page.dart';
import 'package:tagkin_desktop/update/client_identity.dart';
import 'package:tagkin_desktop/update/client_support_providers.dart';

import 'fake_items_repository.dart';
import 'fake_jobs_repository.dart';
import 'fake_persons_repository.dart';
import 'fake_usage_repository.dart';

Account _account({
  ClientSupport? support,
}) =>
    Account(
      id: 'acc_1',
      email: 'acc_1@example.com',
      createdAt: '2026-07-18T00:00:00.000Z',
      clientSupport: support,
    );

List<Override> _signedInOverrides({ClientSupport? support}) => [
      testSessionProvider.overrideWithValue(
        TestSession(token: 'tok', account: _account(support: support)),
      ),
      itemsRepositoryProvider.overrideWithValue(FakeItemsRepository()),
      usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
      jobsRepositoryProvider.overrideWithValue(FakeJobsRepository()),
      personsRepositoryProvider.overrideWithValue(FakePersonsRepository()),
      collectionsStoreProvider.overrideWithValue(MemoryCollectionsStore()),
    ];

void main() {
  test('ClientIdentity header matches the contract example shape', () {
    const id = ClientIdentity(version: '1.0.0+1', platform: 'macos');
    expect(id.headerValue, 'tagkin-desktop/1.0.0+1 (macos)');
  });

  testWidgets('warn clientSupport shows a dismissible banner', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _signedInOverrides(
          support: const ClientSupport(
            status: ClientSupportStatus.warn,
            latestVersion: '1.2.0',
            downloadUrl: 'https://example.test/tagkin',
          ),
        ),
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('client-update-banner')), findsOneWidget);
    expect(find.byKey(const Key('items-empty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('client-update-banner-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('client-update-banner')), findsNothing);
    expect(find.byKey(const Key('items-empty')), findsOneWidget);
  });

  testWidgets('blocked clientSupport shows Update required, not the library',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _signedInOverrides(
          support: const ClientSupport(
            status: ClientSupportStatus.blocked,
            minVersion: '1.0.0',
            downloadUrl: 'https://example.test/tagkin',
          ),
        ),
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('update-required-title')), findsOneWidget);
    expect(find.byKey(const Key('update-required-download')), findsOneWidget);
    expect(find.byKey(const Key('items-empty')), findsNothing);
    expect(find.byKey(const Key('items-list')), findsNothing);
  });

  testWidgets('Settings About shows the installed version', (tester) async {
    final store = MemoryDesktopPrefsStore();
    final prefsController = DesktopPrefsController(store: store);
    await prefsController.load();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          desktopPrefsControllerProvider.overrideWith((ref) => prefsController),
          usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
          clientIdentityProvider.overrideWithValue(
            const ClientIdentity(version: '1.0.0+1', platform: 'test'),
          ),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsOneWidget);
    await tester.dragUntilVisible(
      find.byKey(const Key('settings-about-version')),
      find.byType(Scrollable).first,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-about-version')), findsOneWidget);
    expect(find.text('1.0.0+1'), findsOneWidget);
    expect(find.byKey(const Key('settings-check-for-updates')), findsOneWidget);
  });
}

class MemoryDesktopPrefsStore extends DesktopPrefsStore {
  MemoryDesktopPrefsStore() : super(supportDir: null);

  DesktopPrefs _prefs = DesktopPrefs.defaults;

  @override
  Future<DesktopPrefs> load() async => _prefs;

  @override
  Future<void> save(DesktopPrefs prefs) async {
    _prefs = prefs;
  }
}
