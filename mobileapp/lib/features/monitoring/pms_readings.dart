import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:flutter/material.dart';

class PmsReadings extends StatelessWidget {
  const PmsReadings({super.key, required this.data});

  final SensorData data;

  @override
  Widget build(BuildContext context) {
    String format(double? value) => value == null
        ? '--'
        : '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1)} µg/m³';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Particulate Matter', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _reading('PM1.0', format(data.pm1_0UgM3)),
        _reading('PM2.5', format(data.pm2_5UgM3)),
        _reading('PM10', format(data.pm10UgM3)),
      ],
    );
  }

  Widget _reading(String label, String value) => Row(
    children: [Text('$label: '), Text(value)],
  );
}
