import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubit/organization_cubit.dart';

extension OrgBuildContext on BuildContext {
  OrganizationCubit get org => read<OrganizationCubit>();

  /// Formats [value] using the active organization's symbol and decimal places.
  String formatCurrency(double value, {int? decimals, String? symbol}) =>
      org.formatCurrency(value, decimals: decimals, symbol: symbol);
}
