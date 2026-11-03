import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/lease_item_model.dart';
import '../models/lease_model.dart';
import '../models/leased_sub_item_model.dart';

class LeaseRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // In-memory cache for dynamic leases
  final List<LeaseModel> _leases = [];

  Future<List<LeaseModel>> getLeases({String? status, String? itemId}) async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        var query = _client
            .from('leases')
            .select('*, inventory_items(*), customers(*), lease_items(*, inventory_items(*), leased_sub_items(*))')
            .eq('store_id', user.id);

        if (status != null && status != 'all') {
          query = query.eq('status', status);
        }
        if (itemId != null) {
          query = query.eq('item_id', itemId);
        }

        final data = await query.order('start_time', ascending: false);
        final list = (data as List)
            .map((e) => LeaseModel.fromJson(e as Map<String, dynamic>))
            .toList();

        _leases.clear();
        _leases.addAll(list);
        return list;
      } catch (e) {
        // Fallback without leased_sub_items join if table is pending schema cache
        try {
          var fallbackQuery = _client
              .from('leases')
              .select('*, inventory_items(*), customers(*), lease_items(*, inventory_items(*))')
              .eq('store_id', user.id);

          if (status != null && status != 'all') {
            fallbackQuery = fallbackQuery.eq('status', status);
          }
          if (itemId != null) {
            fallbackQuery = fallbackQuery.eq('item_id', itemId);
          }

          final data = await fallbackQuery.order('start_time', ascending: false);
          final list = (data as List)
              .map((e) => LeaseModel.fromJson(e as Map<String, dynamic>))
              .toList();

          _leases.clear();
          _leases.addAll(list);
          return list;
        } catch (fErr) {
          // Fallback 2: fetch lease_items without embedding inventory_items inside lease_items if FK is missing
          try {
            var fallbackQuery2 = _client
                .from('leases')
                .select('*, inventory_items(*), customers(*), lease_items(*)')
                .eq('store_id', user.id);

            if (status != null && status != 'all') {
              fallbackQuery2 = fallbackQuery2.eq('status', status);
            }
            if (itemId != null) {
              fallbackQuery2 = fallbackQuery2.eq('item_id', itemId);
            }

            final data = await fallbackQuery2.order('start_time', ascending: false);
            final list = (data as List)
                .map((e) => LeaseModel.fromJson(e as Map<String, dynamic>))
                .toList();

            _leases.clear();
            _leases.addAll(list);
            return list;
          } catch (fErr2) {
            // Fallback 3: basic leases query with direct inventory_items & customers
            try {
              var fallbackQuery3 = _client
                  .from('leases')
                  .select('*, inventory_items(*), customers(*)')
                  .eq('store_id', user.id);

              if (status != null && status != 'all') {
                fallbackQuery3 = fallbackQuery3.eq('status', status);
              }
              if (itemId != null) {
                fallbackQuery3 = fallbackQuery3.eq('item_id', itemId);
              }

              final data = await fallbackQuery3.order('start_time', ascending: false);
              final list = (data as List)
                  .map((e) => LeaseModel.fromJson(e as Map<String, dynamic>))
                  .toList();

              _leases.clear();
              _leases.addAll(list);
              return list;
            } catch (fErr3) {
              debugPrint('LeaseRepository.getLeases error: $fErr3');
            }
          }
        }
      }
    }

    // Local in-memory filter if offline
    return _leases.where((l) {
      if (status != null && status != 'all' && l.status != status) return false;
      if (itemId != null && l.itemId != itemId) return false;
      return true;
    }).toList();
  }

  /// Real-Time Conflict Validator Formula (Section 4.2):
  /// (NewStart < ExistingExpectedEnd) AND (NewEnd > ExistingStart)
  Future<bool> hasDateConflict({
    required String itemId,
    required DateTime startTime,
    required DateTime expectedEndTime,
    required int totalQuantity,
    int requestedQuantity = 1,
    String? excludeLeaseId,
  }) async {
    final effectiveTotalQty = totalQuantity <= 0 ? 1 : totalQuantity;

    // For immediate active dispatches (starting now or within 15 mins), if requested quantity is <= total owned sets, allow dispatch
    final isImmediateDispatch = startTime.isBefore(DateTime.now().add(const Duration(minutes: 15)));
    if (isImmediateDispatch && requestedQuantity <= effectiveTotalQty) {
      return false;
    }

    final activeLeases = await getLeases(itemId: itemId);

    final totalOverlapping = activeLeases.where((l) {
      if (excludeLeaseId != null && l.id == excludeLeaseId) return false;
      // Ignore returned or canceled leases
      if (l.status == 'returned' || l.status == 'canceled' || l.actualReturnTime != null) return false;
      if (l.status != 'active' && l.status != 'upcoming' && l.status != 'reserved') return false;

      // Overlap condition
      final overlap =
          startTime.isBefore(l.expectedEndTime) && expectedEndTime.isAfter(l.startTime);
      return overlap;
    }).fold<int>(0, (sum, l) => sum + l.quantity);

    return (totalOverlapping + requestedQuantity) > effectiveTotalQty;
  }

  /// Create new lease order with line items, leased sub-items, free quota check & conflict validator
  Future<LeaseModel> createLease(
    LeaseModel lease, {
    required bool isPro,
    required int totalItemQuantity,
  }) async {
    // 1. Free Quota Check (Max 500 leases/month)
    if (!isPro) {
      final allLeases = await getLeases();
      final now = DateTime.now();
      final monthlyCount = allLeases.where((l) =>
          l.createdAt.month == now.month && l.createdAt.year == now.year).length;
      if (monthlyCount >= 500) {
        throw Exception(
            'FREE_LEASE_LIMIT_REACHED: Free tier is limited to 500 leases per month. Upgrade to Pro for unlimited leases!');
      }
    }

    // 2. Date Conflict Check for primary item
    final isBlocked = await hasDateConflict(
      itemId: lease.itemId,
      startTime: lease.startTime,
      expectedEndTime: lease.expectedEndTime,
      totalQuantity: totalItemQuantity,
      requestedQuantity: lease.quantity,
      excludeLeaseId: lease.id,
    );

    if (isBlocked) {
      throw Exception(
          'ITEM_ALREADY_LEASED: All units of this item are already booked for the selected dates.');
    }

    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        final Map<String, dynamic> fullPayload = lease.copyWith(storeId: user.id).toDatabaseJson();

        // Convert leaseItems & leasedSubItems into nested JSON for single RPC transaction
        final List<Map<String, dynamic>> itemsJson = [];
        for (final line in lease.leaseItems) {
          final lineMap = line.copyWith(leaseId: lease.id, storeId: user.id).toJson();
          final List<Map<String, dynamic>> subItemsJson = [];
          for (final sub in line.leasedSubItems) {
            final subMap = sub.copyWith(leaseId: lease.id, leaseItemId: line.id, storeId: user.id).toDatabaseJson();
            if (sub.leaseItemUnitId != null) subMap['lease_item_unit_id'] = sub.leaseItemUnitId;
            if (sub.inventoryComponentUnitId != null) subMap['inventory_component_unit_id'] = sub.inventoryComponentUnitId;
            subItemsJson.add(subMap);
          }
          lineMap['leased_sub_items'] = subItemsJson;
          itemsJson.add(lineMap);
        }
        fullPayload['lease_items'] = itemsJson;

        debugPrint('--> [CREATE LEASE RPC] Executing single-request transaction for lease ${lease.id}');
        final res = await _client.rpc('create_lease_transaction', params: {
          'p_lease': fullPayload,
        });

        debugPrint('--> [CREATE LEASE RPC SUCCESS] Transaction completed in 1 request: $res');
        return lease;
      } catch (rpcErr) {
        debugPrint('--> [CREATE LEASE RPC WARNING] Falling back to sequential execution: $rpcErr');
      }

      String? insertedLeaseId;
      try {
        final payload = lease.copyWith(storeId: user.id).toDatabaseJson();
        debugPrint('--> [CREATE LEASE STEP 1] Inserting master lease into "leases" table: ${lease.id}');
        final res = await _client.from('leases').insert(payload).select().single();
        final created = LeaseModel.fromJson(res);
        insertedLeaseId = created.id;
        debugPrint('--> [CREATE LEASE STEP 1 SUCCESS] Master lease inserted: ID = ${created.id}');

        // Save line items to lease_items table and sub-items to leased_sub_items table
        final List<LeaseItemModel> savedLineItems = [];
        if (lease.leaseItems.isNotEmpty) {
          for (final line in lease.leaseItems) {
            final linePayload = line.copyWith(
              leaseId: created.id,
              storeId: user.id,
            ).toJson();

            debugPrint('--> [CREATE LEASE STEP 2] Inserting line item into "lease_items" table: ID = ${line.id}');
            final lineRes = await _client.from('lease_items').upsert(linePayload).select().single();
            final savedLine = LeaseItemModel.fromJson(lineRes);
            debugPrint('--> [CREATE LEASE STEP 2 SUCCESS] Line item inserted: ID = ${savedLine.id}');

            // Save leased sub-items if present & sync physical asset statuses
            final List<LeasedSubItemModel> savedSubItems = [];
            final Set<String> processedUnitIds = {};

            if (line.leasedSubItems.isNotEmpty) {
              // STEP 2.5: Create lease_item_units parent rows FIRST to satisfy leased_sub_items_lease_item_unit_id_fkey constraint
              for (final sub in line.leasedSubItems) {
                if (sub.leaseItemUnitId != null &&
                    sub.leaseItemUnitId!.isNotEmpty &&
                    processedUnitIds.add(sub.leaseItemUnitId!)) {
                  final unitPK = sub.leaseItemUnitId!;
                  debugPrint('--> [CREATE LEASE STEP 2.5] Upserting "lease_item_units" parent row: ID = $unitPK');
                  await _client.from('lease_item_units').upsert({
                    'id': unitPK,
                    'lease_id': created.id,
                    'lease_item_id': savedLine.id,
                    'inventory_unit_id': unitPK,
                    'checked_out_at': created.startTime.toIso8601String(),
                    'inspection_status': 'rented',
                  });
                  debugPrint('--> [CREATE LEASE STEP 2.5 SUCCESS] lease_item_units row created for unit $unitPK');

                  if (created.status == 'active') {
                    debugPrint('--> [CREATE LEASE STEP 2.6] Updating "inventory_units" status to rented: ID = $unitPK');
                    await _client
                        .from('inventory_units')
                        .update({'status': 'rented'})
                        .eq('id', unitPK);
                    debugPrint('--> [CREATE LEASE STEP 2.6 SUCCESS] inventory_units status set to rented for $unitPK');
                  }
                }
              }

              for (final sub in line.leasedSubItems) {
                final updatedSub = sub.copyWith(
                  leaseId: created.id,
                  leaseItemId: savedLine.id,
                  storeId: user.id,
                );
                final subPayload = updatedSub.toDatabaseJson();

                debugPrint('--> [CREATE LEASE STEP 3] Inserting sub-item into "leased_sub_items" table: ID = ${sub.id}');
                final subRes = await _client.from('leased_sub_items').upsert(subPayload).select().single();
                final savedSub = LeasedSubItemModel.fromJson(subRes).copyWith(
                  leaseItemUnitId: updatedSub.leaseItemUnitId,
                  inventoryComponentUnitId: updatedSub.inventoryComponentUnitId,
                  isExcluded: updatedSub.isExcluded,
                );
                savedSubItems.add(savedSub);
                debugPrint('--> [CREATE LEASE STEP 3 SUCCESS] Sub-item inserted: ID = ${savedSub.id}');

                if (created.status == 'active' && !updatedSub.isExcluded && updatedSub.inventoryComponentUnitId != null && updatedSub.inventoryComponentUnitId!.isNotEmpty) {
                  debugPrint('--> [CREATE LEASE STEP 3b] Updating "inventory_component_units" status to "rented": ID = ${updatedSub.inventoryComponentUnitId}');
                  await _client
                      .from('inventory_component_units')
                      .update({'status': 'rented'})
                      .eq('id', updatedSub.inventoryComponentUnitId!);
                  debugPrint('--> [CREATE LEASE STEP 3b SUCCESS] inventory_component_units updated to rented for ${updatedSub.inventoryComponentUnitId}');
                }
              }
            }

            savedLineItems.add(savedLine.copyWith(
              item: line.item,
              leasedSubItems: savedSubItems.isNotEmpty ? savedSubItems : line.leasedSubItems,
            ));
          }
        }

        final fullLease = created.copyWith(
          leaseItems: savedLineItems.isNotEmpty ? savedLineItems : lease.leaseItems,
          item: created.item ?? lease.item,
          customer: created.customer ?? lease.customer,
        );

        final index = _leases.indexWhere((l) => l.id == fullLease.id);
        if (index >= 0) {
          _leases[index] = fullLease;
        } else {
          _leases.insert(0, fullLease);
        }
        return fullLease;
      } catch (e) {
        debugPrint('LeaseRepository.createLease error: $e');
        // Atomic Rollback: Delete master lease record if any step fails
        if (insertedLeaseId != null) {
          try {
            debugPrint('--> [ROLLBACK] Deleting incomplete lease record: $insertedLeaseId');
            await _client.from('leases').delete().eq('id', insertedLeaseId);
            debugPrint('--> [ROLLBACK SUCCESS] Incomplete lease record deleted.');
          } catch (rollbackErr) {
            debugPrint('--> [ROLLBACK ERROR] Failed to rollback lease record: $rollbackErr');
          }
        }

        if (e.toString().contains('leases_status_check') && lease.status == 'reserved') {
          try {
            final retryLease = lease.copyWith(status: 'upcoming');
            final payload = retryLease.copyWith(storeId: user.id).toDatabaseJson();
            final res = await _client.from('leases').insert(payload).select().single();
            final created = LeaseModel.fromJson(res);
            final fullLease = created.copyWith(
              leaseItems: lease.leaseItems,
              item: created.item ?? lease.item,
              customer: created.customer ?? lease.customer,
              status: 'reserved',
            );
            _leases.insert(0, fullLease);
            return fullLease;
          } catch (retryErr) {
            throw Exception('Database lease creation failed: $retryErr');
          }
        }
        throw Exception('Database lease creation failed: $e');
      }
    }

    _leases.insert(0, lease);
    return lease;
  }

  /// Take Back / Settlement Update for Lease Order, Line Items, Leased Sub-Items and Inventory Asset Statuses
  Future<LeaseModel> returnAndSettleLease(LeaseModel lease) async {
    final updated = lease.copyWith(
      status: 'returned',
      actualReturnTime: lease.actualReturnTime ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        debugPrint('--> [SETTLE STEP 1] Updating master lease in "leases" table: ${updated.id}');
        await _client
            .from('leases')
            .update(updated.toDatabaseJson())
            .eq('id', updated.id);

        final Map<String, String> unitFinalStatusMap = {};

        for (final line in updated.leaseItems) {
          try {
            debugPrint('--> [SETTLE STEP 2] Updating line item in "lease_items" table: ID = ${line.id}');
            await _client
                .from('lease_items')
                .update(line.toJson())
                .eq('id', line.id);

            for (final sub in line.leasedSubItems) {
              try {
                debugPrint('--> [SETTLE STEP 3] Updating sub-item in "leased_sub_items" table: ID = ${sub.id}');
                await _client
                    .from('leased_sub_items')
                    .update(sub.toDatabaseJson())
                    .eq('id', sub.id);

                final subStatus = sub.conditionStatus.toLowerCase();
                final targetStatus = (subStatus == 'maintenance' || subStatus == 'damaged')
                    ? 'maintenance'
                    : (subStatus == 'lost' ? 'lost' : 'available');

                // Aggregate unit status (maintenance/damaged > lost > available)
                final unitId = sub.leaseItemUnitId;
                if (unitId != null && unitId.isNotEmpty) {
                  final currUnitSt = unitFinalStatusMap[unitId] ?? 'available';
                  if (targetStatus == 'maintenance') {
                    unitFinalStatusMap[unitId] = 'maintenance';
                  } else if (targetStatus == 'lost' && currUnitSt != 'maintenance') {
                    unitFinalStatusMap[unitId] = 'lost';
                  } else if (!unitFinalStatusMap.containsKey(unitId)) {
                    unitFinalStatusMap[unitId] = 'available';
                  }
                }

                // 1. Sync status to inventory_component_units table!
                if (sub.inventoryComponentUnitId != null && sub.inventoryComponentUnitId!.isNotEmpty) {
                  try {
                    await _client
                        .from('inventory_component_units')
                        .update({'status': targetStatus, 'updated_at': DateTime.now().toIso8601String()})
                        .eq('id', sub.inventoryComponentUnitId!);
                    debugPrint('--> [SETTLE STEP 4 SUCCESS] inventory_component_units ${sub.inventoryComponentUnitId} -> $targetStatus');
                  } catch (cErr) {
                    debugPrint('--> [SETTLE STEP 4 WARNING] inventory_component_units error: $cErr');
                  }
                } else if (sub.subItemId.isNotEmpty) {
                  try {
                    await _client
                        .from('inventory_component_units')
                        .update({'status': targetStatus, 'updated_at': DateTime.now().toIso8601String()})
                        .eq('id', sub.subItemId);
                    debugPrint('--> [SETTLE STEP 4 BY SUBITEMID SUCCESS] inventory_component_units ${sub.subItemId} -> $targetStatus');
                  } catch (cErr1) {
                    debugPrint('--> [SETTLE STEP 4 BY SUBITEMID WARNING] $cErr1');
                  }
                } else if (sub.leaseItemUnitId != null && sub.leaseItemUnitId!.isNotEmpty) {
                  try {
                    await _client
                        .from('inventory_component_units')
                        .update({'status': targetStatus, 'updated_at': DateTime.now().toIso8601String()})
                        .eq('inventory_unit_id', sub.leaseItemUnitId!)
                        .ilike('component_name', sub.itemName);
                    debugPrint('--> [SETTLE STEP 4 FALLBACK SUCCESS] inventory_component_units for ${sub.itemName} -> $targetStatus');
                  } catch (cErr2) {
                    debugPrint('--> [SETTLE STEP 4 FALLBACK WARNING] $cErr2');
                  }
                }
              } catch (subErr) {
                debugPrint('LeaseRepository.returnAndSettleLease leased_sub_items update warning: $subErr');
              }
            }
          } catch (lineErr) {
            debugPrint('LeaseRepository.returnAndSettleLease line item update warning: $lineErr');
          }
        }

        // 2. Batch update physical unit statuses in inventory_units and lease_item_units table
        final returnTimeStr = (updated.actualReturnTime ?? DateTime.now()).toIso8601String();

        try {
          final assignedUnitsRes = await _client
              .from('lease_item_units')
              .select('inventory_unit_id')
              .eq('lease_id', updated.id);

          for (final row in assignedUnitsRes as List) {
            final uId = row['inventory_unit_id'] as String?;
            if (uId != null && uId.isNotEmpty) {
              final compRes = await _client
                  .from('inventory_component_units')
                  .select('status')
                  .eq('inventory_unit_id', uId);

              final List<String> cStatuses = (compRes as List)
                  .map((c) => (c['status'] as String? ?? 'available').toLowerCase())
                  .toList();

              String finalUStatus = 'available';
              if (cStatuses.any((s) => s == 'maintenance' || s == 'damaged')) {
                finalUStatus = 'maintenance';
              } else if (cStatuses.any((s) => s == 'lost')) {
                finalUStatus = 'lost';
              } else if (unitFinalStatusMap.containsKey(uId)) {
                finalUStatus = unitFinalStatusMap[uId]!;
              }

              await _client
                  .from('inventory_units')
                  .update({'status': finalUStatus, 'updated_at': DateTime.now().toIso8601String()})
                  .eq('id', uId);

              debugPrint('--> [SETTLE UNIT SYNC SUCCESS] Physical unit $uId status set to $finalUStatus');
            }
          }
        } catch (uSyncErr) {
          debugPrint('--> [SETTLE UNIT SYNC WARNING] $uSyncErr');
        }

        // 3. Always close ALL remaining active lease_item_units records for this lease
        try {
          await _client
              .from('lease_item_units')
              .update({
                'returned_at': returnTimeStr,
                'inspection_status': 'inspected_good',
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('lease_id', updated.id)
              .isFilter('returned_at', null);
          debugPrint('--> [SETTLE STEP 6 SUCCESS] All lease_item_units closed with returned_at = $returnTimeStr');
        } catch (closeErr) {
          debugPrint('--> [SETTLE STEP 6 WARNING] lease_item_units close error: $closeErr');
        }

        final index = _leases.indexWhere((l) => l.id == updated.id);
        if (index >= 0) {
          _leases[index] = updated;
        } else {
          _leases.insert(0, updated);
        }
        return updated;
      } catch (e) {
        debugPrint('LeaseRepository.returnAndSettleLease warning: $e');
      }
    }

    final index = _leases.indexWhere((l) => l.id == updated.id);
    if (index >= 0) {
      _leases[index] = updated;
    } else {
      _leases.insert(0, updated);
    }
    return updated;
  }

  /// Cancel a reserved/active lease order, record refund notes, and release physical units
  Future<void> cancelLease({
    required String leaseId,
    required String cancellationNotes,
    required double refundAmount,
  }) async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        await _client
            .from('leases')
            .update({
              'status': 'cancelled',
              'return_notes': cancellationNotes,
              'final_settlement_balance': refundAmount,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', leaseId);

        // Update line items return status
        try {
          await _client
              .from('lease_items')
              .update({'return_status': 'cancelled', 'updated_at': DateTime.now().toIso8601String()})
              .eq('lease_id', leaseId);
        } catch (_) {}

        // Update lease_item_units inspection status
        try {
          await _client
              .from('lease_item_units')
              .update({'inspection_status': 'cancelled', 'returned_at': DateTime.now().toIso8601String()})
              .eq('lease_id', leaseId);
        } catch (_) {}

        // Release physical units in inventory_units
        try {
          final unitsRes = await _client
              .from('lease_item_units')
              .select('inventory_unit_id')
              .eq('lease_id', leaseId);

          for (final row in (unitsRes as List)) {
            final uId = row['inventory_unit_id'] as String?;
            if (uId != null && uId.isNotEmpty) {
              await _client
                  .from('inventory_units')
                  .update({'status': 'available', 'updated_at': DateTime.now().toIso8601String()})
                  .eq('id', uId);
            }
          }
        } catch (uErr) {
          debugPrint('cancelLease release inventory_units warning: $uErr');
        }

        // Release component units in inventory_component_units
        try {
          final subCompsRes = await _client
              .from('leased_sub_items')
              .select('inventory_component_unit_id')
              .eq('lease_id', leaseId);

          for (final row in (subCompsRes as List)) {
            final compId = row['inventory_component_unit_id'] as String?;
            if (compId != null && compId.isNotEmpty) {
              await _client
                  .from('inventory_component_units')
                  .update({'status': 'available', 'updated_at': DateTime.now().toIso8601String()})
                  .eq('id', compId);
            }
          }
        } catch (cErr) {
          debugPrint('cancelLease release inventory_component_units warning: $cErr');
        }

        debugPrint('--> [CANCEL LEASE SUCCESS] Lease $leaseId cancelled successfully');
      } catch (e) {
        debugPrint('LeaseRepository.cancelLease error: $e');
        throw Exception('Failed to cancel lease: $e');
      }
    }

    final index = _leases.indexWhere((l) => l.id == leaseId);
    if (index >= 0) {
      _leases[index] = _leases[index].copyWith(
        status: 'cancelled',
        returnNotes: cancellationNotes,
        finalSettlementBalance: refundAmount,
      );
    }
  }
}
