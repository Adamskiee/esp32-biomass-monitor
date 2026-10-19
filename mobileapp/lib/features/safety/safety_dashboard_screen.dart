import 'package:flutter/material.dart';

import '../../api_service.dart';
import 'safety_observation_recorder.dart';
import 'widgets/safety_controls_panel.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.apiService,
    this.observationRecorder,
    this.onAlert,
  });

  final ApiService apiService;
  final SafetyObservationRecorder? observationRecorder;
  final VoidCallback? onAlert;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void didUpdateWidget(DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiService != widget.apiService) oldWidget.apiService.close();
  }

  @override
  void dispose() {
    widget.apiService.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('EcoBurn Safety Dashboard')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SafetyControlsPanel(
          key: ObjectKey(widget.apiService),
          apiService: widget.apiService,
          observationRecorder: widget.observationRecorder,
          onAlert: widget.onAlert,
        ),
      ],
    ),
  );
}
