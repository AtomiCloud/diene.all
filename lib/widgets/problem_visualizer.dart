import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/result.dart';

final class ProblemVisualizer extends StatelessWidget {
  const ProblemVisualizer({
    required this.problem,
    required this.retryLabel,
    required this.copyLabel,
    this.onRetry,
    super.key,
  });

  final Problem problem;
  final String retryLabel;
  final String copyLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (problem.recoverable) {
      return MaterialBanner(
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(problem.title, style: Theme.of(context).textTheme.titleMedium),
            if (problem.detail != null) Text(problem.detail!),
          ],
        ),
        leading: const Icon(Icons.sync_problem_rounded),
        actions: <Widget>[
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text(retryLabel))
          else
            TextButton(
              onPressed: () => Clipboard.setData(
                ClipboardData(text: problem.toJson().toString()),
              ),
              child: Text(copyLabel),
            ),
        ],
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.error_outline_rounded,
                  size: 36,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  problem.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (problem.detail != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(problem.detail!),
                ],
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: problem.toJson().toString()),
                  ),
                  icon: const Icon(Icons.copy_rounded),
                  label: Text(copyLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
