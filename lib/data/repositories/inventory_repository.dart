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

        // Fetch active/reserved lease counts per item in realtime
        final Map<String, int> activeCounts = {};
        final Map<String, int> reservedCounts = {};

        try {
          // 1. Query lease_items table for item-level quantities in multi-item orders
          final leaseItemsData = await _client
              .from('lease_items')
              .select('item_id, quantity, return_status, leases!inner(status)')
              .eq('store_id', user.id)
              .or('return_status.eq.available,return_status.eq.active');

          for (final row in (leaseItemsData as List)) {
            final iId = row['item_id'] as String?;
            final qty = (row['quantity'] as num?)?.toInt() ?? 1;
            final leaseObj = row['leases'] as Map<String, dynamic>?;
            final st = leaseObj?['status'] as String?;
            if (iId != null) {
              if (st == 'active') {
                activeCounts[iId] = (activeCounts[iId] ?? 0) + qty;
              } else if (st == 'reserved' || st == 'upcoming') {
                reservedCounts[iId] = (reservedCounts[iId] ?? 0) + qty;
              }
            }
          }
        } catch (_) {
          // 2. Fallback to leases table if lease_items table is pending or offline
          try {
            final leasesData = await _client
                .from('leases')
                .select('item_id, quantity, status')
                .eq('store_id', user.id)
                .or('status.eq.active,status.eq.reserved,status.eq.upcoming');

            for (final row in (leasesData as List)) {
              final iId = row['item_id'] as String?;
              final qty = (row['quantity'] as num?)?.toInt() ?? 1;
              final st = row['status'] as String?;
              if (iId != null) {
                if (st == 'active') {
                  activeCounts[iId] = (activeCounts[iId] ?? 0) + qty;
                } else if (st == 'reserved' || st == 'upcoming') {
                  reservedCounts[iId] = (reservedCounts[iId] ?? 0) + qty;
                }
              }
            }
          } catch (e) {
            debugPrint('InventoryRepository active lease count error: $e');
          }
        }

        // 3. Query inventory_units table for realtime maintenance, in_maintenance, lost, and needed_restock counts per item
        final Map<String, int> maintenanceCounts = {};
        final Map<String, int> lostCounts = {};

        try {
          final unitStatusData = await _client
              .from('inventory_units')
              .select('inventory_item_id, status')
              .eq('store_id', user.id)
              .or('status.eq.damaged,status.eq.maintenance,status.eq.in_maintenance,status.eq.lost,status.eq.needed_restock');

          for (final row in (unitStatusData as List)) {
            final iId = row['inventory_item_id'] as String?;
            final st = (row['status'] as String? ?? '').toLowerCase();
            if (iId != null) {
              if (st == 'maintenance' || st == 'damaged' || st == 'in_maintenance') {
                maintenanceCounts[iId] = (maintenanceCounts[iId] ?? 0) + 1;
              } else if (st == 'lost' || st == 'needed_restock') {
                lostCounts[iId] = (lostCounts[iId] ?? 0) + 1;
              }
            }
          }
        } catch (e) {
          debugPrint('InventoryRepository unit status count error: $e');
        }

        final list = (data as List)
            .map((e) {
              final it = InventoryItemModel.fromJson(e as Map<String, dynamic>);
              final activeCount = activeCounts[it.id] ?? 0;
              final reservedCount = reservedCounts[it.id] ?? 0;
              final maintCount = maintenanceCounts[it.id] ?? 0;
              final lstCount = lostCounts[it.id] ?? 0;
              return it.copyWith(
                activeLeasesCount: activeCount,
                reservedCount: reservedCount,
                maintenanceCount: maintCount,
                lostCount: lstCount,
              );
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
        final payload = item.copyWith(storeId: user.id).toDatabaseJson();
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

  Future<InventoryItemModel> restockItem(String itemId, {int quantity = 1}) async {
    final item = await getItemById(itemId);
    if (item != null) {
      final newLost = (item.lostCount - quantity) < 0 ? 0 : (item.lostCount - quantity);
      final newMaintenance = (item.maintenanceCount - quantity) < 0 ? 0 : (item.maintenanceCount - quantity);
      final updated = item.copyWith(
        lostCount: newLost,
        maintenanceCount: newMaintenance,
        updatedAt: DateTime.now(),
      );
      return await saveItem(updated, isPro: true);
    }
    throw Exception('Item not found');
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

  /// Delete equipment item and all associated physical sets, components, and definitions
  Future<void> deleteItem(String id) async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        // 1. Unlink component unit references in leased_sub_items table
        try {
          await _client
              .from('leased_sub_items')
              .update({'inventory_component_unit_id': null})
              .eq('item_id', id);
        } catch (e) {
          debugPrint('deleteItem unbind leased_sub_items warning: $e');
        }

        // 2. Unlink or delete physical unit references in lease_item_units table
        try {
          await _client
              .from('lease_item_units')
              .delete()
              .eq('lease_item_id', id);
        } catch (_) {
          try {
            await _client
                .from('lease_item_units')
                .update({'inventory_unit_id': null})
                .eq('lease_item_id', id);
          } catch (e) {
            debugPrint('deleteItem unbind lease_item_units warning: $e');
          }
        }

        // 3. Delete component units
        try {
          await _client.from('inventory_component_units').delete().eq('inventory_item_id', id);
        } catch (e) {
          debugPrint('deleteItem component_units warning: $e');
        }

        // 4. Delete physical units
        try {
          await _client.from('inventory_units').delete().eq('inventory_item_id', id);
        } catch (e) {
          debugPrint('deleteItem inventory_units warning: $e');
        }

        // 5. Delete sub item definitions template & sub items
        try {
          await _client.from('sub_item_definitions').delete().eq('parent_item_id', id);
        } catch (_) {}

        try {
          await _client.from('sub_items').delete().eq('parent_item_id', id);
        } catch (_) {}

        // 6. Delete main inventory item or archive if past lease contracts exist
        try {
          await _client.from('inventory_items').delete().eq('id', id);
          debugPrint('--> [DELETE ITEM SUCCESS] Equipment item permanently deleted: $id');
        } catch (itemErr) {
          debugPrint('--> [DELETE ITEM WARNING] Foreign key active on leases, marking as archived: $itemErr');
          await _client.from('inventory_items').update({'is_archived': true}).eq('id', id);
        }
      } catch (e) {
        debugPrint('InventoryRepository.deleteItem error: $e');
        throw Exception('Failed to delete equipment item: $e');
      }
    }

    _items.removeWhere((i) => i.id == id);
  }
}
