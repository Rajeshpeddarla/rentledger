import 'package:equatable/equatable.dart';

class CustomerModel extends Equatable {
  final String id;
  final String storeId;
  final String name;
  final String phone;
  final String? email;
  final String? idProofR2Url;
  final String? notes;
  final int totalLeasesCount;
  final int loyaltyPoints; // Accumulated loyalty points (10 points = 1 unit currency)
  final DateTime createdAt;
  final DateTime updatedAt;

  const CustomerModel({
    required this.id,
    required this.storeId,
    required this.name,
    required this.phone,
    this.email,
    this.idProofR2Url,
    this.notes,
    this.totalLeasesCount = 0,
    this.loyaltyPoints = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isRepeatCustomer => totalLeasesCount > 1;

  /// Monetary value of loyalty points (10 points = 1 unit currency)
  double get loyaltyMonetaryValue => double.parse((loyaltyPoints * 0.10).toStringAsFixed(2));

  factory CustomerModel.fromJson(Map<String, dynamic> json) {
    return CustomerModel(
      id: json['id'] as String,
      storeId: json['store_id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String,
      email: json['email'] as String?,
      idProofR2Url: json['id_proof_r2_url'] as String?,
      notes: json['notes'] as String?,
      totalLeasesCount: json['total_leases_count'] as int? ?? 0,
      loyaltyPoints: json['loyalty_points'] as int? ?? 0,
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
      'store_id': storeId,
      'name': name,
      'phone': phone,
      'email': email,
      'id_proof_r2_url': idProofR2Url,
      'notes': notes,
      'total_leases_count': totalLeasesCount,
      'loyalty_points': loyaltyPoints,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  CustomerModel copyWith({
    String? id,
    String? storeId,
    String? name,
    String? phone,
    String? email,
    String? idProofR2Url,
    String? notes,
    int? totalLeasesCount,
    int? loyaltyPoints,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CustomerModel(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      idProofR2Url: idProofR2Url ?? this.idProofR2Url,
      notes: notes ?? this.notes,
      totalLeasesCount: totalLeasesCount ?? this.totalLeasesCount,
      loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        storeId,
        name,
        phone,
        email,
        idProofR2Url,
        notes,
        totalLeasesCount,
        loyaltyPoints,
        createdAt,
        updatedAt,
      ];
}
