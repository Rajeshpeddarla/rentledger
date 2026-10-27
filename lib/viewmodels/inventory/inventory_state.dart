import 'package:equatable/equatable.dart';
import '../../data/models/inventory_item_model.dart';

abstract class InventoryState extends Equatable {
  const InventoryState();
  @override
  List<Object?> get props => [];
}

class InventoryInitial extends InventoryState {}

class InventoryLoading extends InventoryState {}

class InventoryLoaded extends InventoryState {
  final List<InventoryItemModel> allItems;
  final String selectedCategory; // 'All', 'Power Tools', 'Cameras', 'Events'
  final String searchQuery;

  const InventoryLoaded({
    required this.allItems,
    this.selectedCategory = 'All',
    this.searchQuery = '',
  });

  List<InventoryItemModel> get filteredItems {
    return allItems.where((item) {
      if (!_matchesCategory(item, selectedCategory)) {
        return false;
      }

      if (searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase().trim();
        final matchName = item.name.toLowerCase().contains(q);
        final matchSku = item.sku.toLowerCase().contains(q);
        final matchDesc = (item.description ?? '').toLowerCase().contains(q);
        if (!matchName && !matchSku && !matchDesc) return false;
      }
      return true;
    }).toList();
  }

  static bool _matchesCategory(InventoryItemModel item, String selectedCategory) {
    final sel = selectedCategory.trim().toLowerCase();
    if (sel.isEmpty || sel == 'all') {
      return true;
    }

    final cat = item.category.trim().toLowerCase();

    // Helper: strips trailing 's' for singular/plural comparison
    String singular(String s) => s.endsWith('s') ? s.substring(0, s.length - 1) : s;

    // 1. Exact match (case-insensitive)
    if (cat == sel) return true;

    // 2. Singular / Plural equivalence (e.g. "dji camera" <-> "dji cameras")
    if (singular(cat) == singular(sel)) return true;

    // 3. Clean alphanumeric match (e.g. "dji-camera" <-> "dji camera")
    final selClean = sel.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final catClean = cat.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (selClean.isNotEmpty && catClean.isNotEmpty) {
      if (selClean == catClean) return true;
      if (singular(selClean) == singular(catClean)) return true;
    }

    // 4. If the item has an explicit category that is NOT 'General',
    // it belongs to that specific category and must NEVER match a different category!
    // (e.g. "DSLR Camera" must never match "DJI Camera").
    if (cat.isNotEmpty && cat != 'general') {
      return false;
    }

    // 5. Fallback ONLY when item category was left as 'General' or empty:
    // Match against item name, SKU, or description.
    final name = item.name.trim().toLowerCase();
    final sku = item.sku.trim().toLowerCase();
    final desc = (item.description ?? '').trim().toLowerCase();
    final textBlob = '$name $sku $desc';

    // 5a. Direct containment of full filter (or its singular)
    final selSingular = singular(sel);
    if (textBlob.contains(sel) || textBlob.contains(selSingular)) {
      return true;
    }

    // 5b. For multi-word filters (e.g. "dji camera"), extract defining/distinctive keywords
    // by excluding common generic category words like "camera", "tool", "kit", etc.
    const genericWords = {
      'camera',
      'cameras',
      'tool',
      'tools',
      'equipment',
      'gear',
      'item',
      'items',
      'kit',
      'kits',
      'general',
      'and',
      'for',
      'the',
    };

    final keywords = sel
        .split(RegExp(r'[\s\-_/]+'))
        .map((w) => singular(w.trim()))
        .where((w) => w.length >= 2 && !genericWords.contains(w))
        .toList();

    // If defining keywords exist (e.g. ["dji"] or ["dslr"]), ALL must be present in the item
    if (keywords.isNotEmpty) {
      final allKeywordsMatch = keywords.every((kw) => textBlob.contains(kw));
      if (allKeywordsMatch) return true;
    }

    return false;
  }

  int get totalStockCount => allItems.fold(0, (sum, item) => sum + item.totalQuantity);
  int get availableStockCount => allItems.fold(0, (sum, item) => sum + item.availableQuantity);
  int get rentedStockCount => totalStockCount - availableStockCount;

  @override
  List<Object?> get props => [allItems, selectedCategory, searchQuery];
}

class InventoryError extends InventoryState {
  final String message;
  const InventoryError(this.message);

  @override
  List<Object?> get props => [message];
}
