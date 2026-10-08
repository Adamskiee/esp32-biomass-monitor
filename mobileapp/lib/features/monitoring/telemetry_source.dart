import 'package:flutter/foundation.dart';

import 'sensor_data.dart';

abstract interface class TelemetrySource implements Listenable {
  bool get isHardwareConnected;
  int get telemetryRevision;
  SensorData get currentData;
}
