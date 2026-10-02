class AuditLog {
  const AuditLog(this.action, this.user, this.timestamp);

  final String action;
  final String user;
  final String timestamp;
}
