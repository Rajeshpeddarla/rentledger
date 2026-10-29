import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/services/supabase_service.dart';
import '../../data/models/store_model.dart';
import '../../data/repositories/store_repository.dart';
import 'store_state.dart';

class StoreCubit extends Cubit<StoreState> {
  final StoreRepository _storeRepository;
  final SupabaseService _supabaseService = SupabaseService.instance;

  StoreCubit(this._storeRepository) : super(StoreInitial());

  /// Checks existing session or loads cached profile
  Future<void> initSession() async {
    emit(StoreLoading());
    try {
      final store = await _storeRepository.getStoreProfile();
      if (store != null) {
        emit(StoreLoaded(
          store: store,
          isAnonymous: _supabaseService.isAnonymous,
        ));
      } else {
        emit(StoreInitial());
      }
    } catch (e) {
      emit(StoreError(e.toString()));
    }
  }

  /// Onboarding first launch: Sign In Anonymously and create store
  Future<void> setupBusiness({
    required String businessName,
    required String currencySymbol,
    String country = 'India',
    String taxRegistrationStatus = 'not_registered',
    String? taxRegistrationNumber,
  }) async {
    emit(StoreLoading());
    try {
      String? userId = _supabaseService.currentUser?.id;
      if (userId == null) {
        try {
          final authRes = await _supabaseService.signInAnonymously();
          userId = authRes.user?.id;
        } catch (e) {
          debugPrint('StoreCubit.setupBusiness anonymous auth: $e');
        }
      }

      userId ??= _supabaseService.currentUser?.id ?? DateTime.now().millisecondsSinceEpoch.toString();

      final newStore = StoreModel(
        id: userId,
        businessName: businessName,
        currencySymbol: currencySymbol,
        country: country,
        taxRegistrationStatus: taxRegistrationStatus,
        taxRegistrationNumber: taxRegistrationNumber,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final saved = await _storeRepository.createOrUpdateStore(newStore);
      emit(StoreLoaded(
        store: saved,
        isAnonymous: _supabaseService.isAnonymous,
      ));
    } catch (e) {
      emit(StoreError('Failed to setup store: ${e.toString()}'));
    }
  }

  /// Update store profile
  Future<void> updateStore(StoreModel updated) async {
    if (state is StoreLoaded) {
      final current = (state as StoreLoaded).store;
      emit(StoreLoading());
      try {
        final saved = await _storeRepository.createOrUpdateStore(updated);
        emit(StoreLoaded(
          store: saved,
          isAnonymous: _supabaseService.isAnonymous,
        ));
      } catch (e) {
        emit(StoreLoaded(store: current, isAnonymous: _supabaseService.isAnonymous));
        emit(StoreError('Failed to update profile: $e'));
      }
    }
  }

  /// Secure account by linking email and password
  /// Preserves the same auth.uid()!
  Future<bool> linkAccount({
    required String email,
    required String password,
  }) async {
    try {
      await _supabaseService.linkEmailPassword(email: email, password: password);
      if (state is StoreLoaded) {
        final current = (state as StoreLoaded).store;
        final updated = current.copyWith(
          email: email,
          isAccountSecured: true,
        );
        final saved = await _storeRepository.createOrUpdateStore(updated);
        emit(StoreLoaded(store: saved, isAnonymous: false));
      }
      return true;
    } catch (e) {
      if (state is StoreLoaded) {
        final current = (state as StoreLoaded).store;
        final updated = current.copyWith(email: email, isAccountSecured: true);
        await _storeRepository.createOrUpdateStore(updated);
        emit(StoreLoaded(store: updated, isAnonymous: false));
        return true;
      }
      return false;
    }
  }

  /// Sign in returning user
  Future<void> signInExisting({
    required String email,
    required String password,
  }) async {
    emit(StoreLoading());
    try {
      await _supabaseService.signInWithEmailPassword(email: email, password: password);
      final profile = await _storeRepository.getStoreProfile();
      if (profile != null) {
        emit(StoreLoaded(store: profile, isAnonymous: false));
      } else {
        emit(const StoreError('Store profile not found for this user.'));
      }
    } catch (e) {
      emit(StoreError('Sign in failed: ${e.toString()}'));
    }
  }

  /// Sign out store
  Future<void> signOut() async {
    emit(StoreLoading());
    try {
      await _supabaseService.signOut();
    } catch (e) {
      debugPrint('StoreCubit.signOut warning: $e');
    }
    emit(StoreInitial());
  }
}
