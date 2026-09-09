import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/branding.g.dart';
import 'package:tagkin_desktop/credits/buy_credits_page.dart';
import 'package:tagkin_desktop/credits/trial_card_controller.dart';
import 'package:tagkin_desktop/usage/credits_remaining.dart';
import 'package:tagkin_desktop/usage/usage_controller.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

/// Opens Stripe Checkout in setup mode so the account can receive the Trial pack.
class TrialCardPage extends ConsumerStatefulWidget {
  const TrialCardPage({super.key});

  @override
  ConsumerState<TrialCardPage> createState() => _TrialCardPageState();
}

class _TrialCardPageState extends ConsumerState<TrialCardPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(trialCardControllerProvider).load();
      ref.read(usageControllerProvider).ensureLoaded();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final controller = ref.read(trialCardControllerProvider);
      if (controller.verificationId != null) {
        controller.claim();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(trialCardControllerProvider);
    return SelectableScope(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return Scaffold(
            appBar: AppBar(title: const Text('Card verification')),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: _body(controller),
            ),
          );
        },
      ),
    );
  }

  Widget _body(TrialCardController controller) {
    if (controller.busy && controller.summary == null && !controller.granted) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.granted) {
      return Column(
        key: const Key('trial-card-granted'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CreditsRemainingSentence(textKey: Key('trial-card-remaining')),
          const Text('Trial credits are now remaining credits.'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      );
    }
    if (controller.summary != null &&
        !controller.summary!.eligible &&
        !controller.granted) {
      return const Text('This account already has the Trial pack.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CreditsRemainingSentence(textKey: Key('trial-card-remaining')),
        Text(
          'Add a card to receive the Trial pack. $kAppName never sees the card number.',
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('trial-card-open'),
          onPressed: controller.busy ? null : controller.start,
          child: const Text('Open card form'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('trial-card-finished'),
          onPressed: controller.verificationId == null || controller.busy
              ? null
              : controller.claim,
          child: const Text('I finished in the browser'),
        ),
        if (controller.errorMessage != null) ...[
          const SizedBox(height: 16),
          Text(controller.errorMessage!, key: const Key('trial-card-error')),
          const SizedBox(height: 12),
          TextButton(
            key: const Key('trial-card-buy-credits'),
            onPressed: () {
              final container = ProviderScope.containerOf(context);
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  settings: const RouteSettings(name: 'buy-credits'),
                  builder: (_) => UncontrolledProviderScope(
                    container: container,
                    child: const BuyCreditsPage(),
                  ),
                ),
              );
            },
            child: const Text('Buy credits'),
          ),
        ],
      ],
    );
  }
}
