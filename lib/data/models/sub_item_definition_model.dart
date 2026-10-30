import 'package:equatable/equatable.dart';

class SubItemDefinitionModel extends Equatable {
  final String id;
  final String parentItemId;
  final String storeId;
  final String componentName;
  final int defaultQuantity;
  final bool isRequired;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SubItemDefinitionModel({
    required this.id,
    required this.parentItemId,
    required this.storeId,
    required this.componentName,
    this.defaultQuantity = 1,
    this.isRequired = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SubItemDefinitionModel.fromJson(Map<String, dynamic> json) {
    return SubItemDefinitionModel(
      id: json['id'] as String,
      parentItemId: json['parent_item_id'] as String? ?? json['parentItemId'] as String? ?? '',
      storeId: json['store_id'] as String? ?? json['storeId'] as String? ?? '',
      componentName: json['component_name'] as String? ?? json['componentName'] as String? ?? json['name'] as String? ?? 'Component',
      defaultQuantity: (json['default_quantity'] as num?)?.toInt() ?? 1,
      isRequired: json['is_required'] as bool? ?? true,
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
      'component_name': componentName,
      'default_quantity': defaultQuantity,
      'is_required': isRequired,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  SubItemDefinitionModel copyWith({
    String? id,
    String? parentItemId,
    String? storeId,
    String? componentName,
    int? defaultQuantity,
    bool? isRequired,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SubItemDefinitionModel(
      id: id ?? this.id,
      parentItemId: parentItemId ?? this.parentItemId,
      storeId: storeId ?? this.storeId,
      componentName: componentName ?? this.componentName,
      defaultQuantity: defaultQuantity ?? this.defaultQuantity,
      isRequired: isRequired ?? this.isRequired,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        parentItemId,
        storeId,
        componentName,
        defaultQuantity,
        isRequired,
        createdAt,
        updatedAt,
      ];
}
