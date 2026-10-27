import 'package:flutter/material.dart';

String formatTelemetryTimestamp(BuildContext context, DateTime timestamp) {
  final localizations = MaterialLocalizations.of(context);
  final date = localizations.formatShortDate(timestamp);
  final time = localizations.formatTimeOfDay(
    TimeOfDay.fromDateTime(timestamp),
    alwaysUse24HourFormat: true,
  );
  return '$date · $time';
}
