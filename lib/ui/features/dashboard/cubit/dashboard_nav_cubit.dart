import 'package:flutter_bloc/flutter_bloc.dart';

class DashboardNavCubit extends Cubit<int> {
  /// Defaults to Dashboard (index 1). Customers (index 0) is hidden from the
  /// bottom bar for now but remains available via the wide-screen sidebar.
  DashboardNavCubit() : super(1);

  void setTab(int index) => emit(index);
}
