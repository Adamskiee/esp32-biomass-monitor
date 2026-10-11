import 'dart:async';

import 'package:biomass_iot_app/app/app_state_provider.dart';
import 'package:biomass_iot_app/app/app_theme.dart';
import 'package:biomass_iot_app/core/storage/app_database.dart';
import 'package:biomass_iot_app/core/widgets/fluid_tile_grid.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_history_store.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_log_controller.dart';
import 'package:biomass_iot_app/features/monitoring/pms_readings.dart';
import 'package:biomass_iot_app/features/monitoring/telemetry_csv.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../experiments/attempts_section.dart';

class MonitorTab extends StatefulWidget {
  const MonitorTab({super.key, this.sensorLogController});

  final SensorLogController? sensorLogController;

  @override
  State<MonitorTab> createState() => _MonitorTabState();
}

class _MonitorTabState extends State<MonitorTab> {
  int _segIndex = 0;
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

  void _exportCSV(
    BuildContext context,
    ThemeData theme,
    List<SensorData> history,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Export Telemetry Data",
              style: TextStyle(
                color: theme.textTheme.bodyLarge?.color,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Select the parameters for your CSV report.",
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ListTile(
              title: Text(
                "Date Range",
                style: TextStyle(color: theme.textTheme.bodyLarge?.color),
              ),
              trailing: const Text(
                "Current Session",
                style: TextStyle(color: AppTheme.neonGreen),
              ),
              tileColor: theme.scaffoldBackgroundColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              title: Text(
                "Include Sensors",
                style: TextStyle(color: theme.textTheme.bodyLarge?.color),
              ),
              trailing: const Text(
                "Temperature, chamber, MQ135, MQ2, PMS",
                style: TextStyle(color: AppTheme.neonGreen),
              ),
              tileColor: theme.scaffoldBackgroundColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.neonGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(CupertinoIcons.share),
                label: const Text(
                  "GENERATE & SHARE CSV",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _generateAndShareCSV(history);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _generateAndShareCSV(List<SensorData> history) {
    if (history.isEmpty) return;
    // ignore: deprecated_member_use
    Share.share(buildTelemetryCsv(history), subject: 'Biomass_Telemetry_Export.csv');
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
                        child: Text("Sensors Log"),
                      ),
                      1: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text("Air Quality"),
                      ),
                      2: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text("Attempts"),
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
                      : _segIndex == 2
                      ? const AttemptsSection()
                      : state.isHardwareConnected
                      ? _buildAirQualityView(state.currentData, theme)
                      : const Center(
                          child: Text(
                            'ESP32 disconnected. Air quality is unavailable.',
                          ),
                        ),
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
    final stats = state.getSessionAnalytics();
    final isCompact = MediaQuery.of(context).size.width < 600;

    return ListView(
      key: const ValueKey(0),
      padding: EdgeInsets.only(
        left: isCompact ? 16 : 24,
        right: isCompact ? 16 : 24,
        bottom: 100,
      ),
      children: [
        Text(
          "Session Analytics",
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 16),
        FluidTileGrid(
          minTileWidth: 200,
          children: [
            _statCard(
              "Peak Temp",
              "${stats['maxT']} °C",
              AppTheme.neonOrange,
              theme,
            ),
            _statCard(
              "Peak MQ2",
              "${stats['maxMq2']} V",
              AppTheme.neonRed,
              theme,
            ),
            _statCard(
              "Avg Temp",
              "${stats['avgT']} °C",
              AppTheme.neonOrange,
              theme,
            ),
            _statCard(
              "Avg MQ2",
              "${stats['avgMq2']} V",
              AppTheme.neonRed,
              theme,
            ),
          ],
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                "Sensor Data Log",
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(
                CupertinoIcons.arrow_down_doc,
                color: AppTheme.neonGreen,
              ),
              onPressed: () => _exportCSV(context, theme, state.history),
              tooltip: "Export CSV",
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
              icon: const Icon(CupertinoIcons.refresh),
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
              icon: const Icon(CupertinoIcons.arrow_up),
              label: const Text('New records available'),
            ),
          ),
        const SizedBox(height: 8),
        if (_sensorLogController.isLoading &&
            _sensorLogController.records.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_sensorLogController.errorMessage != null)
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
                  onPressed: () => unawaited(_sensorLogController.refresh()),
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
                      Text(
                        "Chamber: ${log.chamberTempC?.toStringAsFixed(1) ?? '--'}°C | MQ2: ${log.mq2V?.toStringAsFixed(2) ?? '--'}V | Temp: ${log.temperatureC?.toStringAsFixed(1) ?? '--'}°C",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "PM1.0: ${log.pm1_0UgM3?.toStringAsFixed(0) ?? '--'} | PM2.5: ${log.pm2_5UgM3?.toStringAsFixed(0) ?? '--'} | PM10: ${log.pm10UgM3?.toStringAsFixed(0) ?? '--'} µg/m³",
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  "${log.timestamp.hour}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}",
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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

  Widget _statCard(String title, String val, Color color, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            val,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAirQualityView(SensorData data, ThemeData theme) {
    final isCompact = MediaQuery.of(context).size.width < 600;

    return ListView(
      key: const ValueKey(1),
      padding: EdgeInsets.only(
        left: isCompact ? 16 : 24,
        right: isCompact ? 16 : 24,
        bottom: 100,
      ),
      children: [
        Text(
          "Reported Gas Sensor Voltages",
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 24),
        _pollutantBar(
          "MQ135 Gas Voltage",
          (data.mq135V ?? 0) / 5.0,
          AppTheme.neonOrange,
          "${(data.mq135V ?? 0).toStringAsFixed(2)} V",
          theme,
        ),
        const SizedBox(height: 24),
        PmsReadings(data: data),
        const SizedBox(height: 24),
        _pollutantBar(
          "MQ2 Smoke/Gas Voltage",
          (data.mq2V ?? 0) / 5.0,
          AppTheme.neonPurple,
          "${(data.mq2V ?? 0).toStringAsFixed(2)} V",
          theme,
        ),
      ],
    );
  }

  Widget _pollutantBar(
    String label,
    double percent,
    Color color,
    String valLabel,
    ThemeData theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              valLabel,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 1000),
          curve: Curves.easeOutCubic,
          tween: Tween<double>(begin: 0.0, end: percent.clamp(0.0, 1.0)),
          builder: (context, value, _) => ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: value,
              backgroundColor: theme.dividerColor.withValues(alpha: 0.5),
              color: color,
              minHeight: 14,
            ),
          ),
        ),
      ],
    );
  }
}

// ==========================================
// TAB 3: CONTROL (NETWORK, AUDIT LOG & CALIBRATION)
// ==========================================
