import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/app_theme.dart';
import '../../core/services/pdf_receipt_service.dart';
import '../../data/models/inventory_item_history_model.dart';
import '../../data/models/inventory_item_model.dart';
import '../../data/models/lease_model.dart';
import '../../data/repositories/inventory_item_history_repository.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../../viewmodels/lease/lease_cubit.dart';
import '../../viewmodels/lease/lease_state.dart';

class EquipmentHistoryTimelineItem {
  final String title;
  final String description;
  final DateTime timestamp;
  final String eventType; // 'created', 'updated', 'leased', 'returned', 'damaged', 'lost', 'repaired'
  final String? customerName;
  final String? customerPhone;
  final DateTime? expectedReturnTime;
  final double? cost;
  final int? pieces;
  final LeaseModel? lease;

  EquipmentHistoryTimelineItem({
    required this.title,
    required this.description,
    required this.timestamp,
    required this.eventType,
    this.customerName,
    this.customerPhone,
    this.expectedReturnTime,
    this.cost,
    this.pieces,
    this.lease,
  });
}

class EquipmentHistoryTimelineScreen extends StatefulWidget {
  final InventoryItemModel item;
  final String currency;

  const EquipmentHistoryTimelineScreen({
    super.key,
    required this.item,
    required this.currency,
  });

  @override
  State<EquipmentHistoryTimelineScreen> createState() => _EquipmentHistoryTimelineScreenState();
}

class _EquipmentHistoryTimelineScreenState extends State<EquipmentHistoryTimelineScreen> {
  String _selectedFilter = 'All'; // 'All', 'Leases', 'Damaged', 'Lost'
  List<EquipmentHistoryTimelineItem> _timelineEvents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTimelineHistory();
  }

  Future<void> _loadTimelineHistory() async {
    setState(() => _isLoading = true);

    try {
      final List<EquipmentHistoryTimelineItem> events = [];

      // 1. Creation Event
      events.add(EquipmentHistoryTimelineItem(
        title: 'Equipment Item Created',
        description: 'Item created with ${widget.item.totalQuantity} physical set units (SKU: ${widget.item.displaySku}).',
        timestamp: widget.item.createdAt,
        eventType: 'created',
      ));

      // 2. Fetch Audit History Logs from Database
      final historyLogs = await InventoryItemHistoryRepository().getHistoryForItem(widget.item.id);
      for (final log in historyLogs) {
        events.add(EquipmentHistoryTimelineItem(
          title: _getHistoryTitle(log.eventType),
          description: log.notes ?? 'Audit record logged (${log.eventType.toUpperCase()}).',
          timestamp: log.createdAt,
          eventType: log.eventType,
          cost: log.costIncurred,
        ));
      }

      // 3. Fetch Leases from LeaseCubit
      final leaseState = context.read<LeaseCubit>().state;
      if (leaseState is LeaseLoaded) {
        final itemLeases = leaseState.allLeases.where((l) => l.itemId == widget.item.id).toList();

        for (final lease in itemLeases) {
          final customerName = lease.customer?.name ?? 'Customer';
          final customerPhone = lease.customer?.phone;

          events.add(EquipmentHistoryTimelineItem(
            title: 'Lease Dispatched',
            description: 'Leased Customer: $customerName',
            timestamp: lease.startTime,
            eventType: 'leased',
            customerName: customerName,
            customerPhone: customerPhone,
            expectedReturnTime: lease.expectedEndTime,
            pieces: lease.totalPieces,
            lease: lease,
          ));

          if (lease.status == 'returned' && lease.actualReturnTime != null) {
            events.add(EquipmentHistoryTimelineItem(
              title: 'Lease Returned & Settled',
              description: 'Returned by $customerName. Net Rent: ${widget.currency}${lease.netRentTotal.toStringAsFixed(0)}',
              timestamp: lease.actualReturnTime!,
              eventType: 'returned',
              customerName: customerName,
              customerPhone: customerPhone,
              lease: lease,
            ));
          }
        }
      }

      // Sort timeline newest first
      events.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      if (mounted) {
        setState(() {
          _timelineEvents = events;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getHistoryTitle(String type) {
    switch (type.toLowerCase()) {
      case 'damaged':
      case 'maintenance':
        return 'Component Marked Damaged';
      case 'lost':
        return 'Component Marked Lost';
      case 'repaired':
      case 'restocked':
        return 'Item Repaired / Restocked';
      case 'updated':
        return 'Equipment Item Updated';
      default:
        return 'History Event (${type.toUpperCase()})';
    }
  }

  List<EquipmentHistoryTimelineItem> get _filteredEvents {
    if (_selectedFilter == 'All') return _timelineEvents;
    final f = _selectedFilter.toLowerCase();

    return _timelineEvents.where((e) {
      final t = e.eventType.toLowerCase();
      if (f == 'leases') {
        return t == 'leased' || t == 'returned' || t == 'dispatch';
      }
      if (f == 'damaged') {
        return t == 'damaged' || t == 'maintenance' || t == 'repaired';
      }
      if (f == 'lost') {
        return t == 'lost' || t == 'replaced';
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayEvents = _filteredEvents;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: Text('${widget.item.name} History'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      body: Column(
        children: [
          // Filter Chips Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: isDark ? AppColors.darkCard : Colors.white,
            child: Row(
              children: [
                _buildFilterChip('All', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('Leases', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('Damaged', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('Lost', isDark),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : displayEvents.isEmpty
                    ? Center(
                        child: Text(
                          'No history events found for this filter.',
                          style: TextStyle(color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: displayEvents.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final event = displayEvents[index];
                          final iconData = _getEventIcon(event.eventType);
                          final color = _getEventColor(event.eventType);

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkCard : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: color.withValues(alpha: 0.15),
                                  child: Icon(iconData, color: color, size: 18),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              event.title,
                                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          Text(
                                            DateFormat('dd MMM yyyy, hh:mm a').format(event.timestamp),
                                            style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                          ),
                                        ],
                                      ),
                                      if (event.eventType == 'leased') ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Leased Sets: ${event.pieces ?? 1}',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Leased Customer: ${event.customerName ?? "Customer"}',
                                          style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                        ),
                                        if (event.expectedReturnTime != null) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            'Expected Return: ${DateFormat("dd MMM yyyy, hh:mm a").format(event.expectedReturnTime!)}',
                                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.tertiaryAmber),
                                          ),
                                        ],
                                      ] else ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          event.description,
                                          style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                        ),
                                        if (event.expectedReturnTime != null) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            'Expected Return: ${DateFormat("dd MMM yyyy, hh:mm a").format(event.expectedReturnTime!)}',
                                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.tertiaryAmber),
                                          ),
                                        ],
                                      ],
                                      if (event.cost != null && event.cost! > 0) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Fee Incurred: ${widget.currency}${event.cost!.toStringAsFixed(0)}',
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.errorRed),
                                        ),
                                      ],
                                      if (event.lease != null || (event.customerPhone != null && event.customerPhone!.trim().isNotEmpty)) ...[
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            if (event.lease != null) ...[
                                              InkWell(
                                                onTap: () => _openHandoverPdf(event.lease!),
                                                borderRadius: BorderRadius.circular(16),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.primary.withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(16),
                                                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.picture_as_pdf_outlined, size: 12, color: AppColors.primary),
                                                      SizedBox(width: 4),
                                                      Text(
                                                        'Handover PDF',
                                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                            ],
                                            if (event.customerPhone != null && event.customerPhone!.trim().isNotEmpty) ...[
                                              InkWell(
                                                onTap: () => _makePhoneCall(event.customerPhone!),
                                                borderRadius: BorderRadius.circular(16),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.primary.withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(16),
                                                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.phone_outlined, size: 12, color: AppColors.primary),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        'Call ${event.customerName ?? ""}',
                                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  void _openHandoverPdf(LeaseModel lease) async {
    final storeState = context.read<StoreCubit>().state;
    final store = storeState is StoreLoaded ? storeState.store : null;
    if (store == null) return;

    try {
      final file = await PdfReceiptService.instance.generateHandoverReceipt(
        store: store,
        lease: lease,
      );
      final bytes = await file.readAsBytes();
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Handover_Receipt_${lease.shortId}.pdf',
      );
    } catch (e) {
      debugPrint('Error generating handover PDF: $e');
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleanPhone.isEmpty) return;
    final Uri phoneUri = Uri(scheme: 'tel', path: cleanPhone);
    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      }
    } catch (e) {
      debugPrint('Error launching phone dialer: $e');
    }
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

  IconData _getEventIcon(String type) {
    switch (type.toLowerCase()) {
      case 'created':
        return Icons.add_circle_outline;
      case 'updated':
        return Icons.edit_note;
      case 'leased':
        return Icons.outbound_outlined;
      case 'returned':
        return Icons.assignment_turned_in_outlined;
      case 'damaged':
      case 'maintenance':
        return Icons.build_circle_outlined;
      case 'lost':
        return Icons.cancel_outlined;
      case 'repaired':
      case 'restocked':
        return Icons.inventory_outlined;
      default:
        return Icons.history;
    }
  }

  Color _getEventColor(String type) {
    switch (type.toLowerCase()) {
      case 'created':
        return AppColors.primary;
      case 'leased':
        return AppColors.tertiaryAmber;
      case 'returned':
        return AppColors.primaryLight;
      case 'damaged':
      case 'maintenance':
        return Colors.orange;
      case 'lost':
        return AppColors.errorRed;
      case 'repaired':
      case 'restocked':
        return AppColors.primary;
      default:
        return Colors.blue;
    }
  }
}
