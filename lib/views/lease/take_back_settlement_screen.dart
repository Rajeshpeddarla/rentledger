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
import '../../data/models/lease_model.dart';
import '../../data/models/store_model.dart';
import '../../data/models/sub_item_model.dart';
import '../../data/repositories/sub_item_repository.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../../viewmodels/discount/discount_cubit.dart';
import '../../viewmodels/discount/discount_state.dart';
import '../../viewmodels/inventory/inventory_cubit.dart';
import '../../viewmodels/lease/lease_cubit.dart';

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

  // Sub-items tracking for this lease item
  List<SubItemModel> _subItems = [];
  final Map<String, String> _subItemStatusMap = {};

  final TextEditingController _discountController = TextEditingController(text: '0');
  final TextEditingController _damageFeeController = TextEditingController(text: '0');
  final TextEditingController _notesController = TextEditingController();

  DiscountModel? _appliedDiscount;

  RentalBreakdown? _breakdown;
  double _calculatedRent = 0.0;
  double _netRent = 0.0;
  double _finalBalance = 0.0;
  bool _isSettling = false;

  @override
  void initState() {
    super.initState();
    _actualReturnTime = DateTime.now();
    _recalculate();

    // Load sub-items for this equipment item
    SubItemRepository().getSubItems(parentItemId: widget.lease.itemId).then((list) {
      if (mounted && list.isNotEmpty) {
        setState(() {
          _subItems = list;
          for (final s in list) {
            _subItemStatusMap[s.id] = 'available';
          }
        });
      }
    });
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
        totalCalculated += (b.totalRent * li.quantity);
      }
      _breakdown = RateCalculator.getReturnRentBreakdown(
        startTime: widget.lease.startTime,
        actualReturnTime: _actualReturnTime,
        rateHourly: widget.lease.leaseItems.first.rateHourly,
        rateDaily: widget.lease.leaseItems.first.rateDaily,
        rateWeekly: widget.lease.leaseItems.first.rateWeekly,
        rateMonthly: widget.lease.leaseItems.first.rateMonthly,
      );
    } else {
      InventoryItemModel? item = widget.lease.item;
      if (item != null) {
        _breakdown = RateCalculator.getReturnRentBreakdown(
          startTime: widget.lease.startTime,
          actualReturnTime: _actualReturnTime,
          rateHourly: item.rateHourly,
          rateDaily: item.rateDaily,
          rateWeekly: item.rateWeekly,
          rateMonthly: item.rateMonthly,
        );
        totalCalculated = _breakdown!.totalRent * widget.lease.quantity;
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
    final days = duration.inDays;
    final hours = duration.inHours % 24;

    final String displayName = _getLeaseItemDisplayName();

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
            // Asset Summary Tile
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.handyman, color: AppColors.primary, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Client: ${widget.lease.customer?.name ?? "Customer"} (${widget.lease.customer?.phone ?? "-"}) • ${widget.lease.totalPieces} Pcs',
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
            ),

            const SizedBox(height: 14),

            // Actual Duration & Timeline Card
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
                          const Text('Rental Duration', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _breakdown?.durationText ?? "$days Day(s), $hours Hr(s)",
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
                    'Recorded Duration: ${_breakdown?.durationText ?? "$days Day(s), $hours Hr(s)"}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? AppColors.primaryLight : AppColors.primary),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Physical Condition Inspection Module
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
                          Icon(Icons.fact_check_outlined, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
                          const SizedBox(width: 6),
                          const Text('Condition Inspection', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Text('Dispatch Photos: ${widget.lease.beforePhotoUrls.length}',
                          style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Master Quick Action: Select All Arrived in Good Condition
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _returnStatus = 'available';
                          for (final key in _subItemStatusMap.keys) {
                            _subItemStatusMap[key] = 'available';
                          }
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('All items & sub-items marked as Ready / Good Condition!'),
                            backgroundColor: AppColors.primary,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.done_all, size: 16),
                      label: const Text('Select All Arrived in Good Condition', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),

                  if (widget.lease.beforePhotoUrls.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Photos Taken When Leasing:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 8),
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
                  const SizedBox(height: 12),

                  // Individual Sub-Items Inspection Dropdowns if sub-items exist
                  if (_subItems.isNotEmpty) ...[
                    Text('Sub-Items Inspection & Return Status', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _subItems.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final sub = _subItems[index];
                        final currentSt = _subItemStatusMap[sub.id] ?? 'available';

                        return Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(sub.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    Text(sub.serialNumber != null && sub.serialNumber!.isNotEmpty ? 'SN: ${sub.serialNumber}' : sub.displaySku,
                                        style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              DropdownButton<String>(
                                value: currentSt,
                                underline: const SizedBox.shrink(),
                                items: const [
                                  DropdownMenuItem(value: 'available', child: Text('Ready', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryLight))),
                                  DropdownMenuItem(value: 'awaiting_inspection', child: Text('Inspection', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.tertiaryAmber))),
                                  DropdownMenuItem(value: 'maintenance', child: Text('Damaged', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber))),
                                  DropdownMenuItem(value: 'lost', child: Text('Lost', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.errorRed))),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _subItemStatusMap[sub.id] = val;
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ] else ...[
                    // Stock Return Status Dropdown Selector for Parent Item
                    Text('Stock Return Status', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _returnStatus,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'available',
                          child: Text('Available (Inspected & Ready to Rent)', style: TextStyle(fontSize: 12)),
                        ),
                        DropdownMenuItem(
                          value: 'awaiting_inspection',
                          child: Text('Awaiting Inspection (Pending Testing)', style: TextStyle(fontSize: 12)),
                        ),
                        DropdownMenuItem(
                          value: 'maintenance',
                          child: Text('Maintenance (Damaged / Under Repair)', style: TextStyle(fontSize: 12)),
                        ),
                        DropdownMenuItem(
                          value: 'lost',
                          child: Text('Lost / Unreturned (Need Restock)', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _returnStatus = val;
                          });
                        }
                      },
                    ),
                  ],
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

                  // Display Component Breakdown List
                  if (_breakdown != null && _breakdown!.components.isNotEmpty) ...[
                    ..._breakdown!.components.map((comp) {
                      final compSubtotal = comp.amount * widget.lease.quantity;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(comp.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  Text(
                                    widget.lease.quantity > 1
                                        ? '${comp.calculation} = $currency${comp.amount.toStringAsFixed(2)} / pc'
                                        : comp.calculation,
                                    style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '$currency${compSubtotal.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      );
                    }),
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
                      return ListTile(
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
