import 'package:flutter/material.dart';
import 'attempt_comparison.dart';

class AttemptComparisonScreen extends StatelessWidget {
  const AttemptComparisonScreen({super.key, required this.comparison});
  final AttemptComparison comparison;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Attempt comparison')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: comparison.metrics.map((item) {
        final change = item.difference == null
            ? 'No data'
            : item.percentageDifference == null
            ? 'Not available'
            : item.percentageDifference! < 0
            ? '${item.percentageDifference!.abs().toStringAsFixed(1)}% lower with filtration'
            : item.percentageDifference! > 0
            ? '${item.percentageDifference!.toStringAsFixed(1)}% higher with filtration'
            : 'No difference';
        return Card(
          child: ListTile(
            title: Text('${item.metric.label} (${item.metric.unit})'),
            subtitle: Text(
              'Without: ${item.unfiltered.average?.toStringAsFixed(item.metric.decimalPlaces) ?? 'No data'} · With: ${item.filtered.average?.toStringAsFixed(item.metric.decimalPlaces) ?? 'No data'}\n$change',
            ),
          ),
        );
      }).toList(),
    ),
  );
}
