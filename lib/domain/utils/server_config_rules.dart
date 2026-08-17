/// Thrown when a Zoho call is attempted before the OAuth credential triple
/// (client id, client secret, refresh token) has been loaded.
///
/// This is a configuration fault, not a transport one: retrying the same call
/// can never succeed until `server_config/zoho` is fetched (or the secure
/// cache is restored), so callers must not present it as a network error.
class ZohoNotConfiguredException implements Exception {
  const ZohoNotConfiguredException();

  /// Kept stable — [zohoNotConfiguredNeedle] matches against this text after
  /// intermediate layers have re-wrapped the cause into a plain `Exception`.
  @override
  String toString() => 'Zoho credentials not configured';
}

/// Lowercased marker used to recognise a [ZohoNotConfiguredException] that has
/// lost its type by being re-wrapped in a string-formatted `Exception`.
const zohoNotConfiguredNeedle = 'zoho credentials not configured';
