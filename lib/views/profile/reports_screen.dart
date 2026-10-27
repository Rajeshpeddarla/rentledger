import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../core/config/app_theme.dart';
import '../../core/services/report_export_service.dart';
import '../../data/models/lease_model.dart';
import '../../data/models/store_model.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../../viewmodels/lease/lease_cubit.dart';
import '../../viewmodels/lease/lease_state.dart';
import 'subscription_paywall_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _isExporting = false;

  void _exportCsv(StoreModel store, List<LeaseModel> leases) async {
    if (!store.isPro) {
      _showProGateDialog();
      return;
    }

    setState(() => _isExporting = true);
    try {
      final file = await ReportExportService.instance.exportLeasesCsv(
        store: store,
        leases: leases,
      );
      await ReportExportService.instance.shareFile(file, 'RentLedger Financial CSV Export');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error exporting CSV: $e', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _exportPdf(
    StoreModel store,
    List<LeaseModel> leases,
    double totalRevenue,
    double totalDeposits,
    int activeCount,
    int overdueCount,
  ) async {
    if (!store.isPro) {
      _showProGateDialog();
      return;
    }

    setState(() => _isExporting = true);
    try {
      final file = await ReportExportService.instance.exportSummaryPdf(
        store: store,
        leases: leases,
        totalRevenue: totalRevenue,
        totalDepositsHeld: totalDeposits,
        activeLeasesCount: activeCount,
        overdueCount: overdueCount,
      );
      await ReportExportService.instance.shareFile(file, 'RentLedger Financial Summary PDF');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error exporting PDF: $e', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _showProGateDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pro Feature'),
        content: const Text(
          'Downloading PDF & Excel (CSV) financial reports is a Pro feature. Upgrade to Pro to export comprehensive audit sheets anytime.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SubscriptionPaywallScreen()),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Upgrade to Pro'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final storeState = context.watch<StoreCubit>().state;
    final store = storeState is StoreLoaded ? storeState.store : null;
    final currency = store?.currencySymbol ?? '₹';

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('Financial & Tax Reports'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      body: BlocBuilder<LeaseCubit, LeaseState>(
        builder: (context, leaseState) {
          if (leaseState is! LeaseLoaded || store == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final leases = leaseState.allLeases;
          final totalRevenue = leaseState.totalRevenueEarned;
          final totalDeposits = leaseState.totalDepositsHeld;
          final activeCount = leaseState.activeLeases.length;
          final overdueCount = leaseState.overdueLeases.length;

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Export CTAs Card
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
                          const Text('Export Ledger Reports', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: store.isPro ? AppColors.tertiaryFixed : AppColors.lightSurfaceContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              store.isPro ? 'PRO UNLOCKED' : 'PRO EXPORT',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: store.isPro ? AppColors.tertiary : AppColors.secondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isExporting
                                  ? null
                                  : () => _exportPdf(store, leases, totalRevenue, totalDeposits, activeCount, overdueCount),
                              icon: const Icon(Icons.picture_as_pdf, size: 16),
                              label: const Text('Export PDF', style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isExporting ? null : () => _exportCsv(store, leases),
                              icon: const Icon(Icons.table_chart_outlined, size: 16),
                              label: const Text('Export CSV', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Financial Telemetry Cards
                Text(
                  'Operations Performance',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard('Total Revenue Settled', '$currency${NumberFormat('#,##0').format(totalRevenue)}', AppColors.primary, isDark),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildMetricCard('Completed Returns', '${leases.where((l) => l.status == 'returned').length} Returned', AppColors.tertiaryAmber, isDark),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard('Active Leases', '$activeCount Active', isDark ? AppColors.darkOnSurface : AppColors.slateNavy, isDark),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildMetricCard('Total Leases Recorded', '${leases.length} All Time', isDark ? AppColors.primaryLight : AppColors.primary, isDark),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Recent Leases Breakdown Table
                Text(
                  'Recent Transactions (${leases.length})',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                  ),
                ),
                const SizedBox(height: 10),

                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: leases.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final l = leases[index];
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
                              Text(l.item?.name ?? 'Item', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(height: 2),
                              Text('${l.customer?.name ?? "Customer"} • ${DateFormat('dd MMM yyyy').format(l.startTime)}',
                                  style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                l.status == 'returned'
                                    ? '$currency${l.netRentTotal.toStringAsFixed(0)}'
                                    : 'Deposit: $currency${l.depositPaid.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: l.status == 'returned' ? AppColors.primaryLight : AppColors.tertiaryAmber,
                                ),
                              ),
                              Text(l.status.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                            ],
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
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, Color color, bool isDark) {
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
          Text(label, style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}
