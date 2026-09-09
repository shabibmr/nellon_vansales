/// Rounds a monetary value to 2 decimal places.
///
/// Guards against binary floating-point drift (e.g. `0.1 + 0.2 != 0.3`)
/// compounding across chained sums of many line items — every money-bearing
/// getter rounds its own result before it's summed by a caller, so errors
/// can't silently accumulate across a document's totals.
double roundMoney(double value) => (value * 100).roundToDouble() / 100;

/// Rounds a monetary value to the nearest 0.50 (e.g. 0 or 0.50 step).
///
/// .10 -> 0.00, .40 -> .50, .90 -> 1.00, .25 -> .50, .75 -> 1.00.
double roundToNearestHalf(double value) =>
    roundMoney((roundMoney(value) * 2).roundToDouble() / 2);

