import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/lease_model.dart';
import '../../data/repositories/lease_repository.dart';
import 'lease_state.dart';

class LeaseCubit extends Cubit<LeaseState> {
  final LeaseRepository _leaseRepository;

  LeaseCubit(this._leaseRepository) : super(LeaseInitial());

  Future<void> loadLeases() async {
    emit(LeaseLoading());
    try {
      final leases = await _leaseRepository.getLeases();
      emit(LeaseLoaded(
        allLeases: leases,
        selectedDate: DateTime.now(),
      ));
    } catch (e) {
      emit(LeaseError(e.toString()));
    }
  }

  void setStatusFilter(String filter) {
    if (state is LeaseLoaded) {
      final current = state as LeaseLoaded;
      emit(LeaseLoaded(
        allLeases: current.allLeases,
        statusFilter: filter,
        selectedDate: current.selectedDate,
      ));
    }
  }

  void setSelectedDate(DateTime date) {
    if (state is LeaseLoaded) {
      final current = state as LeaseLoaded;
      emit(LeaseLoaded(
        allLeases: current.allLeases,
        statusFilter: current.statusFilter,
        selectedDate: date,
      ));
    }
  }

  /// Date conflict check for Create Lease dispatch
  Future<bool> checkDateConflict({
    required String itemId,
    required DateTime startTime,
    required DateTime expectedEndTime,
    required int totalQuantity,
  }) async {
    return await _leaseRepository.hasDateConflict(
      itemId: itemId,
      startTime: startTime,
      expectedEndTime: expectedEndTime,
      totalQuantity: totalQuantity,
    );
  }

  /// Create new lease
  Future<LeaseModel> createLease(
    LeaseModel lease, {
    required bool isPro,
    required int totalItemQuantity,
  }) async {
    try {
      final created = await _leaseRepository.createLease(
        lease,
        isPro: isPro,
        totalItemQuantity: totalItemQuantity,
      );
      await loadLeases();
      return created;
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  /// Settle and return item
  Future<LeaseModel> returnAndSettle(LeaseModel lease) async {
    try {
      final settled = await _leaseRepository.returnAndSettleLease(lease);
      await loadLeases();
      return settled;
    } catch (e) {
      throw Exception(e.toString());
    }
  }
}
