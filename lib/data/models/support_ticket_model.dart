import 'package:equatable/equatable.dart';

class SupportTicketModel extends Equatable {
  final String id;
  final String storeId;
  final String storeName;
  final String userEmail;
  final String title;
  final String description;
  final String status; // 'open', 'processing', 'closed', 'reopened'
  final List<String> imageUrls;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SupportTicketModel({
    required this.id,
    required this.storeId,
    required this.storeName,
    required this.userEmail,
    required this.title,
    required this.description,
    this.status = 'open',
    this.imageUrls = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  String get timeAgoString {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inDays >= 365) {
      final years = (difference.inDays / 365).floor();
      return '$years ${years == 1 ? 'year' : 'years'} ago';
    } else if (difference.inDays >= 30) {
      final months = (difference.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    } else if (difference.inDays >= 1) {
      return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
    } else if (difference.inHours >= 1) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inMinutes >= 1) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    } else {
      return 'Just now';
    }
  }

  factory SupportTicketModel.fromJson(Map<String, dynamic> json) {
    return SupportTicketModel(
      id: json['id'] as String,
      storeId: json['store_id'] as String,
      storeName: json['store_name'] as String? ?? 'Store',
      userEmail: json['user_email'] as String? ?? 'Client',
      title: json['title'] as String? ?? 'Support Request',
      description: json['description'] as String? ?? '',
      status: json['status'] as String? ?? 'open',
      imageUrls: (json['image_urls'] as List?)?.map((e) => e.toString()).toList() ?? [],
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'store_id': storeId,
      'store_name': storeName,
      'user_email': userEmail,
      'title': title,
      'description': description,
      'status': status,
      'image_urls': imageUrls,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  SupportTicketModel copyWith({
    String? id,
    String? storeId,
    String? storeName,
    String? userEmail,
    String? title,
    String? description,
    String? status,
    List<String>? imageUrls,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SupportTicketModel(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      storeName: storeName ?? this.storeName,
      userEmail: userEmail ?? this.userEmail,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      imageUrls: imageUrls ?? this.imageUrls,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        storeId,
        storeName,
        userEmail,
        title,
        description,
        status,
        imageUrls,
        createdAt,
        updatedAt,
      ];
}
