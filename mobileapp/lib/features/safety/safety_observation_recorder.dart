import 'package:biomass_iot_app/features/alerts/alerts_controller.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';

class SafetyObservationRecorder {
  SafetyObservationRecorder(this._alerts);

  final AlertsController _alerts;
  int _issued = 0;
  int _accepted = 0;
  Future<void> _queue = Future.value();

  int begin() => ++_issued;

  Future<bool> accept(int ticket, Map<String, dynamic> state) async {
    var accepted = false;
    final next = _queue.then((_) async {
      if (ticket <= _accepted) return;
      final reading = SensorData.fromJson(state);
      final triggers = (state['active_triggers'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList();
      await _alerts.recordTriggers(reading, triggers);
      _accepted = ticket;
      accepted = true;
    });
    _queue = next.catchError((_) {});
    await next;
    return accepted;
  }
}
