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
  SalespersonCubit(HiveDatabaseService db) : super(db.getCurrentSalesperson());

  /// The Zoho Location ID mapped to the active salesperson, if resolved.
  String? get locationId => state?.locationId;

  /// The Zoho display name of the active salesperson, if resolved.
  String? get name {
    final n = state?.name.trim();
    if (n == null || n.isEmpty) return null;
    return n;
  }

  /// Re-reads the cached active salesperson from Hive (e.g. after login resolution).
  void refresh(HiveDatabaseService db) => emit(db.getCurrentSalesperson());
}
