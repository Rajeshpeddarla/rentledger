import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/app_theme.dart';
import '../../core/services/pdf_receipt_service.dart';
import '../../data/models/inventory_unit_model.dart';
import '../../data/models/lease_model.dart';
import '../../data/models/store_model.dart';
import '../../data/repositories/inventory_unit_repository.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../../viewmodels/inventory/inventory_cubit.dart';
import '../../viewmodels/inventory/inventory_state.dart';
import '../../viewmodels/lease/lease_cubit.dart';
import '../../viewmodels/lease/lease_state.dart';
import '../../viewmodels/theme/theme_cubit.dart';
import '../analytics/store_performance_screen.dart';
import '../inventory/add_edit_item_screen.dart';
import '../lease/cancel_reservation_screen.dart';
import '../lease/create_lease_screen.dart';
import '../lease/future_reservations_screen.dart';
import '../lease/take_back_settlement_screen.dart';
import '../../services/notification_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DateTime _selectedRhythmDate = DateTime.now();
  Map<String, String> _unitStatusMap = {};

  @override
  void initState() {
    super.initState();
    _loadUnitStatuses();
  }

  Future<void> _loadUnitStatuses() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    try {
      final Map<String, String> map = {};

      // 1. Load parent unit statuses from inventory_units
      final unitsRes = await client
          .from('inventory_units')
          .select('id, status')
          .eq('store_id', user.id);

      for (final row in (unitsRes as List)) {
        final uId = row['id'] as String?;
        final st = row['status'] as String? ?? 'available';
        if (uId != null) map[uId] = st.toLowerCase();
      }

      // 2. Load component unit statuses from inventory_component_units
      final compsRes = await client
          .from('inventory_component_units')
          .select('id, inventory_unit_id, status')
          .eq('store_id', user.id);

      for (final row in (compsRes as List)) {
        final cId = row['id'] as String?;
        final uId = row['inventory_unit_id'] as String?;
        final st = (row['status'] as String? ?? 'available').toLowerCase();
        if (cId != null) map[cId] = st;
        if (uId != null && st != 'available' && !map.containsKey(uId)) {
          map[uId] = st;
        }
      }

      if (mounted) {
        setState(() {
          _unitStatusMap = map;
        });
      }
    } catch (e) {
      debugPrint('Error loading unit statuses: $e');
    }
  }

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
          await _loadUnitStatuses();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
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
              const SizedBox(height: 16),

              // 3.5. Today's Reservation Pickup Reminder Banner
             // _buildTodayReservationAlertBanner(context, isDark),

              // 3.8. Upcoming Future Reservations Horizontal Strip
              _buildUpcomingReservationsStrip(context, isDark),

              // 4. Mini Calendar Week Strip (Weekly Rental Status)
              _buildWeeklyRhythmStrip(context, isDark),
              const SizedBox(height: 20),

              // 5. Immediate Action List (Due Today & Overdue Leases)
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
            // Store Performance Analytics Button
            IconButton(
              icon: Icon(
                Icons.analytics_outlined,
                size: 22,
                color: isDark ? AppColors.primaryLight : AppColors.slateNavy,
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StorePerformanceScreen()),
                );
              },
              tooltip: 'Store Performance Analytics',
            ),
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
    final storeState = context.watch<StoreCubit>().state;
    final currency = storeState is StoreLoaded ? storeState.store.currencySymbol : '₹';

    final inventoryState = context.watch<InventoryCubit>().state;
    final totalAssets = inventoryState is InventoryLoaded ? inventoryState.allItems.length : 0;
    final availableAssets = inventoryState is InventoryLoaded ? inventoryState.availableStockCount : 0;
    final rentedAssets = inventoryState is InventoryLoaded ? inventoryState.rentedStockCount : 0;

    final leaseState = context.watch<LeaseCubit>().state;
    final activeLeasesCount = leaseState is LeaseLoaded ? leaseState.activeLeases.length : 0;
    final overdueCount = leaseState is LeaseLoaded ? leaseState.overdueLeases.length : 0;
    final depositsHeld = leaseState is LeaseLoaded ? leaseState.totalDepositsHeld : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Operations Telemetry',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StorePerformanceScreen()),
                );
              },
              icon: Icon(Icons.show_chart, size: 14, color: isDark ? AppColors.primaryLight : AppColors.primary),
              label: Text(
                'Analytics ➔',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.primaryLight : AppColors.primary,
                ),
              ),
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
            // Card 4: Deposits Held
            _buildTelemetryCard(
              title: 'Deposits Held',
              value: '$currency${NumberFormat('#,##0').format(depositsHeld)}',
              subtitle: '',
              icon: Icons.lock_clock_outlined,
              iconColor: AppColors.primary,
              iconBg: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceContainer,
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

  // Widget _buildTodayReservationAlertBanner(BuildContext context, bool isDark) {
  //   final leaseState = context.watch<LeaseCubit>().state;
  //   final allLeases = leaseState is LeaseLoaded ? leaseState.allLeases : <LeaseModel>[];
  //
  //   final now = DateTime.now();
  //   final today = DateTime(now.year, now.month, now.day);
  //
  //   final todayPickups = allLeases.where((l) {
  //     if (l.status != 'reserved' && l.status != 'upcoming') return false;
  //     final st = DateTime(l.startTime.year, l.startTime.month, l.startTime.day);
  //     return st.isAtSameMomentAs(today);
  //   }).toList();
  //
  //   if (todayPickups.isEmpty) return const SizedBox.shrink();
  //
  //   final firstPickup = todayPickups.first;
  //   final custName = firstPickup.customer?.name ?? 'Client';
  //   final timeStr = DateFormat('hh:mm a').format(firstPickup.startTime);
  //   final itemStr = firstPickup.itemNamesSummary;
  //
  //   return Container(
  //     margin: const EdgeInsets.only(bottom: 14),
  //     padding: const EdgeInsets.all(12),
  //     decoration: BoxDecoration(
  //       color: isDark ? const Color(0xFF3B2E15) : const Color(0xFFFFFBEB),
  //       borderRadius: BorderRadius.circular(12),
  //       border: Border.all(color: isDark ? const Color(0xFF6B4E15) : const Color(0xFFFDE68A)),
  //     ),
  //     child: Row(
  //       children: [
  //         const Icon(Icons.notifications_active_outlined, color: Colors.amber, size: 22),
  //         const SizedBox(width: 10),
  //         Expanded(
  //           child: Column(
  //             crossAxisAlignment: CrossAxisAlignment.start,
  //             children: [
  //               Text(
  //                 '🔔 Pickup Scheduled Today at $timeStr',
  //                 style: TextStyle(
  //                   fontSize: 12,
  //                   fontWeight: FontWeight.bold,
  //                   color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
  //                 ),
  //               ),
  //               const SizedBox(height: 2),
  //               Text(
  //                 '$custName is picking up $itemStr',
  //                 style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.black87),
  //                 overflow: TextOverflow.ellipsis,
  //               ),
  //             ],
  //           ),
  //         ),
  //         TextButton(
  //           onPressed: () {
  //             Navigator.of(context).push(
  //               MaterialPageRoute(builder: (_) => const FutureReservationsScreen()),
  //             );
  //           },
  //           child: const Text('View ➔', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  Widget _buildUpcomingReservationsStrip(BuildContext context, bool isDark) {
    final leaseState = context.watch<LeaseCubit>().state;
    final allLeases = leaseState is LeaseLoaded ? leaseState.allLeases : <LeaseModel>[];

    final storeState = context.watch<StoreCubit>().state;
    final currency = storeState is StoreLoaded ? storeState.store.currencySymbol : '₹';

    final upcomingList = allLeases.where((l) => l.isFutureReservation || l.status == 'reserved' || l.status == 'upcoming').toList();
    upcomingList.sort((a, b) => a.startTime.compareTo(b.startTime));

    if (upcomingList.isEmpty) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = upcomingList.length == 1
        ? (screenWidth - 20)
        : (screenWidth * 0.88).clamp(330.0, 440.0);

    // Schedule 30-minute local pickup notifications for all upcoming reservations
    for (final lease in upcomingList) {
      NotificationService().schedulePickupNotification(
        leaseId: lease.id,
        title: '⏰ Equipment Pick-up Reminder',
        body: 'Pick-up for ${lease.customer?.name ?? "Client"} (${lease.itemNamesSummary}) is scheduled in 30 minutes!',
        pickupTime: lease.startTime,
      );
    }

    // Check if any upcoming reservation has unit conflicts to adjust container height dynamically
    bool hasAnyUpcomingConflict = false;
    for (final l in upcomingList) {
      for (final line in l.leaseItems) {
        for (final sub in line.leasedSubItems) {
          final uId = sub.leaseItemUnitId;
          final cId = sub.inventoryComponentUnitId;
          String liveSt = 'available';
          if (cId != null && _unitStatusMap.containsKey(cId)) {
            liveSt = _unitStatusMap[cId]!;
          } else if (uId != null && _unitStatusMap.containsKey(uId)) {
            liveSt = _unitStatusMap[uId]!;
          } else {
            liveSt = sub.conditionStatus.toLowerCase();
          }
          if (liveSt == 'maintenance' ||
              liveSt == 'damaged' ||
              liveSt == 'in_maintenance' ||
              liveSt == 'lost' ||
              liveSt == 'needed_restock') {
            hasAnyUpcomingConflict = true;
            break;
          }
        }
        if (hasAnyUpcomingConflict) break;
      }
      if (hasAnyUpcomingConflict) break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.event_seat_outlined, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  'Upcoming Reservations (${upcomingList.length})',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FutureReservationsScreen()),
                );
              },
              child: Text(
                'View All ➔',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.primaryLight : AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: hasAnyUpcomingConflict ? 220.0 : 165.0,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: upcomingList.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (ctx, idx) {
              final lease = upcomingList[idx];
              final advancePaid = lease.advanceRentPaid > 0 ? lease.advanceRentPaid : lease.depositPaid;
              final custName = lease.customer?.name ?? 'Client';
              final phone = lease.customer?.phone ?? '';

              bool hasUnitConflict = false;
              String? conflictUnitCode;
              String? conflictCompName;
              String? conflictStatusLabel;
              String? conflictUnitId;

              for (final line in lease.leaseItems) {
                for (final sub in line.leasedSubItems) {
                  final uId = sub.leaseItemUnitId;
                  final cId = sub.inventoryComponentUnitId;

                  String liveSt = 'available';
                  if (cId != null && _unitStatusMap.containsKey(cId)) {
                    liveSt = _unitStatusMap[cId]!;
                  } else if (uId != null && _unitStatusMap.containsKey(uId)) {
                    liveSt = _unitStatusMap[uId]!;
                  } else {
                    liveSt = sub.conditionStatus.toLowerCase();
                  }

                  if (liveSt == 'maintenance' ||
                      liveSt == 'damaged' ||
                      liveSt == 'in_maintenance' ||
                      liveSt == 'lost' ||
                      liveSt == 'needed_restock') {
                    hasUnitConflict = true;
                    conflictUnitCode = sub.serialNumber ?? 'Assigned Set';
                    conflictCompName = sub.itemName;
                    if (liveSt == 'maintenance' || liveSt == 'damaged') {
                      conflictStatusLabel = 'Damaged';
                    } else if (liveSt == 'in_maintenance') {
                      conflictStatusLabel = 'In Maintenance';
                    } else if (liveSt == 'lost') {
                      conflictStatusLabel = 'Lost';
                    } else if (liveSt == 'needed_restock') {
                      conflictStatusLabel = 'Needed Restock';
                    } else {
                      conflictStatusLabel = 'Unavailable';
                    }
                    conflictUnitId = uId ?? cId;
                    break;
                  }
                }
                if (hasUnitConflict) break;
              }

              return Container(
                width: cardWidth,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: hasUnitConflict ? AppColors.errorRed : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    width: hasUnitConflict ? 1.5 : 1.0,
                  ),
                ),
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
                              Text(
                                custName,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (phone.isNotEmpty)
                                Text(
                                  'Phone: $phone',
                                  style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        if (phone.isNotEmpty)
                          InkWell(
                            onTap: () async {
                              final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
                              final Uri uri = Uri.parse('tel:$cleanPhone');
                              if (await canLaunchUrl(uri)) await launchUrl(uri);
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.darkSurfaceLow : const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: isDark ? AppColors.primary : const Color(0xFFA7F3D0)),
                              ),
                              child: Icon(
                                Icons.phone_outlined,
                                color: isDark ? AppColors.primaryLight : AppColors.primary,
                                size: 16,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurfaceLow : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Equipment: ${lease.itemNamesSummary}',
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Pick-up: ${DateFormat("dd MMM, hh:mm a").format(lease.startTime)}',
                                style: TextStyle(fontSize: 9.0, fontWeight: FontWeight.bold, color: isDark ? AppColors.primaryLight : AppColors.primary),
                              ),
                              if (advancePaid > 0)
                                Text(
                                  'Adv: $currency${advancePaid.toStringAsFixed(0)}',
                                  style: TextStyle(fontSize: 9.0, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    if (hasUnitConflict) ...[
                      const SizedBox(height: 4),
                      Text(
                        '⚠️ Conflict: $conflictUnitCode ($conflictCompName) is $conflictStatusLabel',
                        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppColors.errorRed),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    const Spacer(),

                    // Action Buttons Layout
                    if (hasUnitConflict) ...[
                      Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _openSwapUnitModal(context, lease, conflictUnitId),
                                  icon: const Icon(Icons.swap_horiz, size: 14),
                                  label: const Text('Swap Unit', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    minimumSize: const Size(0, 36),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _openChangeUnitStatusModal(context, lease, conflictUnitId),
                                  icon: const Icon(Icons.build_outlined, size: 14),
                                  label: const Text('Status', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    minimumSize: const Size(0, 36),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _openRescheduleModal(context, lease),
                                  icon: const Icon(Icons.edit_calendar, size: 14),
                                  label: const Text('Reschedule', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    minimumSize: const Size(0, 36),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final lCubit = context.read<LeaseCubit>();
                                    final res = await Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => CancelReservationScreen(lease: lease)),
                                    );
                                    if (res == true && mounted) {
                                      lCubit.loadLeases();
                                    }
                                  },
                                  icon: const Icon(Icons.cancel_outlined, size: 14, color: AppColors.errorRed),
                                  label: const Text('Cancel', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.errorRed)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: AppColors.errorRed),
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    minimumSize: const Size(0, 36),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: ElevatedButton.icon(
                              onPressed: () => _openConfirmPickupModal(context, lease),
                              icon: const Icon(Icons.check_circle_outline, size: 14),
                              label: const Text('Confirm Pickup', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                minimumSize: const Size(0, 36),
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            flex: 2,
                            child: OutlinedButton.icon(
                              onPressed: () => _openRescheduleModal(context, lease),
                              icon: const Icon(Icons.edit_calendar, size: 14),
                              label: const Text('Reschedule', style: TextStyle(fontSize: 10.0, fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                minimumSize: const Size(0, 36),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            flex: 2,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final lCubit = context.read<LeaseCubit>();
                                final res = await Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => CancelReservationScreen(lease: lease)),
                                );
                                if (res == true && mounted) {
                                  lCubit.loadLeases();
                                }
                              },
                              icon: const Icon(Icons.cancel_outlined, size: 14, color: AppColors.errorRed),
                              label: const Text('Cancel', style: TextStyle(fontSize: 10.0, fontWeight: FontWeight.bold, color: AppColors.errorRed)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.errorRed),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                minimumSize: const Size(0, 36),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _openRescheduleModal(BuildContext context, LeaseModel lease) async {
    final client = Supabase.instance.client;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    DateTime newStart = lease.startTime;
    DateTime newEnd = lease.expectedEndTime;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.edit_calendar_outlined, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Reschedule Booking: ${lease.itemNamesSummary}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Client: ${lease.customer?.name ?? "Customer"}',
                    style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                  ),
                  const SizedBox(height: 16),

                  // Pick New Start Date & Time
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurfaceLow : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? AppColors.darkBorder : const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('New Pick-up Start Time:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(
                              DateFormat('dd MMM yyyy, hh:mm a').format(newStart),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: modalCtx,
                              initialDate: newStart,
                              firstDate: DateTime.now().subtract(const Duration(days: 1)),
                              lastDate: DateTime.now().add(const Duration(days: 180)),
                            );
                            if (d == null) return;
                            final t = await showTimePicker(
                              context: modalCtx,
                              initialTime: TimeOfDay.fromDateTime(newStart),
                            );
                            final time = t ?? TimeOfDay.fromDateTime(newStart);
                            setModalState(() {
                              newStart = DateTime(d.year, d.month, d.day, time.hour, time.minute);
                              if (newEnd.isBefore(newStart)) {
                                newEnd = newStart.add(const Duration(days: 1));
                              }
                            });
                          },
                          icon: const Icon(Icons.calendar_today, size: 14),
                          label: const Text('Change', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Pick New End Date & Time
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurfaceLow : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? AppColors.darkBorder : const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('New Expected Return Time:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(
                              DateFormat('dd MMM yyyy, hh:mm a').format(newEnd),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: modalCtx,
                              initialDate: newEnd.isBefore(newStart) ? newStart : newEnd,
                              firstDate: DateTime(newStart.year, newStart.month, newStart.day),
                              lastDate: DateTime.now().add(const Duration(days: 180)),
                            );
                            if (d == null) return;
                            final t = await showTimePicker(
                              context: modalCtx,
                              initialTime: TimeOfDay.fromDateTime(newEnd),
                            );
                            final time = t ?? TimeOfDay.fromDateTime(newEnd);
                            DateTime endCandidate = DateTime(d.year, d.month, d.day, time.hour, time.minute);
                            if (!endCandidate.isAfter(newStart)) {
                              endCandidate = newStart.add(const Duration(hours: 1));
                            }
                            setModalState(() {
                              newEnd = endCandidate;
                            });
                          },
                          icon: const Icon(Icons.calendar_today, size: 14),
                          label: const Text('Change', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size.fromHeight(46),
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Confirm Reschedule', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      Navigator.pop(modalCtx);
                      try {
                        await client.from('leases').update({
                          'start_time': newStart.toIso8601String(),
                          'expected_end_time': newEnd.toIso8601String(),
                          'updated_at': DateTime.now().toIso8601String(),
                        }).eq('id', lease.id);

                        await client.from('lease_item_units').update({
                          'checked_out_at': newStart.toIso8601String(),
                        }).eq('lease_id', lease.id);

                        // Schedule local notification 30 minutes before new pick-up time
                        NotificationService().schedulePickupNotification(
                          leaseId: lease.id,
                          title: '⏰ Rescheduled Pick-up Reminder',
                          body: 'Pick-up for ${lease.customer?.name ?? "Client"} (${lease.itemNamesSummary}) is scheduled in 30 minutes!',
                          pickupTime: newStart,
                        );

                        if (!mounted) return;
                        await context.read<LeaseCubit>().loadLeases();

                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Rescheduled booking for ${lease.customer?.name ?? "Client"} to ${DateFormat("dd MMM, hh:mm a").format(newStart)}!'),
                            backgroundColor: AppColors.primary,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error rescheduling booking: $e'),
                            backgroundColor: AppColors.errorRed,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openConfirmPickupModal(BuildContext context, LeaseModel lease) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();

    final diffMinutes = now.difference(lease.startTime).inMinutes;
    final bool isEarly = diffMinutes < -15;
    final bool isLate = diffMinutes > 15;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: isDark ? AppColors.darkCard : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                isEarly ? Icons.timer_outlined : (isLate ? Icons.history_toggle_off : Icons.check_circle_outline),
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isEarly
                      ? 'Early Pick-up Confirmation'
                      : (isLate ? 'Late Pick-up Confirmation' : 'Confirm Pick-up & Rent'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Client: ${lease.customer?.name ?? "Customer"}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                'Equipment: ${lease.itemNamesSummary}',
                style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurfaceLow : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isDark ? AppColors.darkBorder : const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scheduled Pick-up: ${DateFormat("dd MMM yyyy, hh:mm a").format(lease.startTime)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: (isEarly || isLate) ? Colors.amber.shade900 : AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Actual Pick-up Time (Now): ${DateFormat("dd MMM yyyy, hh:mm a").format(now)}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (isEarly) ...[
                Text(
                  'Customer is picking up equipment ${-diffMinutes} minutes before scheduled time. Rental start time will be updated to current time (${DateFormat("hh:mm a").format(now)}).',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ] else if (isLate) ...[
                Text(
                  'Customer is picking up equipment $diffMinutes minutes after scheduled time. Rental start time will be updated to current time (${DateFormat("hh:mm a").format(now)}).',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ] else ...[
                const Text(
                  'Confirm that customer has picked up the equipment? Rental start time will be recorded as current time, order status will change to RENTED, and assigned physical units will be marked RENTED.',
                  style: TextStyle(fontSize: 11.5),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.secondary)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: const Text('Confirm & Rent', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        );
      },
    );

    if (confirm == true && mounted) {
      try {
        final lCubit = context.read<LeaseCubit>();
        final iCubit = context.read<InventoryCubit>();

        await lCubit.confirmReservation(
          lease,
          actualPickupTime: now,
        );

        if (!mounted) return;
        await iCubit.loadInventory();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Reservation for ${lease.customer?.name ?? "Customer"} confirmed and marked as RENTED!',
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error confirming pickup: $e'),
            backgroundColor: AppColors.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _openSwapUnitModal(BuildContext context, LeaseModel lease, String? currentUnitId) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    try {
      final unitRepo = InventoryUnitRepository();
      final units = await unitRepo.getUnitsForProduct(lease.itemId);
      final availableUnits = units.where((u) => u.isAvailable && u.id != currentUnitId).toList();

      if (!mounted) return;

      if (availableUnits.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No other available physical units found for this equipment.'),
            backgroundColor: AppColors.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: isDark ? AppColors.darkCard : Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            minChildSize: 0.3,
            maxChildSize: 0.85,
            builder: (sheetCtx, scrollController) {
              return Padding(
                padding: const EdgeInsets.all(20),
                child: ListView(
                  controller: scrollController,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.swap_horiz_outlined, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Swap Unit for ${lease.itemNamesSummary}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select an available physical unit to assign to this reservation:',
                      style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                    ),
                    const SizedBox(height: 16),

                    ...availableUnits.map((u) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurfaceLow : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? AppColors.darkBorder : const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '📦 Set #${u.unitNumber} (${u.assetCode})',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${u.components.length} components included',
                                    style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () async {
                                Navigator.pop(ctx);
                                try {
                                  if (currentUnitId != null && currentUnitId.isNotEmpty) {
                                    await client
                                        .from('lease_item_units')
                                        .update({'inventory_unit_id': u.id})
                                        .eq('lease_id', lease.id)
                                        .eq('inventory_unit_id', currentUnitId);

                                    await client
                                        .from('leased_sub_items')
                                        .update({'lease_item_unit_id': u.id, 'condition_status': 'available'})
                                        .eq('lease_id', lease.id)
                                        .eq('lease_item_unit_id', currentUnitId);
                                  }

                                  if (!mounted) return;
                                  await _loadUnitStatuses();
                                  await context.read<LeaseCubit>().loadLeases();
                                  await context.read<InventoryCubit>().loadInventory();

                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Swapped reservation to Set #${u.unitNumber} (${u.assetCode})!'),
                                      backgroundColor: AppColors.primary,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                } catch (e) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error swapping unit: $e'),
                                      backgroundColor: AppColors.errorRed,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                              child: const Text('Assign Unit', style: TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      debugPrint('Error opening swap modal: $e');
    }
  }

  Future<void> _openChangeUnitStatusModal(BuildContext context, LeaseModel lease, String? currentUnitId) async {
    final client = Supabase.instance.client;
    if (currentUnitId == null || currentUnitId.isEmpty) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    try {
      final unitRes = await client.from('inventory_units').select('*').eq('id', currentUnitId).single();
      final unit = InventoryUnitModel.fromJson(unitRes);

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        backgroundColor: isDark ? AppColors.darkCard : Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) {
          return Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.build_outlined, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Change Status: Set #${unit.unitNumber} (${unit.assetCode})',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Current status: ${unit.status.toUpperCase()}. Change to "Available" if unit is repaired and ready for handover:',
                  style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                ),
                const SizedBox(height: 16),

                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(44),
                  ),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Mark Repaired & Available', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await client.from('inventory_units').update({'status': 'available', 'updated_at': DateTime.now().toIso8601String()}).eq('id', unit.id);
                      await client.from('inventory_component_units').update({'status': 'available', 'updated_at': DateTime.now().toIso8601String()}).eq('inventory_unit_id', unit.id);
                      await client.from('leased_sub_items').update({'condition_status': 'available', 'updated_at': DateTime.now().toIso8601String()}).eq('lease_id', lease.id).eq('lease_item_unit_id', unit.id);

                      if (!mounted) return;
                      await _loadUnitStatuses();
                      await context.read<LeaseCubit>().loadLeases();
                      await context.read<InventoryCubit>().loadInventory();

                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Unit Set #${unit.unitNumber} marked Available!'),
                          backgroundColor: AppColors.primary,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error updating status: $e'),
                          backgroundColor: AppColors.errorRed,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      debugPrint('Error opening status modal: $e');
    }
  }

  Widget _buildWeeklyRhythmStrip(BuildContext context, bool isDark) {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    final leaseState = context.watch<LeaseCubit>().state;
    final allLeases = leaseState is LeaseLoaded ? leaseState.allLeases : <LeaseModel>[];

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
                    'Weekly Rental Status',
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
                        : (isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow),
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

    final String itemName = lease.itemNamesSummary;

    return InkWell(
      onTap: () {
        final storeState = context.read<StoreCubit>().state;
        final store = storeState is StoreLoaded ? storeState.store : null;

        if (isReturned) {
          _showReadOnlySettlementDetailsModal(context, lease, store, isDark);
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TakeBackSettlementScreen(lease: lease),
            ),
          );
        }
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
                          itemName,
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

  void _showReadOnlySettlementDetailsModal(BuildContext context, LeaseModel lease, StoreModel? store, bool isDark) {
    final currency = store?.currencySymbol ?? '₹';
    final returnTime = lease.actualReturnTime ?? lease.updatedAt;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalCtx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkBorder : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.verified, color: AppColors.primaryLight, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Returned Lease Summary',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Settlement ID: SR-${lease.shortId} • Completed & Closed',
                          style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('RETURNED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.primaryLight)),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Details Panel
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                ),
                child: Column(
                  children: [
                    _buildDetailRow('Rented Equipment', '${lease.quantity}x ${lease.item?.name ?? "Equipment"}', isDark),
                    const SizedBox(height: 6),
                    _buildDetailRow('Client Name', lease.customer?.name ?? 'Customer', isDark),
                    const SizedBox(height: 6),
                    _buildDetailRow('Client Phone', lease.customer?.phone ?? '-', isDark),
                    const SizedBox(height: 6),
                    _buildDetailRow('Handover Date', DateFormat('dd MMM yyyy, hh:mm a').format(lease.startTime), isDark),
                    const SizedBox(height: 6),
                    _buildDetailRow('Returned On', DateFormat('dd MMM yyyy, hh:mm a').format(returnTime), isDark),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Financial Summary Panel
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                ),
                child: Column(
                  children: [
                    _buildDetailRow('Base Rent Charges', '$currency${lease.calculatedRent.toStringAsFixed(2)}', isDark),
                    if (lease.discountAmount > 0) ...[
                      const SizedBox(height: 4),
                      _buildDetailRow('Discount Applied', '-$currency${lease.discountAmount.toStringAsFixed(2)}', isDark, isGreen: true),
                    ],
                    if (lease.damageOrLateFee > 0) ...[
                      const SizedBox(height: 4),
                      _buildDetailRow('Damage / Late Fee', '+$currency${lease.damageOrLateFee.toStringAsFixed(2)}', isDark, isRed: true),
                    ],
                    const SizedBox(height: 6),
                    const Divider(),
                    const SizedBox(height: 6),
                    _buildDetailRow('Total Net Rent Paid', '$currency${lease.netRentTotal.toStringAsFixed(2)}', isDark, isBold: true),
                    const SizedBox(height: 4),
                    _buildDetailRow('Upfront Deposit Paid', '$currency${lease.depositPaid.toStringAsFixed(2)}', isDark),
                  ],
                ),
              ),

              if (lease.returnNotes != null && lease.returnNotes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Return Notes & Condition:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                const SizedBox(height: 4),
                Text(
                  lease.returnNotes!,
                  style: const TextStyle(fontSize: 12),
                ),
              ],

              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        if (store == null) return;
                        final pdfFile = await PdfReceiptService.instance.generateReturnSettlementReceipt(store: store, lease: lease);
                        await PdfReceiptService.instance.printReceipt(pdfFile);
                      },
                      icon: const Icon(Icons.print_outlined, size: 18),
                      label: const Text('Print Settlement PDF', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        if (store == null) return;
                        final pdfFile = await PdfReceiptService.instance.generateReturnSettlementReceipt(store: store, lease: lease);
                        final msg = 'Return settlement receipt for ${lease.item?.name} from ${store.businessName}';
                        await PdfReceiptService.instance.shareReceipt(pdfFile, msg);
                      },
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text('Share PDF', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, bool isDark, {bool isBold = false, bool isGreen = false, bool isRed = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: isGreen ? AppColors.primaryLight : (isRed ? AppColors.errorRed : (isDark ? Colors.white : AppColors.lightOnSurface)),
          ),
        ),
      ],
    );
  }

  Widget _buildImmediateAttentionSection(BuildContext context, bool isDark) {
    final storeState = context.watch<StoreCubit>().state;
    final currency = storeState is StoreLoaded ? storeState.store.currencySymbol : '₹';

    return BlocBuilder<LeaseCubit, LeaseState>(
      builder: (context, state) {
        if (state is! LeaseLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        final attentionLeases = [
          ...state.overdueLeases,
          ...state.dueTodayLeases,
        ];

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
                  final phone = lease.customer?.phone.trim() ?? '';

                  final String itemName = '${lease.quantity > 1 ? '${lease.quantity}x ' : ''}${lease.item?.name ?? "Equipment Item"}';

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
                                          itemName,
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
                                    '${lease.customer?.name ?? "Customer"} • ${phone.isNotEmpty ? phone : "-"}',
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
                              'Deposit held: $currency${lease.depositPaid.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (phone.isNotEmpty) ...[
                                  IconButton(
                                    icon: const Icon(Icons.phone_forwarded, size: 18, color: AppColors.primary),
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(6),
                                    tooltip: 'Call ${lease.customer?.name ?? "Customer"}',
                                    onPressed: () async {
                                      final uri = Uri.parse('tel:$phone');
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(uri);
                                      } else {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Cannot launch phone call to $phone')),
                                          );
                                        }
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 6),
                                ],
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
