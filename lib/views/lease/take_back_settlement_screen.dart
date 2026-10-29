import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/config/app_theme.dart';
import '../../core/services/pdf_receipt_service.dart';
import '../../core/utils/rate_calculator.dart';
import '../../data/models/discount_model.dart';
import '../../data/models/inventory_item_model.dart';
import '../../data/models/lease_item_model.dart';
import '../../data/models/lease_model.dart';
import '../../data/models/leased_sub_item_model.dart';
import '../../data/models/store_model.dart';
import '../../data/models/sub_item_model.dart';
import '../../data/repositories/sub_item_repository.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../../viewmodels/discount/discount_cubit.dart';
import '../../viewmodels/discount/discount_state.dart';
import '../../viewmodels/inventory/inventory_cubit.dart';
import '../../viewmodels/inventory/inventory_state.dart';
import '../../viewmodels/lease/lease_cubit.dart';

class ItemSmartBreakdown {
  final String name;
  final int quantity;
  final RentalBreakdown breakdown;
  final double lineTotalRent;

  ItemSmartBreakdown({
    required this.name,
    required this.quantity,
    required this.breakdown,
    required this.lineTotalRent,
  });
}

class TakeBackSettlementScreen extends StatefulWidget {
  final LeaseModel lease;

  const TakeBackSettlementScreen({super.key, required this.lease});

  @override
  State<TakeBackSettlementScreen> createState() => _TakeBackSettlementScreenState();
}

class _TakeBackSettlementScreenState extends State<TakeBackSettlementScreen> {
  late DateTime _actualReturnTime;

  final String _billingMode = 'auto'; // 'auto', 'hourly', 'daily', 'weekly', 'monthly'
  String _returnStatus = 'available'; // 'available', 'awaiting_inspection', 'maintenance', 'lost'

  // Item & Sub-items status tracking
  final Map<String, String> _itemStatusMap = {};
  List<SubItemModel> _subItems = [];
  final Map<String, String> _subItemStatusMap = {};

  final TextEditingController _discountController = TextEditingController(text: '0');
  final TextEditingController _damageFeeController = TextEditingController(text: '0');
  final TextEditingController _notesController = TextEditingController();

  DiscountModel? _appliedDiscount;

  RentalBreakdown? _breakdown;
  final List<ItemSmartBreakdown> _itemBreakdowns = [];
  double _calculatedRent = 0.0;
  double _netRent = 0.0;
  double _finalBalance = 0.0;
  bool _isSettling = false;

  @override
  void initState() {
    super.initState();
    _actualReturnTime = DateTime.now();

    // Initialize item status map for items in lease
    if (widget.lease.leaseItems.isNotEmpty) {
      for (final line in widget.lease.leaseItems) {
        _itemStatusMap[line.id] = 'available';
        for (final sub in line.leasedSubItems) {
          _subItemStatusMap[sub.id] = 'available';
        }
      }
    } else {
      _itemStatusMap[widget.lease.itemId] = 'available';
    }

    // Load sub-items for primary item if any
    SubItemRepository().getSubItems(parentItemId: widget.lease.itemId).then((list) {
      if (mounted && list.isNotEmpty) {
        setState(() {
          _subItems = list;
          for (final s in list) {
            if (!_subItemStatusMap.containsKey(s.id)) {
              _subItemStatusMap[s.id] = 'available';
            }
          }
        });
      }
    });

    _recalculate();
  }

  @override
  void dispose() {
    _discountController.dispose();
    _damageFeeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _getLeaseItemDisplayName() {
    return widget.lease.itemNamesSummary;
  }

  void _recalculate() {
    double totalCalculated = 0.0;
    _itemBreakdowns.clear();

    if (widget.lease.leaseItems.isNotEmpty) {
      for (final li in widget.lease.leaseItems) {
        final b = RateCalculator.getReturnRentBreakdown(
          startTime: widget.lease.startTime,
          actualReturnTime: _actualReturnTime,
          rateHourly: li.rateHourly > 0 ? li.rateHourly : (li.item?.rateHourly ?? 0.0),
          rateDaily: li.rateDaily > 0 ? li.rateDaily : (li.item?.rateDaily ?? 0.0),
          rateWeekly: li.rateWeekly > 0 ? li.rateWeekly : (li.item?.rateWeekly ?? 0.0),
          rateMonthly: li.rateMonthly > 0 ? li.rateMonthly : (li.item?.rateMonthly ?? 0.0),
        );
        final lineRent = b.totalRent * li.quantity;
        totalCalculated += lineRent;

        _itemBreakdowns.add(ItemSmartBreakdown(
          name: li.item?.name ?? 'Equipment Item',
          quantity: li.quantity,
          breakdown: b,
          lineTotalRent: lineRent,
        ));
      }
    } else {
      InventoryItemModel? item = widget.lease.item;
      if (item == null) {
        try {
          final invState = context.read<InventoryCubit>().state;
          if (invState is InventoryLoaded) {
            item = invState.allItems.firstWhere((i) => i.id == widget.lease.itemId);
          }
        } catch (_) {}
      }

      if (item != null) {
        final b = RateCalculator.getReturnRentBreakdown(
          startTime: widget.lease.startTime,
          actualReturnTime: _actualReturnTime,
          rateHourly: item.rateHourly,
          rateDaily: item.rateDaily,
          rateWeekly: item.rateWeekly,
          rateMonthly: item.rateMonthly,
        );
        totalCalculated = b.totalRent * widget.lease.quantity;

        _itemBreakdowns.add(ItemSmartBreakdown(
          name: item.name,
          quantity: widget.lease.quantity,
          breakdown: b,
          lineTotalRent: totalCalculated,
        ));
      } else {
        totalCalculated = widget.lease.calculatedRent;
      }
    }

    _calculatedRent = totalCalculated;

    final discountVal = double.tryParse(_discountController.text) ?? 0.0;
    final damageFeeVal = double.tryParse(_damageFeeController.text) ?? 0.0;

    _netRent = (_calculatedRent - discountVal + damageFeeVal);
    if (_netRent < 0) _netRent = 0.0;

    final totalUpfrontCredit = widget.lease.depositPaid + widget.lease.advanceRentPaid;
    _finalBalance = _netRent - totalUpfrontCredit;
  }

  Future<void> _selectReturnDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _actualReturnTime,
      firstDate: widget.lease.startTime,
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (pickedDate == null) return;

    if (!mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_actualReturnTime),
    );

    final selectedTime = pickedTime ?? TimeOfDay.fromDateTime(_actualReturnTime);

    setState(() {
      _actualReturnTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        selectedTime.hour,
        selectedTime.minute,
      );
    });
    _recalculate();
  }

  void _handleSettlement() async {
    setState(() => _isSettling = true);

    try {
      final storeState = context.read<StoreCubit>().state;
      final store = storeState is StoreLoaded ? storeState.store : null;
      if (store == null) throw Exception('Store not found');

      // Construct updated line items and sub-items with exact selected return/condition statuses
      List<LeaseItemModel> updatedLeaseItems = [];

      if (widget.lease.leaseItems.isNotEmpty) {
        updatedLeaseItems = widget.lease.leaseItems.map((line) {
          final st = _itemStatusMap[line.id] ?? 'available';
          final updatedSubItems = line.leasedSubItems.map((sub) {
            final subSt = _subItemStatusMap[sub.id] ?? 'available';
            return sub.copyWith(conditionStatus: subSt);
          }).toList();

          return line.copyWith(
            returnStatus: st,
            leasedSubItems: updatedSubItems,
          );
        }).toList();
      } else {
        final st = _itemStatusMap[widget.lease.itemId] ?? _returnStatus;
        final updatedSubItems = _subItems.map((s) {
          final subSt = _subItemStatusMap[s.id] ?? 'available';
          return LeasedSubItemModel(
            id: s.id,
            leaseId: widget.lease.id,
            leaseItemId: widget.lease.id,
            subItemId: s.id,
            itemId: widget.lease.itemId,
            storeId: widget.lease.storeId,
            itemName: s.name,
            serialNumber: s.serialNumber,
            conditionStatus: subSt,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
        }).toList();

        updatedLeaseItems.add(LeaseItemModel(
          id: widget.lease.id,
          leaseId: widget.lease.id,
          storeId: widget.lease.storeId,
          itemId: widget.lease.itemId,
          quantity: widget.lease.quantity,
          rateHourly: widget.lease.item?.rateHourly ?? 0,
          rateDaily: widget.lease.item?.rateDaily ?? 0,
          rateWeekly: widget.lease.item?.rateWeekly ?? 0,
          rateMonthly: widget.lease.item?.rateMonthly ?? 0,
          depositAmount: widget.lease.depositExpected,
          lineCalculatedRent: widget.lease.calculatedRent,
          returnStatus: st,
          createdAt: widget.lease.createdAt,
          updatedAt: DateTime.now(),
          item: widget.lease.item,
          leasedSubItems: updatedSubItems,
        ));
      }

      final updatedLease = widget.lease.copyWith(
        actualReturnTime: _actualReturnTime,
        billingUnitUsed: _billingMode,
        calculatedRent: _calculatedRent,
        discountAmount: double.tryParse(_discountController.text) ?? 0.0,
        damageOrLateFee: double.tryParse(_damageFeeController.text) ?? 0.0,
        netRentTotal: _netRent,
        finalSettlementBalance: _finalBalance,
        returnNotes: _notesController.text.trim(),
        status: 'returned',
        leaseItems: updatedLeaseItems,
      );

      final settled = await context.read<LeaseCubit>().returnAndSettle(updatedLease);

      // Update sub-items and parent item's stock status counts in database
      final subItemRepo = SubItemRepository();
      int subMaintCount = 0;
      int subLostCount = 0;
      int subAwaitingCount = 0;

      if (_subItems.isNotEmpty) {
        for (final sub in _subItems) {
          final status = _subItemStatusMap[sub.id] ?? 'available';
          await subItemRepo.updateSubItemStatus(subItemId: sub.id, newStatus: status);
          if (status == 'maintenance') subMaintCount++;
          if (status == 'lost') subLostCount++;
          if (status == 'awaiting_inspection') subAwaitingCount++;
        }
      }

      if (!mounted) return;
      final inventoryCubit = context.read<InventoryCubit>();
      final item = widget.lease.item;
      if (item != null) {
        if (_subItems.isNotEmpty) {
          final updatedItem = item.copyWith(
            maintenanceCount: item.maintenanceCount + subMaintCount,
            lostCount: item.lostCount + subLostCount,
            awaitingInspectionCount: item.awaitingInspectionCount + subAwaitingCount,
            updatedAt: DateTime.now(),
          );
          await inventoryCubit.saveItem(updatedItem, isPro: true);
        } else {
          if (_returnStatus == 'maintenance') {
            final updatedItem = item.copyWith(
              maintenanceCount: item.maintenanceCount + widget.lease.quantity,
              updatedAt: DateTime.now(),
            );
            await inventoryCubit.saveItem(updatedItem, isPro: true);
          } else if (_returnStatus == 'lost') {
            final updatedItem = item.copyWith(
              lostCount: item.lostCount + widget.lease.quantity,
              updatedAt: DateTime.now(),
            );
            await inventoryCubit.saveItem(updatedItem, isPro: true);
          } else if (_returnStatus == 'awaiting_inspection') {
            final updatedItem = item.copyWith(
              awaitingInspectionCount: item.awaitingInspectionCount + widget.lease.quantity,
              updatedAt: DateTime.now(),
            );
            await inventoryCubit.saveItem(updatedItem, isPro: true);
          }
        }
      }

      // Reload inventory so available quantities immediately update across all screens
      if (mounted) {
        context.read<InventoryCubit>().loadInventory();
      }

      // Generate Final Return & Settlement Receipt PDF
      final pdfFile = await PdfReceiptService.instance.generateReturnSettlementReceipt(
        store: store,
        lease: settled,
      );

      if (!mounted) return;
      _showSettlementSuccessSheet(store, settled, pdfFile);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error settling return: $e',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppColors.errorRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSettling = false);
    }
  }

  void _showPaymentQrModal(StoreModel store) {
    final upiId = store.upiId;
    final businessName = Uri.encodeComponent(store.businessName);
    final amount = _finalBalance.abs().toStringAsFixed(2);
    final upiUri = 'upi://pay?pa=$upiId&pn=$businessName&am=$amount&cu=INR';

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
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Collect ${store.currencySymbol}$amount',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppColors.lightOnSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Scan with Google Pay, PhonePe, Paytm or any UPI App',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : AppColors.secondary,
                ),
              ),
              const SizedBox(height: 16),
              if (upiId != null && upiId.isNotEmpty)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
                    ),
                    child: QrImageView(
                      data: upiUri,
                      version: QrVersions.auto,
                      size: 200,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Add your UPI ID in Profile tab to enable dynamic amount QR codes.'),
                ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Payment Received'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSettlementSuccessSheet(StoreModel store, LeaseModel lease, File pdfFile) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Colors.white, size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                'Settlement Completed & Item Returned!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppColors.lightOnSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Settlement PDF ready for ${lease.customer?.name ?? "Customer"}.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white70 : AppColors.secondary,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () async {
                  final msg =
                      'Hello ${lease.customer?.name ?? "Customer"}, here is your official return settlement statement from ${store.businessName} for ${lease.itemNamesSummary}. Final balance: ${store.currencySymbol}${lease.finalSettlementBalance.abs().toStringAsFixed(2)}. Thank you for renting with us!';

                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) Navigator.pop(context);

                  await PdfReceiptService.instance.shareReceipt(pdfFile, msg);
                },
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Share Settlement Statement via WhatsApp'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  await PdfReceiptService.instance.printReceipt(pdfFile);
                },
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Print / Preview Statement'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                child: const Text('Done & Return to Dashboard'),
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
    final store = storeState is StoreLoaded ? storeState.store : null;
    final currency = store?.currencySymbol ?? '₹';

    final duration = _actualReturnTime.difference(widget.lease.startTime);
    final totalMinutes = duration.inMinutes < 1 ? 1 : duration.inMinutes;

    final days = totalMinutes ~/ (24 * 60);
    final minutesAfterDays = totalMinutes % (24 * 60);
    final hours = minutesAfterDays ~/ 60;
    final minutes = minutesAfterDays % 60;

    String fallbackDurationText = '';
    if (days > 0) fallbackDurationText += '$days Day${days > 1 ? 's' : ''}, ';
    if (hours > 0) fallbackDurationText += '$hours Hr${hours > 1 ? 's' : ''}, ';
    fallbackDurationText += '$minutes Min${minutes > 1 ? 's' : ''}';

    final durationDisplay = _breakdown?.durationText ?? fallbackDurationText;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('Return & Final Settlement'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Actual Duration & Timeline Card
            Container(
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
                      Row(
                        children: [
                          Icon(Icons.timer_outlined, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
                          const SizedBox(width: 6),
                          const Text('Rental Duration & Timeline', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          durationDisplay,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Handover Date', style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                            Text(DateFormat('dd MMM, hh:mm a').format(widget.lease.startTime), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        InkWell(
                          onTap: _selectReturnDateTime,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.edit, size: 10, color: isDark ? AppColors.primaryLight : AppColors.primary),
                                    const SizedBox(width: 3),
                                    Text('Actual Return', style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                                  ],
                                ),
                                Text(DateFormat('dd MMM, hh:mm a').format(_actualReturnTime), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Recorded Duration: $durationDisplay',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? AppColors.primaryLight : AppColors.primary),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 2. Master Quick Action Control
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Inspection Actions',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              for (final k in _itemStatusMap.keys) {
                                _itemStatusMap[k] = 'available';
                              }
                              for (final k in _subItemStatusMap.keys) {
                                _subItemStatusMap[k] = 'available';
                              }
                              _returnStatus = 'available';
                            });
                          },
                          icon: const Icon(Icons.check_circle_outline, size: 14),
                          label: const Text(
                            'Mark All Ready',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              for (final k in _itemStatusMap.keys) {
                                _itemStatusMap[k] = 'maintenance';
                              }
                              for (final k in _subItemStatusMap.keys) {
                                _subItemStatusMap[k] = 'maintenance';
                              }
                              _returnStatus = 'maintenance';
                            });
                          },
                          icon: const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.errorRed),
                          label: const Text(
                            'Mark All Damaged',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.errorRed),
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                            side: const BorderSide(color: AppColors.errorRed),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 3. Individual Item Settlement Cards
            Text(
              'Equipment Condition Inspection',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
            ),
            const SizedBox(height: 8),

            ..._buildIndividualItemCards(context, isDark),

            const SizedBox(height: 6),

            // 4. Inspection Proof Photos taken when leasing
            if (widget.lease.beforePhotoUrls.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
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
                        Row(
                          children: [
                            Icon(Icons.photo_library_outlined, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
                            const SizedBox(width: 6),
                            const Text('Photos Taken When Leasing', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Text('${widget.lease.beforePhotoUrls.length} Photos',
                            style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 76,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.lease.beforePhotoUrls.length,
                        separatorBuilder: (context, index) => const SizedBox(width: 8),
                        itemBuilder: (context, index) => _buildConditionPhotoThumbnail(
                          context,
                          widget.lease.beforePhotoUrls[index],
                          index,
                          isDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 14),

            // Prior Upfront Payments & Credits Card
            Container(
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
                    children: [
                      Icon(Icons.account_balance_wallet_outlined, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
                      const SizedBox(width: 6),
                      const Text('Prior Upfront Payments & Credits', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Security deposit paid upfront', style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                      Text('$currency${widget.lease.depositPaid.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Advance rent paid upfront', style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                      Text('$currency${widget.lease.advanceRentPaid.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Divider(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Upfront Credit Available', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? AppColors.primaryLight : AppColors.primary)),
                      Text(
                        '$currency${(widget.lease.depositPaid + widget.lease.advanceRentPaid).toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? AppColors.primaryLight : AppColors.primary),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Smart Ledger Calculation Breakdown
            Container(
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
                    children: [
                      Icon(Icons.calculate_outlined, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
                      const SizedBox(width: 6),
                      const Text('Smart Ledger Breakdown', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Display Itemized Component Breakdown List for ALL items in order
                  if (_itemBreakdowns.isNotEmpty) ...[
                    ..._itemBreakdowns.map((itemBk) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurfaceLow : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isDark ? AppColors.darkBorder : const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${itemBk.quantity}x ${itemBk.name}',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface),
                                ),
                                Text(
                                  '$currency${itemBk.lineTotalRent.toStringAsFixed(2)}',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? AppColors.primaryLight : AppColors.primary),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ...itemBk.breakdown.components.map((comp) {
                              final compSubtotal = comp.amount * itemBk.quantity;
                              return Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '• ${comp.label}: ${comp.calculation}',
                                        style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                      ),
                                    ),
                                    Text(
                                      itemBk.quantity > 1
                                          ? '$currency${comp.amount.toStringAsFixed(2)} / pc ($currency${compSubtotal.toStringAsFixed(2)})'
                                          : '$currency${comp.amount.toStringAsFixed(2)}',
                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            if (itemBk.quantity > 1) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Formula: ${itemBk.quantity} pcs × $currency${itemBk.breakdown.totalRent.toStringAsFixed(2)} / pc = $currency${itemBk.lineTotalRent.toStringAsFixed(2)}',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isDark ? AppColors.primaryLight : AppColors.primary),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 4),
                    Divider(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    const SizedBox(height: 6),
                  ],

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Gross Rent Subtotal', style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                      Text('$currency${_calculatedRent.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Coupon / Discount row
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _discountController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Discount / Coupon ($currency)',
                            prefixText: '$currency ',
                          ),
                          onChanged: (_) => setState(_recalculate),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: const Icon(Icons.local_offer_outlined, color: AppColors.primary),
                        tooltip: 'Apply Coupon',
                        onPressed: () => _openDiscountPickerModal(context),
                      ),
                    ],
                  ),
                  if (_appliedDiscount != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Applied Coupon: ${_appliedDiscount!.code} (${_appliedDiscount!.discountText})',
                        style: const TextStyle(fontSize: 11, color: AppColors.primaryLight, fontWeight: FontWeight.bold),
                      ),
                    ),

                  const SizedBox(height: 10),

                  TextFormField(
                    controller: _damageFeeController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Damage / Inspection / Overdue Fee ($currency)',
                      prefixText: '$currency ',
                      helperText: 'Added to final rental charges upon inspection',
                    ),
                    onChanged: (_) => setState(_recalculate),
                  ),

                  const SizedBox(height: 12),
                  Divider(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  const SizedBox(height: 8),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Final Net Rental Charge', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface)),
                      Text('$currency${_netRent.toStringAsFixed(2)}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isDark ? AppColors.primaryLight : AppColors.primary)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Final Settlement Reconciliation Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _finalBalance > 0
                    ? (isDark ? const Color(0xFF3B2E15) : const Color(0xFFFFFBEB))
                    : (_finalBalance < 0
                        ? (isDark ? const Color(0xFF142E24) : const Color(0xFFECFDF5))
                        : (isDark ? AppColors.darkCard : Colors.white)),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _finalBalance > 0
                      ? AppColors.tertiaryAmber
                      : (_finalBalance < 0 ? AppColors.primaryLight : (isDark ? AppColors.darkBorder : AppColors.lightBorder)),
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _finalBalance > 0
                            ? 'Client Owes Store (Additional Collect)'
                            : (_finalBalance < 0 ? 'Store Refund to Client' : 'Fully Settled (Net Zero Balance)'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _finalBalance > 0
                              ? Colors.amber.shade900
                              : (_finalBalance < 0 ? AppColors.primaryLight : (isDark ? Colors.white : AppColors.slateNavy)),
                        ),
                      ),
                      if (store != null && _finalBalance > 0)
                        IconButton(
                          icon: const Icon(Icons.qr_code, color: AppColors.primary),
                          tooltip: 'Show UPI QR Code',
                          onPressed: () => _showPaymentQrModal(store),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$currency${_finalBalance.abs().toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _finalBalance > 0
                          ? AppColors.errorRed
                          : (_finalBalance < 0 ? AppColors.primaryLight : (isDark ? Colors.white : AppColors.slateNavy)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _finalBalance > 0
                        ? 'Collect $currency${_finalBalance.toStringAsFixed(2)} via Cash / UPI QR Code.'
                        : (_finalBalance < 0
                            ? 'Refund $currency${_finalBalance.abs().toStringAsFixed(2)} security deposit balance to client.'
                            : 'Security deposit matches rental charges exactly.'),
                    style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Return Inspection Notes
            TextFormField(
              controller: _notesController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Return Notes (Optional)',
                hintText: 'Accessories verified, minor scratches recorded...',
              ),
            ),

            const SizedBox(height: 24),

            // Primary Settlement Button
            ElevatedButton.icon(
              onPressed: _isSettling ? null : _handleSettlement,
              icon: const Icon(Icons.check_circle_outline, size: 20),
              label: Text(_isSettling ? 'Finalizing Settlement...' : 'Confirm Return & Finalize Settlement'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildIndividualItemCards(BuildContext context, bool isDark) {
    final List<Widget> cards = [];

    final hasLineItems = widget.lease.leaseItems.isNotEmpty;
    final itemsCount = hasLineItems ? widget.lease.leaseItems.length : 1;

    for (int i = 0; i < itemsCount; i++) {
      final lineItem = hasLineItems ? widget.lease.leaseItems[i] : null;
      final key = lineItem?.id ?? widget.lease.itemId;
      final itemName = lineItem?.item?.name ?? (hasLineItems ? 'Equipment Item #${i + 1}' : _getLeaseItemDisplayName());
      final qty = lineItem?.quantity ?? widget.lease.quantity;
      final sku = lineItem?.item?.displaySku ?? widget.lease.item?.displaySku ?? '-';

      final currentStatus = _itemStatusMap[key] ?? 'available';

      // Get sub-items for this line item
      final List<dynamic> subItemsList = lineItem != null && lineItem.leasedSubItems.isNotEmpty
          ? lineItem.leasedSubItems
          : (i == 0 ? _subItems : []);

      bool isCardDamagedOrLost = currentStatus == 'maintenance' ||
          currentStatus == 'lost' ||
          currentStatus == 'awaiting_inspection';

      for (final sub in subItemsList) {
        final subId = sub is LeasedSubItemModel ? sub.id : (sub as SubItemModel).id;
        final subSt = _subItemStatusMap[subId] ?? 'available';
        if (subSt == 'maintenance' || subSt == 'lost' || subSt == 'awaiting_inspection') {
          isCardDamagedOrLost = true;
          break;
        }
      }

      final Color cardBgColor = isCardDamagedOrLost
          ? (isDark ? const Color(0xFF3B1515) : const Color(0xFFFEF2F2))
          : (isDark ? const Color(0xFF142E24) : const Color(0xFFECFDF5));

      final Color cardBorderColor = isCardDamagedOrLost
          ? (isDark ? const Color(0xFF6B1D22) : const Color(0xFFFECACA))
          : (isDark ? AppColors.primary : const Color(0xFFA7F3D0));

      final String statusLabel = isCardDamagedOrLost ? 'DAMAGED / REPAIR' : 'AVAILABLE (READY)';
      final Color badgeBg = isCardDamagedOrLost
          ? (isDark ? const Color(0xFF6B1D22) : const Color(0xFFFFDAD6))
          : (isDark ? AppColors.darkSurfaceLow : const Color(0xFFD1FAE5));
      final Color badgeTextColor = isCardDamagedOrLost ? AppColors.errorRed : AppColors.primary;

      cards.add(
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cardBorderColor, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$qty x $itemName',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Asset SKU: $sku • $qty ${qty > 1 ? "pieces" : "piece"}',
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
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: badgeTextColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Text(
                'Select Item Condition:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                ),
              ),
              const SizedBox(height: 6),

              // 4 Choice Options for Item Condition
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildConditionChoiceChip(
                    label: 'Available (OK)',
                    value: 'available',
                    selectedGroupValue: currentStatus,
                    onSelected: () {
                      setState(() {
                        _itemStatusMap[key] = 'available';
                      });
                    },
                    isDark: isDark,
                    activeColor: AppColors.primary,
                  ),
                  _buildConditionChoiceChip(
                    label: 'Damaged',
                    value: 'maintenance',
                    selectedGroupValue: currentStatus,
                    onSelected: () {
                      setState(() {
                        _itemStatusMap[key] = 'maintenance';
                      });
                    },
                    isDark: isDark,
                    activeColor: AppColors.errorRed,
                  ),
                  _buildConditionChoiceChip(
                    label: 'Lost',
                    value: 'lost',
                    selectedGroupValue: currentStatus,
                    onSelected: () {
                      setState(() {
                        _itemStatusMap[key] = 'lost';
                      });
                    },
                    isDark: isDark,
                    activeColor: AppColors.errorRed,
                  ),
                  _buildConditionChoiceChip(
                    label: 'Maintenance',
                    value: 'awaiting_inspection',
                    selectedGroupValue: currentStatus,
                    onSelected: () {
                      setState(() {
                        _itemStatusMap[key] = 'awaiting_inspection';
                      });
                    },
                    isDark: isDark,
                    activeColor: AppColors.tertiaryAmber,
                  ),
                ],
              ),

              // Sub-Items Section inside Card
              if (subItemsList.isNotEmpty) ...[
                const SizedBox(height: 12),
                Divider(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                const SizedBox(height: 8),
                Text(
                  'Sub-Items & Accessories Inspection (${subItemsList.length}):',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                  ),
                ),
                const SizedBox(height: 8),
                ...subItemsList.map((sub) {
                  final String subId = sub is LeasedSubItemModel ? sub.id : (sub as SubItemModel).id;
                  final String subName = sub is LeasedSubItemModel ? sub.itemName : (sub as SubItemModel).name;
                  final String? subSerial = sub is LeasedSubItemModel ? sub.serialNumber : (sub as SubItemModel).serialNumber;
                  final String currentSubSt = _subItemStatusMap[subId] ?? 'available';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCard : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '• $subName${subSerial != null && subSerial.isNotEmpty ? " (SN: $subSerial)" : ""}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            _buildConditionChoiceChip(
                              label: 'Available',
                              value: 'available',
                              selectedGroupValue: currentSubSt,
                              onSelected: () {
                                setState(() {
                                  _subItemStatusMap[subId] = 'available';
                                });
                              },
                              isDark: isDark,
                              activeColor: AppColors.primary,
                              isCompact: true,
                            ),
                            _buildConditionChoiceChip(
                              label: 'Damaged',
                              value: 'maintenance',
                              selectedGroupValue: currentSubSt,
                              onSelected: () {
                                setState(() {
                                  _subItemStatusMap[subId] = 'maintenance';
                                });
                              },
                              isDark: isDark,
                              activeColor: AppColors.errorRed,
                              isCompact: true,
                            ),
                            _buildConditionChoiceChip(
                              label: 'Lost',
                              value: 'lost',
                              selectedGroupValue: currentSubSt,
                              onSelected: () {
                                setState(() {
                                  _subItemStatusMap[subId] = 'lost';
                                });
                              },
                              isDark: isDark,
                              activeColor: AppColors.errorRed,
                              isCompact: true,
                            ),
                            _buildConditionChoiceChip(
                              label: 'Maintenance',
                              value: 'awaiting_inspection',
                              selectedGroupValue: currentSubSt,
                              onSelected: () {
                                setState(() {
                                  _subItemStatusMap[subId] = 'awaiting_inspection';
                                });
                              },
                              isDark: isDark,
                              activeColor: AppColors.tertiaryAmber,
                              isCompact: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      );
    }

    return cards;
  }

  Widget _buildConditionChoiceChip({
    required String label,
    required String value,
    required String selectedGroupValue,
    required VoidCallback onSelected,
    required bool isDark,
    required Color activeColor,
    bool isCompact = false,
  }) {
    final bool isSelected = selectedGroupValue == value;

    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 8 : 10,
          vertical: isCompact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor
              : (isDark ? AppColors.darkCard : Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? activeColor
                : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: isCompact ? 12 : 14,
              color: isSelected ? Colors.white : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
            ),
            SizedBox(width: isCompact ? 4 : 6),
            Text(
              label,
              style: TextStyle(
                fontSize: isCompact ? 10 : 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? Colors.white : (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionPhotoThumbnail(BuildContext context, String photoUrl, int index, bool isDark) {
    return GestureDetector(
      onTap: () => _showEnlargedPhotoDialog(context, photoUrl, index),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(photoUrl, fit: BoxFit.cover),
        ),
      ),
    );
  }

  void _showEnlargedPhotoDialog(BuildContext context, String photoUrl, int index) {
    showDialog(
      context: context,
      builder: (dCtx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.black,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: InteractiveViewer(
                    child: Image.network(photoUrl, fit: BoxFit.contain),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(dCtx),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Close Photo Preview'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openDiscountPickerModal(BuildContext context) {
    final discountState = context.read<DiscountCubit>().state;
    final discounts = discountState is DiscountLoaded ? discountState.discounts : <DiscountModel>[];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalCtx) {
        final isDark = Theme.of(modalCtx).brightness == Brightness.dark;

        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Available Discount Coupons',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppColors.lightOnSurface),
              ),
              const SizedBox(height: 12),
              if (discounts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text('No discount coupons active.')),
                )
              else
                SizedBox(
                  height: 200,
                  child: ListView.separated(
                    itemCount: discounts.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final disc = discounts[index];
                      return Material(
                        color: Colors.transparent,
                        child: ListTile(
                          leading: const Icon(Icons.local_offer, color: AppColors.primary),
                          title: Text(disc.code, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(disc.title),
                          trailing: Text(disc.discountText, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryLight)),
                          onTap: () {
                            final discAmt = disc.calculateDiscountAmount(_calculatedRent);
                            setState(() {
                              _appliedDiscount = disc;
                              _discountController.text = discAmt.toStringAsFixed(0);
                              _recalculate();
                            });
                            Navigator.pop(modalCtx);
                          },
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
