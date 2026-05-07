import 'package:intl/intl.dart';

class CurrencyFormatter {
  static final NumberFormat _pesoFormat = NumberFormat.currency(
    locale: 'en_PH', // Philippines locale
    symbol: '₱',
  );

  static String format(double amount) {
    return _pesoFormat.format(amount);
  }
}
