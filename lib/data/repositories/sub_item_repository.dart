import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/sub_item_model.dart';

class SubItemRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // In-memory fallback cache
  final List<SubItemModel> _subItems = [];

  Future<List<SubItemModel>> getSubItems({
    required String parentItemId,
    String? status,
  }) async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        var query = _client
            .from('sub_items')
            .select()
            .eq('parent_item_id', parentItemId)
            .eq('store_id', user.id);

        if (status != null && status != 'all') {
          query = query.eq('status', status);
        }

        final data = await query.order('created_at', ascending: true);
        final list = (data as List)
            .map((e) => SubItemModel.fromJson(e as Map<String, dynamic>))
            .toList();

        // Update cache for parent item
        _subItems.removeWhere((s) => s.parentItemId == parentItemId);
        _subItems.addAll(list);
        return list;
      } catch (e) {
        debugPrint('SubItemRepository.getSubItems warning: $e');
      }
    }

    return _subItems.where((s) {
      if (s.parentItemId != parentItemId) return false;
      if (status != null && status != 'all' && s.status != status) return false;
      return true;
    }).toList();
  }

  Future<SubItemModel> saveSubItem(SubItemModel subItem) async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        final payload = subItem.copyWith(storeId: user.id).toJson();
        final res = await _client
            .from('sub_items')
            .upsert(payload)
            .select()
            .single();
        final saved = SubItemModel.fromJson(res);
        final index = _subItems.indexWhere((s) => s.id == saved.id);
        if (index >= 0) {
          _subItems[index] = saved;
        } else {
          _subItems.add(saved);
        }
        return saved;
      } catch (e) {
        debugPrint('SubItemRepository.saveSubItem warning: $e');
      }
    }

    final index = _subItems.indexWhere((s) => s.id == subItem.id);
    if (index >= 0) {
      _subItems[index] = subItem;
    } else {
      _subItems.add(subItem);
    }
    return subItem;
  }

  Future<void> updateSubItemStatus({
    required String subItemId,
    required String newStatus,
    String? notes,
  }) async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        final updatePayload = <String, dynamic>{
          'status': newStatus,
          'updated_at': DateTime.now().toIso8601String(),
        };
        if (notes != null) updatePayload['notes'] = notes;

        await _client
            .from('sub_items')
            .update(updatePayload)
            .eq('id', subItemId);
      } catch (e) {
        debugPrint('SubItemRepository.updateSubItemStatus warning: $e');
      }
    }

    final index = _subItems.indexWhere((s) => s.id == subItemId);
    if (index >= 0) {
      _subItems[index] = _subItems[index].copyWith(
        status: newStatus,
        notes: notes ?? _subItems[index].notes,
        updatedAt: DateTime.now(),
      );
    }
  }

  Future<void> deleteSubItem(String subItemId) async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        await _client.from('sub_items').delete().eq('id', subItemId);
      } catch (e) {
        debugPrint('SubItemRepository.deleteSubItem warning: $e');
      }
    }
    _subItems.removeWhere((s) => s.id == subItemId);
  }
}
