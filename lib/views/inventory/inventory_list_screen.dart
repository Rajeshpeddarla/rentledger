import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/config/app_theme.dart';
import '../../core/utils/rate_calculator.dart';
import '../../core/widgets/app_image_view.dart';
import '../../data/models/inventory_item_model.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../../viewmodels/category/category_cubit.dart';
import '../../viewmodels/category/category_state.dart';
import '../../viewmodels/inventory/inventory_cubit.dart';
import '../../viewmodels/inventory/inventory_state.dart';
import '../widgets/shimmer_loading.dart';
import 'add_edit_item_screen.dart';
import 'item_detail_history_screen.dart';

class InventoryListScreen extends StatefulWidget {
  const InventoryListScreen({super.key});

  @override
  State<InventoryListScreen> createState() => _InventoryListScreenState();
}

class _InventoryListScreenState extends State<InventoryListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _calcHourlyController = TextEditingController(text: '150');
  double _calcHourly = 150;

  @override
  void initState() {
    super.initState();
    context.read<CategoryCubit>().loadCategories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _calcHourlyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final storeState = context.watch<StoreCubit>().state;
    final store = storeState is StoreLoaded ? storeState.store : null;
    final isPro = store?.isPro ?? false;
    final currency = store?.currencySymbol ?? '₹';

    final workingHours = store != null ? (store.dailyWorkingHours <= 0 ? 8 : store.dailyWorkingHours) : 8;
    final daysPerWeek = store?.daysPerWeek ?? 6;
    final daysPerMonth = store != null ? (store.daysPerMonth <= 0 ? 28 : store.daysPerMonth) : 28;

    final smartRates = RateCalculator.suggestRates(
      hourly: _calcHourly,
      workingHours: workingHours.toDouble(),
      daysPerWeek: daysPerWeek,
      daysPerMonth: daysPerMonth,
    );

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('Equipment Inventory'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box_rounded, color: AppColors.primary),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AddEditItemScreen(isPro: isPro),
                ),
              );
            },
            tooltip: 'Add Equipment Item',
          ),
        ],
      ),
      body: BlocBuilder<InventoryCubit, InventoryState>(
        builder: (context, state) {
          if (state is InventoryLoading || state is InventoryInitial) {
            return const ShimmerListPlaceholder(itemCount: 5, itemHeight: 96);
          }

          if (state is InventoryError) {
            return Center(child: Text('Error loading inventory: ${state.message}'));
          }

          final inventoryLoaded = state as InventoryLoaded;
          final filteredItems = inventoryLoaded.filteredItems;
          final currentCategory = inventoryLoaded.selectedCategory;
          final totalStock = inventoryLoaded.totalStockCount;
          final availableStock = inventoryLoaded.availableStockCount;

          return RefreshIndicator(
            onRefresh: () async {
              context.read<InventoryCubit>().loadInventory();
              context.read<CategoryCubit>().loadCategories();
            },
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Search Bar
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCard : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) {
                        context.read<InventoryCubit>().setSearchQuery(val);
                      },
                      decoration: InputDecoration(
                        hintText: 'Search by item name, SKU or model...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  context.read<InventoryCubit>().setSearchQuery('');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 2. Category Filter Strip (Dynamic categories from CategoryCubit)
                  BlocBuilder<CategoryCubit, CategoryState>(
                    builder: (context, catState) {
                      if (catState is CategoryLoading || catState is CategoryInitial) {
                        return const ShimmerCategoryChipsPlaceholder();
                      }

                      final loadedCategories = catState is CategoryLoaded
                          ? catState.categoryNames.where((n) => n.trim().isNotEmpty).toList()
                          : <String>[];

                      // Also ensure categories present on allItems appear in the filter list if not already there
                      for (final it in inventoryLoaded.allItems) {
                        final c = it.category.trim();
                        if (c.isNotEmpty && c.toLowerCase() != 'general' && !loadedCategories.any((lc) => lc.toLowerCase() == c.toLowerCase())) {
                          loadedCategories.add(c);
                        }
                      }

                      final categories = ['All', ...loadedCategories];

                      return SizedBox(
                        height: 36,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: categories.length,
                          separatorBuilder: (context, index) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final cat = categories[index];
                            final isSelected = currentCategory.trim().toLowerCase() == cat.trim().toLowerCase() ||
                                (cat == 'All' && (currentCategory == 'All' || currentCategory.isEmpty));

                            return ChoiceChip(
                              label: Text(
                                cat,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? Colors.white
                                      : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                ),
                              ),
                              selected: isSelected,
                              selectedColor: AppColors.primary,
                              backgroundColor: isDark ? AppColors.darkCard : Colors.white,
                              side: BorderSide(
                                color: isSelected
                                    ? AppColors.primary
                                    : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              onSelected: (selected) {
                                if (!selected || cat == 'All') {
                                  context.read<InventoryCubit>().setCategoryFilter('All');
                                } else {
                                  context.read<InventoryCubit>().setCategoryFilter(cat);
                                }
                              },
                            );
                          },
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 8),

                  // Availability ticker pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.primaryLight,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$availableStock / $totalStock Units Available for Lease',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDark ? AppColors.primaryLight : AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 3. Smart Rate Auto-Calculator Highlight Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCard : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.calculate, size: 20, color: isDark ? AppColors.primaryLight : AppColors.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Smart Rate Auto-Calculator',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Base Hourly Benchmark',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(currency, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: TextField(
                                            controller: _calcHourlyController,
                                            keyboardType: TextInputType.number,
                                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              border: InputBorder.none,
                                              contentPadding: EdgeInsets.symmetric(vertical: 6),
                                            ),
                                            onChanged: (val) {
                                              setState(() {
                                                _calcHourly = double.tryParse(val) ?? 0;
                                              });
                                            },
                                          ),
                                        ),
                                        Text('/ hr',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  children: [
                                    Text('${workingHours}h Shift',
                                        style: TextStyle(
                                            fontSize: 9,
                                            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$currency${smartRates['daily']?.toStringAsFixed(0)} / day',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: isDark ? AppColors.primaryLight : AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // 3 Multiplier Tiles
                        Row(
                          children: [
                            _buildMultiplierTile('Daily', '${workingHours}h Shift', '$currency${smartRates['daily']?.toStringAsFixed(0)}', isDark),
                            const SizedBox(width: 8),
                            _buildMultiplierTile('Weekly', '$daysPerWeek Days', '$currency${smartRates['weekly']?.toStringAsFixed(0)}', isDark),
                            const SizedBox(width: 8),
                            _buildMultiplierTile('Monthly', '$daysPerMonth Days', '$currency${smartRates['monthly']?.toStringAsFixed(0)}', isDark),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 4. Equipment List Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Equipment List (${filteredItems.length})',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        ),
                      ),
                      Text(
                        'Sort: Availability',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // 5. Equipment Cards
                  if (filteredItems.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(Icons.inventory_2_outlined,
                                size: 48, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                            const SizedBox(height: 8),
                            const Text('No inventory items match your search.'),
                          ],
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredItems.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
                        return _buildInventoryCard(context, item, currency, isDark, isPro);
                      },
                    ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMultiplierTile(String title, String subtitle, String value, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                Text(subtitle, style: const TextStyle(fontSize: 8, color: AppColors.primaryLight, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 3),
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface)),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryCard(BuildContext context, InventoryItemModel item, String currency, bool isDark, bool isPro) {
    final available = item.availableQuantity;

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ItemDetailHistoryScreen(item: item, currency: currency),
          ),
        );
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppImageView(
              imagePathOrUrl: item.imageR2Url,
              width: 58,
              height: 58,
              borderRadius: BorderRadius.circular(10),
              fit: BoxFit.cover,
              fallback: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.handyman_outlined, size: 28, color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            item.displaySku,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: isDark ? AppColors.primaryLight : AppColors.primary,
                              letterSpacing: 0.5,
                            ),
                          ),
                          if (item.category.trim().isNotEmpty && item.category.trim().toLowerCase() != 'general') ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.category,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: available > 0
                              ? (isDark ? const Color(0xFF142E24) : const Color(0xFFECFDF5))
                              : (isDark ? const Color(0xFF3B1515) : const Color(0xFFFFDAD6)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$available Available',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: available > 0 ? AppColors.primaryLight : AppColors.errorRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    ),
                  ),
                  if (item.description != null && item.description!.isNotEmpty)
                    Text(
                      item.description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$currency${item.rateDaily.toStringAsFixed(0)} / day',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        ),
                      ),
                      Text(
                        'Deposit: $currency${item.depositAmount.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
