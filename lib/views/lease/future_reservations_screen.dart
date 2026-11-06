import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/app_theme.dart';
import '../../data/models/inventory_unit_model.dart';
import '../../data/models/lease_model.dart';
import '../../data/repositories/inventory_unit_repository.dart';
import '../../services/notification_service.dart';
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
  Map<String, String> _unitStatusMap = {};

  @override
  void initState() {
    super.initState();
    context.read<LeaseCubit>().loadLeases();
    _loadUnitStatuses();
  }

  Future<void> _loadUnitStatuses() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    try {
      final res = await client
          .from('inventory_units')
          .select('id, status')
          .eq('store_id', user.id);

      final Map<String, String> map = {};
      for (final row in (res as List)) {
        final uId = row['id'] as String?;
        final st = row['status'] as String? ?? 'available';
        if (uId != null) map[uId] = st.toLowerCase();
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

  void _makePhoneCall(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final Uri uri = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
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
        await _loadUnitStatuses();
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

                                  final lCubit = context.read<LeaseCubit>();
                                  final iCubit = context.read<InventoryCubit>();
                                  if (!mounted) return;
                                  await _loadUnitStatuses();
                                  await lCubit.loadLeases();
                                  await iCubit.loadInventory();

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

                      final lCubit = context.read<LeaseCubit>();
                      final iCubit = context.read<InventoryCubit>();
                      if (!mounted) return;
                      await _loadUnitStatuses();
                      await lCubit.loadLeases();
                      await iCubit.loadInventory();

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

  String _getReadableStatusLabel(String rawStatus) {
    final st = rawStatus.toLowerCase();
    if (st == 'maintenance' || st == 'damaged') return 'Damaged';
    if (st == 'in_maintenance') return 'In Maintenance';
    if (st == 'lost') return 'Lost';
    if (st == 'needed_restock') return 'Needed Restock';
    return 'Unavailable';
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

                        final lCubit = context.read<LeaseCubit>();
                        if (!mounted) return;
                        await lCubit.loadLeases();

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

          for (final lease in displayList) {
            NotificationService().schedulePickupNotification(
              leaseId: lease.id,
              title: '⏰ Equipment Pick-up Reminder',
              body: 'Pick-up for ${lease.customer?.name ?? "Client"} (${lease.itemNamesSummary}) is scheduled for ${DateFormat("hh:mm a").format(lease.startTime)}!',
              pickupTime: lease.startTime,
            );
          }

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

                          bool hasUnitConflict = false;
                          String? conflictUnitCode;
                          String? conflictStatusLabel;
                          String? conflictUnitId;

                          for (final line in lease.leaseItems) {
                            for (final sub in line.leasedSubItems) {
                              final uId = sub.leaseItemUnitId;
                              final liveSt = uId != null ? (_unitStatusMap[uId] ?? sub.conditionStatus.toLowerCase()) : sub.conditionStatus.toLowerCase();

                              if (liveSt == 'maintenance' ||
                                  liveSt == 'damaged' ||
                                  liveSt == 'in_maintenance' ||
                                  liveSt == 'lost' ||
                                  liveSt == 'needed_restock') {
                                hasUnitConflict = true;
                                conflictUnitCode = sub.serialNumber ?? 'Assigned Set';
                                conflictStatusLabel = _getReadableStatusLabel(liveSt);
                                conflictUnitId = uId;
                                break;
                              }
                            }
                            if (hasUnitConflict) break;
                          }

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkCard : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: hasUnitConflict
                                    ? AppColors.errorRed
                                    : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
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

                                if (hasUnitConflict) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF3B1515) : const Color(0xFFFFDAD6),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.errorRed),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            '⚠️ Unit Conflict: $conflictUnitCode is $conflictStatusLabel.',
                                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.errorRed),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 12),

                                if (hasUnitConflict) ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () => _openSwapUnitModal(context, lease, conflictUnitId),
                                          icon: const Icon(Icons.swap_horiz, size: 13),
                                          label: const Text('Swap Unit', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.primary,
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => _openChangeUnitStatusModal(context, lease, conflictUnitId),
                                          icon: const Icon(Icons.build_outlined, size: 13),
                                          label: const Text('Status', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () async {
                                            final lCubit = context.read<LeaseCubit>();
                                            final res = await Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => CancelReservationScreen(lease: lease),
                                              ),
                                            );
                                            if (res == true && mounted) {
                                              lCubit.loadLeases();
                                            }
                                          },
                                          icon: const Icon(Icons.cancel_outlined, size: 13, color: AppColors.errorRed),
                                          label: const Text('Cancel', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.errorRed)),
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(color: AppColors.errorRed),
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ] else ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => _openRescheduleModal(context, lease),
                                          icon: const Icon(Icons.edit_calendar, size: 13),
                                          label: const Text('Reschedule', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () async {
                                            final lCubit = context.read<LeaseCubit>();
                                            final res = await Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => CancelReservationScreen(lease: lease),
                                              ),
                                            );
                                            if (res == true && mounted) {
                                              lCubit.loadLeases();
                                            }
                                          },
                                          icon: const Icon(Icons.cancel_outlined, size: 13, color: AppColors.errorRed),
                                          label: const Text('Cancel', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppColors.errorRed)),
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(color: AppColors.errorRed),
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () => _openConfirmPickupModal(context, lease),
                                          icon: const Icon(Icons.check_circle_outline, size: 13),
                                          label: const Text('Confirm Pickup', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.primary,
                                            padding: const EdgeInsets.symmetric(vertical: 8),
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
