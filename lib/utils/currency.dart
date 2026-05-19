import 'package:intl/intl.dart';

class CurrencyFormatter {
  static final NumberFormat _pesoFormat = NumberFormat.currency(
    locale: 'en_PH', // Philippines locale
    symbol: '\u20B1',
    decimalDigits: 2,
  );

  static String format(double amount) {
    return _pesoFormat.format(amount);
  }
}
