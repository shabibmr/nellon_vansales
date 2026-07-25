import 'package:equatable/equatable.dart';

/// Represents a Zoho Books Salesperson (sales user) entity.
///
/// The master list mirrors all sales users configured in Zoho Books. The single
/// "active" instance additionally carries location, cash account, and voucher
/// context resolved at login from `cm_salesperson_profile` + `GET /locations`.
class Salesperson extends Equatable {
  /// Unique salesperson identifier from Zoho (salesperson_id).
  final String id;

  /// Full display name of the salesperson.
  final String name;

  /// Login email address of the salesperson (legacy; may be empty).
  final String email;

  /// E.164 phone number bound to this session (`cm_salesperson_profile.record_name`).
  final String? phone;

  /// Zoho Location ID mapped to this salesperson (van warehouse), if resolved.
  /// Falls back to the primary business location when the salesperson has no
  /// van mapped yet (orders-only mode).
  final String? locationId;

  /// Display name of the mapped van location, if resolved.
  final String? locationName;

  /// Local voucher number prefix for this van/location session, if configured.
  final String? voucherPrefix;

  /// Zoho Chart of Accounts id for this salesperson's personal cash ledger
  /// (`cf_cash_account`).
  final String? cashAccountId;

  /// Display name of the mapped cash account, if resolved.
  final String? cashAccountName;

  /// Zoho lifecycle status (e.g. "active", "inactive").
  final String status;

  /// Creates a new [Salesperson] record.
  const Salesperson({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.locationId,
    this.locationName,
    this.voucherPrefix,
    this.cashAccountId,
    this.cashAccountName,
    this.status = 'active',
  });

  /// Creates a copy of this [Salesperson] with replaced values for specific fields.
  ///
  /// Pass [clearLocationId] as `true` to explicitly null out [locationId]
  /// (e.g. when the Zoho mapping was removed); otherwise a null [locationId]
  /// argument keeps the current value. Same pattern for [locationName],
  /// [voucherPrefix], [cashAccountId] and [cashAccountName] via their
  /// respective `clear*` flags.
  Salesperson copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    bool clearPhone = false,
    String? locationId,
    bool clearLocationId = false,
    String? locationName,
    bool clearLocationName = false,
    String? voucherPrefix,
    bool clearVoucherPrefix = false,
    String? cashAccountId,
    bool clearCashAccountId = false,
    String? cashAccountName,
    bool clearCashAccountName = false,
    String? status,
  }) {
    return Salesperson(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: clearPhone ? null : (phone ?? this.phone),
      locationId: clearLocationId ? null : (locationId ?? this.locationId),
      locationName:
          clearLocationName ? null : (locationName ?? this.locationName),
      voucherPrefix:
          clearVoucherPrefix ? null : (voucherPrefix ?? this.voucherPrefix),
      cashAccountId:
          clearCashAccountId ? null : (cashAccountId ?? this.cashAccountId),
      cashAccountName: clearCashAccountName
          ? null
          : (cashAccountName ?? this.cashAccountName),
      status: status ?? this.status,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    email,
    phone,
    locationId,
    locationName,
    voucherPrefix,
    cashAccountId,
    cashAccountName,
    status,
  ];
}
