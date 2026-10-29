import 'package:equatable/equatable.dart';

class SubItemModel extends Equatable {
  final String id;
  final String parentItemId;
  final String storeId;
  final String name;
  final String? serialNumber;
  final String? sku;
  final String status; // 'available', 'leased', 'awaiting_inspection', 'maintenance', 'reserved', 'lost'
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SubItemModel({
    required this.id,
    required this.parentItemId,
    required this.storeId,
    required this.name,
    this.serialNumber,
    this.sku,
    this.status = 'available',
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isAvailable => status == 'available';
  bool get isLeased => status == 'leased';
  bool get isAwaitingInspection => status == 'awaiting_inspection';
  bool get isMaintenance => status == 'maintenance';
  bool get isReserved => status == 'reserved';
  bool get isLost => status == 'lost';

  String get displaySku => (sku != null && sku!.isNotEmpty) ? sku! : 'SUB-${id.substring(0, id.length >= 6 ? 6 : id.length).toUpperCase()}';

  factory SubItemModel.fromJson(Map<String, dynamic> json) {
    return SubItemModel(
      id: json['id'] as String,
      parentItemId: json['parent_item_id'] as String? ?? json['parentItemId'] as String,
      storeId: json['store_id'] as String? ?? json['storeId'] as String,
      name: json['name'] as String? ?? 'Sub-Item',
      serialNumber: json['serial_number'] as String? ?? json['serialNumber'] as String?,
      sku: json['sku'] as String?,
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
      'parent_item_id': parentItemId,
      'store_id': storeId,
      'name': name,
      'serial_number': serialNumber,
      'sku': sku,
      'status': status,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  SubItemModel copyWith({
    String? id,
    String? parentItemId,
    String? storeId,
    String? name,
    String? serialNumber,
    String? sku,
    String? status,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SubItemModel(
      id: id ?? this.id,
      parentItemId: parentItemId ?? this.parentItemId,
      storeId: storeId ?? this.storeId,
      name: name ?? this.name,
      serialNumber: serialNumber ?? this.serialNumber,
      sku: sku ?? this.sku,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        parentItemId,
        storeId,
        name,
        serialNumber,
        sku,
        status,
        notes,
        createdAt,
        updatedAt,
      ];
}
