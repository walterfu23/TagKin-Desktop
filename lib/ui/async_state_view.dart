import 'package:flutter/material.dart';

/// Shared empty / error / loading copy for route bodies.
class AsyncStateView extends StatelessWidget {
  const AsyncStateView.loading({super.key, this.message = 'Loading…'})
      : _kind = _Kind.loading,
        onRetry = null;

  const AsyncStateView.empty({super.key, required this.message})
      : _kind = _Kind.empty,
        onRetry = null;

  const AsyncStateView.error({
    super.key,
    required this.message,
    this.onRetry,
  }) : _kind = _Kind.error;

  final _Kind _kind;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_kind == _Kind.loading) const CircularProgressIndicator(),
            if (_kind == _Kind.loading) const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

enum _Kind { loading, empty, error }
