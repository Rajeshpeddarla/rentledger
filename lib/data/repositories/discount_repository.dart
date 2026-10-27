import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/discount_model.dart';

class DiscountRepository {
  final SupabaseClient _client = Supabase.instance.client;

  final List<DiscountModel> _discounts = [];

  Future<List<DiscountModel>> getDiscounts({String? storeId}) async {
    final user = _client.auth.currentUser;
    final effectiveStoreId = storeId ?? user?.id;

    if (effectiveStoreId != null) {
      try {
        final data = await _client
            .from('discounts')
            .select()
            .eq('store_id', effectiveStoreId)
            .order('created_at', ascending: false);

        final list = (data as List)
            .map((e) => DiscountModel.fromJson(e as Map<String, dynamic>))
            .toList();

        _discounts.clear();
        _discounts.addAll(list);
        return List.from(_discounts);
      } catch (e) {
        debugPrint('DiscountRepository.getDiscounts warning: $e');
      }
    }
    return List.from(_discounts);
  }

  Future<DiscountModel> saveDiscount(DiscountModel discount) async {
    final user = _client.auth.currentUser;
    final effectiveStoreId = user?.id ?? discount.storeId;
    final payloadDiscount = discount.copyWith(storeId: effectiveStoreId);

    try {
      final res = await _client
          .from('discounts')
          .upsert(payloadDiscount.toJson())
          .select()
          .single();

      final saved = DiscountModel.fromJson(res);
      final index = _discounts.indexWhere((d) => d.id == saved.id);
      if (index >= 0) {
        _discounts[index] = saved;
      } else {
        _discounts.insert(0, saved);
      }
      return saved;
    } catch (e) {
      debugPrint('DiscountRepository.saveDiscount warning: $e');
    }

    final index = _discounts.indexWhere((d) => d.id == payloadDiscount.id);
    if (index >= 0) {
      _discounts[index] = payloadDiscount;
    } else {
      _discounts.insert(0, payloadDiscount);
    }
    return payloadDiscount;
  }

  Future<void> deleteDiscount(String id) async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        await _client.from('discounts').delete().eq('id', id);
      } catch (e) {
        debugPrint('DiscountRepository.deleteDiscount warning: $e');
      }
    }
    _discounts.removeWhere((d) => d.id == id);
  }
}
