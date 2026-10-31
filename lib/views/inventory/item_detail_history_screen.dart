import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../core/config/app_theme.dart';
import '../../core/widgets/app_image_view.dart';
import '../../data/models/inventory_item_model.dart';
import '../../data/models/inventory_unit_model.dart';
import '../../data/models/lease_model.dart';
import '../../data/repositories/inventory_unit_repository.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../../viewmodels/inventory/inventory_cubit.dart';
import '../../viewmodels/inventory/inventory_state.dart';
import '../../viewmodels/lease/lease_cubit.dart';
import '../../viewmodels/lease/lease_state.dart';
import 'add_edit_item_screen.dart';

class ItemDetailHistoryScreen extends StatefulWidget {
  final InventoryItemModel item;
  final String currency;

  const ItemDetailHistoryScreen({
    super.key,
    required this.item,
    required this.currency,
  });

  @override
  State<ItemDetailHistoryScreen> createState() => _ItemDetailHistoryScreenState();
}

class _ItemDetailHistoryScreenState extends State<ItemDetailHistoryScreen> {
  List<InventoryUnitModel> _units = [];
  bool _isLoadingUnits = true;

  @override
  void initState() {
    super.initState();
    _loadUnits();
  }

  Future<void> _loadUnits() async {
    try {
      final list = await InventoryUnitRepository().getUnitsForProduct(widget.item.id);
      if (mounted) {
        setState(() {
          _units = list;
          _isLoadingUnits = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingUnits = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final storeState = context.watch<StoreCubit>().state;
    final isPro = storeState is StoreLoaded && storeState.store.isPro;

    // Resolve latest updated item definition from InventoryCubit
    final invState = context.watch<InventoryCubit>().state;
    InventoryItemModel item = widget.item;
    if (invState is InventoryLoaded) {
      final found = invState.allItems.where((i) => i.id == widget.item.id).firstOrNull;
      if (found != null) item = found;
    }

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: Text(item.name),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AddEditItemScreen(initialItem: item, isPro: isPro),
                ),
              );
              if (mounted) {
                _loadUnits();
              }
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
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: item.availableQuantity > 0
                                  ? (isDark ? const Color(0xFF142E24) : const Color(0xFFECFDF5))
                                  : (isDark ? const Color(0xFF3B1515) : const Color(0xFFFFDAD6)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${item.availableQuantity}/${item.totalQuantity} Sets Available',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: item.availableQuantity > 0 ? AppColors.primaryLight : AppColors.errorRed,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(item.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      if (item.description != null && item.description!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(item.description!, style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                      ],
                      const SizedBox(height: 14),
                      Divider(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                      const SizedBox(height: 10),

                      // Rates Summary Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildRatePill('Hourly', widget.currency, item.rateHourly, isDark),
                          _buildRatePill('Daily', widget.currency, item.rateDaily, isDark),
                          _buildRatePill('Weekly', widget.currency, item.rateWeekly, isDark),
                          _buildRatePill('Monthly', widget.currency, item.rateMonthly, isDark),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Physical Sets & Components Card List
                const Text('Owned Physical Sets & Component Breakdowns', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),

                if (_isLoadingUnits)
                  const Center(child: CircularProgressIndicator())
                else if (_units.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCard : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    ),
                    child: Text('No physical sets registered. Total owned: ${item.totalQuantity} sets.', style: const TextStyle(fontSize: 12, color: AppColors.secondary)),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _units.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final unit = _units[index];

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkCard : Colors.white,
                          borderRadius: BorderRadius.circular(14),
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
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(unit.assetCode, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                                    ),
                                    const SizedBox(width: 8),
                                    Text('Physical Set #${index + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: unit.isAvailable
                                        ? (isDark ? const Color(0xFF142E24) : const Color(0xFFECFDF5))
                                        : (isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    unit.status.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: unit.isAvailable ? AppColors.primaryLight : AppColors.tertiaryAmber,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            if (unit.components.isNotEmpty) ...[
                              const Text('Component Units:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary)),
                              const SizedBox(height: 4),
                              ...unit.components.map((comp) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 3),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '• ${comp.componentName} (${comp.assetCode})${comp.serialNumber != null ? " [SN: ${comp.serialNumber}]" : ""}',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      Text(
                                        comp.status,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: comp.isAvailable ? AppColors.primaryLight : AppColors.errorRed,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ],
                        ),
                      );
                    },
                  ),

                const SizedBox(height: 20),

                // Rental History List Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Rental History & Invoices', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    Text(
                      'Total Earned: ${widget.currency}${totalRevenue.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (itemLeases.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCard : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    ),
                    child: const Text('No past rental contracts recorded for this equipment.', style: TextStyle(fontSize: 12, color: AppColors.secondary)),
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
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                              child: const Icon(Icons.assignment, color: AppColors.primary, size: 20),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${lease.customer?.name ?? "Customer"} • ${lease.totalPieces} Pcs',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '${DateFormat("dd MMM yyyy").format(lease.startTime)} - ${DateFormat("dd MMM yyyy").format(lease.expectedEndTime)}',
                                    style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${widget.currency}${lease.netRentTotal.toStringAsFixed(0)}',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: isReturned
                                        ? (isDark ? const Color(0xFF142E24) : const Color(0xFFECFDF5))
                                        : (isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    lease.status.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      color: isReturned ? AppColors.primaryLight : AppColors.tertiaryAmber,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRatePill(String label, String currency, double rate, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 9, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
          const SizedBox(height: 2),
          Text(
            '$currency${rate.toInt()}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
