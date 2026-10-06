import 'package:biomass_iot_app/features/alerts/alerts_controller.dart';
import 'package:biomass_iot_app/features/authentication/session_controller.dart';
import 'package:biomass_iot_app/features/monitoring/telemetry_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index = widget.initialTab;
  @override
  Widget build(BuildContext context) {
    final telemetry = context.watch<TelemetryController>();
    final alerts = context.watch<AlertsController>();
    final session = context.read<SessionController>();
    final pages = [
      Center(
        child: Text('Chamber ${telemetry.currentData.chamberTempC ?? '--'}'),
      ),
      Center(child: Text('History: ${telemetry.history.length} readings')),
      const Center(child: Text('Controls')),
      Center(child: Text('Alerts: ${alerts.alerts.length}')),
      Center(
        child: FilledButton(
          onPressed: () {
            telemetry.stop();
            session.logout();
          },
          child: const Text('Log out'),
        ),
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          telemetry.isHardwareConnected
              ? session.deviceIp
              : '${session.deviceIp} (offline)',
        ),
      ),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.monitor), label: 'Monitor'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Control'),
          NavigationDestination(icon: Icon(Icons.warning), label: 'Alerts'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
