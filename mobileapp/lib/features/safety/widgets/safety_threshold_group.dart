import 'package:flutter/material.dart';

class SafetyThresholdField {
  const SafetyThresholdField({required this.label, required this.value});

  final String label;
  final String value;
}

class SafetyThresholdGroup extends StatelessWidget {
  const SafetyThresholdGroup({
    super.key,
    required this.title,
    required this.fields,
    required this.locked,
    this.currentReading,
    this.onChanged,
  });

  final String title;
  final Map<String, SafetyThresholdField> fields;
  final bool locked;
  final String? currentReading;
  final void Function(String field, String value)? onChanged;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (currentReading != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(currentReading!),
            ),
          for (final entry in fields.entries)
            TextFormField(
              key: ValueKey(entry.key),
              enabled: !locked,
              initialValue: entry.value.value,
              onChanged: (value) => onChanged?.call(entry.key, value),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: entry.value.label),
            ),
        ],
      ),
    ),
  );
}
