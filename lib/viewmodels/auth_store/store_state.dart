import 'package:equatable/equatable.dart';
import '../../data/models/store_model.dart';

abstract class StoreState extends Equatable {
  const StoreState();
  @override
  List<Object?> get props => [];
}

class StoreInitial extends StoreState {}

class StoreLoading extends StoreState {}

class StoreLoaded extends StoreState {
  final StoreModel store;
  final bool isAnonymous;

  const StoreLoaded({
    required this.store,
    required this.isAnonymous,
  });

  @override
  List<Object?> get props => [store, isAnonymous];
}

class StoreError extends StoreState {
  final String message;
  const StoreError(this.message);

  @override
  List<Object?> get props => [message];
}
