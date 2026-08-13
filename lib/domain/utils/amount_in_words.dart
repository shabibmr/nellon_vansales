/// Converts a numeric amount to English words for thermal / PDF totals.
///
/// Whole amounts omit the fraction: `AED Fifteen only`.
/// With fils: `AED One Thousand Two Hundred Thirty-Four And fifty six fils.`
String amountInWords(num amount, {String currencyName = ''}) {
  final absolute = amount.abs();
  final whole = absolute.floor();
  final cents = ((absolute - whole) * 100).round().clamp(0, 99);

  final wholeWords = _integerToWords(whole);
  final String body;
  if (cents == 0) {
    body = '$wholeWords only';
  } else {
    final filsWords =
        _integerToWords(cents).toLowerCase().replaceAll('-', ' ');
    body = '$wholeWords And $filsWords ${_subunitName(currencyName)}.';
  }

  final prefix = currencyName.trim();
  if (prefix.isEmpty) return body;
  return '$prefix $body';
}

/// Fractional unit for [currencyName] (Dirhams → fils).
String _subunitName(String currencyName) {
  final key = currencyName.trim().toLowerCase();
  return switch (key) {
    'dirhams' || 'dirham' || 'aed' || 'dhs' || 'dh' => 'fils',
    'rupees' || 'rupee' || 'inr' => 'paise',
    'pounds' || 'pound' || 'gbp' => 'pence',
    'dollars' || 'dollar' || 'usd' || 'euros' || 'euro' => 'cents',
    _ => 'fils',
  };
}

/// Maps common currency codes/symbols to a printable unit name.
String currencyUnitName(String codeOrSymbol) {
  final key = codeOrSymbol.trim().toUpperCase();
  return switch (key) {
    'AED' || 'DHS' || 'DH' || 'DIRHAMS' || 'DIRHAM' => 'AED',
    'INR' || 'RS' || '₹' => 'Rupees',
    'USD' || r'$' || r'US$' => 'Dollars',
    'EUR' || '€' => 'Euros',
    'GBP' || '£' => 'Pounds',
    _ => codeOrSymbol.trim().isEmpty ? '' : codeOrSymbol.trim(),
  };
}

String _integerToWords(int value) {
  if (value == 0) return 'Zero';
  if (value < 0) return _integerToWords(-value);

  final parts = <String>[];
  var n = value;

  void take(int divisor, String label) {
    if (n < divisor) return;
    final count = n ~/ divisor;
    n %= divisor;
    parts.add('${_underThousand(count)} $label');
  }

  take(1000000000, 'Billion');
  take(1000000, 'Million');
  take(1000, 'Thousand');
  if (n > 0) {
    parts.add(_underThousand(n));
  }
  return parts.join(' ');
}

String _underThousand(int value) {
  assert(value >= 0 && value < 1000);
  if (value == 0) return '';
  if (value < 20) return _ones[value];
  if (value < 100) {
    final tens = value ~/ 10;
    final ones = value % 10;
    if (ones == 0) return _tens[tens];
    return '${_tens[tens]}-${_ones[ones]}';
  }
  final hundreds = value ~/ 100;
  final rest = value % 100;
  if (rest == 0) return '${_ones[hundreds]} Hundred';
  return '${_ones[hundreds]} Hundred ${_underThousand(rest)}';
}

const _ones = <String>[
  'Zero',
  'One',
  'Two',
  'Three',
  'Four',
  'Five',
  'Six',
  'Seven',
  'Eight',
  'Nine',
  'Ten',
  'Eleven',
  'Twelve',
  'Thirteen',
  'Fourteen',
  'Fifteen',
  'Sixteen',
  'Seventeen',
  'Eighteen',
  'Nineteen',
];

const _tens = <String>[
  '',
  '',
  'Twenty',
  'Thirty',
  'Forty',
  'Fifty',
  'Sixty',
  'Seventy',
  'Eighty',
  'Ninety',
];
