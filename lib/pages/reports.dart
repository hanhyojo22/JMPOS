import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_app/database/database_helper.dart';
import 'package:pos_app/theme/app_typography.dart';
import 'package:pos_app/utils/currency.dart';
import 'package:pos_app/utils/profit_margin.dart' as profit_margin;
import 'package:sqflite_sqlcipher/sqflite.dart';

const _purple = Color(0xFF667EEA);
const _green = Color(0xFF10B981);
const _amber = Color(0xFFF59E0B);
const _red = Color(0xFFEF4444);
const _lowStockThreshold = 10;

enum _ReportPeriod { today, custom }

enum _ReportSection { overview, profit, topProducts, inventory, voids }

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, this.onOpenMenu, this.readOnly = false});

  final VoidCallback? onOpenMenu;
  final bool readOnly;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  _ReportPeriod _period = _ReportPeriod.today;
  _ReportSection _section = _ReportSection.overview;
  DateTimeRange? _customRange;
  _ReportData _data = _ReportData.empty();
  bool _loading = true;
  bool _refreshingPeriod = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports({bool showFullPageLoader = true}) async {
    if (showFullPageLoader && mounted) {
      setState(() => _loading = true);
    }
    try {
      final data = await _fetchReportData();
      if (mounted) setState(() => _data = data);
    } catch (e) {
      debugPrint('Report error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to load reports: $e')));
      }
    } finally {
      if (showFullPageLoader && mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<_ReportData> _fetchReportData() async {
    final db = await DatabaseHelper.instance.database;
    await DatabaseHelper.instance.ensureSalesSchema();
    if (!widget.readOnly) {
      await DatabaseHelper.instance.completeDueSales();
    }
    final range = _activeRange();
    final salesRows = await _querySalesForRange(db, range);
    final products = await db.query(
      'products',
      where: 'pending_delete = ?',
      whereArgs: [0],
      orderBy: 'product_name COLLATE NOCASE ASC',
    );
    return _aggregate(salesRows, products, range);
  }

  Future<List<Map<String, Object?>>> _querySalesForRange(
    Database db,
    DateTimeRange range,
  ) {
    return db.query(
      'sales',
      where: 'created_at >= ? AND created_at < ?',
      whereArgs: [range.start.toIso8601String(), range.end.toIso8601String()],
      orderBy: 'created_at DESC',
    );
  }

  DateTimeRange _activeRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case _ReportPeriod.today:
        return DateTimeRange(
          start: today,
          end: today.add(const Duration(days: 1)),
        );
      case _ReportPeriod.custom:
        final custom = _customRange;
        if (custom == null) {
          return DateTimeRange(
            start: today,
            end: today.add(const Duration(days: 1)),
          );
        }
        final start = DateTime(
          custom.start.year,
          custom.start.month,
          custom.start.day,
        );
        final endDay = DateTime(
          custom.end.year,
          custom.end.month,
          custom.end.day,
        );
        return DateTimeRange(
          start: start,
          end: endDay.add(const Duration(days: 1)),
        );
    }
  }

  _ReportData _aggregate(
    List<Map<String, Object?>> rows,
    List<Map<String, Object?>> products,
    DateTimeRange range,
  ) {
    final productById = <int, Map<String, Object?>>{
      for (final product in products)
        if ((product['id'] as num?)?.toInt() case final int id) id: product,
    };
    final filteredRows = <Map<String, Object?>>[];
    final receipts = <String, _ReceiptAccumulator>{};
    final productStats = <int, _ProductAccumulator>{};
    final categoryRevenue = <String, double>{};
    final trendRevenue = <DateTime, double>{};
    final trendProfit = <DateTime, double>{};
    var coveredRevenue = 0.0;
    var costOfGoodsSold = 0.0;
    var legacyMissingCostCount = 0;
    var productDiscountTotal = 0.0;

    for (final row in rows) {
      final createdAt = DateTime.tryParse(
        row['created_at']?.toString() ?? '',
      )?.toLocal();
      if (createdAt == null ||
          createdAt.isBefore(range.start) ||
          !createdAt.isBefore(range.end)) {
        continue;
      }
      filteredRows.add(row);
      final receiptKey = _receiptKey(row, createdAt);
      final receipt = receipts.putIfAbsent(
        receiptKey,
        () => _ReceiptAccumulator(receiptNumber: receiptKey),
      );
      receipt.add(row, createdAt);

      if (_isVoided(row)) continue;
      final productDiscount =
          (row['product_discount_amount'] as num?)?.toDouble() ?? 0;
      if (productDiscount.isFinite && productDiscount > 0) {
        productDiscountTotal += productDiscount;
      }
      final productId = (row['product_id'] as num?)?.toInt() ?? -1;
      final name = row['product_name']?.toString().trim();
      final stat = productStats.putIfAbsent(
        productId,
        () => _ProductAccumulator(
          name: name == null || name.isEmpty ? 'Unknown product' : name,
        ),
      );
      stat.add(row);
      final category = productById[productId]?['category']?.toString().trim();
      final categoryName = category == null || category.isEmpty
          ? 'Other'
          : category;
      final total = (row['total'] as num?)?.toDouble() ?? 0;
      categoryRevenue[categoryName] =
          (categoryRevenue[categoryName] ?? 0) + total;
      final costPrice = (row['cost_price'] as num?)?.toDouble();
      if (costPrice == null) {
        legacyMissingCostCount++;
      }
    }

    final completedReceipts = receipts.values
        .where((receipt) => !receipt.isVoided)
        .toList();
    final voidedReceipts =
        receipts.values.where((receipt) => receipt.isVoided).toList()
          ..sort((a, b) => b.voidedAt.compareTo(a.voidedAt));
    final stats = productStats.values.toList();
    final topByQuantity = [...stats]
      ..sort((a, b) => b.quantity.compareTo(a.quantity));
    final topByRevenue = [...stats]
      ..sort((a, b) => b.revenue.compareTo(a.revenue));
    final productProfitability = [...stats]
      ..sort((a, b) => b.grossProfit.compareTo(a.grossProfit));

    for (final receipt in completedReceipts) {
      final createdAt = receipt.createdAt;
      if (createdAt == null) continue;
      final trendKey = _period == _ReportPeriod.today
          ? DateTime(
              createdAt.year,
              createdAt.month,
              createdAt.day,
              createdAt.hour,
            )
          : DateTime(createdAt.year, createdAt.month, createdAt.day);
      trendRevenue[trendKey] = (trendRevenue[trendKey] ?? 0) + receipt.netTotal;
      if (receipt.missingCostItems == 0) {
        coveredRevenue += receipt.netTotal;
        costOfGoodsSold += receipt.costOfGoodsSold;
        trendProfit[trendKey] =
            (trendProfit[trendKey] ?? 0) + receipt.grossProfit;
      }
    }

    final inventory = _InventorySnapshot.fromProducts(products);
    final soldProductIds = productStats.keys.toSet();
    final slowMovers =
        products
            .where((product) {
              final id = (product['id'] as num?)?.toInt();
              final stock = (product['stock_quantity'] as num?)?.toInt() ?? 0;
              return stock > 0 && id != null && !soldProductIds.contains(id);
            })
            .map(_SlowMover.fromProduct)
            .toList()
          ..sort((a, b) => b.stock.compareTo(a.stock));

    return _ReportData(
      range: range,
      filteredRows: filteredRows,
      revenue: completedReceipts.fold(
        0,
        (sum, receipt) => sum + receipt.netTotal,
      ),
      coveredRevenue: coveredRevenue,
      costOfGoodsSold: costOfGoodsSold,
      productDiscountTotal: productDiscountTotal,
      legacyMissingCostCount: legacyMissingCostCount,
      receipts: completedReceipts.length,
      itemsSold: completedReceipts.fold(
        0,
        (sum, receipt) => sum + receipt.quantity,
      ),
      voidedAmount: voidedReceipts.fold(
        0,
        (sum, receipt) => sum + receipt.netTotal,
      ),
      voidedReceipts: voidedReceipts
          .map((receipt) => receipt.toVoidAudit())
          .toList(),
      topByQuantity: topByQuantity.take(5).toList(),
      topByRevenue: topByRevenue.take(5).toList(),
      productProfitability: productProfitability,
      categoryRevenue: categoryRevenue,
      trend: _buildTrend(range, trendRevenue),
      profitTrend: _buildTrend(range, trendProfit),
      inventory: inventory,
      slowMovers: slowMovers,
      periodLabel: switch (_period) {
        _ReportPeriod.today => 'Today',
        _ReportPeriod.custom => 'Date',
      },
    );
  }

  List<_TrendPoint> _buildTrend(
    DateTimeRange range,
    Map<DateTime, double> revenue,
  ) {
    final points = <_TrendPoint>[];
    if (_period == _ReportPeriod.today) {
      for (var hour = 0; hour < 24; hour++) {
        final time = DateTime(
          range.start.year,
          range.start.month,
          range.start.day,
          hour,
        );
        points.add(
          _TrendPoint(
            label: DateFormat('ha').format(time),
            value: revenue[time] ?? 0,
          ),
        );
      }
      return points;
    }
    for (
      var day = range.start;
      day.isBefore(range.end);
      day = day.add(const Duration(days: 1))
    ) {
      final time = DateTime(day.year, day.month, day.day);
      points.add(
        _TrendPoint(
          label: DateFormat('MMM d').format(time),
          value: revenue[time] ?? 0,
        ),
      );
    }
    return points;
  }

  Future<void> _selectPeriod(_ReportPeriod period) async {
    if (period == _ReportPeriod.custom) {
      final now = DateTime.now();
      final selected = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: now,
        initialDateRange:
            _customRange ??
            DateTimeRange(
              start: now.subtract(const Duration(days: 6)),
              end: now,
            ),
      );
      if (selected == null) return;
      _customRange = selected;
    }
    if (!mounted) return;
    setState(() {
      _period = period;
      _refreshingPeriod = true;
    });
    try {
      final data = await _fetchReportData();
      if (!mounted) return;
      setState(() => _data = data);
    } catch (e) {
      debugPrint('Report period refresh error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to refresh report: $e')));
      }
    } finally {
      if (mounted) setState(() => _refreshingPeriod = false);
    }
  }

  Future<void> _showExportSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Export report', style: AppTypography.sectionTitle),
              const SizedBox(height: 4),
              Text(_rangeLabel, style: AppTypography.caption),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.summarize_outlined, color: _purple),
                title: const Text('Summary CSV'),
                subtitle: const Text(
                  'Dashboard metrics and inventory snapshot',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _exportCsv(summary: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.table_rows_outlined, color: _purple),
                title: const Text('Detailed CSV'),
                subtitle: const Text('Filtered sale line items'),
                onTap: () {
                  Navigator.pop(context);
                  _exportCsv(summary: false);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportCsv({required bool summary}) async {
    setState(() => _exporting = true);
    try {
      final csv = summary ? _buildSummaryCsv() : _buildDetailedCsv();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      await FileSaver.instance.saveAs(
        name: '${summary ? 'report_summary' : 'report_details'}_$timestamp',
        bytes: Uint8List.fromList(utf8.encode(csv)),
        fileExtension: 'csv',
        mimeType: MimeType.other,
        customMimeType: 'text/csv',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${summary ? 'Summary' : 'Detailed'} report exported',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: _red),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _buildSummaryCsv() {
    final buffer = StringBuffer()
      ..writeln('POS Report Summary')
      ..writeln('Range,${_csvCell(_rangeLabel)}')
      ..writeln()
      ..writeln('Sales Overview')
      ..writeln('Metric,Value')
      ..writeln('Net Sales,${_data.revenue}')
      ..writeln('Product Discounts,${_data.productDiscountTotal}')
      ..writeln('Profit-covered Sales,${_data.coveredRevenue}')
      ..writeln('Excluded Sales,${_data.excludedRevenue}')
      ..writeln('Cost Of Goods Sold,${_data.costOfGoodsSold}')
      ..writeln('Gross Profit,${_data.grossProfit}')
      ..writeln('Gross Margin,${_data.grossMarginPercent}%')
      ..writeln(
        'Legacy Items Missing Historical Cost,${_data.legacyMissingCostCount}',
      )
      ..writeln('Receipt Count,${_data.receipts}')
      ..writeln('Items Sold,${_data.itemsSold}')
      ..writeln('Average Sale,${_data.averageSale}')
      ..writeln('Void Count,${_data.voidedReceipts.length}')
      ..writeln('Void Amount,${_data.voidedAmount}')
      ..writeln()
      ..writeln('Current Inventory Snapshot')
      ..writeln('Metric,Value')
      ..writeln('Products In Stock,${_data.inventory.productsInStock}')
      ..writeln('Units On Hand,${_data.inventory.unitsOnHand}')
      ..writeln('Low Stock Products,${_data.inventory.lowStock.length}')
      ..writeln('Out Of Stock Products,${_data.inventory.outOfStock.length}')
      ..writeln('Estimated Cost Value,${_data.inventory.costValue}')
      ..writeln()
      ..writeln('Product Profitability')
      ..writeln(
        'Product,Units,Revenue,Covered Revenue,Excluded Revenue,Cost,Gross Profit,Gross Margin,Missing Cost Items',
      );
    for (final item in _data.productProfitability) {
      buffer.writeln(
        [
          item.name,
          item.quantity,
          item.revenue,
          item.coveredRevenue,
          item.excludedRevenue,
          item.costOfGoodsSold,
          item.grossProfit,
          '${item.grossMarginPercent}%',
          item.missingCostItems,
        ].map(_csvCell).join(','),
      );
    }
    buffer
      ..writeln()
      ..writeln('Top Products By Quantity')
      ..writeln('Product,Units,Revenue');
    for (final item in _data.topByQuantity) {
      buffer.writeln('${_csvCell(item.name)},${item.quantity},${item.revenue}');
    }
    buffer
      ..writeln()
      ..writeln('Top Products By Revenue')
      ..writeln('Product,Units,Revenue');
    for (final item in _data.topByRevenue) {
      buffer.writeln('${_csvCell(item.name)},${item.quantity},${item.revenue}');
    }
    buffer
      ..writeln()
      ..writeln('Sales By Category')
      ..writeln('Category,Revenue');
    for (final entry in _data.categoryRevenue.entries) {
      buffer.writeln('${_csvCell(entry.key)},${entry.value}');
    }
    buffer
      ..writeln()
      ..writeln('Low Stock Products')
      ..writeln('Product,Units');
    for (final item in _data.inventory.lowStock) {
      buffer.writeln('${_csvCell(item.name)},${item.stock}');
    }
    buffer
      ..writeln()
      ..writeln('Out Of Stock Products')
      ..writeln('Product,Units');
    for (final item in _data.inventory.outOfStock) {
      buffer.writeln('${_csvCell(item.name)},${item.stock}');
    }
    buffer
      ..writeln()
      ..writeln('Slow-moving Products')
      ..writeln('Product,Units On Hand');
    for (final item in _data.slowMovers) {
      buffer.writeln('${_csvCell(item.name)},${item.stock}');
    }
    buffer
      ..writeln()
      ..writeln('Void Audit')
      ..writeln('Receipt Number,Voided At,Total,Voided By,Reason');
    for (final item in _data.voidedReceipts) {
      buffer.writeln(
        [
          item.receiptNumber,
          item.voidedAt.toIso8601String(),
          item.total,
          item.voidedBy,
          item.reason,
        ].map(_csvCell).join(','),
      );
    }
    return buffer.toString();
  }

  String _buildDetailedCsv() {
    final buffer = StringBuffer()
      ..writeln(
        'Receipt Number,Date,Product ID,Product Name,Quantity,Unit Price,Unit Cost,Gross Profit,Total,Status,Voided By,Void Reason',
      );
    for (final row in _data.filteredRows) {
      final createdAt = DateTime.tryParse(
        row['created_at']?.toString() ?? '',
      )?.toLocal();
      final unitCost = (row['cost_price'] as num?)?.toDouble();
      final quantity = (row['quantity'] as num?)?.toInt() ?? 0;
      final total = (row['total'] as num?)?.toDouble() ?? 0;
      buffer.writeln(
        [
          _receiptKey(row, createdAt ?? DateTime.now()),
          row['created_at'],
          row['product_id'],
          row['product_name'],
          row['quantity'],
          row['price'],
          unitCost,
          unitCost == null ? null : total - (unitCost * quantity),
          row['total'],
          _isVoided(row) ? 'Voided' : 'Completed',
          row['voided_by'],
          row['void_reason'],
        ].map(_csvCell).join(','),
      );
    }
    return buffer.toString();
  }

  String _csvCell(Object? value) {
    final escaped = (value ?? '').toString().replaceAll('"', '""');
    return escaped.contains(RegExp(r'[,"\r\n]')) ? '"$escaped"' : escaped;
  }

  String get _rangeLabel {
    final range = _data.range;
    if (_period == _ReportPeriod.today) {
      return 'Today, ${DateFormat('MMM d, yyyy').format(range.start)}';
    }
    return '${DateFormat('MMM d, yyyy').format(range.start)} - '
        '${DateFormat('MMM d, yyyy').format(range.end.subtract(const Duration(days: 1)))}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Column(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
                  child: Row(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: widget.onOpenMenu,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E293B)
                                : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF334155)
                                  : const Color(0xFFE8ECF3),
                            ),
                          ),
                          child: const Icon(Icons.menu_rounded, size: 21),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Reports', style: AppTypography.pageTitle),
                            const SizedBox(height: 2),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        onPressed: _exporting ? null : _showExportSheet,
                        tooltip: 'Export report',
                        style: IconButton.styleFrom(
                          foregroundColor: const Color(0xFF2563EB),
                          side: const BorderSide(color: Color(0xFF93C5FD)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                        icon: _exporting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.download_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF111827) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF243047)
                            : const Color(0xFFE8ECF3),
                      ),
                    ),
                    child: Row(
                      children: _ReportSection.values
                          .map(
                            (section) => Expanded(child: _sectionChip(section)),
                          )
                          .toList(),
                    ),
                  ),
                ),
                if (_refreshingPeriod)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                const SizedBox(height: 8),
              ],
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: () => _loadReports(showFullPageLoader: false),
                      child: _ReportView(
                        data: _data,
                        section: _section,
                        onSelectCustomRange: () =>
                            _selectPeriod(_ReportPeriod.custom),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionChip(_ReportSection section) {
    final selected = _section == section;
    final label = switch (section) {
      _ReportSection.overview => 'Overview',
      _ReportSection.profit => 'Profit',
      _ReportSection.topProducts => 'Products',
      _ReportSection.inventory => 'Inventory',
      _ReportSection.voids => 'Voids',
    };
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _section = section),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2563EB) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.22),
                    blurRadius: 7,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.smallCaption.copyWith(
                    color: selected ? Colors.white : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportView extends StatelessWidget {
  const _ReportView({
    required this.data,
    required this.section,
    required this.onSelectCustomRange,
  });

  final _ReportData data;
  final _ReportSection section;
  final VoidCallback onSelectCustomRange;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: switch (section) {
        _ReportSection.overview => [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _SalesOverviewCard(
              key: ValueKey(
                '${data.periodLabel}-${data.range.start}-${data.range.end}',
              ),
              data: data,
              onSelectCustomRange: onSelectCustomRange,
            ),
          ),
          const SizedBox(height: 16),
          _TrendCard(
            key: const ValueKey('sales-trend'),
            salesPoints: data.trend,
            profitPoints: data.profitTrend,
            period: data.periodLabel,
            allowToggle: false,
          ),
          const SizedBox(height: 16),
          _CategoryCard(revenue: data.categoryRevenue),
        ],
        _ReportSection.profit => [
          _ProfitOverviewCard(
            data: data,
            onSelectCustomRange: onSelectCustomRange,
          ),
          const SizedBox(height: 16),
          _ProfitReconciliationCard(data: data),
          if (data.legacyMissingCostCount > 0) ...[
            const SizedBox(height: 12),
            _LegacyCostWarning(
              count: data.legacyMissingCostCount,
              excludedRevenue: data.excludedRevenue,
            ),
          ],
          const SizedBox(height: 16),
          _TrendCard(
            key: const ValueKey('profit-trend'),
            salesPoints: data.trend,
            profitPoints: data.profitTrend,
            period: data.periodLabel,
            initialShowProfit: true,
            allowToggle: false,
          ),
          const SizedBox(height: 16),
          _ProfitabilityCard(items: data.productProfitability),
        ],
        _ReportSection.topProducts => [
          _ProductHighlights(
            topByQuantity: data.topByQuantity,
            topByRevenue: data.topByRevenue,
          ),
          _InsightPreview(
            title: 'Slow-moving Products',
            subtitle: 'In stock with no sales in this period',
            icon: Icons.hourglass_empty_rounded,
            color: _amber,
            count: data.slowMovers.length,
            preview: _SlowMoverList(items: data.slowMovers.take(3).toList()),
            details: _SlowMoverList(items: data.slowMovers),
          ),
        ],
        _ReportSection.inventory => [_InventoryCard(snapshot: data.inventory)],
        _ReportSection.voids => [_VoidsSection(data: data)],
      },
    );
  }
}

class _VoidsSection extends StatelessWidget {
  const _VoidsSection({required this.data});

  final _ReportData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _VoidMetricCard(
                label: 'Voided Receipts',
                value: '${data.voidedReceipts.length}',
                helper: 'Receipts voided in this period',
                icon: Icons.assignment_return_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _VoidMetricCard(
                label: 'Void Amount',
                value: CurrencyFormatter.format(data.voidedAmount),
                helper: 'Total voided amount',
                icon: Icons.money_off_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Panel(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: _SectionHeader(
                  title: 'Void Audit',
                  subtitle: 'Receipt-level void history for this period',
                  icon: Icons.undo_rounded,
                  color: _red,
                ),
              ),
              _VoidAuditList(items: data.voidedReceipts),
            ],
          ),
        ),
      ],
    );
  }
}

class _VoidMetricCard extends StatelessWidget {
  const _VoidMetricCard({
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
  });

  final String label;
  final String value;
  final String helper;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(minHeight: 132),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFFECACA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: _red),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.cardTitle.copyWith(color: _red),
          ),
          const SizedBox(height: 4),
          Text(label, style: AppTypography.label),
          const SizedBox(height: 3),
          Text(helper, style: AppTypography.smallCaption),
        ],
      ),
    );
  }
}

class _SalesOverviewCard extends StatelessWidget {
  const _SalesOverviewCard({
    super.key,
    required this.data,
    required this.onSelectCustomRange,
  });
  final _ReportData data;
  final VoidCallback onSelectCustomRange;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text('Sales Overview', style: AppTypography.cardTitle),
                ),
                OutlinedButton.icon(
                  onPressed: onSelectCustomRange,
                  icon: const Icon(Icons.calendar_month_outlined, size: 15),
                  label: const Text('Date'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2563EB),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 7,
                    ),
                    visualDensity: VisualDensity.compact,
                    side: const BorderSide(color: Color(0xFFBFDBFE)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 16) / 3;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _OverviewTile(
                    width: width,
                    label: 'Net Sales',
                    value: CurrencyFormatter.format(data.revenue),
                    icon: Icons.payments_outlined,
                    color: _green,
                  ),
                  _OverviewTile(
                    width: width,
                    label: 'Receipts',
                    value: '${data.receipts}',
                    icon: Icons.receipt_long_outlined,
                    color: const Color(0xFF2563EB),
                  ),
                  _OverviewTile(
                    width: width,
                    label: 'Items Sold',
                    value: '${data.itemsSold}',
                    icon: Icons.shopping_bag_outlined,
                    color: const Color(0xFFF97316),
                  ),
                  _OverviewTile(
                    width: width,
                    label: 'Average Sale',
                    value: CurrencyFormatter.format(data.averageSale),
                    icon: Icons.hub_outlined,
                    color: const Color(0xFF8B5CF6),
                  ),
                  _OverviewTile(
                    width: width,
                    label: 'Voids Total',
                    value: '${data.voidedReceipts.length}',
                    icon: Icons.assignment_return_outlined,
                    color: _red,
                  ),
                  _OverviewTile(
                    width: width,
                    label: 'Void Amount',
                    value: CurrencyFormatter.format(data.voidedAmount),
                    icon: Icons.money_off_outlined,
                    color: const Color(0xFFFB7185),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProfitOverviewCard extends StatelessWidget {
  const _ProfitOverviewCard({
    required this.data,
    required this.onSelectCustomRange,
  });

  final _ReportData data;
  final VoidCallback onSelectCustomRange;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profitColor = data.grossProfit < 0 ? _red : _green;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF172033), const Color(0xFF111827)]
              : [const Color(0xFFF0FDF4), Colors.white],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: profitColor.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: profitColor.withValues(alpha: isDark ? 0.08 : 0.1),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gross Profit', style: AppTypography.caption),
                    const SizedBox(height: 5),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        CurrencyFormatter.format(data.grossProfit),
                        style: AppTypography.heroAmount.copyWith(
                          color: profitColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _ProfitMarginChip(
                margin: data.grossMarginPercent,
                color: profitColor,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(
                Icons.calendar_month_outlined,
                size: 16,
                color: Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _profitRangeLabel(data.range),
                  style: AppTypography.caption,
                ),
              ),
              TextButton(
                onPressed: onSelectCustomRange,
                child: const Text('Change date'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _profitRangeLabel(DateTimeRange range) {
  final end = range.end.subtract(const Duration(days: 1));
  if (range.start.year == end.year &&
      range.start.month == end.month &&
      range.start.day == end.day) {
    return DateFormat('MMM d, yyyy').format(range.start);
  }
  return '${DateFormat('MMM d').format(range.start)} - '
      '${DateFormat('MMM d, yyyy').format(end)}';
}

class _ProfitMarginChip extends StatelessWidget {
  const _ProfitMarginChip({required this.margin, required this.color});

  final double margin;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        children: [
          Text(
            '${margin.toStringAsFixed(1)}%',
            style: AppTypography.cardTitle.copyWith(color: color),
          ),
          Text(
            'Margin',
            style: AppTypography.smallCaption.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _ProfitReconciliationCard extends StatelessWidget {
  const _ProfitReconciliationCard({required this.data});

  final _ReportData data;

  @override
  Widget build(BuildContext context) {
    final profitColor = data.grossProfit < 0 ? _red : _green;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Profit Breakdown', style: AppTypography.cardTitle),
          const SizedBox(height: 4),
          Text(
            'How your sales revenue becomes gross profit',
            style: AppTypography.caption,
          ),
          const SizedBox(height: 14),
          _ProfitBreakdownRow(
            label: 'Total Sales Revenue',
            value: data.revenue,
            icon: Icons.payments_outlined,
          ),
          _ProfitBreakdownRow(
            label: 'Profit-covered Sales',
            value: data.coveredRevenue,
            icon: Icons.verified_outlined,
            color: _green,
          ),
          _ProfitBreakdownRow(
            label: 'Excluded Sales',
            value: data.excludedRevenue,
            icon: Icons.info_outline_rounded,
            color: data.excludedRevenue > 0 ? _amber : null,
          ),
          _ProfitBreakdownRow(
            label: 'Cost of Goods Sold',
            value: data.costOfGoodsSold,
            icon: Icons.inventory_2_outlined,
            color: _amber,
          ),
          const Divider(height: 24),
          _ProfitBreakdownRow(
            label: 'Gross Profit',
            value: data.grossProfit,
            icon: Icons.trending_up_rounded,
            color: profitColor,
            emphasized: true,
            bottomPadding: 0,
          ),
        ],
      ),
    );
  }
}

class _ProfitBreakdownRow extends StatelessWidget {
  const _ProfitBreakdownRow({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.emphasized = false,
    this.bottomPadding = 12,
  });

  final String label;
  final double value;
  final IconData icon;
  final Color? color;
  final bool emphasized;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final valueColor = color ?? Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color ?? const Color(0xFF64748B)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: emphasized
                  ? AppTypography.emphasizedBody
                  : AppTypography.body,
            ),
          ),
          Text(
            CurrencyFormatter.format(value),
            style:
                (emphasized
                        ? AppTypography.cardTitle
                        : AppTypography.emphasizedBody)
                    .copyWith(color: valueColor),
          ),
        ],
      ),
    );
  }
}

class _OverviewTile extends StatelessWidget {
  const _OverviewTile({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final valueStyle = value.length >= 11
        ? AppTypography.smallCaption.copyWith(fontWeight: FontWeight.w700)
        : value.length >= 9
        ? AppTypography.label.copyWith(fontWeight: FontWeight.w700)
        : AppTypography.cardTitle;
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF172033) : const Color(0xFFFCFDFE),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: isDark ? const Color(0xFF2B3A52) : const Color(0xFFE8ECF3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.smallCaption,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: valueStyle),
          ),
        ],
      ),
    );
  }
}

class _LegacyCostWarning extends StatelessWidget {
  const _LegacyCostWarning({
    required this.count,
    required this.excludedRevenue,
  });

  final int count;
  final double excludedRevenue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: _amber, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '${CurrencyFormatter.format(excludedRevenue)} from $count older '
              'sale item${count == 1 ? '' : 's'} is excluded from profit. '
              'Historical cost is unavailable, so the app does not estimate it.',
              style: AppTypography.caption,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatefulWidget {
  const _TrendCard({
    super.key,
    required this.salesPoints,
    required this.profitPoints,
    required this.period,
    this.initialShowProfit = false,
    this.allowToggle = true,
  });
  final List<_TrendPoint> salesPoints;
  final List<_TrendPoint> profitPoints;
  final String period;
  final bool initialShowProfit;
  final bool allowToggle;

  @override
  State<_TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<_TrendCard> {
  late bool _showProfit;

  @override
  void initState() {
    super.initState();
    _showProfit = widget.initialShowProfit;
  }

  @override
  Widget build(BuildContext context) {
    final points = _showProfit ? widget.profitPoints : widget.salesPoints;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_showProfit ? 'Profit' : 'Sales'} Trend (${widget.period})',
                  style: AppTypography.cardTitle,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: widget.allowToggle
                          ? () => setState(() => _showProfit = !_showProfit)
                          : null,
                      child: Text(
                        _showProfit ? 'Profit' : 'Sales',
                        style: AppTypography.smallCaption.copyWith(
                          color: const Color(0xFF2563EB),
                        ),
                      ),
                    ),
                    if (widget.allowToggle) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.swap_horiz_rounded, size: 15),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _TrendChart(points: points),
        ],
      ),
    );
  }
}

class _ProductHighlights extends StatefulWidget {
  const _ProductHighlights({
    required this.topByQuantity,
    required this.topByRevenue,
  });

  final List<_ProductAccumulator> topByQuantity;
  final List<_ProductAccumulator> topByRevenue;

  @override
  State<_ProductHighlights> createState() => _ProductHighlightsState();
}

class _ProductHighlightsState extends State<_ProductHighlights> {
  bool _showRevenue = false;

  @override
  Widget build(BuildContext context) {
    final items = _showRevenue ? widget.topByRevenue : widget.topByQuantity;
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionHeader(
                  title: 'Top Products',
                  subtitle: 'Best performers in this period',
                  icon: Icons.emoji_events_outlined,
                  color: _purple,
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFF1F4F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SegmentButton(
                          label: 'By quantity',
                          selected: !_showRevenue,
                          onTap: () => setState(() => _showRevenue = false),
                        ),
                      ),
                      Expanded(
                        child: _SegmentButton(
                          label: 'By revenue',
                          selected: _showRevenue,
                          onTap: () => setState(() => _showRevenue = true),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _ProductList(items: items, showRevenue: _showRevenue),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? (Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF334155)
                    : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppTypography.label.copyWith(color: selected ? _purple : null),
        ),
      ),
    );
  }
}

class _InventoryCard extends StatelessWidget {
  const _InventoryCard({required this.snapshot});
  final _InventorySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final attentionItems = [...snapshot.outOfStock, ...snapshot.lowStock];
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeader(
            title: 'Inventory Snapshot',
            subtitle: 'Current stock levels and estimated cost',
            icon: Icons.inventory_2_outlined,
            color: _green,
          ),
          const SizedBox(height: 14),
          Text(
            'Live inventory status based on your current stock levels.',
            style: AppTypography.caption,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 10.0;
              final tileWidth = (constraints.maxWidth - spacing) / 2;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  _InventoryStatTile(
                    width: tileWidth,
                    label: 'Products in stock',
                    value: '${snapshot.productsInStock}',
                    icon: Icons.inventory_2_outlined,
                    color: _green,
                  ),
                  _InventoryStatTile(
                    width: tileWidth,
                    label: 'Units on hand',
                    value: '${snapshot.unitsOnHand}',
                    icon: Icons.layers_outlined,
                    color: _purple,
                  ),
                  _InventoryStatTile(
                    width: tileWidth,
                    label: 'Low stock',
                    value: '${snapshot.lowStock.length}',
                    icon: Icons.warning_amber_rounded,
                    color: _amber,
                  ),
                  _InventoryStatTile(
                    width: tileWidth,
                    label: 'Out of stock',
                    value: '${snapshot.outOfStock.length}',
                    icon: Icons.error_outline_rounded,
                    color: _red,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _InventoryValueCard(value: snapshot.costValue),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text('Stock attention', style: AppTypography.cardTitle),
              ),
              if (attentionItems.isNotEmpty)
                TextButton(
                  onPressed: () => _showReportDetails(
                    context,
                    title: 'Inventory Attention',
                    subtitle: 'Products that need restocking',
                    child: _InventoryAttentionList(items: attentionItems),
                  ),
                  child: const Text('View all'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (attentionItems.isEmpty)
            const _InventoryHealthyState()
          else
            ...attentionItems
                .take(3)
                .map((item) => _InventoryAttentionRow(item: item)),
        ],
      ),
    );
  }
}

class _InventoryStatTile extends StatelessWidget {
  const _InventoryStatTile({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(value, style: AppTypography.sectionTitle.copyWith(color: color)),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption,
          ),
        ],
      ),
    );
  }
}

class _InventoryValueCard extends StatelessWidget {
  const _InventoryValueCard({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF172033) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF2B3A52) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.account_balance_wallet_outlined,
              color: _green,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Estimated inventory cost', style: AppTypography.caption),
                const SizedBox(height: 3),
                Text(
                  CurrencyFormatter.format(value),
                  style: AppTypography.sectionTitle.copyWith(color: _green),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryAttentionList extends StatelessWidget {
  const _InventoryAttentionList({required this.items});

  final List<_StockItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items
          .map((item) => _InventoryAttentionRow(item: item))
          .toList(),
    );
  }
}

class _InventoryAttentionRow extends StatelessWidget {
  const _InventoryAttentionRow({required this.item});

  final _StockItem item;

  @override
  Widget build(BuildContext context) {
    final isOutOfStock = item.stock <= 0;
    final color = isOutOfStock ? _red : _amber;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(
            isOutOfStock
                ? Icons.error_outline_rounded
                : Icons.warning_amber_rounded,
            color: color,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.emphasizedBody,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            isOutOfStock ? 'Out of stock' : '${item.stock} left',
            style: AppTypography.label.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _InventoryHealthyState extends StatelessWidget {
  const _InventoryHealthyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: _green.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            color: _green,
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Stock levels look healthy. No products need attention.',
              style: AppTypography.caption,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.revenue});
  final Map<String, double> revenue;

  @override
  Widget build(BuildContext context) {
    if (revenue.isEmpty) {
      return const _EmptyPanel(message: 'No category sales in this period');
    }
    final total = revenue.values.fold<double>(0, (sum, value) => sum + value);
    final entries = revenue.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeader(
            title: 'Sales by Category',
            subtitle: 'Revenue contribution by category',
            icon: Icons.pie_chart_outline_rounded,
            color: _purple,
          ),
          const SizedBox(height: 16),
          ...entries.map((entry) {
            final ratio = total == 0 ? 0.0 : entry.value / total;
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(entry.key, style: AppTypography.label),
                      ),
                      Text(
                        '${(ratio * 100).round()}%',
                        style: AppTypography.label.copyWith(color: _purple),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 9,
                      color: _purple,
                      backgroundColor: _purple.withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _InsightPreview extends StatelessWidget {
  const _InsightPreview({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.count,
    required this.preview,
    required this.details,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final int count;
  final Widget preview;
  final Widget details;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: _SectionHeader(
                    title: title,
                    subtitle: subtitle,
                    icon: icon,
                    color: color,
                  ),
                ),
                if (count > 0)
                  TextButton(
                    onPressed: () => _showReportDetails(
                      context,
                      title: title,
                      subtitle: '$count item${count == 1 ? '' : 's'}',
                      child: details,
                    ),
                    child: const Text('View all'),
                  ),
              ],
            ),
          ),
          preview,
        ],
      ),
    );
  }
}

class _ProductList extends StatelessWidget {
  const _ProductList({required this.items, required this.showRevenue});
  final List<_ProductAccumulator> items;
  final bool showRevenue;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _InlineEmpty(message: 'No completed sales in this period');
    }
    return Column(
      children: items.asMap().entries.map((entry) {
        final item = entry.value;
        return _SimpleRow(
          title: '${entry.key + 1}. ${item.name}',
          subtitle: showRevenue
              ? '${item.quantity} units sold'
              : CurrencyFormatter.format(item.revenue),
          trailing: showRevenue
              ? CurrencyFormatter.format(item.revenue)
              : '${item.quantity} units',
        );
      }).toList(),
    );
  }
}

class _ProfitabilityCard extends StatelessWidget {
  const _ProfitabilityCard({required this.items});

  final List<_ProductAccumulator> items;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: _SectionHeader(
              title: 'Product Profitability',
              subtitle: 'All sold products ranked by gross profit',
              icon: Icons.insights_outlined,
              color: _green,
            ),
          ),
          if (items.isEmpty)
            const _InlineEmpty(message: 'No completed sales in this period')
          else
            ...items.map((item) => _ProfitabilityRow(item: item)),
        ],
      ),
    );
  }
}

class _ProfitabilityRow extends StatelessWidget {
  const _ProfitabilityRow({required this.item});

  final _ProductAccumulator item;

  @override
  Widget build(BuildContext context) {
    final profitColor = item.grossProfit < 0 ? _red : _green;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () => _showProductProfitDetails(context, item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: profitColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                item.grossProfit < 0
                    ? Icons.trending_down_rounded
                    : Icons.trending_up_rounded,
                color: profitColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.emphasizedBody,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        '${item.quantity} units sold',
                        style: AppTypography.caption,
                      ),
                      if (item.missingCostItems > 0) ...[
                        const SizedBox(width: 7),
                        const Icon(
                          Icons.info_outline_rounded,
                          color: _amber,
                          size: 14,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  CurrencyFormatter.format(item.grossProfit),
                  style: AppTypography.label.copyWith(color: profitColor),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: profitColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${item.grossMarginPercent.toStringAsFixed(1)}%',
                    style: AppTypography.smallCaption.copyWith(
                      color: profitColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showProductProfitDetails(
  BuildContext context,
  _ProductAccumulator item,
) {
  final profitColor = item.grossProfit < 0 ? _red : _green;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(item.name, style: AppTypography.sectionTitle),
            const SizedBox(height: 3),
            Text('${item.quantity} units sold', style: AppTypography.caption),
            const SizedBox(height: 18),
            _ProductProfitDetailRow(
              label: 'Total Sales Revenue',
              value: CurrencyFormatter.format(item.revenue),
            ),
            _ProductProfitDetailRow(
              label: 'Profit-covered Sales',
              value: CurrencyFormatter.format(item.coveredRevenue),
              valueColor: _green,
            ),
            _ProductProfitDetailRow(
              label: 'Excluded Sales',
              value: CurrencyFormatter.format(item.excludedRevenue),
              valueColor: item.excludedRevenue > 0 ? _amber : null,
            ),
            _ProductProfitDetailRow(
              label: 'Cost of Goods Sold',
              value: CurrencyFormatter.format(item.costOfGoodsSold),
            ),
            const Divider(height: 24),
            _ProductProfitDetailRow(
              label: 'Gross Profit',
              value: CurrencyFormatter.format(item.grossProfit),
              valueColor: profitColor,
              emphasized: true,
            ),
            _ProductProfitDetailRow(
              label: 'Gross Margin',
              value: '${item.grossMarginPercent.toStringAsFixed(1)}%',
              valueColor: profitColor,
              emphasized: true,
            ),
            if (item.missingCostItems > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: _amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${item.missingCostItems} older sale item${item.missingCostItems == 1 ? '' : 's'} '
                  'excluded because historical cost is unavailable.',
                  style: AppTypography.caption,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _ProductProfitDetailRow extends StatelessWidget {
  const _ProductProfitDetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: emphasized
                  ? AppTypography.emphasizedBody
                  : AppTypography.body,
            ),
          ),
          Text(
            value,
            style:
                (emphasized
                        ? AppTypography.cardTitle
                        : AppTypography.emphasizedBody)
                    .copyWith(color: valueColor),
          ),
        ],
      ),
    );
  }
}

class _SlowMoverList extends StatelessWidget {
  const _SlowMoverList({required this.items});
  final List<_SlowMover> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _InlineEmpty(
        message: 'Every in-stock product sold during this period',
      );
    }
    return Column(
      children: items
          .map(
            (item) => _SimpleRow(
              title: item.name,
              subtitle: 'No sales in selected period',
              trailing: '${item.stock} in stock',
            ),
          )
          .toList(),
    );
  }
}

class _VoidAuditList extends StatelessWidget {
  const _VoidAuditList({required this.items});
  final List<_VoidAudit> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _InlineEmpty(message: 'No voided receipts in this period');
    }
    return Column(
      children: items.map((item) {
        final detail = [
          DateFormat('MMM d, yyyy h:mm a').format(item.voidedAt),
          'By ${item.voidedBy}',
          if (item.reason.isNotEmpty) item.reason,
        ].join(' | ');
        return _SimpleRow(
          title: item.receiptNumber,
          subtitle: detail,
          trailing: CurrencyFormatter.format(item.total),
          trailingColor: _red,
        );
      }).toList(),
    );
  }
}

class _SimpleRow extends StatelessWidget {
  const _SimpleRow({
    required this.title,
    required this.trailing,
    this.subtitle,
    this.trailingColor,
  });
  final String title;
  final String? subtitle;
  final String trailing;
  final Color? trailingColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.emphasizedBody,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            trailing,
            style: AppTypography.label.copyWith(color: trailingColor),
          ),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points});
  final List<_TrendPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.every((point) => point.value == 0)) {
      return const SizedBox(
        height: 130,
        child: Center(child: Text('No completed sales in this period')),
      );
    }
    return SizedBox(
      height: 190,
      child: CustomPaint(
        painter: _TrendPainter(
          points: points,
          isDark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.points, required this.isDark});
  final List<_TrendPoint> points;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 38.0;
    const right = 6.0;
    const top = 8.0;
    const bottom = 28.0;
    final width = size.width - left - right;
    final height = size.height - top - bottom;
    final values = points.map((point) => point.value);
    final maxValue = values.fold<double>(0, max);
    final minValue = values.fold<double>(0, min);
    final valueRange = maxValue - minValue;
    double yFor(double value) =>
        top +
        height -
        (valueRange == 0 ? 0 : (value - minValue) / valueRange * height);
    final zeroY = yFor(0);
    final axis = Paint()
      ..color = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final grid = Paint()
      ..color = isDark ? const Color(0xFF28364D) : const Color(0xFFE8EDF4)
      ..strokeWidth = 1;
    final line = Paint()
      ..color = const Color(0xFF2563EB)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final point = Paint()
      ..color = isDark ? const Color(0xFF111827) : Colors.white
      ..style = PaintingStyle.fill;
    final pointBorder = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF2563EB).withValues(alpha: 0.12),
          const Color(0xFF2563EB).withValues(alpha: 0.01),
        ],
      ).createShader(Rect.fromLTWH(left, top, width, height));
    final labelStyle = TextStyle(
      color: isDark ? Colors.white60 : Colors.black54,
      fontSize: 9,
    );
    for (var index = 0; index <= 4; index++) {
      final y = top + height * index / 4;
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), grid);
      final value = maxValue - valueRange * index / 4;
      final painter = TextPainter(
        text: TextSpan(text: _compactMoney(value), style: labelStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(0, y - painter.height / 2));
    }
    canvas.drawLine(
      Offset(left, zeroY),
      Offset(size.width - right, zeroY),
      axis,
    );
    final path = Path();
    final fillPath = Path();
    final offsets = <Offset>[];
    for (var index = 0; index < points.length; index++) {
      final x =
          left +
          (points.length == 1
              ? width / 2
              : width * index / (points.length - 1));
      final y = yFor(points[index].value);
      offsets.add(Offset(x, y));
      if (index == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, zeroY);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath
      ..lineTo(size.width, zeroY)
      ..close();
    canvas.drawPath(fillPath, fill);
    canvas.drawPath(path, line);
    for (final offset in offsets) {
      canvas.drawCircle(offset, 2.8, point);
      canvas.drawCircle(offset, 2.8, pointBorder);
    }
    final step = max(1, (points.length / 5).ceil());
    for (var index = 0; index < points.length; index += step) {
      final x =
          left +
          (points.length == 1
              ? width / 2
              : width * index / (points.length - 1));
      final painter = TextPainter(
        text: TextSpan(text: points[index].label, style: labelStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          (x - painter.width / 2).clamp(left, size.width - painter.width),
          top + height + 8,
        ),
      );
    }
  }

  String _compactMoney(double value) {
    if (value >= 1000) {
      final compact = value / 1000;
      return 'P${compact.toStringAsFixed(compact >= 10 ? 0 : 1)}K';
    }
    return 'P${value.toStringAsFixed(0)}';
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.isDark != isDark;
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF243047) : const Color(0xFFE8ECF3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.caption,
          ),
        ),
      ),
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white38
                : Colors.black38,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: AppTypography.caption)),
        ],
      ),
    );
  }
}

Future<void> _showReportDetails(
  BuildContext context, {
  required String title,
  required String subtitle,
  required Widget child,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.78,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.sectionTitle),
                  const SizedBox(height: 3),
                  Text(subtitle, style: AppTypography.caption),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: child,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.color,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: color, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.cardTitle),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: AppTypography.caption),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ReportData {
  _ReportData({
    required this.range,
    required this.filteredRows,
    required this.revenue,
    required this.coveredRevenue,
    required this.costOfGoodsSold,
    required this.productDiscountTotal,
    required this.legacyMissingCostCount,
    required this.receipts,
    required this.itemsSold,
    required this.voidedAmount,
    required this.voidedReceipts,
    required this.topByQuantity,
    required this.topByRevenue,
    required this.productProfitability,
    required this.categoryRevenue,
    required this.trend,
    required this.profitTrend,
    required this.inventory,
    required this.slowMovers,
    required this.periodLabel,
  });

  factory _ReportData.empty() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _ReportData(
      range: DateTimeRange(
        start: today,
        end: today.add(const Duration(days: 1)),
      ),
      filteredRows: const [],
      revenue: 0,
      coveredRevenue: 0,
      costOfGoodsSold: 0,
      productDiscountTotal: 0,
      legacyMissingCostCount: 0,
      receipts: 0,
      itemsSold: 0,
      voidedAmount: 0,
      voidedReceipts: const [],
      topByQuantity: const [],
      topByRevenue: const [],
      productProfitability: const [],
      categoryRevenue: const {},
      trend: const [],
      profitTrend: const [],
      inventory: const _InventorySnapshot.empty(),
      slowMovers: const [],
      periodLabel: 'Today',
    );
  }

  final DateTimeRange range;
  final List<Map<String, Object?>> filteredRows;
  final double revenue;
  final double coveredRevenue;
  final double costOfGoodsSold;
  final double productDiscountTotal;
  final int legacyMissingCostCount;
  final int receipts;
  final int itemsSold;
  final double voidedAmount;
  final List<_VoidAudit> voidedReceipts;
  final List<_ProductAccumulator> topByQuantity;
  final List<_ProductAccumulator> topByRevenue;
  final List<_ProductAccumulator> productProfitability;
  final Map<String, double> categoryRevenue;
  final List<_TrendPoint> trend;
  final List<_TrendPoint> profitTrend;
  final _InventorySnapshot inventory;
  final List<_SlowMover> slowMovers;
  final String periodLabel;

  double get averageSale => receipts == 0 ? 0 : revenue / receipts;
  double get excludedRevenue => profit_margin.excludedRevenue(
    totalRevenue: revenue,
    coveredRevenue: coveredRevenue,
  );
  double get grossProfit => profit_margin.grossProfit(
    coveredRevenue: coveredRevenue,
    costOfGoodsSold: costOfGoodsSold,
  );
  double get grossMarginPercent => profit_margin.grossMarginPercent(
    coveredRevenue: coveredRevenue,
    costOfGoodsSold: costOfGoodsSold,
  );
}

class _ReceiptAccumulator {
  _ReceiptAccumulator({required this.receiptNumber});
  final String receiptNumber;
  double total = 0;
  double discount = 0;
  double costOfGoodsSold = 0;
  int quantity = 0;
  int missingCostItems = 0;
  bool isVoided = false;
  DateTime? createdAt;
  DateTime voidedAt = DateTime.fromMillisecondsSinceEpoch(0);
  String voidedBy = 'Unknown';
  String reason = '';

  void add(Map<String, Object?> row, DateTime rowCreatedAt) {
    createdAt ??= rowCreatedAt;
    final lineTotal = (row['total'] as num?)?.toDouble() ?? 0;
    final lineQuantity = (row['quantity'] as num?)?.toInt() ?? 0;
    total += lineTotal;
    quantity += lineQuantity;
    final rowDiscount =
        (row['receipt_discount_amount'] as num?)?.toDouble() ?? 0;
    if (rowDiscount.isFinite && rowDiscount > discount) {
      discount = rowDiscount;
    }
    final costPrice = (row['cost_price'] as num?)?.toDouble();
    if (costPrice == null) {
      missingCostItems++;
    } else {
      costOfGoodsSold += costPrice * lineQuantity;
    }
    if (_isVoided(row)) {
      isVoided = true;
      final parsed = DateTime.tryParse(
        row['voided_at']?.toString() ?? '',
      )?.toLocal();
      if (parsed != null && parsed.isAfter(voidedAt)) voidedAt = parsed;
      final user = row['voided_by']?.toString().trim();
      if (user != null && user.isNotEmpty) voidedBy = user;
      final value = row['void_reason']?.toString().trim();
      if (value != null && value.isNotEmpty) reason = value;
    }
  }

  double get netTotal => (total - discount.clamp(0, total)).clamp(0, total);

  double get grossProfit => profit_margin.grossProfit(
    coveredRevenue: netTotal,
    costOfGoodsSold: costOfGoodsSold,
  );

  _VoidAudit toVoidAudit() => _VoidAudit(
    receiptNumber: receiptNumber,
    voidedAt: voidedAt,
    total: netTotal,
    voidedBy: voidedBy,
    reason: reason,
  );
}

class _ProductAccumulator {
  _ProductAccumulator({required this.name});
  final String name;
  int quantity = 0;
  double revenue = 0;
  double coveredRevenue = 0;
  double costOfGoodsSold = 0;
  int missingCostItems = 0;

  void add(Map<String, Object?> row) {
    final lineQuantity = (row['quantity'] as num?)?.toInt() ?? 0;
    final lineRevenue = (row['total'] as num?)?.toDouble() ?? 0;
    final costPrice = (row['cost_price'] as num?)?.toDouble();
    quantity += lineQuantity;
    revenue += lineRevenue;
    if (costPrice == null) {
      missingCostItems++;
    } else {
      coveredRevenue += lineRevenue;
      costOfGoodsSold += costPrice * lineQuantity;
    }
  }

  double get grossProfit => profit_margin.grossProfit(
    coveredRevenue: coveredRevenue,
    costOfGoodsSold: costOfGoodsSold,
  );
  double get grossMarginPercent => profit_margin.grossMarginPercent(
    coveredRevenue: coveredRevenue,
    costOfGoodsSold: costOfGoodsSold,
  );
  double get excludedRevenue => profit_margin.excludedRevenue(
    totalRevenue: revenue,
    coveredRevenue: coveredRevenue,
  );
}

class _VoidAudit {
  const _VoidAudit({
    required this.receiptNumber,
    required this.voidedAt,
    required this.total,
    required this.voidedBy,
    required this.reason,
  });
  final String receiptNumber;
  final DateTime voidedAt;
  final double total;
  final String voidedBy;
  final String reason;
}

class _TrendPoint {
  const _TrendPoint({required this.label, required this.value});
  final String label;
  final double value;
}

class _StockItem {
  const _StockItem({required this.name, required this.stock});
  final String name;
  final int stock;
}

class _InventorySnapshot {
  const _InventorySnapshot({
    required this.productsInStock,
    required this.unitsOnHand,
    required this.costValue,
    required this.lowStock,
    required this.outOfStock,
  });
  const _InventorySnapshot.empty()
    : productsInStock = 0,
      unitsOnHand = 0,
      costValue = 0,
      lowStock = const [],
      outOfStock = const [];

  factory _InventorySnapshot.fromProducts(List<Map<String, Object?>> products) {
    var productsInStock = 0;
    var unitsOnHand = 0;
    var costValue = 0.0;
    final lowStock = <_StockItem>[];
    final outOfStock = <_StockItem>[];
    for (final product in products) {
      final name = product['product_name']?.toString() ?? 'Unknown product';
      final stock = (product['stock_quantity'] as num?)?.toInt() ?? 0;
      final cost = (product['cost_price'] as num?)?.toDouble() ?? 0;
      if (stock > 0) productsInStock++;
      unitsOnHand += max(stock, 0);
      costValue += max(stock, 0) * cost;
      if (stock <= 0) {
        outOfStock.add(_StockItem(name: name, stock: stock));
      } else if (stock <= _lowStockThreshold) {
        lowStock.add(_StockItem(name: name, stock: stock));
      }
    }
    lowStock.sort((a, b) => a.stock.compareTo(b.stock));
    outOfStock.sort((a, b) => a.name.compareTo(b.name));
    return _InventorySnapshot(
      productsInStock: productsInStock,
      unitsOnHand: unitsOnHand,
      costValue: costValue,
      lowStock: lowStock,
      outOfStock: outOfStock,
    );
  }

  final int productsInStock;
  final int unitsOnHand;
  final double costValue;
  final List<_StockItem> lowStock;
  final List<_StockItem> outOfStock;
}

class _SlowMover {
  const _SlowMover({required this.name, required this.stock});
  factory _SlowMover.fromProduct(Map<String, Object?> product) => _SlowMover(
    name: product['product_name']?.toString() ?? 'Unknown product',
    stock: (product['stock_quantity'] as num?)?.toInt() ?? 0,
  );
  final String name;
  final int stock;
}

bool _isVoided(Map<String, Object?> row) =>
    (row['voided_at']?.toString() ?? '').isNotEmpty;

String _receiptKey(Map<String, Object?> row, DateTime createdAt) {
  final receipt = row['receipt_number']?.toString().trim();
  if (receipt != null && receipt.isNotEmpty) return receipt;
  return 'LEGACY-${DateFormat('yyyyMMdd-HHmmss').format(createdAt)}';
}
