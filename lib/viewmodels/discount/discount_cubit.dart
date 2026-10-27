import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/discount_model.dart';
import '../../data/repositories/discount_repository.dart';
import 'discount_state.dart';

class DiscountCubit extends Cubit<DiscountState> {
  final DiscountRepository _discountRepository;

  DiscountCubit(this._discountRepository) : super(DiscountInitial());

  Future<void> loadDiscounts({String? storeId}) async {
    emit(DiscountLoading());
    try {
      final discounts = await _discountRepository.getDiscounts(storeId: storeId);
      emit(DiscountLoaded(discounts: discounts));
    } catch (e) {
      emit(DiscountError(e.toString()));
    }
  }

  Future<DiscountModel> saveDiscount(DiscountModel discount) async {
    try {
      final saved = await _discountRepository.saveDiscount(discount);
      final discounts = await _discountRepository.getDiscounts(storeId: discount.storeId);
      emit(DiscountLoaded(discounts: discounts));
      return saved;
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<void> toggleDiscountStatus(DiscountModel discount) async {
    try {
      final updated = discount.copyWith(isActive: !discount.isActive);
      await _discountRepository.saveDiscount(updated);
      final discounts = await _discountRepository.getDiscounts(storeId: discount.storeId);
      emit(DiscountLoaded(discounts: discounts));
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<void> deleteDiscount(String id, {String? storeId}) async {
    try {
      await _discountRepository.deleteDiscount(id);
      final discounts = await _discountRepository.getDiscounts(storeId: storeId);
      emit(DiscountLoaded(discounts: discounts));
    } catch (e) {
      throw Exception(e.toString());
    }
  }
}
