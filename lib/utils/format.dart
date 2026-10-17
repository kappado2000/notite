import 'package:intl/intl.dart';

String formatDate(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Azi, ${DateFormat.Hm('ro').format(d)}';
  if (diff == 1) return 'Ieri, ${DateFormat.Hm('ro').format(d)}';
  if (d.year == now.year) return DateFormat('d MMM', 'ro').format(d);
  return DateFormat('d MMM y', 'ro').format(d);
}

String formatDateTime(DateTime d) =>
    DateFormat('EEE, d MMM y, HH:mm', 'ro').format(d);

String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

String snippet(String plain, {int max = 160}) {
  final s = plain.replaceAll('￼', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return s.length <= max ? s : '${s.substring(0, max)}…';
}
