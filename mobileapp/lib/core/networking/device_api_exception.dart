enum DeviceApiErrorKind {
  connection,
  authentication,
  safetyConflict,
  invalidResponse,
  unsuccessfulResponse,
}

class DeviceApiException implements Exception {
  const DeviceApiException(this.kind, {this.statusCode, this.message});

  final DeviceApiErrorKind kind;
  final int? statusCode;
  final String? message;

  @override
  String toString() => message ?? 'Device API failure: $kind';
}
