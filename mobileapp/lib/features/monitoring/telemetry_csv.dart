import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';

String buildTelemetryCsv(List<SensorData> history) {
  final csv = StringBuffer();
  csv.writeln('Timestamp,Temperature(C),ChamberTemperature(C),MQ135(V),MQ2(V),PM1.0(ug/m3),PM2.5(ug/m3),PM10(ug/m3)');
  for (final data in history) {
    String value(double? reading) => reading?.toStringAsFixed(2) ?? '';
    csv.writeln('${data.timestamp.toIso8601String()},${value(data.temperatureC)},${value(data.chamberTempC)},${value(data.mq135V)},${value(data.mq2V)},${value(data.pm1_0UgM3)},${value(data.pm2_5UgM3)},${value(data.pm10UgM3)}');
  }
  return csv.toString();
}
