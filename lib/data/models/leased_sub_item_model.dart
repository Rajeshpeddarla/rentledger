import 'package:equatable/equatable.dart';

class LeasedSubItemModel extends Equatable {
  final String id;
  final String leaseId;
  final String leaseItemId;
  final String subItemId;
  final String itemId;
  final String storeId;
  final String itemName;
  final String? serialNumber;
  final String conditionStatus; // 'available', 'awaiting_inspection', 'maintenance', 'lost'
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LeasedSubItemModel({
    required this.id,
    required this.leaseId,
    required this.leaseItemId,
    required this.subItemId,
    required this.itemId,
    required this.storeId,
    required this.itemName,
    this.serialNumber,
    this.conditionStatus = 'available',
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LeasedSubItemModel.fromJson(Map<String, dynamic> json) {
    return LeasedSubItemModel(
      id: json['id'] as String,
      leaseId: json['lease_id'] as String? ?? json['leaseId'] as String? ?? '',
      leaseItemId: json['lease_item_id'] as String? ?? json['leaseItemId'] as String? ?? '',
      subItemId: json['sub_item_id'] as String? ?? json['subItemId'] as String? ?? '',
      itemId: json['item_id'] as String? ?? json['itemId'] as String? ?? '',
      storeId: json['store_id'] as String? ?? json['storeId'] as String? ?? 'demo_store_1',
      itemName: json['item_name'] as String? ?? json['itemName'] as String? ?? 'Sub-Item Unit',
      serialNumber: json['serial_number'] as String?,
      conditionStatus: json['condition_status'] as String? ?? 'available',
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'lease_id': leaseId,
      'lease_item_id': leaseItemId,
      'sub_item_id': subItemId,
      'item_id': itemId,
      'store_id': storeId,
      'item_name': itemName,
      'serial_number': serialNumber,
      'condition_status': conditionStatus,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  LeasedSubItemModel copyWith({
    String? id,
    String? leaseId,
    String? leaseItemId,
    String? subItemId,
    String? itemId,
    String? storeId,
    String? itemName,
    String? serialNumber,
    String? conditionStatus,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LeasedSubItemModel(
      id: id ?? this.id,
      leaseId: leaseId ?? this.leaseId,
      leaseItemId: leaseItemId ?? this.leaseItemId,
      subItemId: subItemId ?? this.subItemId,
      itemId: itemId ?? this.itemId,
      storeId: storeId ?? this.storeId,
      itemName: itemName ?? this.itemName,
      serialNumber: serialNumber ?? this.serialNumber,
      conditionStatus: conditionStatus ?? this.conditionStatus,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        leaseId,
        leaseItemId,
        subItemId,
        itemId,
        storeId,
        itemName,
        serialNumber,
        conditionStatus,
        notes,
        createdAt,
        updatedAt,
      ];
}
