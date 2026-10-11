import 'package:flutter/foundation.dart';

import '../monitoring/telemetry_source.dart';
import 'attempt.dart';
import 'attempt_comparison.dart';
import 'attempt_comparison_service.dart';
import 'attempt_store.dart';

class AttemptController extends ChangeNotifier {
  AttemptController(this._source, this._store, this._comparison) {
    _source.addListener(_onTelemetry);
  }
  final TelemetrySource _source;
  final AttemptStore _store;
  final AttemptComparisonService _comparison;
  List<Attempt> _attempts = [];
  Attempt? _activeAttempt;
  Future<void> _pending = Future.value();
  int _lastRevision = 0;
  bool _isBusy = false;
  String? _errorMessage;
  bool _disposed = false;
  List<Attempt> get attempts => List.unmodifiable(_attempts);
  Attempt? get activeAttempt => _activeAttempt;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  Future<void> initialize() async {
    await _store.recoverActiveAttempt();
    await _reload();
  }

  Future<void> start(AttemptScenario scenario) async {
    if (!_source.isHardwareConnected) {
      _errorMessage = 'Connect to the ESP32 before recording.';
      notifyListeners();
      return;
    }
    await _enqueue(() async {
      _activeAttempt = await _store.startAttempt(scenario, DateTime.now());
      _lastRevision = _source.telemetryRevision;
      await _reload();
    });
  }

  Future<void> stop() => _finish(AttemptStatus.completed);
  Future<void> deleteAttempt(int id) => _enqueue(() async {
    await _store.deleteAttempt(id);
    await _reload();
  });
  Future<AttemptComparison> compare(int unfilteredId, int filteredId) async =>
      _comparison.compare(
        await _store.listReadings(unfilteredId),
        await _store.listReadings(filteredId),
      );
  void _onTelemetry() {
    if (_activeAttempt == null) return;
    if (!_source.isHardwareConnected) {
      _finish(AttemptStatus.interrupted);
      return;
    }
    if (_source.telemetryRevision <= _lastRevision) return;
    _lastRevision = _source.telemetryRevision;
    final attempt = _activeAttempt!;
    _enqueue(() async {
      await _store.addReading(
        attempt.id,
        _source.currentData,
        DateTime.now().difference(attempt.startedAt),
      );
      await _reload();
    });
  }

  Future<void> _finish(AttemptStatus status) => _enqueue(() async {
    final attempt = _activeAttempt;
    if (attempt == null) return;
    await _store.finishAttempt(attempt.id, DateTime.now(), status);
    _activeAttempt = null;
    await _reload();
  });
  Future<void> _reload() async {
    _attempts = await _store.listAttempts();
    _activeAttempt = _attempts
        .where((item) => item.status == AttemptStatus.active)
        .firstOrNull;
    notifyListeners();
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    _isBusy = true;
    notifyListeners();
    _pending = _pending
        .then((_) => operation())
        .catchError((Object error) {
          _errorMessage = 'Recording could not continue: $error';
          _activeAttempt = null;
        })
        .whenComplete(() {
          _isBusy = false;
          if (!_disposed) notifyListeners();
        });
    return _pending;
  }

  @override
  void dispose() {
    _disposed = true;
    _source.removeListener(_onTelemetry);
    super.dispose();
  }
}
