import 'dart:convert';
import 'dart:typed_data';

import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:biomass_iot_app/features/monitoring/telemetry_csv.dart';
import 'package:file_picker/file_picker.dart';

Future<Uri?> saveTelemetryCsv(List<SensorData> history) {
  return FilePicker.saveFile(
    fileName: 'Biomass_Telemetry_Export.csv',
    bytes: Uint8List.fromList(utf8.encode(buildTelemetryCsv(history))),
    mimeType: 'text/csv',
  );
}
