import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/lease_model.dart';

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
            .select('*, inventory_items(*), customers(*)')
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
        debugPrint('LeaseRepository.getLeases error: $e');
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
    final activeLeases = await getLeases(itemId: itemId);
    final totalOverlapping = activeLeases.where((l) {
      if (l.id == excludeLeaseId) return false;
      if (l.status != 'active' && l.status != 'upcoming') return false;

      // Overlap condition
      final overlap =
          startTime.isBefore(l.expectedEndTime) && expectedEndTime.isAfter(l.startTime);
      return overlap;
    }).fold<int>(0, (sum, l) => sum + l.quantity);

    return (totalOverlapping + requestedQuantity) > totalQuantity;
  }

  /// Create new lease with free quota check & conflict validator
  Future<LeaseModel> createLease(
    LeaseModel lease, {
    required bool isPro,
    required int totalItemQuantity,
  }) async {
    // 1. Free Quota Check (Max 15 leases/month)
    if (!isPro) {
      final allLeases = await getLeases();
      final now = DateTime.now();
      final monthlyCount = allLeases.where((l) =>
          l.createdAt.month == now.month && l.createdAt.year == now.year).length;
      if (monthlyCount >= 15) {
        throw Exception(
            'FREE_LEASE_LIMIT_REACHED: Free tier is limited to 15 leases per month. Upgrade to Pro for unlimited leases!');
      }
    }

    // 2. Date Conflict Check
    final isBlocked = await hasDateConflict(
      itemId: lease.itemId,
      startTime: lease.startTime,
      expectedEndTime: lease.expectedEndTime,
      totalQuantity: totalItemQuantity,
      requestedQuantity: lease.quantity,
    );

    if (isBlocked) {
      throw Exception(
          'ITEM_ALREADY_LEASED: All units of this item are already booked for the selected dates.');
    }

    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        final payload = lease.copyWith(storeId: user.id).toJson();
        final res = await _client.from('leases').insert(payload).select().single();
        final created = LeaseModel.fromJson(res);
        final fullLease = created.copyWith(
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
        debugPrint('LeaseRepository.createLease warning: $e');
      }
    }

    _leases.insert(0, lease);
    return lease;
  }

  /// Take Back / Settlement Update
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
            .update(updated.toJson())
            .eq('id', updated.id);

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
