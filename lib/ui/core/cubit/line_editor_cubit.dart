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
    required double initialQuantity,
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
  void setQuantity(double quantity) {
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

  /// Recomputes the rate when the user switches unit: effective rate =
  /// base rate × the selected unit's conversion rate (Zoho stores no
  /// per-unit price). The rate stays user-editable afterwards via [setRate].
  void setUnit({required double baseRate, required double conversionRate}) {
    emit(state.copyWith(rate: baseRate * conversionRate));
  }
}
