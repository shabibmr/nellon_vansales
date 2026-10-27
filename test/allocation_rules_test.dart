import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/open_invoice.dart';
import 'package:van_sales/domain/utils/allocation_rules.dart';

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

void main() {
  test('autoAllocate fills oldest first, caps at balance, skips settled', () {
    final result = AllocationRules.autoAllocate(
      [_inv('late', 50, 3), _inv('zero', 0, 2), _inv('old', 40, 1)],
      70,
    );
    expect(result.map((a) => a.invoiceId), ['old', 'late']);
    expect(result.map((a) => a.amountApplied), [40, 30]);
  });

  test('autoAllocate returns nothing for a non-positive amount', () {
    expect(AllocationRules.autoAllocate([_inv('a', 10, 1)], 0), isEmpty);
  });

  test('exceeds tolerates half a cent of drift', () {
    expect(AllocationRules.exceeds(100.004, 100), isFalse);
    expect(AllocationRules.exceeds(100.01, 100), isTrue);
  });

  test('fillFor takes the smaller of remaining payment and balance', () {
    expect(AllocationRules.fillFor(_inv('a', 60, 1), 100), 60);
    expect(AllocationRules.fillFor(_inv('a', 60, 1), 25), 25);
    expect(AllocationRules.fillFor(_inv('a', 60, 1), -5), 0);
  });
}
