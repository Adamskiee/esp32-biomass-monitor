import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_theme.dart';
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
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.science_outlined, color: AppTheme.neonGreen),
            const SizedBox(width: 12),
            Text('Attempts', style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Record paired readings to compare filtration conditions.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        _recordingCard(context, controller, active),
        const SizedBox(height: 20),
        Text('Saved attempts', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final cards = AttemptScenario.values
                .map(
                  (scenario) => _scenarioCard(
                    context,
                    scenario,
                    attempts
                        .where(
                          (item) =>
                              item.scenario == scenario &&
                              item.status != AttemptStatus.active,
                        )
                        .toList(growable: false),
                    controller,
                  ),
                )
                .toList(growable: false);
            if (constraints.maxWidth >= 700) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 16),
                  Expanded(child: cards[1]),
                ],
              );
            }
            return Column(
              children: [cards[0], const SizedBox(height: 16), cards[1]],
            );
          },
        ),
        const SizedBox(height: 20),
        _comparisonCard(context, controller, attempts),
      ],
    );
  }

  Widget _recordingCard(
    BuildContext context,
    AttemptController controller,
    Attempt? active,
  ) => Card(
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recording', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            active == null
                ? 'Start an attempt when the chamber is ready.'
                : '${active.label} is recording · ${active.sampleCount} samples',
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: controller.isBusy
                  ? null
                  : active == null
                  ? () => _start(context, controller)
                  : controller.stop,
              icon: Icon(active == null ? Icons.play_arrow : Icons.stop),
              label: Text(active == null ? 'Start attempt' : 'Stop attempt'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _scenarioCard(
    BuildContext context,
    AttemptScenario scenario,
    List<Attempt> scenarioAttempts,
    AttemptController controller,
  ) => Card(
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              scenario.labelPrefix,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (scenarioAttempts.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text('No attempts saved yet'),
            )
          else
            ...scenarioAttempts.map(
              (attempt) => _attemptTile(attempt, controller),
            ),
        ],
      ),
    ),
  );

  Widget _comparisonCard(
    BuildContext context,
    AttemptController controller,
    List<Attempt> attempts,
  ) {
    final without = attempts
        .where((attempt) => attempt.id == _withoutId)
        .firstOrNull;
    final filtered = attempts
        .where((attempt) => attempt.id == _withId)
        .firstOrNull;
    final canCompare =
        !controller.isBusy && without != null && filtered != null;
    return Card(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose attempts to compare',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              canCompare
                  ? 'Comparing ${without.label} with ${filtered.label}.'
                  : 'Save one attempt from each scenario to unlock comparison.',
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canCompare
                    ? () async {
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
                      }
                    : null,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.compare_arrows),
                    SizedBox(width: 8),
                    Text('Compare attempts'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _attemptTile(Attempt attempt, AttemptController controller) =>
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
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
