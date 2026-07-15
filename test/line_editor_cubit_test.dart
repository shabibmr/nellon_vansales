import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/ui/core/cubit/line_editor_cubit.dart';

void main() {
  late LineEditorCubit cubit;

  setUp(() {
    cubit = LineEditorCubit(
      initialQuantity: 2,
      initialRate: 10.0,
      initialDiscount: 0.0,
      taxPercentage: 5.0,
    );
  });

  tearDown(() => cubit.close());

  test('Initial state reflects constructor args', () {
    expect(cubit.state.quantity, 2);
    expect(cubit.state.rate, 10.0);
    expect(cubit.state.discount, 0.0);
    expect(cubit.state.taxPercentage, 5.0);
  });

  test('Computed subtotal = rate × quantity', () {
    expect(cubit.state.subtotal, 20.0); // 10 × 2
  });

  test('Computed taxAmount = (subtotal − discount) × tax%', () {
    // (20 - 0) × 5% = 1.0
    expect(cubit.state.taxAmount, 1.0);
  });

  test('Computed total = subtotal + taxAmount − discount', () {
    // 20 + 1 - 0 = 21
    expect(cubit.state.total, 21.0);
  });

  test('setQuantity updates quantity and recalculates totals', () {
    cubit.setQuantity(5);
    expect(cubit.state.quantity, 5);
    expect(cubit.state.subtotal, 50.0); // 10 × 5
    expect(cubit.state.taxAmount, 2.5); // 50 × 5%
    expect(cubit.state.total, 52.5);   // 50 + 2.5
  });

  test('setRate updates rate and recalculates totals', () {
    cubit.setRate(20.0);
    expect(cubit.state.rate, 20.0);
    expect(cubit.state.subtotal, 40.0); // 20 × 2
    expect(cubit.state.taxAmount, 2.0); // 40 × 5%
    expect(cubit.state.total, 42.0);
  });

  test('setDiscount updates discount and recalculates totals', () {
    cubit.setDiscount(5.0);
    expect(cubit.state.discount, 5.0);
    // subtotal = 20, taxAmount = (20 - 5) × 5% = 0.75, total = 20 + 0.75 - 5 = 15.75
    expect(cubit.state.taxAmount, 0.75);
    expect(cubit.state.total, 15.75);
  });

  test('Zero quantity initialQuantity falls back to 1', () {
    final c = LineEditorCubit(
      initialQuantity: 0,
      initialRate: 10.0,
      initialDiscount: 0.0,
      taxPercentage: 0.0,
    );
    expect(c.state.quantity, 1);
    c.close();
  });

  test('State equality via Equatable', () {
    const a = LineEditorState(quantity: 3, rate: 5.0, discount: 1.0, taxPercentage: 10.0);
    const b = LineEditorState(quantity: 3, rate: 5.0, discount: 1.0, taxPercentage: 10.0);
    expect(a, equals(b));
  });

  test('States with different fields are not equal', () {
    const a = LineEditorState(quantity: 3, rate: 5.0, discount: 1.0, taxPercentage: 10.0);
    const b = LineEditorState(quantity: 4, rate: 5.0, discount: 1.0, taxPercentage: 10.0);
    expect(a, isNot(equals(b)));
  });
}
