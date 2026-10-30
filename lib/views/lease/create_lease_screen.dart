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

  List<InventoryUnitModel> loadedUnits;
  List<InventoryUnitModel> selectedUnits;

  // Excluded Component Unit IDs per physical set unit ID
  Map<String, Set<String>> excludedComponentIdsMap;

  LeaseItemQuantity({
    required this.item,
    this.pieces = 1,
    List<InventoryUnitModel>? loadedUnits,
    List<InventoryUnitModel>? selectedUnits,
    Map<String, Set<String>>? excludedComponentIdsMap,
  })  : loadedUnits = loadedUnits ?? [],
        selectedUnits = selectedUnits ?? [],
        excludedComponentIdsMap = excludedComponentIdsMap ?? {};

  double get totalDailyRate => item.rateDaily * pieces;
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

  @override
  void initState() {
    super.initState();
    if (widget.preSelectedItem != null) {
      final line = LeaseItemQuantity(item: widget.preSelectedItem!, pieces: 1);
      _selectedLeaseItems.add(line);
      _loadUnitsForLine(line);
      _depositPaidController.text = totalExpectedDeposit.toStringAsFixed(0);
    }
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
          rateHourly: item.rateHourly,
          rateDaily: item.rateDaily,
          rateWeekly: item.rateWeekly,
          rateMonthly: item.rateMonthly,
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

      double taxableSubtotal = grossRent;
      double taxAmount = 0.0;
      double totalWithTax = grossRent;

      if (taxType != 'No Tax' && taxRate > 0) {
        if (isInclusive) {
          taxableSubtotal = double.parse((grossRent / (1 + (taxRate / 100.0))).toStringAsFixed(2));
          taxAmount = double.parse((grossRent - taxableSubtotal).toStringAsFixed(2));
          totalWithTax = grossRent;
        } else {
          taxableSubtotal = grossRent;
          taxAmount = double.parse((grossRent * (taxRate / 100.0)).toStringAsFixed(2));
          totalWithTax = double.parse((grossRent + taxAmount).toStringAsFixed(2));
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
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(line.item.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                Text(
                                  '${line.item.displaySku} • $currency${line.item.rateDaily.toStringAsFixed(0)}/day • Deposit: $currency${line.item.depositAmount.toStringAsFixed(0)}',
                                  style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, size: 20),
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
                                  });
                                  _validateConflict();
                                },
                              ),
                              Text('${line.pieces} Pcs', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline, size: 20),
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(4),
                                onPressed: () {
                                  setState(() {
                                    if (line.pieces < line.item.availableQuantity) {
                                      line.pieces++;
                                      final avail = line.loadedUnits.where((u) => u.isAvailable && !line.selectedUnits.contains(u)).firstOrNull;
                                      if (avail != null) line.selectedUnits.add(avail);
                                    }
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
                        const Text('Assigned Physical Units & Component Handover Toggles:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
                        const SizedBox(height: 6),
                        ...line.selectedUnits.map((unit) {
                          final excludedSet = line.excludedComponentIdsMap[unit.id] ?? {};

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkCard : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Physical Set (${unit.assetCode})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(4)),
                                      child: const Text('ASSIGNED', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),

                                ...unit.components.map((comp) {
                                  final isExcluded = excludedSet.contains(comp.id);

                                  return Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '• ${comp.componentName}${comp.serialNumber != null ? " [${comp.serialNumber}]" : ""}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          decoration: isExcluded ? TextDecoration.lineThrough : null,
                                          color: isExcluded ? Colors.grey : (isDark ? Colors.white : Colors.black),
                                        ),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            isExcluded ? 'Excluded' : 'Included',
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isExcluded ? Colors.grey : AppColors.primary),
                                          ),
                                          Switch(
                                            value: !isExcluded,
                                            activeColor: AppColors.primary,
                                            onChanged: (val) {
                                              setState(() {
                                                final set = line.excludedComponentIdsMap[unit.id] ?? {};
                                                if (val) {
                                                  set.remove(comp.id);
                                                } else {
                                                  set.add(comp.id);
                                                }
                                                line.excludedComponentIdsMap[unit.id] = set;
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                }),
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (modalCtx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select Equipment to Rent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final it = items[index];
                    return ListTile(
                      title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${it.displaySku} • Available: ${it.availableQuantity}/${it.totalQuantity}'),
                      trailing: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                      onTap: () {
                        setState(() {
                          final line = LeaseItemQuantity(item: it, pieces: 1);
                          _selectedLeaseItems.add(line);
                          _loadUnitsForLine(line);
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

  Widget _buildTimelineCard(BuildContext context, bool isDark) {
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
                  Icon(Icons.calendar_month, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
                  const SizedBox(width: 6),
                  const Text('Lease Schedule', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
              Text(_formatDuration(_expectedEndTime.difference(_startTime)), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _selectStartDateTime,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Start', style: TextStyle(fontSize: 10, color: AppColors.secondary)),
                      Text(DateFormat('dd MMM yyyy, hh:mm a').format(_startTime), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: _selectEndDateTime,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Expected Return', style: TextStyle(fontSize: 10, color: AppColors.secondary)),
                      Text(DateFormat('dd MMM yyyy, hh:mm a').format(_expectedEndTime), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerCard(BuildContext context, bool isDark, String currency) {
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
          const Text('Client Verification', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _customerNameController,
            decoration: const InputDecoration(labelText: 'Customer Full Name', prefixIcon: Icon(Icons.person_outline)),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _customerPhoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone_outlined)),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialSummaryCard(BuildContext context, String currency, bool isDark) {
    double totalGross = 0.0;
    for (final line in _selectedLeaseItems) {
      final itemRent = RateCalculator.calculateReturnRent(
        startTime: _startTime,
        actualReturnTime: _expectedEndTime,
        rateHourly: line.item.rateHourly,
        rateDaily: line.item.rateDaily,
        rateWeekly: line.item.rateWeekly,
        rateMonthly: line.item.rateMonthly,
      );
      totalGross += (itemRent * line.pieces);
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Estimated Rent Payable', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              Text('$currency${totalGross.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primary)),
            ],
          ),
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
              const Text('Condition Proof ("Before")', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.add_a_photo_outlined), onPressed: _pickPhoto),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUpfrontPaymentCard(BuildContext context, String currency, bool isDark) {
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
          const Text('Upfront Deposit Received', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _depositPaidController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Deposit ($currency)', prefixText: '$currency '),
          ),
        ],
      ),
    );
  }
}
