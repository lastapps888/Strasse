/// Unités d'affichage.
enum Units { metric, imperial }

const double _mPerMile = 1609.344;
const double _ftPerM = 3.28084;

String _num(double v, {int decimals = 1}) {
  var s = v.toStringAsFixed(decimals).replaceAll('.', ',');
  if (decimals > 0 && s.contains(',')) {
    s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r',$'), '');
  }
  return s;
}

/// Distance lisible : « 350 m », « 1,2 km », « 0,3 mi », « 400 ft ».
String formatDistance(double meters, [Units units = Units.metric]) {
  if (meters.isNaN || meters < 0) meters = 0;
  if (units == Units.imperial) {
    final miles = meters / _mPerMile;
    if (miles < 0.1) {
      final ft = meters * _ftPerM;
      return '${(ft / 10).round() * 10} ft';
    }
    return '${_num(miles, decimals: miles < 10 ? 1 : 0)} mi';
  }
  if (meters < 1000) {
    final step = meters < 100 ? 5 : 10;
    return '${(meters / step).round() * step} m';
  }
  final km = meters / 1000;
  return '${_num(km, decimals: km < 10 ? 1 : 0)} km';
}

/// Distance dite à voix haute : « 400 mètres », « 1,5 kilomètre ».
String speakDistance(double meters, [Units units = Units.metric]) {
  if (units == Units.imperial) {
    final miles = meters / _mPerMile;
    if (miles < 0.2) {
      final ft = (meters * _ftPerM / 100).round() * 100;
      return '${ft < 100 ? 100 : ft} pieds';
    }
    final v = _num(miles);
    return '$v ${miles <= 1 ? 'mile' : 'miles'}';
  }
  if (meters < 1000) {
    final r = (meters / 50).round() * 50;
    return '${r < 50 ? 50 : r} mètres';
  }
  final km = meters / 1000;
  final v = _num(km);
  return '$v ${km < 2 ? 'kilomètre' : 'kilomètres'}';
}

/// Durée lisible : « 45 s », « 12 min », « 1 h 05 ».
String formatDuration(double seconds) {
  if (seconds.isNaN || seconds < 0) seconds = 0;
  final totalMin = (seconds / 60).round();
  if (seconds < 60) return seconds < 10 ? '< 1 min' : '${seconds.round()} s';
  if (totalMin < 60) return '$totalMin min';
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  if (h >= 24) {
    final d = h ~/ 24;
    final hh = h % 24;
    return '$d j ${hh} h';
  }
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

/// Heure « 14:32 ».
String formatClock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Date « 4 nov. 2026 ».
String formatDate(DateTime t) {
  const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
  return '${t.day} ${months[t.month - 1]} ${t.year}';
}

/// Date et heure « 4 nov. 2026, 14:32 ».
String formatDateTime(DateTime t) => '${formatDate(t)}, ${formatClock(t)}';

/// Heure d'arrivée estimée.
String formatEta(DateTime now, double remainingSeconds) =>
    formatClock(now.add(Duration(seconds: remainingSeconds.round())));

/// Vitesse en km/h ou mph (entrée en m/s).
String formatSpeed(double mps, [Units units = Units.metric]) {
  if (mps.isNaN || mps < 0) mps = 0;
  return units == Units.imperial ? '${(mps * 2.23694).round()} mph' : '${(mps * 3.6).round()} km/h';
}

/// Taille de fichier : « 12,4 Mo ».
String formatBytes(num bytes) {
  const units = ['o', 'Ko', 'Mo', 'Go', 'To'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${_num(v, decimals: i == 0 ? 0 : 1)} ${units[i]}';
}

/// « il y a 5 min », « il y a 2 h », « il y a 3 j ».
String formatRelative(DateTime now, DateTime t) {
  final d = now.difference(t);
  if (d.inSeconds < 45) return 'à l\'instant';
  if (d.inMinutes < 60) return 'il y a ${d.inMinutes < 1 ? 1 : d.inMinutes} min';
  if (d.inHours < 24) return 'il y a ${d.inHours} h';
  return 'il y a ${d.inDays} j';
}

/// Durée restante « dans 12 min ».
String formatRemaining(DateTime now, DateTime until) {
  final d = until.difference(now);
  if (d.isNegative) return 'expiré';
  if (d.inMinutes < 1) return 'dans moins d\'une minute';
  if (d.inMinutes < 60) return 'dans ${d.inMinutes} min';
  return 'dans ${d.inHours} h';
}

/// Retire les accents et met en minuscules, pour des comparaisons de recherche tolérantes.
String foldText(String s) {
  const from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿœæ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final sb = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final ch = String.fromCharCode(r);
    final i = from.indexOf(ch);
    sb.write(i >= 0 ? to[i] : ch);
  }
  return sb.toString();
}
