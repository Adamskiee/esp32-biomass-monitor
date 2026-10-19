import 'package:biomass_iot_app/api_service.dart';
import 'package:biomass_iot_app/app/app_state_provider.dart';
import 'widgets/safety_controls_panel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ControlTab extends StatefulWidget {
  const ControlTab({super.key});

  @override
  State<ControlTab> createState() => _ControlTabState();
}

class _ControlTabState extends State<ControlTab> {
  ApiService? _apiService;
  String? _deviceIp;
  String? _authorization;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.watch<AppStateProvider>();
    if (_deviceIp != state.deviceIp ||
        _authorization != state.authorizationHeader) {
      _apiService?.close();
      _deviceIp = state.deviceIp;
      _authorization = state.authorizationHeader;
      _apiService = state.createSafetyApiService();
    }
  }

  @override
  void dispose() {
    _apiService?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final theme = Theme.of(context);

    final isCompact = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ListView(
            padding: EdgeInsets.only(
              left: isCompact ? 16 : 24,
              right: isCompact ? 16 : 24,
              top: isCompact ? 16 : 24,
              bottom: 100,
            ),
            children: [
              if (state.isAdmin) ...[
                Text(
                  "Emergency Control & Local Alerts",
                  style: TextStyle(
                    color: theme.textTheme.bodyLarge?.color,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 16),
                SafetyControlsPanel(
                  key: ObjectKey(_apiService),
                  apiService: _apiService!,
                  observationRecorder: state.safetyObservationRecorder,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
