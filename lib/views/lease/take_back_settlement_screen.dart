import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/config/app_theme.dart';
import '../../core/services/admob_service.dart';
import '../../core/services/pdf_receipt_service.dart';
import '../../core/utils/rate_calculator.dart';
import '../../core/utils/whatsapp_launcher.dart';
import '../../core/widgets/app_image_view.dart';
import '../../data/models/discount_model.dart';
import '../../data/models/lease_model.dart';
import '../../data/models/store_model.dart';
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
  bool _inspectionPassed = true;
  final String _billingMode = 'auto'; // 'auto', 'hourly', 'daily'

  final TextEditingController _discountController = TextEditingController(text: '0');
  final TextEditingController _damageFeeController = TextEditingController(text: '0');
  final TextEditingController _notesController = TextEditingController();

  double _calculatedRent = 0.0;
  double _netRent = 0.0;
  double _finalBalance = 0.0;
  bool _isSettling = false;
  DiscountModel? _selectedDiscount;
  RentalBreakdown? _breakdown;

  @override
  void initState() {
    super.initState();
    _actualReturnTime = DateTime.now();
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
    if (widget.lease.returnNotes != null && widget.lease.returnNotes!.contains('Leased Equipment Items:')) {
      final noteStr = widget.lease.returnNotes!.replaceFirst('Leased Equipment Items:', '').trim();
      if (noteStr.isNotEmpty) return noteStr;
    }
    return widget.lease.item?.name ?? 'Equipment Item';
  }

  void _recalculate() {
    final item = widget.lease.item;
    if (item == null) return;

    _breakdown = RateCalculator.getReturnRentBreakdown(
      startTime: widget.lease.startTime,
      actualReturnTime: _actualReturnTime,
      rateHourly: item.rateHourly,
      rateDaily: item.rateDaily,
      rateWeekly: item.rateWeekly,
      rateMonthly: item.rateMonthly,
      billingMode: _billingMode,
    );
    _calculatedRent = _breakdown!.totalRent;

    if (_selectedDiscount != null) {
      final discountAmt = _selectedDiscount!.calculateDiscountAmount(_calculatedRent);
      _discountController.text = discountAmt.toStringAsFixed(2);
    }

    final discount = double.tryParse(_discountController.text) ?? 0.0;
    final damageFee = double.tryParse(_damageFeeController.text) ?? 0.0;

    _netRent = RateCalculator.calculateNetRent(
      calculatedRent: _calculatedRent,
      discount: discount,
      damageOrLateFee: damageFee,
    );

    _finalBalance = RateCalculator.calculateSettlementBalance(
      netRentDue: _netRent,
      depositPaid: widget.lease.depositPaid,
      advanceRentPaid: widget.lease.advanceRentPaid,
    );

    if (mounted) setState(() {});
  }

  Future<void> _selectActualReturnDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _actualReturnTime,
      firstDate: widget.lease.startTime.subtract(const Duration(days: 1)),
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

      // Reload inventory so available quantity immediately increments (e.g. 4/5 -> 5/5 Available)
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
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final phone = lease.customer?.phone ?? '';
                    final msg =
                        'Rental return settlement from ${store.businessName} for ${_getLeaseItemDisplayName()}. Net rent: ${store.currencySymbol}${lease.netRentTotal}. Final balance: ${store.currencySymbol}${lease.finalSettlementBalance}. Thank you for renting with us!';

                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) Navigator.pop(context);

                    await WhatsAppLauncher.sendWhatsAppMessage(phone: phone, message: msg);
                    await PdfReceiptService.instance.shareReceipt(pdfFile, msg);

                    // AdMob interstitial check
                    AdMobService.instance.showInterstitialIfEligible(isPro: store.isPro);
                  },
                  icon: const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                  label: const Text('Send Settlement to WhatsApp', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => PdfReceiptService.instance.printReceipt(pdfFile),
                  icon: Icon(Icons.print, size: 18, color: isDark ? Colors.white : AppColors.primary),
                  label: Text('Print Receipt', style: TextStyle(color: isDark ? Colors.white : AppColors.primary, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  AdMobService.instance.showInterstitialIfEligible(isPro: store.isPro);
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                child: Text(
                  'Back to Dashboard',
                  style: TextStyle(color: isDark ? AppColors.primaryLight : AppColors.primary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConditionPhotoThumbnail(BuildContext context, String rawUrl, int idx, bool isDark) {
    return AppImageView(
      imagePathOrUrl: rawUrl,
      width: 76,
      height: 76,
      fit: BoxFit.cover,
      borderRadius: BorderRadius.circular(10),
      enableZoom: true,
      fallback: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_outlined, size: 24, color: isDark ? AppColors.primaryLight : AppColors.primary),
            const SizedBox(height: 2),
            Text('#${idx + 1}', style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
          ],
        ),
      ),
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

    final discountState = context.watch<DiscountCubit>().state;
    final allDiscounts = discountState is DiscountLoaded ? discountState.discounts : <DiscountModel>[];
    final durationDays = days < 1 ? 1 : days;
    final applicableDiscounts = allDiscounts
        .where((d) => d.matchesItem(itemId: widget.lease.itemId, durationDays: durationDays))
        .toList();

    final isEarly = _actualReturnTime.isBefore(widget.lease.expectedEndTime.subtract(const Duration(hours: 1)));
    final isLate = widget.lease.isOverdue;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('Item Return & Inspection'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Operational Context Strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightSurfaceLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LEASE INSPECTION & SETTLEMENT',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'Lease #${widget.lease.shortId}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isLate ? 'OVERDUE RETURN' : (isEarly ? 'EARLY RETURN' : 'ON TIME RETURN'),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isLate ? AppColors.errorRed : AppColors.primaryLight,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Asset & Customer Summary Tile
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
              ),
              child: Column(
                children: [
                  Row(
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
                              _getLeaseItemDisplayName(),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${widget.lease.customer?.name ?? "Customer"} (${widget.lease.customer?.phone ?? "-"})',
                              style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Time Matrix
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Handed Out', style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                            Text(DateFormat('dd MMM, hh:mm a').format(widget.lease.startTime), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        InkWell(
                          onTap: _selectActualReturnDateTime,
                          borderRadius: BorderRadius.circular(6),
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
                  if (widget.lease.beforePhotoUrls.isNotEmpty) ...[
                    const SizedBox(height: 10),
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
                  const SizedBox(height: 10),
                  // Inspection passed toggle
                  Material(
                    color: Colors.transparent,
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Inspection Passed', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: const Text('Zero damages, missing parts, or unreturned accessories.', style: TextStyle(fontSize: 11)),
                      value: _inspectionPassed,
                      activeThumbColor: AppColors.primary,
                      onChanged: (val) {
                        setState(() {
                          _inspectionPassed = val;
                        });
                      },
                    ),
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
                                  Text(comp.calculation, style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                                ],
                              ),
                            ),
                            Text('$currency${comp.amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 6),
                    Divider(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    const SizedBox(height: 6),
                  ] else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Base Calculated Rent ($_billingMode)', style: const TextStyle(fontSize: 13)),
                        Text('$currency${_calculatedRent.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Line 2: Discount Input / Dropdown
                  Row(
                    children: [
                      const Expanded(child: Text('Discount / Voucher (-)', style: TextStyle(fontSize: 13))),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _discountController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.right,
                          decoration: InputDecoration(
                            isDense: true,
                            prefixText: '$currency ',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          ),
                          onChanged: (_) => _recalculate(),
                        ),
                      ),
                    ],
                  ),
                  if (applicableDiscounts.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 28,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: applicableDiscounts.length,
                        separatorBuilder: (context, index) => const SizedBox(width: 6),
                        itemBuilder: (ctx, idx) {
                          final disc = applicableDiscounts[idx];
                          final isSelected = _selectedDiscount?.id == disc.id;
                          return InkWell(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selectedDiscount = null;
                                  _discountController.text = '0';
                                } else {
                                  _selectedDiscount = disc;
                                }
                              });
                              _recalculate();
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary
                                    : (isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceContainer),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? AppColors.primary : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                                ),
                              ),
                              child: Text(
                                '${disc.code} (${disc.discountText})',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? Colors.white : (isDark ? AppColors.primaryLight : AppColors.primary),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),

                  // Line 3: Damage / Late Fee
                  Row(
                    children: [
                      const Expanded(child: Text('Damage / Late Fee (+)', style: TextStyle(fontSize: 13))),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _damageFeeController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.right,
                          decoration: InputDecoration(
                            isDense: true,
                            prefixText: '$currency ',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          ),
                          onChanged: (_) => _recalculate(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 6),

                  // Net Rent Due
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Net Rent Due', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      Text('$currency${_netRent.toStringAsFixed(2)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Less: Security Deposit Held in Escrow',
                          style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                      Text('-$currency${widget.lease.depositPaid.toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 11, color: isDark ? AppColors.primaryLight : AppColors.primary)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Final Settlement Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _finalBalance > 0
                    ? (isDark ? const Color(0xFF3B1515) : const Color(0xFFFEF2F2))
                    : (_finalBalance < 0
                        ? (isDark ? const Color(0xFF142E24) : const Color(0xFFECFDF5))
                        : (isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow)),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _finalBalance > 0
                      ? (isDark ? const Color(0xFF6B1D22) : const Color(0xFFFECACA))
                      : (_finalBalance < 0
                          ? (isDark ? AppColors.primary : const Color(0xFFA7F3D0))
                          : (isDark ? AppColors.darkBorder : AppColors.lightBorder)),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _finalBalance > 0
                                ? 'COLLECT FROM CUSTOMER'
                                : (_finalBalance < 0 ? 'REFUND DEPOSIT TO CUSTOMER' : 'FULLY SETTLED'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: _finalBalance > 0
                                  ? AppColors.errorRed
                                  : (_finalBalance < 0 ? AppColors.primaryLight : (isDark ? Colors.white : AppColors.slateNavy)),
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            _finalBalance > 0
                                ? 'Rent exceeded deposit held'
                                : (_finalBalance < 0 ? 'Rent auto-deducted from deposit' : 'Net zero balance'),
                            style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                          ),
                        ],
                      ),
                      Text(
                        '$currency${_finalBalance.abs().toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: _finalBalance > 0
                              ? AppColors.errorRed
                              : (_finalBalance < 0 ? AppColors.primaryLight : (isDark ? Colors.white : AppColors.slateNavy)),
                        ),
                      ),
                    ],
                  ),
                  if (_finalBalance > 0) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: store == null ? null : () => _showPaymentQrModal(store),
                      icon: const Icon(Icons.qr_code, size: 18),
                      label: const Text('Show Payment UPI QR Code'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.errorRed,
                        side: const BorderSide(color: AppColors.errorRed),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Confirm Return & Settlement CTA
            ElevatedButton(
              onPressed: _isSettling ? null : _handleSettlement,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSettling
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                    )
                  : const Text('Confirm Payment & Release Item Back to Inventory', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
