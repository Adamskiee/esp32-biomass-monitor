import 'dart:math' as math;

import 'package:flutter/material.dart';

class SafetyThresholdSlider extends StatefulWidget {
  const SafetyThresholdSlider({
    super.key,
    required this.field,
    required this.label,
    required this.unit,
    required this.controller,
    required this.saved,
    required this.minimum,
    required this.maximum,
    required this.step,
    required this.enabled,
    required this.onChanged,
    this.onDefault,
    this.expandRange = false,
  });

  final String field;
  final String label;
  final String unit;
  final TextEditingController controller;
  final double? saved;
  final double minimum;
  final double maximum;
  final double step;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final bool expandRange;
  final VoidCallback? onDefault;

  @override
  State<SafetyThresholdSlider> createState() => _SafetyThresholdSliderState();
}

class _SafetyThresholdSliderState extends State<SafetyThresholdSlider> {
  late double _displayMaximum;

  @override
  void initState() {
    super.initState();
    _displayMaximum = widget.expandRange ? 500 : widget.maximum;
    _extendRange();
    widget.controller.addListener(_textChanged);
  }

  @override
  void didUpdateWidget(SafetyThresholdSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_textChanged);
      widget.controller.addListener(_textChanged);
    }
    if (oldWidget.field != widget.field ||
        oldWidget.maximum != widget.maximum ||
        oldWidget.expandRange != widget.expandRange) {
      _displayMaximum = widget.expandRange ? 500 : widget.maximum;
    }
    _extendRange();
  }

  void _extendRange() {
    if (!widget.expandRange) return;
    for (final value in [_number(widget.controller.text), widget.saved]) {
      if (value != null && value.isFinite && value > _displayMaximum) {
        _displayMaximum = math.min(
          widget.maximum,
          (value / 100).ceil() * 100.0,
        );
      }
    }
  }

  void _textChanged() => setState(_extendRange);

  @override
  void dispose() {
    widget.controller.removeListener(_textChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value =
        (_number(widget.controller.text) ?? widget.saved ?? widget.minimum)
            .clamp(widget.minimum, _displayMaximum)
            .toDouble();
    return _SliderControls(
      field: widget.field,
      label: widget.label,
      enabled: widget.enabled,
      onDefault: widget.onDefault,
      builder: (editing) => Column(
        children: [
          Semantics(
            label: '${widget.label} limit',
            child: Slider(
              key: ValueKey('${widget.field}_slider'),
              min: widget.minimum,
              max: _displayMaximum,
              value: value,
              label: _withUnit(value, widget.unit),
              semanticFormatterCallback: (value) =>
                  _withUnit(value, widget.unit),
              onChanged: editing
                  ? (value) {
                      final snapped =
                          ((value / widget.step).round() * widget.step)
                              .clamp(widget.minimum, _displayMaximum)
                              .toDouble();
                      final text = _text(snapped);
                      widget.controller.text = text;
                      widget.onChanged(text);
                    }
                  : null,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(_withUnit(widget.minimum, widget.unit))),
              Flexible(
                child: Text(
                  _withUnit(_displayMaximum, widget.unit),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SafetyHumidityRangeSlider extends StatelessWidget {
  const SafetyHumidityRangeSlider({
    super.key,
    required this.minimumController,
    required this.maximumController,
    required this.enabled,
    required this.onChanged,
    this.onDefault,
  });

  final TextEditingController minimumController;
  final TextEditingController maximumController;
  final bool enabled;
  final void Function(String field, String text) onChanged;
  final VoidCallback? onDefault;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([minimumController, maximumController]),
    builder: (context, _) {
      final minimum = (_number(minimumController.text) ?? 0).clamp(0.0, 100.0);
      final maximum = (_number(maximumController.text) ?? 100).clamp(
        0.0,
        100.0,
      );
      final values = RangeValues(
        math.min(minimum, maximum).toDouble(),
        math.max(minimum, maximum).toDouble(),
      );
      return _SliderControls(
        field: 'humidity_range',
        label: 'Humidity',
        enabled: enabled,
        onDefault: onDefault,
        builder: (editing) => Column(
          children: [
            Semantics(
              label: 'Humidity limits',
              child: RangeSlider(
                key: const ValueKey('humidity_range_slider'),
                min: 0,
                max: 100,
                values: values,
                labels: RangeLabels(
                  _withUnit(values.start, '%'),
                  _withUnit(values.end, '%'),
                ),
                semanticFormatterCallback: (value) => _withUnit(value, '%'),
                onChanged: editing
                    ? (values) {
                        final start =
                            values.start == _number(minimumController.text)
                            ? values.start
                            : values.start.roundToDouble().clamp(0.0, 100.0);
                        final end =
                            values.end == _number(maximumController.text)
                            ? values.end
                            : values.end.roundToDouble().clamp(0.0, 100.0);
                        if (start >= end) return;
                        _edit(
                          minimumController,
                          'threshold_humidity_min_percent',
                          start,
                        );
                        _edit(
                          maximumController,
                          'threshold_humidity_max_percent',
                          end,
                        );
                      }
                    : null,
              ),
            ),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('0 %'), Text('100 %')],
            ),
          ],
        ),
      );
    },
  );

  void _edit(TextEditingController controller, String field, double value) {
    if (_number(controller.text) == value) return;
    final text = _text(value);
    controller.text = text;
    onChanged(field, text);
  }
}

class _SliderControls extends StatelessWidget {
  const _SliderControls({
    required this.field,
    required this.label,
    required this.enabled,
    required this.builder,
    this.onDefault,
  });

  final String field;
  final String label;
  final bool enabled;
  final Widget Function(bool enabled) builder;
  final VoidCallback? onDefault;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      builder(enabled),
      if (onDefault != null)
        Align(
          alignment: Alignment.centerRight,
          child: Tooltip(
            message: 'Restore $label default',
            child: TextButton.icon(
              key: ValueKey('${field}_slider_default'),
              onPressed: enabled ? onDefault : null,
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('Default'),
            ),
          ),
        ),
    ],
  );
}

double? _number(String text) {
  final value = double.tryParse(text);
  return value != null && value.isFinite ? value : null;
}

String _text(double value) => value == value.truncateToDouble()
    ? value.truncate().toString()
    : value.toStringAsFixed(1);

String _withUnit(double value, String unit) =>
    '${value == value.truncateToDouble() ? value.truncate() : value} $unit';
