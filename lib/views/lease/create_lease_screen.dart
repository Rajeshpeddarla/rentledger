import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../core/config/app_theme.dart';
import '../../core/services/admob_service.dart';
import '../../core/services/pdf_receipt_service.dart';
import '../../core/services/r2_storage_service.dart';
import '../../core/utils/rate_calculator.dart';
import '../../core/utils/uuid_generator.dart';
import '../../core/widgets/app_image_view.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/inventory_item_model.dart';
import '../../data/models/inventory_unit_model.dart';
import '../../data/models/lease_item_model.dart';
import '../../data/models/lease_model.dart';
import '../../data/models/leased_sub_item_model.dart';
import '../../data/models/store_model.dart';
import '../../data/repositories/inventory_unit_repository.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../../viewmodels/customer/customer_cubit.dart';
import '../../viewmodels/customer/customer_state.dart';
import '../../viewmodels/inventory/inventory_cubit.dart';
import '../../viewmodels/inventory/inventory_state.dart';
import '../../viewmodels/lease/lease_cubit.dart';
import '../profile/subscription_paywall_screen.dart';
import 'in_app_camera_screen.dart';

class LeaseItemQuantity {
  final InventoryItemModel item;
  int pieces;

  // Custom Negotiated Discounted Rates per line item
  double? customHourlyRate;
  double? customDailyRate;
  double? customWeeklyRate;
  double? customMonthlyRate;

  List<InventoryUnitModel> loadedUnits;
  List<InventoryUnitModel> selectedUnits;

  // Excluded Component Unit IDs per physical set unit ID
  Map<String, Set<String>> excludedComponentIdsMap;

  LeaseItemQuantity({
    required this.item,
    this.pieces = 1,
    this.customHourlyRate,
    this.customDailyRate,
    this.customWeeklyRate,
    this.customMonthlyRate,
    List<InventoryUnitModel>? loadedUnits,
    List<InventoryUnitModel>? selectedUnits,
    Map<String, Set<String>>? excludedComponentIdsMap,
  })  : loadedUnits = loadedUnits ?? [],
        selectedUnits = selectedUnits ?? [],
        excludedComponentIdsMap = excludedComponentIdsMap ?? {};

  double get effectiveRateHourly => customHourlyRate ?? item.rateHourly;
  double get effectiveRateDaily => customDailyRate ?? item.rateDaily;
  double get effectiveRateWeekly => customWeeklyRate ?? item.rateWeekly;
  double get effectiveRateMonthly => customMonthlyRate ?? item.rateMonthly;

  double get totalDailyRate => effectiveRateDaily * pieces;
  double get totalDepositExpected => item.depositAmount * pieces;
}

class CreateLeaseScreen extends StatefulWidget {
  final bool isPro;
  final InventoryItemModel? preSelectedItem;

  const CreateLeaseScreen({super.key, required this.isPro, this.preSelectedItem});

  @override
  State<CreateLeaseScreen> createState() => _CreateLeaseScreenState();
}

class _CreateLeaseScreenState extends State<CreateLeaseScreen> {
  final List<LeaseItemQuantity> _selectedLeaseItems = [];

  DateTime _startTime = DateTime.now();
  DateTime _expectedEndTime = DateTime.now().add(const Duration(days: 1));

  // Customer
  CustomerModel? _selectedCustomer;
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerPhoneController = TextEditingController();
  final TextEditingController _customerEmailController = TextEditingController();

  // Financials
  String _depositPaymentType = 'full'; // 'full', 'partial', 'none'
  final TextEditingController _depositPaidController = TextEditingController();
  final TextEditingController _advanceRentController = TextEditingController(text: '0');
  final TextEditingController _discountController = TextEditingController(text: '0');

  // Condition Photos (2-3 photos)
  final List<File> _beforePhotos = [];
  bool _isSaving = false;
  bool _hasConflict = false;

  double get totalExpectedDeposit =>
      _selectedLeaseItems.fold(0.0, (sum, i) => sum + i.totalDepositExpected);

  double get totalDailyRate =>
      _selectedLeaseItems.fold(0.0, (sum, i) => sum + i.totalDailyRate);

  int get totalPiecesLeased =>
      _selectedLeaseItems.fold(0, (sum, i) => sum + i.pieces);

  String _formatDuration(Duration duration) {
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;

    final List<String> parts = [];
    if (days > 0) parts.add('$days Day${days > 1 ? "s" : ""}');
    if (hours > 0) parts.add('$hours Hr${hours > 1 ? "s" : ""}');
    if (minutes > 0 || parts.isEmpty) parts.add('$minutes Min${minutes > 1 ? "s" : ""}');

    return parts.join(', ');
  }

  void _updateDepositIfFull() {
    if (_depositPaymentType == 'full') {
      _depositPaidController.text = totalExpectedDeposit.toStringAsFixed(0);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.preSelectedItem != null) {
      final line = LeaseItemQuantity(item: widget.preSelectedItem!, pieces: 1);
      _selectedLeaseItems.add(line);
      _loadUnitsForLine(line);
    }
    _depositPaidController.text = totalExpectedDeposit.toStringAsFixed(0);
    _validateConflict();
    _retrieveLostData();
  }

  Future<void> _loadUnitsForLine(LeaseItemQuantity line) async {
    try {
      final units = await InventoryUnitRepository().getUnitsForProduct(line.item.id);
      if (mounted) {
        setState(() {
          line.loadedUnits = units;
          final available = units.where((u) => u.isAvailable).toList();
          line.selectedUnits = available.take(line.pieces).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading units for ${line.item.name}: $e');
    }
  }

  Future<void> _retrieveLostData() async {
    try {
      final picker = ImagePicker();
      final response = await picker.retrieveLostData();
      if (response.isEmpty || response.file == null) return;
      final file = response.file;
      if (file != null && file.path.isNotEmpty) {
        setState(() {
          if (_beforePhotos.length < 3) {
            _beforePhotos.add(File(file.path));
          }
        });
      }
    } catch (e) {
      debugPrint('Error retrieving lost camera photo: $e');
    }
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _customerEmailController.dispose();
    _depositPaidController.dispose();
    _advanceRentController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  Future<void> _selectStartDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _startTime,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (pickedDate == null) return;

    if (!mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startTime),
    );

    final selectedTime = pickedTime ?? TimeOfDay.fromDateTime(_startTime);

    setState(() {
      _startTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        selectedTime.hour,
        selectedTime.minute,
      );
      if (_expectedEndTime.isBefore(_startTime)) {
        _expectedEndTime = _startTime.add(const Duration(days: 1));
      }
    });
    _validateConflict();
  }

  Future<void> _selectEndDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _expectedEndTime.isBefore(_startTime) ? _startTime : _expectedEndTime,
      firstDate: _startTime,
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (pickedDate == null) return;

    if (!mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_expectedEndTime),
    );

    final selectedTime = pickedTime ?? TimeOfDay.fromDateTime(_expectedEndTime);

    setState(() {
      _expectedEndTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        selectedTime.hour,
        selectedTime.minute,
      );
    });
    _validateConflict();
  }

  Future<void> _validateConflict() async {
    if (_selectedLeaseItems.isEmpty) return;
    bool conflictFound = false;
    for (final line in _selectedLeaseItems) {
      final hasConflict = await context.read<LeaseCubit>().checkDateConflict(
            itemId: line.item.id,
            startTime: _startTime,
            expectedEndTime: _expectedEndTime,
            totalQuantity: line.item.totalQuantity,
            requestedQuantity: line.pieces,
          );
      if (hasConflict) {
        conflictFound = true;
        break;
      }
    }
    if (mounted) {
      setState(() {
        _hasConflict = conflictFound;
      });
    }
  }

  Future<void> _pickPhoto() async {
    if (_beforePhotos.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum 3 condition proof photos.'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final sourceOption = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                const Text('Add Condition Proof Photo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined, color: AppColors.primary),
                  title: const Text('Take Photo with In-App Camera'),
                  onTap: () => Navigator.pop(ctx, 'camera'),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
                  title: const Text('Choose from Gallery'),
                  onTap: () => Navigator.pop(ctx, 'gallery'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (sourceOption == null) return;

    if (sourceOption == 'camera') {
      if (!mounted) return;
      final capturedFile = await Navigator.of(context).push<File>(
        MaterialPageRoute(builder: (_) => const InAppCameraScreen()),
      );
      if (capturedFile != null) {
        setState(() {
          _beforePhotos.add(capturedFile);
        });
      }
    } else {
      try {
        final picker = ImagePicker();
        final picked = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 800,
          maxHeight: 800,
          imageQuality: 70,
        );
        if (picked != null) {
          setState(() {
            _beforePhotos.add(File(picked.path));
          });
        }
      } catch (e) {
        debugPrint('Error picking gallery photo: $e');
      }
    }
  }

  void _onDepositTypeChanged(String type) {
    setState(() {
      _depositPaymentType = type;
      if (type == 'full') {
        _depositPaidController.text = totalExpectedDeposit.toStringAsFixed(0);
      } else if (type == 'none') {
        _depositPaidController.text = '0';
      }
    });
  }

  void _handleDispatch() async {
    if (_selectedLeaseItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one equipment item to rent out.'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    if (_selectedCustomer == null &&
        (_customerNameController.text.trim().isEmpty || _customerPhoneController.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer name and phone number are required.'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isSaving = true);

    try {
      final storeState = context.read<StoreCubit>().state;
      final store = storeState is StoreLoaded ? storeState.store : null;
      if (store == null) throw Exception('Store not initialized');

      // 1. Resolve or create customer
      CustomerModel customer;
      if (_selectedCustomer != null) {
        customer = _selectedCustomer!.copyWith(
          totalLeasesCount: _selectedCustomer!.totalLeasesCount + 1,
          updatedAt: DateTime.now(),
        );
        await context.read<CustomerCubit>().saveCustomer(customer);
      } else {
        customer = CustomerModel(
          id: UuidGenerator.generateV4(),
          storeId: store.id,
          name: _customerNameController.text.trim(),
          phone: _customerPhoneController.text.trim(),
          email: _customerEmailController.text.trim().isNotEmpty ? _customerEmailController.text.trim() : null,
          totalLeasesCount: 1,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await context.read<CustomerCubit>().saveCustomer(customer);
      }

      // 2. Upload condition photos
      final List<String> uploadedPhotoUrls = [];
      final leaseId = UuidGenerator.generateV4();

      for (int i = 0; i < _beforePhotos.length; i++) {
        final url = await R2StorageService.instance.uploadImage(
          file: _beforePhotos[i],
          folder: 'leases/$leaseId',
          filename: 'before_${i + 1}.webp',
        );
        if (url != null) uploadedPhotoUrls.add(url);
      }

      final itemsSummary = _selectedLeaseItems.map((li) => '${li.pieces}x ${li.item.name}').join(', ');
      final bool isFutureDate = _startTime.isAfter(DateTime.now().add(const Duration(hours: 4)));
      final initialStatus = isFutureDate ? 'reserved' : 'active';

      // 3. Create 1 Single Lease Order with LeaseItemModel line items and LeasedSubItemModel component handovers/exclusions
      final List<LeaseItemModel> lineItems = [];
      double grossRent = 0.0;

      for (int i = 0; i < _selectedLeaseItems.length; i++) {
        final line = _selectedLeaseItems[i];
        final item = line.item;

        final itemRent = RateCalculator.calculateReturnRent(
          startTime: _startTime,
          actualReturnTime: _expectedEndTime,
          rateHourly: line.effectiveRateHourly,
          rateDaily: line.effectiveRateDaily,
          rateWeekly: line.effectiveRateWeekly,
          rateMonthly: line.effectiveRateMonthly,
        );
        final lineGrossRent = itemRent * line.pieces;
        grossRent += lineGrossRent;

        final List<LeasedSubItemModel> lineLeasedSubItems = [];

        for (final unit in line.selectedUnits) {
          final excludedSet = line.excludedComponentIdsMap[unit.id] ?? {};

          for (final comp in unit.components) {
            final isExcluded = excludedSet.contains(comp.id);

            lineLeasedSubItems.add(LeasedSubItemModel(
              id: UuidGenerator.generateV4(),
              leaseId: leaseId,
              leaseItemId: '${leaseId}_item_${i + 1}',
              subItemId: comp.id,
              itemId: item.id,
              storeId: store.id,
              itemName: comp.componentName,
              serialNumber: comp.serialNumber,
              isExcluded: isExcluded,
              conditionStatus: isExcluded ? 'available' : 'rented',
              notes: isExcluded ? 'Excluded from rental handover' : null,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ));
          }
        }

        final lineItem = LeaseItemModel(
          id: '${leaseId}_item_${i + 1}',
          leaseId: leaseId,
          storeId: store.id,
          itemId: item.id,
          quantity: line.pieces,
          rateHourly: item.rateHourly,
          rateDaily: item.rateDaily,
          rateWeekly: item.rateWeekly,
          rateMonthly: item.rateMonthly,
          discountedRateHourly: line.customHourlyRate ?? 0.0,
          discountedRateDaily: line.customDailyRate ?? 0.0,
          discountedRateWeekly: line.customWeeklyRate ?? 0.0,
          discountedRateMonthly: line.customMonthlyRate ?? 0.0,
          depositAmount: item.depositAmount,
          lineCalculatedRent: lineGrossRent,
          returnStatus: 'available',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          item: item,
          leasedSubItems: lineLeasedSubItems,
        );
        lineItems.add(lineItem);
      }

      final primaryItem = _selectedLeaseItems.first.item;
      final taxType = primaryItem.taxType;
      final taxRate = primaryItem.taxRate;
      final isInclusive = primaryItem.isTaxInclusive;

      // Apply overall discount first before calculating taxes
      final double discountVal = double.tryParse(_discountController.text) ?? 0.0;
      final double discountedGrossRent = (grossRent - discountVal) < 0 ? 0.0 : (grossRent - discountVal);

      double taxableSubtotal = discountedGrossRent;
      double taxAmount = 0.0;
      double totalWithTax = discountedGrossRent;

      if (taxType != 'No Tax' && taxRate > 0) {
        if (isInclusive) {
          taxableSubtotal = double.parse((discountedGrossRent / (1 + (taxRate / 100.0))).toStringAsFixed(2));
          taxAmount = double.parse((discountedGrossRent - taxableSubtotal).toStringAsFixed(2));
          totalWithTax = discountedGrossRent;
        } else {
          taxableSubtotal = discountedGrossRent;
          taxAmount = double.parse((discountedGrossRent * (taxRate / 100.0)).toStringAsFixed(2));
          totalWithTax = double.parse((discountedGrossRent + taxAmount).toStringAsFixed(2));
        }
      }

      final lease = LeaseModel(
        id: leaseId,
        storeId: store.id,
        itemId: primaryItem.id,
        customerId: customer.id,
        startTime: _startTime,
        expectedEndTime: _expectedEndTime,
        beforePhotoUrls: uploadedPhotoUrls,
        depositExpected: totalExpectedDeposit,
        depositPaid: double.tryParse(_depositPaidController.text) ?? 0.0,
        advanceRentPaid: double.tryParse(_advanceRentController.text) ?? 0.0,
        depositPaymentType: _depositPaymentType,
        calculatedRent: grossRent,
        discountAmount: discountVal,
        discountedNetRentTotal: totalWithTax,
        netRentTotal: totalWithTax,
        taxableAmount: taxableSubtotal,
        appliedTaxType: taxType,
        appliedTaxRate: taxRate,
        taxAmount: taxAmount,
        totalAmountWithTax: totalWithTax,
        isTaxInclusive: isInclusive,
        returnNotes: 'Leased Equipment Items: $itemsSummary',
        quantity: totalPiecesLeased,
        status: initialStatus,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        leaseItems: lineItems,
        item: primaryItem,
        customer: customer,
      );

      if (!mounted) return;

      final createdLease = await context.read<LeaseCubit>().createLease(
            lease,
            isPro: widget.isPro,
            totalItemQuantity: primaryItem.totalQuantity,
          );

      if (mounted) {
        context.read<InventoryCubit>().loadInventory();
      }

      final pdfFile = await PdfReceiptService.instance.generateReceiptForLease(
        store: store,
        lease: createdLease,
        multiItemLeases: [createdLease],
      );

      if (!mounted) return;
      _showDispatchSuccessSheet(store, createdLease, pdfFile);
    } catch (e) {
      if (!mounted) return;
      if (e.toString().contains('FREE_LEASE_LIMIT_REACHED')) {
        _showUpgradePaywallDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error dispatching lease: $e'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showUpgradePaywallDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Free Monthly Limit Reached'),
        content: const Text(
          'Free tier allows up to 500 leases per month. Upgrade to Pro for unlimited leases, custom store branding, and direct PDF generation.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SubscriptionPaywallScreen()),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Upgrade to Pro'),
          ),
        ],
      ),
    );
  }

  void _showDispatchSuccessSheet(StoreModel store, LeaseModel lease, File pdfFile) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final isReserved = lease.status == 'reserved';
        return Container(
          padding: const EdgeInsets.all(24),
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
                isReserved ? 'Equipment Reserved Successfully!' : 'Item Rented Successfully!',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Handover receipt generated for ${lease.customer?.name ?? "Customer"}.',
                style: const TextStyle(fontSize: 13, color: AppColors.secondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () async {
                  final msg =
                      'Hello ${lease.customer?.name ?? "Customer"}, here is your official rental receipt from ${store.businessName} for ${lease.itemNamesSummary}. Expected return: ${DateFormat("dd MMM, hh:mm a").format(lease.expectedEndTime)}. Security deposit: ${store.currencySymbol}${lease.depositPaid}.';

                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) Navigator.pop(context);

                  await PdfReceiptService.instance.shareReceipt(pdfFile, msg);
                  AdMobService.instance.showInterstitialIfEligible(isPro: widget.isPro);
                },
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Share PDF Receipt to WhatsApp'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  await PdfReceiptService.instance.printReceipt(pdfFile);
                },
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Print / Preview Receipt'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  AdMobService.instance.showInterstitialIfEligible(isPro: widget.isPro);
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
    final currency = storeState is StoreLoaded ? storeState.store.currencySymbol : '₹';

    final bool isFutureDate = _startTime.isAfter(DateTime.now().add(const Duration(hours: 4)));
    final String ctaLabel = isFutureDate ? 'Reserve for Future & Issue Receipt' : 'Confirm Lease & Issue Receipt';
    final IconData ctaIcon = isFutureDate ? Icons.event_available : Icons.assignment_turned_in;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: Text(isFutureDate ? 'Reserve Equipment' : 'Lease Item'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Selected Asset Summary Tile with Physical Unit Selection & Component Exclusions
            _buildAssetSelectorCard(context, currency, isDark),
            const SizedBox(height: 16),

            // 2. Timeline
            _buildTimelineCard(context, isDark),
            const SizedBox(height: 16),

            // 3. Customer
            _buildCustomerCard(context, isDark, currency),
            const SizedBox(height: 16),

            // 4. Financial Summary
            _buildFinancialSummaryCard(context, currency, isDark),
            const SizedBox(height: 16),

            // 5. Condition Proof
            _buildConditionProofCard(context, isDark),
            const SizedBox(height: 16),

            // 6. Upfront Deposit
            _buildUpfrontPaymentCard(context, currency, isDark),
            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _isSaving ? null : _handleDispatch,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(ctaIcon, size: 20),
                        const SizedBox(width: 8),
                        Text(ctaLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _openNegotiateRateModal(BuildContext context, LeaseItemQuantity line, String currency, bool isDark) {
    final hCtrl = TextEditingController(text: line.effectiveRateHourly.toStringAsFixed(0));
    final dCtrl = TextEditingController(text: line.effectiveRateDaily.toStringAsFixed(0));
    final wCtrl = TextEditingController(text: line.effectiveRateWeekly.toStringAsFixed(0));
    final mCtrl = TextEditingController(text: line.effectiveRateMonthly.toStringAsFixed(0));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
                  Text(
                    'Negotiate Custom Rates for ${line.item.name}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Base Rates — Daily: $currency${line.item.rateDaily.toStringAsFixed(0)} • Hourly: $currency${line.item.rateHourly.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 11, color: AppColors.secondary),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: hCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Hourly Rate ($currency)',
                            prefixText: '$currency ',
                            isDense: true,
                          ),
                          onChanged: (val) {
                            final h = double.tryParse(val) ?? 0.0;
                            if (h > 0) {
                              final rates = RateCalculator.suggestRates(hourly: h);
                              setModalState(() {
                                dCtrl.text = rates['daily']!.toStringAsFixed(0);
                                wCtrl.text = rates['weekly']!.toStringAsFixed(0);
                                mCtrl.text = rates['monthly']!.toStringAsFixed(0);
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: dCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Daily Rate ($currency)',
                            prefixText: '$currency ',
                            isDense: true,
                          ),
                          onChanged: (val) {
                            final d = double.tryParse(val) ?? 0.0;
                            if (d > 0) {
                              final rates = RateCalculator.suggestRates(daily: d);
                              setModalState(() {
                                hCtrl.text = rates['hourly']!.toStringAsFixed(0);
                                wCtrl.text = rates['weekly']!.toStringAsFixed(0);
                                mCtrl.text = rates['monthly']!.toStringAsFixed(0);
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: wCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Weekly Rate ($currency)',
                            prefixText: '$currency ',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: mCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Monthly Rate ($currency)',
                            prefixText: '$currency ',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            this.setState(() {
                              line.customHourlyRate = null;
                              line.customDailyRate = null;
                              line.customWeeklyRate = null;
                              line.customMonthlyRate = null;
                              _updateDepositIfFull();
                            });
                            Navigator.pop(modalCtx);
                          },
                          child: const Text('Reset Base Rates'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            this.setState(() {
                              line.customHourlyRate = double.tryParse(hCtrl.text);
                              line.customDailyRate = double.tryParse(dCtrl.text);
                              line.customWeeklyRate = double.tryParse(wCtrl.text);
                              line.customMonthlyRate = double.tryParse(mCtrl.text);
                              _updateDepositIfFull();
                            });
                            Navigator.pop(modalCtx);
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                          child: const Text('Apply Rates'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAssetSelectorCard(BuildContext context, String currency, bool isDark) {
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
              Text(
                'Selected Equipment (${_selectedLeaseItems.length})',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              TextButton(
                onPressed: () => _openItemSelectionModal(context),
                child: Text(
                  _selectedLeaseItems.isEmpty ? '+ Add Equipment' : '+ Add More',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          if (_selectedLeaseItems.isNotEmpty) ...[
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _selectedLeaseItems.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final line = _selectedLeaseItems[index];

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Row: Equipment Name, SKU, Base Daily Rate, Deposit & Negotiated Badge
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(line.item.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      '${line.item.displaySku} • $currency${line.effectiveRateDaily.toStringAsFixed(0)}/day • Deposit: $currency${line.item.depositAmount.toStringAsFixed(0)}',
                                      style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                    ),
                                    if (line.customDailyRate != null || line.customHourlyRate != null || line.customWeeklyRate != null || line.customMonthlyRate != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                                        child: const Text('Negotiated Rate', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.primary)),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Bottom Action Row (Below Name): Negotiate Button on Left, Pieces Counter on Right
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: () => _openNegotiateRateModal(context, line, currency, isDark),
                            icon: const Icon(Icons.edit_outlined, size: 14),
                            label: Text(
                              line.customDailyRate != null ? 'Rate: $currency${line.effectiveRateDaily.toInt()}' : 'Negotiate Rate',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, size: 22),
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(4),
                                onPressed: () {
                                  setState(() {
                                    if (line.pieces > 1) {
                                      line.pieces--;
                                      if (line.selectedUnits.length > line.pieces) {
                                        line.selectedUnits = line.selectedUnits.take(line.pieces).toList();
                                      }
                                    } else {
                                      _selectedLeaseItems.removeAt(index);
                                    }
                                    _updateDepositIfFull();
                                  });
                                  _validateConflict();
                                },
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  '${line.pieces} Pcs',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline, size: 22),
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(4),
                                onPressed: () {
                                  setState(() {
                                    if (line.pieces < line.item.availableQuantity) {
                                      line.pieces++;
                                      final avail = line.loadedUnits.where((u) => u.isAvailable && !line.selectedUnits.contains(u)).firstOrNull;
                                      if (avail != null) line.selectedUnits.add(avail);
                                    }
                                    _updateDepositIfFull();
                                  });
                                  _validateConflict();
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Physical Set Unit Cards & Component Inclusion / Exclusion Toggles
                      if (line.selectedUnits.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, size: 14, color: AppColors.primary),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'All items are pre-selected. Tap any item chip to exclude it from this rental.',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primary),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),

                        ...line.selectedUnits.map((unit) {
                          final excludedSet = line.excludedComponentIdsMap[unit.id] ?? {};

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkCard : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Physical Set: ${unit.assetCode}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(4)),
                                      child: const Text('ASSIGNED', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),

                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: unit.components.map((comp) {
                                    final isExcluded = excludedSet.contains(comp.id);
                                    final label = '${comp.componentName}${comp.serialNumber != null ? " [${comp.serialNumber}]" : ""}';

                                    return InkWell(
                                      onTap: () {
                                        setState(() {
                                          final set = line.excludedComponentIdsMap[unit.id] ?? {};
                                          if (isExcluded) {
                                            set.remove(comp.id);
                                          } else {
                                            set.add(comp.id);
                                          }
                                          line.excludedComponentIdsMap[unit.id] = set;
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(20),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: isExcluded
                                              ? (isDark ? const Color(0xFF3B1515) : const Color(0xFFFFEAEA))
                                              : (isDark ? const Color(0xFF142E24) : const Color(0xFFECFDF5)),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(
                                            color: isExcluded ? AppColors.errorRed : AppColors.primaryLight,
                                            width: 1.0,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isExcluded ? Icons.close : Icons.check,
                                              size: 14,
                                              color: isExcluded ? AppColors.errorRed : AppColors.primaryLight,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              label,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                decoration: isExcluded ? TextDecoration.lineThrough : null,
                                                color: isExcluded
                                                    ? AppColors.errorRed
                                                    : (isDark ? AppColors.primaryLight : AppColors.primary),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                );
              },
            ),
          ] else
            OutlinedButton.icon(
              onPressed: () => _openItemSelectionModal(context),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Tap to Choose Equipment Items & Pieces'),
            ),
        ],
      ),
    );
  }

  void _openItemSelectionModal(BuildContext context) {
    final inventoryState = context.read<InventoryCubit>().state;
    final items = inventoryState is InventoryLoaded ? inventoryState.allItems : <InventoryItemModel>[];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final storeState = context.read<StoreCubit>().state;
    final currency = storeState is StoreLoaded ? storeState.store.currencySymbol : '₹';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalCtx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
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
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Select Equipment to Rent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${items.length} Items Available',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          'No equipment items found in inventory.',
                          style: TextStyle(color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                        ),
                      )
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final it = items[index];
                          final isAlreadySelected = _selectedLeaseItems.any((line) => line.item.id == it.id);
                          final isAvailable = it.availableQuantity > 0;

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkCard : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isAlreadySelected
                                    ? AppColors.primary
                                    : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                                width: isAlreadySelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                // Thumbnail Image
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: it.imageR2Url != null && it.imageR2Url!.isNotEmpty
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: AppImageView(imagePathOrUrl: it.imageR2Url, fit: BoxFit.cover),
                                        )
                                      : const Icon(Icons.handyman_outlined, color: AppColors.primary, size: 24),
                                ),
                                const SizedBox(width: 12),

                                // Equipment Details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        it.name,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${it.category} • $currency${it.rateDaily.toStringAsFixed(0)}/day',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isAvailable
                                              ? (isDark ? const Color(0xFF142E24) : const Color(0xFFECFDF5))
                                              : (isDark ? const Color(0xFF3B1515) : const Color(0xFFFFDAD6)),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          isAvailable ? '${it.availableQuantity}/${it.totalQuantity} Sets Available' : 'Out of Stock',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: isAvailable ? AppColors.primaryLight : AppColors.errorRed,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Action Button
                                ElevatedButton(
                                  onPressed: (isAlreadySelected || !isAvailable)
                                      ? null
                                      : () {
                                          setState(() {
                                            final line = LeaseItemQuantity(item: it, pieces: 1);
                                            _selectedLeaseItems.add(line);
                                            _loadUnitsForLine(line);
                                            _updateDepositIfFull();
                                          });
                                          Navigator.pop(modalCtx);
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isAlreadySelected ? Colors.grey : AppColors.primary,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: Text(
                                    isAlreadySelected ? 'Added' : '+ Select',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
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
      },
    );
  }

  Widget _buildTimelineCard(BuildContext context, bool isDark) {
    final duration = _expectedEndTime.difference(_startTime);
    final durationText = _formatDuration(duration);

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
              Row(
                children: [
                  Icon(Icons.calendar_month_outlined, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
                  const SizedBox(width: 6),
                  const Text('Lease Schedule', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 12, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      durationText,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Side-by-side Start and Expected Return Tiles
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _selectStartDateTime,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'START / DISPATCH',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                            ),
                            Icon(Icons.edit_calendar_outlined, size: 14, color: isDark ? AppColors.primaryLight : AppColors.primary),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          DateFormat('dd MMM yyyy').format(_startTime),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          DateFormat('hh:mm a').format(_startTime),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
              ),
              Expanded(
                child: InkWell(
                  onTap: _selectEndDateTime,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'EXPECTED RETURN',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                            ),
                            Icon(Icons.edit_calendar_outlined, size: 14, color: isDark ? AppColors.primaryLight : AppColors.primary),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          DateFormat('dd MMM yyyy').format(_expectedEndTime),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          DateFormat('hh:mm a').format(_expectedEndTime),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Quick Duration Presets Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildQuickDurationChip('1 Day', const Duration(days: 1), isDark),
                const SizedBox(width: 6),
                _buildQuickDurationChip('2 Days', const Duration(days: 2), isDark),
                const SizedBox(width: 6),
                _buildQuickDurationChip('3 Days', const Duration(days: 3), isDark),
                const SizedBox(width: 6),
                _buildQuickDurationChip('1 Week', const Duration(days: 7), isDark),
                const SizedBox(width: 6),
                _buildQuickDurationChip('1 Month', const Duration(days: 30), isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickDurationChip(String label, Duration addDuration, bool isDark) {
    final isSelected = _expectedEndTime.difference(_startTime).inHours == addDuration.inHours;

    return InkWell(
      onTap: () {
        setState(() {
          _expectedEndTime = _startTime.add(addDuration);
        });
        _validateConflict();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : (isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ),
        ),
        child: Text(
          '+ $label',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  void _openClientPickerModal(BuildContext context, List<CustomerModel> customers, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalCtx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
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
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Select Existing Client', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${customers.length} Clients Registered',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              Expanded(
                child: customers.isEmpty
                    ? Center(
                        child: Text(
                          'No pre-added clients found.',
                          style: TextStyle(color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                        ),
                      )
                    : ListView.separated(
                        itemCount: customers.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final client = customers[index];
                          final isSelected = _selectedCustomer?.id == client.id;

                          return Container(
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkCard : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary
                                    : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                                child: Text(
                                  client.name.isNotEmpty ? client.name[0].toUpperCase() : 'C',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      client.name,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.tertiaryAmber.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.star, size: 12, color: Colors.amber),
                                        const SizedBox(width: 3),
                                        Text(
                                          '${client.loyaltyPoints} Pts',
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                '${client.phone}${client.email != null && client.email!.isNotEmpty ? " • ${client.email}" : ""} • ${client.totalLeasesCount} Rentals',
                                style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                              ),
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle, color: AppColors.primary, size: 20)
                                  : const Icon(Icons.chevron_right, size: 20),
                              onTap: () {
                                setState(() {
                                  _selectedCustomer = client;
                                  _customerNameController.text = client.name;
                                  _customerPhoneController.text = client.phone;
                                  _customerEmailController.text = client.email ?? '';
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

  Widget _buildCustomerCard(BuildContext context, bool isDark, String currency) {
    final customerState = context.watch<CustomerCubit>().state;
    final customers = customerState is CustomerLoaded ? customerState.allCustomers : <CustomerModel>[];

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
              const Row(
                children: [
                  Icon(Icons.person_outline, size: 18, color: AppColors.primary),
                  SizedBox(width: 6),
                  Text('Client Verification', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
              TextButton.icon(
                onPressed: () => _openClientPickerModal(context, customers, isDark),
                icon: const Icon(Icons.people_outline, size: 16),
                label: Text(
                  _selectedCustomer == null ? 'Select Client' : 'Change',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_selectedCustomer != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: Text(
                      _selectedCustomer!.name.isNotEmpty ? _selectedCustomer!.name[0].toUpperCase() : 'C',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_selectedCustomer!.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        Text(
                          '${_selectedCustomer!.phone}${_selectedCustomer!.email != null && _selectedCustomer!.email!.isNotEmpty ? " • ${_selectedCustomer!.email}" : ""}',
                          style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.tertiaryAmber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.star, size: 14, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          '${_selectedCustomer!.loyaltyPoints} Pts',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                    onPressed: () {
                      setState(() {
                        _selectedCustomer = null;
                        _customerNameController.clear();
                        _customerPhoneController.clear();
                        _customerEmailController.clear();
                      });
                    },
                  ),
                ],
              ),
            ),
          ] else ...[
            TextFormField(
              controller: _customerNameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Customer Full Name *', prefixIcon: Icon(Icons.person_outline)),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _customerPhoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone Number *', prefixIcon: Icon(Icons.phone_outlined)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFinancialSummaryCard(BuildContext context, String currency, bool isDark) {
    final List<Map<String, dynamic>> itemBreakdowns = [];
    double totalGross = 0.0;

    for (final line in _selectedLeaseItems) {
      final breakdown = RateCalculator.getReturnRentBreakdown(
        startTime: _startTime,
        actualReturnTime: _expectedEndTime,
        rateHourly: line.effectiveRateHourly,
        rateDaily: line.effectiveRateDaily,
        rateWeekly: line.effectiveRateWeekly,
        rateMonthly: line.effectiveRateMonthly,
      );

      final lineTotal = breakdown.totalRent * line.pieces;
      totalGross += lineTotal;

      String durationVal = breakdown.durationText;
      String rateVal = line.effectiveRateDaily.toStringAsFixed(2);
      String unitLabel = 'day';

      if (breakdown.days == 0 && breakdown.hours > 0 && line.effectiveRateHourly > 0) {
        durationVal = '${breakdown.hours}';
        rateVal = line.effectiveRateHourly.toStringAsFixed(2);
        unitLabel = 'hr';
      } else if (breakdown.days > 0) {
        durationVal = '${breakdown.days}';
        rateVal = line.effectiveRateDaily.toStringAsFixed(2);
        unitLabel = 'day';
      }

      final formulaStr = '${line.pieces} sets × ${breakdown.durationText} × $currency$rateVal/$unitLabel = $currency${lineTotal.toStringAsFixed(2)}';

      itemBreakdowns.add({
        'name': line.item.name,
        'quantity': line.pieces,
        'breakdown': breakdown,
        'lineTotal': lineTotal,
        'durationVal': durationVal,
        'rateVal': rateVal,
        'unitLabel': unitLabel,
        'formulaStr': formulaStr,
      });
    }

    final primaryItem = _selectedLeaseItems.firstOrNull?.item;
    final taxType = primaryItem?.taxType ?? 'No Tax';
    final taxRate = primaryItem?.taxRate ?? 0.0;
    final isInclusive = primaryItem?.isTaxInclusive ?? false;

    final double discountVal = double.tryParse(_discountController.text) ?? 0.0;
    final double discountedGross = (totalGross - discountVal) < 0 ? 0.0 : (totalGross - discountVal);

    double taxableSubtotal = discountedGross;
    double taxAmount = 0.0;
    double totalWithTax = discountedGross;

    if (taxType != 'No Tax' && taxRate > 0) {
      if (isInclusive) {
        taxableSubtotal = discountedGross / (1 + (taxRate / 100.0));
        taxAmount = discountedGross - taxableSubtotal;
        totalWithTax = discountedGross;
      } else {
        taxableSubtotal = discountedGross;
        taxAmount = discountedGross * (taxRate / 100.0);
        totalWithTax = discountedGross + taxAmount;
      }
    }

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
            children: [
              Icon(Icons.request_quote_outlined, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
              const SizedBox(width: 6),
              const Text('Estimated Rent & Price Breakdown', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),

          if (_selectedLeaseItems.isEmpty)
            Text(
              'Select equipment items above to calculate rent breakdown.',
              style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
            )
          else ...[
            ...itemBreakdowns.map((data) {
              final name = data['name'] as String;
              final qty = data['quantity'] as int;
              final b = data['breakdown'] as RentalBreakdown;
              final lineTotal = data['lineTotal'] as double;
              final durationVal = data['durationVal'] as String;
              final rateVal = data['rateVal'] as String;
              final unitLabel = data['unitLabel'] as String;
              final formulaStr = data['formulaStr'] as String;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurfaceLow : Colors.blue.shade50.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isDark ? AppColors.darkBorder : Colors.blue.shade100),
                ),
                child: Column(
                  children: [
                    // Item Card Header
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.desktop_windows_outlined, color: AppColors.primary, size: 24),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                Text('$qty sets × ${b.durationText}', style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                              ],
                            ),
                          ),
                          Text('$currency${lineTotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.primary)),
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_up, size: 18, color: Colors.grey),
                        ],
                      ),
                    ),

                    // Table Grid Container
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkCard : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isDark ? AppColors.darkBorder : Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          // Table Header
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkSurfaceLow : Colors.grey.shade50,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                            ),
                            child: Row(
                              children: [
                                const Expanded(flex: 3, child: Text('Item', style: TextStyle(fontSize: 11, color: AppColors.secondary))),
                                const Expanded(flex: 1, child: Text('Qty', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.secondary))),
                                const Expanded(flex: 1, child: Text('Time', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.secondary))),
                                Expanded(flex: 2, child: Text('Rate ($currency/$unitLabel)', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: AppColors.secondary))),
                                Expanded(flex: 2, child: Text('Amount ($currency)', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: AppColors.secondary))),
                              ],
                            ),
                          ),
                          const Divider(height: 1, thickness: 1),

                          // Table Row
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            child: Row(
                              children: [
                                Expanded(flex: 3, child: Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                                Expanded(flex: 1, child: Text('$qty', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
                                Expanded(flex: 1, child: Text(durationVal, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
                                Expanded(flex: 2, child: Text(rateVal, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
                                Expanded(flex: 2, child: Text(lineTotal.toStringAsFixed(2), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Green Calculation Box
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.all(8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF142E24) : const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Calculation:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryLight)),
                          const SizedBox(height: 2),
                          Text(formulaStr, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryLight)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 6),

            // Total Discount Input Field (Above Subtotal Text)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceLow : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? AppColors.darkBorder : Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_offer_outlined, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Text('Total Discount', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _discountController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      decoration: InputDecoration(
                        hintText: '0',
                        prefixText: '$currency ',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (_) {
                        setState(() {
                          _updateDepositIfFull();
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Subtotal Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Subtotal (Equipment Rent)', style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                Text('$currency${totalGross.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),

            // Discount Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Discount Applied', style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                Text('-$currency${discountVal.toStringAsFixed(2)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: discountVal > 0 ? AppColors.errorRed : (isDark ? Colors.white : Colors.black))),
              ],
            ),
            const SizedBox(height: 6),

            // Taxes Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Taxes (${taxRate.toInt()}%)', style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                Text('$currency${taxAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),

            // Total Estimated Rent Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF142E24) : const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Estimated Rent', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  Text('$currency${totalWithTax.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primaryLight)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConditionProofCard(BuildContext context, bool isDark) {
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
              const Row(
                children: [
                  Icon(Icons.photo_camera_outlined, size: 18, color: AppColors.primary),
                  SizedBox(width: 6),
                  Text('Condition Proof ("Before")', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.add_a_photo_outlined, color: AppColors.primary, size: 20),
                onPressed: _pickPhoto,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Horizontal list of taken photos + Add Photo button
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ..._beforePhotos.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final photoFile = entry.value;

                  return Container(
                    margin: const EdgeInsets.only(right: 10),
                    width: 80,
                    height: 80,
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            photoFile,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _beforePhotos.removeAt(idx);
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                if (_beforePhotos.length < 3)
                  InkWell(
                    onTap: _pickPhoto,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurfaceLow : Colors.blue.shade50.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? AppColors.darkBorder : Colors.blue.shade200,
                        ),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, color: AppColors.primary, size: 22),
                          SizedBox(height: 2),
                          Text('Add Photo', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showNoDepositWarningModal(BuildContext context, String currency) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.errorRed.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded, color: AppColors.errorRed, size: 32),
              ),
              const SizedBox(height: 16),
              const Text(
                'Zero Security Deposit Warning',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.errorRed),
              ),
              const SizedBox(height: 8),
              Text(
                'You are dispatching $totalPiecesLeased piece(s) requiring $currency${totalExpectedDeposit.toStringAsFixed(0)} deposit with ZERO upfront security deposit collected.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _onDepositTypeChanged('full');
                      },
                      child: const Text('Cancel & Collect Full'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.errorRed),
                      child: const Text('Confirm No Deposit'),
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

  Widget _buildUpfrontPaymentCard(BuildContext context, String currency, bool isDark) {
    final List<String> depositFormulas = [];
    for (final line in _selectedLeaseItems) {
      if (line.pieces > 0 && line.item.depositAmount > 0) {
        depositFormulas.add('${line.pieces}x ${line.item.name} @ $currency${line.item.depositAmount.toStringAsFixed(0)}/set');
      }
    }
    final depositCalcText = depositFormulas.isNotEmpty
        ? '${depositFormulas.join(' + ')} = $currency${totalExpectedDeposit.toStringAsFixed(0)}'
        : '$currency${totalExpectedDeposit.toStringAsFixed(0)}';

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
              Row(
                children: [
                  Icon(Icons.account_balance_wallet_outlined, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
                  const SizedBox(width: 6),
                  const Text('Upfront Deposit & Advance Rent', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Green Deposit Formula Box
          if (_selectedLeaseItems.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF142E24) : const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Deposit Calculation:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primaryLight)),
                  const SizedBox(height: 2),
                  Text(depositCalcText, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryLight)),
                ],
              ),
            ),

          // Option Choice Chips: Full Paid / Partial Paid / No Upfront
          Row(
            children: [
              _buildDepositChip('Full Paid', 'full', isDark, () {
                _onDepositTypeChanged('full');
              }),
              const SizedBox(width: 8),
              _buildDepositChip('Partial Paid', 'partial', isDark, () {
                _onDepositTypeChanged('partial');
              }),
              const SizedBox(width: 8),
              _buildDepositChip('No Upfront', 'none', isDark, () {
                _onDepositTypeChanged('none');
                _showNoDepositWarningModal(context, currency);
              }),
            ],
          ),
          const SizedBox(height: 12),

          // Side-by-side perfectly aligned Deposit Collected & Advance Rent fields
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _depositPaidController,
                  enabled: _depositPaymentType != 'none',
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Deposit Collected ($currency)',
                    prefixText: '$currency ',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _advanceRentController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Advance Rent ($currency)',
                    prefixText: '$currency ',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDepositChip(String label, String value, bool isDark, VoidCallback onTap) {
    final isSelected = _depositPaymentType == value;

    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87))),
      selected: isSelected,
      checkmarkColor: Colors.white,
      selectedColor: value == 'none' ? AppColors.errorRed : AppColors.primary,
      backgroundColor: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
      onSelected: (_) => onTap(),
    );
  }
}
