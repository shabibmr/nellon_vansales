import 'package:equatable/equatable.dart';

/// Represents Zoho API credentials and configuration loaded from Firestore.
class ServerConfig extends Equatable {
  final String clientId;
  final String clientSecret;
  final String code; // Represents the Zoho authorization code or refresh token

  const ServerConfig({
    required this.clientId,
    required this.clientSecret,
    required this.code,
  });

  /// Factory constructor to create a [ServerConfig] from a Firestore map.
  factory ServerConfig.fromMap(Map<String, dynamic> map) {
    return ServerConfig(
      clientId: map['client_id'] as String? ?? '',
      clientSecret: map['client_secret'] as String? ?? '',
      code: map['code'] as String? ?? '',
    );
  }

  /// Converts the [ServerConfig] to a map.
  Map<String, dynamic> toMap() {
    return {
      'client_id': clientId,
      'client_secret': clientSecret,
      'code': code,
    };
  }

  @override
  List<Object?> get props => [clientId, clientSecret, code];
}
