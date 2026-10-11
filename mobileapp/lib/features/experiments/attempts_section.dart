import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'attempt.dart';
import 'attempt_comparison_screen.dart';
import 'attempt_controller.dart';

class AttemptsSection extends StatefulWidget {
  const AttemptsSection({super.key});
  @override
  State<AttemptsSection> createState() => _AttemptsSectionState();
}

class _AttemptsSectionState extends State<AttemptsSection> {
  int? _withoutId, _withId;
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AttemptController>();
    final active = controller.activeAttempt;
    final attempts = controller.attempts;
    if (_withoutId != null && !attempts.any((a) => a.id == _withoutId)) {
      _withoutId = null;
    }
    if (_withId != null && !attempts.any((a) => a.id == _withId)) {
      _withId = null;
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
      children: [
        Text('Attempts', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        if (active == null)
          ElevatedButton(
            onPressed: controller.isBusy
                ? null
                : () => _start(context, controller),
            child: const Text('Start Attempt'),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${active.label} recording'),
              Text('${active.sampleCount} samples'),
              ElevatedButton(
                onPressed: controller.isBusy ? null : controller.stop,
                child: const Text('Stop Attempt'),
              ),
            ],
          ),
        const SizedBox(height: 24),
        for (final scenario in AttemptScenario.values) ...[
          Text(
            scenario.labelPrefix,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final attempt in attempts.where(
            (item) =>
                item.scenario == scenario &&
                item.status != AttemptStatus.active,
          ))
            _attemptTile(attempt, controller),
          const SizedBox(height: 16),
        ],
        ElevatedButton(
          onPressed: controller.isBusy || _withoutId == null || _withId == null
              ? null
              : () async {
                  final comparison = await controller.compare(
                    _withoutId!,
                    _withId!,
                  );
                  if (!context.mounted) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          AttemptComparisonScreen(comparison: comparison),
                    ),
                  );
                },
          child: const Text('Compare attempts'),
        ),
        const SizedBox(height: 12),
        Text('Select one saved attempt from each scenario before comparing.'),
      ],
    );
  }

  Widget _attemptTile(Attempt attempt, AttemptController controller) =>
      ListTile(
        title: Text(attempt.label),
        subtitle: Text(
          '${attempt.status.name} · ${attempt.sampleCount} samples',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: controller.isBusy
              ? null
              : () => _confirmDelete(attempt, controller),
        ),
        enabled: !controller.isBusy && attempt.sampleCount > 0,
        selected: attempt.id == _withoutId || attempt.id == _withId,
        onTap: controller.isBusy || attempt.sampleCount == 0
            ? null
            : () => setState(() {
                if (attempt.scenario == AttemptScenario.withoutFiltration) {
                  _withoutId = attempt.id;
                } else {
                  _withId = attempt.id;
                }
              }),
      );

  Future<void> _confirmDelete(
    Attempt attempt,
    AttemptController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete attempt?'),
        content: Text('Delete ${attempt.label}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await controller.deleteAttempt(attempt.id);
    }
  }

  Future<void> _start(
    BuildContext context,
    AttemptController controller,
  ) async {
    final scenario = await showDialog<AttemptScenario>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start Attempt'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, AttemptScenario.withoutFiltration),
            child: const Text('Without filtration'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, AttemptScenario.withFiltration),
            child: const Text('With filtration'),
          ),
        ],
      ),
    );
    if (scenario != null) await controller.start(scenario);
  }
}
