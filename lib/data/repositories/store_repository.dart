import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/store_model.dart';

class StoreRepository {
  final SupabaseClient _client = Supabase.instance.client;

  StoreModel? _cachedStore;

  Future<StoreModel?> getStoreProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return null;
    }

    try {
      final data = await _client
          .from('stores')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (data != null) {
        _cachedStore = StoreModel.fromJson(data);
        return _cachedStore;
      }
    } catch (e) {
      debugPrint('StoreRepository.getStoreProfile error: $e');
    }

    return _cachedStore;
  }

  Future<StoreModel> createOrUpdateStore(StoreModel store) async {
    _cachedStore = store;
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        final res = await _client
            .from('stores')
            .upsert(store.toJson())
            .select()
            .single();
        _cachedStore = StoreModel.fromJson(res);
        return _cachedStore!;
      } catch (e) {
        debugPrint('StoreRepository.createOrUpdateStore warning: $e');
      }
    }
    return store;
  }

  Future<void> upgradePlanTier(String tier) async {
    if (_cachedStore != null) {
      _cachedStore = _cachedStore!.copyWith(
        planTier: tier,
        subscriptionExpiresAt: DateTime.now().add(
          tier == 'pro_annual' ? const Duration(days: 365) : const Duration(days: 30),
        ),
      );
    }
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        await _client.from('stores').update({
          'plan_tier': tier,
          'subscription_expires_at': _cachedStore?.subscriptionExpiresAt?.toIso8601String(),
        }).eq('id', user.id);
      } catch (e) {
        debugPrint('StoreRepository.upgradePlanTier note: $e');
      }
    }
  }
}
