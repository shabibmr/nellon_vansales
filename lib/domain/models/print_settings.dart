import 'package:equatable/equatable.dart';

class PrintSettings extends Equatable {
  /// Last known hardcoded invoice footer number. Used only when Firestore
  /// and cache have no value so vans never print a blank supervisor line.
  static const String fallbackSupervisorPhone = '+971 501880810';

  final String supervisorPhone;

  const PrintSettings({required this.supervisorPhone});

  String get resolvedPhone =>
      supervisorPhone.trim().isEmpty ? fallbackSupervisorPhone : supervisorPhone.trim();

  factory PrintSettings.fromMap(Map<String, dynamic> map) {
    return PrintSettings(
      supervisorPhone: (map['supervisor_phone'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toMap() => {'supervisor_phone': supervisorPhone};

  @override
  List<Object?> get props => [supervisorPhone];
}
