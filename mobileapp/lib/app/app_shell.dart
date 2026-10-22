import 'package:biomass_iot_app/app/app_icons.dart';
import 'package:biomass_iot_app/app/app_state_provider.dart';
import 'package:biomass_iot_app/app/app_theme.dart';
import 'package:biomass_iot_app/features/alerts/alerts_tab.dart';
import 'package:biomass_iot_app/features/monitoring/home_tab.dart';
import 'package:biomass_iot_app/features/monitoring/monitor_tab.dart';
import 'package:biomass_iot_app/features/safety/control_tab.dart';
import 'package:biomass_iot_app/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class MainWrapper extends StatefulWidget {
  const MainWrapper({super.key});
  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> {
  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Disconnect Terminal?"),
        content: const Text(
          "You will stop receiving live push notifications and telemetry updates.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.neonRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AppStateProvider>().logout();
            },
            child: const Text("Logout"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentTab = context.select<AppStateProvider, int>(
      (state) => state.currentTab,
    );
    final isHardwareConnected = context.select<AppStateProvider, bool>(
      (state) => state.isHardwareConnected,
    );
    final deviceIp = context.select<AppStateProvider, String>(
      (state) => state.deviceIp,
    );
    final alertCount = context.select<AppStateProvider, int>(
      (state) => state.alertCount,
    );
    final state = context.read<AppStateProvider>();
    const screens = [
      HomeTab(),
      MonitorTab(),
      ControlTab(),
      AlertsTab(),
      SettingsScreen(),
    ];
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 850;

    Widget offlineBanner = !isHardwareConnected
        ? GestureDetector(
            onTap: () => state.startLiveTelemetryStream(),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              color: AppTheme.neonRed,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    AppIcons.wifiDisconnected,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Hardware Offline: Tap to reconnect to $deviceIp",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          )
        : const SizedBox.shrink();

    return Scaffold(
      extendBody: true,
      appBar: !isDesktop
          ? AppBar(
              backgroundColor: theme.cardColor.withValues(alpha: 0.9),
              elevation: 0,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/branding/ecoburn-icon.png',
                    width: 28,
                    height: 28,
                    semanticLabel: 'EcoBurn icon',
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "EcoBurn",
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              actions: [
                Icon(
                  AppIcons.wifi,
                  color: isHardwareConnected
                      ? AppTheme.neonGreen
                      : AppTheme.neonRed,
                  size: 20,
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(
                    AppIcons.disconnect,
                    color: AppTheme.neonRed,
                    size: 20,
                  ),
                  onPressed: () => _showLogoutConfirmation(context),
                ),
                const SizedBox(width: 8),
              ],
            )
          : null,
      body: Row(
        children: [
          if (isDesktop)
            Container(
              width: 260,
              decoration: BoxDecoration(
                color: theme.cardColor,
                border: Border(right: BorderSide(color: theme.dividerColor)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 40,
                      horizontal: 20,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          AppIcons.brand,
                          color: AppTheme.neonGreen,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "ECOBURN",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _sidebarItem(
                          0,
                          AppIcons.home,
                          "Home Dashboard",
                          theme,
                          selectedIcon: AppIcons.homeSelected,
                        ),
                        _sidebarItem(
                          1,
                          AppIcons.monitor,
                          "Air Quality Monitor",
                          theme,
                        ),
                        _sidebarItem(
                          2,
                          AppIcons.control,
                          "System Control",
                          theme,
                        ),
                        _sidebarItem(
                          3,
                          AppIcons.alerts,
                          "Active Alerts",
                          theme,
                          selectedIcon: AppIcons.alertsSelected,
                          badge: alertCount,
                        ),
                        _sidebarItem(
                          4,
                          AppIcons.settings,
                          "Settings & Admin",
                          theme,
                          selectedIcon: AppIcons.settingsSelected,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.neonRed.withValues(
                          alpha: 0.1,
                        ),
                        foregroundColor: AppTheme.neonRed,
                        elevation: 0,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      icon: const Icon(AppIcons.disconnect),
                      label: const Text("Logout"),
                      onPressed: () => _showLogoutConfirmation(context),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Column(
              children: [
                offlineBanner,
                Expanded(
                  child: KeyedSubtree(
                    key: ValueKey(currentTab),
                    child: screens[currentTab],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: !isDesktop
          ? Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: theme.dividerColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 30,
                      spreadRadius: -5,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: BottomNavigationBar(
                    currentIndex: currentTab,
                    type: BottomNavigationBarType.fixed,
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    selectedItemColor: AppTheme.neonGreen,
                    unselectedItemColor: Colors.grey,
                    showSelectedLabels: false,
                    showUnselectedLabels: false,
                    onTap: (index) => state.setTab(index),
                    items: const [
                      BottomNavigationBarItem(
                        icon: Icon(AppIcons.home, size: 24),
                        activeIcon: Icon(AppIcons.homeSelected, size: 24),
                        label: 'Home',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(AppIcons.monitor, size: 24),
                        label: 'Monitor',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(AppIcons.control, size: 24),
                        label: 'Control',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(AppIcons.alerts, size: 24),
                        activeIcon: Icon(AppIcons.alertsSelected, size: 24),
                        label: 'Alerts',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(AppIcons.settings, size: 24),
                        activeIcon: Icon(AppIcons.settingsSelected, size: 24),
                        label: 'Settings',
                      ),
                    ],
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _sidebarItem(
    int index,
    IconData icon,
    String title,
    ThemeData theme, {
    IconData? selectedIcon,
    int badge = 0,
  }) {
    final currentTab = context.select<AppStateProvider, int>(
      (state) => state.currentTab,
    );
    bool isSel = currentTab == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => context.read<AppStateProvider>().setTab(index),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isSel
                ? AppTheme.neonGreen.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                isSel ? selectedIcon ?? icon : icon,
                color: isSel ? AppTheme.neonGreen : Colors.grey,
                size: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: isSel
                        ? theme.textTheme.bodyLarge?.color
                        : Colors.grey,
                    fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ),
              if (badge > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.neonOrange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// TAB 1: HOME (DASHBOARD)
// ==========================================
