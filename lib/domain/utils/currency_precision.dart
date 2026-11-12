/// ISO-4217 minor-unit counts used when Zoho omits [price_precision].
int minorUnitsFor(String code) {
  switch (code.trim().toUpperCase()) {
    case 'KWD':
    case 'BHD':
    case 'OMR':
    case 'JOD':
    case 'IQD':
    case 'LYD':
    case 'TND':
      return 3;
    case 'JPY':
    case 'KRW':
      return 0;
    default:
      return 2;
  }
}
