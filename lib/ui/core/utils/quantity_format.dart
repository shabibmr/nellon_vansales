/// Formats a quantity for display: whole numbers render without decimals
/// ("3"), fractional quantities keep up to [maxDecimals] trimmed of trailing
/// zeros ("2.5", "0.25").
String formatQuantity(double value, {int maxDecimals = 3}) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  var text = value.toStringAsFixed(maxDecimals);
  text = text.replaceFirst(RegExp(r'0+$'), '');
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return text;
}
