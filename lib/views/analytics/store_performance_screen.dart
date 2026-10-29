import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../core/config/app_theme.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/lease_model.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../../viewmodels/customer/customer_cubit.dart';
import '../../viewmodels/customer/customer_state.dart';
import '../../viewmodels/inventory/inventory_cubit.dart';
import '../../viewmodels/inventory/inventory_state.dart';
import '../../viewmodels/lease/lease_cubit.dart';
import '../../viewmodels/lease/lease_state.dart';

class StorePerformanceScreen extends StatefulWidget {
  const StorePerformanceScreen({super.key});

  @override
  State<StorePerformanceScreen> createState() => _StorePerformanceScreenState();
}

class _StorePerformanceScreenState extends State<StorePerformanceScreen> {
  String _timeframe = 'this_month'; // 'this_week', 'this_month', 'all_time'

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final storeState = context.watch<StoreCubit>().state;
    final currency = storeState is StoreLoaded ? storeState.store.currencySymbol : '₹';

    final leaseState = context.watch<LeaseCubit>().state;
    final allLeases = leaseState is LeaseLoaded ? leaseState.allLeases : <LeaseModel>[];

    final customerState = context.watch<CustomerCubit>().state;
    final allCustomers = customerState is CustomerLoaded ? customerState.allCustomers : <CustomerModel>[];

    final inventoryState = context.watch<InventoryCubit>().state;
    final allItems = inventoryState is InventoryLoaded ? inventoryState.allItems : [];

    // Filter leases by timeframe
    final now = DateTime.now();
    final filteredLeases = allLeases.where((l) {
      if (_timeframe == 'this_week') {
        final weekAgo = now.subtract(const Duration(days: 7));
        return l.createdAt.isAfter(weekAgo);
      } else if (_timeframe == 'this_month') {
        return l.createdAt.month == now.month && l.createdAt.year == now.year;
      }
      return true;
    }).toList();

    // Financial Metrics
    final totalGrossRevenue = filteredLeases.fold(0.0, (sum, l) => sum + l.netRentTotal);
    final totalTaxCollected = filteredLeases.fold(0.0, (sum, l) => sum + l.taxAmount);
    final totalDamageLateFees = filteredLeases.fold(0.0, (sum, l) => sum + l.damageOrLateFee);
    final totalDiscountsGiven = filteredLeases.fold(0.0, (sum, l) => sum + l.discountAmount);

    // Most Valuable Customers (Ranked by spend)
    final Map<String, double> customerSpendMap = {};
    for (final l in filteredLeases) {
      if (l.customerId.isNotEmpty) {
        customerSpendMap[l.customerId] = (customerSpendMap[l.customerId] ?? 0.0) + l.netRentTotal;
      }
    }
    final sortedCustomerEntries = customerSpendMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Combine both inventory items marked in repair/lost AND lease records with damage/late fees
    final List<Map<String, dynamic>> damagedAndFeeItemsList = [];

    for (final l in filteredLeases) {
      if (l.damageOrLateFee > 0) {
        String name = l.item?.name ?? 'Equipment Item';
        if (l.returnNotes != null && l.returnNotes!.contains('Leased Equipment Items:')) {
          final noteStr = l.returnNotes!.replaceFirst('Leased Equipment Items:', '').trim();
          if (noteStr.isNotEmpty) name = noteStr;
        }
        damagedAndFeeItemsList.add({
          'name': name,
          'sku': l.item?.displaySku ?? 'SKU: #${l.shortId}',
          'fee': l.damageOrLateFee,
          'notes': 'Damage / Late Fee Charged',
          'customerName': l.customer?.name ?? 'Customer',
        });
      }
    }

    for (final i in allItems) {
      if (i.maintenanceCount > 0 || i.lostCount > 0) {
        if (!damagedAndFeeItemsList.any((d) => d['name'] == i.name)) {
          damagedAndFeeItemsList.add({
            'name': i.name,
            'sku': i.displaySku,
            'fee': 0.0,
            'maintenanceCount': i.maintenanceCount,
            'lostCount': i.lostCount,
            'notes': 'Current Depot Stock Issue',
            'customerName': 'Depot Stock',
          });
        }
      }
    }

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('Store Performance & Analytics'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeframe Selector Chip Row
            Row(
              children: [
                _buildTimeframeChip('This Week', 'this_week', isDark),
                const SizedBox(width: 8),
                _buildTimeframeChip('This Month', 'this_month', isDark),
                const SizedBox(width: 8),
                _buildTimeframeChip('All Time', 'all_time', isDark),
              ],
            ),

            const SizedBox(height: 16),

            // Financial Performance Overview Card
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
                  Row(
                    children: [
                      Icon(Icons.query_stats, color: isDark ? AppColors.primaryLight : AppColors.primary),
                      const SizedBox(width: 8),
                      const Text('Revenue & Financial Metrics', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile(
                          label: 'Gross Revenue',
                          value: '$currency${NumberFormat("#,##0").format(totalGrossRevenue)}',
                          color: isDark ? AppColors.primaryLight : AppColors.primary,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricTile(
                          label: 'Taxes Collected',
                          value: '$currency${NumberFormat("#,##0").format(totalTaxCollected)}',
                          color: isDark ? AppColors.primaryLight : AppColors.primary,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile(
                          label: 'Damage/Late Fees',
                          value: '$currency${NumberFormat("#,##0").format(totalDamageLateFees)}',
                          color: AppColors.errorRed,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricTile(
                          label: 'Discounts Given',
                          value: '$currency${NumberFormat("#,##0").format(totalDiscountsGiven)}',
                          color: Colors.amber.shade800,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Revenue Visual Bar Chart Card
            _buildRevenueBarChartCard(currency, filteredLeases, isDark),

            const SizedBox(height: 20),

            // Most Valuable Customers Card
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.workspace_premium, color: Colors.amber.shade800),
                          const SizedBox(width: 8),
                          const Text('Most Valuable Customers', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Text('${sortedCustomerEntries.length} Ranked', style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (sortedCustomerEntries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: Text('No customer spend recorded in this timeframe.')),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: sortedCustomerEntries.length > 5 ? 5 : sortedCustomerEntries.length,
                      separatorBuilder: (_, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final entry = sortedCustomerEntries[index];
                        final customer = allCustomers.firstWhere(
                          (c) => c.id == entry.key,
                          orElse: () => CustomerModel(
                            id: entry.key,
                            storeId: '',
                            name: 'Customer',
                            phone: '-',
                            createdAt: DateTime.now(),
                            updatedAt: DateTime.now(),
                          ),
                        );

                        return Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: AppColors.primary,
                                child: Text('#${index + 1}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(customer.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                    Text('Phone: ${customer.phone}', style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                                  ],
                                ),
                              ),
                              Text(
                                '$currency${NumberFormat("#,##0").format(entry.value)}',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? AppColors.primaryLight : AppColors.primary),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Damaged & Lost Fleet Equipment Card
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: AppColors.errorRed, size: 20),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Damaged & Fee-Charged Items',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('${damagedAndFeeItemsList.length} Recorded', style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (damagedAndFeeItemsList.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: Text('Zero lost, damaged, or fee-charged equipment in fleet.')),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: damagedAndFeeItemsList.length,
                      separatorBuilder: (_, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final entry = damagedAndFeeItemsList[index];
                        final double fee = (entry['fee'] as num?)?.toDouble() ?? 0.0;
                        final int lost = (entry['lostCount'] as num?)?.toInt() ?? 0;
                        final int maint = (entry['maintenanceCount'] as num?)?.toInt() ?? 0;

                        return Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.build_circle_outlined, color: AppColors.errorRed, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry['name'] as String,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      'Client: ${entry['customerName']} • ${entry['sku']}',
                                      style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (fee > 0)
                                    Text('+$currency${fee.toStringAsFixed(0)} Fee', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.errorRed)),
                                  if (lost > 0)
                                    Text('$lost Lost', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.errorRed)),
                                  if (maint > 0)
                                    Text('$maint Damaged', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeframeChip(String label, String value, bool isDark) {
    final isSelected = _timeframe == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _timeframe = value),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : (isDark ? AppColors.darkCard : Colors.white),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isSelected ? AppColors.primary : (isDark ? AppColors.darkBorder : AppColors.lightBorder)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricTile({required String label, required String value, required Color color, required bool isDark}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  Widget _buildRevenueBarChartCard(String currency, List<LeaseModel> leases, bool isDark) {
    // Generate 7-day revenue visualization
    final now = DateTime.now();
    final List<double> dailyRevenues = List.generate(7, (i) {
      final day = now.subtract(Duration(days: 6 - i));
      return leases
          .where((l) => l.createdAt.year == day.year && l.createdAt.month == day.month && l.createdAt.day == day.day)
          .fold(0.0, (sum, l) => sum + l.netRentTotal);
    });

    final maxRevenue = dailyRevenues.reduce((a, b) => a > b ? a : b);
    final maxScale = maxRevenue <= 0 ? 1000.0 : maxRevenue;

    return Container(
      padding: const EdgeInsets.all(16),
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
              const Text('Weekly Revenue Growth Trend', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              Text('Max: $currency${maxScale.toStringAsFixed(0)}', style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (index) {
                final day = now.subtract(Duration(days: 6 - index));
                final dayName = DateFormat('EEE').format(day);
                final rev = dailyRevenues[index];
                final heightFactor = (rev / maxScale).clamp(0.08, 1.0);

                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('$currency${rev.toStringAsFixed(0)}', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 22,
                      height: 80 * heightFactor,
                      decoration: BoxDecoration(
                        color: rev > 0 ? AppColors.primary : (isDark ? AppColors.darkBorder : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(dayName, style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
