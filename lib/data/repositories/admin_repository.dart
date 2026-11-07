import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/category_model.dart';
import '../models/customer_model.dart';
import '../models/discount_model.dart';
import '../models/inventory_item_model.dart';
import '../models/inventory_unit_model.dart';
import '../models/lease_model.dart';
import '../models/store_model.dart';

class AdminLeaseOverview {
  final LeaseModel lease;
  final String storeName;

  const AdminLeaseOverview({required this.lease, required this.storeName});
}

class AdminEquipmentOverview {
  final InventoryItemModel item;
  final String storeName;
  final int totalUnits;
  final int availableUnits;
  final int rentedUnits;
  final int maintenanceUnits;

  const AdminEquipmentOverview({
    required this.item,
    required this.storeName,
    this.totalUnits = 0,
    this.availableUnits = 0,
    this.rentedUnits = 0,
    this.maintenanceUnits = 0,
  });
}

class PackageLimitsModel {
  final String proMonthlyPrice;
  final int freeItemsLimit;
  final int freeMonthlyLeasesLimit;
  final int freePhotosLimit;
  final int proPhotosLimit;

  const PackageLimitsModel({
    this.proMonthlyPrice = '₹349',
    this.freeItemsLimit = 10,
    this.freeMonthlyLeasesLimit = 100,
    this.freePhotosLimit = 3,
    this.proPhotosLimit = 6,
  });
}

class AdminSystemMetrics {
  final int totalStores;
  final int totalLeases;
  final int totalItems;
  final int totalUnits;
  final int totalComponents;
  final int activeSupportTickets;
  final int proStoresCount;
  final int freeStoresCount;

  const AdminSystemMetrics({
    this.totalStores = 0,
    this.totalLeases = 0,
    this.totalItems = 0,
    this.totalUnits = 0,
    this.totalComponents = 0,
    this.activeSupportTickets = 0,
    this.proStoresCount = 0,
    this.freeStoresCount = 0,
  });
}

class AdminStoreDetail {
  final StoreModel store;
  final List<InventoryItemModel> items;
  final List<InventoryUnitModel> units;
  final List<CustomerModel> customers;
  final List<CategoryModel> categories;
  final List<DiscountModel> discounts;
  final int totalLeasesCount;

  const AdminStoreDetail({
    required this.store,
    this.items = const [],
    this.units = const [],
    this.customers = const [],
    this.categories = const [],
    this.discounts = const [],
    this.totalLeasesCount = 0,
  });
}

class AdminRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Fetch overall system metrics across all stores
  Future<AdminSystemMetrics> getSystemMetrics() async {
    try {
      final storesRes = await _client.from('stores').select('id, plan_tier');
      final totalStores = (storesRes as List).length;

      int proCount = 0;
      int freeCount = 0;
      for (final row in (storesRes as List)) {
        final tier = row['plan_tier'] as String? ?? 'free';
        if (tier.contains('pro')) {
          proCount++;
        } else {
          freeCount++;
        }
      }

      int leasesCount = 0;
      try {
        final leasesRes = await _client.from('leases').select('id');
        leasesCount = (leasesRes as List).length;
      } catch (_) {}

      int itemsCount = 0;
      try {
        final itemsRes = await _client.from('inventory_items').select('id');
        itemsCount = (itemsRes as List).length;
      } catch (_) {}

      int unitsCount = 0;
      try {
        final unitsRes = await _client.from('inventory_units').select('id');
        unitsCount = (unitsRes as List).length;
      } catch (_) {}

      int compsCount = 0;
      try {
        final compsRes = await _client.from('inventory_component_units').select('id');
        compsCount = (compsRes as List).length;
      } catch (_) {}

      int ticketsCount = 0;
      try {
        final ticketsRes = await _client
            .from('support_tickets')
            .select('id')
            .or('status.eq.open,status.eq.processing,status.eq.reopened');
        ticketsCount = (ticketsRes as List).length;
      } catch (_) {}

      return AdminSystemMetrics(
        totalStores: totalStores,
        totalLeases: leasesCount,
        totalItems: itemsCount,
        totalUnits: unitsCount,
        totalComponents: compsCount,
        activeSupportTickets: ticketsCount,
        proStoresCount: proCount,
        freeStoresCount: freeCount,
      );
    } catch (e) {
      debugPrint('AdminRepository.getSystemMetrics error: $e');
      return const AdminSystemMetrics();
    }
  }

  /// Fetch all stores in system
  Future<List<StoreModel>> getAllStores() async {
    try {
      final data = await _client
          .from('stores')
          .select()
          .order('created_at', ascending: false);

      return (data as List)
          .map((e) => StoreModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('AdminRepository.getAllStores error: $e');
      return [];
    }
  }

  /// Toggle store account suspension (enable / disable store)
  Future<void> toggleStoreSuspension(String storeId, bool isSuspended) async {
    await _client.from('stores').update({
      'is_suspended': isSuspended,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', storeId);
  }

  /// Update store subscription plan tier ('free', 'pro_monthly', 'pro_annual')
  Future<void> updateStorePlanTier(String storeId, String newTier) async {
    final expiresAt = newTier.contains('pro')
        ? DateTime.now().add(newTier == 'pro_annual' ? const Duration(days: 365) : const Duration(days: 30))
        : null;

    await _client.from('stores').update({
      'plan_tier': newTier,
      'subscription_expires_at': expiresAt?.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', storeId);
  }

  /// Fetch deep store details for admin inspection
  Future<AdminStoreDetail?> getStoreDeepDetails(String storeId) async {
    try {
      final storeRes = await _client.from('stores').select().eq('id', storeId).single();
      final store = StoreModel.fromJson(storeRes);

      final itemsRes = await _client.from('inventory_items').select().eq('store_id', storeId);
      final items = (itemsRes as List)
          .map((e) => InventoryItemModel.fromJson(e as Map<String, dynamic>))
          .toList();

      final unitsRes = await _client
          .from('inventory_units')
          .select('*, inventory_component_units(*)')
          .eq('store_id', storeId);
      final units = (unitsRes as List)
          .map((e) => InventoryUnitModel.fromJson(e as Map<String, dynamic>))
          .toList();

      final customersRes = await _client.from('customers').select().eq('store_id', storeId);
      final customers = (customersRes as List)
          .map((e) => CustomerModel.fromJson(e as Map<String, dynamic>))
          .toList();

      final categoriesRes = await _client.from('categories').select().eq('store_id', storeId);
      final categories = (categoriesRes as List)
          .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
          .toList();

      final discountsRes = await _client.from('discounts').select().eq('store_id', storeId);
      final discounts = (discountsRes as List)
          .map((e) => DiscountModel.fromJson(e as Map<String, dynamic>))
          .toList();

      int leaseCount = 0;
      try {
        final leasesRes = await _client.from('leases').select('id').eq('store_id', storeId);
        leaseCount = (leasesRes as List).length;
      } catch (_) {}

      return AdminStoreDetail(
        store: store,
        items: items,
        units: units,
        customers: customers,
        categories: categories,
        discounts: discounts,
        totalLeasesCount: leaseCount,
      );
    } catch (e) {
      debugPrint('AdminRepository.getStoreDeepDetails error: $e');
      return null;
    }
  }

  /// Fetch all system leases with store names
  Future<List<AdminLeaseOverview>> getAdminLeases() async {
    try {
      final stores = await getAllStores();
      final Map<String, String> storeNameMap = {for (final s in stores) s.id: s.businessName};

      final leasesRes = await _client
          .from('leases')
          .select('*, customers(*), inventory_items(*), lease_items(*, leased_sub_items(*))')
          .order('created_at', ascending: false);

      final List<AdminLeaseOverview> result = [];
      for (final row in (leasesRes as List)) {
        final lease = LeaseModel.fromJson(row as Map<String, dynamic>);
        final storeName = storeNameMap[lease.storeId] ?? 'Unknown Store';
        result.add(AdminLeaseOverview(lease: lease, storeName: storeName));
      }
      return result;
    } catch (e) {
      debugPrint('AdminRepository.getAdminLeases error: $e');
      return [];
    }
  }

  /// Fetch all system equipment items with live unit status summaries
  Future<List<AdminEquipmentOverview>> getAdminEquipment() async {
    try {
      final stores = await getAllStores();
      final Map<String, String> storeNameMap = {for (final s in stores) s.id: s.businessName};

      final itemsRes = await _client.from('inventory_items').select('*, inventory_units(*)');

      final List<AdminEquipmentOverview> result = [];
      for (final row in (itemsRes as List)) {
        final item = InventoryItemModel.fromJson(row as Map<String, dynamic>);
        final storeName = storeNameMap[item.storeId] ?? 'Store';

        final rawUnits = row['inventory_units'] as List? ?? [];
        int available = 0;
        int rented = 0;
        int maintenance = 0;

        for (final u in rawUnits) {
          final st = (u['status'] as String? ?? 'available').toLowerCase();
          if (st == 'rented') {
            rented++;
          } else if (st == 'maintenance' || st == 'damaged' || st == 'in_maintenance') {
            maintenance++;
          } else {
            available++;
          }
        }

        result.add(AdminEquipmentOverview(
          item: item,
          storeName: storeName,
          totalUnits: rawUnits.isNotEmpty ? rawUnits.length : item.totalQuantity,
          availableUnits: available,
          rentedUnits: rented,
          maintenanceUnits: maintenance,
        ));
      }
      return result;
    } catch (e) {
      debugPrint('AdminRepository.getAdminEquipment error: $e');
      return [];
    }
  }

  /// Fetch global system feature flags (enable_coupons, enable_loyalty)
  Future<Map<String, bool>> getSystemFeatureFlags() async {
    final Map<String, bool> flags = {
      'enable_coupons': false,
      'enable_loyalty': false,
    };

    try {
      final data = await _client.from('system_settings').select();
      for (final row in (data as List)) {
        final key = row['key'] as String?;
        final val = row['value'];
        if (key != null && val is bool) {
          flags[key] = val;
        }
      }
    } catch (e) {
      debugPrint('AdminRepository.getSystemFeatureFlags error: $e');
    }
    return flags;
  }

  /// Update a global system feature flag
  Future<void> updateSystemFeatureFlag(String key, bool enabled) async {
    try {
      final res = await _client.from('system_settings').update({
        'value': enabled,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('key', key).select();

      if ((res as List).isNotEmpty) {
        debugPrint('--> [SYSTEM SETTING] Updated $key to $enabled');
        return;
      }

      await _client.from('system_settings').upsert({
        'key': key,
        'value': enabled,
        'updated_at': DateTime.now().toIso8601String(),
      });
      debugPrint('--> [SYSTEM SETTING] Upserted $key to $enabled');
    } catch (e) {
      debugPrint('AdminRepository.updateSystemFeatureFlag error: $e');
      rethrow;
    }
  }

  /// Fetch system package limits and subscription pricing
  Future<PackageLimitsModel> getPackageLimits() async {
    try {
      final data = await _client.from('system_settings').select();
      String price = '₹349';
      int items = 10;
      int leases = 100;
      int freePhotos = 3;
      int proPhotos = 6;

      for (final row in (data as List)) {
        final key = row['key'] as String?;
        final textVal = row['value_text'] as String? ?? row['value']?.toString();

        if (key == 'pro_monthly_price' && textVal != null) price = textVal;
        if (key == 'free_items_limit' && textVal != null) items = int.tryParse(textVal) ?? 10;
        if (key == 'free_monthly_leases_limit' && textVal != null) leases = int.tryParse(textVal) ?? 100;
        if (key == 'free_photos_limit' && textVal != null) freePhotos = int.tryParse(textVal) ?? 3;
        if (key == 'pro_photos_limit' && textVal != null) proPhotos = int.tryParse(textVal) ?? 6;
      }

      return PackageLimitsModel(
        proMonthlyPrice: price,
        freeItemsLimit: items,
        freeMonthlyLeasesLimit: leases,
        freePhotosLimit: freePhotos,
        proPhotosLimit: proPhotos,
      );
    } catch (e) {
      debugPrint('AdminRepository.getPackageLimits error: $e');
      return const PackageLimitsModel();
    }
  }

  /// Update system package limits and pricing
  Future<void> updatePackageLimits(PackageLimitsModel limits) async {
    final Map<String, String> map = {
      'pro_monthly_price': limits.proMonthlyPrice,
      'free_items_limit': limits.freeItemsLimit.toString(),
      'free_monthly_leases_limit': limits.freeMonthlyLeasesLimit.toString(),
      'free_photos_limit': limits.freePhotosLimit.toString(),
      'pro_photos_limit': limits.proPhotosLimit.toString(),
    };

    for (final entry in map.entries) {
      try {
        final res = await _client.from('system_settings').update({
          'value_text': entry.value,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('key', entry.key).select();

        if ((res as List).isNotEmpty) continue;

        await _client.from('system_settings').upsert({
          'key': entry.key,
          'value_text': entry.value,
          'value': false,
          'updated_at': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        debugPrint('updatePackageLimits error for ${entry.key}: $e');
      }
    }
  }
}
