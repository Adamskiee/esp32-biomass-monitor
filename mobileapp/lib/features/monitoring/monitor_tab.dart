import 'dart:async';

import 'package:biomass_iot_app/core/widgets/icon_label.dart';
import 'package:biomass_iot_app/app/app_icons.dart';
import 'package:biomass_iot_app/app/app_state_provider.dart';
import 'package:biomass_iot_app/app/app_theme.dart';
import 'package:biomass_iot_app/core/storage/app_database.dart';
import 'package:biomass_iot_app/core/widgets/delayed_loading.dart';
import 'package:biomass_iot_app/core/widgets/loading_skeleton.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_history_store.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_log_controller.dart';
import 'package:biomass_iot_app/features/monitoring/telemetry_csv_saver.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../experiments/attempts_section.dart';

class MonitorTab extends StatefulWidget {
  const MonitorTab({super.key, this.sensorLogController, this.csvSaver});

  final SensorLogController? sensorLogController;
  final Future<Uri?> Function(List<SensorData>)? csvSaver;

  @override
  State<MonitorTab> createState() => _MonitorTabState();
}

class _MonitorTabState extends State<MonitorTab> {
  int _segIndex = 0;
  bool _isSavingCsv = false;
  late SensorLogController _sensorLogController;
  late bool _ownsSensorLogController;
  int? _lastTelemetryRevision;

  @override
  void initState() {
    super.initState();
    _attachSensorLogController();
  }

  void _attachSensorLogController() {
    _ownsSensorLogController = widget.sensorLogController == null;
    _sensorLogController =
        widget.sensorLogController ??
        SensorLogController(SensorHistoryStore(AppDatabase()));
    _sensorLogController.addListener(_onSensorLogChanged);
    unawaited(_sensorLogController.loadInitialPage());
  }

  void _onSensorLogChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant MonitorTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sensorLogController == widget.sensorLogController) return;
    _sensorLogController.removeListener(_onSensorLogChanged);
    if (_ownsSensorLogController) _sensorLogController.dispose();
    _attachSensorLogController();
  }

  @override
  void dispose() {
    _sensorLogController.removeListener(_onSensorLogChanged);
    if (_ownsSensorLogController) _sensorLogController.dispose();
    super.dispose();
  }

  Future<void> _saveCSV(List<SensorData> history) async {
    if (_isSavingCsv) return;
    if (history.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No sensor readings to save yet.')),
      );
      return;
    }
    setState(() => _isSavingCsv = true);
    try {
      final savedUri = await (widget.csvSaver ?? saveTelemetryCsv)(
        List<SensorData>.of(history),
      );
      if (!mounted || savedUri == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('CSV saved successfully.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save CSV. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _isSavingCsv = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final theme = Theme.of(context);
    _handleTelemetryRevision(state.telemetryRevision);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoSegmentedControl<int>(
                    selectedColor: AppTheme.neonGreen,
                    borderColor: AppTheme.neonGreen,
                    unselectedColor: theme.cardColor,
                    groupValue: _segIndex,
                    children: const {
                      0: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: IconLabel(
                          icon: AppIcons.sensorLog,
                          label: "Sensors Log",
                        ),
                      ),
                      1: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: IconLabel(
                          icon: AppIcons.experiment,
                          label: "Attempts",
                        ),
                      ),
                    },
                    onValueChanged: (val) => setState(() => _segIndex = val),
                  ),
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _segIndex == 0
                      ? _buildSensorsView(state, theme)
                      : const AttemptsSection(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleTelemetryRevision(int revision) {
    if (_lastTelemetryRevision == null) {
      _lastTelemetryRevision = revision;
      return;
    }
    if (_lastTelemetryRevision == revision) return;
    _lastTelemetryRevision = revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_sensorLogController.onTelemetryRevision());
    });
  }

  Widget _buildSensorsView(AppStateProvider state, ThemeData theme) {
    final isCompact = MediaQuery.of(context).size.width < 600;

    return ListView(
      key: const ValueKey(0),
      padding: EdgeInsets.only(
        left: isCompact ? 16 : 24,
        right: isCompact ? 16 : 24,
        bottom: 100,
      ),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: IconLabel(
                icon: AppIcons.sensorLog,
                label: 'Sensor Data Log',
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(AppIcons.download, color: AppTheme.neonGreen),
              onPressed: _isSavingCsv ? null : () => _saveCSV(state.history),
              tooltip: "Save CSV",
            ),
          ],
        ),
        Row(
          children: [
            const Expanded(child: Text('Live updates')),
            Switch(
              value: _sensorLogController.liveUpdates,
              onChanged: _sensorLogController.isLoading
                  ? null
                  : (enabled) =>
                        unawaited(_sensorLogController.setLiveUpdates(enabled)),
            ),
            IconButton(
              icon: const Icon(AppIcons.refresh),
              tooltip: 'Refresh sensor log',
              onPressed: _sensorLogController.isLoading
                  ? null
                  : () => unawaited(_sensorLogController.refresh()),
            ),
          ],
        ),
        if (_sensorLogController.hasNewRecords)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _sensorLogController.isLoading
                  ? null
                  : () => unawaited(_sensorLogController.showNewRecords()),
              icon: const Icon(AppIcons.scrollToTop),
              label: const Text('New records available'),
            ),
          ),
        const SizedBox(height: 8),
        DelayedLoading(
          isLoading: _sensorLogController.isLoading,
          hasContent: _sensorLogController.records.isNotEmpty,
          placeholder: const _SensorLogSkeleton(),
          child: Column(
            children: [
              if (_sensorLogController.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      Text(
                        _sensorLogController.errorMessage!,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () =>
                            unawaited(_sensorLogController.refresh()),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              else if (_sensorLogController.records.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text('No sensor records yet.')),
                ),
              ..._sensorLogController.records.map(
                (log) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Telemetry Record",
                              style: TextStyle(
                                color: theme.textTheme.bodyLarge?.color,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 8,
                              runSpacing: 2,
                              children: [
                                _sensorReading(
                                  'Chamber Temp',
                                  log.chamberTempC,
                                  '°C',
                                  1,
                                ),
                                _sensorReading(
                                  'Ambient Temp',
                                  log.temperatureC,
                                  '°C',
                                  1,
                                ),
                                _sensorReading(
                                  'Humidity',
                                  log.humidityPercent,
                                  '%',
                                  1,
                                ),
                                _sensorReading('MQ-135', log.mq135V, 'V', 2),
                                _sensorReading('MQ-2', log.mq2V, 'V', 2),
                                _sensorReading(
                                  'PM1.0',
                                  log.pm1_0UgM3,
                                  'µg/m³',
                                  0,
                                ),
                                _sensorReading(
                                  'PM2.5',
                                  log.pm2_5UgM3,
                                  'µg/m³',
                                  0,
                                ),
                                _sensorReading(
                                  'PM10',
                                  log.pm10UgM3,
                                  'µg/m³',
                                  0,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        "${log.timestamp.hour}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton(
              onPressed:
                  !_sensorLogController.isLoading &&
                      _sensorLogController.currentPage > 1
                  ? () => unawaited(_sensorLogController.previousPage())
                  : null,
              child: const Text('Previous'),
            ),
            Text(
              'Page ${_sensorLogController.currentPage} of ${_sensorLogController.pageCount}',
            ),
            TextButton(
              onPressed:
                  !_sensorLogController.isLoading &&
                      _sensorLogController.currentPage <
                          _sensorLogController.pageCount
                  ? () => unawaited(_sensorLogController.nextPage())
                  : null,
              child: const Text('Next'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sensorReading(
    String label,
    double? value,
    String unit,
    int decimals,
  ) {
    final reading = value?.toStringAsFixed(decimals) ?? '--';
    return Text(
      '$label: $reading $unit',
      style: const TextStyle(color: Colors.grey, fontSize: 12),
    );
  }
}

class _SensorLogSkeleton extends StatelessWidget {
  const _SensorLogSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: 16),
    child: Column(
      children: [
        LoadingSkeletonCard(),
        LoadingSkeletonCard(),
        LoadingSkeletonCard(margin: EdgeInsets.zero),
      ],
    ),
  );
}
