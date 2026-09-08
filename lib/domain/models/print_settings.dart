import 'package:equatable/equatable.dart';

class PrintSettings extends Equatable {
  /// Last known hardcoded invoice footer number. Used only when Firestore
  /// and cache have no value so vans never print a blank supervisor line.
  static const String fallbackSupervisorPhone = '+971 501880810';

  /// Company phone printed on the voucher letterhead / "Supplier" block. Used
  /// only when Firestore and cache have no value so the header is never blank.
  static const String fallbackCompanyPhone = '+971589642244';

  final String supervisorPhone;
  final String companyPhone;

  const PrintSettings({
    required this.supervisorPhone,
    this.companyPhone = '',
  });

  String get resolvedPhone =>
      supervisorPhone.trim().isEmpty ? fallbackSupervisorPhone : supervisorPhone.trim();

  String get resolvedCompanyPhone =>
      companyPhone.trim().isEmpty ? fallbackCompanyPhone : companyPhone.trim();

  factory PrintSettings.fromMap(Map<String, dynamic> map) {
    return PrintSettings(
      supervisorPhone: (map['supervisor_phone'] ?? '').toString().trim(),
      companyPhone: (map['company_phone'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toMap() => {
        'supervisor_phone': supervisorPhone,
        'company_phone': companyPhone,
      };

  @override
  List<Object?> get props => [supervisorPhone, companyPhone];
}
