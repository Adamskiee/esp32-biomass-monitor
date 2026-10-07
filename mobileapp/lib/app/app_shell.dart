import 'package:biomass_iot_app/app/app_state_provider.dart';
import 'package:biomass_iot_app/app/app_theme.dart';
import 'package:biomass_iot_app/core/widgets/glass_container.dart';
import 'package:biomass_iot_app/features/alerts/alerts_tab.dart';
import 'package:biomass_iot_app/features/monitoring/home_tab.dart';
import 'package:biomass_iot_app/features/monitoring/monitor_tab.dart';
import 'package:biomass_iot_app/features/safety/control_tab.dart';
import 'package:biomass_iot_app/features/settings/settings_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class MainWrapper extends StatefulWidget {
  const MainWrapper({super.key});
  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> {
  final List<Widget> _screens = const [
    HomeTab(),
    MonitorTab(),
    ControlTab(),
    AlertsTab(),
    SettingsScreen(),
  ];

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
    final state = context.watch<AppStateProvider>();
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 850;

    Widget offlineBanner = !state.isHardwareConnected
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
                    CupertinoIcons.wifi_slash,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Hardware Offline: Tap to reconnect to ${state.deviceIp}",
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
              title: Text(
                "IoT Biomass Terminal",
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              actions: [
                Icon(
                  CupertinoIcons.wifi,
                  color: state.isHardwareConnected
                      ? AppTheme.neonGreen
                      : AppTheme.neonRed,
                  size: 20,
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(
                    CupertinoIcons.power,
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
                          CupertinoIcons.flame_fill,
                          color: AppTheme.neonGreen,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "BIOMASS IOT",
                            style: GoogleFonts.inter(
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
                          CupertinoIcons.house_fill,
                          "Home Dashboard",
                          theme,
                        ),
                        _sidebarItem(
                          1,
                          CupertinoIcons.wind,
                          "Air Quality Monitor",
                          theme,
                        ),
                        _sidebarItem(2, Icons.tune, "System Control", theme),
                        _sidebarItem(
                          3,
                          CupertinoIcons.bell_fill,
                          "Active Alerts",
                          theme,
                          badge: state.alerts.length,
                        ),
                        _sidebarItem(
                          4,
                          CupertinoIcons.gear_solid,
                          "Settings & Admin",
                          theme,
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
                      icon: const Icon(CupertinoIcons.power),
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
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey<int>(state.currentTab),
                      child: _screens[state.currentTab],
                    ),
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
              child: GlassContainer(
                borderRadius: 30,
                color: theme.cardColor.withValues(alpha: 0.85),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: BottomNavigationBar(
                    currentIndex: state.currentTab,
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
                        icon: Icon(CupertinoIcons.house_fill, size: 26),
                        label: 'Home',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(CupertinoIcons.wind, size: 26),
                        label: 'Monitor',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.tune, size: 26),
                        label: 'Control',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(CupertinoIcons.bell_fill, size: 26),
                        label: 'Alerts',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(CupertinoIcons.bars, size: 26),
                        label: 'More',
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
    int badge = 0,
  }) {
    final state = context.watch<AppStateProvider>();
    bool isSel = state.currentTab == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => state.setTab(index),
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
                icon,
                color: isSel ? AppTheme.neonGreen : Colors.grey,
                size: 20,
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
