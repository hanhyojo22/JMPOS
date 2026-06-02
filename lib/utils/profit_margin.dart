double grossProfit({
  required double coveredRevenue,
  required double costOfGoodsSold,
}) {
  return coveredRevenue - costOfGoodsSold;
}

double excludedRevenue({
  required double totalRevenue,
  required double coveredRevenue,
}) {
  return totalRevenue - coveredRevenue;
}

double grossMarginPercent({
  required double coveredRevenue,
  required double costOfGoodsSold,
}) {
  if (coveredRevenue == 0) return 0;
  return grossProfit(
        coveredRevenue: coveredRevenue,
        costOfGoodsSold: costOfGoodsSold,
      ) /
      coveredRevenue *
      100;
}
