import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/app_theme.dart';
import '../../data/models/lease_model.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../../viewmodels/inventory/inventory_cubit.dart';
import '../../viewmodels/lease/lease_cubit.dart';
import '../../viewmodels/lease/lease_state.dart';
import 'cancel_reservation_screen.dart';

class FutureReservationsScreen extends StatefulWidget {
  const FutureReservationsScreen({super.key});

  @override
  State<FutureReservationsScreen> createState() => _FutureReservationsScreenState();
}

class _FutureReservationsScreenState extends State<FutureReservationsScreen> {
  String _selectedFilter = 'All'; // 'All', 'Today', 'This Week'

  @override
  void initState() {
    super.initState();
    context.read<LeaseCubit>().loadLeases();
  }

  void _makePhoneCall(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final Uri uri = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _dispatchPickup(LeaseModel lease) async {
    try {
      final updated = lease.copyWith(
        status: 'active',
        startTime: DateTime.now(),
      );
      await context.read<LeaseCubit>().returnAndSettle(updated);
      if (!mounted) return;
      await context.read<InventoryCubit>().loadInventory();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reservation for ${lease.customer?.name ?? "Customer"} dispatched successfully!'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error dispatching pickup: $e'),
          backgroundColor: AppColors.errorRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  List<LeaseModel> _getFilteredReservations(List<LeaseModel> allLeases) {
    final reservedList = allLeases.where((l) => l.isFutureReservation || l.status == 'reserved' || l.status == 'upcoming').toList();

    reservedList.sort((a, b) => a.startTime.compareTo(b.startTime));

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final nextWeek = today.add(const Duration(days: 7));

    if (_selectedFilter == 'Today') {
      return reservedList.where((l) {
        final st = DateTime(l.startTime.year, l.startTime.month, l.startTime.day);
        return st.isAtSameMomentAs(today);
      }).toList();
    } else if (_selectedFilter == 'This Week') {
      return reservedList.where((l) {
        return l.startTime.isAfter(today.subtract(const Duration(seconds: 1))) &&
            l.startTime.isBefore(nextWeek);
      }).toList();
    }

    return reservedList;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final storeState = context.watch<StoreCubit>().state;
    final currency = storeState is StoreLoaded ? storeState.store.currencySymbol : '₹';

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('Future Reservations'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      body: BlocBuilder<LeaseCubit, LeaseState>(
        builder: (context, state) {
          if (state is LeaseLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final allLeases = state is LeaseLoaded ? state.allLeases : <LeaseModel>[];
          final displayList = _getFilteredReservations(allLeases);

          return Column(
            children: [
              // Filter Chips Row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: isDark ? AppColors.darkCard : Colors.white,
                child: Row(
                  children: [
                    _buildFilterChip('All', isDark),
                    const SizedBox(width: 8),
                    _buildFilterChip('Today', isDark),
                    const SizedBox(width: 8),
                    _buildFilterChip('This Week', isDark),
                  ],
                ),
              ),
              const Divider(height: 1),

              Expanded(
                child: displayList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.event_seat_outlined, size: 48, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                            const SizedBox(height: 12),
                            const Text('No Upcoming Reservations Found', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(
                              'Future booked equipment rentals will be listed here.',
                              style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: displayList.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final lease = displayList[index];
                          final advancePaid = lease.advanceRentPaid > 0 ? lease.advanceRentPaid : lease.depositPaid;

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
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            lease.customer?.name ?? 'Customer',
                                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                          ),
                                          if (lease.customer?.phone != null && lease.customer!.phone.isNotEmpty)
                                            Text(
                                              'Phone: ${lease.customer!.phone}',
                                              style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                            ),
                                        ],
                                      ),
                                    ),
                                    // Quick Customer Contact Call Container Button
                                    if (lease.customer?.phone != null && lease.customer!.phone.isNotEmpty)
                                      InkWell(
                                        onTap: () => _makePhoneCall(lease.customer!.phone),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: isDark ? AppColors.darkSurfaceLow : const Color(0xFFECFDF5),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: isDark ? AppColors.primary : const Color(0xFFA7F3D0)),
                                          ),
                                          child: Icon(
                                            Icons.phone_outlined,
                                            color: isDark ? AppColors.primaryLight : AppColors.primary,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),

                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: isDark ? AppColors.darkSurfaceLow : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Equipment: ${lease.itemNamesSummary}',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Pick-up: ${DateFormat("dd MMM yyyy, hh:mm a").format(lease.startTime)}',
                                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: isDark ? AppColors.primaryLight : AppColors.primary),
                                          ),
                                          if (advancePaid > 0)
                                            Text(
                                              'Advance: $currency${advancePaid.toStringAsFixed(0)}',
                                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.amber.shade800),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 12),

                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () async {
                                          final res = await Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => CancelReservationScreen(lease: lease),
                                            ),
                                          );
                                          if (res == true && mounted) {
                                            context.read<LeaseCubit>().loadLeases();
                                          }
                                        },
                                        icon: const Icon(Icons.cancel_outlined, size: 14, color: AppColors.errorRed),
                                        label: const Text('Cancel Lease', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.errorRed)),
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(color: AppColors.errorRed),
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () => _dispatchPickup(lease),
                                        icon: const Icon(Icons.check_circle_outline, size: 14),
                                        label: const Text('Dispatch Pickup', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          padding: const EdgeInsets.symmetric(vertical: 8),
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
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isDark) {
    final isSelected = _selectedFilter == label;

    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
        ),
      ),
      selected: isSelected,
      selectedColor: AppColors.primary,
      backgroundColor: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
      onSelected: (_) {
        setState(() {
          _selectedFilter = label;
        });
      },
    );
  }
}
