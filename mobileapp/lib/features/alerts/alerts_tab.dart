part of '../../app/legacy_ui.dart';

class AlertsTab extends StatefulWidget {
  const AlertsTab({super.key});
  @override
  State<AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends State<AlertsTab> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final theme = Theme.of(context);
    final isCompact = MediaQuery.of(context).size.width < 600;
    List<AlertItem> filteredAlerts = state.alerts;
    if (_filter != 'All') {
      filteredAlerts = state.alerts
          .where((a) => a.severity.toLowerCase() == _filter.toLowerCase())
          .toList();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.all(isCompact ? 16 : 24),
                child: GlowingCard(
                  glowColor: AppTheme.neonOrange,
                  padding: EdgeInsets.all(isCompact ? 16 : 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Session Summary",
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "${state.alerts.length} alerts today",
                            style: TextStyle(
                              color: theme.textTheme.bodyLarge?.color,
                              fontWeight: FontWeight.w900,
                              fontSize: 24,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.neonRed.withValues(
                            alpha: 0.1,
                          ),
                          foregroundColor: AppTheme.neonRed,
                          elevation: 0,
                        ),
                        onPressed: state.clearAllAlerts,
                        icon: const Icon(CupertinoIcons.trash, size: 18),
                        label: const Text(
                          "Clear All",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 24),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoSegmentedControl<String>(
                    selectedColor: AppTheme.neonOrange,
                    borderColor: AppTheme.neonOrange,
                    unselectedColor: theme.cardColor,
                    groupValue: _filter,
                    children: const {
                      'All': Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text("All"),
                      ),
                      'Info': Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text("Info"),
                      ),
                      'Warning': Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text("Warning"),
                      ),
                      'Critical': Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text("Critical"),
                      ),
                    },
                    onValueChanged: (val) {
                      setState(() => _filter = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: filteredAlerts.isEmpty
                    ? const Center(
                        child: Text(
                          "No alerts found.",
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.only(
                          left: isCompact ? 16 : 24,
                          right: isCompact ? 16 : 24,
                          bottom: 100,
                        ),
                        itemCount: filteredAlerts.length,
                        itemBuilder: (ctx, i) {
                          final alert = filteredAlerts[i];
                          Color color = alert.severity == 'critical'
                              ? AppTheme.neonRed
                              : (alert.severity == 'warning'
                                    ? AppTheme.neonOrange
                                    : AppTheme.neonBlue);
                          IconData icon = alert.severity == 'critical'
                              ? CupertinoIcons.exclamationmark_octagon_fill
                              : (alert.severity == 'warning'
                                    ? CupertinoIcons
                                          .exclamationmark_triangle_fill
                                    : CupertinoIcons.info_circle_fill);

                          return Dismissible(
                            key: Key(alert.id),
                            direction: DismissDirection.endToStart,
                            onDismissed: (_) => state.removeAlert(alert.id),
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 24),
                              decoration: BoxDecoration(
                                color: AppTheme.neonGreen,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                            child: Card(
                              color: theme.cardColor,
                              margin: const EdgeInsets.only(bottom: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: theme.dividerColor),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(icon, color: color, size: 24),
                                    ),
                                    const SizedBox(width: 20),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  alert.title,
                                                  style: TextStyle(
                                                    color: color,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                formatAlertTimestamp(
                                                  alert.timestamp,
                                                ),
                                                style: const TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            alert.description,
                                            style: TextStyle(
                                              color: theme
                                                  .textTheme
                                                  .bodyLarge
                                                  ?.color,
                                              fontSize: 13,
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
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
// TAB 5: MORE (SETTINGS & ABOUT CAPSTONE)
// ==========================================
