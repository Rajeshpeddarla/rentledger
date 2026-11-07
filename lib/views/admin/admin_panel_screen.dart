import 'package:flutter/material.dart';
import '../../core/config/app_theme.dart';
import '../../data/repositories/admin_repository.dart';
import 'admin_equipment_list_screen.dart';
import 'admin_leases_list_screen.dart';
import 'admin_package_limits_screen.dart';
import 'admin_stores_list_screen.dart';
import 'admin_support_tickets_screen.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final AdminRepository _adminRepo = AdminRepository();
  AdminSystemMetrics _metrics = const AdminSystemMetrics();
  bool _isLoading = true;
  bool _enableCoupons = false;
  bool _enableLoyalty = false;

  @override
  void initState() {
    super.initState();
    _loadMetrics();
  }

  Future<void> _loadMetrics() async {
    setState(() => _isLoading = true);
    final res = await _adminRepo.getSystemMetrics();
    final flags = await _adminRepo.getSystemFeatureFlags();
    if (mounted) {
      setState(() {
        _metrics = res;
        _enableCoupons = flags['enable_coupons'] ?? false;
        _enableLoyalty = flags['enable_loyalty'] ?? false;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleFeatureFlag(String key, bool val) async {
    setState(() {
      if (key == 'enable_coupons') _enableCoupons = val;
      if (key == 'enable_loyalty') _enableLoyalty = val;
    });

    try {
      await _adminRepo.updateSystemFeatureFlag(key, val);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(val ? 'Feature enabled globally for all stores!' : 'Feature disabled globally.'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating setting: $e'), backgroundColor: AppColors.errorRed),
      );
    }
  }

  Widget _buildDashboardCard({
    required BuildContext context,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 26),
                ),
                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            value,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureSwitchCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: value ? color.withValues(alpha: 0.6) : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
          width: value ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: value ? color.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        value ? 'ENABLED' : 'DISABLED',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: value ? color : Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: color,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Super Admin Control Center'),
          ],
        ),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadMetrics,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Global System Feature Controls',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Global Switch 1: Enable Coupons
                    _buildFeatureSwitchCard(
                      title: 'Enable Coupons & Vouchers',
                      subtitle: 'Show/hide discount vouchers feature in Profile for all stores',
                      icon: Icons.discount_outlined,
                      color: Colors.amber.shade900,
                      value: _enableCoupons,
                      onChanged: (val) => _toggleFeatureFlag('enable_coupons', val),
                      isDark: isDark,
                    ),
                    const SizedBox(height: 10),

                    // Global Switch 2: Enable Loyalty
                    _buildFeatureSwitchCard(
                      title: 'Enable Loyalty & Rewards',
                      subtitle: 'Show/hide customer loyalty points program in Profile for all stores',
                      icon: Icons.stars_outlined,
                      color: Colors.purple.shade700,
                      value: _enableLoyalty,
                      onChanged: (val) => _toggleFeatureFlag('enable_loyalty', val),
                      isDark: isDark,
                    ),
                    const SizedBox(height: 10),

                    // Package Limits & Pricing Card
                    _buildDashboardCard(
                      context: context,
                      title: 'Package Limits & Pro Pricing',
                      value: 'SETTINGS',
                      subtitle: 'Configure Pro monthly price, free items limit, monthly leases quota & photo limits',
                      icon: Icons.workspace_premium,
                      color: const Color(0xFF92400E),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const AdminPackageLimitsScreen()),
                        );
                        _loadMetrics();
                      },
                      isDark: isDark,
                    ),
                    const SizedBox(height: 20),

                    Text(
                      'System Metric Overview',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 1. Stores & Accounts Card
                    _buildDashboardCard(
                      context: context,
                      title: 'Stores & Accounts',
                      value: '${_metrics.totalStores}',
                      subtitle: 'Free: ${_metrics.freeStoresCount}  •  Pro: ${_metrics.proStoresCount}',
                      icon: Icons.storefront_outlined,
                      color: AppColors.primary,
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const AdminStoresListScreen()),
                        );
                        _loadMetrics();
                      },
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),

                    // 2. All System Leases Card
                    _buildDashboardCard(
                      context: context,
                      title: 'System Leases Overview',
                      value: '${_metrics.totalLeases}',
                      subtitle: 'View all Reserved, Rented & Returned orders',
                      icon: Icons.assignment_outlined,
                      color: Colors.blue.shade700,
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const AdminLeasesListScreen()),
                        );
                        _loadMetrics();
                      },
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),

                    // 3. Equipment Fleet Card
                    _buildDashboardCard(
                      context: context,
                      title: 'Equipment Fleet',
                      value: '${_metrics.totalItems}',
                      subtitle: 'View all equipment items & live unit status breakdown',
                      icon: Icons.inventory_2_outlined,
                      color: Colors.purple.shade700,
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const AdminEquipmentListScreen()),
                        );
                        _loadMetrics();
                      },
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),

                    // 4. Support Tickets Card
                    _buildDashboardCard(
                      context: context,
                      title: 'Support Ticket Center',
                      value: '${_metrics.activeSupportTickets}',
                      subtitle: 'Active support tickets from Free & Pro stores',
                      icon: Icons.support_agent_outlined,
                      color: Colors.amber.shade900,
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const AdminSupportTicketsScreen()),
                        );
                        _loadMetrics();
                      },
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
