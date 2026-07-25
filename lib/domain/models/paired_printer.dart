import 'package:equatable/equatable.dart';

/// A Bluetooth thermal printer previously paired with the device (or last used).
class PairedPrinter extends Equatable {
  /// Display name reported by the OS Bluetooth stack.
  final String name;

  /// MAC address used to reconnect (Android Classic).
  final String macAddress;

  const PairedPrinter({
    required this.name,
    required this.macAddress,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'macAddress': macAddress,
      };

  factory PairedPrinter.fromJson(Map<String, dynamic> json) {
    return PairedPrinter(
      name: json['name'] as String? ?? 'Unknown',
      macAddress: json['macAddress'] as String? ?? '',
    );
  }

  @override
  List<Object?> get props => [name, macAddress];
}
