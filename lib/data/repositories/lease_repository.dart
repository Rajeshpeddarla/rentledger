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
      try {
        final payload = lease.copyWith(storeId: user.id).toDatabaseJson();
        final res = await _client.from('leases').insert(payload).select().single();
        final created = LeaseModel.fromJson(res);

        // Save line items to lease_items table and sub-items to leased_sub_items table
        final List<LeaseItemModel> savedLineItems = [];
        if (lease.leaseItems.isNotEmpty) {
          for (final line in lease.leaseItems) {
            final linePayload = line.copyWith(
              leaseId: created.id,
              storeId: user.id,
            ).toJson();
            try {
              final lineRes = await _client.from('lease_items').upsert(linePayload).select().single();
              final savedLine = LeaseItemModel.fromJson(lineRes);

              // Save leased sub-items if present
              final List<LeasedSubItemModel> savedSubItems = [];
              if (line.leasedSubItems.isNotEmpty) {
                for (final sub in line.leasedSubItems) {
                  final subPayload = sub.copyWith(
                    leaseId: created.id,
                    leaseItemId: savedLine.id,
                    storeId: user.id,
                  ).toJson();
                  try {
                    final subRes = await _client.from('leased_sub_items').upsert(subPayload).select().single();
                    savedSubItems.add(LeasedSubItemModel.fromJson(subRes));
                  } catch (subErr) {
                    debugPrint('LeaseRepository.createLease leased_sub_items insert warning: $subErr');
                    savedSubItems.add(sub);
                  }
                }
              }

              savedLineItems.add(savedLine.copyWith(
                item: line.item,
                leasedSubItems: savedSubItems.isNotEmpty ? savedSubItems : line.leasedSubItems,
              ));
            } catch (lineErr) {
              debugPrint('LeaseRepository.createLease line item insert warning: $lineErr');
              savedLineItems.add(line);
            }
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
        await _client
            .from('leases')
            .update(updated.toDatabaseJson())
            .eq('id', updated.id);

        if (updated.leaseItems.isNotEmpty) {
          for (final line in updated.leaseItems) {
            try {
              await _client
                  .from('lease_items')
                  .update(line.toJson())
                  .eq('id', line.id);

              if (line.leasedSubItems.isNotEmpty) {
                for (final sub in line.leasedSubItems) {
                  try {
                    await _client
                        .from('leased_sub_items')
                        .update(sub.toJson())
                        .eq('id', sub.id);
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
