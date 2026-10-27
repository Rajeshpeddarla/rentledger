import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../core/config/app_theme.dart';
import '../../data/models/lease_model.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../../viewmodels/inventory/inventory_cubit.dart';
import '../../viewmodels/inventory/inventory_state.dart';
import '../../viewmodels/lease/lease_cubit.dart';
import '../../viewmodels/lease/lease_state.dart';
import '../../viewmodels/theme/theme_cubit.dart';
import '../inventory/add_edit_item_screen.dart';
import '../lease/create_lease_screen.dart';
import '../lease/take_back_settlement_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DateTime _selectedRhythmDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(68),
        child: _buildDashboardHeader(context, isDark),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          context.read<InventoryCubit>().loadInventory();
          context.read<LeaseCubit>().loadLeases();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Store Status Banner
              _buildLiveStatusBanner(context, isDark),
              const SizedBox(height: 14),

              // 2. Quick Action Dual CTAs
              _buildQuickActionCtas(context, isDark),
              const SizedBox(height: 20),

              // 3. Operations Telemetry KPI 2x2 Grid
              _buildTelemetryGrid(context, isDark),
              const SizedBox(height: 20),

              // 4. Mini Calendar Week Strip
              _buildWeeklyRhythmStrip(context, isDark),
              const SizedBox(height: 20),

              // 5. Quick Attention List (Due Today & Overdue Leases)
              _buildImmediateAttentionSection(context, isDark),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardHeader(BuildContext context, bool isDark) {
    return BlocBuilder<StoreCubit, StoreState>(
      builder: (context, state) {
        final store = state is StoreLoaded ? state.store : null;
        final businessName = store?.businessName ?? 'Apex Rentals & Tools';
        final isPro = store?.isPro ?? false;

        return AppBar(
          automaticallyImplyLeading: false,
          elevation: 0,
          backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          titleSpacing: 16,
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.assignment_turned_in, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            businessName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isPro ? AppColors.tertiaryFixed : AppColors.primaryFixed,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isPro ? Icons.verified : Icons.bolt,
                                size: 10,
                                color: isPro ? AppColors.tertiary : AppColors.onPrimaryFixed,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                isPro ? 'PRO GOLD' : 'FREE',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: isPro ? AppColors.onTertiaryFixed : AppColors.onPrimaryFixed,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Live Operations Dashboard',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            // Theme Mode Toggle
            IconButton(
              icon: Icon(
                isDark ? Icons.light_mode : Icons.dark_mode,
                size: 20,
                color: isDark ? AppColors.primaryLight : AppColors.slateNavy,
              ),
              onPressed: () {
                context.read<ThemeCubit>().toggleTheme();
              },
              tooltip: 'Toggle Theme',
            ),
            const SizedBox(width: 8),
          ],
        );
      },
    );
  }

  Widget _buildLiveStatusBanner(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Store is Live & Operational',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                  ),
                ),
                Text(
                  'Real-time deposit custody & lease monitoring',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Accepting',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.primaryLight : AppColors.primary,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(Icons.check_circle, size: 12, color: isDark ? AppColors.primaryLight : AppColors.primary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionCtas(BuildContext context, bool isDark) {
    final storeState = context.watch<StoreCubit>().state;
    final isPro = storeState is StoreLoaded && storeState.store.isPro;

    return Row(
      children: [
        // Primary CTA: Rent Out Item
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CreateLeaseScreen(isPro: isPro),
                ),
              );
            },
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: const Text('Rent Out Item'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Secondary CTA: Add Inventory Item
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AddEditItemScreen(isPro: isPro),
                ),
              );
            },
            icon: Icon(
              Icons.inventory_2_outlined,
              size: 18,
              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
            ),
            label: Text(
              '+ Add Inventory',
              style: TextStyle(
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: isDark ? AppColors.darkCard : Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTelemetryGrid(BuildContext context, bool isDark) {
    final inventoryState = context.watch<InventoryCubit>().state;
    final totalAssets = inventoryState is InventoryLoaded ? inventoryState.totalStockCount : 5;

    final leaseState = context.watch<LeaseCubit>().state;
    final activeLeasesCount = leaseState is LeaseLoaded ? leaseState.activeLeases.length : 0;
    final overdueCount = leaseState is LeaseLoaded ? leaseState.overdueLeases.length : 0;
    final returnedCount = leaseState is LeaseLoaded
        ? leaseState.allLeases.where((l) => l.status == 'returned').length
        : 0;

    final rentedAssets = inventoryState is InventoryLoaded
        ? (inventoryState.rentedStockCount > 0 ? inventoryState.rentedStockCount : activeLeasesCount)
        : activeLeasesCount;
    final availableAssets = (totalAssets - rentedAssets).clamp(0, totalAssets);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Operations',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
            ),
            Row(
              children: [
                Icon(Icons.sync, size: 14, color: isDark ? AppColors.primaryLight : AppColors.primary),
                const SizedBox(width: 4),
                Text(
                  'Realtime Ledger',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.primaryLight : AppColors.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.45,
          children: [
            // Card 1: Total Assets
            _buildTelemetryCard(
              title: 'Total Assets',
              value: '$totalAssets',
              subtitle: '$availableAssets ready • $rentedAssets rented',
              icon: Icons.construction,
              iconColor: AppColors.primary,
              iconBg: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceContainer,
              isDark: isDark,
            ),
            // Card 2: Active Leases
            _buildTelemetryCard(
              title: 'Active Leases',
              value: '$activeLeasesCount',
              subtitle: 'Contracted out',
              icon: Icons.local_shipping_outlined,
              iconColor: AppColors.primary,
              iconBg: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceContainer,
              isDark: isDark,
            ),
            // Card 3: Overdue Returns
            _buildTelemetryCard(
              title: 'Overdue Returns',
              value: '$overdueCount',
              subtitle: overdueCount > 0 ? 'Urgent attention' : 'All on time',
              icon: Icons.warning_amber_rounded,
              iconColor: overdueCount > 0 ? AppColors.errorRed : AppColors.tertiaryAmber,
              iconBg: overdueCount > 0
                  ? (isDark ? const Color(0xFF3B1515) : const Color(0xFFFFDAD6))
                  : (isDark ? AppColors.darkSurfaceLow : AppColors.tertiaryFixed),
              isDark: isDark,
              isAlert: overdueCount > 0,
            ),
            // Card 4: Completed Returns
            _buildTelemetryCard(
              title: 'Completed Returns',
              value: '$returnedCount',
              subtitle: 'Returned to fleet',
              icon: Icons.assignment_turned_in_outlined,
              iconColor: AppColors.primaryLight,
              iconBg: isDark ? AppColors.darkSurfaceLow : const Color(0xFFD1F2D9),
              isDark: isDark,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTelemetryCard({
    required String title,
    required String value,
    String? subtitle,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required bool isDark,
    bool isAlert = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isAlert
            ? (isDark ? const Color(0xFF231417) : const Color(0xFFFFF1F2))
            : (isDark ? AppColors.darkCard : Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isAlert
              ? (isDark ? const Color(0xFF6B1D22) : const Color(0xFFFECACA))
              : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: isAlert
                      ? (isDark ? const Color(0xFFFF8B8B) : AppColors.error)
                      : (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface),
                ),
              ),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isAlert
                        ? (isDark ? const Color(0xFFFFB4AB) : AppColors.error)
                        : (isDark ? AppColors.primaryLight : AppColors.primary),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyRhythmStrip(BuildContext context, bool isDark) {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    final leaseState = context.watch<LeaseCubit>().state;
    final allLeases = leaseState is LeaseLoaded ? leaseState.allLeases : <LeaseModel>[];

    // Find leases for the currently selected rhythm date
    final selectedStart = DateTime(_selectedRhythmDate.year, _selectedRhythmDate.month, _selectedRhythmDate.day, 0, 0, 0);
    final selectedEnd = DateTime(_selectedRhythmDate.year, _selectedRhythmDate.month, _selectedRhythmDate.day, 23, 59, 59);
    final selectedDayLeases = allLeases.where((l) {
      final s = l.startTime;
      final e = l.actualReturnTime ?? l.expectedEndTime;
      return s.isBefore(selectedEnd) && e.isAfter(selectedStart);
    }).toList();

    final isTodaySelected = _selectedRhythmDate.year == now.year &&
        _selectedRhythmDate.month == now.month &&
        _selectedRhythmDate.day == now.day;

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.date_range, size: 16, color: isDark ? AppColors.primaryLight : AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Weekly Rental Rhythm',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    ),
                  ),
                ],
              ),
              Text(
                'This Week',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (index) {
              final dayDate = weekStart.add(Duration(days: index));
              final isSelected = dayDate.day == _selectedRhythmDate.day &&
                  dayDate.month == _selectedRhythmDate.month &&
                  dayDate.year == _selectedRhythmDate.year;

              final isToday = dayDate.day == now.day &&
                  dayDate.month == now.month &&
                  dayDate.year == now.year;

              final dayStart = DateTime(dayDate.year, dayDate.month, dayDate.day, 0, 0, 0);
              final dayEnd = DateTime(dayDate.year, dayDate.month, dayDate.day, 23, 59, 59);
              final dayLeases = allLeases.where((l) {
                final s = l.startTime;
                final e = l.actualReturnTime ?? l.expectedEndTime;
                return s.isBefore(dayEnd) && e.isAfter(dayStart);
              }).toList();
              final hasLeases = dayLeases.isNotEmpty;

              return InkWell(
                onTap: () {
                  setState(() {
                    _selectedRhythmDate = dayDate;
                  });
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 40,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : (isToday
                            ? (isDark ? const Color(0xFF1B3B2B) : const Color(0xFFD1FAE5))
                            : (isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow)),
                    borderRadius: BorderRadius.circular(10),
                    border: isToday && !isSelected
                        ? Border.all(color: AppColors.primary, width: 1.5)
                        : null,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            )
                          ]
                        : null,
                  ),
                  child: Column(
                    children: [
                      Text(
                        weekdays[index],
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? Colors.white
                              : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${dayDate.day}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: isSelected
                              ? Colors.white
                              : (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white
                              : (hasLeases ? AppColors.tertiaryAmber : Colors.transparent),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 14),
          Divider(
            height: 1,
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isTodaySelected
                    ? "Today's Rentals (${selectedDayLeases.length})"
                    : "${DateFormat('EEE, dd MMM').format(_selectedRhythmDate)} Rentals (${selectedDayLeases.length})",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                ),
              ),
              if (selectedDayLeases.isNotEmpty)
                Text(
                  'Tap to manage',
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (selectedDayLeases.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Text(
                  'No rentals active or scheduled on this date.',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                  ),
                ),
              ),
            )
          else
            ...selectedDayLeases.map((lease) => _buildRhythmLeaseTile(context, lease, isDark)),
        ],
      ),
    );
  }

  Widget _buildRhythmLeaseTile(BuildContext context, LeaseModel lease, bool isDark) {
    final isOverdue = lease.isOverdue;
    final isReturned = lease.status == 'returned';
    final statusColor = isReturned
        ? Colors.grey
        : (isOverdue ? AppColors.errorRed : AppColors.primaryLight);

    final statusText = isReturned
        ? 'RETURNED'
        : (isOverdue ? 'OVERDUE' : lease.status.toUpperCase());

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TakeBackSettlementScreen(lease: lease),
          ),
        );
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.handyman, size: 18, color: statusColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          lease.item?.name ?? 'Equipment Item',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${lease.customer?.name ?? "Client"} • Return: ${DateFormat('dd MMM, hh:mm a').format(lease.expectedEndTime)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImmediateAttentionSection(BuildContext context, bool isDark) {
    return BlocBuilder<LeaseCubit, LeaseState>(
      builder: (context, state) {
        if (state is! LeaseLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        final attentionLeases = [
          ...state.overdueLeases,
          ...state.dueTodayLeases,
        ];

        // Deduplicate
        final uniqueLeases = attentionLeases.toSet().toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'Immediate Action Leases',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: uniqueLeases.isNotEmpty
                            ? (isDark ? const Color(0xFF4A1A1E) : const Color(0xFFFFDAD6))
                            : (isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${uniqueLeases.length}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: uniqueLeases.isNotEmpty ? AppColors.errorRed : AppColors.secondary,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Due Today / Overdue',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (uniqueLeases.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                ),
                child: Column(
                  children: [
                    Icon(Icons.check_circle_outline, size: 36, color: AppColors.primaryLight),
                    const SizedBox(height: 8),
                    Text(
                      'All leases are current and healthy!',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      ),
                    ),
                    Text(
                      'No overdue items or overdue security deposits right now.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: uniqueLeases.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final lease = uniqueLeases[index];
                  final isOverdue = lease.isOverdue;

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCard : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isOverdue
                            ? (isDark ? const Color(0xFF6B1D22) : const Color(0xFFFECACA))
                            : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.handyman, size: 24, color: AppColors.primary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          lease.item?.name ?? 'Equipment Item',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isOverdue
                                              ? (isDark ? const Color(0xFF3B1515) : const Color(0xFFFFDAD6))
                                              : (isDark ? const Color(0xFF3B2E15) : AppColors.tertiaryFixed),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          isOverdue ? 'OVERDUE' : 'DUE TODAY',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            color: isOverdue ? AppColors.errorRed : AppColors.tertiary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${lease.customer?.name ?? "Customer"} • ${lease.customer?.phone ?? "-"}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Deposit held: ₹${lease.depositPaid.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => TakeBackSettlementScreen(lease: lease),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isOverdue ? AppColors.errorRed : AppColors.primary,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('Settle / Take Back', style: TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}
