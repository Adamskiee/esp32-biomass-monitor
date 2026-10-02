class Alert {
  const Alert({
    required this.id,
    required this.title,
    required this.description,
    required this.severity,
    required this.timestamp,
  });

  final String id;
  final String title;
  final String description;
  final String severity;
  final DateTime? timestamp;
}
