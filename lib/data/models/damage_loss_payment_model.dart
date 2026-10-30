import 'package:equatable/equatable.dart';

class DamageLossPaymentModel extends Equatable {
  final String id;
  final String incidentId;
  final String storeId;
  final double amountPaid;
  final String paymentMethod; // 'cash', 'upi', 'card', 'bank_transfer'
  final String? notes;
  final DateTime paidAt;
  final DateTime createdAt;

  const DamageLossPaymentModel({
    required this.id,
    required this.incidentId,
    required this.storeId,
    required this.amountPaid,
    this.paymentMethod = 'cash',
    this.notes,
    required this.paidAt,
    required this.createdAt,
  });

  factory DamageLossPaymentModel.fromJson(Map<String, dynamic> json) {
    return DamageLossPaymentModel(
      id: json['id'] as String,
      incidentId: json['incident_id'] as String? ?? json['incidentId'] as String? ?? '',
      storeId: json['store_id'] as String? ?? json['storeId'] as String? ?? '',
      amountPaid: (json['amount_paid'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: json['payment_method'] as String? ?? json['paymentMethod'] as String? ?? 'cash',
      notes: json['notes'] as String?,
      paidAt: json['paid_at'] != null
          ? DateTime.parse(json['paid_at'] as String)
          : DateTime.now(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'incident_id': incidentId,
      'store_id': storeId,
      'amount_paid': amountPaid,
      'payment_method': paymentMethod,
      'notes': notes,
      'paid_at': paidAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  DamageLossPaymentModel copyWith({
    String? id,
    String? incidentId,
    String? storeId,
    double? amountPaid,
    String? paymentMethod,
    String? notes,
    DateTime? paidAt,
    DateTime? createdAt,
  }) {
    return DamageLossPaymentModel(
      id: id ?? this.id,
      incidentId: incidentId ?? this.incidentId,
      storeId: storeId ?? this.storeId,
      amountPaid: amountPaid ?? this.amountPaid,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      notes: notes ?? this.notes,
      paidAt: paidAt ?? this.paidAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        incidentId,
        storeId,
        amountPaid,
        paymentMethod,
        notes,
        paidAt,
        createdAt,
      ];
}
