import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/utils/receipt_discount.dart';

void main() {
  group('ReceiptDiscount', () {
    test('calculates peso amount discounts', () {
      const discount = ReceiptDiscount(
        type: ReceiptDiscountType.amount,
        value: 25,
      );

      expect(discount.amountFor(100), 25);
    });

    test('calculates percent discounts rounded to cents', () {
      const discount = ReceiptDiscount(
        type: ReceiptDiscountType.percent,
        value: 12.5,
      );

      expect(discount.amountFor(199.99), 25);
    });

    test('clamps amount discounts to subtotal', () {
      const discount = ReceiptDiscount(
        type: ReceiptDiscountType.amount,
        value: 150,
      );

      expect(discount.amountFor(100), 100);
    });

    test('returns zero for empty or invalid discount values', () {
      const discount = ReceiptDiscount.none();

      expect(discount.amountFor(100), 0);
      expect(discount.amountFor(0), 0);
    });

    test('recomputes percent discount when subtotal changes', () {
      const discount = ReceiptDiscount(
        type: ReceiptDiscountType.percent,
        value: 10,
      );

      expect(discount.amountFor(100), 10);
      expect(discount.amountFor(50), 5);
    });
  });
}
