import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../core/config/app_theme.dart';
import '../../data/models/discount_model.dart';
import '../../data/models/inventory_item_model.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../../viewmodels/discount/discount_cubit.dart';
import '../../viewmodels/discount/discount_state.dart';
import '../../viewmodels/inventory/inventory_cubit.dart';
import '../../viewmodels/inventory/inventory_state.dart';
import '../widgets/shimmer_loading.dart';
import 'create_edit_discount_screen.dart';

class DiscountListScreen extends StatefulWidget {
  const DiscountListScreen({super.key});

  @override
  State<DiscountListScreen> createState() => _DiscountListScreenState();
}

class _DiscountListScreenState extends State<DiscountListScreen> {
  @override
  void initState() {
    super.initState();
    final storeState = context.read<StoreCubit>().state;
    final storeId = storeState is StoreLoaded ? storeState.store.id : null;
    context.read<DiscountCubit>().loadDiscounts(storeId: storeId);
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.green.shade700,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red.shade700,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _navigateToCreateOrEditDiscountScreen([DiscountModel? existing]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateEditDiscountScreen(existingDiscount: existing),
      ),
    );
  }

  void _confirmDeleteDiscount(DiscountModel discount) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Discount Coupon', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete coupon "${discount.code}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dCtx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      try {
        await context.read<DiscountCubit>().deleteDiscount(discount.id);
        _showSuccessSnackBar('Coupon "${discount.code}" deleted successfully!');
      } catch (e) {
        _showErrorSnackBar('Failed to delete coupon: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final storeState = context.watch<StoreCubit>().state;
    final currency = storeState is StoreLoaded ? storeState.store.currencySymbol : '₹';

    final inventoryState = context.watch<InventoryCubit>().state;
    final inventoryItems = inventoryState is InventoryLoaded ? inventoryState.allItems : <InventoryItemModel>[];

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('Discounts & Vouchers'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
            onPressed: () => _navigateToCreateOrEditDiscountScreen(),
            tooltip: 'Create Coupon',
          ),
        ],
      ),
      body: BlocBuilder<DiscountCubit, DiscountState>(
        builder: (context, state) {
          if (state is DiscountLoading || state is DiscountInitial) {
            return const ShimmerListPlaceholder(itemCount: 5, itemHeight: 90);
          }

          if (state is DiscountError) {
            return Center(child: Text('Error loading discounts: ${state.message}'));
          }

          final discounts = state is DiscountLoaded ? state.discounts : <DiscountModel>[];

          if (discounts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.discount_outlined,
                      size: 48,
                      color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No Active Discount Coupons',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap "+" above to create promotional discount coupons for equipment items.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: discounts.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final d = discounts[index];
              final valueText = d.discountType == 'percentage'
                  ? '${d.discountValue.toStringAsFixed(0)}% OFF'
                  : '$currency${d.discountValue.toStringAsFixed(0)} OFF';

              String targetLabel;
              if (d.eligibleItemIds.isEmpty) {
                targetLabel = 'All Fleet Equipment';
              } else if (d.eligibleItemIds.length == 1) {
                final match = inventoryItems.where((it) => it.id == d.eligibleItemIds.first).firstOrNull;
                targetLabel = match != null ? 'Item: ${match.name}' : '1 Selected Item';
              } else {
                targetLabel = '${d.eligibleItemIds.length} Selected Items';
              }

              final expiryStr = DateFormat('dd MMM yyyy').format(d.expiryDate);
              final isExpired = d.isExpired;

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: d.isActive && !isExpired
                                ? AppColors.primary.withValues(alpha: 0.12)
                                : Colors.grey.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: d.isActive && !isExpired ? AppColors.primary : Colors.grey,
                            ),
                          ),
                          child: Text(
                            d.code,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: d.isActive && !isExpired ? AppColors.primary : Colors.grey,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            valueText,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Switch(
                          value: d.isActive && !isExpired,
                          activeThumbColor: AppColors.primary,
                          onChanged: isExpired
                              ? null
                              : (_) {
                                  context.read<DiscountCubit>().toggleDiscountStatus(d);
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      d.title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Applies to $targetLabel • Min rental: ${d.minRentalDays} day(s)',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.event,
                          size: 13,
                          color: isExpired ? Colors.redAccent : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isExpired ? 'Expired ($expiryStr)' : 'Expires: $expiryStr',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isExpired ? FontWeight.bold : FontWeight.normal,
                            color: isExpired ? Colors.redAccent : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                          ),
                        ),
                        if (d.maxUses != null) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.numbers_outlined, size: 13, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                          const SizedBox(width: 4),
                          Text(
                            'Uses: ${d.usedCount}/${d.maxUses}',
                            style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Divider(
                      height: 1,
                      thickness: 0.8,
                      color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(6),
                          onPressed: () => _navigateToCreateOrEditDiscountScreen(d),
                          tooltip: 'Edit Coupon',
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(6),
                          onPressed: () => _confirmDeleteDiscount(d),
                          tooltip: 'Delete Coupon',
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
