import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory_item_history_model.dart';

class InventoryItemHistoryRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Log an audit event entry in inventory_item_history table
  Future<void> logHistory(InventoryItemHistoryModel history) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      final payload = history.copyWith(storeId: user.id).toJson();
      await _client.from('inventory_item_history').insert(payload);
      debugPrint('--> [AUDIT LOG SUCCESS] ${history.eventType} for item ${history.inventoryItemId}');
    } catch (e) {
      debugPrint('InventoryItemHistoryRepository.logHistory warning: $e');
    }
  }

  /// Get history timeline logs for a specific equipment item
  Future<List<InventoryItemHistoryModel>> getHistoryForItem(String productId) async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    try {
      final data = await _client
          .from('inventory_item_history')
          .select('*')
          .eq('inventory_item_id', productId)
          .eq('store_id', user.id)
          .order('created_at', ascending: false);

      return (data as List)
          .map((e) => InventoryItemHistoryModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('InventoryItemHistoryRepository.getHistoryForItem error: $e');
      return [];
    }
  }
}
