import '../models/salesperson.dart';

/// Abstract contract resolving the active logged-in salesperson and their mapped
/// Zoho Location, and exposing the cached master list of all salespersons.
abstract class SalespersonRepository {
  /// Resolves the active salesperson matching [email] against the synced Zoho
  /// Salespersons list, attaches the mapped `locationId` (from the Zoho
  /// `cm_salesperson_location` custom module), persists both locally, and
  /// updates the session's assigned location. Returns `null` if no matching
  /// salesperson record is found.
  Future<Salesperson?> resolveActiveSalesperson(String email);

  /// Returns the locally cached master list of all Zoho salespersons.
  List<Salesperson> getCachedSalespersons();

  /// Returns the resolved active salesperson for the current session, if any.
  Salesperson? get currentSalesperson;
}
