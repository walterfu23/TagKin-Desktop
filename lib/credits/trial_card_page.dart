import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/api/credits_repository.dart';
import 'package:tagkin_desktop/app_shell.dart' show creditsRepositoryProvider;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/credits/buy_credits_page.dart';
import 'package:tagkin_desktop/credits/checkout_launcher.dart';
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
  TrialSummary? _summary;
  String? _error;
  String? _verificationId;
  bool _busy = false;
  bool _granted = false;

  CreditsRepository get _repo => ref.read(creditsRepositoryProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _verificationId != null) {
      _claim();
    }
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _summary = await _repo.getTrial();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await _repo.startTrialVerification();
      _verificationId = created.verificationId;
      final opened = await launchCheckoutUrl(Uri.parse(created.cardSetupUrl));
      if (!opened) {
        _error = 'Could not open the browser';
      }
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _claim() async {
    final id = _verificationId;
    if (id == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _repo.claimTrialVerification(id);
      _granted = result.status == 'granted';
      await ref.read(usageControllerProvider).load();
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return SelectableScope(
      child: Scaffold(
        appBar: AppBar(title: const Text('Card verification')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: _body(),
        ),
      ),
    );
  }

  Widget _body() {
    if (_busy && _summary == null && !_granted) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_granted) {
      return Column(
        key: const Key('trial-card-granted'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Trial credits are now remaining credits.'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      );
    }
    if (_summary != null && !_summary!.eligible && !_granted) {
      return const Text('This account already has the Trial pack.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Add a card to receive the Trial pack. TagKin never sees the card number.',
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('trial-card-open'),
          onPressed: _busy ? null : _start,
          child: const Text('Open card form'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('trial-card-finished'),
          onPressed: _verificationId == null || _busy ? null : _claim,
          child: const Text('I finished in the browser'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, key: const Key('trial-card-error')),
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
