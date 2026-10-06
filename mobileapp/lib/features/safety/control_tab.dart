part of '../../app/legacy_ui.dart';

class ControlTab extends StatelessWidget {
  const ControlTab({super.key});

  void _showCalibrationDialog(
    BuildContext context,
    String sensor,
    double currentVal,
    SettingsProvider settings,
  ) {
    double tempVal = currentVal;
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: theme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            "Calibrate $sensor",
            style: TextStyle(
              color: theme.textTheme.bodyLarge?.color,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Adjust analog ADC voltage offset. Incorrect values may trigger false hardware alarms.",
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 24),
              Text(
                "${tempVal > 0 ? '+' : ''}${tempVal.toStringAsFixed(1)} mV",
                style: const TextStyle(
                  color: AppTheme.neonBlue,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              CupertinoSlider(
                value: tempVal.clamp(-15.0, 15.0),
                min: -15.0,
                max: 15.0,
                activeColor: AppTheme.neonBlue,
                onChanged: (val) => setDialogState(() => tempVal = val),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.neonBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                settings.setMqOffset(tempVal);
                Navigator.pop(ctx);
              },
              child: const Text("Apply Update"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final settings = context.watch<SettingsProvider>();
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
              Text(
                "Network & Hardware Diagnostics",
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),
              FluidTileGrid(
                minTileWidth: 300,
                children: [
                  GlowingCard(
                    glowColor: AppTheme.neonBlue,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Active Connection",
                              style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _infoRow(
                          CupertinoIcons.wifi,
                          "IP Address",
                          state.deviceIp,
                          AppTheme.neonBlue,
                          theme,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),

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
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  tileColor: theme.cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: theme.dividerColor),
                  ),
                  leading: const Icon(
                    Icons.dashboard_outlined,
                    color: AppTheme.neonGreen,
                    size: 28,
                  ),
                  title: Text(
                    "Biomass Monitor Safety Dashboard",
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: const Text(
                    "Direct ESP32 Sprinkler Control & Danger Alerts",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  trailing: const Icon(
                    CupertinoIcons.chevron_right,
                    color: Colors.grey,
                    size: 18,
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DashboardScreen(
                        apiService: ApiService(
                          baseUrl: 'http://${state.deviceIp}/api',
                          authorizationHeader: state._basicAuthHeader,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                Text(
                  "Hardware Audit Log",
                  style: TextStyle(
                    color: theme.textTheme.bodyLarge?.color,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: state.auditLogs.length,
                    itemBuilder: (ctx, i) {
                      final log = state.auditLogs[i];
                      return ListTile(
                        leading: const Icon(
                          CupertinoIcons.text_badge_checkmark,
                          color: AppTheme.neonGreen,
                        ),
                        title: Text(
                          log.action,
                          style: TextStyle(
                            color: theme.textTheme.bodyLarge?.color,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          "User: ${log.user}",
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 11,
                          ),
                        ),
                        trailing: Text(
                          log.timestamp,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 11,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 40),
              ],

              Text(
                "Sensor Calibration (Admin Override)",
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),
              if (!state.isAdmin)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.neonRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.neonRed.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(CupertinoIcons.lock_fill, color: AppTheme.neonRed),
                      SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          "Calibration requires Administrator authentication.",
                          style: TextStyle(
                            color: AppTheme.neonRed,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                const Text(
                  "Tap a sensor below to apply resistance offsets to the ESP32 microcontroller.",
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 20),
                _calibTile(
                  "MQ-2 (Combustible Gas)",
                  "Offset: ${settings.mqCalibOffset.toStringAsFixed(1)} mV",
                  theme,
                  () => _showCalibrationDialog(
                    context,
                    "MQ-2",
                    settings.mqCalibOffset,
                    settings,
                  ),
                ),
                const SizedBox(height: 12),
                _calibTile(
                  "MQ-135 (Air Quality)",
                  "Offset: 0.0 mV",
                  theme,
                  () =>
                      _showCalibrationDialog(context, "MQ-135", 0.0, settings),
                ),
                const SizedBox(height: 12),
                _calibTile(
                  "DHT22 (Temperature)",
                  "Offset: -0.5 °C",
                  theme,
                  () {},
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(
    IconData icon,
    String title,
    String val,
    Color color,
    ThemeData theme,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: theme.textTheme.bodyLarge?.color,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Text(val, style: const TextStyle(color: Colors.grey, fontSize: 13)),
      ],
    );
  }

  Widget _calibTile(
    String title,
    String subtitle,
    ThemeData theme,
    VoidCallback onTap,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      tileColor: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: theme.textTheme.bodyLarge?.color,
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(subtitle, style: const TextStyle(color: Colors.grey)),
      ),
      trailing: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          CupertinoIcons.slider_horizontal_3,
          color: AppTheme.neonBlue,
          size: 20,
        ),
      ),
      onTap: onTap,
    );
  }
}

// ==========================================
// TAB 4: ALERTS
// ==========================================
