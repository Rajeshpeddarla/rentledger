import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory_item_model.dart';
import '../models/inventory_unit_model.dart';
import '../models/sub_item_definition_model.dart';

class InventoryUnitRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Fetch all physical units and their component units for a specific product definition
  Future<List<InventoryUnitModel>> getUnitsForProduct(String productId) async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        final data = await _client
            .from('inventory_units')
            .select('*, inventory_component_units(*)')
            .eq('inventory_item_id', productId)
            .eq('store_id', user.id)
            .order('created_at', ascending: true);

        return (data as List)
            .map((e) => InventoryUnitModel.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('InventoryUnitRepository.getUnitsForProduct error: $e');
      }
    }
    return [];
  }

  /// Generate concurrency-safe store asset code calling backend SQL function
  Future<String> generateAssetCode(String prefix, String assetType, {String? productId}) async {
    final user = _client.auth.currentUser;
    if (user != null) {
      final tag = prefix.toUpperCase().trim();

      // Query asset_code max index specifically for this product
      if (productId != null && productId.isNotEmpty) {
        try {
          final tableName = assetType == 'component_unit'
              ? 'inventory_component_units'
              : 'inventory_units';

          final existing = await _client
              .from(tableName)
              .select('asset_code')
              .eq('store_id', user.id)
              .eq('inventory_item_id', productId)
              .ilike('asset_code', '$tag-%')
              .order('created_at', ascending: false);

          int maxIndex = 0;
          for (final row in existing as List) {
            final code = row['asset_code'] as String? ?? '';
            final parts = code.split('-');
            if (parts.length >= 2) {
              final numPart = int.tryParse(parts.last) ?? 0;
              if (numPart > maxIndex) maxIndex = numPart;
            }
          }
          final nextNum = (maxIndex + 1).toString().padLeft(4, '0');
          return '$tag-$nextNum';
        } catch (e) {
          debugPrint('InventoryUnitRepository.generateAssetCode product query warning: $e');
        }
      }

      // Fallback per-store query
      try {
        final tableName = assetType == 'component_unit'
            ? 'inventory_component_units'
            : 'inventory_units';

        final existing = await _client
            .from(tableName)
            .select('asset_code')
            .eq('store_id', user.id)
            .ilike('asset_code', '$tag-%')
            .order('created_at', ascending: false)
            .limit(50);

        int maxIndex = 0;
        for (final row in existing as List) {
          final code = row['asset_code'] as String? ?? '';
          final parts = code.split('-');
          if (parts.length >= 2) {
            final numPart = int.tryParse(parts.last) ?? 0;
            if (numPart > maxIndex) maxIndex = numPart;
          }
        }
        final nextNum = (maxIndex + 1).toString().padLeft(4, '0');
        return '$tag-$nextNum';
      } catch (_) {
        final rand = DateTime.now().millisecondsSinceEpoch.toString().substring(8);
        return '$tag-$rand';
      }
    }
    return '${prefix.toUpperCase()}-0001';
  }

  /// Fetch component definitions template for a product
  Future<List<SubItemDefinitionModel>> getDefinitionsForProduct(String productId) async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        final data = await _client
            .from('sub_item_definitions')
            .select('*')
            .eq('parent_item_id', productId)
            .eq('store_id', user.id);

        final list = (data as List)
            .map((e) => SubItemDefinitionModel.fromJson(e as Map<String, dynamic>))
            .toList();

        // Deduplicate by componentName to guarantee exactly 1 definition per accessory
        final Map<String, SubItemDefinitionModel> uniqueMap = {};
        for (final def in list) {
          final key = def.componentName.trim().toLowerCase();
          if (!uniqueMap.containsKey(key)) {
            uniqueMap[key] = def;
          }
        }

        return uniqueMap.values.toList();
      } catch (e) {
        debugPrint('InventoryUnitRepository.getDefinitionsForProduct error: $e');
      }
    }
    return [];
  }

  /// Save component definitions template for a product
  Future<void> saveDefinitions({
    required String productId,
    required List<SubItemDefinitionModel> definitions,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      await _client.from('sub_item_definitions').delete().eq('parent_item_id', productId);
    } catch (_) {}

    for (final def in definitions) {
      final payload = def.copyWith(
        parentItemId: productId,
        storeId: user.id,
      ).toJson();

      try {
        await _client.from('sub_item_definitions').upsert(payload);
      } catch (e) {
        debugPrint('Error saving sub_item_definition: $e');
      }
    }
  }

  /// Batch update component name and damage/loss replacement cost across all physical sets in 1 DB request
  Future<void> updateComponentNameAndCost({
    required String productId,
    required String oldName,
    required String newName,
    required double newCost,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      // 1. Update sub_item_definitions template
      await _client
          .from('sub_item_definitions')
          .update({
            'component_name': newName,
            'replacement_cost': newCost,
          })
          .eq('parent_item_id', productId)
          .eq('store_id', user.id)
          .ilike('component_name', oldName);

      // 2. Single batch update on inventory_component_units across all physical sets (1 Request!)
      await _client
          .from('inventory_component_units')
          .update({
            'component_name': newName,
            'replacement_cost': newCost,
          })
          .eq('inventory_item_id', productId)
          .eq('store_id', user.id)
          .ilike('component_name', oldName);

      debugPrint('--> [BATCH COMPONENT UPDATE] Renamed "$oldName" to "$newName" ($newCost) across all units in 1 DB request.');
    } catch (e) {
      debugPrint('--> [BATCH COMPONENT UPDATE ERROR] $e');
    }
  }

  /// Delete component template and unrented component units for a product
  Future<void> deleteComponentFromProduct({
    required String productId,
    required String componentName,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      await _client
          .from('sub_item_definitions')
          .delete()
          .eq('parent_item_id', productId)
          .eq('store_id', user.id)
          .ilike('component_name', componentName);

      await _client
          .from('inventory_component_units')
          .delete()
          .eq('inventory_item_id', productId)
          .eq('store_id', user.id)
          .ilike('component_name', componentName)
          .neq('status', 'rented');

      debugPrint('--> [DELETE COMPONENT SUCCESS] Removed "$componentName" template and unrented units.');
    } catch (e) {
      debugPrint('--> [DELETE COMPONENT ERROR] $e');
    }
  }

  /// Delete unrented physical units if user decreased sets count
  Future<void> deleteExtraAvailableUnits({
    required String productId,
    required int targetCount,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      final existing = await getUnitsForProduct(productId);
      if (existing.length > targetCount) {
        final toRemove = existing.sublist(targetCount);
        for (final unit in toRemove) {
          if (unit.status == 'available') {
            await _client
                .from('inventory_component_units')
                .delete()
                .eq('inventory_unit_id', unit.id)
                .neq('status', 'rented');

            await _client
                .from('inventory_units')
                .delete()
                .eq('id', unit.id)
                .eq('status', 'available');

            debugPrint('--> [DELETE EXTRA SET SUCCESS] Removed unrented set ${unit.assetCode}');
          }
        }
      }
    } catch (e) {
      debugPrint('--> [DELETE EXTRA SET ERROR] $e');
    }
  }

  /// Transactional save of physical sets and their physical component units without deleting existing units
  Future<void> savePhysicalSets({
    required String productId,
    required List<InventoryUnitModel> units,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    for (final unit in units) {
      final unitPayload = unit.copyWith(
        inventoryItemId: productId,
        storeId: user.id,
      ).toJson();

      try {
        final unitRes = await _client.from('inventory_units').upsert(unitPayload).select().single();
        final savedUnit = InventoryUnitModel.fromJson(unitRes);

        for (final comp in unit.components) {
          final compPayload = comp.copyWith(
            inventoryUnitId: savedUnit.id,
            inventoryItemId: productId,
            storeId: user.id,
          ).toJson();

          try {
            await _client.from('inventory_component_units').upsert(compPayload, onConflict: 'id');
          } catch (cErr) {
            debugPrint('Error saving inventory_component_unit: $cErr');
          }
        }
      } catch (uErr) {
        debugPrint('Error saving inventory_unit: $uErr');
      }
    }
  }

  /// Single-request RPC transaction to save inventory item product, definitions, units, and components
  Future<void> saveInventoryItemTransaction({
    required InventoryItemModel item,
    required List<SubItemDefinitionModel> definitions,
    required List<InventoryUnitModel> units,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      final Map<String, dynamic> itemJson = item.copyWith(storeId: user.id).toJson();
      final List<Map<String, dynamic>> defsJson = definitions.map((d) => d.copyWith(storeId: user.id, parentItemId: item.id).toJson()).toList();

      final List<Map<String, dynamic>> unitsJson = [];
      for (final u in units) {
        final unitMap = u.copyWith(storeId: user.id, inventoryItemId: item.id).toJson();
        final List<Map<String, dynamic>> compsJson = u.components.map((c) => c.copyWith(storeId: user.id, inventoryItemId: item.id, inventoryUnitId: u.id).toJson()).toList();
        unitMap['components'] = compsJson;
        unitsJson.add(unitMap);
      }

      final Map<String, dynamic> fullPayload = {
        'item': itemJson,
        'definitions': defsJson,
        'units': unitsJson,
      };

      debugPrint('--> [SAVE INVENTORY RPC] Executing single-request transaction for item ${item.id}');
      final res = await _client.rpc('save_inventory_item_transaction', params: {
        'p_data': fullPayload,
      });

      debugPrint('--> [SAVE INVENTORY RPC SUCCESS] Inventory save transaction completed in 1 request: $res');
    } catch (e) {
      debugPrint('--> [SAVE INVENTORY RPC WARNING] Falling back to sequential save: $e');
      await saveDefinitions(productId: item.id, definitions: definitions);
      await savePhysicalSets(productId: item.id, units: units);
    }
  }
}
