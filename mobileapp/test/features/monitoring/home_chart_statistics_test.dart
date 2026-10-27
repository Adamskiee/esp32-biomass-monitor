import 'dart:async';

import 'package:biomass_iot_app/app/app_state_provider.dart';
import 'package:biomass_iot_app/features/monitoring/chart_history.dart';
import 'package:biomass_iot_app/features/monitoring/home_tab.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Reader implements ChartHistoryReader {
  _Reader(this.read);
  final Future<ChartHistory> Function(DateTime?, DateTime) read;

  @override
  Future<ChartHistory> load({DateTime? since, required DateTime through}) =>
      read(since, through);
}

void main() {
  late AppStateProvider state;
  final time = DateTime.utc(2026, 10, 1);
  ChartHistory snapshot(double peak) => ChartHistory(
    points: [SensorData(temperatureC: 20, timestamp: time)],
    statistics: {
      SensorMetric.ambient: SensorStatistics(peak: peak, average: 25),
    },
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppStateProvider(await SharedPreferences.getInstance());
    state.history.addAll([
      SensorData(temperatureC: 10, mq2V: 0.5, timestamp: time),
      SensorData(temperatureC: 30, mq2V: 1.5, timestamp: time),
    ]);
  });
  tearDown(() => state.dispose());

  Future<void> mount(
    WidgetTester tester,
    ChartHistoryReader reader, {
    double width = 450,
    double scale = 1,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: HomeTab(chartHistoryReader: reader),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('All time'), 300);
  }

  testWidgets('Live summaries sit with charts and preserve missing values', (
    tester,
  ) async {
    await mount(tester, _Reader((_, _) async => snapshot(900)));
    expect(
      find.text('Ambient: Peak 30.0 °C · Average 20.0 °C'),
      findsOneWidget,
    );
    expect(find.text('Chamber: No data'), findsOneWidget);
    expect(find.text('MQ2: Peak 1.50 V · Average 1.00 V'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'All time displays raw history statistics instead of sampled points',
    (tester) async {
      DateTime? sinceReceived = time;
      await mount(
        tester,
        _Reader((since, through) async {
          sinceReceived = since;
          return snapshot(900);
        }),
      );
      await tester.tap(find.text('All time'));
      await tester.pumpAndSettle();
      expect(sinceReceived, isNull);
      expect(
        find.text('Ambient: Peak 900.0 °C · Average 25.0 °C'),
        findsOneWidget,
      );
      expect(
        find.text('Ambient: Peak 30.0 °C · Average 20.0 °C'),
        findsNothing,
      );
    },
  );

  testWidgets('late results cannot replace the selected period', (
    tester,
  ) async {
    final first = Completer<ChartHistory>();
    final second = Completer<ChartHistory>();
    await mount(
      tester,
      _Reader((since, through) => since == null ? second.future : first.future),
    );
    await tester.tap(find.text('1H'));
    await tester.pump();
    await tester.tap(find.text('All time'));
    await tester.pump();
    second.complete(snapshot(900));
    await tester.pumpAndSettle();
    first.complete(snapshot(100));
    await tester.pumpAndSettle();
    expect(
      find.text('Ambient: Peak 900.0 °C · Average 25.0 °C'),
      findsOneWidget,
    );
    expect(find.text('Ambient: Peak 100.0 °C · Average 25.0 °C'), findsNothing);
  });

  testWidgets('failed history can be retried without displaying Live values', (
    tester,
  ) async {
    var fails = true;
    await mount(
      tester,
      _Reader((_, _) async {
        if (fails) throw StateError('database unavailable');
        return snapshot(900);
      }),
    );
    await tester.tap(find.text('All time'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to load chart history.'), findsOneWidget);
    expect(find.text('Ambient: Peak 30.0 °C · Average 20.0 °C'), findsNothing);
    fails = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      find.text('Ambient: Peak 900.0 °C · Average 25.0 °C'),
      findsOneWidget,
    );
  });

  testWidgets('1H and 24H summaries use their selected saved periods', (
    tester,
  ) async {
    await mount(
      tester,
      _Reader(
        (since, through) async =>
            snapshot(through.difference(since!).inHours.toDouble()),
      ),
    );
    await tester.tap(find.text('1H'));
    await tester.pumpAndSettle();
    expect(find.text('Ambient: Peak 1.0 °C · Average 25.0 °C'), findsOneWidget);
    await tester.ensureVisible(find.text('24H'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24H'));
    await tester.pumpAndSettle();
    expect(
      find.text('Ambient: Peak 24.0 °C · Average 25.0 °C'),
      findsOneWidget,
    );
  });

  testWidgets('empty saved history shows a no-data state', (tester) async {
    await mount(tester, _Reader((_, _) async => ChartHistory.fromReadings([])));
    await tester.tap(find.text('All time'));
    await tester.pumpAndSettle();
    expect(find.text('No historical data available'), findsOneWidget);
    expect(find.text('Ambient: Peak 30.0 °C · Average 20.0 °C'), findsNothing);
  });

  testWidgets(
    'period controls and summaries fit a narrow screen with larger text',
    (tester) async {
      await mount(
        tester,
        _Reader((_, _) async => snapshot(900)),
        width: 320,
        scale: 1.5,
      );
      await tester.tap(find.text('All time'));
      await tester.pumpAndSettle();
      expect(
        find.text('Ambient: Peak 900.0 °C · Average 25.0 °C'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
