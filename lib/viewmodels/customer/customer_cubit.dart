import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/customer_model.dart';
import '../../data/repositories/customer_repository.dart';
import 'customer_state.dart';

class CustomerCubit extends Cubit<CustomerState> {
  final CustomerRepository _customerRepository;

  CustomerCubit(this._customerRepository) : super(CustomerInitial());

  Future<void> loadCustomers() async {
    emit(CustomerLoading());
    try {
      final customers = await _customerRepository.getCustomers();
      emit(CustomerLoaded(allCustomers: customers));
    } catch (e) {
      emit(CustomerError(e.toString()));
    }
  }

  void setSearchQuery(String query) {
    if (state is CustomerLoaded) {
      final current = state as CustomerLoaded;
      emit(CustomerLoaded(
        allCustomers: current.allCustomers,
        searchQuery: query,
      ));
    }
  }

  Future<CustomerModel> saveCustomer(CustomerModel customer) async {
    try {
      final saved = await _customerRepository.saveCustomer(customer);
      await loadCustomers();
      return saved;
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<void> deleteCustomer(String id) async {
    try {
      await _customerRepository.deleteCustomer(id);
      await loadCustomers();
    } catch (e) {
      throw Exception(e.toString());
    }
  }
}
