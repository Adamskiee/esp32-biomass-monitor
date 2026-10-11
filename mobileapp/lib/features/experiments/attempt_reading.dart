import '../monitoring/sensor_data.dart';

class AttemptReading {
  const AttemptReading({
    required this.attemptId,
    required this.recordedAt,
    required this.elapsed,
    required this.data,
  });
  final int attemptId;
  final DateTime recordedAt;
  final Duration elapsed;
  final SensorData data;
}
