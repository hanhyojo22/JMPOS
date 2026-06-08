import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/utils/product_discount.dart';

void main() {
  group('product discount', () {
    test('returns original price when discount is disabled', () {
      final product = {
        'price': 100.0,
        'discount_enabled': 0,
        'discount_percent': 10.0,
      };

      expect(productDiscountPercent(product), 0);
      expect(discountedProductPrice(product), 100);
      expect(productDiscountAmount(product, 2), 0);
    });

    test('calculates discounted unit price and line discount', () {
      final product = {
        'price': 199.99,
        'discount_enabled': 1,
        'discount_percent': 12.5,
      };

      expect(productDiscountPercent(product), 12.5);
      expect(discountedProductPrice(product), 174.99);
      expect(productDiscountAmount(product, 2), 50);
    });

    test('ignores invalid percent values', () {
      for (final percent in const [0, 100, 125]) {
        final product = {
          'price': 100.0,
          'discount_enabled': true,
          'discount_percent': percent,
        };

        expect(productDiscountPercent(product), 0);
        expect(discountedProductPrice(product), 100);
      }
    });

    test('cart item falls back to product discount', () {
      final item = {
        'product': {
          'price': 100.0,
          'discount_enabled': 1,
          'discount_percent': 15.0,
        },
        'quantity': 2,
      };

      expect(cartItemDiscountPercent(item), 15);
      expect(discountedCartItemPrice(item), 85);
      expect(cartItemDiscountAmount(item), 30);
    });

    test('cart item override replaces product discount for checkout only', () {
      final item = {
        'product': {
          'price': 100.0,
          'discount_enabled': 1,
          'discount_percent': 15.0,
        },
        'quantity': 2,
        'checkout_discount_enabled': true,
        'checkout_discount_percent': 25.0,
      };

      expect(cartItemDiscountPercent(item), 25);
      expect(discountedCartItemPrice(item), 75);
      expect(cartItemDiscountAmount(item), 50);
    });

    test('cart item override can remove a product discount', () {
      final item = {
        'product': {
          'price': 100.0,
          'discount_enabled': 1,
          'discount_percent': 15.0,
        },
        'quantity': 2,
        'checkout_discount_enabled': false,
        'checkout_discount_percent': null,
      };

      expect(cartItemDiscountPercent(item), 0);
      expect(discountedCartItemPrice(item), 100);
      expect(cartItemDiscountAmount(item), 0);
    });
  });
}
