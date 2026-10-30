import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/damage_loss_incident_model.dart';
import '../models/damage_loss_payment_model.dart';

class DamageLossRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // In-memory fallback
  final List<DamageLossIncidentModel> _incidents = [];

  Future<List<DamageLossIncidentModel>> getIncidents({String? incidentType}) async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        var query = _client
            .from('damage_loss_incidents')
            .select('*, inventory_units(*), inventory_component_units(*), damage_loss_payments(*)')
            .eq('store_id', user.id);

        if (incidentType != null && incidentType != 'all') {
          query = query.eq('incident_type', incidentType);
        }

        final data = await query.order('reported_at', ascending: false);
        final list = (data as List)
            .map((e) => DamageLossIncidentModel.fromJson(e as Map<String, dynamic>))
            .toList();

        _incidents.clear();
        _incidents.addAll(list);
        return list;
      } catch (e) {
        debugPrint('DamageLossRepository.getIncidents error: $e');
      }
    }
    return _incidents;
  }

  Future<DamageLossIncidentModel> createIncident(DamageLossIncidentModel incident) async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        final payload = incident.copyWith(storeId: user.id).toJson();
        final res = await _client.from('damage_loss_incidents').insert(payload).select('*, inventory_units(*), inventory_component_units(*), damage_loss_payments(*)').single();
        final created = DamageLossIncidentModel.fromJson(res);
        _incidents.insert(0, created);
        return created;
      } catch (e) {
        debugPrint('DamageLossRepository.createIncident error: $e');
      }
    }
    _incidents.insert(0, incident);
    return incident;
  }

  Future<void> recordPayment(DamageLossPaymentModel payment) async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        final payload = payment.copyWith(storeId: user.id).toJson();
        await _client.from('damage_loss_payments').insert(payload);
        await getIncidents(); // Reload to sync customer_amount_paid and payment_status via DB trigger
      } catch (e) {
        debugPrint('DamageLossRepository.recordPayment error: $e');
      }
    }
  }

  Future<void> updateRepairStatus({
    required String incidentId,
    required String repairStatus,
    double? actualRepairCost,
    double? customerCharge,
    String? notes,
  }) async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        final updates = <String, dynamic>{
          'repair_status': repairStatus,
          'updated_at': DateTime.now().toIso8601String(),
        };
        if (actualRepairCost != null) updates['actual_repair_cost'] = actualRepairCost;
        if (customerCharge != null) updates['customer_charge'] = customerCharge;
        if (notes != null) updates['notes'] = notes;
        if (repairStatus == 'resolved' || repairStatus == 'repaired' || repairStatus == 'written_off') {
          updates['resolved_at'] = DateTime.now().toIso8601String();
        }

        await _client
            .from('damage_loss_incidents')
            .update(updates)
            .eq('id', incidentId)
            .eq('store_id', user.id);

        await getIncidents();
      } catch (e) {
        debugPrint('DamageLossRepository.updateRepairStatus error: $e');
      }
    }
  }
}
