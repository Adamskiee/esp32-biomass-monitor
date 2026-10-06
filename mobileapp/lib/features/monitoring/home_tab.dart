part of '../../app/legacy_ui.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  int _chartTimeframe = 0;
  List<SensorData>? _historicalData;
  bool _isLoadingHistory = false;

  Future<void> _fetchHistoricalData(int index) async {
    setState(() {
      _chartTimeframe = index;
      if (index == 0) {
        _historicalData = null;
        _isLoadingHistory = false;
      } else {
        _isLoadingHistory = true;
      }
    });

    if (index > 0) {
      int hours = index == 1 ? 1 : 24;
      final data = await DatabaseHelper().getAggregatedSensorData(hours);
      if (mounted) {
        setState(() {
          _historicalData = data;
          _isLoadingHistory = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final data = state.currentData;
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
            onRefresh: () => state.forceRefresh(),
            child: ListView(
              padding: EdgeInsets.only(
                left: isCompact ? 16 : 24,
                right: isCompact ? 16 : 24,
                top: isCompact ? 16 : 24,
                bottom: 160,
              ),
              children: [
                if (!state.isHardwareConnected)
                  const Card(
                    child: ListTile(
                      leading: Icon(CupertinoIcons.wifi_slash),
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
                        CupertinoIcons.thermometer,
                        AppTheme.neonOrange,
                        theme,
                        decimals: 1,
                        isCompact: isCompact,
                        maxVal: 50.0,
                      ),
                      _metricCard(
                        "Chamber Temp",
                        data.chamberTempC,
                        " °C",
                        CupertinoIcons.flame_fill,
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
                        CupertinoIcons.cloud_fill,
                        AppTheme.neonBlue,
                        theme,
                        decimals: 2,
                        isCompact: isCompact,
                        maxVal: 5.0,
                      ),
                      _metricCard(
                        "MQ2 Smoke",
                        data.mq2V,
                        " V",
                        CupertinoIcons.smoke_fill,
                        AppTheme.neonPurple,
                        theme,
                        decimals: 2,
                        isCompact: isCompact,
                        maxVal: 5.0,
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
                        runSpacing: 16,
                        children: [
                          Text(
                            "Real-Time Telemetry Trends",
                            style: TextStyle(
                              color: theme.textTheme.bodyLarge?.color,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          CupertinoSegmentedControl<int>(
                            selectedColor: AppTheme.neonBlue,
                            borderColor: AppTheme.neonBlue,
                            unselectedColor: theme.cardColor,
                            groupValue: _chartTimeframe,
                            children: const {
                              0: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  "Live",
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                              1: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  "1H",
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                              2: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  "24H",
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            },
                            onValueChanged: _fetchHistoricalData,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _chartTimeframe == 0
                            ? "Temperature and MQ2 voltage from recent readings. Tap chart for details."
                            : "Historical average trends.",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 24),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (_isLoadingHistory) {
                            return SizedBox(
                              height: constraints.maxWidth < 600 ? 200 : 350,
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          final chartData = _chartTimeframe == 0
                              ? state.history
                              : (_historicalData ?? []);
                          if (chartData.isEmpty) {
                            return SizedBox(
                              height: constraints.maxWidth < 600 ? 200 : 350,
                              child: const Center(
                                child: Text(
                                  "No historical data available",
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            );
                          }
                          return SizedBox(
                            height: constraints.maxWidth < 600 ? 200 : 350,
                            child: LineChart(_buildChartData(chartData, theme)),
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
                    Text(
                      "Recent Alerts",
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
                  ...state.alerts
                      .take(2)
                      .map(
                        (a) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            tileColor: theme.cardColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: theme.dividerColor),
                            ),
                            leading: Icon(
                              CupertinoIcons.exclamationmark_triangle_fill,
                              color: a.severity == 'critical'
                                  ? AppTheme.neonRed
                                  : AppTheme.neonOrange,
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
                        ),
                      ),
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
    );
  }

  LineChartData _buildChartData(List<SensorData> history, ThemeData theme) {
    List<FlSpot> tempSpots = [], coSpots = [];
    for (int i = 0; i < history.length; i++) {
      tempSpots.add(FlSpot(i.toDouble(), history[i].temperatureC ?? 0.0));
      coSpots.add(FlSpot(i.toDouble(), (history[i].mq2V ?? 0.0) * 10));
    }
    return LineChartData(
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (spot) => theme.cardColor.withValues(alpha: 0.9),
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              final isTemp = spot.barIndex == 0;
              final val = isTemp
                  ? spot.y.toStringAsFixed(1)
                  : (spot.y / 10).toStringAsFixed(2);
              return LineTooltipItem(
                '${isTemp ? "Temp" : "MQ2"}: $val${isTemp ? "°C" : "V"}',
                TextStyle(
                  color: isTemp ? AppTheme.neonOrange : AppTheme.neonRed,
                  fontWeight: FontWeight.bold,
                ),
              );
            }).toList();
          },
        ),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (val) => FlLine(
          color: theme.dividerColor.withValues(alpha: 0.5),
          strokeWidth: 1,
          dashArray: [5, 5],
        ),
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (val, _) => Text(
              val.toInt().toString(),
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: tempSpots,
          isCurved: true,
          color: AppTheme.neonOrange,
          barWidth: 4,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [
                AppTheme.neonOrange.withValues(alpha: 0.3),
                Colors.transparent,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        LineChartBarData(
          spots: coSpots,
          isCurved: true,
          color: AppTheme.neonRed,
          barWidth: 4,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [
                AppTheme.neonRed.withValues(alpha: 0.3),
                Colors.transparent,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
    );
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
                      isFault
                          ? CupertinoIcons.exclamationmark_triangle_fill
                          : icon,
                      color: displayColor,
                      size: isCompact ? 20 : 24,
                    ),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.arrow_up_right,
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
