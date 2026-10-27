import 'package:equatable/equatable.dart';
import '../../data/models/discount_model.dart';

abstract class DiscountState extends Equatable {
  const DiscountState();
  @override
  List<Object?> get props => [];
}

class DiscountInitial extends DiscountState {}

class DiscountLoading extends DiscountState {}

class DiscountLoaded extends DiscountState {
  final List<DiscountModel> discounts;

  const DiscountLoaded({required this.discounts});

  @override
  List<Object?> get props => [discounts];
}

class DiscountError extends DiscountState {
  final String message;
  const DiscountError(this.message);

  @override
  List<Object?> get props => [message];
}
