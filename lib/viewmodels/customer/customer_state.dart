import 'package:equatable/equatable.dart';
import '../../data/models/customer_model.dart';

abstract class CustomerState extends Equatable {
  const CustomerState();
  @override
  List<Object?> get props => [];
}

class CustomerInitial extends CustomerState {}

class CustomerLoading extends CustomerState {}

class CustomerLoaded extends CustomerState {
  final List<CustomerModel> allCustomers;
  final String searchQuery;

  const CustomerLoaded({
    required this.allCustomers,
    this.searchQuery = '',
  });

  List<CustomerModel> get filteredCustomers {
    if (searchQuery.trim().isEmpty) return allCustomers;
    final q = searchQuery.trim().toLowerCase();
    return allCustomers.where((c) {
      final nameMatch = c.name.toLowerCase().contains(q);
      final phoneMatch = c.phone.contains(q);
      final emailMatch = c.email != null && c.email!.toLowerCase().contains(q);
      return nameMatch || phoneMatch || emailMatch;
    }).toList();
  }

  @override
  List<Object?> get props => [allCustomers, searchQuery];
}

class CustomerError extends CustomerState {
  final String message;
  const CustomerError(this.message);

  @override
  List<Object?> get props => [message];
}
