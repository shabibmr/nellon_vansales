/// Normalizes a phone number to E.164 for comparison and storage.
///
/// Strips spaces/dashes/parens; a leading '00' international-dialing prefix
/// becomes '+'; a string already starting with '+' is returned as-is.
/// UAE-specific shorthand is also recognized and expanded to '+971…':
/// a local mobile number starting '05' (e.g. '0542891246'), the country
/// code typed without a '+' (e.g. '971542891246'), or a bare mobile number
/// (e.g. '542891246'). Apply to both sides of any comparison.
String normalizePhone(String raw) {
  final stripped = raw.replaceAll(RegExp(r'[\s\-()]'), '');
  if (stripped.isEmpty) return stripped;

  if (stripped.startsWith('+')) return stripped;
  if (stripped.startsWith('00')) return '+${stripped.substring(2)}';
  if (RegExp(r'^05\d{8}$').hasMatch(stripped)) {
    return '+971${stripped.substring(1)}';
  }
  if (RegExp(r'^971\d{9}$').hasMatch(stripped)) return '+$stripped';
  if (RegExp(r'^5\d{8}$').hasMatch(stripped)) return '+971$stripped';
  return stripped;
}

/// Checks whether [phone] is a valid E.164 number: '+' followed by a 1-3
/// digit country code and subscriber number, 8-15 digits total.
bool isValidE164(String phone) => RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone);
