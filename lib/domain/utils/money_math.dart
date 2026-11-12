/// Active decimal places for [roundMoney].
///
/// Defaults to 2 until an organization has been loaded.
class MoneyScale {
  MoneyScale._();

  static int _decimals = 2;
  static double _totalStep = 0;

  static int get decimals => _decimals;

  /// Step document totals round to (e.g. 0.5); 0 means no cash rounding.
  static double get totalStep => _totalStep;

  /// Stores the org's total rounding step; negative values become 0.
  static void useTotalStep(double step) {
    _totalStep = step > 0 ? step : 0;
  }

  /// Clamps [decimals] to 0–6 and stores it for later [roundMoney] calls.
  static void use(int decimals) {
    if (decimals < 0) {
      _decimals = 0;
    } else if (decimals > 6) {
      _decimals = 6;
    } else {
      _decimals = decimals;
    }
  }
}

double _decimalFactor(int decimals) {
  var factor = 1.0;
  for (var i = 0; i < decimals; i++) {
    factor *= 10.0;
  }
  return factor;
}

/// Rounds a monetary value half away from zero to [MoneyScale.decimals] places.
///
/// Guards against binary floating-point drift (e.g. `0.1 + 0.2 != 0.3`)
/// compounding across chained sums of many line items — every money-bearing
/// getter rounds its own result before it's summed by a caller, so errors
/// can't silently accumulate across a document's totals.
double roundMoney(double value) {
  final factor = _decimalFactor(MoneyScale.decimals);
  return (value * factor).roundToDouble() / factor;
}

/// Rounds a document total to [MoneyScale.totalStep], mirroring the
/// transaction rounding Zoho applies server-side. With step 0 this is
/// [roundMoney].
double roundTotal(double value) {
  final step = MoneyScale.totalStep;
  final money = roundMoney(value);
  if (step <= 0) return money;
  return roundMoney((money / step).roundToDouble() * step);
}

/// Steps [detectTotalRoundingStep] tries, largest first.
const totalRoundingStepCandidates = [1.0, 0.5, 0.25, 0.1, 0.05];

/// Infers the org's total rounding step from recent Zoho invoice totals.
///
/// Returns the largest candidate step that every non-zero total is a
/// multiple of, or 0 when none fits. Returns null when fewer than
/// [minSamples] non-zero totals are available (not enough evidence).
double? detectTotalRoundingStep(
  Iterable<double> totals, {
  int minSamples = 10,
}) {
  final samples = totals.where((t) => t.abs() > 1e-9).toList();
  if (samples.length < minSamples) return null;
  for (final step in totalRoundingStepCandidates) {
    final fits = samples.every((t) {
      final q = t / step;
      return (q - q.roundToDouble()).abs() < 1e-6;
    });
    if (fits) return step;
  }
  return 0;
}
