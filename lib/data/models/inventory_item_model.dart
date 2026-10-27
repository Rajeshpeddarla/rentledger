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

  // Local helper (dynamic)
  final int activeLeasesCount;

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
    this.activeLeasesCount = 0,
  });

  int get availableQuantity {
    final available = totalQuantity - activeLeasesCount;
    return available < 0 ? 0 : available;
  }

  bool get isAvailable => availableQuantity > 0;

  String get shortId => id.length > 6 ? id.substring(0, 6).toUpperCase() : id.toUpperCase();
  String get displaySku => sku.isNotEmpty ? sku : 'SKU: #$shortId';

  factory InventoryItemModel.fromJson(Map<String, dynamic> json) {
    return InventoryItemModel(
      id: json['id'] as String,
      storeId: json['store_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      imageR2Url: json['image_r2_url'] as String?,
      depositAmount: (json['deposit_amount'] as num?)?.toDouble() ?? 0.0,
      rateHourly: (json['rate_hourly'] as num?)?.toDouble() ?? 0.0,
      rateDaily: (json['rate_daily'] as num?)?.toDouble() ?? 0.0,
      rateWeekly: (json['rate_weekly'] as num?)?.toDouble() ?? 0.0,
      rateMonthly: (json['rate_monthly'] as num?)?.toDouble() ?? 0.0,
      totalQuantity: json['total_quantity'] as int? ?? 1,
      isArchived: json['is_archived'] as bool? ?? false,
      category: json['category'] as String? ?? 'General',
      sku: json['sku'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      activeLeasesCount: json['active_leases_count'] as int? ?? 0,
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
    };
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
    int? activeLeasesCount,
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
      activeLeasesCount: activeLeasesCount ?? this.activeLeasesCount,
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
        activeLeasesCount,
      ];
}
