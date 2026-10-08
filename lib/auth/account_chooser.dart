import 'package:flutter/material.dart';
import 'package:tagkin_desktop/auth/account_roster.dart';
import 'package:tagkin_desktop/auth/login_hero.dart';

enum AccountSwitchKind { activate, add, setup, remove }

/// What the user picked from [showAccountSwitchDialog].
class AccountSwitchChoice {
  const AccountSwitchChoice.activate(this.localId)
    : kind = AccountSwitchKind.activate,
      email = null;
  const AccountSwitchChoice.add()
    : kind = AccountSwitchKind.add,
      localId = null,
      email = null;
  const AccountSwitchChoice.setup(this.email)
    : kind = AccountSwitchKind.setup,
      localId = null;
  const AccountSwitchChoice.remove(this.localId)
    : kind = AccountSwitchKind.remove,
      email = null;

  final AccountSwitchKind kind;
  final String? localId;
  final String? email;
}

/// Account list shown when the active session is missing or the user is
/// switching. Tapping an account opens that library. **Set up account** is
/// only for an account that has no saved session on this computer.
class AccountChooserPage extends StatelessWidget {
  const AccountChooserPage({
    super.key,
    required this.accounts,
    required this.onActivate,
    required this.onSetup,
    this.notice,
    this.onBack,
  });

  final List<SavedAccount> accounts;
  final ValueChanged<SavedAccount> onActivate;
  final ValueChanged<String?> onSetup;
  final String? notice;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return SignedOutFrame(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Accounts on this computer',
              key: const Key('account-chooser-title'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (notice != null) ...[
              const SizedBox(height: 12),
              Text(notice!, key: const Key('account-chooser-notice')),
            ],
            const SizedBox(height: 16),
            for (final account in accounts) ...[
              OutlinedButton(
                key: Key('account-choice-${account.localId}'),
                onPressed: () => onActivate(account),
                child: Text(account.label),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton(
              key: const Key('account-setup'),
              onPressed: () => onSetup(null),
              child: const Text('Set up account'),
            ),
            if (onBack != null) ...[
              const SizedBox(height: 8),
              TextButton(
                key: const Key('account-chooser-back'),
                onPressed: onBack,
                child: const Text('Back'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Picks another saved account, adds one, or removes one from this computer.
Future<AccountSwitchChoice?> showAccountSwitchDialog({
  required BuildContext context,
  required List<SavedAccount> accounts,
  required String activeLocalId,
}) {
  return showDialog<AccountSwitchChoice>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Switch account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final account in accounts)
              ListTile(
                key: Key('switch-account-${account.localId}'),
                title: Text(account.label),
                subtitle: Text(
                  account.localId == activeLocalId
                      ? 'Active'
                      : account.hasSession
                      ? 'Saved on this computer'
                      : 'Set up again',
                ),
                trailing: IconButton(
                  key: Key('remove-account-${account.localId}'),
                  tooltip: 'Remove from this computer',
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(AccountSwitchChoice.remove(account.localId)),
                  icon: const Icon(Icons.close),
                ),
                onTap: account.localId == activeLocalId
                    ? null
                    : () => Navigator.of(context).pop(
                        account.hasSession
                            ? AccountSwitchChoice.activate(account.localId)
                            : AccountSwitchChoice.setup(account.email),
                      ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('switch-add-account'),
                onPressed: () =>
                    Navigator.of(context).pop(const AccountSwitchChoice.add()),
                child: const Text('Add account'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('switch-account-cancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      );
    },
  );
}
