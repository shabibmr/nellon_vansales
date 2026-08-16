/// Outcome of an online-first save attempt.
enum SubmitResult {
  /// Zoho accepted the document; it is stored locally with a Zoho id.
  synced,

  /// Zoho/network failed or the device is offline; item is on the sync queue.
  queued,
}

/// User-facing save toast: synced copy vs queue fallback.
extension SubmitResultMessage on SubmitResult {
  String message(String saved) =>
      this == SubmitResult.synced ? saved : 'Saved to upload queue';
}

/// Offline customer ids minted by create-customer before Zoho assigns one.
bool isTempCustomerId(String id) => id.startsWith('temp_');
