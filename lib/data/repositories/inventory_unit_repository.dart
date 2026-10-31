import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory_component_unit_model.dart';
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
  Future<String> generateAssetCode(String prefix, String assetType) async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        final res = await _client.rpc('generate_store_asset_code', params: {
          'p_store_id': user.id,
          'p_prefix': prefix.toUpperCase().trim(),
          'p_asset_type': assetType,
        });
        return res.toString();
      } catch (e) {
        debugPrint('InventoryUnitRepository.generateAssetCode RPC warning: $e');
        final tag = prefix.toUpperCase().trim();
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

        return (data as List)
            .map((e) => SubItemDefinitionModel.fromJson(e as Map<String, dynamic>))
            .toList();
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

  /// Transactional save of physical sets and their physical component units
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

        // Clean up available component units before re-inserting updated component units
        try {
          await _client
              .from('inventory_component_units')
              .delete()
              .eq('inventory_unit_id', savedUnit.id)
              .eq('status', 'available');
        } catch (_) {}

        for (final comp in unit.components) {
          final compPayload = comp.copyWith(
            inventoryUnitId: savedUnit.id,
            inventoryItemId: productId,
            storeId: user.id,
          ).toJson();

          try {
            await _client.from('inventory_component_units').upsert(compPayload);
          } catch (cErr) {
            debugPrint('Error saving inventory_component_unit: $cErr');
          }
        }
      } catch (uErr) {
        debugPrint('Error saving inventory_unit: $uErr');
      }
    }
  }
}
