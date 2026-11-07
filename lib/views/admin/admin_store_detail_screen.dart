import 'package:flutter/material.dart';
import '../../core/config/app_theme.dart';
import '../../data/repositories/admin_repository.dart';

class AdminStoreDetailScreen extends StatefulWidget {
  final String storeId;

  const AdminStoreDetailScreen({super.key, required this.storeId});

  @override
  State<AdminStoreDetailScreen> createState() => _AdminStoreDetailScreenState();
}

class _AdminStoreDetailScreenState extends State<AdminStoreDetailScreen> with SingleTickerProviderStateMixin {
  final AdminRepository _repo = AdminRepository();
  AdminStoreDetail? _detail;
  bool _isLoading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadDetails();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoading = true);
    final res = await _repo.getStoreDeepDetails(widget.storeId);
    if (mounted) {
      setState(() {
        _detail = res;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleSuspension() async {
    if (_detail == null) return;
    final current = _detail!.store.isSuspended;
    final newSt = !current;

    try {
      await _repo.toggleStoreSuspension(_detail!.store.id, newSt);
      await _loadDetails();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newSt ? 'Store Account Disabled/Suspended!' : 'Store Account Enabled!'),
          backgroundColor: newSt ? AppColors.errorRed : AppColors.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.errorRed),
      );
    }
  }

  Future<void> _changePlanTier(String tier) async {
    if (_detail == null) return;
    try {
      await _repo.updateStorePlanTier(_detail!.store.id, tier);
      await _loadDetails();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Plan tier updated to ${tier.toUpperCase()}!'), backgroundColor: AppColors.primary),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating plan: $e'), backgroundColor: AppColors.errorRed),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        appBar: AppBar(title: const Text('Store Deep Details')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_detail == null) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        appBar: AppBar(title: const Text('Store Details')),
        body: const Center(child: Text('Store details not found.')),
      );
    }

    final store = _detail!.store;
    final currency = store.currencySymbol;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: Text(store.businessName),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        bottom: TabBar(
          controller: _tabController,
          labelColor: isDark ? AppColors.primaryLight : AppColors.primary,
          unselectedLabelColor: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
          indicatorColor: AppColors.primary,
          isScrollable: true,
          tabs: [
            Tab(text: 'Items (${_detail!.items.length})'),
            Tab(text: 'Units (${_detail!.units.length})'),
            Tab(text: 'Customers (${_detail!.customers.length})'),
            Tab(text: 'Coupons (${_detail!.discounts.length})'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Store Header Info Card
          Container(
            padding: const EdgeInsets.all(16),
            color: isDark ? AppColors.darkCard : Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(store.businessName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Text(
                            'Owner: ${store.ownerName ?? "Not specified"} (${store.ownerEmail ?? store.email ?? "No Email"})',
                            style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                          ),
                          if (store.phone != null && store.phone!.isNotEmpty)
                            Text('Phone: ${store.phone}', style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: store.planTier.contains('pro') ? const Color(0xFFFEF3C7) : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            store.planTier.toUpperCase(),
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: store.planTier.contains('pro') ? const Color(0xFF92400E) : Colors.black87),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: store.isSuspended ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            store.isSuspended ? 'SUSPENDED' : 'ACTIVE',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: store.isSuspended ? AppColors.errorRed : const Color(0xFF065F46)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _toggleSuspension,
                        icon: Icon(store.isSuspended ? Icons.check_circle_outline : Icons.block, size: 14),
                        label: Text(store.isSuspended ? 'Enable Account' : 'Disable Account', style: const TextStyle(fontSize: 11)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: store.isSuspended ? AppColors.primary : AppColors.errorRed,
                          side: BorderSide(color: store.isSuspended ? AppColors.primary : AppColors.errorRed),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: PopupMenuButton<String>(
                        onSelected: _changePlanTier,
                        itemBuilder: (ctx) => const [
                          PopupMenuItem(value: 'free', child: Text('Downgrade to Free')),
                          PopupMenuItem(value: 'pro_monthly', child: Text('Upgrade to Pro Monthly')),
                          PopupMenuItem(value: 'pro_annual', child: Text('Upgrade to Pro Annual')),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.workspace_premium, color: Colors.white, size: 14),
                              SizedBox(width: 6),
                              Text('Change Plan', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Items List
                _detail!.items.isEmpty
                    ? const Center(child: Text('No inventory items added.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _detail!.items.length,
                        itemBuilder: (ctx, idx) {
                          final item = _detail!.items[idx];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('Qty: ${item.totalQuantity} | Rate: $currency${item.rateDaily}/day | Category: ${item.category}'),
                              trailing: Text('$currency${item.rateDaily.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          );
                        },
                      ),

                // Tab 2: Physical Units List
                _detail!.units.isEmpty
                    ? const Center(child: Text('No physical unit sets found.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _detail!.units.length,
                        itemBuilder: (ctx, idx) {
                          final unit = _detail!.units[idx];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text('Set #${unit.unitNumber} (${unit.assetCode})', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('Status: ${unit.status.toUpperCase()} | ${unit.components.length} components'),
                            ),
                          );
                        },
                      ),

                // Tab 3: Customers & Loyalty Points List
                _detail!.customers.isEmpty
                    ? const Center(child: Text('No customers registered.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _detail!.customers.length,
                        itemBuilder: (ctx, idx) {
                          final cust = _detail!.customers[idx];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(cust.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('Phone: ${cust.phone} | Leases: ${cust.totalLeasesCount}'),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(8)),
                                child: Text('★ ${cust.loyaltyPoints} pts', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF92400E))),
                              ),
                            ),
                          );
                        },
                      ),

                // Tab 4: Coupons List
                _detail!.discounts.isEmpty
                    ? const Center(child: Text('No coupons/discounts configured.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _detail!.discounts.length,
                        itemBuilder: (ctx, idx) {
                          final disc = _detail!.discounts[idx];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(disc.code, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                              subtitle: Text('${disc.title} (${disc.discountType == 'percentage' ? '${disc.discountValue}% OFF' : '$currency${disc.discountValue} OFF'})'),
                            ),
                          );
                        },
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
