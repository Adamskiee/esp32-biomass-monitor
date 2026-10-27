import 'package:biomass_iot_app/core/widgets/icon_label.dart';
import 'package:biomass_iot_app/app/app_icons.dart';
import 'package:biomass_iot_app/app/app_state_provider.dart';
import 'package:biomass_iot_app/app/app_theme.dart';
import 'package:biomass_iot_app/core/widgets/fluid_tile_grid.dart';
import 'package:biomass_iot_app/core/widgets/glowing_card.dart';
import 'package:biomass_iot_app/core/widgets/delayed_loading.dart';
import 'package:biomass_iot_app/core/widgets/loading_skeleton.dart';
import 'package:biomass_iot_app/core/storage/app_database.dart';
import 'package:biomass_iot_app/features/alerts/alert_presentation.dart';
import 'package:biomass_iot_app/features/alerts/alert_timestamp.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:biomass_iot_app/features/monitoring/widgets/sensor_metric_card.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'chart_history.dart';
import 'chart_history_store.dart';
import 'telemetry_time_format.dart';
import 'widgets/sensor_trend_chart.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key, this.chartHistoryReader});

  final ChartHistoryReader? chartHistoryReader;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HistoryChartsSkeleton extends StatelessWidget {
  const _HistoryChartsSkeleton({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => Column(
    children: List.generate(
      3,
      (index) => Padding(
        padding: EdgeInsets.only(bottom: index == 2 ? 0 : 16),
        child: Container(
          height: height,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LoadingSkeleton(width: 128, height: 18),
              SizedBox(height: 16),
              Expanded(
                child: LoadingSkeleton(
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _HomeTabState extends State<HomeTab> {
  int _chartTimeframe = 0;
  ChartHistory? _historicalData;
  bool _isLoadingHistory = false;
  bool _historyError = false;
  int _chartRequest = 0;
  DateTime? _snapshotSince;
  DateTime? _snapshotThrough;
  late final ChartHistoryReader _historyReader =
      widget.chartHistoryReader ?? ChartHistoryStore(AppDatabase());

  Future<void> _fetchHistoricalData(int index) async {
    final request = ++_chartRequest;
    setState(() {
      _chartTimeframe = index;
      _historicalData = null;
      _snapshotSince = null;
      _snapshotThrough = null;
      _historyError = false;
      _isLoadingHistory = index != 0;
    });
    if (index == 0) return;
    final through = DateTime.now();
    final since = index == 3
        ? null
        : through.subtract(Duration(hours: index == 1 ? 1 : 24));
    try {
      final data = await _historyReader.load(since: since, through: through);
      if (!mounted || request != _chartRequest) return;
      setState(() {
        _historicalData = data;
        _snapshotSince = since;
        _snapshotThrough = through;
        _isLoadingHistory = false;
      });
    } catch (_) {
      if (!mounted || request != _chartRequest) return;
      setState(() {
        _historyError = true;
        _isLoadingHistory = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.select<AppStateProvider, SensorData>(
      (state) => state.currentData,
    );
    final isHardwareConnected = context.select<AppStateProvider, bool>(
      (state) => state.isHardwareConnected,
    );
    context.select<AppStateProvider, int>((state) => state.telemetryRevision);
    context.select<AppStateProvider, int>((state) => state.history.length);
    final state = context.read<AppStateProvider>();
    final theme = Theme.of(context);
    final isCompact = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: RefreshIndicator(
            color: AppTheme.neonGreen,
            backgroundColor: theme.cardColor,
            onRefresh: () async {
              await state.forceRefresh();
              if (mounted && _chartTimeframe != 0) {
                await _fetchHistoricalData(_chartTimeframe);
              }
            },
            child: ListView(
              padding: EdgeInsets.only(
                left: isCompact ? 16 : 24,
                right: isCompact ? 16 : 24,
                top: isCompact ? 16 : 24,
                bottom: 160,
              ),
              children: [
                if (!isHardwareConnected)
                  const Card(
                    child: ListTile(
                      leading: Icon(AppIcons.wifiDisconnected),
                      title: Text('ESP32 disconnected'),
                      subtitle: Text('Live sensor readings are unavailable.'),
                    ),
                  )
                else
                  FluidTileGrid(
                    minTileWidth: isCompact ? 150 : 260,
                    spacing: isCompact ? 12 : 16,
                    children: [
                      _metricCard(
                        "Ambient Temp",
                        data.temperatureC,
                        " °C",
                        AppIcons.ambientTemperature,
                        AppTheme.neonOrange,
                        theme,
                        decimals: 1,
                        isCompact: isCompact,
                        maxVal: 50.0,
                      ),
                      _metricCard(
                        "Humidity",
                        data.humidityPercent,
                        " %",
                        AppIcons.humidity,
                        AppTheme.neonBlue,
                        theme,
                        decimals: 1,
                        isCompact: isCompact,
                        maxVal: 100.0,
                      ),
                      _metricCard(
                        "Chamber Temp",
                        data.chamberTempC,
                        " °C",
                        AppIcons.chamberTemperature,
                        data.chamberTempC != null && data.chamberTempC! > 100
                            ? AppTheme.neonRed
                            : AppTheme.neonOrange,
                        theme,
                        isCompact: isCompact,
                        maxVal: 150.0,
                      ),
                      _metricCard(
                        "MQ135 Gas",
                        data.mq135V,
                        " V",
                        AppIcons.gas,
                        AppTheme.neonBlue,
                        theme,
                        decimals: 2,
                        isCompact: isCompact,
                        maxVal: 5.0,
                        statusText: _mqWarmupStatus(data),
                      ),
                      _metricCard(
                        "MQ2 Smoke",
                        data.mq2V,
                        " V",
                        AppIcons.smoke,
                        AppTheme.neonPurple,
                        theme,
                        decimals: 2,
                        isCompact: isCompact,
                        maxVal: 5.0,
                        statusText: _mqWarmupStatus(data),
                      ),
                      _metricCard(
                        "PM1.0",
                        data.pm1_0UgM3,
                        " µg/m³",
                        AppIcons.particulateMatter,
                        AppTheme.neonBlue,
                        theme,
                        decimals: 1,
                        isCompact: isCompact,
                        maxVal: 500.0,
                      ),
                      _metricCard(
                        "PM2.5",
                        data.pm2_5UgM3,
                        " µg/m³",
                        AppIcons.particulateMatter,
                        AppTheme.neonPurple,
                        theme,
                        decimals: 1,
                        isCompact: isCompact,
                        maxVal: 500.0,
                      ),
                      _metricCard(
                        "PM10",
                        data.pm10UgM3,
                        " µg/m³",
                        AppIcons.particulateMatter,
                        AppTheme.neonOrange,
                        theme,
                        decimals: 1,
                        isCompact: isCompact,
                        maxVal: 500.0,
                      ),
                    ],
                  ),
                const SizedBox(height: 32),

                GlowingCard(
                  glowColor: AppTheme.neonBlue,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          IconLabel(
                            icon: AppIcons.trends,
                            label: 'Telemetry Trends',
                            style: TextStyle(
                              color: theme.textTheme.bodyLarge?.color,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final entry in const {
                                0: 'Live',
                                1: '1H',
                                2: '24H',
                                3: 'All time',
                              }.entries)
                                ChoiceChip(
                                  label: Text(entry.value),
                                  selected: _chartTimeframe == entry.key,
                                  onSelected: (_) =>
                                      _fetchHistoricalData(entry.key),
                                ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (_chartTimeframe == 0)
                        Text(
                          'Recent ${state.history.length} readings${isHardwareConnected ? ' · Updating live' : ''}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        )
                      else if (_snapshotThrough != null) ...[
                        Text(
                          _snapshotSince == null
                              ? 'All saved readings · As of ${formatTelemetryTimestamp(context, _snapshotThrough!)}'
                              : 'Selected period: ${formatTelemetryTimestamp(context, _snapshotSince!)} – ${formatTelemetryTimestamp(context, _snapshotThrough!)}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Pull down to refresh',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 24),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final chartHistory = _chartTimeframe == 0
                              ? ChartHistory.fromReadings(state.history)
                              : (_historicalData ??
                                    ChartHistory.fromReadings([]));
                          final chartData = chartHistory.points;
                          if (_historyError) {
                            return Column(
                              children: [
                                const Text('Unable to load chart history.'),
                                TextButton(
                                  onPressed: () =>
                                      _fetchHistoricalData(_chartTimeframe),
                                  child: const Text('Retry'),
                                ),
                              ],
                            );
                          }
                          return DelayedLoading(
                            isLoading: _isLoadingHistory,
                            hasContent: chartData.isNotEmpty,
                            placeholder: _HistoryChartsSkeleton(
                              height: constraints.maxWidth < 600 ? 200 : 350,
                            ),
                            child: Builder(
                              builder: (context) {
                                if (chartData.isEmpty) {
                                  return SizedBox(
                                    height: constraints.maxWidth < 600
                                        ? 200
                                        : 350,
                                    child: const Center(
                                      child: Text(
                                        "No historical data available",
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ),
                                  );
                                }
                                final chartHeight = constraints.maxWidth < 600
                                    ? 200.0
                                    : 250.0;
                                return Column(
                                  children: [
                                    SensorTrendChart(
                                      key: ValueKey(
                                        'Temperature-$_chartTimeframe',
                                      ),
                                      title: 'Temperature',
                                      icon: AppIcons.ambientTemperature,
                                      unit: '°C',
                                      history: chartData,
                                      statistics: chartHistory.statistics,
                                      isLive: _chartTimeframe == 0,
                                      height: chartHeight,
                                      series: [
                                        SensorTrendSeries(
                                          label: 'Ambient',
                                          color: AppTheme.neonOrange,
                                          metric: SensorMetric.ambient,
                                        ),
                                        SensorTrendSeries(
                                          label: 'Chamber',
                                          color: AppTheme.neonRed,
                                          metric: SensorMetric.chamber,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 24),
                                    SensorTrendChart(
                                      key: ValueKey(
                                        'Gas Sensors-$_chartTimeframe',
                                      ),
                                      title: 'Gas Sensors',
                                      icon: AppIcons.gas,
                                      unit: 'V',
                                      history: chartData,
                                      statistics: chartHistory.statistics,
                                      isLive: _chartTimeframe == 0,
                                      height: chartHeight,
                                      series: [
                                        SensorTrendSeries(
                                          label: 'MQ2',
                                          color: AppTheme.neonPurple,
                                          metric: SensorMetric.mq2,
                                        ),
                                        SensorTrendSeries(
                                          label: 'MQ135',
                                          color: AppTheme.neonBlue,
                                          metric: SensorMetric.mq135,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 24),
                                    SensorTrendChart(
                                      key: ValueKey(
                                        'Humidity-$_chartTimeframe',
                                      ),
                                      title: 'Humidity',
                                      icon: AppIcons.humidity,
                                      unit: '%',
                                      history: chartData,
                                      statistics: chartHistory.statistics,
                                      isLive: _chartTimeframe == 0,
                                      height: chartHeight,
                                      series: [
                                        SensorTrendSeries(
                                          label: 'Relative humidity',
                                          color: AppTheme.neonBlue,
                                          metric: SensorMetric.humidity,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 24),
                                    SensorTrendChart(
                                      key: ValueKey(
                                        'Particulate Matter-$_chartTimeframe',
                                      ),
                                      title: 'Particulate Matter',
                                      icon: AppIcons.particulateMatter,
                                      unit: 'µg/m³',
                                      history: chartData,
                                      statistics: chartHistory.statistics,
                                      isLive: _chartTimeframe == 0,
                                      height: chartHeight,
                                      series: [
                                        SensorTrendSeries(
                                          label: 'PM1.0',
                                          color: AppTheme.neonGreen,
                                          metric: SensorMetric.pm1,
                                        ),
                                        SensorTrendSeries(
                                          label: 'PM2.5',
                                          color: AppTheme.neonBlue,
                                          metric: SensorMetric.pm25,
                                        ),
                                        SensorTrendSeries(
                                          label: 'PM10',
                                          color: AppTheme.neonOrange,
                                          metric: SensorMetric.pm10,
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconLabel(
                      icon: AppIcons.alerts,
                      label: 'Recent Alerts',
                      style: TextStyle(
                        color: theme.textTheme.bodyLarge?.color,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          context.read<AppStateProvider>().setTab(3),
                      child: const Text(
                        "See all",
                        style: TextStyle(color: AppTheme.neonGreen),
                      ),
                    ),
                  ],
                ),
                if (state.alerts.isNotEmpty)
                  ...state.alerts.take(2).map((a) {
                    final presentation = alertPresentationForSeverity(
                      a.severity,
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        tileColor: theme.cardColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: theme.dividerColor),
                        ),
                        leading: Icon(
                          presentation.icon,
                          color: presentation.color,
                        ),
                        title: Text(
                          a.title,
                          style: TextStyle(
                            color: theme.textTheme.bodyLarge?.color,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          formatAlertTimestamp(a.timestamp),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metricCard(
    String title,
    double? value,
    String suffix,
    IconData icon,
    Color color,
    ThemeData theme, {
    int decimals = 0,
    bool isCompact = false,
    double maxVal = 100.0,
    String? statusText,
  }) {
    return SensorMetricCard(
      title: title,
      value: value,
      suffix: suffix,
      icon: icon,
      color: color,
      theme: theme,
      decimals: decimals,
      isCompact: isCompact,
      maxVal: maxVal,
      statusText: statusText,
    );
  }

  String? _mqWarmupStatus(SensorData data) {
    if (!data.isMqWarmingUp) return null;
    if (data.mqWarmupRemainingSeconds == 0) {
      return 'Warming up: finishing...';
    }
    final minutes = (data.mqWarmupRemainingSeconds / 60).ceil();
    return 'Warming up: $minutes min remaining';
  }
}

class LegacySensorMetricCard extends StatelessWidget {
  const LegacySensorMetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.suffix,
    required this.icon,
    required this.color,
    required this.theme,
    this.decimals = 0,
    this.isCompact = false,
    this.maxVal = 100.0,
  });

  final String title;
  final double? value;
  final String suffix;
  final IconData icon;
  final Color color;
  final ThemeData theme;
  final int decimals;
  final bool isCompact;
  final double maxVal;

  @override
  Widget build(BuildContext context) {
    final isFault = value == null;
    final displayColor = isFault ? Colors.amber : color;

    return GlowingCard(
      glowColor: displayColor,
      padding: EdgeInsets.all(isCompact ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: isCompact ? 40 : 48,
                height: isCompact ? 40 : 48,
                decoration: BoxDecoration(
                  color: displayColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (!isFault)
                      TweenAnimationBuilder<double>(
                        duration: const Duration(seconds: 1),
                        curve: Curves.easeOutExpo,
                        tween: Tween<double>(
                          begin: 0.0,
                          end: (value! / maxVal).clamp(0.0, 1.0),
                        ),
                        builder: (context, progress, _) =>
                            CircularProgressIndicator(
                              value: progress,
                              backgroundColor: displayColor.withValues(
                                alpha: 0.1,
                              ),
                              color: displayColor,
                              strokeWidth: 3,
                            ),
                      ),
                    Icon(
                      isFault ? AppIcons.warning : icon,
                      color: displayColor,
                      size: isCompact ? 20 : 24,
                    ),
                  ],
                ),
              ),
              Icon(
                AppIcons.openDetails,
                color: Colors.grey.withValues(alpha: 0.5),
                size: 16,
              ),
            ],
          ),
          SizedBox(height: isCompact ? 16 : 24),
          Text(
            title,
            style: TextStyle(
              color: Colors.grey,
              fontSize: isCompact ? 12 : 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          if (isFault)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '--',
                  style: TextStyle(
                    color: theme.textTheme.bodyLarge?.color,
                    fontSize: isCompact ? 24 : 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sensor fault',
                  style: TextStyle(
                    color: displayColor,
                    fontSize: isCompact ? 11 : 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            )
          else
            TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutExpo,
              tween: Tween<double>(begin: 0.0, end: value!),
              builder: (context, animatedValue, _) => Text(
                '${animatedValue.toStringAsFixed(decimals)}$suffix',
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontSize: isCompact ? 24 : 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ==========================================
// TAB 2: MONITOR (ANALYTICS & CSV EXPORT)
// ==========================================
