import 'package:equatable/equatable.dart';

class InventoryItemHistoryModel extends Equatable {
  final String id;
  final String storeId;
  final String inventoryItemId;
  final String? inventoryUnitId;
  final String? inventoryComponentUnitId;
  final String? leaseId;
  final String eventType; // 'damaged', 'repaired', 'lost', 'replaced'
  final String? previousStatus;
  final String newStatus;
  final String? notes;
  final double costIncurred;
  final DateTime createdAt;

  const InventoryItemHistoryModel({
    required this.id,
    required this.storeId,
    required this.inventoryItemId,
    this.inventoryUnitId,
    this.inventoryComponentUnitId,
    this.leaseId,
    required this.eventType,
    this.previousStatus,
    required this.newStatus,
    this.notes,
    this.costIncurred = 0.0,
    required this.createdAt,
  });

  factory InventoryItemHistoryModel.fromJson(Map<String, dynamic> json) {
    return InventoryItemHistoryModel(
      id: json['id'] as String,
      storeId: json['store_id'] as String? ?? json['storeId'] as String? ?? '',
      inventoryItemId: json['inventory_item_id'] as String? ?? json['inventoryItemId'] as String? ?? '',
      inventoryUnitId: json['inventory_unit_id'] as String? ?? json['inventoryUnitId'] as String?,
      inventoryComponentUnitId: json['inventory_component_unit_id'] as String? ?? json['inventoryComponentUnitId'] as String?,
      leaseId: json['lease_id'] as String? ?? json['leaseId'] as String?,
      eventType: json['event_type'] as String? ?? json['eventType'] as String? ?? 'damaged',
      previousStatus: json['previous_status'] as String? ?? json['previousStatus'] as String?,
      newStatus: json['new_status'] as String? ?? json['newStatus'] as String? ?? 'available',
      notes: json['notes'] as String?,
      costIncurred: (json['cost_incurred'] as num?)?.toDouble() ?? (json['costIncurred'] as num?)?.toDouble() ?? 0.0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'store_id': storeId,
      'inventory_item_id': inventoryItemId,
      if (inventoryUnitId != null) 'inventory_unit_id': inventoryUnitId,
      if (inventoryComponentUnitId != null) 'inventory_component_unit_id': inventoryComponentUnitId,
      if (leaseId != null) 'lease_id': leaseId,
      'event_type': eventType,
      if (previousStatus != null) 'previous_status': previousStatus,
      'new_status': newStatus,
      if (notes != null) 'notes': notes,
      'cost_incurred': costIncurred,
      'created_at': createdAt.toIso8601String(),
    };
  }

  InventoryItemHistoryModel copyWith({
    String? id,
    String? storeId,
    String? inventoryItemId,
    String? inventoryUnitId,
    String? inventoryComponentUnitId,
    String? leaseId,
    String? eventType,
    String? previousStatus,
    String? newStatus,
    String? notes,
    double? costIncurred,
    DateTime? createdAt,
  }) {
    return InventoryItemHistoryModel(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      inventoryItemId: inventoryItemId ?? this.inventoryItemId,
      inventoryUnitId: inventoryUnitId ?? this.inventoryUnitId,
      inventoryComponentUnitId: inventoryComponentUnitId ?? this.inventoryComponentUnitId,
      leaseId: leaseId ?? this.leaseId,
      eventType: eventType ?? this.eventType,
      previousStatus: previousStatus ?? this.previousStatus,
      newStatus: newStatus ?? this.newStatus,
      notes: notes ?? this.notes,
      costIncurred: costIncurred ?? this.costIncurred,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        storeId,
        inventoryItemId,
        inventoryUnitId,
        inventoryComponentUnitId,
        leaseId,
        eventType,
        previousStatus,
        newStatus,
        notes,
        costIncurred,
        createdAt,
      ];
}
