import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/services/hive_database_service.dart';
import '../../../domain/models/organization.dart';

/// Cubit that holds the locally-cached [Organization] loaded from Hive.
/// Currency symbol, company name, and other org details should be read from here
/// rather than hardcoded anywhere in the UI.
class OrganizationCubit extends Cubit<Organization?> {
  OrganizationCubit(HiveDatabaseService db) : super(db.getOrganization());

  String get currencySymbol => state?.currencySymbol ?? '₹';
  String get companyName => state?.name ?? 'Van Sales Pro';
  String get currencyCode => state?.currencyCode ?? 'INR';
}
