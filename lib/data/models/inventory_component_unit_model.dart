import 'package:equatable/equatable.dart';

class InventoryComponentUnitModel extends Equatable {
  final String id;
  final String inventoryUnitId;
  final String inventoryItemId;
  final String? componentDefinitionId;
  final String storeId;
  final String componentName;
  final String assetCode;
  final String? serialNumber;
  final String status; // 'available', 'rented', 'maintenance', 'lost', 'archived'
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const InventoryComponentUnitModel({
    required this.id,
    required this.inventoryUnitId,
    required this.inventoryItemId,
    this.componentDefinitionId,
    required this.storeId,
    required this.componentName,
    required this.assetCode,
    this.serialNumber,
    this.status = 'available',
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isAvailable => status == 'available';
  bool get isRented => status == 'rented';
  bool get isMaintenance => status == 'maintenance';
  bool get isLost => status == 'lost';

  factory InventoryComponentUnitModel.fromJson(Map<String, dynamic> json) {
    return InventoryComponentUnitModel(
      id: json['id'] as String,
      inventoryUnitId: json['inventory_unit_id'] as String? ?? json['inventoryUnitId'] as String? ?? '',
      inventoryItemId: json['inventory_item_id'] as String? ?? json['inventoryItemId'] as String? ?? '',
      componentDefinitionId: json['component_definition_id'] as String? ?? json['componentDefinitionId'] as String?,
      storeId: json['store_id'] as String? ?? json['storeId'] as String? ?? '',
      componentName: json['component_name'] as String? ?? json['componentName'] as String? ?? json['name'] as String? ?? 'Component',
      assetCode: json['asset_code'] as String? ?? json['assetCode'] as String? ?? '',
      serialNumber: json['serial_number'] as String? ?? json['serialNumber'] as String?,
      status: json['status'] as String? ?? 'available',
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
      'inventory_unit_id': inventoryUnitId,
      'inventory_item_id': inventoryItemId,
      'component_definition_id': componentDefinitionId,
      'store_id': storeId,
      'component_name': componentName,
      'asset_code': assetCode,
      'serial_number': serialNumber,
      'status': status,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  InventoryComponentUnitModel copyWith({
    String? id,
    String? inventoryUnitId,
    String? inventoryItemId,
    String? componentDefinitionId,
    String? storeId,
    String? componentName,
    String? assetCode,
    String? serialNumber,
    String? status,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return InventoryComponentUnitModel(
      id: id ?? this.id,
      inventoryUnitId: inventoryUnitId ?? this.inventoryUnitId,
      inventoryItemId: inventoryItemId ?? this.inventoryItemId,
      componentDefinitionId: componentDefinitionId ?? this.componentDefinitionId,
      storeId: storeId ?? this.storeId,
      componentName: componentName ?? this.componentName,
      assetCode: assetCode ?? this.assetCode,
      serialNumber: serialNumber ?? this.serialNumber,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        inventoryUnitId,
        inventoryItemId,
        componentDefinitionId,
        storeId,
        componentName,
        assetCode,
        serialNumber,
        status,
        notes,
        createdAt,
        updatedAt,
      ];
}
