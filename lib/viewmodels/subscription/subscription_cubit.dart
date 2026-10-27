import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/services/supabase_service.dart';
import '../../data/repositories/store_repository.dart';
import 'subscription_state.dart';

class SubscriptionCubit extends Cubit<SubscriptionState> {
  final StoreRepository _storeRepository;
  final SupabaseService _supabaseService = SupabaseService.instance;

  SubscriptionCubit(this._storeRepository) : super(SubscriptionInitial());

  Future<void> init() async {
    emit(SubscriptionLoading());
    final profile = await _storeRepository.getStoreProfile();
    emit(SubscriptionReady(
      planTier: profile?.planTier ?? 'free',
      isAnonymous: _supabaseService.isAnonymous,
      expiresAt: profile?.subscriptionExpiresAt,
    ));
  }

  /// Upgrade execution after account security check
  Future<void> upgradeToTier(String tier) async {
    emit(SubscriptionLoading());
    try {
      await _storeRepository.upgradePlanTier(tier);
      final profile = await _storeRepository.getStoreProfile();
      emit(SubscriptionReady(
        planTier: profile?.planTier ?? tier,
        isAnonymous: _supabaseService.isAnonymous,
        expiresAt: profile?.subscriptionExpiresAt,
      ));
    } catch (e) {
      emit(SubscriptionReady(
        planTier: 'free',
        isAnonymous: _supabaseService.isAnonymous,
      ));
    }
  }
}
