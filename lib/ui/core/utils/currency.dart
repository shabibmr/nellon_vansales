String formatCurrency(double value, String symbol) =>
    '$symbol${value.toStringAsFixed(2)}';
