String formatDuration(double seconds) {
  if (seconds.isNaN || seconds < 0) seconds = 0;
  final s = seconds.round();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  final ss = sec.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// "1 sa 12 dk" / "42 dk"
String formatTotal(double seconds) {
  final m = (seconds / 60).round();
  if (m >= 60) return '${m ~/ 60} sa ${m % 60} dk';
  if (m == 0 && seconds > 0) return '${seconds.round()} sn';
  return '$m dk';
}

String formatSize(int bytes) {
  if (bytes <= 0) return '0 MB';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 10 || i == 0 ? 0 : 1)} ${units[i]}';
}

String songCount(int n) => '$n şarkı';

/// Greeting by time of day.
String greeting([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  if (h >= 5 && h < 12) return 'Günaydın';
  if (h >= 12 && h < 18) return 'İyi günler';
  if (h >= 18 && h < 23) return 'İyi akşamlar';
  return 'İyi geceler';
}

/// Turkish-aware case folding for local search (offline).
String foldTr(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    var c = String.fromCharCode(r);
    switch (c) {
      case 'İ':
      case 'I':
      case 'ı':
        c = 'i';
      case 'Ş':
      case 'ş':
        c = 's';
      case 'Ğ':
      case 'ğ':
        c = 'g';
      case 'Ü':
      case 'ü':
        c = 'u';
      case 'Ö':
      case 'ö':
        c = 'o';
      case 'Ç':
      case 'ç':
        c = 'c';
      default:
        c = c.toLowerCase();
    }
    b.write(c);
  }
  return b.toString();
}
