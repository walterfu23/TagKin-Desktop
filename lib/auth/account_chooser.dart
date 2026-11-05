import 'package:flutter/material.dart';
import 'package:tagkin_desktop/auth/account_roster.dart';
import 'package:tagkin_desktop/auth/login_hero.dart';

/// Saved accounts on this computer. A tap opens that library. No password.
class AccountChooserPage extends StatelessWidget {
  const AccountChooserPage({
    super.key,
    required this.accounts,
    required this.allowAdd,
    required this.onOpen,
    required this.onRemove,
    this.onAdd,
  });

  final List<SavedAccount> accounts;
  final bool allowAdd;
  final ValueChanged<SavedAccount> onOpen;
  final ValueChanged<SavedAccount> onRemove;
  final VoidCallback? onAdd;

  Future<void> _confirmRemove(
    BuildContext context,
    SavedAccount account,
  ) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          key: const Key('account-remove-dialog'),
          title: const SelectableText('Remove from this computer'),
          content: const SelectableText(
            'This removes the saved sign-in on this computer. '
            'The account, its photos, people, and credits are not deleted. '
            'Sign in again with the same email to open it.',
          ),
          actions: [
            TextButton(
              key: const Key('account-remove-cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const Key('account-remove-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove from this computer'),
            ),
          ],
        );
      },
    );
    if (remove == true) onRemove(account);
  }

  @override
  Widget build(BuildContext context) {
    return SignedOutFrame(
      formWidth: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Choose an account',
            key: const Key('account-chooser-title'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text('Tap an account to open it.'),
          const SizedBox(height: 16),
          for (final account in accounts) ...[
            OutlinedButton(
              key: Key('account-open-${account.localId}'),
              onPressed: () => onOpen(account),
              child: Text(account.label),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: Key('account-remove-${account.localId}'),
                onPressed: () => _confirmRemove(context, account),
                child: const Text('Remove from this computer'),
              ),
            ),
          ],
          if (allowAdd && onAdd != null) ...[
            const SizedBox(height: 8),
            TextButton(
              key: const Key('account-add'),
              onPressed: onAdd,
              child: const Text('Add account'),
            ),
          ],
        ],
      ),
    );
  }
}
