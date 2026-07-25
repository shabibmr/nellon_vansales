import 'package:equatable/equatable.dart';

/// Reactive line-item calculation state for [LineEditorCubit].
///
/// [quantity] and [rate] are expressed in the currently selected unit;
/// the math is unit-agnostic (subtotal = rate × quantity either way).
class LineEditorState extends Equatable {
  final double quantity;
  final double rate;
  final double discount;
  final double taxPercentage;

  /// Pre-computed: rate × quantity
  double get subtotal => rate * quantity;

  /// Pre-computed: (subtotal − discount) × taxPercentage / 100
  double get taxAmount => (subtotal - discount) * (taxPercentage / 100);

  /// Pre-computed: subtotal + taxAmount − discount
  double get total => subtotal + taxAmount - discount;

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
