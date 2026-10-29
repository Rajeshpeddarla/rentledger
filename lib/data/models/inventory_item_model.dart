import 'package:equatable/equatable.dart';

class InventoryItemModel extends Equatable {
  final String id;
  final String storeId;
  final String name;
  final String? description;
  final String? imageR2Url;
  final double depositAmount;
  final double rateHourly;
  final double rateDaily;
  final double rateWeekly;
  final double rateMonthly;
  final int totalQuantity;
  final bool isArchived;
  final String category;
  final String sku;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Equipment Tax Configuration Fields
  final String taxType; // 'GST', 'VAT', 'Sales Tax', 'Other', 'No Tax'
  final double taxRate; // e.g. 18.0 (%)
  final bool isTaxInclusive; // false = add tax on top, true = price includes tax
  final DateTime? taxEffectiveDate;
  final DateTime? taxLastVerifiedDate;
  final bool isTaxConfirmed;

  // Explicit Stock State Counts
  final int activeLeasesCount; // Leased out
  final int awaitingInspectionCount; // Returned but awaiting inspection
  final int maintenanceCount; // Damaged / under repair
  final int reservedCount; // Reserved for future confirmed bookings
  final int lostCount; // Lost / destroyed needing restock

  const InventoryItemModel({
    required this.id,
    required this.storeId,
    required this.name,
    this.description,
    this.imageR2Url,
    this.depositAmount = 0.0,
    this.rateHourly = 0.0,
    this.rateDaily = 0.0,
    this.rateWeekly = 0.0,
    this.rateMonthly = 0.0,
    this.totalQuantity = 1,
    this.isArchived = false,
    this.category = 'General',
    this.sku = '',
    required this.createdAt,
    required this.updatedAt,
    this.taxType = 'No Tax',
    this.taxRate = 0.0,
    this.isTaxInclusive = false,
    this.taxEffectiveDate,
    this.taxLastVerifiedDate,
    this.isTaxConfirmed = true,
    this.activeLeasesCount = 0,
    this.awaitingInspectionCount = 0,
    this.maintenanceCount = 0,
    this.reservedCount = 0,
    this.lostCount = 0,
  });

  /// Stock Calculation Formula:
  /// Available stock = Total stock - Leased - AwaitingInspection - Maintenance - Reserved - Lost
  int get availableQuantity {
    final available = totalQuantity -
        activeLeasesCount -
        awaitingInspectionCount -
        maintenanceCount -
        reservedCount -
        lostCount;
    return available < 0 ? 0 : available;
  }

  bool get isAvailable => availableQuantity > 0;

  bool get isTaxable => taxType != 'No Tax' && taxRate > 0;

  String get shortId => id.length > 6 ? id.substring(0, 6).toUpperCase() : id.toUpperCase();
  String get displaySku => sku.isNotEmpty ? sku : 'SKU: #$shortId';

  factory InventoryItemModel.fromJson(Map<String, dynamic> json) {
    return InventoryItemModel(
      id: json['id'] as String,
      storeId: json['store_id'] as String? ?? json['storeId'] as String? ?? 'demo_store_1',
      name: json['name'] as String? ?? 'Equipment Item',
      description: json['description'] as String?,
      imageR2Url: json['image_r2_url'] as String?,
      depositAmount: (json['deposit_amount'] as num?)?.toDouble() ?? 0.0,
      rateHourly: (json['rate_hourly'] as num?)?.toDouble() ?? 0.0,
      rateDaily: (json['rate_daily'] as num?)?.toDouble() ?? 0.0,
      rateWeekly: (json['rate_weekly'] as num?)?.toDouble() ?? 0.0,
      rateMonthly: (json['rate_monthly'] as num?)?.toDouble() ?? 0.0,
      totalQuantity: (json['total_quantity'] as num?)?.toInt() ?? 1,
      isArchived: json['is_archived'] as bool? ?? false,
      category: json['category'] as String? ?? 'General',
      sku: json['sku'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      taxType: json['tax_type'] as String? ?? 'No Tax',
      taxRate: (json['tax_rate'] as num?)?.toDouble() ?? 0.0,
      isTaxInclusive: json['is_tax_inclusive'] as bool? ?? false,
      taxEffectiveDate: json['tax_effective_date'] != null
          ? DateTime.tryParse(json['tax_effective_date'] as String)
          : null,
      taxLastVerifiedDate: json['tax_last_verified_date'] != null
          ? DateTime.tryParse(json['tax_last_verified_date'] as String)
          : null,
      isTaxConfirmed: json['is_tax_confirmed'] as bool? ?? true,
      activeLeasesCount: (json['active_leases_count'] as num?)?.toInt() ?? 0,
      awaitingInspectionCount: (json['awaiting_inspection_count'] as num?)?.toInt() ?? 0,
      maintenanceCount: (json['maintenance_count'] as num?)?.toInt() ?? 0,
      reservedCount: (json['reserved_count'] as num?)?.toInt() ?? 0,
      lostCount: (json['lost_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'store_id': storeId,
      'name': name,
      'description': description,
      'image_r2_url': imageR2Url,
      'deposit_amount': depositAmount,
      'rate_hourly': rateHourly,
      'rate_daily': rateDaily,
      'rate_weekly': rateWeekly,
      'rate_monthly': rateMonthly,
      'total_quantity': totalQuantity,
      'is_archived': isArchived,
      'category': category,
      'sku': sku,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'tax_type': taxType,
      'tax_rate': taxRate,
      'is_tax_inclusive': isTaxInclusive,
      'tax_effective_date': taxEffectiveDate?.toIso8601String(),
      'tax_last_verified_date': taxLastVerifiedDate?.toIso8601String(),
      'is_tax_confirmed': isTaxConfirmed,
      'active_leases_count': activeLeasesCount,
      'awaiting_inspection_count': awaitingInspectionCount,
      'maintenance_count': maintenanceCount,
      'reserved_count': reservedCount,
      'lost_count': lostCount,
    };
  }

  Map<String, dynamic> toDatabaseJson() {
    final map = Map<String, dynamic>.from(toJson());
    map.remove('active_leases_count');
    return map;
  }

  InventoryItemModel copyWith({
    String? id,
    String? storeId,
    String? name,
    String? description,
    String? imageR2Url,
    double? depositAmount,
    double? rateHourly,
    double? rateDaily,
    double? rateWeekly,
    double? rateMonthly,
    int? totalQuantity,
    bool? isArchived,
    String? category,
    String? sku,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? taxType,
    double? taxRate,
    bool? isTaxInclusive,
    DateTime? taxEffectiveDate,
    DateTime? taxLastVerifiedDate,
    bool? isTaxConfirmed,
    int? activeLeasesCount,
    int? awaitingInspectionCount,
    int? maintenanceCount,
    int? reservedCount,
    int? lostCount,
  }) {
    return InventoryItemModel(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      name: name ?? this.name,
      description: description ?? this.description,
      imageR2Url: imageR2Url ?? this.imageR2Url,
      depositAmount: depositAmount ?? this.depositAmount,
      rateHourly: rateHourly ?? this.rateHourly,
      rateDaily: rateDaily ?? this.rateDaily,
      rateWeekly: rateWeekly ?? this.rateWeekly,
      rateMonthly: rateMonthly ?? this.rateMonthly,
      totalQuantity: totalQuantity ?? this.totalQuantity,
      isArchived: isArchived ?? this.isArchived,
      category: category ?? this.category,
      sku: sku ?? this.sku,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      taxType: taxType ?? this.taxType,
      taxRate: taxRate ?? this.taxRate,
      isTaxInclusive: isTaxInclusive ?? this.isTaxInclusive,
      taxEffectiveDate: taxEffectiveDate ?? this.taxEffectiveDate,
      taxLastVerifiedDate: taxLastVerifiedDate ?? this.taxLastVerifiedDate,
      isTaxConfirmed: isTaxConfirmed ?? this.isTaxConfirmed,
      activeLeasesCount: activeLeasesCount ?? this.activeLeasesCount,
      awaitingInspectionCount: awaitingInspectionCount ?? this.awaitingInspectionCount,
      maintenanceCount: maintenanceCount ?? this.maintenanceCount,
      reservedCount: reservedCount ?? this.reservedCount,
      lostCount: lostCount ?? this.lostCount,
    );
  }

  @override
  List<Object?> get props => [
        id,
        storeId,
        name,
        description,
        imageR2Url,
        depositAmount,
        rateHourly,
        rateDaily,
        rateWeekly,
        rateMonthly,
        totalQuantity,
        isArchived,
        category,
        sku,
        createdAt,
        updatedAt,
        taxType,
        taxRate,
        isTaxInclusive,
        taxEffectiveDate,
        taxLastVerifiedDate,
        isTaxConfirmed,
        activeLeasesCount,
        awaitingInspectionCount,
        maintenanceCount,
        reservedCount,
        lostCount,
      ];
}
