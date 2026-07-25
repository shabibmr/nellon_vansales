import 'package:flutter_bloc/flutter_bloc.dart';

/// Shared list vs grid layout preference for dashboard menu tabs
/// (Operations and Reports).
///
/// `true` = grid mode, `false` = list mode.
class ListLayoutCubit extends Cubit<bool> {
  ListLayoutCubit() : super(false);

  void setGrid(bool isGrid) => emit(isGrid);

  void toggle() => emit(!state);
}
