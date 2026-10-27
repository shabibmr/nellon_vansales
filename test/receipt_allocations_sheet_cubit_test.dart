import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/open_invoice.dart';
import 'package:van_sales/domain/models/receipt_voucher.dart';
import 'package:van_sales/ui/features/receipts/cubit/receipt_allocations_sheet_cubit.dart';

OpenInvoice _inv(String id, double balance, int day) => OpenInvoice(
  invoiceId: id,
  invoiceNumber: 'INV-$id',
  customerId: 'c1',
  date: DateTime(2026, 1, day),
  dueDate: DateTime(2026, 2, day),
  total: balance,
  balance: balance,
  status: 'unpaid',
);

ReceiptAllocationsSheetCubit _cubit({
  List<PaymentAllocation> allocations = const [],
  double payment = 100,
}) => ReceiptAllocationsSheetCubit(
  openInvoices: [_inv('b', 80, 2), _inv('a', 60, 1)],
  allocations: allocations,
  paymentAmount: payment,
);

void main() {
  test('invoices are sorted oldest first', () {
    expect(_cubit().state.invoices.map((i) => i.invoiceId), ['a', 'b']);
  });

  test('fillRemaining caps at invoice balance, then at unallocated payment', () {
    final cubit = _cubit();
    cubit.fillRemaining('a');
    expect(cubit.state.amountFor('a'), 60);
    cubit.fillRemaining('b');
    expect(cubit.state.amountFor('b'), 40);
    expect(cubit.state.canApply, isTrue);
  });

  test('blank, invalid and non-finite text clear the invoice', () {
    final cubit = _cubit();
    cubit.setAmount('a', '25');
    expect(cubit.state.amountFor('a'), 25);
    for (final text in ['', 'abc', 'Infinity', 'NaN']) {
      cubit.setAmount('a', '25');
      cubit.setAmount('a', text);
      expect(cubit.state.amountFor('a'), 0, reason: 'text "$text"');
    }
  });

  test('over-allocating the payment or an invoice disables apply', () {
    final cubit = _cubit();
    cubit.setAmount('a', '60');
    cubit.setAmount('b', '50');
    expect(cubit.state.isOverPayment, isTrue);
    expect(cubit.state.canApply, isFalse);

    cubit.setAmount('b', '40');
    expect(cubit.state.canApply, isTrue);

    final overflow = _cubit(payment: 500)..setAmount('a', '61');
    expect(overflow.state.hasInvoiceOverflow, isTrue);
    expect(overflow.state.canApply, isFalse);
  });

  test('toAllocations returns only positive rows, rounded to 2dp', () {
    final cubit = _cubit();
    cubit.setAmount('a', '10.456');
    final result = cubit.state.toAllocations();
    expect(result, hasLength(1));
    expect(result.single.invoiceId, 'a');
    expect(result.single.amountApplied, 10.46);
  });

  test('allocations to invoices no longer open are dropped from the total', () {
    final cubit = _cubit(
      allocations: const [
        PaymentAllocation(invoiceId: 'a', invoiceNumber: 'INV-a', amountApplied: 30),
        PaymentAllocation(invoiceId: 'gone', invoiceNumber: 'INV-gone', amountApplied: 50),
      ],
    );
    expect(cubit.state.totalAllocated, 30);
    expect(cubit.state.toAllocations().map((a) => a.invoiceId), ['a']);
  });
}
