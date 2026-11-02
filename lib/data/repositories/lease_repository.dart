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
    final activeLeases = await getLeases(itemId: itemId);
    final totalOverlapping = activeLeases.where((l) {
      if (excludeLeaseId != null && l.id == excludeLeaseId) return false;
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

                  debugPrint('--> [CREATE LEASE STEP 2.6] Updating "inventory_units" status to rented: ID = $unitPK');
                  await _client
                      .from('inventory_units')
                      .update({'status': 'rented'})
                      .eq('id', unitPK);
                  debugPrint('--> [CREATE LEASE STEP 2.6 SUCCESS] inventory_units status set to rented for $unitPK');
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

                if (!updatedSub.isExcluded && updatedSub.inventoryComponentUnitId != null && updatedSub.inventoryComponentUnitId!.isNotEmpty) {
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

  /// Take Back / Settlement Update for Lease Order, Line Items and Leased Sub-Items
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
        debugPrint('--> [SETTLE STEP 1 SUCCESS] Master lease updated to returned');

        if (updated.leaseItems.isNotEmpty) {
          for (final line in updated.leaseItems) {
            try {
              debugPrint('--> [SETTLE STEP 2] Updating line item in "lease_items" table: ID = ${line.id}');
              await _client
                  .from('lease_items')
                  .update(line.toJson())
                  .eq('id', line.id);
              debugPrint('--> [SETTLE STEP 2 SUCCESS] Line item updated: status = ${line.returnStatus}');

              if (line.leasedSubItems.isNotEmpty) {
                for (final sub in line.leasedSubItems) {
                  try {
                    debugPrint('--> [SETTLE STEP 3] Updating sub-item in "leased_sub_items" table: ID = ${sub.id}');
                    await _client
                        .from('leased_sub_items')
                        .update(sub.toDatabaseJson())
                        .eq('id', sub.id);
                    debugPrint('--> [SETTLE STEP 3 SUCCESS] Sub-item updated: status = ${sub.conditionStatus}');

                    // Sync physical asset states back upon return
                    final targetUnitStatus = sub.conditionStatus == 'maintenance'
                        ? 'maintenance'
                        : (sub.conditionStatus == 'lost' ? 'lost' : 'available');

                    if (sub.leaseItemUnitId != null && sub.leaseItemUnitId!.isNotEmpty) {
                      try {
                        debugPrint('--> [SETTLE STEP 4] Updating "lease_item_units": unit = ${sub.leaseItemUnitId}');
                        await _client
                            .from('lease_item_units')
                            .update({
                              'returned_at': (updated.actualReturnTime ?? DateTime.now()).toIso8601String(),
                              'inspection_status': targetUnitStatus == 'available' ? 'inspected_good' : targetUnitStatus,
                            })
                            .eq('lease_id', updated.id)
                            .eq('inventory_unit_id', sub.leaseItemUnitId!);
                      } catch (uLinkErr) {
                        debugPrint('--> [SETTLE STEP 4 WARNING] lease_item_units warning: $uLinkErr');
                      }

                      try {
                        debugPrint('--> [SETTLE STEP 5] Updating "inventory_units" status to "$targetUnitStatus": ID = ${sub.leaseItemUnitId}');
                        await _client
                            .from('inventory_units')
                            .update({'status': targetUnitStatus})
                            .eq('id', sub.leaseItemUnitId!);
                        debugPrint('--> [SETTLE STEP 5 SUCCESS] inventory_units updated to $targetUnitStatus');
                      } catch (uErr) {
                        debugPrint('--> [SETTLE STEP 5 WARNING] inventory_units update warning: $uErr');
                      }
                    }

                    if (sub.inventoryComponentUnitId != null && sub.inventoryComponentUnitId!.isNotEmpty) {
                      try {
                        debugPrint('--> [SETTLE STEP 5b] Updating "inventory_component_units" status to "$targetUnitStatus": ID = ${sub.inventoryComponentUnitId}');
                        await _client
                            .from('inventory_component_units')
                            .update({'status': targetUnitStatus})
                            .eq('id', sub.inventoryComponentUnitId!);
                        debugPrint('--> [SETTLE STEP 5b SUCCESS] inventory_component_units updated to $targetUnitStatus');
                      } catch (compErr) {
                        debugPrint('--> [SETTLE STEP 5b WARNING] inventory_component_units update warning: $compErr');
                      }
                    }
                  } catch (subErr) {
                    debugPrint('LeaseRepository.returnAndSettleLease leased_sub_items update warning: $subErr');
                  }
                }
              }
            } catch (lineErr) {
              debugPrint('LeaseRepository.returnAndSettleLease line item update warning: $lineErr');
            }
          }
        }

        // Sync physical asset states back to available for all assigned physical units in lease_item_units
        try {
          final unitAssignments = await _client
              .from('lease_item_units')
              .select('inventory_unit_id')
              .eq('lease_id', updated.id);

          for (final assignment in unitAssignments as List) {
            final unitId = assignment['inventory_unit_id'] as String?;
            if (unitId != null && unitId.isNotEmpty) {
              await _client
                  .from('inventory_units')
                  .update({'status': 'available'})
                  .eq('id', unitId);

              await _client
                  .from('inventory_component_units')
                  .update({'status': 'available'})
                  .eq('inventory_unit_id', unitId);

              await _client
                  .from('lease_item_units')
                  .update({
                    'returned_at': (updated.actualReturnTime ?? DateTime.now()).toIso8601String(),
                    'inspection_status': 'inspected_good',
                  })
                  .eq('lease_id', updated.id)
                  .eq('inventory_unit_id', unitId);
              debugPrint('--> [SETTLE UNIT SYNC SUCCESS] Unit $unitId restored to available');
            }
          }
        } catch (uSyncErr) {
          debugPrint('--> [SETTLE UNIT SYNC WARNING] lease_item_units sync warning: $uSyncErr');
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
}
