import 'package:biomass_iot_app/app/app_shell.dart';
import 'package:biomass_iot_app/app/app_theme.dart';
import 'package:biomass_iot_app/features/authentication/session_controller.dart';
import 'package:biomass_iot_app/features/monitoring/telemetry_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class BiomassApp extends StatelessWidget {
  const BiomassApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Biomass Monitor',
    theme: AppTheme.getLightTheme(),
    darkTheme: AppTheme.getDarkTheme(),
    home: Consumer<SessionController>(
      builder: (context, session, _) =>
          session.isAuthenticated ? const AppShell() : const LoginScreen(),
    ),
    routes: {'/dashboard': (_) => const AppShell(initialTab: 2)},
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _ip = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ip.text.isEmpty) _ip.text = context.read<SessionController>().deviceIp;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Connect to ESP32')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          TextField(
            controller: _ip,
            decoration: const InputDecoration(labelText: 'ESP32 IP address'),
          ),
          TextField(
            controller: _username,
            decoration: const InputDecoration(labelText: 'Username'),
          ),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          FilledButton(
            onPressed: () async {
              final session = context.read<SessionController>();
              final telemetry = context.read<TelemetryController>();
              final accepted = await session.login(
                ipAddress: _ip.text,
                username: _username.text,
                password: _password.text,
              );
              if (accepted) {
                telemetry.start();
              }
              if (!accepted && mounted) {
                setState(
                  () => _error = 'Unable to authenticate with this device.',
                );
              }
            },
            child: const Text('Log in'),
          ),
        ],
      ),
    ),
  );
}
