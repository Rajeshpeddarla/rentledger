import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../core/config/app_theme.dart';
import '../../data/models/lease_model.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../../viewmodels/lease/lease_cubit.dart';
import '../../viewmodels/lease/lease_state.dart';
import '../../core/services/pdf_receipt_service.dart';
import 'create_lease_screen.dart';
import 'take_back_settlement_screen.dart';

class CalendarHistoryScreen extends StatefulWidget {
  const CalendarHistoryScreen({super.key});

  @override
  State<CalendarHistoryScreen> createState() => _CalendarHistoryScreenState();
}

class _CalendarHistoryScreenState extends State<CalendarHistoryScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.twoWeeks;

  final List<String> _filters = ['all', 'active', 'upcoming', 'overdue', 'returned'];

  Future<void> _handleReceiptAction(BuildContext context, LeaseModel lease) async {
    final storeState = context.read<StoreCubit>().state;
    if (storeState is! StoreLoaded) return;
    final store = storeState.store;
    final isReturned = lease.status == 'returned';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkBorder : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isReturned ? 'Return Settlement Receipt' : 'Lease Agreement / Handover Receipt',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppColors.lightOnSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${lease.itemNamesSummary} • ${lease.customer?.name ?? "Customer"}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : AppColors.secondary,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final file = await PdfReceiptService.instance.generateReceiptForLease(store: store, lease: lease);
                  await PdfReceiptService.instance.printReceipt(file);
                },
                icon: const Icon(Icons.print, size: 18, color: Colors.white),
                label: const Text('Print / Save PDF Receipt', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final file = await PdfReceiptService.instance.generateReceiptForLease(store: store, lease: lease);
                  final msg = isReturned
                      ? 'Return settlement receipt for ${lease.item?.name} from ${store.businessName}'
                      : 'Rental lease receipt for ${lease.item?.name} from ${store.businessName}';
                  await PdfReceiptService.instance.shareReceipt(file, msg);
                },
                icon: Icon(Icons.share, size: 18, color: isDark ? Colors.white : AppColors.primary),
                label: Text(
                  'Share Receipt via WhatsApp / App',
                  style: TextStyle(color: isDark ? Colors.white : AppColors.primary, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final storeState = context.watch<StoreCubit>().state;
    final isPro = storeState is StoreLoaded && storeState.store.isPro;
    final currency = storeState is StoreLoaded ? storeState.store.currencySymbol : '₹';

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('Rental Calendar & History'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle, color: AppColors.primary),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CreateLeaseScreen(isPro: isPro),
                ),
              );
            },
            tooltip: 'New Lease Dispatch',
          ),
        ],
      ),
      body: BlocBuilder<LeaseCubit, LeaseState>(
        builder: (context, state) {
          if (state is! LeaseLoaded) {
            return const Center(child: CircularProgressIndicator());
          }

          final allLeases = state.allLeases;
          final currentFilter = state.statusFilter;

          // Find dates that have active leases to mark on calendar
          List<LeaseModel> getEventsForDay(DateTime day) {
            final dayStart = DateTime(day.year, day.month, day.day, 0, 0, 0);
            final dayEnd = DateTime(day.year, day.month, day.day, 23, 59, 59);

            return allLeases.where((l) {
              final s = l.startTime;
              final e = l.actualReturnTime ?? l.expectedEndTime;
              return s.isBefore(dayEnd) && e.isAfter(dayStart);
            }).toList();
          }

          // Filter leases on the selected date by selected filter chip
          final selectedDayLeases = getEventsForDay(_selectedDay).where((l) {
            if (currentFilter == 'active') return l.status == 'active';
            if (currentFilter == 'upcoming') return l.status == 'upcoming';
            if (currentFilter == 'overdue') return l.isOverdue;
            if (currentFilter == 'returned') return l.status == 'returned';
            return true;
          }).toList();

          return Column(
            children: [
              // 1. Interactive Table Calendar
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TableCalendar<LeaseModel>(
                  firstDay: DateTime.now().subtract(const Duration(days: 365)),
                  lastDay: DateTime.now().add(const Duration(days: 365)),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  calendarFormat: _calendarFormat,
                  eventLoader: getEventsForDay,
                  startingDayOfWeek: StartingDayOfWeek.monday,
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                    context.read<LeaseCubit>().setSelectedDate(selectedDay);
                  },
                  onFormatChanged: (format) {
                    setState(() {
                      _calendarFormat = format;
                    });
                  },
                  onPageChanged: (focusedDay) {
                    _focusedDay = focusedDay;
                  },
                  calendarStyle: CalendarStyle(
                    isTodayHighlighted: true,
                    todayDecoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    todayTextStyle: TextStyle(
                      color: isDark ? AppColors.primaryLight : AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                    selectedDecoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    selectedTextStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    markerDecoration: const BoxDecoration(
                      color: AppColors.tertiaryAmber,
                      shape: BoxShape.circle,
                    ),
                    markersMaxCount: 3,
                  ),
                  headerStyle: HeaderStyle(
                    formatButtonVisible: true,
                    titleCentered: true,
                    formatButtonShowsNext: false,
                    formatButtonDecoration: BoxDecoration(
                      border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    formatButtonTextStyle: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    titleTextStyle: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // 2. Filter Chips Strip
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filters.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final filter = _filters[index];
                    final isSelected = currentFilter == filter;

                    return ChoiceChip(
                      label: Text(
                        filter.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? Colors.white
                              : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: AppColors.primary,
                      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
                      side: BorderSide(
                        color: isSelected
                            ? AppColors.primary
                            : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      onSelected: (_) {
                        context.read<LeaseCubit>().setStatusFilter(filter);
                      },
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              // 3. Selected Date Status Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormat('EEE, dd MMMM yyyy').format(_selectedDay),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      ),
                    ),
                    Text(
                      '${selectedDayLeases.length} record(s)',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // 4. Leases on Selected Date List
              Expanded(
                child: selectedDayLeases.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.event_available,
                                size: 48,
                                color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                            const SizedBox(height: 8),
                            Text(
                              'No leases scheduled on this date.',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: selectedDayLeases.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final lease = selectedDayLeases[index];
                          final isOverdue = lease.isOverdue;
                          final isReturned = lease.status == 'returned';

                          final String itemName = lease.itemNamesSummary;

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkCard : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isOverdue
                                    ? (isDark ? const Color(0xFF6B1D22) : const Color(0xFFFECACA))
                                    : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        itemName,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isOverdue
                                            ? (isDark ? const Color(0xFF3B1515) : const Color(0xFFFFDAD6))
                                            : (isReturned
                                                ? (isDark ? const Color(0xFF142E24) : const Color(0xFFECFDF5))
                                                : (isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow)),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isOverdue ? 'OVERDUE' : lease.status.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: isOverdue
                                              ? AppColors.errorRed
                                              : (isReturned ? AppColors.primaryLight : AppColors.primary),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.person_outline, size: 14, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                    const SizedBox(width: 4),
                                    Text(
                                      lease.customer?.name ?? "Customer",
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                                      ),
                                    ),
                                  ],
                                ),
                                if (lease.customer?.phone != null && lease.customer!.phone.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Icon(Icons.phone_outlined, size: 14, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                      const SizedBox(width: 4),
                                      Text(
                                        lease.customer!.phone,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.schedule, size: 14, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Expected return: ${DateFormat('dd MMM, hh:mm a').format(lease.expectedEndTime)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Deposit: $currency${lease.depositPaid.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: isDark ? AppColors.primaryLight : AppColors.primary,
                                      ),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        OutlinedButton.icon(
                                          onPressed: () => _handleReceiptAction(context, lease),
                                          icon: const Icon(Icons.receipt_long, size: 14),
                                          label: Text(
                                            isReturned ? 'Receipt' : 'Lease PDF',
                                            style: const TextStyle(fontSize: 11),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            minimumSize: const Size(0, 30),
                                            side: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                                          ),
                                        ),
                                        if (lease.status == 'active') ...[
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                            onPressed: () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) => TakeBackSettlementScreen(lease: lease),
                                                ),
                                              );
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppColors.primary,
                                              minimumSize: const Size(80, 30),
                                              padding: const EdgeInsets.symmetric(horizontal: 10),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            ),
                                            child: const Text('Take Back', style: TextStyle(fontSize: 11)),
                                          ),
                                        ],
                                      ],
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
}
