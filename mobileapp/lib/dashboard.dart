import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Timer? _timer;
  Map<String, dynamic> _state = {};
  List<String> _previousTriggers = [];
  bool _isMuted = false;
  bool? _queuedSprinklerState;
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _pollState();
    _timer = Timer.periodic(const Duration(seconds: 2), (t) => _pollState());
  }

  Future<void> _pollState() async {
    if (_isPosting) return; // Wait if posting
    if (_queuedSprinklerState != null) {
      _isPosting = true;
      try {
        await ApiService.setSprinkler(_queuedSprinklerState!);
        _queuedSprinklerState = null;
      } catch (e) {
        // Ignore transient network errors during debounced post
      } finally {
        _isPosting = false;
      }
      return;
    }
    try {
      final state = await ApiService.fetchState();
      if (!mounted) return;
      final triggers = List<String>.from(state['active_triggers'] ?? []);
      _handleAlerts(triggers);
      setState(() {
        _state = state;
        _previousTriggers = triggers;
      });
    } catch (e) {
      // Ignore transient network errors during background polling
    }
  }

  void _handleAlerts(List<String> currentTriggers) {
    if (!mounted) return;
    if (currentTriggers.isNotEmpty &&
        currentTriggers.toString() != _previousTriggers.toString()) {
      _isMuted = false; // Unmute on new trigger
      if (!_isMuted) SystemSound.play(SystemSoundType.alert);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('DANGER: ${currentTriggers.join(", ")}')),
      );
    } else if (currentTriggers.isEmpty && _previousTriggers.isNotEmpty) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_state.isEmpty) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Biomass Monitor'),
        actions: [
          if (_previousTriggers.isNotEmpty)
            IconButton(
              icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up),
              onPressed: () => setState(() => _isMuted = !_isMuted),
            )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Manual Sprinkler'),
            value: _queuedSprinklerState ?? _state['sprinkler_on'] ?? false,
            onChanged: (val) => setState(() => _queuedSprinklerState = val),
          ),
        ],
      ),
    );
  }
}
