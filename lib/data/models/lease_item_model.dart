import 'package:equatable/equatable.dart';
import 'inventory_item_model.dart';
import 'leased_sub_item_model.dart';

class LeaseItemModel extends Equatable {
  final String id;
  final String leaseId;
  final String storeId;
  final String itemId;
  final int quantity;

  // Locked Historical Base Rates (Preserved at time of lease creation)
  final double rateHourly;
  final double rateDaily;
  final double rateWeekly;
  final double rateMonthly;

  // Optional Negotiated Discounted Rates per line item
  final double discountedRateHourly;
  final double discountedRateDaily;
  final double discountedRateWeekly;
  final double discountedRateMonthly;

  final double depositAmount;
  final double lineCalculatedRent;

  final String returnStatus; // 'available', 'awaiting_inspection', 'maintenance', 'lost'
  final List<String> subItemIds;

  final DateTime createdAt;
  final DateTime updatedAt;

  // Embedded relation for UI consumption
  final InventoryItemModel? item;
  final List<LeasedSubItemModel> leasedSubItems;

  const LeaseItemModel({
    required this.id,
    required this.leaseId,
    required this.storeId,
    required this.itemId,
    this.quantity = 1,
    this.rateHourly = 0.0,
    this.rateDaily = 0.0,
    this.rateWeekly = 0.0,
    this.rateMonthly = 0.0,
    this.discountedRateHourly = 0.0,
    this.discountedRateDaily = 0.0,
    this.discountedRateWeekly = 0.0,
    this.discountedRateMonthly = 0.0,
    this.depositAmount = 0.0,
    this.lineCalculatedRent = 0.0,
    this.returnStatus = 'available',
    this.subItemIds = const [],
    required this.createdAt,
    required this.updatedAt,
    this.item,
    this.leasedSubItems = const [],
  });

  // Effective rates used for rent calculations
  double get effectiveRateHourly => discountedRateHourly > 0 ? discountedRateHourly : rateHourly;
  double get effectiveRateDaily => discountedRateDaily > 0 ? discountedRateDaily : rateDaily;
  double get effectiveRateWeekly => discountedRateWeekly > 0 ? discountedRateWeekly : rateWeekly;
  double get effectiveRateMonthly => discountedRateMonthly > 0 ? discountedRateMonthly : rateMonthly;

  factory LeaseItemModel.fromJson(Map<String, dynamic> json) {
    List<String> subItems = [];
    if (json['sub_item_ids'] != null && json['sub_item_ids'] is List) {
      subItems = (json['sub_item_ids'] as List).map((e) => e.toString()).toList();
    }

    List<LeasedSubItemModel> subItemModels = [];
    if (json['leased_sub_items'] != null && json['leased_sub_items'] is List) {
      subItemModels = (json['leased_sub_items'] as List)
          .map((e) => LeasedSubItemModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return LeaseItemModel(
      id: json['id'] as String,
      leaseId: json['lease_id'] as String? ?? json['leaseId'] as String? ?? '',
      storeId: json['store_id'] as String? ?? json['storeId'] as String? ?? 'demo_store_1',
      itemId: json['item_id'] as String? ?? json['itemId'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      rateHourly: (json['rate_hourly'] as num?)?.toDouble() ?? 0.0,
      rateDaily: (json['rate_daily'] as num?)?.toDouble() ?? 0.0,
      rateWeekly: (json['rate_weekly'] as num?)?.toDouble() ?? 0.0,
      rateMonthly: (json['rate_monthly'] as num?)?.toDouble() ?? 0.0,
      discountedRateHourly: (json['discounted_rate_hourly'] as num?)?.toDouble() ?? 0.0,
      discountedRateDaily: (json['discounted_rate_daily'] as num?)?.toDouble() ?? 0.0,
      discountedRateWeekly: (json['discounted_rate_weekly'] as num?)?.toDouble() ?? 0.0,
      discountedRateMonthly: (json['discounted_rate_monthly'] as num?)?.toDouble() ?? 0.0,
      depositAmount: (json['deposit_amount'] as num?)?.toDouble() ?? 0.0,
      lineCalculatedRent: (json['line_calculated_rent'] as num?)?.toDouble() ?? 0.0,
      returnStatus: json['return_status'] as String? ?? 'available',
      subItemIds: subItems,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      item: json['inventory_items'] != null
          ? InventoryItemModel.fromJson(json['inventory_items'] as Map<String, dynamic>)
          : null,
      leasedSubItems: subItemModels,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'lease_id': leaseId,
      'store_id': storeId,
      'item_id': itemId,
      'quantity': quantity,
      'rate_hourly': rateHourly,
      'rate_daily': rateDaily,
      'rate_weekly': rateWeekly,
      'rate_monthly': rateMonthly,
      'discounted_rate_hourly': discountedRateHourly,
      'discounted_rate_daily': discountedRateDaily,
      'discounted_rate_weekly': discountedRateWeekly,
      'discounted_rate_monthly': discountedRateMonthly,
      'deposit_amount': depositAmount,
      'line_calculated_rent': lineCalculatedRent,
      'return_status': returnStatus,
      'sub_item_ids': subItemIds,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  LeaseItemModel copyWith({
    String? id,
    String? leaseId,
    String? storeId,
    String? itemId,
    int? quantity,
    double? rateHourly,
    double? rateDaily,
    double? rateWeekly,
    double? rateMonthly,
    double? discountedRateHourly,
    double? discountedRateDaily,
    double? discountedRateWeekly,
    double? discountedRateMonthly,
    double? depositAmount,
    double? lineCalculatedRent,
    String? returnStatus,
    List<String>? subItemIds,
    DateTime? createdAt,
    DateTime? updatedAt,
    InventoryItemModel? item,
    List<LeasedSubItemModel>? leasedSubItems,
  }) {
    return LeaseItemModel(
      id: id ?? this.id,
      leaseId: leaseId ?? this.leaseId,
      storeId: storeId ?? this.storeId,
      itemId: itemId ?? this.itemId,
      quantity: quantity ?? this.quantity,
      rateHourly: rateHourly ?? this.rateHourly,
      rateDaily: rateDaily ?? this.rateDaily,
      rateWeekly: rateWeekly ?? this.rateWeekly,
      rateMonthly: rateMonthly ?? this.rateMonthly,
      discountedRateHourly: discountedRateHourly ?? this.discountedRateHourly,
      discountedRateDaily: discountedRateDaily ?? this.discountedRateDaily,
      discountedRateWeekly: discountedRateWeekly ?? this.discountedRateWeekly,
      discountedRateMonthly: discountedRateMonthly ?? this.discountedRateMonthly,
      depositAmount: depositAmount ?? this.depositAmount,
      lineCalculatedRent: lineCalculatedRent ?? this.lineCalculatedRent,
      returnStatus: returnStatus ?? this.returnStatus,
      subItemIds: subItemIds ?? this.subItemIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      item: item ?? this.item,
      leasedSubItems: leasedSubItems ?? this.leasedSubItems,
    );
  }

  @override
  List<Object?> get props => [
        id,
        leaseId,
        storeId,
        itemId,
        quantity,
        rateHourly,
        rateDaily,
        rateWeekly,
        rateMonthly,
        discountedRateHourly,
        discountedRateDaily,
        discountedRateWeekly,
        discountedRateMonthly,
        depositAmount,
        lineCalculatedRent,
        returnStatus,
        subItemIds,
        createdAt,
        updatedAt,
        item,
        leasedSubItems,
      ];
}
