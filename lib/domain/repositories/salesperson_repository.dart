import '../models/salesperson.dart';
import '../models/session_bind_result.dart';

/// Abstract contract resolving the active logged-in salesperson and their mapped
/// Zoho van location/cash account, and exposing the cached master list of all
/// salespersons.
abstract class SalespersonRepository {
  /// Post-Firebase Zoho identity gate: profile → salespersons → locations.
  ///
  /// 1. `GET /cm_salesperson_profile` and match `record_name` against
  ///    [phone] (both sides normalized to E.164).
  /// 2. Require `cf_active`; require `cf_salesperson` + `cf_cash_account`.
  /// 3. `GET /salespersons` and confirm the looked-up salesperson is active.
  /// 4. `GET /locations` and cache; resolve the primary (KGT) location.
  /// 5. `cf_van_location` empty ⇒ orders-only mode: fall back to the primary
  ///    location and permit Sales Orders, Receipts, Expenses, and Cash Closing
  ///    (block invoices, returns, and stock moves).
  /// 6. Persist session fields (phone, van/primary location, cash account,
  ///    voucher prefix, orders-only flag).
  Future<SessionBindResult> verifyAndBindSession(String phone);

  /// Convenience wrapper: returns the bound salesperson or `null` on failure.
  ///
  /// Prefer [verifyAndBindSession] when failure reasons matter for UI copy.
  Future<Salesperson?> resolveActiveSalesperson(String phone);

  /// Returns the locally cached master list of all Zoho salespersons.
  List<Salesperson> getCachedSalespersons();

  /// Returns the resolved active salesperson for the current session, if any.
  Salesperson? get currentSalesperson;

  /// Clears the session's active salesperson (e.g. on logout).
  Future<void> clearCurrentSalesperson();
}
