/// Loads the Zoho OAuth configuration that every other Zoho call depends on.
///
/// Exists so the login path can guarantee credentials are present *before*
/// binding a session. Remote config normally arrives via `LicenseGate`, which
/// only mounts for an already-authenticated user — on a fresh install (no
/// secure-storage cache) that ordering makes login impossible, since the bind
/// itself needs Zoho.
abstract class ServerConfigRepository {
  /// Whether usable Zoho credentials are currently loaded.
  bool get hasCredentials;

  /// Ensures credentials are loaded. Always tries `server_config/zoho` first
  /// so a rotated OAuth client is applied before session bind; falls back to
  /// in-memory / secure-cache credentials when remote is incomplete or
  /// unreachable.
  ///
  /// Returns whether credentials are usable afterwards. Never throws — a
  /// caller only needs to know if it can proceed.
  Future<bool> ensureCredentialsLoaded();
}
