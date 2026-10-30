import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/config/app_theme.dart';
import '../../core/services/pdf_receipt_service.dart';
import '../../core/utils/rate_calculator.dart';
import '../../core/utils/uuid_generator.dart';
import '../../data/models/damage_loss_incident_model.dart';
import '../../data/models/discount_model.dart';
import '../../data/models/inventory_item_model.dart';
import '../../data/models/lease_model.dart';
import '../../data/models/store_model.dart';
import '../../data/repositories/damage_loss_repository.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
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

  final String _billingMode = 'auto';
  String _returnStatus = 'available';

  // Sub-items tracking for this lease item
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

    // Populate sub-item return status map
    if (widget.lease.leaseItems.isNotEmpty) {
      for (final line in widget.lease.leaseItems) {
        for (final sub in line.leasedSubItems) {
          if (!sub.isExcluded) {
            _subItemStatusMap[sub.id] = sub.conditionStatus == 'rented' ? 'available' : sub.conditionStatus;
          }
        }
      }
    }
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

      // Create damage/loss incidents if any physical component is marked damaged or lost
      final damageRepo = DamageLossRepository();

      for (final line in widget.lease.leaseItems) {
        for (final sub in line.leasedSubItems) {
          if (!sub.isExcluded) {
            final st = _subItemStatusMap[sub.id] ?? 'available';
            if (st == 'maintenance' || st == 'lost') {
              final incidentType = st == 'lost' ? 'lost' : 'damaged';
              final incident = DamageLossIncidentModel(
                id: UuidGenerator.generateV4(),
                storeId: store.id,
                leaseId: settled.id,
                leaseItemId: line.id,
                inventoryComponentUnitId: sub.inventoryComponentUnitId ?? sub.id,
                incidentType: incidentType,
                description: 'Reported $incidentType during return inspection of ${sub.itemName}',
                customerCharge: incidentType == 'lost' ? 1500.0 : 500.0,
                estimatedRepairCost: incidentType == 'lost' ? 0.0 : 400.0,
                reportedAt: DateTime.now(),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              );
              await damageRepo.createIncident(incident);
            }
          }
        }
      }

      // Reload inventory so available quantities immediately update across all screens
      if (mounted) {
        context.read<InventoryCubit>().loadInventory();
      }

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
          content: Text('Error settling return: $e'),
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
                style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : AppColors.secondary),
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
                    child: QrImageView(data: upiUri, version: QrVersions.auto, size: 200),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(20),
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
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppColors.lightOnSurface),
              ),
              const SizedBox(height: 8),
              Text(
                'Settlement PDF ready for ${lease.customer?.name ?? "Customer"}.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : AppColors.secondary),
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

    final displayName = _getLeaseItemDisplayName();

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
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Client: ${widget.lease.customer?.name ?? "Customer"} (${widget.lease.customer?.phone ?? "-"}) • ${widget.lease.totalPieces} Pcs',
                          style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Condition Inspection Card
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
                      const Row(
                        children: [
                          Icon(Icons.fact_check_outlined, size: 18, color: AppColors.primary),
                          SizedBox(width: 6),
                          Text('Condition Inspection', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Text('Photos: ${widget.lease.beforePhotoUrls.length}', style: const TextStyle(fontSize: 11, color: AppColors.secondary)),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Master Quick Action: Select All Arrived in Good Condition
                  SizedBox(
                    width: double.infinity,
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
                            content: Text('All non-excluded components marked as Good Condition / Available!'),
                            backgroundColor: AppColors.primary,
                          ),
                        );
                      },
                      icon: const Icon(Icons.done_all, size: 16),
                      label: const Text('Select All Arrived in Good Condition', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 8)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Per-Sub-Item Condition Status Dropdowns
                  if (widget.lease.leaseItems.isNotEmpty) ...[
                    ...widget.lease.leaseItems.map((line) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(line.item?.name ?? 'Equipment', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                          const SizedBox(height: 6),

                          ...line.leasedSubItems.map((sub) {
                            if (sub.isExcluded) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text('• ${sub.itemName} [EXCLUDED FROM RENTAL - NOT EXPECTED]', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              );
                            }

                            final currentSt = _subItemStatusMap[sub.id] ?? 'available';

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '• ${sub.itemName}${sub.serialNumber != null ? " [${sub.serialNumber}]" : ""}',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  DropdownButton<String>(
                                    value: currentSt,
                                    isDense: true,
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
                          }),
                        ],
                      );
                    }),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Financial Summary & Calculations
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
                      const Text('Rental Charge Subtotal', style: TextStyle(fontSize: 12)),
                      Text('$currency${_calculatedRent.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _discountController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: 'Discount ($currency)', prefixText: '$currency '),
                          onChanged: (_) => setState(_recalculate),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _damageFeeController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: 'Damage Fee ($currency)', prefixText: '$currency '),
                          onChanged: (_) => setState(_recalculate),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Final Net Charge', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      Text('$currency${_netRent.toStringAsFixed(2)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.primary)),
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
                    : (isDark ? const Color(0xFF142E24) : const Color(0xFFECFDF5)),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _finalBalance > 0 ? AppColors.tertiaryAmber : AppColors.primaryLight, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _finalBalance > 0 ? 'Client Owes Store (Additional Collect)' : 'Store Refund to Client',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _finalBalance > 0 ? Colors.amber.shade900 : AppColors.primaryLight),
                      ),
                      if (store != null && _finalBalance > 0)
                        IconButton(
                          icon: const Icon(Icons.qr_code, color: AppColors.primary),
                          onPressed: () => _showPaymentQrModal(store),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$currency${_finalBalance.abs().toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _finalBalance > 0 ? AppColors.errorRed : AppColors.primaryLight),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

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
}
