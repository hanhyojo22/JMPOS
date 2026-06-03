class ReceiptDiscountPreset {
  const ReceiptDiscountPreset({
    this.id,
    required this.name,
    required this.percent,
    this.enabled = true,
    this.sortOrder = 0,
  });

  final int? id;
  final String name;
  final double percent;
  final bool enabled;
  final int sortOrder;

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'percent': percent,
      'enabled': enabled ? 1 : 0,
      'sort_order': sortOrder,
    };
  }

  static ReceiptDiscountPreset fromMap(Map<String, Object?> row) {
    return ReceiptDiscountPreset(
      id: (row['id'] as num?)?.toInt(),
      name: row['name']?.toString() ?? '',
      percent: (row['percent'] as num?)?.toDouble() ?? 0,
      enabled: ((row['enabled'] as num?)?.toInt() ?? 1) == 1,
      sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}
