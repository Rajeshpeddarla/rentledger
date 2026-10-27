import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/config/app_theme.dart';
import '../../core/services/admob_service.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../../viewmodels/customer/customer_cubit.dart';
import '../../viewmodels/inventory/inventory_cubit.dart';
import '../../viewmodels/lease/lease_cubit.dart';
import '../dashboard/dashboard_screen.dart';
import '../inventory/inventory_list_screen.dart';
import '../lease/calendar_history_screen.dart';
import '../lease/create_lease_screen.dart';
import '../profile/profile_screen.dart';

class MainBottomNavScreen extends StatefulWidget {
  final int initialIndex;
  const MainBottomNavScreen({super.key, this.initialIndex = 0});

  @override
  State<MainBottomNavScreen> createState() => _MainBottomNavScreenState();
}

class _MainBottomNavScreenState extends State<MainBottomNavScreen> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;

    // Load all initial repositories data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InventoryCubit>().loadInventory();
      context.read<LeaseCubit>().loadLeases();
      context.read<CustomerCubit>().loadCustomers();

      // Preload AdMob interstitial for free users
      AdMobService.instance.preloadInterstitial();
    });
  }

  void _onTabSelected(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final screens = [
      const DashboardScreen(),
      const CalendarHistoryScreen(),
      const InventoryListScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  index: 0,
                  icon: Icons.dashboard_outlined,
                  activeIcon: Icons.dashboard,
                  label: 'Dashboard',
                  isDark: isDark,
                ),
                _buildNavItem(
                  index: 1,
                  icon: Icons.calendar_month_outlined,
                  activeIcon: Icons.calendar_month,
                  label: 'Calendar',
                  isDark: isDark,
                ),
                // Center Quick Action Button (+ Rent Out)
                GestureDetector(
                  onTap: () {
                    final storeState = context.read<StoreCubit>().state;
                    final isPro = storeState is StoreLoaded && storeState.store.isPro;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CreateLeaseScreen(isPro: isPro),
                      ),
                    );
                  },
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
                _buildNavItem(
                  index: 2,
                  icon: Icons.inventory_2_outlined,
                  activeIcon: Icons.inventory_2,
                  label: 'Inventory',
                  isDark: isDark,
                ),
                _buildNavItem(
                  index: 3,
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  label: 'Profile',
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isDark,
  }) {
    final isSelected = _currentIndex == index;
    final activeColor = isDark ? AppColors.primaryLight : AppColors.primary;
    final inactiveColor = isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary;

    return InkWell(
      onTap: () => _onTabSelected(index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              size: 22,
              color: isSelected ? activeColor : inactiveColor,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: 14,
              height: 2.5,
              decoration: BoxDecoration(
                color: isSelected ? activeColor : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
