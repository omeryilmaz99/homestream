String formatDuration(double seconds, {bool long = false}) {
  if (seconds.isNaN || seconds < 0) seconds = 0;
  final s = seconds.round();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  if (long) {
    if (s < 60) return '$s sn';
    if (h > 0) return '$h sa ${m.toString().padLeft(2, '0')} dk';
    return '$m dk';
  }
  final mm = m.toString().padLeft(2, '0');
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
}

String formatRemaining(double position, double duration) {
  final left = (duration - position).clamp(0, double.infinity).toDouble();
  final m = (left / 60).ceil();
  if (m >= 60) return '${m ~/ 60} sa ${m % 60} dk kaldı';
  return '$m dk kaldı';
}

String formatSize(int bytes) {
  if (bytes <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 10 || i == 0 ? 0 : 1)} ${units[i]}';
}

const _langNames = {
  'tur': 'Türkçe',
  'tr': 'Türkçe',
  'turkish': 'Türkçe',
  'eng': 'İngilizce',
  'en': 'İngilizce',
  'english': 'İngilizce',
  'ger': 'Almanca',
  'deu': 'Almanca',
  'de': 'Almanca',
  'fre': 'Fransızca',
  'fra': 'Fransızca',
  'fr': 'Fransızca',
  'spa': 'İspanyolca',
  'es': 'İspanyolca',
  'ita': 'İtalyanca',
  'it': 'İtalyanca',
  'rus': 'Rusça',
  'ru': 'Rusça',
  'jpn': 'Japonca',
  'ja': 'Japonca',
  'kor': 'Korece',
  'ko': 'Korece',
  'ara': 'Arapça',
  'ar': 'Arapça',
  'chi': 'Çince',
  'zho': 'Çince',
  'zh': 'Çince',
  'por': 'Portekizce',
  'pt': 'Portekizce',
  'dut': 'Felemenkçe',
  'nld': 'Felemenkçe',
  'nl': 'Felemenkçe',
  'pol': 'Lehçe',
  'pl': 'Lehçe',
  'gre': 'Yunanca',
  'ell': 'Yunanca',
  'el': 'Yunanca',
  'hin': 'Hintçe',
  'hi': 'Hintçe',
  'und': 'Bilinmiyor',
};

String languageName(String code) {
  if (code.isEmpty) return '';
  return _langNames[code.toLowerCase()] ?? code.toUpperCase();
}

bool languageMatches(String? code, String pref) {
  if (code == null || code.isEmpty) return false;
  final c = code.toLowerCase();
  switch (pref) {
    case 'tur':
      return c == 'tur' || c == 'tr' || c == 'turkish' || c.startsWith('tr-');
    case 'eng':
      return c == 'eng' || c == 'en' || c == 'english' || c.startsWith('en-');
  }
  return c == pref;
}
