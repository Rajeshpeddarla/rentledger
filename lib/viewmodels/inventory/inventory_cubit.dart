import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/utils/rate_calculator.dart';
import '../../data/models/inventory_item_model.dart';
import '../../data/repositories/inventory_repository.dart';
import 'inventory_state.dart';

class InventoryCubit extends Cubit<InventoryState> {
  final InventoryRepository _inventoryRepository;

  InventoryCubit(this._inventoryRepository) : super(InventoryInitial());

  Future<void> loadInventory() async {
    emit(InventoryLoading());
    try {
      final items = await _inventoryRepository.getItems();
      emit(InventoryLoaded(allItems: items));
    } catch (e) {
      emit(InventoryError(e.toString()));
    }
  }

  void setCategoryFilter(String category) {
    if (state is InventoryLoaded) {
      final current = state as InventoryLoaded;
      emit(InventoryLoaded(
        allItems: current.allItems,
        selectedCategory: category,
        searchQuery: current.searchQuery,
      ));
    }
  }

  void setSearchQuery(String query) {
    if (state is InventoryLoaded) {
      final current = state as InventoryLoaded;
      emit(InventoryLoaded(
        allItems: current.allItems,
        selectedCategory: current.selectedCategory,
        searchQuery: query,
      ));
    }
  }

  Future<void> saveItem(InventoryItemModel item, {required bool isPro}) async {
    try {
      await _inventoryRepository.saveItem(item, isPro: isPro);
      await loadInventory();
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<void> archiveItem(String itemId) async {
    try {
      await _inventoryRepository.archiveItem(itemId);
      await loadInventory();
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  /// Helper used by Add/Edit Item Form for Smart Rate Auto-Calculation
  /// Section 4.1: Multipliers (8x daily, 6x weekly, 22x monthly)
  Map<String, double> computeSmartRates({
    double? hourly,
    double? daily,
    bool hourlyEdited = false,
    bool dailyEdited = false,
    bool weeklyEdited = false,
    bool monthlyEdited = false,
    required double currentHourly,
    required double currentDaily,
    required double currentWeekly,
    required double currentMonthly,
  }) {
    final suggested = RateCalculator.suggestRates(hourly: hourly, daily: daily);

    return {
      'hourly': hourlyEdited ? (hourly ?? currentHourly) : (suggested['hourly'] ?? currentHourly),
      'daily': dailyEdited ? (daily ?? currentDaily) : (suggested['daily'] ?? currentDaily),
      'weekly': weeklyEdited ? currentWeekly : (suggested['weekly'] ?? currentWeekly),
      'monthly': monthlyEdited ? currentMonthly : (suggested['monthly'] ?? currentMonthly),
    };
  }
}
