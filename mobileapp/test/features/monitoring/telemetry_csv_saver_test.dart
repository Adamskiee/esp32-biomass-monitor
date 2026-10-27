import 'dart:convert';

import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:biomass_iot_app/features/monitoring/telemetry_csv.dart';
import 'package:biomass_iot_app/features/monitoring/telemetry_csv_saver.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeFilePicker extends FilePickerPlatform {
  Uri? result = Uri.parse('content://documents/chosen.csv');
  bool fail = false;
  String? savedName;
  String? savedMimeType;
  Uint8List? savedBytes;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    savedName = fileName;
    savedMimeType = mimeType;
    savedBytes = bytes;
    if (fail) throw PlatformException(code: 'save_failed');
    return result;
  }
}

void main() {
  late FilePickerPlatform original;
  late _FakeFilePicker picker;

  setUp(() {
    original = FilePickerPlatform.instance;
    picker = _FakeFilePicker();
    FilePickerPlatform.instance = picker;
  });

  tearDown(() => FilePickerPlatform.instance = original);

  test(
    'saves CSV bytes with the suggested name and returns the saved URI',
    () async {
      final history = [
        SensorData(
          temperatureC: 31.2,
          humidityPercent: 54.5,
          timestamp: DateTime.utc(2026, 10, 19, 12),
        ),
      ];
      String datedName(DateTime date) {
        final month = date.month.toString().padLeft(2, '0');
        final day = date.day.toString().padLeft(2, '0');
        final hour = date.hour.toString().padLeft(2, '0');
        final minute = date.minute.toString().padLeft(2, '0');
        final second = date.second.toString().padLeft(2, '0');
        return 'Biomass_Telemetry_Export_${date.year}-$month-${day}_$hour-$minute-$second.csv';
      }

      final before = DateTime.now();
      expect(await saveTelemetryCsv(history), picker.result);
      final after = DateTime.now();
      expect(picker.savedName, anyOf(datedName(before), datedName(after)));
      expect(picker.savedMimeType, 'text/csv');
      expect(utf8.decode(picker.savedBytes!), buildTelemetryCsv(history));
    },
  );

  test('returns null when the user cancels', () async {
    picker.result = null;
    expect(await saveTelemetryCsv([]), isNull);
  });

  test('propagates saving errors', () async {
    picker.fail = true;
    await expectLater(saveTelemetryCsv([]), throwsA(isA<PlatformException>()));
  });
}
