import 'package:biomass_iot_app/core/widgets/icon_label.dart';
import 'package:biomass_iot_app/app/app_icons.dart';
import 'package:biomass_iot_app/app/app_state_provider.dart';
import 'package:biomass_iot_app/app/app_theme.dart';
import 'package:biomass_iot_app/core/widgets/glowing_card.dart';
import 'package:biomass_iot_app/features/settings/settings_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _showAboutDialog(BuildContext context, ThemeData theme) async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              AppIcons.information,
              color: theme.colorScheme.onSurfaceVariant,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              "About the Project",
              style: TextStyle(
                color: theme.textTheme.bodyLarge?.color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Design and Evaluation of an IoT-Monitored Low-Emission Biomass Burning System for Controlled Disposal of Backyard Waste",
              style: TextStyle(
                color: AppTheme.neonGreen,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "This system provides real-time telemetry monitoring and automated safety responses for controlled biomass disposal.",
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            const Text(
              "Institution:",
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            Text(
              "Batangas State University JPLPC - Malvar Campus",
              style: TextStyle(
                color: theme.textTheme.bodyLarge?.color,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "Developers:",
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            Text(
              "Brucal, Cabaluna, Jimenez, Manalo, Vivas",
              style: TextStyle(
                color: theme.textTheme.bodyLarge?.color,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Version ${packageInfo.version} (${packageInfo.buildNumber})",
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Close",
              style: TextStyle(color: AppTheme.neonBlue),
            ),
          ),
        ],
      ),
    );
  }

  void _showDiagnosticsDialog(BuildContext context, ThemeData theme) {
    final deviceIp = context.read<AppStateProvider>().deviceIp;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              AppIcons.wifi,
              color: theme.colorScheme.onSurfaceVariant,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "Network & Hardware Diagnostics",
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Active Connection",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              "IP Address",
              style: TextStyle(
                color: theme.textTheme.bodyLarge?.color,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(deviceIp, style: const TextStyle(color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Close",
              style: TextStyle(color: AppTheme.neonBlue),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final theme = Theme.of(context);

    final isCompact = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: EdgeInsets.only(
              left: isCompact ? 16 : 24,
              right: isCompact ? 16 : 24,
              top: isCompact ? 16 : 24,
              bottom: 100,
            ),
            children: [
              IconLabel(
                color: theme.colorScheme.onSurfaceVariant,
                icon: AppIcons.preferences,
                label: 'Preferences (Auto-Saved)',
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),
              GlowingCard(
                glowColor: AppTheme.cardBorder,
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    _switchRow(
                      "Dark Mode Theme",
                      AppIcons.darkMode,
                      settings.isDarkMode,
                      theme,
                      (val) => settings.toggleTheme(),
                    ),
                    const Divider(height: 32),
                    _switchRow(
                      "Push Notifications",
                      AppIcons.alerts,
                      settings.pushNotifications,
                      theme,
                      (val) => settings.togglePush(val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              IconLabel(
                color: theme.colorScheme.onSurfaceVariant,
                icon: AppIcons.wifi,
                label: 'Telemetry Connection',
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),
              GlowingCard(
                glowColor: AppTheme.cardBorder,
                padding: const EdgeInsets.all(24),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    IconLabel(
                      color: theme.colorScheme.onSurfaceVariant,
                      icon: AppIcons.pollingInterval,
                      label: 'Polling Interval',
                      style: TextStyle(
                        color: theme.textTheme.bodyLarge?.color,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    CupertinoSegmentedControl<int>(
                      selectedColor: AppTheme.neonGreen,
                      borderColor: AppTheme.neonGreen,
                      unselectedColor: theme.cardColor,
                      groupValue: settings.pollingInterval,
                      children: const {
                        1: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text("1s"),
                        ),
                        2: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text("2s"),
                        ),
                        5: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text("5s"),
                        ),
                      },
                      onValueChanged: (val) {
                        settings.setPollingInterval(val);
                        context
                            .read<AppStateProvider>()
                            .startLiveTelemetryStream();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              GlowingCard(
                glowColor: AppTheme.cardBorder,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    Material(
                      type: MaterialType.transparency,
                      child: ListTile(
                        minLeadingWidth: 20,
                        horizontalTitleGap: 8,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        leading: Icon(
                          AppIcons.information,
                          color: theme.colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                        title: Text(
                          "About / Documentation",
                          style: TextStyle(
                            color: theme.textTheme.bodyLarge?.color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        trailing: Icon(
                          AppIcons.next,
                          color: theme.colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                        onTap: () => _showAboutDialog(context, theme),
                      ),
                    ),
                    const Divider(height: 1, indent: 24, endIndent: 24),
                    Material(
                      type: MaterialType.transparency,
                      child: ListTile(
                        minLeadingWidth: 20,
                        horizontalTitleGap: 8,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        leading: Icon(
                          AppIcons.wifi,
                          color: theme.colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                        title: Text(
                          "Network & Hardware Diagnostics",
                          style: TextStyle(
                            color: theme.textTheme.bodyLarge?.color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        trailing: Icon(
                          AppIcons.next,
                          color: theme.colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                        onTap: () => _showDiagnosticsDialog(context, theme),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _switchRow(
    String label,
    IconData icon,
    bool val,
    ThemeData theme,
    Function(bool) onChanged,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: IconLabel(
            color: theme.colorScheme.onSurfaceVariant,
            icon: icon,
            label: label,
            style: TextStyle(
              color: theme.textTheme.bodyLarge?.color,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        CupertinoSwitch(
          value: val,
          activeTrackColor: AppTheme.neonGreen,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ==========================================
// ROOT APPLICATION ENTRY
// ==========================================
