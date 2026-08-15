/// Weight is stored in kilograms everywhere. This is the only place that knows
/// about pounds, so a user switching units never rewrites a single stored row.
enum WeightUnit {
  kg,
  lb;

  String get suffix => name;
}

const double _lbPerKg = 2.2046226218;

double kgToDisplay(double kg, WeightUnit unit) =>
    unit == WeightUnit.kg ? kg : kg * _lbPerKg;

double displayToKg(double value, WeightUnit unit) =>
    unit == WeightUnit.kg ? value : value / _lbPerKg;

/// Formats a stored weight for display, trimming the pointless ".0" on whole
/// numbers so the logging screen reads "80 kg" rather than "80.0 kg".
String formatWeight(double? kg, WeightUnit unit, {bool withSuffix = true}) {
  if (kg == null) return '—';

  final value = kgToDisplay(kg, unit);
  final rounded = (value * 100).round() / 100;
  final text = rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);

  return withSuffix ? '$text ${unit.suffix}' : text;
}

/// "80 kg x 8" — the shape used for last-session hints and history rows.
String formatSet(double? kg, int? reps, WeightUnit unit) {
  if (kg == null && reps == null) return '—';
  if (kg == null) return '$reps reps';
  if (reps == null) return formatWeight(kg, unit);
  return '${formatWeight(kg, unit)} × $reps';
}

String formatDuration(Duration d) {
  final minutes = d.inMinutes;
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  return '${hours}h ${minutes % 60}m';
}

String formatRest(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return rest == 0 ? '${minutes}m' : '${minutes}m ${rest}s';
}
