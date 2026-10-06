part of 'legacy_ui.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return MaterialApp(
      title: 'Biomass IoT Monitor',
      debugShowCheckedModeBanner: false,
      theme: settings.isDarkMode
          ? AppTheme.getDarkTheme()
          : AppTheme.getLightTheme(),
      home: Consumer<AppStateProvider>(
        builder: (context, state, _) =>
            state.isAuthenticated ? const MainWrapper() : const LoginScreen(),
      ),
      routes: {
        '/dashboard': (context) {
          final state = context.read<AppStateProvider>();
          return DashboardScreen(
            apiService: ApiService(
              baseUrl: 'http://${state.deviceIp}/api',
              authorizationHeader: state._basicAuthHeader,
            ),
          );
        },
      },
    );
  }
}
