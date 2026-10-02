String formatAlertTimestamp(DateTime? timestamp, {DateTime? now}) {
  if (timestamp == null) return 'Timestamp unavailable';

  final elapsed = (now ?? DateTime.now()).difference(timestamp);
  if (elapsed.inMinutes < 1) return 'Just now';
  if (elapsed.inHours < 1) {
    final minutes = elapsed.inMinutes;
    return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} ago';
  }
  if (elapsed.inHours < 24) {
    final hours = elapsed.inHours;
    return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
  }
  if (elapsed.inDays < 7) {
    final days = elapsed.inDays;
    return '$days ${days == 1 ? 'day' : 'days'} ago';
  }

  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[timestamp.month - 1]} ${timestamp.day}, ${timestamp.year}';
}
