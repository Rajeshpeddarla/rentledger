import 'package:equatable/equatable.dart';
import 'inventory_component_unit_model.dart';

class InventoryUnitModel extends Equatable {
  final String id;
  final String inventoryItemId;
  final String storeId;
  final String assetCode;
  final String status; // 'available', 'rented', 'maintenance', 'lost', 'awaiting_inspection', 'archived'
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Embedded component units list
  final List<InventoryComponentUnitModel> components;

  const InventoryUnitModel({
    required this.id,
    required this.inventoryItemId,
    required this.storeId,
    required this.assetCode,
    this.status = 'available',
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.components = const [],
  });

  bool get isAvailable => status == 'available';
  bool get isRented => status == 'rented';
  bool get isMaintenance => status == 'maintenance';
  bool get isLost => status == 'lost';
  bool get isAwaitingInspection => status == 'awaiting_inspection';

  factory InventoryUnitModel.fromJson(Map<String, dynamic> json) {
    List<InventoryComponentUnitModel> compList = [];
    if (json['inventory_component_units'] != null && json['inventory_component_units'] is List) {
      compList = (json['inventory_component_units'] as List)
          .map((e) => InventoryComponentUnitModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return InventoryUnitModel(
      id: json['id'] as String,
      inventoryItemId: json['inventory_item_id'] as String? ?? json['inventoryItemId'] as String? ?? '',
      storeId: json['store_id'] as String? ?? json['storeId'] as String? ?? '',
      assetCode: json['asset_code'] as String? ?? json['assetCode'] as String? ?? '',
      status: json['status'] as String? ?? 'available',
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      components: compList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'inventory_item_id': inventoryItemId,
      'store_id': storeId,
      'asset_code': assetCode,
      'status': status,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  InventoryUnitModel copyWith({
    String? id,
    String? inventoryItemId,
    String? storeId,
    String? assetCode,
    String? status,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<InventoryComponentUnitModel>? components,
  }) {
    return InventoryUnitModel(
      id: id ?? this.id,
      inventoryItemId: inventoryItemId ?? this.inventoryItemId,
      storeId: storeId ?? this.storeId,
      assetCode: assetCode ?? this.assetCode,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      components: components ?? this.components,
    );
  }

  @override
  List<Object?> get props => [
        id,
        inventoryItemId,
        storeId,
        assetCode,
        status,
        notes,
        createdAt,
        updatedAt,
        components,
      ];
}
