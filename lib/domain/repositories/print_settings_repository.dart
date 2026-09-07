import '../models/print_settings.dart';

abstract class PrintSettingsRepository {
  /// Cached (or fallback) phone for PDF/thermal. Never empty.
  String get supervisorPhone;

  /// Loads last-good phone from Hive into memory. No-op when cache is empty.
  Future<void> hydrate();

  /// Fetches `server_config/print`, updates cache when the field is non-empty.
  Future<PrintSettings> refresh();
}
