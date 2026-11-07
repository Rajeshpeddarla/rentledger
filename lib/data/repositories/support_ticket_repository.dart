import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/support_ticket_model.dart';

class SupportTicketRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Create a new support ticket
  Future<SupportTicketModel> createTicket({
    required String storeId,
    required String storeName,
    required String userEmail,
    required String title,
    required String description,
    List<String> imageUrls = const [],
  }) async {
    final payload = {
      'store_id': storeId,
      'store_name': storeName,
      'user_email': userEmail,
      'title': title,
      'description': description,
      'status': 'open',
      'image_urls': imageUrls,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    final res = await _client.from('support_tickets').insert(payload).select().single();
    return SupportTicketModel.fromJson(res);
  }

  /// Get support tickets submitted by current store
  Future<List<SupportTicketModel>> getTicketsForStore(String storeId) async {
    try {
      final data = await _client
          .from('support_tickets')
          .select()
          .eq('store_id', storeId)
          .order('created_at', ascending: false);

      return (data as List)
          .map((e) => SupportTicketModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('SupportTicketRepository.getTicketsForStore error: $e');
      return [];
    }
  }

  /// Admin method: Get all support tickets across system
  Future<List<SupportTicketModel>> getAllTicketsForAdmin() async {
    try {
      final data = await _client
          .from('support_tickets')
          .select()
          .order('created_at', ascending: false);

      return (data as List)
          .map((e) => SupportTicketModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('SupportTicketRepository.getAllTicketsForAdmin error: $e');
      return [];
    }
  }

  /// Update support ticket status ('open', 'processing', 'closed', 'reopened')
  Future<void> updateTicketStatus(String ticketId, String newStatus) async {
    await _client.from('support_tickets').update({
      'status': newStatus,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', ticketId);
  }
}
