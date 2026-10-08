import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'attempt.dart';
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
      padding: const EdgeInsets.all(24),
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
        for (final attempt in attempts)
          ListTile(
            title: Text(attempt.label),
            subtitle: Text(
              '${attempt.status.name} · ${attempt.sampleCount} samples',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: attempt.status == AttemptStatus.active
                  ? null
                  : () => controller.deleteAttempt(attempt.id),
            ),
          ),
        const SizedBox(height: 12),
        Text('Select one saved attempt from each scenario before comparing.'),
      ],
    );
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
