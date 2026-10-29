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
import '../../data/models/lease_item_model.dart';
import '../../data/models/lease_model.dart';
import '../../data/models/leased_sub_item_model.dart';
import '../../data/models/store_model.dart';
import '../../data/models/sub_item_model.dart';
import '../../data/repositories/sub_item_repository.dart';
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
  bool includeAllSubItems;
  List<SubItemModel> loadedSubItems;
  List<String> selectedSubItemIds;

  LeaseItemQuantity({
    required this.item,
    this.pieces = 1,
    this.includeAllSubItems = true,
    List<SubItemModel>? loadedSubItems,
    List<String>? selectedSubItemIds,
  })  : loadedSubItems = loadedSubItems ?? [],
        selectedSubItemIds = selectedSubItemIds ?? [];

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
      _loadSubItemsForLine(line);
      _depositPaidController.text = totalExpectedDeposit.toStringAsFixed(0);
    }
    _validateConflict();
    _retrieveLostData();
  }

  Future<void> _loadSubItemsForLine(LeaseItemQuantity line) async {
    try {
      final subItems = await SubItemRepository().getSubItems(parentItemId: line.item.id);
      if (mounted) {
        setState(() {
          line.loadedSubItems = subItems;
          line.selectedSubItemIds = subItems.where((s) => s.isAvailable).map((s) => s.id).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading sub-items for ${line.item.name}: $e');
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
          content: Text(
            'Maximum 3 condition proof photos.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
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
                const Text(
                  'Add Condition Proof Photo',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Material(
                  color: Colors.transparent,
                  child: ListTile(
                    leading: const Icon(Icons.camera_alt_outlined, color: AppColors.primary),
                    title: const Text('Take Photo with In-App Camera'),
                    subtitle: const Text('Fast, crash-proof live equipment capture'),
                    onTap: () => Navigator.pop(ctx, 'camera'),
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: ListTile(
                    leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
                    title: const Text('Choose from Gallery'),
                    subtitle: const Text('Select existing photo from device storage'),
                    onTap: () => Navigator.pop(ctx, 'gallery'),
                  ),
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

  Future<void> _replacePhoto(int index) async {
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
                const Text(
                  'Replace Condition Proof Photo',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Material(
                  color: Colors.transparent,
                  child: ListTile(
                    leading: const Icon(Icons.camera_alt_outlined, color: AppColors.primary),
                    title: const Text('Retake with In-App Camera'),
                    onTap: () => Navigator.pop(ctx, 'camera'),
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: ListTile(
                    leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
                    title: const Text('Choose from Gallery'),
                    onTap: () => Navigator.pop(ctx, 'gallery'),
                  ),
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
          _beforePhotos[index] = capturedFile;
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
            _beforePhotos[index] = File(picked.path);
          });
        }
      } catch (e) {
        debugPrint('Error replacing gallery photo: $e');
      }
    }
  }

  void _showEnlargedPhotoDialog(BuildContext context, File photoFile, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                  maxHeight: MediaQuery.of(context).size.height * 0.65,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.black,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: InteractiveViewer(
                    child: Image.file(photoFile, fit: BoxFit.contain),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Action Toolbar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.replay, color: AppColors.primary),
                      tooltip: 'Replace / Retake Photo',
                      onPressed: () {
                        Navigator.pop(dCtx);
                        _replacePhoto(index);
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      tooltip: 'Delete Photo',
                      onPressed: () {
                        Navigator.pop(dCtx);
                        setState(() {
                          _beforePhotos.removeAt(index);
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Close Preview',
                      onPressed: () => Navigator.pop(dCtx),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
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

  Future<bool> _showZeroDepositWarningConfirmationSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final confirm = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded, color: AppColors.tertiaryAmber, size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                'Confirm Lease Without Security Deposit?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppColors.lightOnSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Zero deposit is currently selected for this equipment rental. Are you sure you want to dispatch $totalPiecesLeased piece(s) without collecting an upfront security deposit?',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Yes, Confirm & Lease Without Deposit', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    side: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  ),
                  child: const Text('Cancel & Collect Deposit'),
                ),
              ),
            ],
          ),
        );
      },
    );

    return confirm ?? false;
  }

  void _handleDispatch() async {
    if (_selectedLeaseItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select at least one equipment item to rent out.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    if (_selectedCustomer == null &&
        (_customerNameController.text.trim().isEmpty || _customerPhoneController.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Customer name and phone number are required.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    if (_hasConflict) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'All units of one or more selected items are booked for the chosen timeline!',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    // Zero Deposit Warning Confirmation Check
    final depositPaidAmt = double.tryParse(_depositPaidController.text) ?? 0.0;
    if (_depositPaymentType == 'none' || depositPaidAmt <= 0) {
      final confirmed = await _showZeroDepositWarningConfirmationSheet();
      if (!confirmed) return;
    }

    if (!mounted) return;
    setState(() => _isSaving = true);

    try {
      final storeState = context.read<StoreCubit>().state;
      final store = storeState is StoreLoaded ? storeState.store : null;
      if (store == null) throw Exception('Store not initialized');

      // 1. Resolve or create/save customer to directory
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
          email: _customerEmailController.text.trim().isNotEmpty
              ? _customerEmailController.text.trim()
              : null,
          totalLeasesCount: 1,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await context.read<CustomerCubit>().saveCustomer(customer);
      }

      // 2. Upload condition photos to R2
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

      // Build Multi-Item Summary String for Notes/Receipt
      final itemsSummary = _selectedLeaseItems.map((li) => '${li.pieces}x ${li.item.name}').join(', ');
      final bool isFutureDate = _startTime.isAfter(DateTime.now().add(const Duration(hours: 4)));
      final initialStatus = isFutureDate ? 'reserved' : 'active';

      // 3. Create 1 Single Lease Order with all LeaseItemModel line items (locking base rates)
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

        List<String> finalSubItemIds = [];
        if (line.includeAllSubItems) {
          finalSubItemIds = line.loadedSubItems.map((s) => s.id).toList();
        } else {
          finalSubItemIds = line.selectedSubItemIds;
        }

        // Create LeasedSubItemModel instances
        final List<LeasedSubItemModel> lineLeasedSubItems = [];
        for (int sIdx = 0; sIdx < finalSubItemIds.length; sIdx++) {
          final subId = finalSubItemIds[sIdx];
          final matchingSub = line.loadedSubItems.where((s) => s.id == subId).firstOrNull;
          final subName = matchingSub?.name ?? '${item.name} Unit #${sIdx + 1}';
          final serial = matchingSub?.serialNumber;

          lineLeasedSubItems.add(LeasedSubItemModel(
            id: '${leaseId}_sub_${i + 1}_${sIdx + 1}',
            leaseId: leaseId,
            leaseItemId: '${leaseId}_item_${i + 1}',
            subItemId: subId,
            itemId: item.id,
            storeId: store.id,
            itemName: subName,
            serialNumber: serial,
            conditionStatus: 'available',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ));
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
          subItemIds: finalSubItemIds,
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

      // Reload inventory so available quantities for ALL items immediately update
      if (mounted) {
        context.read<InventoryCubit>().loadInventory();
      }

      // Generate Receipt PDF for 1 single lease order
      debugPrint('--> [CreateLease] BEFORE generateReceiptForLease. Lease ID: ${createdLease.id}, status: ${createdLease.status}, leaseItems count: ${createdLease.leaseItems.length}');
      debugPrint('--> [store] BEFORE generateReceiptForLease. ${store.toJson()} ');
      debugPrint('--> [createdLease] BEFORE generateReceiptForLease. ${createdLease.toJson()} ');
      final pdfFile = await PdfReceiptService.instance.generateReceiptForLease(
        store: store,
        lease: createdLease,
        multiItemLeases: [createdLease],
      );
      debugPrint('--> [CreateLease] AFTER generateReceiptForLease. PDF file path: ${pdfFile.path}, exists: ${pdfFile.existsSync()}');

      if (!mounted) return;

      // Show Success Bottom Sheet with Direct PDF Receipt Share
      _showDispatchSuccessSheet(store, createdLease, pdfFile);
    } catch (e) {
      if (!mounted) return;
      if (e.toString().contains('FREE_LEASE_LIMIT_REACHED')) {
        _showUpgradePaywallDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error dispatching lease: $e',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
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
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
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
              // WhatsApp Direct Action with PDF Receipt File
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
            // 1. Selected Asset Summary Tile
            _buildAssetSelectorCard(context, currency, isDark),
            const SizedBox(height: 16),

            // 2. Rental Timeline & Real-Time Conflict Validator
            _buildTimelineCard(context, isDark),
            const SizedBox(height: 16),

            // 3. Customer Profile & Auto-fill
            _buildCustomerCard(context, isDark, currency),
            const SizedBox(height: 16),

            // 4. Financial Summary & Tax Calculation Breakdown
            _buildFinancialSummaryCard(context, currency, isDark),
            const SizedBox(height: 16),

            // 5. Condition Proof ('Before' Intake Photos)
            _buildConditionProofCard(context, isDark),
            const SizedBox(height: 16),

            // 6. Upfront Deposit & Payment Collection
            _buildUpfrontPaymentCard(context, currency, isDark),
            const SizedBox(height: 24),

            // Primary Dispatch CTA
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
              Expanded(
                child: Text(
                  'Selected Equipment (${_selectedLeaseItems.length})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              TextButton(
                onPressed: () => _openItemSelectionModal(context),
                child: Text(
                  _selectedLeaseItems.isEmpty ? '+ Add Equipment' : '+ Add More',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.primaryLight : AppColors.primary,
                  ),
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
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkCard : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.handyman, size: 22, color: AppColors.primary),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  line.item.name,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${line.item.displaySku} • $currency${line.item.rateDaily.toStringAsFixed(0)}/day • Deposit: $currency${line.item.depositAmount.toStringAsFixed(0)}',
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Pieces Quantity Stepper
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
                                    } else {
                                      _selectedLeaseItems.removeAt(index);
                                    }
                                    if (_depositPaymentType == 'full') {
                                      _depositPaidController.text = totalExpectedDeposit.toStringAsFixed(0);
                                    }
                                  });
                                  _validateConflict();
                                },
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${line.pieces} Pcs',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline, size: 20),
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(4),
                                onPressed: () {
                                  setState(() {
                                    if (line.pieces < line.item.availableQuantity) {
                                      line.pieces++;
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Only ${line.item.availableQuantity} pieces available in depot.')),
                                      );
                                    }
                                    if (_depositPaymentType == 'full') {
                                      _depositPaidController.text = totalExpectedDeposit.toStringAsFixed(0);
                                    }
                                  });
                                  _validateConflict();
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Checkbox for Include all sub-items
                      Row(
                        children: [
                          Checkbox(
                            value: line.includeAllSubItems,
                            activeColor: AppColors.primary,
                            onChanged: (val) {
                              setState(() {
                                line.includeAllSubItems = val ?? true;
                              });
                            },
                          ),
                          const Text('Include all sub-items (Checked by default)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),

                      // Manual sub-items unit selector if includeAllSubItems == false
                      if (!line.includeAllSubItems && line.loadedSubItems.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkCard : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Select Specific Available Units:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary)),
                              const SizedBox(height: 4),
                              ...line.loadedSubItems.where((s) => s.isAvailable).map((sub) {
                                final isSubSelected = line.selectedSubItemIds.contains(sub.id);
                                return Material(
                                  color: Colors.transparent,
                                  child: CheckboxListTile(
                                    value: isSubSelected,
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    activeColor: AppColors.primary,
                                    title: Text(sub.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    subtitle: Text(sub.serialNumber != null ? 'SN: ${sub.serialNumber}' : sub.displaySku, style: const TextStyle(fontSize: 9)),
                                    onChanged: (check) {
                                      setState(() {
                                        if (check == true) {
                                          line.selectedSubItemIds.add(sub.id);
                                        } else {
                                          line.selectedSubItemIds.remove(sub.id);
                                        }
                                      });
                                    },
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total $totalPiecesLeased Piece(s)',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Total Deposit: $currency${totalExpectedDeposit.toStringAsFixed(0)}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? AppColors.primaryLight : AppColors.primary),
                  ),
                ],
              ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inventoryState = context.read<InventoryCubit>().state;
    final items = inventoryState is InventoryLoaded ? inventoryState.allItems : <InventoryItemModel>[];
    final storeState = context.read<StoreCubit>().state;
    final currency = storeState is StoreLoaded ? storeState.store.currencySymbol : '₹';

    String searchQuery = '';

    final Map<String, int> modalPiecesMap = {};
    for (final line in _selectedLeaseItems) {
      modalPiecesMap[line.item.id] = line.pieces;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final filteredItems = items.where((it) {
              if (searchQuery.trim().isEmpty) return true;
              final q = searchQuery.toLowerCase().trim();
              return it.name.toLowerCase().contains(q) ||
                  it.displaySku.toLowerCase().contains(q) ||
                  it.category.toLowerCase().contains(q);
            }).toList();

            final selectedCount = modalPiecesMap.values.where((v) => v > 0).length;

            return Container(
              height: MediaQuery.of(context).size.height * 0.82,
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
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
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.handyman_outlined, color: AppColors.primary, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Select Equipment Items',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'Select items and piece quantities',
                                    style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$selectedCount Selected',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    onChanged: (val) {
                      setModalState(() {
                        searchQuery = val;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search by item name, SKU, or scan barcode...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.qr_code_scanner, color: AppColors.primary),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Barcode & QR Scanner ready. Place barcode in view.',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                              backgroundColor: AppColors.primary,
                            ),
                          );
                        },
                        tooltip: 'Scan Barcode / QR',
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 14),

                  Expanded(
                    child: filteredItems.isEmpty
                        ? Center(
                            child: Text(
                              'No inventory items found.',
                              style: TextStyle(color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filteredItems.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final it = filteredItems[index];
                              final currentPcs = modalPiecesMap[it.id] ?? 0;
                              final isSelected = currentPcs > 0;
                              final available = it.availableQuantity;

                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? (isDark ? AppColors.primaryLight.withValues(alpha: 0.12) : AppColors.primary.withValues(alpha: 0.06))
                                      : (isDark ? AppColors.darkCard : Colors.white),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected ? AppColors.primary : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                                    width: isSelected ? 1.5 : 1.0,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: isSelected,
                                      activeColor: AppColors.primary,
                                      onChanged: (val) {
                                        setModalState(() {
                                          if (val == true) {
                                            modalPiecesMap[it.id] = 1;
                                          } else {
                                            modalPiecesMap.remove(it.id);
                                          }
                                        });
                                      },
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                it.displaySku,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: isDark ? AppColors.primaryLight : AppColors.primary,
                                                ),
                                              ),
                                              Text(
                                                '$available/${it.totalQuantity} Available',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: available > 0 ? AppColors.primaryLight : AppColors.errorRed,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            it.name,
                                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                          ),
                                          Text(
                                            '$currency${it.rateDaily.toStringAsFixed(0)}/day • Deposit: $currency${it.depositAmount.toStringAsFixed(0)}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    if (isSelected) ...[
                                      const SizedBox(width: 8),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.remove_circle, color: AppColors.primary, size: 22),
                                            constraints: const BoxConstraints(),
                                            padding: const EdgeInsets.all(4),
                                            onPressed: () {
                                              setModalState(() {
                                                if (currentPcs > 1) {
                                                  modalPiecesMap[it.id] = currentPcs - 1;
                                                } else {
                                                  modalPiecesMap.remove(it.id);
                                                }
                                              });
                                            },
                                          ),
                                          Text(
                                            '$currentPcs Pcs',
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.add_circle, color: AppColors.primary, size: 22),
                                            constraints: const BoxConstraints(),
                                            padding: const EdgeInsets.all(4),
                                            onPressed: () {
                                              if (currentPcs < available) {
                                                setModalState(() {
                                                  modalPiecesMap[it.id] = currentPcs + 1;
                                                });
                                              } else {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(content: Text('Max $available pieces available in depot.')),
                                                );
                                              }
                                            },
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

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _selectedLeaseItems.clear();
                          modalPiecesMap.forEach((id, pcs) {
                            if (pcs > 0) {
                              final item = items.where((i) => i.id == id).firstOrNull;
                              if (item != null) {
                                final line = LeaseItemQuantity(item: item, pieces: pcs);
                                _selectedLeaseItems.add(line);
                                _loadSubItemsForLine(line);
                              }
                            }
                          });

                          if (_depositPaymentType == 'full') {
                            _depositPaidController.text = totalExpectedDeposit.toStringAsFixed(0);
                          }
                        });
                        Navigator.pop(modalCtx);
                        _validateConflict();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        'Confirm $selectedCount Selected Item(s)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
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
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.calendar_month, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Lease Schedule',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  durationText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _selectStartDateTime,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Start & Handover', style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                        const SizedBox(height: 2),
                        Text(DateFormat('dd MMM yyyy').format(_startTime), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        Row(
                          children: [
                            Text(DateFormat('hh:mm a').format(_startTime), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? AppColors.primaryLight : AppColors.primary)),
                            const SizedBox(width: 4),
                            Icon(Icons.edit, size: 12, color: isDark ? AppColors.primaryLight : AppColors.primary),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: _selectEndDateTime,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Expected Return', style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary)),
                        const SizedBox(height: 2),
                        Text(DateFormat('dd MMM yyyy').format(_expectedEndTime), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        Row(
                          children: [
                            Text(DateFormat('hh:mm a').format(_expectedEndTime), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.tertiaryAmber)),
                            const SizedBox(width: 4),
                            const Icon(Icons.edit, size: 12, color: AppColors.tertiaryAmber),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _hasConflict
                  ? (isDark ? const Color(0xFF3B1515) : const Color(0xFFFFDAD6))
                  : (isDark ? const Color(0xFF142E24) : const Color(0xFFECFDF5)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  _hasConflict ? Icons.error_outline : Icons.verified,
                  size: 16,
                  color: _hasConflict ? AppColors.errorRed : AppColors.primaryLight,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _hasConflict
                        ? 'Booking Conflict: All units booked for this time window.'
                        : 'Inventory Verified: Zero booking conflict in depot.',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _hasConflict ? AppColors.errorRed : (isDark ? AppColors.primaryLight : AppColors.primary),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.person_pin, size: 18, color: isDark ? AppColors.darkOnSurface : AppColors.slateNavy),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Client Verification',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _openRepeatCustomerModal(context),
                child: Text(
                  'Select Repeat Client',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.primaryLight : AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          if (_selectedCustomer != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.primary,
                    child: Icon(Icons.person, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(_selectedCustomer!.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(width: 6),
                            if (_selectedCustomer!.isRepeatCustomer)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryFixed,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Repeat Client',
                                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: AppColors.onPrimaryFixed),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_selectedCustomer!.phone} • ${_selectedCustomer!.totalLeasesCount} Prior Leases',
                          style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '🪙 ${_selectedCustomer!.loyaltyPoints} Pts ($currency${_selectedCustomer!.loyaltyMonetaryValue.toStringAsFixed(2)})',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      setState(() {
                        _selectedCustomer = null;
                        _customerNameController.clear();
                        _customerPhoneController.clear();
                        _customerEmailController.clear();
                      });
                    },
                    tooltip: 'Unselect Client',
                  ),
                ],
              ),
            ),
          ] else ...[
            TextFormField(
              controller: _customerNameController,
              decoration: const InputDecoration(
                labelText: 'Customer Full Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _customerPhoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone Number (for WhatsApp Receipt)',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFinancialSummaryCard(BuildContext context, String currency, bool isDark) {
    double totalGrossRent = 0.0;

    for (final line in _selectedLeaseItems) {
      final itemRent = RateCalculator.calculateReturnRent(
        startTime: _startTime,
        actualReturnTime: _expectedEndTime,
        rateHourly: line.item.rateHourly,
        rateDaily: line.item.rateDaily,
        rateWeekly: line.item.rateWeekly,
        rateMonthly: line.item.rateMonthly,
      );
      totalGrossRent += (itemRent * line.pieces);
    }

    final primaryItem = _selectedLeaseItems.isNotEmpty ? _selectedLeaseItems.first.item : null;
    final taxType = primaryItem?.taxType ?? 'No Tax';
    final taxRate = primaryItem?.taxRate ?? 0.0;
    final isInclusive = primaryItem?.isTaxInclusive ?? false;

    double taxableSubtotal = totalGrossRent;
    double taxAmount = 0.0;
    double totalWithTax = totalGrossRent;

    if (taxType != 'No Tax' && taxRate > 0) {
      if (isInclusive) {
        taxableSubtotal = double.parse((totalGrossRent / (1 + (taxRate / 100.0))).toStringAsFixed(2));
        taxAmount = double.parse((totalGrossRent - taxableSubtotal).toStringAsFixed(2));
        totalWithTax = totalGrossRent;
      } else {
        taxableSubtotal = totalGrossRent;
        taxAmount = double.parse((totalGrossRent * (taxRate / 100.0)).toStringAsFixed(2));
        totalWithTax = double.parse((totalGrossRent + taxAmount).toStringAsFixed(2));
      }
    }

    final advanceRentPaid = double.tryParse(_advanceRentController.text) ?? 0.0;
    final estimatedRentBalance = (totalWithTax - advanceRentPaid) < 0
        ? 0.0
        : (totalWithTax - advanceRentPaid);

    final depositPaid = double.tryParse(_depositPaidController.text) ?? 0.0;
    final depositOutstanding = (totalExpectedDeposit - depositPaid) < 0
        ? 0.0
        : (totalExpectedDeposit - depositPaid);

    final duration = _expectedEndTime.difference(_startTime);
    final breakdownText = _formatDuration(duration);

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
                child: Row(
                  children: [
                    Icon(Icons.account_balance_wallet_outlined, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Financial Summary & Taxes',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Duration: $breakdownText',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                      ),
                      child: Text(
                        'Rental Estimate & Equipment Breakdown',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurface : AppColors.slateNavy),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_selectedLeaseItems.isNotEmpty) ...[
                            ..._selectedLeaseItems.map((line) {
                              final lineRent = RateCalculator.calculateReturnRent(
                                startTime: _startTime,
                                actualReturnTime: _expectedEndTime,
                                rateHourly: line.item.rateHourly,
                                rateDaily: line.item.rateDaily,
                                rateWeekly: line.item.rateWeekly,
                                rateMonthly: line.item.rateMonthly,
                              );
                              final totalLineRent = lineRent * line.pieces;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${line.pieces}x ${line.item.name} (${line.pieces} Pcs)',
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            '${line.pieces} Pcs × $currency${lineRent.toStringAsFixed(2)}/unit',
                                            style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '$currency${totalLineRent.toStringAsFixed(2)}',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            Divider(height: 1, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                            const SizedBox(height: 6),
                          ],

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: Text('Rental Subtotal', style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary))),
                              Text('$currency${taxableSubtotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          if (taxType != 'No Tax' && taxRate > 0) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '$taxType (${taxRate.toStringAsFixed(1)}% ${isInclusive ? 'Incl' : 'Excl'})',
                                    style: TextStyle(fontSize: 10, color: isDark ? AppColors.primaryLight : AppColors.primary, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Text('$currency${taxAmount.toStringAsFixed(2)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? AppColors.primaryLight : AppColors.primary)),
                              ],
                            ),
                          ],
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: Text('Advance Rent Received (-)', style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary))),
                              Text('-$currency${advanceRentPaid.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Divider(height: 1, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: Text('Total Rent Payable', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? AppColors.primaryLight : AppColors.primary))),
                              Text('$currency${estimatedRentBalance.toStringAsFixed(2)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? AppColors.primaryLight : AppColors.primary)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                      ),
                      child: Text(
                        'Security Deposit Summary',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurface : AppColors.slateNavy),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: Text('Deposit Required', style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary))),
                              Text('$currency${totalExpectedDeposit.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: Text('Deposit Received', style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary))),
                              Text('$currency${depositPaid.toStringAsFixed(2)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryLight)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Divider(height: 1, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: Text('Deposit Outstanding', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurface : AppColors.slateNavy))),
                              Text('$currency${depositOutstanding.toStringAsFixed(2)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurface : AppColors.slateNavy)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openRepeatCustomerModal(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customerState = context.read<CustomerCubit>().state;
    final customers = customerState is CustomerLoaded ? customerState.allCustomers : <CustomerModel>[];
    final storeState = context.read<StoreCubit>().state;
    final currency = storeState is StoreLoaded ? storeState.store.currencySymbol : '₹';

    String searchQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final filteredCustomers = customers.where((c) {
              if (searchQuery.trim().isEmpty) return true;
              final q = searchQuery.toLowerCase().trim();
              return c.name.toLowerCase().contains(q) ||
                  c.phone.contains(q) ||
                  (c.email != null && c.email!.toLowerCase().contains(q));
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
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
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                        child: const Icon(Icons.person, color: AppColors.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Select Saved Client',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Auto-fill client details from customer directory',
                              style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    onChanged: (val) {
                      setModalState(() {
                        searchQuery = val;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search client by name, phone, or scan ID...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.qr_code_scanner, color: AppColors.primary),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Client ID Scanner ready.',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                              backgroundColor: AppColors.primary,
                            ),
                          );
                        },
                        tooltip: 'Scan Client ID / Barcode',
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 14),

                  Expanded(
                    child: filteredCustomers.isEmpty
                        ? Center(
                            child: Text(
                              'No saved customers found.',
                              style: TextStyle(color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filteredCustomers.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final c = filteredCustomers[index];

                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedCustomer = c;
                                    _customerNameController.text = c.name;
                                    _customerPhoneController.text = c.phone;
                                    _customerEmailController.text = c.email ?? '';
                                  });
                                  Navigator.pop(modalCtx);
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isDark ? AppColors.darkCard : Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 20,
                                        backgroundColor: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceContainer,
                                        child: const Icon(Icons.person, color: AppColors.primary, size: 22),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    c.name,
                                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (c.isRepeatCustomer)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.primaryFixed,
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: const Text(
                                                      'REPEAT',
                                                      style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: AppColors.onPrimaryFixed),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Phone: ${c.phone} • Leases: ${c.totalLeasesCount}',
                                              style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                            ),
                                            if (c.loyaltyPoints > 0) ...[
                                              const SizedBox(height: 3),
                                              Text(
                                                '🪙 ${c.loyaltyPoints} Pts ($currency${c.loyaltyMonetaryValue.toStringAsFixed(2)})',
                                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
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
      },
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
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.camera_indoor_outlined, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Condition Proof ("Before")',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_beforePhotos.length}/3 Snapped',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.primaryLight : AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Pre-dispatch visual inspection timestamp for damage protection.',
            style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ..._beforePhotos.asMap().entries.map(
                (entry) {
                  final index = entry.key;
                  final file = entry.value;

                  return Container(
                    width: 68,
                    height: 68,
                    margin: const EdgeInsets.only(right: 10),
                    child: Stack(
                      children: [
                        InkWell(
                          onTap: () => _showEnlargedPhotoDialog(context, file, index),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.file(file, fit: BoxFit.cover),
                            ),
                          ),
                        ),

                        Positioned(
                          top: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _beforePhotos.removeAt(index);
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                              ),
                              child: const Icon(Icons.close, size: 12, color: Colors.white),
                            ),
                          ),
                        ),

                        Positioned(
                          bottom: 6,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(Icons.zoom_in, size: 10, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              if (_beforePhotos.length < 3)
                InkWell(
                  onTap: _pickPhoto,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_outlined, size: 20, color: isDark ? AppColors.primaryLight : AppColors.primary),
                        const SizedBox(height: 2),
                        const Text('+ Photo', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
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

  Widget _buildUpfrontPaymentCard(BuildContext context, String currency, bool isDark) {
    final expectedDeposit = totalExpectedDeposit;

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
                child: Row(
                  children: [
                    Icon(Icons.payments_outlined, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Deposit & Handover',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Expected: $currency${expectedDeposit.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.tertiaryAmber),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildDepositToggleOption('Full Deposit', 'full'),
              const SizedBox(width: 8),
              _buildDepositToggleOption('Partial Deposit', 'partial'),
              const SizedBox(width: 8),
              _buildDepositToggleOption('Zero Deposit', 'none'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _depositPaidController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Deposit Amount Paid ($currency)',
                    prefixText: '$currency ',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _advanceRentController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Advance Rent ($currency)',
                    prefixText: '$currency ',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDepositToggleOption(String label, String value) {
    final isSelected = _depositPaymentType == value;
    return Expanded(
      child: InkWell(
        onTap: () => _onDepositTypeChanged(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? AppColors.primary : AppColors.lightBorder),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : AppColors.secondary,
            ),
          ),
        ),
      ),
    );
  }
}
