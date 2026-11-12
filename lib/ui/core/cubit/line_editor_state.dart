import 'package:equatable/equatable.dart';

import '../../../domain/utils/money_math.dart';

/// Reactive line-item calculation state for [LineEditorCubit].
///
/// [quantity] and [rate] are expressed in the currently selected unit;
/// the math is unit-agnostic (subtotal = rate × quantity either way).
class LineEditorState extends Equatable {
  final double quantity;
  final double rate;
  final double discount;
  final double taxPercentage;

  /// rate × quantity, rounded to the active money scale.
  double get subtotal => roundMoney(rate * quantity);

  /// Tax on the full subtotal (discount is applied after tax).
  double get taxAmount => roundMoney(subtotal * (taxPercentage / 100));

  /// subtotal + tax − discount, rounded to the active money scale.
  double get total => roundMoney(subtotal + taxAmount - discount);

  const LineEditorState({
    this.quantity = 1,
    this.rate = 0.0,
    this.discount = 0.0,
    this.taxPercentage = 0.0,
  });

  LineEditorState copyWith({
    double? quantity,
    double? rate,
    double? discount,
    double? taxPercentage,
  }) {
    return LineEditorState(
      quantity: quantity ?? this.quantity,
      rate: rate ?? this.rate,
      discount: discount ?? this.discount,
      taxPercentage: taxPercentage ?? this.taxPercentage,
    );
  }

  @override
  List<Object?> get props => [quantity, rate, discount, taxPercentage];
}
