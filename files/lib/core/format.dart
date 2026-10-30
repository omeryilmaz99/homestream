/// Turkish formatting helpers for sizes, speeds, dates and durations.
String formatBytes(num bytes, {int digits = 1}) {
  if (bytes < 0) bytes = 0;
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final s = i == 0
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(v >= 100 ? 0 : digits);
  return '${s.replaceAll('.', ',')} ${units[i]}';
}

String formatSpeed(double bytesPerSec) => '${formatBytes(bytesPerSec)}/sn';

String formatDuration(Duration d) {
  if (d.inSeconds < 1) return '0 sn';
  if (d.inSeconds < 60) return '${d.inSeconds} sn';
  if (d.inMinutes < 60) {
    final s = d.inSeconds % 60;
    return s == 0 ? '${d.inMinutes} dk' : '${d.inMinutes} dk $s sn';
  }
  if (d.inHours < 24) {
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours} sa' : '${d.inHours} sa $m dk';
  }
  final h = d.inHours % 24;
  return h == 0 ? '${d.inDays} gün' : '${d.inDays} gün $h sa';
}

const _months = [
  'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', //
  'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// "Bugün 14:05", "Dün 09:12", "12 Mar 14:05", "12 Mar 2023".
String formatDate(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final hm = '${_two(t.hour)}:${_two(t.minute)}';
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Bugün $hm';
  if (diff == 1) return 'Dün $hm';
  if (t.year == now.year) return '${t.day} ${_months[t.month - 1]} $hm';
  return '${t.day} ${_months[t.month - 1]} ${t.year}';
}

String formatAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 45) return 'az önce';
  if (d.inMinutes < 60) return '${d.inMinutes} dk önce';
  if (d.inHours < 24) return '${d.inHours} sa önce';
  if (d.inDays < 7) return '${d.inDays} gün önce';
  return formatDate(t);
}

String plural(int n, String word) => '$n $word';

/// Lower-case, Turkish-aware folding for search/sort.
String foldText(String s) {
  const map = {
    'İ': 'i', 'I': 'i', 'ı': 'i', 'Ş': 's', 'ş': 's', 'Ğ': 'g', 'ğ': 'g', //
    'Ü': 'u', 'ü': 'u', 'Ö': 'o', 'ö': 'o', 'Ç': 'c', 'ç': 'c',
  };
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    b.write(map[c] ?? c.toLowerCase());
  }
  return b.toString();
}

/// Natural order: "Bölüm 2" < "Bölüm 10".
int naturalCompare(String a, String b) {
  final x = foldText(a), y = foldText(b);
  var i = 0, j = 0;
  while (i < x.length && j < y.length) {
    final ci = x.codeUnitAt(i), cj = y.codeUnitAt(j);
    final di = ci >= 48 && ci <= 57, dj = cj >= 48 && cj <= 57;
    if (di && dj) {
      var ei = i, ej = j;
      while (ei < x.length && _digit(x.codeUnitAt(ei))) {
        ei++;
      }
      while (ej < y.length && _digit(y.codeUnitAt(ej))) {
        ej++;
      }
      final ni = BigInt.parse(x.substring(i, ei));
      final nj = BigInt.parse(y.substring(j, ej));
      final c = ni.compareTo(nj);
      if (c != 0) return c;
      i = ei;
      j = ej;
      continue;
    }
    if (ci != cj) return ci.compareTo(cj);
    i++;
    j++;
  }
  return (x.length - i).compareTo(y.length - j);
}

bool _digit(int c) => c >= 48 && c <= 57;
