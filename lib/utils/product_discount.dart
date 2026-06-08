double productDiscountPercent(Map<String, dynamic> product) {
  final enabled =
      product['discount_enabled'] == true ||
      product['discount_enabled'] == 1 ||
      product['discount_enabled']?.toString() == '1';
  final percent = (product['discount_percent'] as num?)?.toDouble() ?? 0;
  if (!enabled || !percent.isFinite || percent <= 0 || percent >= 100) {
    return 0;
  }
  return percent;
}

double discountedProductPrice(Map<String, dynamic> product) {
  final price = (product['price'] as num?)?.toDouble() ?? 0;
  final percent = productDiscountPercent(product);
  if (price <= 0 || percent <= 0) return price;
  return ((price * (100 - percent)) / 100 * 100).round() / 100;
}

double productDiscountAmount(Map<String, dynamic> product, int quantity) {
  final price = (product['price'] as num?)?.toDouble() ?? 0;
  final discounted = discountedProductPrice(product);
  final amount = (price - discounted) * quantity;
  return amount <= 0 ? 0 : (amount * 100).round() / 100;
}

double cartItemDiscountPercent(Map<String, dynamic> item) {
  if (item.containsKey('checkout_discount_enabled') ||
      item.containsKey('checkout_discount_percent')) {
    final enabled =
        item['checkout_discount_enabled'] == true ||
        item['checkout_discount_enabled'] == 1 ||
        item['checkout_discount_enabled']?.toString() == '1';
    final percent =
        (item['checkout_discount_percent'] as num?)?.toDouble() ?? 0;
    if (!enabled || !percent.isFinite || percent <= 0 || percent >= 100) {
      return 0;
    }
    return percent;
  }

  final product = item['product'];
  if (product is! Map<String, dynamic>) return 0;
  return productDiscountPercent(product);
}

double discountedCartItemPrice(Map<String, dynamic> item) {
  final product = item['product'];
  if (product is! Map<String, dynamic>) return 0;
  final price = (product['price'] as num?)?.toDouble() ?? 0;
  final percent = cartItemDiscountPercent(item);
  if (price <= 0 || percent <= 0) return price;
  return ((price * (100 - percent)) / 100 * 100).round() / 100;
}

double cartItemDiscountAmount(Map<String, dynamic> item) {
  final product = item['product'];
  if (product is! Map<String, dynamic>) return 0;
  final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
  final price = (product['price'] as num?)?.toDouble() ?? 0;
  final discounted = discountedCartItemPrice(item);
  final amount = (price - discounted) * quantity;
  return amount <= 0 ? 0 : (amount * 100).round() / 100;
}
