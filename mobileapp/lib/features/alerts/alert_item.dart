class AlertItem {
  final String id, title, description, severity;
  final DateTime? timestamp;

  AlertItem({
    required this.id,
    required this.title,
    required this.description,
    required this.severity,
    required this.timestamp,
  });
}
