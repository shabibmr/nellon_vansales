/// Normalizes a phone number to E.164 for comparison and storage.
///
/// Strips spaces/dashes/parens; a leading '00' international-dialing prefix
/// becomes '+'; a string already starting with '+' is returned as-is. The
/// caller is expected to enter the full number including country code.
/// Apply to both sides of any comparison.
String normalizePhone(String raw) {
  final stripped = raw.replaceAll(RegExp(r'[\s\-()]'), '');
  if (stripped.isEmpty) return stripped;

  if (stripped.startsWith('+')) return stripped;
  if (stripped.startsWith('00')) return '+${stripped.substring(2)}';
  return stripped;
}

/// Checks whether [phone] is a valid E.164 number: '+' followed by a 1-3
/// digit country code and subscriber number, 8-15 digits total.
bool isValidE164(String phone) => RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone);
