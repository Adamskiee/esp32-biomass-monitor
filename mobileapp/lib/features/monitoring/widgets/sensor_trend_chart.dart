import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/icon_label.dart';
import '../chart_history.dart';
import '../sensor_data.dart';
import '../telemetry_time_format.dart';

class SensorTrendChart extends StatelessWidget {
  const SensorTrendChart({
    super.key,
    required this.title,
    required this.icon,
    required this.unit,
    required this.history,
    required this.statistics,
    required this.height,
    required this.series,
    required this.isLive,
  });

  final String title;
  final IconData icon;
  final String unit;
  final List<SensorData> history;
  final Map<SensorMetric, SensorStatistics> statistics;
  final double height;
  final List<SensorTrendSeries> series;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final availableSeries = series
        .where(
          (item) => history.any((reading) => item.valueFor(reading) != null),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: IconLabel(
            icon: icon,
            label: '$title ($unit)',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        if (isLive) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final item in availableSeries)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _seriesDot(item.color),
                    const SizedBox(width: 4),
                    Text(item.label, style: const TextStyle(fontSize: 12)),
                  ],
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          height: height,
          child: availableSeries.isEmpty
              ? Center(child: Text('No readings available for $title'))
              : LineChart(
                  _buildChartData(history, theme, unit, availableSeries),
                  // Reset cached tooltips and bar animations when sensors change.
                  key: ValueKey(
                    availableSeries.map((item) => item.label).join('|'),
                  ),
                ),
        ),
        if (history.isNotEmpty && availableSeries.isNotEmpty) ...[
          const SizedBox(height: 8),
          _timeContext(context),
        ],
        const SizedBox(height: 12),
        if (isLive)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            title: const Text('Peak & average', style: TextStyle(fontSize: 13)),
            children: [_summaryTable(theme)],
          )
        else
          _summaryTable(theme),
      ],
    );
  }

  Widget _seriesDot(Color color) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  Widget _timeContext(BuildContext context) {
    final plottedReadings = history.where(
      (reading) => series.any((item) => item.valueFor(reading) != null),
    );
    final first = plottedReadings.first.timestamp;
    final last = plottedReadings.last.timestamp;
    final style = TextStyle(
      fontSize: 11,
      color: Theme.of(context).textTheme.bodySmall?.color,
    );
    if (first == last) {
      return Text(
        'Reading at ${formatTelemetryTimestamp(context, first)}',
        style: style,
      );
    }
    final sameDate = DateUtils.isSameDay(first, last);
    String label(DateTime time) => sameDate
        ? MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(time),
            alwaysUse24HourFormat: true,
          )
        : formatTelemetryTimestamp(context, time);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Semantics(
            label: 'First reading',
            child: Text(label(first), style: style),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Semantics(
            label: 'Last reading',
            child: Text(label(last), textAlign: TextAlign.end, style: style),
          ),
        ),
      ],
    );
  }

  Widget _summaryTable(ThemeData theme) {
    final textStyle = theme.textTheme.bodySmall?.copyWith(fontSize: 12);
    Widget cell(String text, {bool numeric = false, bool header = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Semantics(
            header: header,
            child: Text(
              text,
              textAlign: numeric ? TextAlign.end : TextAlign.start,
              style: header
                  ? textStyle?.copyWith(color: theme.hintColor)
                  : textStyle,
            ),
          ),
        );
    final decimals = unit == 'V' ? 2 : 1;
    String value(double? number) =>
        number?.toStringAsFixed(decimals) ?? 'No data';
    final table = Table(
      columnWidths: const {
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(1.1),
        2: FlexColumnWidth(1.1),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            cell('Sensor', header: true),
            cell('Peak ($unit)', numeric: true, header: true),
            cell('Average ($unit)', numeric: true, header: true),
          ],
        ),
        for (final item in series)
          TableRow(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _seriesDot(item.color),
                    const SizedBox(width: 5),
                    Expanded(child: Text(item.label, style: textStyle)),
                  ],
                ),
              ),
              cell(value(statistics[item.metric]?.peak), numeric: true),
              cell(value(statistics[item.metric]?.average), numeric: true),
            ],
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
        if (constraints.maxWidth >= 260 * textScale) return table;
        Widget statistic(String label, double? number) => MergeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label ($unit)',
                style: textStyle?.copyWith(color: theme.hintColor),
              ),
              const SizedBox(height: 4),
              Text(value(number), style: textStyle),
            ],
          ),
        );
        return Column(
          children: [
            for (final item in series)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: theme.dividerColor)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _seriesDot(item.color),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.label,
                            style: textStyle?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 24,
                      runSpacing: 12,
                      children: [
                        statistic('Peak', statistics[item.metric]?.peak),
                        statistic('Average', statistics[item.metric]?.average),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  LineChartData _buildChartData(
    List<SensorData> history,
    ThemeData theme,
    String unit,
    List<SensorTrendSeries> series,
  ) {
    return LineChartData(
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (spot) => theme.cardColor.withValues(alpha: 0.9),
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              final item = series[spot.barIndex];
              return LineTooltipItem(
                '${item.label}: ${spot.y.toStringAsFixed(unit == 'V' ? 2 : 1)} $unit',
                TextStyle(color: item.color, fontWeight: FontWeight.bold),
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
            minIncluded: false,
            maxIncluded: false,
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
      lineBarsData: series
          .map(
            (item) => LineChartBarData(
              spots: List.generate(
                history.length,
                (index) => item.valueFor(history[index]) == null
                    ? FlSpot.nullSpot
                    : FlSpot(index.toDouble(), item.valueFor(history[index])!),
              ),
              isCurved: true,
              color: item.color,
              barWidth: 3,
              dotData: const FlDotData(show: false),
            ),
          )
          .toList(),
    );
  }
}

class SensorTrendSeries {
  const SensorTrendSeries({
    required this.label,
    required this.color,
    required this.metric,
  });

  final String label;
  final Color color;
  final SensorMetric metric;

  double? valueFor(SensorData data) => metric.valueFor(data);
}
