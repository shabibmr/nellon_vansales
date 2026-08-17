import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/services/hive_database_service.dart';
import '../../../domain/models/salesperson.dart';

/// Cubit that holds the resolved active [Salesperson] for the current session.
///
/// Populated from Hive at construction and refreshed once [AuthBloc] resolves
/// the logged-in user's salesperson/location mapping (including the Zoho
/// display [Salesperson.name]). Read [locationId] / [name] from here rather
/// than reaching into [HiveDatabaseService] directly.
class SalespersonCubit extends Cubit<Salesperson?> {
  final HiveDatabaseService _db;

  SalespersonCubit(HiveDatabaseService db)
      : _db = db,
        super(db.getCurrentSalesperson());

  /// The Zoho Location ID mapped to the active salesperson, if resolved.
  String? get locationId => state?.locationId;

  /// The Zoho display name of the active salesperson, if resolved.
  String? get name {
    final n = state?.name.trim();
    if (n == null || n.isEmpty) return null;
    return n;
  }

  /// Session phone of the active salesperson, if resolved.
  String? get phone {
    final p = state?.phone?.trim();
    if (p == null || p.isEmpty) return null;
    return p;
  }

  /// Re-reads the cached active salesperson from Hive (e.g. after login resolution).
  void refresh() => emit(_db.getCurrentSalesperson());
}
