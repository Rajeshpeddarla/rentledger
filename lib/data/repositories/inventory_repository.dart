import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory_item_model.dart';
import 'lease_repository.dart';

class InventoryRepository {
  final SupabaseClient _client = Supabase.instance.client;
  final LeaseRepository? _leaseRepository;

  InventoryRepository([this._leaseRepository]);

  // In-memory cache for loaded items
  final List<InventoryItemModel> _items = [];

  Future<List<InventoryItemModel>> getItems({
    bool includeArchived = false,
  }) async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        var query = _client
            .from('inventory_items')
            .select()
            .eq('store_id', user.id);

        if (!includeArchived) {
          query = query.eq('is_archived', false);
        }

        final data = await query.order('created_at', ascending: false);

        // Fetch active leases count per item in realtime using exact quantity
        final Map<String, int> activeCounts = {};
        try {
          final activeLeasesData = await _client
              .from('leases')
              .select('item_id, quantity')
              .eq('store_id', user.id)
              .eq('status', 'active');

          for (final row in (activeLeasesData as List)) {
            final iId = row['item_id'] as String?;
            final qty = (row['quantity'] as num?)?.toInt() ?? 1;
            if (iId != null) {
              activeCounts[iId] = (activeCounts[iId] ?? 0) + qty;
            }
          }
        } catch (e) {
          debugPrint('InventoryRepository active lease count error: $e');
        }

        final list = (data as List)
            .map((e) {
              final it = InventoryItemModel.fromJson(e as Map<String, dynamic>);
              final count = activeCounts[it.id] ?? 0;
              return it.copyWith(activeLeasesCount: count);
            })
            .toList();

        _items.clear();
        _items.addAll(list);
        return list;
      } catch (e) {
        debugPrint('InventoryRepository.getItems error: $e');
      }
    }

    // Local in-memory update with active leases if offline
    if (_leaseRepository != null) {
      try {
        final activeLeases = await _leaseRepository.getLeases(status: 'active');
        final Map<String, int> counts = {};
        for (final l in activeLeases) {
          counts[l.itemId] = (counts[l.itemId] ?? 0) + l.quantity;
        }
        return _items
            .where((item) => includeArchived ? true : !item.isArchived)
            .map((item) => item.copyWith(activeLeasesCount: counts[item.id] ?? 0))
            .toList();
      } catch (_) {}
    }

    return _items
        .where((item) => includeArchived ? true : !item.isArchived)
        .toList();
  }

  Future<InventoryItemModel?> getItemById(String id) async {
    final items = await getItems(includeArchived: true);
    try {
      return items.firstWhere((i) => i.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<InventoryItemModel> saveItem(
    InventoryItemModel item, {
    required bool isPro,
  }) async {
    // Check Free limit of 10 items
    if (!isPro) {
      final currentItems = await getItems(includeArchived: false);
      final isNew = !currentItems.any((i) => i.id == item.id);
      if (isNew && currentItems.length >= 10) {
        throw Exception(
            'FREE_ITEM_LIMIT_REACHED: Free tier is limited to 10 active items. Upgrade to Pro for unlimited inventory!');
      }
    }

    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        final payload = item.copyWith(storeId: user.id).toJson();
        final res = await _client
            .from('inventory_items')
            .upsert(payload)
            .select()
            .single();
        final saved = InventoryItemModel.fromJson(res);
        final index = _items.indexWhere((i) => i.id == saved.id);
        if (index >= 0) {
          _items[index] = saved;
        } else {
          _items.insert(0, saved);
        }
        return saved;
      } catch (e) {
        debugPrint('InventoryRepository.saveItem warning: $e');
      }
    }

    // Local in-memory update if offline
    final index = _items.indexWhere((i) => i.id == item.id);
    if (index >= 0) {
      _items[index] = item;
    } else {
      _items.insert(0, item);
    }
    return item;
  }

  Future<void> archiveItem(String id) async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        await _client
            .from('inventory_items')
            .update({'is_archived': true})
            .eq('id', id);
      } catch (e) {
        debugPrint('InventoryRepository.archiveItem warning: $e');
      }
    }

    final index = _items.indexWhere((i) => i.id == id);
    if (index >= 0) {
      _items[index] = _items[index].copyWith(isArchived: true);
    }
  }
}
