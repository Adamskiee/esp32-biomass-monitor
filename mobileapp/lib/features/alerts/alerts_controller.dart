import 'package:biomass_iot_app/features/alerts/alert_item.dart';
import 'package:biomass_iot_app/features/alerts/alerts_store.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:flutter/foundation.dart';

class AlertsController extends ChangeNotifier {
  AlertsController(this._store);

  final AlertsStore _store;
  final List<AlertItem> _alerts = [];

  List<AlertItem> get alerts => List.unmodifiable(_alerts);

  Future<void> load() async {
    _alerts
      ..clear()
      ..addAll(await _store.getAlerts());
    notifyListeners();
  }

  Future<void> recordTriggers(SensorData reading, List<String> triggers) async {
    if (!triggers.contains('high_mq2_gas') ||
        reading.mq2V == null ||
        _alerts.any((alert) => alert.title.contains('Gas Hazard'))) {
      return;
    }
    final timestamp = DateTime.now();
    final alert = AlertItem(
      id: timestamp.microsecondsSinceEpoch.toString(),
      title: 'CRITICAL: Gas Hazard',
      description:
          'ESP32 reported a high MQ-2 reading (${reading.mq2V!.toStringAsFixed(2)} V).',
      severity: 'critical',
      timestamp: timestamp,
    );
    _alerts.insert(0, alert);
    await _store.insertAlert(alert);
    notifyListeners();
  }

  void removeAlert(String id) {
    _alerts.removeWhere((alert) => alert.id == id);
    notifyListeners();
  }

  void clearAllAlerts() {
    _alerts.clear();
    notifyListeners();
  }
}
