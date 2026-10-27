import 'package:equatable/equatable.dart';

class DiscountModel extends Equatable {
  final String id;
  final String storeId;
  final String code; // e.g. 'SUMMER10'
  final String title; // e.g. '10% Off Camera Gear'
  final String discountType; // 'percentage' or 'flat'
  final double discountValue; // e.g. 10.0 (%) or 500.0 (flat amount)
  final List<String> eligibleItemIds; // Selected inventory item IDs (empty = all fleet equipment)
  final int minRentalDays;
  final DateTime expiryDate; // Expiry date (default 30 days from creation)
  final int? maxUses; // Optional usage limit (null = unlimited)
  final int usedCount;
  final bool isActive;
  final DateTime createdAt;

  const DiscountModel({
    required this.id,
    required this.storeId,
    required this.code,
    required this.title,
    this.discountType = 'percentage',
    required this.discountValue,
    this.eligibleItemIds = const [],
    this.minRentalDays = 1,
    required this.expiryDate,
    this.maxUses,
    this.usedCount = 0,
    this.isActive = true,
    required this.createdAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiryDate);

  bool get isMaxUsesReached => maxUses != null && usedCount >= maxUses!;

  bool matchesItem({required String? itemId, int durationDays = 1}) {
    if (!isActive) return false;
    if (isExpired) return false;
    if (isMaxUsesReached) return false;
    if (durationDays < minRentalDays) return false;

    if (eligibleItemIds.isNotEmpty && itemId != null) {
      return eligibleItemIds.contains(itemId);
    }
    return true; // Applies to all fleet equipment if list is empty
  }

  double calculateDiscountAmount(double grossRent) {
    if (!isActive || isExpired || isMaxUsesReached || grossRent <= 0) return 0.0;
    if (discountType == 'percentage') {
      final discount = (grossRent * discountValue) / 100.0;
      return discount > grossRent ? grossRent : double.parse(discount.toStringAsFixed(2));
    } else {
      return discountValue > grossRent ? grossRent : double.parse(discountValue.toStringAsFixed(2));
    }
  }

  factory DiscountModel.fromJson(Map<String, dynamic> json) {
    final rawEligible = json['eligible_item_ids'] ?? json['eligibleItemIds'];
    List<String> itemsList = [];
    if (rawEligible is List) {
      itemsList = rawEligible.map((e) => e.toString()).toList();
    } else if (json['target_item_id'] != null) {
      itemsList = [json['target_item_id'].toString()];
    }

    return DiscountModel(
      id: json['id'] as String,
      storeId: json['store_id'] as String? ?? 'demo_store_1',
      code: json['code'] as String? ?? 'DISCOUNT',
      title: json['title'] as String? ?? 'Special Discount',
      discountType: json['discount_type'] as String? ?? 'percentage',
      discountValue: (json['discount_value'] as num?)?.toDouble() ?? 0.0,
      eligibleItemIds: itemsList,
      minRentalDays: (json['min_rental_days'] as num?)?.toInt() ?? 1,
      expiryDate: json['expiry_date'] != null
          ? DateTime.parse(json['expiry_date'] as String)
          : DateTime.now().add(const Duration(days: 30)),
      maxUses: json['max_uses'] != null ? (json['max_uses'] as num).toInt() : null,
      usedCount: (json['used_count'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'store_id': storeId,
      'code': code,
      'title': title,
      'discount_type': discountType,
      'discount_value': discountValue,
      'eligible_item_ids': eligibleItemIds,
      'min_rental_days': minRentalDays,
      'expiry_date': expiryDate.toIso8601String(),
      'max_uses': maxUses,
      'used_count': usedCount,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }

  DiscountModel copyWith({
    String? id,
    String? storeId,
    String? code,
    String? title,
    String? discountType,
    double? discountValue,
    List<String>? eligibleItemIds,
    int? minRentalDays,
    DateTime? expiryDate,
    int? maxUses,
    int? usedCount,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return DiscountModel(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      code: code ?? this.code,
      title: title ?? this.title,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
      eligibleItemIds: eligibleItemIds ?? this.eligibleItemIds,
      minRentalDays: minRentalDays ?? this.minRentalDays,
      expiryDate: expiryDate ?? this.expiryDate,
      maxUses: maxUses ?? this.maxUses,
      usedCount: usedCount ?? this.usedCount,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        storeId,
        code,
        title,
        discountType,
        discountValue,
        eligibleItemIds,
        minRentalDays,
        expiryDate,
        maxUses,
        usedCount,
        isActive,
        createdAt,
      ];
}
