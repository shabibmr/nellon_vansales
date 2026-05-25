import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubit/organization_cubit.dart';

extension OrgBuildContext on BuildContext {
  OrganizationCubit get org => read<OrganizationCubit>();
}
