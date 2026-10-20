import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_history_store.dart';
import 'package:flutter/foundation.dart';

class SensorLogController extends ChangeNotifier {
  SensorLogController(this._historyStore);

  static const pageSize = 10;

  final SensorHistoryReader _historyStore;
  final List<SensorData> _records = [];
  int _snapshotId = 0;
  int _totalRecords = 0;
  int _currentPage = 1;
  bool _liveUpdates = false;
  bool _hasNewRecords = false;
  bool _isLoading = false;
  String? _errorMessage;
  bool _refreshQueued = false;
  bool _isDisposed = false;

  List<SensorData> get records => List.unmodifiable(_records);
  int get currentPage => _currentPage;
  bool get liveUpdates => _liveUpdates;
  bool get hasNewRecords => _hasNewRecords;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get pageCount =>
      _totalRecords == 0 ? 1 : (_totalRecords + pageSize - 1) ~/ pageSize;

  Future<void> loadInitialPage() async {
    if (_isDisposed || _isLoading) return;
    _currentPage = 1;
    await _refreshSnapshot();
  }

  Future<void> refresh() async {
    if (_isDisposed || _isLoading) return;
    await _refreshSnapshot();
  }

  Future<void> setLiveUpdates(bool enabled) async {
    if (_isDisposed || _isLoading || _liveUpdates == enabled) return;
    _liveUpdates = enabled;
    _hasNewRecords = false;
    if (enabled) {
      _currentPage = 1;
      await _refreshSnapshot();
    } else {
      _notifyListeners();
    }
  }

  Future<void> onTelemetryRevision() async {
    if (_isDisposed || !_liveUpdates) return;
    if (_currentPage == 1) {
      if (_isLoading) {
        _refreshQueued = true;
        return;
      }
      await _refreshSnapshot();
      return;
    }
    _hasNewRecords = true;
    _notifyListeners();
  }

  Future<void> showNewRecords() async {
    if (_isDisposed || _isLoading) return;
    _currentPage = 1;
    await _refreshSnapshot();
  }

  Future<void> _refreshSnapshot() async {
    _hasNewRecords = false;
    await _load(() async {
      _snapshotId = await _historyStore.getLatestSensorDataId();
      _totalRecords = await _historyStore.getSensorDataCount(
        throughId: _snapshotId,
      );
      if (_currentPage > pageCount) _currentPage = pageCount;
      await _readCurrentPage();
    });
  }

  Future<void> nextPage() async {
    if (_isDisposed || _isLoading || _currentPage >= pageCount) return;
    await _load(() => _readCurrentPage(page: _currentPage + 1));
  }

  Future<void> previousPage() async {
    if (_isDisposed || _isLoading || _currentPage <= 1) return;
    await _load(() => _readCurrentPage(page: _currentPage - 1));
  }

  Future<void> _readCurrentPage({int? page}) async {
    final requestedPage = page ?? _currentPage;
    final records = await _historyStore.getSensorData(
      limit: pageSize,
      offset: (requestedPage - 1) * pageSize,
      throughId: _snapshotId,
    );
    if (_isDisposed) return;
    _currentPage = requestedPage;
    _records
      ..clear()
      ..addAll(records);
  }

  Future<void> _load(Future<void> Function() operation) async {
    if (_isDisposed || _isLoading) return;
    _isLoading = true;
    _errorMessage = null;
    _notifyListeners();
    try {
      await operation();
    } catch (_) {
      if (!_isDisposed) {
        _errorMessage = 'Unable to load sensor data. Try again.';
      }
    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        _notifyListeners();
        if (_refreshQueued && _liveUpdates && _currentPage == 1) {
          _refreshQueued = false;
          await _refreshSnapshot();
        }
      }
    }
  }

  void _notifyListeners() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
