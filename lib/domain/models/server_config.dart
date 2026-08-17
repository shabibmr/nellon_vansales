import 'package:equatable/equatable.dart';

/// Represents Zoho API credentials and configuration loaded from Firestore.
class ServerConfig extends Equatable {
  final String clientId;
  final String clientSecret;
  final String code; // Represents the Zoho authorization code or refresh token

  /// Zoho Books organization ID. Empty means "keep the client's current
  /// (hardcoded) organization" — see `ZohoApiClient.updateCredentials`.
  final String organizationId;

  const ServerConfig({
    required this.clientId,
    required this.clientSecret,
    required this.code,
    this.organizationId = '',
  });
  /// Whether all essential Zoho OAuth credentials are present and non-empty.
  bool get isValid =>
      clientId.trim().isNotEmpty &&
      clientSecret.trim().isNotEmpty &&
      code.trim().isNotEmpty;

  /// Parses Firestore `server_config/zoho`. Prefers a non-empty
  /// `refresh_token` over `code` (which is often a leftover grant).
  factory ServerConfig.fromMap(Map<String, dynamic> map) {
    // Prefer `refresh_token` when it is non-empty. Firestore `code` is often a
    // leftover Self Client grant (Zoho then returns `invalid_code` on refresh).
    final refreshToken = (map['refresh_token'] ?? '').toString().trim();
    final codeField = (map['code'] ?? '').toString().trim();
    final codeValue = refreshToken.isNotEmpty ? refreshToken : codeField;
    return ServerConfig(
      clientId: (map['client_id'] ?? '').toString().trim(),
      clientSecret: (map['client_secret'] ?? '').toString().trim(),
      code: codeValue,
      organizationId: (map['organization_id'] ?? '').toString().trim(),
    );
  }

  /// Converts the [ServerConfig] to a map.
  Map<String, dynamic> toMap() {
    return {
      'client_id': clientId,
      'client_secret': clientSecret,
      'code': code,
      'organization_id': organizationId,
    };
  }

  @override
  List<Object?> get props => [
    clientId,
    clientSecret,
    code,
    organizationId,
  ];
}
