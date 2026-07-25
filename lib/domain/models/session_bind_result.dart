import 'salesperson.dart';

/// Why [SalespersonRepository.verifyAndBindSession] could not authorize a login.
enum SessionBindFailure {
  /// No `cm_salesperson_profile` record matches the verified phone number.
  notRegistered,

  /// A profile record exists but `cf_active` is not true.
  disabled,

  /// Profile record is missing `cf_salesperson` / `cf_cash_account`, or the
  /// looked-up salesperson could not be confirmed active in `/salespersons`.
  notFullyMapped,

  /// Network / Zoho API failure while loading identity masters or the profile.
  network,
}

/// Outcome of post-Firebase Zoho identity verification and session binding.
class SessionBindResult {
  /// Bound salesperson when [isSuccess] is true.
  final Salesperson? salesperson;

  /// Failure reason when [isSuccess] is false.
  final SessionBindFailure? failure;

  const SessionBindResult._({this.salesperson, this.failure});

  /// Successful bind with a fully resolved [salesperson].
  factory SessionBindResult.success(Salesperson salesperson) =>
      SessionBindResult._(salesperson: salesperson);

  /// Failed bind with a [failure] reason for UI messaging.
  factory SessionBindResult.failed(SessionBindFailure failure) =>
      SessionBindResult._(failure: failure);

  /// Whether session identity was bound successfully.
  bool get isSuccess => salesperson != null && failure == null;
}
