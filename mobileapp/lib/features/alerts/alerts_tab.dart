import 'dart:async';

import 'package:biomass_iot_app/core/widgets/icon_label.dart';
import 'package:biomass_iot_app/app/app_icons.dart';
import 'package:biomass_iot_app/app/app_state_provider.dart';
import 'package:biomass_iot_app/app/app_theme.dart';
import 'package:biomass_iot_app/core/widgets/glowing_card.dart';
import 'package:biomass_iot_app/core/widgets/delayed_loading.dart';
import 'package:biomass_iot_app/core/widgets/loading_skeleton.dart';
import 'package:biomass_iot_app/features/alerts/alert_presentation.dart';
import 'package:biomass_iot_app/features/alerts/alerts_controller.dart';
import 'package:biomass_iot_app/features/alerts/alert_timestamp.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class _SeverityFilterLabel extends StatelessWidget {
  const _SeverityFilterLabel(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}

double alertListBottomInset({
  required double width,
  required double safeAreaBottom,
}) => width > 850 ? 32 : safeAreaBottom + 136;

class AlertsTab extends StatefulWidget {
  const AlertsTab({super.key, this.controller});

  final AlertsController? controller;

  @override
  State<AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends State<AlertsTab> {
  String _filter = 'All';
  late AlertsController _controller;
  late bool _ownsController;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _ownsController = false;
    _controller =
        widget.controller ?? context.read<AppStateProvider>().alertsController;
    _controller.addListener(_onAlertsChanged);
    _scrollController.addListener(_loadMoreWhenNeeded);
    unawaited(_controller.load());
  }

  void _onAlertsChanged() {
    if (mounted) setState(() {});
  }

  void _loadMoreWhenNeeded() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > 240) {
      return;
    }
    unawaited(_controller.loadMore());
  }

  @override
  void dispose() {
    _controller.removeListener(_onAlertsChanged);
    if (_ownsController) _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final isCompact = mediaQuery.size.width < 600;
    final alerts = _controller.alerts;
    final sessionSummary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const IconLabel(
          icon: AppIcons.alerts,
          label: 'Session Summary',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "${_controller.totalAlerts} alerts today",
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontWeight: FontWeight.w900,
            fontSize: 24,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
    final clearAllButton = ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.neonRed.withValues(alpha: 0.1),
        foregroundColor: AppTheme.neonRed,
        elevation: 0,
      ),
      onPressed: () => unawaited(_controller.clearAllAlerts()),
      icon: const Icon(AppIcons.delete, size: 20),
      label: const Text(
        'Clear All',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
    );

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
                  child: isCompact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            sessionSummary,
                            const SizedBox(height: 12),
                            clearAllButton,
                          ],
                        )
                      : Row(
                          children: [
                            sessionSummary,
                            const Spacer(),
                            clearAllButton,
                          ],
                        ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 24),
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoSegmentedControl<String>(
                        selectedColor: AppTheme.neonOrange,
                        borderColor: AppTheme.neonOrange,
                        unselectedColor: theme.cardColor,
                        groupValue: _filter,
                        children: const {
                          'All': Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: _SeverityFilterLabel(AppIcons.alerts, 'All'),
                          ),
                          'Info': Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: _SeverityFilterLabel(
                              AppIcons.information,
                              'Info',
                            ),
                          ),
                          'Warning': Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: _SeverityFilterLabel(
                              AppIcons.warning,
                              'Warning',
                            ),
                          ),
                          'Critical': Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: _SeverityFilterLabel(
                              AppIcons.critical,
                              'Critical',
                            ),
                          ),
                        },
                        onValueChanged: (val) {
                          if (_controller.isLoading) return;
                          setState(() => _filter = val);
                          unawaited(
                            _controller.setSeverity(
                              val == 'All' ? null : val.toLowerCase(),
                            ),
                          );
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(AppIcons.refresh),
                      tooltip: 'Refresh alerts',
                      onPressed: _controller.isLoading
                          ? null
                          : () => unawaited(_controller.load()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: DelayedLoading(
                  isLoading: _controller.isLoading,
                  hasContent: alerts.isNotEmpty,
                  placeholder: const _AlertsSkeleton(),
                  child: alerts.isEmpty && _controller.errorMessage != null
                      ? Center(
                          child: TextButton(
                            onPressed: _controller.load,
                            child: Text(_controller.errorMessage!),
                          ),
                        )
                      : alerts.isEmpty
                      ? const Center(
                          child: Text(
                            "No alerts found.",
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: EdgeInsets.only(
                            left: isCompact ? 16 : 24,
                            right: isCompact ? 16 : 24,
                            bottom: alertListBottomInset(
                              width: mediaQuery.size.width,
                              safeAreaBottom: mediaQuery.padding.bottom,
                            ),
                          ),
                          itemCount:
                              alerts.length +
                              (_controller.hasMoreAlerts ||
                                      _controller.errorMessage != null
                                  ? 1
                                  : 0),
                          itemBuilder: (ctx, i) {
                            if (i == alerts.length) {
                              if (_controller.errorMessage != null) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: TextButton(
                                    onPressed: _controller.loadMore,
                                    child: Text(_controller.errorMessage!),
                                  ),
                                );
                              }
                              return const Padding(
                                padding: EdgeInsets.only(bottom: 16),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            final alert = alerts[i];
                            final presentation = alertPresentationForSeverity(
                              alert.severity,
                            );

                            return Dismissible(
                              key: Key(alert.id),
                              direction: DismissDirection.endToStart,
                              onDismissed: (_) {
                                unawaited(_controller.removeAlert(alert.id));
                              },
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 24),
                                decoration: BoxDecoration(
                                  color: AppTheme.neonGreen,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  AppIcons.success,
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: presentation.color.withValues(
                                            alpha: 0.15,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          presentation.icon,
                                          color: presentation.color,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 20),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    alert.title,
                                                    style: TextStyle(
                                                      color: presentation.color,
                                                      fontWeight:
                                                          FontWeight.bold,
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertsSkeleton extends StatelessWidget {
  const _AlertsSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    children: const [
      LoadingSkeletonCard(),
      LoadingSkeletonCard(),
      LoadingSkeletonCard(),
      LoadingSkeletonCard(margin: EdgeInsets.zero),
    ],
  );
}
