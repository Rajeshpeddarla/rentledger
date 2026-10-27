import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/customer_model.dart';

class CustomerRepository {
  final SupabaseClient _client = Supabase.instance.client;

  final List<CustomerModel> _customers = [];

  Future<List<CustomerModel>> getCustomers({String? searchQuery}) async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        var query = _client.from('customers').select().eq('store_id', user.id);
        if (searchQuery != null && searchQuery.trim().isNotEmpty) {
          query = query.or('name.ilike.%$searchQuery%,phone.ilike.%$searchQuery%');
        }
        final data = await query.order('name');
        final list = (data as List)
            .map((e) => CustomerModel.fromJson(e as Map<String, dynamic>))
            .toList();

        _customers.clear();
        _customers.addAll(list);
        return list;
      } catch (e) {
        debugPrint('CustomerRepository.getCustomers error: $e');
      }
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.toLowerCase();
      return _customers.where((c) =>
          c.name.toLowerCase().contains(q) || c.phone.contains(q)).toList();
    }
    return List.from(_customers);
  }

  Future<CustomerModel> saveCustomer(CustomerModel customer) async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        final payload = customer.copyWith(storeId: user.id).toJson();
        final res = await _client
            .from('customers')
            .upsert(payload)
            .select()
            .single();
        final saved = CustomerModel.fromJson(res);
        final index = _customers.indexWhere((c) => c.id == saved.id);
        if (index >= 0) {
          _customers[index] = saved;
        } else {
          _customers.insert(0, saved);
        }
        return saved;
      } catch (e) {
        debugPrint('CustomerRepository.saveCustomer warning: $e');
      }
    }

    final index = _customers.indexWhere((c) => c.id == customer.id);
    if (index >= 0) {
      _customers[index] = customer;
    } else {
      _customers.insert(0, customer);
    }
    return customer;
  }

  Future<void> deleteCustomer(String id) async {
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        await _client
            .from('customers')
            .delete()
            .eq('id', id)
            .eq('store_id', user.id);
      } catch (e) {
        debugPrint('CustomerRepository.deleteCustomer warning: $e');
      }
    }
    _customers.removeWhere((c) => c.id == id);
  }
}
