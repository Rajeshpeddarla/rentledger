import 'package:equatable/equatable.dart';
import 'customer_model.dart';
import 'inventory_item_model.dart';
import 'lease_item_model.dart';

class LeaseModel extends Equatable {
  final String id;
  final String storeId;
  final String itemId;
  final String customerId;

  final DateTime startTime;
  final DateTime expectedEndTime;
  final DateTime? actualReturnTime;

  final List<String> beforePhotoUrls;

  final double depositExpected;
  final double depositPaid;
  final double advanceRentPaid;
  final String depositPaymentType; // 'full', 'partial', 'none'

  final String billingUnitUsed; // 'auto', 'hourly', 'daily', etc.
  final double calculatedRent;
  final double discountAmount;
  final double damageOrLateFee;
  final double netRentTotal;
  final double finalSettlementBalance;
  final String? returnNotes;

  // Transaction Tax Snapshot Fields (Retained for Historical Audits)
  final double taxableAmount;
  final String appliedTaxType; // 'GST', 'VAT', 'Sales Tax', 'Other', 'No Tax'
  final double appliedTaxRate; // e.g. 18.0 (%)
  final double taxAmount;
  final double totalAmountWithTax;
  final bool isTaxInclusive;

  final int quantity;
  final List<String> subItemIds;
  final String status; // 'upcoming', 'active', 'reserved', 'returned', 'cancelled'
  final DateTime createdAt;
  final DateTime updatedAt;

  // 1-to-Many Lease Line Items
  final List<LeaseItemModel> leaseItems;

  // Embedded relations for convenient UI consumption
  final InventoryItemModel? item;
  final CustomerModel? customer;

  const LeaseModel({
    required this.id,
    required this.storeId,
    required this.itemId,
    required this.customerId,
    required this.startTime,
    required this.expectedEndTime,
    this.actualReturnTime,
    this.beforePhotoUrls = const [],
    this.depositExpected = 0.0,
    this.depositPaid = 0.0,
    this.advanceRentPaid = 0.0,
    this.depositPaymentType = 'full',
    this.billingUnitUsed = 'auto',
    this.calculatedRent = 0.0,
    this.discountAmount = 0.0,
    this.damageOrLateFee = 0.0,
    this.netRentTotal = 0.0,
    this.finalSettlementBalance = 0.0,
    this.returnNotes,
    this.taxableAmount = 0.0,
    this.appliedTaxType = 'No Tax',
    this.appliedTaxRate = 0.0,
    this.taxAmount = 0.0,
    this.totalAmountWithTax = 0.0,
    this.isTaxInclusive = false,
    this.quantity = 1,
    this.subItemIds = const [],
    this.status = 'active',
    required this.createdAt,
    required this.updatedAt,
    this.leaseItems = const [],
    this.item,
    this.customer,
  });

  bool get isOverdue {
    if (status != 'active' && status != 'reserved') return false;
    return DateTime.now().isAfter(expectedEndTime);
  }

  int get hoursOverdue {
    if (!isOverdue) return 0;
    return DateTime.now().difference(expectedEndTime).inHours;
  }

  bool get isDueToday {
    if (status != 'active' && status != 'reserved') return false;
    final now = DateTime.now();
    return expectedEndTime.year == now.year &&
        expectedEndTime.month == now.month &&
        expectedEndTime.day == now.day;
  }

  bool get isFutureReservation => status == 'reserved' || (status == 'upcoming' && startTime.isAfter(DateTime.now()));

  String get shortId => id.length > 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();

  int get totalPieces {
    if (leaseItems.isNotEmpty) {
      return leaseItems.fold(0, (sum, li) => sum + li.quantity);
    }
    return quantity;
  }

  String get itemNamesSummary {
    if (leaseItems.isNotEmpty) {
      return leaseItems.map((li) => '${li.quantity}x ${li.item?.name ?? "Equipment"}').join(', ');
    }
    if (returnNotes != null && returnNotes!.contains('Leased Equipment Items:')) {
      final noteStr = returnNotes!.replaceFirst('Leased Equipment Items:', '').trim();
      if (noteStr.isNotEmpty) return noteStr;
    }
    return item?.name ?? 'Equipment Item';
  }

  static DateTime _parseLocalDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value.toLocal();
    final str = value.toString();
    try {
      final parsed = DateTime.parse(str);
      return DateTime(
        parsed.year,
        parsed.month,
        parsed.day,
        parsed.hour,
        parsed.minute,
        parsed.second,
        parsed.millisecond,
      );
    } catch (_) {
      return DateTime.now();
    }
  }

  factory LeaseModel.fromJson(Map<String, dynamic> json) {
    List<String> photos = [];
    if (json['before_photo_urls'] != null && json['before_photo_urls'] is List) {
      photos = (json['before_photo_urls'] as List).map((e) => e.toString()).toList();
    }

    List<String> subItems = [];
    if (json['sub_item_ids'] != null && json['sub_item_ids'] is List) {
      subItems = (json['sub_item_ids'] as List).map((e) => e.toString()).toList();
    }

    List<LeaseItemModel> lineItems = [];
    if (json['lease_items'] != null && json['lease_items'] is List) {
      lineItems = (json['lease_items'] as List)
          .map((e) => LeaseItemModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return LeaseModel(
      id: json['id'] as String,
      storeId: json['store_id'] as String? ?? json['storeId'] as String? ?? 'demo_store_1',
      itemId: json['item_id'] as String? ?? json['itemId'] as String? ?? '',
      customerId: json['customer_id'] as String? ?? json['customerId'] as String? ?? '',
      startTime: _parseLocalDateTime(json['start_time']),
      expectedEndTime: _parseLocalDateTime(json['expected_end_time']),
      actualReturnTime: json['actual_return_time'] != null
          ? _parseLocalDateTime(json['actual_return_time'])
          : null,
      beforePhotoUrls: photos,
      depositExpected: (json['deposit_expected'] as num?)?.toDouble() ?? 0.0,
      depositPaid: (json['deposit_paid'] as num?)?.toDouble() ?? 0.0,
      advanceRentPaid: (json['advance_rent_paid'] as num?)?.toDouble() ?? 0.0,
      depositPaymentType: json['deposit_payment_type'] as String? ?? 'full',
      billingUnitUsed: json['billing_unit_used'] as String? ?? 'auto',
      calculatedRent: (json['calculated_rent'] as num?)?.toDouble() ?? 0.0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0.0,
      damageOrLateFee: (json['damage_or_late_fee'] as num?)?.toDouble() ?? 0.0,
      netRentTotal: (json['net_rent_total'] as num?)?.toDouble() ?? 0.0,
      finalSettlementBalance:
          (json['final_settlement_balance'] as num?)?.toDouble() ?? 0.0,
      returnNotes: json['return_notes'] as String?,
      taxableAmount: (json['taxable_amount'] as num?)?.toDouble() ?? 0.0,
      appliedTaxType: json['applied_tax_type'] as String? ?? 'No Tax',
      appliedTaxRate: (json['applied_tax_rate'] as num?)?.toDouble() ?? 0.0,
      taxAmount: (json['tax_amount'] as num?)?.toDouble() ?? 0.0,
      totalAmountWithTax: (json['total_amount_with_tax'] as num?)?.toDouble() ??
          (json['net_rent_total'] as num?)?.toDouble() ??
          0.0,
      isTaxInclusive: json['is_tax_inclusive'] as bool? ?? false,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      subItemIds: subItems,
      status: json['status'] as String? ?? 'active',
      createdAt: json['created_at'] != null
          ? _parseLocalDateTime(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? _parseLocalDateTime(json['updated_at'])
          : DateTime.now(),
      leaseItems: lineItems,
      item: json['inventory_items'] != null
          ? InventoryItemModel.fromJson(json['inventory_items'] as Map<String, dynamic>)
          : null,
      customer: json['customers'] != null
          ? CustomerModel.fromJson(json['customers'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'store_id': storeId,
      'item_id': itemId,
      'customer_id': customerId,
      'start_time': startTime.toIso8601String(),
      'expected_end_time': expectedEndTime.toIso8601String(),
      'actual_return_time': actualReturnTime?.toIso8601String(),
      'before_photo_urls': beforePhotoUrls,
      'deposit_expected': depositExpected,
      'deposit_paid': depositPaid,
      'advance_rent_paid': advanceRentPaid,
      'deposit_payment_type': depositPaymentType,
      'billing_unit_used': billingUnitUsed,
      'calculated_rent': calculatedRent,
      'discount_amount': discountAmount,
      'damage_or_late_fee': damageOrLateFee,
      'net_rent_total': netRentTotal,
      'final_settlement_balance': finalSettlementBalance,
      'return_notes': returnNotes,
      'taxable_amount': taxableAmount,
      'applied_tax_type': appliedTaxType,
      'applied_tax_rate': appliedTaxRate,
      'tax_amount': taxAmount,
      'total_amount_with_tax': totalAmountWithTax,
      'is_tax_inclusive': isTaxInclusive,
      'quantity': quantity,
      'sub_item_ids': subItemIds,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toDatabaseJson() {
    final map = Map<String, dynamic>.from(toJson());
    if (actualReturnTime == null) {
      map.remove('actual_return_time');
    }
    return map;
  }

  LeaseModel copyWith({
    String? id,
    String? storeId,
    String? itemId,
    String? customerId,
    DateTime? startTime,
    DateTime? expectedEndTime,
    DateTime? actualReturnTime,
    List<String>? beforePhotoUrls,
    double? depositExpected,
    double? depositPaid,
    double? advanceRentPaid,
    String? depositPaymentType,
    String? billingUnitUsed,
    double? calculatedRent,
    double? discountAmount,
    double? damageOrLateFee,
    double? netRentTotal,
    double? finalSettlementBalance,
    String? returnNotes,
    double? taxableAmount,
    String? appliedTaxType,
    double? appliedTaxRate,
    double? taxAmount,
    double? totalAmountWithTax,
    bool? isTaxInclusive,
    int? quantity,
    List<String>? subItemIds,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<LeaseItemModel>? leaseItems,
    InventoryItemModel? item,
    CustomerModel? customer,
  }) {
    return LeaseModel(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      itemId: itemId ?? this.itemId,
      customerId: customerId ?? this.customerId,
      startTime: startTime ?? this.startTime,
      expectedEndTime: expectedEndTime ?? this.expectedEndTime,
      actualReturnTime: actualReturnTime ?? this.actualReturnTime,
      beforePhotoUrls: beforePhotoUrls ?? this.beforePhotoUrls,
      depositExpected: depositExpected ?? this.depositExpected,
      depositPaid: depositPaid ?? this.depositPaid,
      advanceRentPaid: advanceRentPaid ?? this.advanceRentPaid,
      depositPaymentType: depositPaymentType ?? this.depositPaymentType,
      billingUnitUsed: billingUnitUsed ?? this.billingUnitUsed,
      calculatedRent: calculatedRent ?? this.calculatedRent,
      discountAmount: discountAmount ?? this.discountAmount,
      damageOrLateFee: damageOrLateFee ?? this.damageOrLateFee,
      netRentTotal: netRentTotal ?? this.netRentTotal,
      finalSettlementBalance:
          finalSettlementBalance ?? this.finalSettlementBalance,
      returnNotes: returnNotes ?? this.returnNotes,
      taxableAmount: taxableAmount ?? this.taxableAmount,
      appliedTaxType: appliedTaxType ?? this.appliedTaxType,
      appliedTaxRate: appliedTaxRate ?? this.appliedTaxRate,
      taxAmount: taxAmount ?? this.taxAmount,
      totalAmountWithTax: totalAmountWithTax ?? this.totalAmountWithTax,
      isTaxInclusive: isTaxInclusive ?? this.isTaxInclusive,
      quantity: quantity ?? this.quantity,
      subItemIds: subItemIds ?? this.subItemIds,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      leaseItems: leaseItems ?? this.leaseItems,
      item: item ?? this.item,
      customer: customer ?? this.customer,
    );
  }

  @override
  List<Object?> get props => [
        id,
        storeId,
        itemId,
        customerId,
        startTime,
        expectedEndTime,
        actualReturnTime,
        beforePhotoUrls,
        depositExpected,
        depositPaid,
        advanceRentPaid,
        depositPaymentType,
        billingUnitUsed,
        calculatedRent,
        discountAmount,
        damageOrLateFee,
        netRentTotal,
        finalSettlementBalance,
        returnNotes,
        taxableAmount,
        appliedTaxType,
        appliedTaxRate,
        taxAmount,
        totalAmountWithTax,
        isTaxInclusive,
        quantity,
        subItemIds,
        status,
        createdAt,
        updatedAt,
        leaseItems,
        item,
        customer,
      ];
}
