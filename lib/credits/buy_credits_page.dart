import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/credits/buy_credits_controller.dart';
import 'package:tagkin_desktop/credits/pack_label.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

/// Pick a paid pack, disclose net credits from the server, open Checkout.
class BuyCreditsPage extends ConsumerStatefulWidget {
  const BuyCreditsPage({super.key});

  @override
  ConsumerState<BuyCreditsPage> createState() => _BuyCreditsPageState();
}

class _BuyCreditsPageState extends ConsumerState<BuyCreditsPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(buyCreditsControllerProvider).loadOffers();
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
      ref.read(buyCreditsControllerProvider).refreshPurchase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(buyCreditsControllerProvider);
    return SelectableScope(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return Scaffold(
            appBar: AppBar(title: const Text('Buy credits')),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: _body(controller),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _body(BuyCreditsController controller) {
    if (controller.phase == BuyCreditsPhase.loadingOffers) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.phase == BuyCreditsPhase.applied) {
      return Column(
        key: const Key('buy-credits-applied'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Credits applied. Remaining: '
            '${formatCreditCount(controller.purchase?.remainingCredits ?? 0)}.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('buy-credits-done'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      );
    }
    if (controller.phase == BuyCreditsPhase.expired) {
      return const Text(
        key: Key('buy-credits-expired'),
        'That checkout expired. Pick a pack to try again.',
      );
    }
    if (controller.phase == BuyCreditsPhase.failed &&
        controller.offers.isEmpty) {
      return Text(
        key: const Key('buy-credits-error'),
        controller.errorMessage ?? 'Could not load credit packs.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Choose a credit pack. Credits do not expire.'),
        const SizedBox(height: 16),
        RadioGroup<String>(
          groupValue: controller.selected?.packId,
          onChanged: (packId) {
            if (packId == null) return;
            for (final offer in controller.offers) {
              if (offer.packId == packId) {
                controller.select(offer);
                return;
              }
            }
          },
          child: Column(
            children: [
              for (final offer in controller.offers)
                RadioListTile<String>(
                  key: Key('buy-credits-pack-${offer.packId}'),
                  title: Text(
                    packSticker(
                      priceUsdCents: offer.priceUsdCents,
                      credits: offer.credits,
                    ),
                  ),
                  subtitle: Text(packDebtDisclosure(offer)),
                  value: offer.packId,
                ),
            ],
          ),
        ),
        if (controller.errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(controller.errorMessage!),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton(
              key: const Key('buy-credits-checkout'),
              onPressed: controller.selected == null ||
                      controller.phase == BuyCreditsPhase.creating
                  ? null
                  : controller.startCheckout,
              child: const Text('Continue to Checkout'),
            ),
            if (controller.phase == BuyCreditsPhase.awaitingBrowser ||
                controller.phase == BuyCreditsPhase.polling) ...[
              OutlinedButton(
                key: const Key('buy-credits-finished'),
                onPressed: controller.refreshPurchase,
                child: const Text('I finished in the browser'),
              ),
              TextButton(
                key: const Key('buy-credits-cancel'),
                onPressed: controller.cancel,
                child: const Text('Cancel'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
