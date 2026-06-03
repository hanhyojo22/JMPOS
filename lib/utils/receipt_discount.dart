enum ReceiptDiscountType { amount, percent }

class ReceiptDiscount {
  const ReceiptDiscount({required this.type, required this.value});

  const ReceiptDiscount.none() : type = ReceiptDiscountType.amount, value = 0;

  final ReceiptDiscountType type;
  final double value;

  double amountFor(double subtotal) {
    if (!subtotal.isFinite || subtotal <= 0 || !value.isFinite || value <= 0) {
      return 0;
    }
    final rawAmount = switch (type) {
      ReceiptDiscountType.amount => value,
      ReceiptDiscountType.percent => subtotal * (value.clamp(0, 100) / 100),
    };
    return _roundMoney(rawAmount.clamp(0, subtotal));
  }

  String get storageType => switch (type) {
    ReceiptDiscountType.amount => 'amount',
    ReceiptDiscountType.percent => 'percent',
  };

  bool get isActive => value.isFinite && value > 0;

  static double _roundMoney(num value) => (value * 100).round() / 100;
}
