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
import 'package:sqflite_sqlcipher/sqflite.dart';

const _purple = Color(0xFF667EEA);
const _green = Color(0xFF10B981);
const _amber = Color(0xFFF59E0B);
const _red = Color(0xFFEF4444);
const _lowStockThreshold = 10;

enum _ReportPeriod { today, custom }

enum _ReportSection { overview, topProducts, inventory, voids }

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
      receipt.add(row);

      if (_isVoided(row)) continue;
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
      final trendKey = _period == _ReportPeriod.today
          ? DateTime(
              createdAt.year,
              createdAt.month,
              createdAt.day,
              createdAt.hour,
            )
          : DateTime(createdAt.year, createdAt.month, createdAt.day);
      trendRevenue[trendKey] = (trendRevenue[trendKey] ?? 0) + total;
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
      revenue: completedReceipts.fold(0, (sum, receipt) => sum + receipt.total),
      receipts: completedReceipts.length,
      itemsSold: completedReceipts.fold(
        0,
        (sum, receipt) => sum + receipt.quantity,
      ),
      voidedAmount: voidedReceipts.fold(
        0,
        (sum, receipt) => sum + receipt.total,
      ),
      voidedReceipts: voidedReceipts
          .map((receipt) => receipt.toVoidAudit())
          .toList(),
      topByQuantity: topByQuantity.take(5).toList(),
      topByRevenue: topByRevenue.take(5).toList(),
      categoryRevenue: categoryRevenue,
      trend: _buildTrend(range, trendRevenue),
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
        'Receipt Number,Date,Product ID,Product Name,Quantity,Unit Price,Total,Status,Voided By,Void Reason',
      );
    for (final row in _data.filteredRows) {
      final createdAt = DateTime.tryParse(
        row['created_at']?.toString() ?? '',
      )?.toLocal();
      buffer.writeln(
        [
          _receiptKey(row, createdAt ?? DateTime.now()),
          row['created_at'],
          row['product_id'],
          row['product_name'],
          row['quantity'],
          row['price'],
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
          _TrendCard(points: data.trend, period: data.periodLabel),
          const SizedBox(height: 16),
          _CategoryCard(revenue: data.categoryRevenue),
        ],
        _ReportSection.topProducts => [
          _ProductHighlights(
            topByQuantity: data.topByQuantity,
            topByRevenue: data.topByRevenue,
          ),
          const SizedBox(height: 16),
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

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.points, required this.period});
  final List<_TrendPoint> points;
  final String period;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sales Trend ($period)',
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
                    Text(
                      period == 'Today' ? 'Hourly' : 'Daily',
                      style: AppTypography.smallCaption,
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down, size: 15),
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
            'Current values, not historical stock levels.',
            style: AppTypography.caption,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _CompactStat(
                label: 'Products in stock',
                value: '${snapshot.productsInStock}',
              ),
              _CompactStat(
                label: 'Units on hand',
                value: '${snapshot.unitsOnHand}',
              ),
              _CompactStat(
                label: 'Low stock',
                value: '${snapshot.lowStock.length}',
                color: _amber,
              ),
              _CompactStat(
                label: 'Out of stock',
                value: '${snapshot.outOfStock.length}',
                color: _red,
              ),
            ],
          ),
          const Divider(height: 28),
          Text('Estimated inventory cost value', style: AppTypography.caption),
          const SizedBox(height: 3),
          Text(
            CurrencyFormatter.format(snapshot.costValue),
            style: AppTypography.primaryAmount.copyWith(color: _green),
          ),
          if (snapshot.lowStock.isNotEmpty ||
              snapshot.outOfStock.isNotEmpty) ...[
            const Divider(height: 28),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Needs attention',
                    style: AppTypography.cardTitle,
                  ),
                ),
                TextButton(
                  onPressed: () => _showReportDetails(
                    context,
                    title: 'Inventory Attention',
                    subtitle: 'Low-stock and out-of-stock products',
                    child: _Panel(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [...snapshot.outOfStock, ...snapshot.lowStock]
                            .map(
                              (item) => _SimpleRow(
                                title: item.name,
                                trailing: item.stock == 0
                                    ? 'Out of stock'
                                    : '${item.stock} left',
                                trailingColor: item.stock == 0 ? _red : _amber,
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                  child: const Text('View all'),
                ),
              ],
            ),
            const SizedBox(height: 2),
            ...[...snapshot.outOfStock, ...snapshot.lowStock]
                .take(3)
                .map(
                  (item) => _SimpleRow(
                    title: item.name,
                    trailing: item.stock == 0
                        ? 'Out of stock'
                        : '${item.stock} left',
                    trailingColor: item.stock == 0 ? _red : _amber,
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _CompactStat extends StatelessWidget {
  const _CompactStat({
    required this.label,
    required this.value,
    this.color = _purple,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AppTypography.sectionTitle.copyWith(color: color)),
          Text(label, style: AppTypography.caption),
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
    final maxValue = points.map((point) => point.value).fold<double>(0, max);
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
      final value = maxValue * (4 - index) / 4;
      final painter = TextPainter(
        text: TextSpan(text: _compactMoney(value), style: labelStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(0, y - painter.height / 2));
    }
    canvas.drawLine(
      Offset(left, top + height),
      Offset(size.width - right, top + height),
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
      final y =
          top +
          height -
          (maxValue == 0 ? 0 : points[index].value / maxValue * height);
      offsets.add(Offset(x, y));
      if (index == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, top + height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath
      ..lineTo(size.width, top + height)
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
    required this.receipts,
    required this.itemsSold,
    required this.voidedAmount,
    required this.voidedReceipts,
    required this.topByQuantity,
    required this.topByRevenue,
    required this.categoryRevenue,
    required this.trend,
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
      receipts: 0,
      itemsSold: 0,
      voidedAmount: 0,
      voidedReceipts: const [],
      topByQuantity: const [],
      topByRevenue: const [],
      categoryRevenue: const {},
      trend: const [],
      inventory: const _InventorySnapshot.empty(),
      slowMovers: const [],
      periodLabel: 'Today',
    );
  }

  final DateTimeRange range;
  final List<Map<String, Object?>> filteredRows;
  final double revenue;
  final int receipts;
  final int itemsSold;
  final double voidedAmount;
  final List<_VoidAudit> voidedReceipts;
  final List<_ProductAccumulator> topByQuantity;
  final List<_ProductAccumulator> topByRevenue;
  final Map<String, double> categoryRevenue;
  final List<_TrendPoint> trend;
  final _InventorySnapshot inventory;
  final List<_SlowMover> slowMovers;
  final String periodLabel;

  double get averageSale => receipts == 0 ? 0 : revenue / receipts;
}

class _ReceiptAccumulator {
  _ReceiptAccumulator({required this.receiptNumber});
  final String receiptNumber;
  double total = 0;
  int quantity = 0;
  bool isVoided = false;
  DateTime voidedAt = DateTime.fromMillisecondsSinceEpoch(0);
  String voidedBy = 'Unknown';
  String reason = '';

  void add(Map<String, Object?> row) {
    total += (row['total'] as num?)?.toDouble() ?? 0;
    quantity += (row['quantity'] as num?)?.toInt() ?? 0;
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

  _VoidAudit toVoidAudit() => _VoidAudit(
    receiptNumber: receiptNumber,
    voidedAt: voidedAt,
    total: total,
    voidedBy: voidedBy,
    reason: reason,
  );
}

class _ProductAccumulator {
  _ProductAccumulator({required this.name});
  final String name;
  int quantity = 0;
  double revenue = 0;

  void add(Map<String, Object?> row) {
    quantity += (row['quantity'] as num?)?.toInt() ?? 0;
    revenue += (row['total'] as num?)?.toDouble() ?? 0;
  }
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
