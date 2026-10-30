import 'package:equatable/equatable.dart';
import 'damage_loss_payment_model.dart';
import 'inventory_component_unit_model.dart';
import 'inventory_unit_model.dart';

class DamageLossIncidentModel extends Equatable {
  final String id;
  final String storeId;
  final String? leaseId;
  final String? leaseItemId;
  final String? inventoryUnitId;
  final String? inventoryComponentUnitId;

  final String incidentType; // 'damaged', 'lost'
  final String? description;
  final double estimatedRepairCost;
  final double actualRepairCost;
  final double customerCharge;
  final double customerAmountPaid;
  final String paymentStatus; // 'unpaid', 'partially_paid', 'fully_paid', 'overpaid'
  final String repairStatus; // 'reported', 'awaiting_repair', 'in_repair', 'repaired', 'replaced', 'written_off', 'resolved'

  final DateTime reportedAt;
  final DateTime? resolvedAt;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Relations for UI
  final InventoryUnitModel? unit;
  final InventoryComponentUnitModel? componentUnit;
  final List<DamageLossPaymentModel> payments;

  const DamageLossIncidentModel({
    required this.id,
    required this.storeId,
    this.leaseId,
    this.leaseItemId,
    this.inventoryUnitId,
    this.inventoryComponentUnitId,
    required this.incidentType,
    this.description,
    this.estimatedRepairCost = 0.0,
    this.actualRepairCost = 0.0,
    this.customerCharge = 0.0,
    this.customerAmountPaid = 0.0,
    this.paymentStatus = 'unpaid',
    this.repairStatus = 'reported',
    required this.reportedAt,
    this.resolvedAt,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.unit,
    this.componentUnit,
    this.payments = const [],
  });

  double get outstandingBalance {
    final bal = customerCharge - customerAmountPaid;
    return bal < 0 ? 0.0 : bal;
  }

  bool get isResolved => repairStatus == 'resolved' || repairStatus == 'repaired' || repairStatus == 'written_off';

  factory DamageLossIncidentModel.fromJson(Map<String, dynamic> json) {
    List<DamageLossPaymentModel> payList = [];
    if (json['damage_loss_payments'] != null && json['damage_loss_payments'] is List) {
      payList = (json['damage_loss_payments'] as List)
          .map((e) => DamageLossPaymentModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return DamageLossIncidentModel(
      id: json['id'] as String,
      storeId: json['store_id'] as String? ?? json['storeId'] as String? ?? '',
      leaseId: json['lease_id'] as String? ?? json['leaseId'] as String?,
      leaseItemId: json['lease_item_id'] as String? ?? json['leaseItemId'] as String?,
      inventoryUnitId: json['inventory_unit_id'] as String? ?? json['inventoryUnitId'] as String?,
      inventoryComponentUnitId: json['inventory_component_unit_id'] as String? ?? json['inventoryComponentUnitId'] as String?,
      incidentType: json['incident_type'] as String? ?? json['incidentType'] as String? ?? 'damaged',
      description: json['description'] as String?,
      estimatedRepairCost: (json['estimated_repair_cost'] as num?)?.toDouble() ?? 0.0,
      actualRepairCost: (json['actual_repair_cost'] as num?)?.toDouble() ?? 0.0,
      customerCharge: (json['customer_charge'] as num?)?.toDouble() ?? 0.0,
      customerAmountPaid: (json['customer_amount_paid'] as num?)?.toDouble() ?? 0.0,
      paymentStatus: json['payment_status'] as String? ?? 'unpaid',
      repairStatus: json['repair_status'] as String? ?? 'reported',
      reportedAt: json['reported_at'] != null
          ? DateTime.parse(json['reported_at'] as String)
          : DateTime.now(),
      resolvedAt: json['resolved_at'] != null
          ? DateTime.parse(json['resolved_at'] as String)
          : null,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      unit: json['inventory_units'] != null
          ? InventoryUnitModel.fromJson(json['inventory_units'] as Map<String, dynamic>)
          : null,
      componentUnit: json['inventory_component_units'] != null
          ? InventoryComponentUnitModel.fromJson(json['inventory_component_units'] as Map<String, dynamic>)
          : null,
      payments: payList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'store_id': storeId,
      'lease_id': leaseId,
      'lease_item_id': leaseItemId,
      'inventory_unit_id': inventoryUnitId,
      'inventory_component_unit_id': inventoryComponentUnitId,
      'incident_type': incidentType,
      'description': description,
      'estimated_repair_cost': estimatedRepairCost,
      'actual_repair_cost': actualRepairCost,
      'customer_charge': customerCharge,
      'customer_amount_paid': customerAmountPaid,
      'payment_status': paymentStatus,
      'repair_status': repairStatus,
      'reported_at': reportedAt.toIso8601String(),
      'resolved_at': resolvedAt?.toIso8601String(),
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  DamageLossIncidentModel copyWith({
    String? id,
    String? storeId,
    String? leaseId,
    String? leaseItemId,
    String? inventoryUnitId,
    String? inventoryComponentUnitId,
    String? incidentType,
    String? description,
    double? estimatedRepairCost,
    double? actualRepairCost,
    double? customerCharge,
    double? customerAmountPaid,
    String? paymentStatus,
    String? repairStatus,
    DateTime? reportedAt,
    DateTime? resolvedAt,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    InventoryUnitModel? unit,
    InventoryComponentUnitModel? componentUnit,
    List<DamageLossPaymentModel>? payments,
  }) {
    return DamageLossIncidentModel(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      leaseId: leaseId ?? this.leaseId,
      leaseItemId: leaseItemId ?? this.leaseItemId,
      inventoryUnitId: inventoryUnitId ?? this.inventoryUnitId,
      inventoryComponentUnitId: inventoryComponentUnitId ?? this.inventoryComponentUnitId,
      incidentType: incidentType ?? this.incidentType,
      description: description ?? this.description,
      estimatedRepairCost: estimatedRepairCost ?? this.estimatedRepairCost,
      actualRepairCost: actualRepairCost ?? this.actualRepairCost,
      customerCharge: customerCharge ?? this.customerCharge,
      customerAmountPaid: customerAmountPaid ?? this.customerAmountPaid,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      repairStatus: repairStatus ?? this.repairStatus,
      reportedAt: reportedAt ?? this.reportedAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      unit: unit ?? this.unit,
      componentUnit: componentUnit ?? this.componentUnit,
      payments: payments ?? this.payments,
    );
  }

  @override
  List<Object?> get props => [
        id,
        storeId,
        leaseId,
        leaseItemId,
        inventoryUnitId,
        inventoryComponentUnitId,
        incidentType,
        description,
        estimatedRepairCost,
        actualRepairCost,
        customerCharge,
        customerAmountPaid,
        paymentStatus,
        repairStatus,
        reportedAt,
        resolvedAt,
        notes,
        createdAt,
        updatedAt,
        unit,
        componentUnit,
        payments,
      ];
}
