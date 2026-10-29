import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../core/config/app_theme.dart';
import '../../core/widgets/app_image_view.dart';
import '../../data/models/inventory_item_model.dart';
import '../../data/models/lease_model.dart';
import '../../data/models/sub_item_model.dart';
import '../../data/repositories/sub_item_repository.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../../viewmodels/lease/lease_cubit.dart';
import '../../viewmodels/lease/lease_state.dart';
import '../lease/create_lease_screen.dart';
import '../lease/take_back_settlement_screen.dart';
import 'add_edit_item_screen.dart';

class ItemDetailHistoryScreen extends StatelessWidget {
  final InventoryItemModel item;
  final String currency;

  const ItemDetailHistoryScreen({
    super.key,
    required this.item,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final storeState = context.watch<StoreCubit>().state;
    final isPro = storeState is StoreLoaded && storeState.store.isPro;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: Text(item.name),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AddEditItemScreen(initialItem: item, isPro: isPro),
                ),
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<LeaseCubit, LeaseState>(
        builder: (context, leaseState) {
          final List<LeaseModel> allLeases = leaseState is LeaseLoaded ? leaseState.allLeases : [];
          final itemLeases = allLeases.where((l) => l.itemId == item.id).toList();

          final totalRevenue = itemLeases
              .where((l) => l.status == 'returned')
              .fold(0.0, (sum, l) => sum + l.netRentTotal);

          final activeCount = itemLeases
              .where((l) => l.status == 'active')
              .fold<int>(0, (sum, l) => sum + l.quantity);
          final availableCount = item.availableQuantity;

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Item Header Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkCard : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.imageR2Url != null && item.imageR2Url!.isNotEmpty) ...[
                        AppImageView(
                          imagePathOrUrl: item.imageR2Url,
                          width: double.infinity,
                          height: 190,
                          borderRadius: BorderRadius.circular(12),
                          fit: BoxFit.cover,
                          enableZoom: true,
                        ),
                        const SizedBox(height: 14),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.displaySku,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isDark ? AppColors.primaryLight : AppColors.primary,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: availableCount > 0
                                  ? (isDark ? const Color(0xFF142E24) : const Color(0xFFECFDF5))
                                  : (isDark ? const Color(0xFF3B1515) : const Color(0xFFFFDAD6)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$availableCount Available',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: availableCount > 0 ? AppColors.primaryLight : AppColors.errorRed,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        item.name,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        ),
                      ),
                      if (item.description != null && item.description!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.description!,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      // Rate Matrix
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildRateColumn('Hourly', '$currency${item.rateHourly.toStringAsFixed(0)}', isDark),
                            _buildRateColumn('Daily', '$currency${item.rateDaily.toStringAsFixed(0)}', isDark),
                            _buildRateColumn('Weekly', '$currency${item.rateWeekly.toStringAsFixed(0)}', isDark),
                            _buildRateColumn('Deposit', '$currency${item.depositAmount.toStringAsFixed(0)}', isDark),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Sub-Items Fleet Card (Displayed above Item Lifetime Revenue row)
                _buildSubItemsListCard(context, item.id, isDark),

                const SizedBox(height: 16),

                // Financial Telemetry for this Item
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkCard : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Item Lifetime Revenue',
                                style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                            const SizedBox(height: 4),
                            Text(
                              '$currency${totalRevenue.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: isDark ? AppColors.primaryLight : AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkCard : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Leases Completed',
                                style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                            const SizedBox(height: 4),
                            Text(
                              '${itemLeases.length} ($activeCount Active)',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Quick Dispatch CTA for this specific item
                ElevatedButton.icon(
                  onPressed: item.availableQuantity <= 0
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CreateLeaseScreen(
                                isPro: isPro,
                                preSelectedItem: item,
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                  label: Text(item.availableQuantity > 0 ? 'Rent Out / Dispatch This Item' : 'All Units Currently Leased', style: const TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),

                const SizedBox(height: 24),

                // Individual Item Lease History
                Text(
                  'Item Lease History (${itemLeases.length})',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                  ),
                ),
                const SizedBox(height: 10),

                if (itemLeases.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No lease contracts recorded for this asset yet.',
                        style: TextStyle(color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: itemLeases.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final lease = itemLeases[index];
                      final isReturned = lease.status == 'returned';

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkCard : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      lease.customer?.name ?? 'Client',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                                      ),
                                    ),
                                    if (lease.quantity > 1) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '${lease.quantity} pcs',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? AppColors.primaryLight : AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${DateFormat('dd MMM yyyy').format(lease.startTime)} → ${DateFormat('dd MMM yyyy').format(lease.expectedEndTime)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  isReturned ? '$currency${lease.netRentTotal.toStringAsFixed(0)}' : 'Active',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: isReturned
                                        ? (isDark ? AppColors.primaryLight : AppColors.primary)
                                        : AppColors.tertiaryAmber,
                                  ),
                                ),
                                if (!isReturned)
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => TakeBackSettlementScreen(lease: lease),
                                        ),
                                      );
                                    },
                                    child: const Text('Take Back', style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.bold)),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSubItemsListCard(BuildContext context, String itemId, bool isDark) {
    return FutureBuilder<List<SubItemModel>>(
      future: SubItemRepository().getSubItems(parentItemId: itemId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 60,
            alignment: Alignment.center,
            child: const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final subItems = snapshot.data ?? [];

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.format_list_bulleted, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Sub-Items (${subItems.length})',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Unit Tracking',
                    style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              if (subItems.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No serial-tracked sub-items registered for this asset.',
                    style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: subItems.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final sub = subItems[index];

                    Color badgeBg;
                    Color badgeText;
                    String statusLabel;

                    if (sub.isAvailable) {
                      badgeBg = isDark ? const Color(0xFF142E24) : const Color(0xFFECFDF5);
                      badgeText = AppColors.primaryLight;
                      statusLabel = 'READY';
                    } else if (sub.isLeased) {
                      badgeBg = const Color(0xFFEFF4FF);
                      badgeText = AppColors.primary;
                      statusLabel = 'LEASED';
                    } else if (sub.isAwaitingInspection || sub.isMaintenance) {
                      badgeBg = const Color(0xFFFFF6E5);
                      badgeText = AppColors.tertiaryAmber;
                      statusLabel = sub.isMaintenance ? 'REPAIR' : 'INSPECTION';
                    } else {
                      badgeBg = const Color(0xFFFFDAD6);
                      badgeText = AppColors.errorRed;
                      statusLabel = 'LOST';
                    }

                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(sub.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                Text(
                                  sub.serialNumber != null && sub.serialNumber!.isNotEmpty
                                      ? 'SN: ${sub.serialNumber}'
                                      : sub.displaySku,
                                  style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: badgeText),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRateColumn(String label, String value, bool isDark) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface)),
      ],
    );
  }
}
