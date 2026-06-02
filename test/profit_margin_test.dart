import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/utils/profit_margin.dart';

void main() {
  group('gross profit margin', () {
    test('calculates profit and percentage from covered sales only', () {
      expect(grossProfit(coveredRevenue: 250, costOfGoodsSold: 150), 100);
      expect(grossMarginPercent(coveredRevenue: 250, costOfGoodsSold: 150), 40);
    });

    test('returns zero margin when no covered revenue exists', () {
      expect(grossMarginPercent(coveredRevenue: 0, costOfGoodsSold: 0), 0);
    });

    test('preserves losses as negative profit and margin', () {
      expect(grossProfit(coveredRevenue: 80, costOfGoodsSold: 100), -20);
      expect(grossMarginPercent(coveredRevenue: 80, costOfGoodsSold: 100), -25);
    });

    test('reconciles covered and excluded sales revenue', () {
      final excluded = excludedRevenue(totalRevenue: 300, coveredRevenue: 200);

      expect(excluded, 100);
      expect(200 + excluded, 300);
    });
  });
}
