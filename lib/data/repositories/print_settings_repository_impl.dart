import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/print_settings.dart';
import '../../domain/repositories/print_settings_repository.dart';
import '../services/app_logger.dart';
import '../services/error_classification.dart';
import '../services/local_storage_service.dart';

class PrintSettingsRepositoryImpl implements PrintSettingsRepository {
  PrintSettingsRepositoryImpl({
    required LocalStorageService localStorage,
    FirebaseFirestore? firestore,
  })  : _localStorage = localStorage,
        _firestore = firestore;

  final LocalStorageService _localStorage;
  final FirebaseFirestore? _firestore;
  String _cached = PrintSettings.fallbackSupervisorPhone;
  String _cachedCompany = PrintSettings.fallbackCompanyPhone;

  FirebaseFirestore get firestore =>
      _firestore ?? FirebaseFirestore.instance;

  @override
  String get supervisorPhone =>
      _cached.trim().isEmpty ? PrintSettings.fallbackSupervisorPhone : _cached;

  @override
  String get companyPhone => _cachedCompany.trim().isEmpty
      ? PrintSettings.fallbackCompanyPhone
      : _cachedCompany;

  @override
  Future<void> hydrate() async {
    final stored = await _localStorage.readSupervisorPhone();
    if (stored != null && stored.isNotEmpty) {
      _cached = stored;
    }
    final storedCompany = await _localStorage.readCompanyPhone();
    if (storedCompany != null && storedCompany.isNotEmpty) {
      _cachedCompany = storedCompany;
    }
  }

  @override
  Future<PrintSettings> refresh() async {
    try {
      final doc = await firestore
          .collection('server_config')
          .doc('print')
          .get()
          .timeout(const Duration(seconds: 8));
      if (doc.exists && doc.data() != null) {
        final remote = PrintSettings.fromMap(doc.data()!);
        if (remote.supervisorPhone.isNotEmpty) {
          _cached = remote.supervisorPhone;
          await _localStorage.saveSupervisorPhone(_cached);
        }
        if (remote.companyPhone.isNotEmpty) {
          _cachedCompany = remote.companyPhone;
          await _localStorage.saveCompanyPhone(_cachedCompany);
        }
      }
    } catch (e) {
      AppLogger.warning(
        'PrintSettings',
        'Failed to fetch server_config/print: $e',
      );
      if (isFirestorePermissionDenied(e)) {
        AppLogger.error(
          'PrintSettings',
          'Firestore permission-denied reading server_config/print.',
        );
      }
    }
    return PrintSettings(
      supervisorPhone: supervisorPhone,
      companyPhone: companyPhone,
    );
  }
}
