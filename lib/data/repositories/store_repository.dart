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
      final payload = store.copyWith(id: user.id).toDatabaseJson();
      try {
        // Try direct update first (matches FOR UPDATE RLS policy)
        final updateData = await _client
            .from('stores')
            .update(payload)
            .eq('id', user.id)
            .select();

        if (updateData != null && (updateData as List).isNotEmpty) {
          _cachedStore = StoreModel.fromJson((updateData as List).first as Map<String, dynamic>);
          return _cachedStore!;
        }

        // Fallback to insert if store record does not exist yet
        final insertRes = await _client
            .from('stores')
            .insert(payload)
            .select()
            .single();

        _cachedStore = StoreModel.fromJson(insertRes);
        return _cachedStore!;
      } catch (e) {
        debugPrint('StoreRepository.createOrUpdateStore error: $e');

        try {
          final res = await _client
              .from('stores')
              .upsert(payload)
              .select()
              .single();
          _cachedStore = StoreModel.fromJson(res);
          return _cachedStore!;
        } catch (uErr) {
          debugPrint('StoreRepository.createOrUpdateStore upsert fallback warning: $uErr');
        }
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

  /// Permanently delete guest store data and sign out
  Future<void> deleteGuestStoreAndAccount() async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        // Delete store profile & cascading data (leases, items, units, customers)
        await _client.from('stores').delete().eq('id', user.id);
        _cachedStore = null;
        debugPrint('--> [DELETE GUEST STORE] Store profile $user.id deleted from DB');
      } catch (e) {
        debugPrint('StoreRepository.deleteGuestStoreAndAccount DB error: $e');
      }

      try {
        await _client.auth.signOut();
      } catch (aErr) {
        debugPrint('StoreRepository.deleteGuestStoreAndAccount auth signOut note: $aErr');
      }
    }
  }
}
