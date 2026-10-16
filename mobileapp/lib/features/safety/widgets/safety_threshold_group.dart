import 'package:flutter/material.dart';

class SafetyThresholdGroup extends StatelessWidget {
  const SafetyThresholdGroup({
    super.key,
    required this.title,
    required this.fields,
    required this.locked,
  });

  final String title;
  final Map<String, String> fields;
  final bool locked;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          for (final entry in fields.entries)
            TextFormField(
              key: ValueKey(entry.key),
              enabled: !locked,
              initialValue: entry.value,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: entry.key),
            ),
        ],
      ),
    ),
  );
}
