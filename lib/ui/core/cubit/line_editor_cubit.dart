import 'package:flutter_bloc/flutter_bloc.dart';
import 'line_editor_state.dart';

export 'line_editor_state.dart';

/// Manages reactive line-item calculations for [SharedItemLineEditorDialog].
///
/// Text controllers in the dialog remain widget-local for IME compatibility.
/// The dialog dispatches parsed values here on each keystroke so that the
/// totals preview panel rebuilds via [BlocBuilder] without any [setState].
class LineEditorCubit extends Cubit<LineEditorState> {
  LineEditorCubit({
    required int initialQuantity,
    required double initialRate,
    required double initialDiscount,
    required double taxPercentage,
  }) : super(LineEditorState(
          quantity: initialQuantity > 0 ? initialQuantity : 1,
          rate: initialRate,
          discount: initialDiscount,
          taxPercentage: taxPercentage,
        ));

  /// Updates quantity from the parsed field value (0 while the user types).
  void setQuantity(int quantity) {
    emit(state.copyWith(quantity: quantity));
  }

  /// Updates rate from the parsed field value.
  void setRate(double rate) {
    emit(state.copyWith(rate: rate));
  }

  /// Updates discount from the parsed field value.
  void setDiscount(double discount) {
    emit(state.copyWith(discount: discount));
  }
}
