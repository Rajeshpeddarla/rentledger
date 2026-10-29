import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/app_theme.dart';
import '../../core/services/r2_storage_service.dart';
import '../../core/utils/rate_calculator.dart';
import '../../core/utils/uuid_generator.dart';
import '../../core/widgets/app_image_view.dart';
import '../../data/models/inventory_item_model.dart';
import '../../data/models/store_model.dart';
import '../../data/models/sub_item_model.dart';
import '../../data/repositories/sub_item_repository.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../../viewmodels/category/category_cubit.dart';
import '../../viewmodels/category/category_state.dart';
import '../../viewmodels/inventory/inventory_cubit.dart';
import '../profile/category_list_screen.dart';
import '../profile/subscription_paywall_screen.dart';

class SubItemInput {
  final TextEditingController nameCtrl;
  final TextEditingController serialCtrl;

  SubItemInput({String name = '', String serial = ''})
      : nameCtrl = TextEditingController(text: name),
        serialCtrl = TextEditingController(text: serial);

  void dispose() {
    nameCtrl.dispose();
    serialCtrl.dispose();
  }
}

class AddEditItemScreen extends StatefulWidget {
  final InventoryItemModel? initialItem;
  final bool isPro;

  const AddEditItemScreen({super.key, this.initialItem, required this.isPro});

  @override
  State<AddEditItemScreen> createState() => _AddEditItemScreenState();
}

class _AddEditItemScreenState extends State<AddEditItemScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  late final TextEditingController _skuController;
  late final TextEditingController _quantityController;
  late final TextEditingController _depositController;

  late final TextEditingController _hourlyController;
  late final TextEditingController _dailyController;
  late final TextEditingController _weeklyController;
  late final TextEditingController _monthlyController;

  // Equipment Tax Configuration Fields
  String _taxType = 'No Tax';
  late final TextEditingController _taxRateController;
  bool _isTaxInclusive = false;
  bool _isTaxConfirmed = true;

  // Sub-Items list controller
  final List<SubItemInput> _subItemInputs = [];

  String _selectedCategory = 'Cameras';
  bool _isCategoryDropdownExpanded = false;

  File? _pickedImage;
  String? _imageUrl;
  bool _isUploading = false;
  bool _isSaving = false;

  // Manual override tracking flags
  bool _isWeeklyManuallyEdited = false;
  bool _isMonthlyManuallyEdited = false;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;

    _nameController = TextEditingController(text: item?.name ?? '');
    _descController = TextEditingController(text: item?.description ?? '');
    _skuController = TextEditingController(text: item?.sku ?? '');
    _quantityController = TextEditingController(text: '${item?.totalQuantity ?? 1}');
    _depositController = TextEditingController(text: item != null ? '${item.depositAmount.toInt()}' : '2500');

    _hourlyController = TextEditingController(text: item != null ? '${item.rateHourly.toInt()}' : '150');
    _dailyController = TextEditingController(text: item != null ? '${item.rateDaily.toInt()}' : '1200');
    _weeklyController = TextEditingController(text: item != null ? '${item.rateWeekly.toInt()}' : '7200');
    _monthlyController = TextEditingController(text: item != null ? '${item.rateMonthly.toInt()}' : '26400');

    _taxType = item?.taxType ?? 'No Tax';
    _taxRateController = TextEditingController(text: item != null ? item.taxRate.toStringAsFixed(1) : '0.0');
    _isTaxInclusive = item?.isTaxInclusive ?? false;
    _isTaxConfirmed = item?.isTaxConfirmed ?? true;

    _selectedCategory = item?.category ?? 'Cameras';
    final initialImg = item?.imageR2Url;
    if (initialImg != null && !initialImg.startsWith('http')) {
      final f = File(initialImg);
      _imageUrl = f.existsSync() ? initialImg : null;
    } else {
      _imageUrl = initialImg;
    }

    if (item != null) {
      _isWeeklyManuallyEdited = true;
      _isMonthlyManuallyEdited = true;

      // Load existing sub-items
      SubItemRepository().getSubItems(parentItemId: item.id).then((subItems) {
        if (mounted && subItems.isNotEmpty) {
          setState(() {
            _subItemInputs.clear();
            for (final s in subItems) {
              _subItemInputs.add(SubItemInput(name: s.name, serial: s.serialNumber ?? ''));
            }
          });
        }
      });
    }

    context.read<CategoryCubit>().loadCategories();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _skuController.dispose();
    _quantityController.dispose();
    _depositController.dispose();
    _hourlyController.dispose();
    _dailyController.dispose();
    _weeklyController.dispose();
    _monthlyController.dispose();
    _taxRateController.dispose();
    for (final input in _subItemInputs) {
      input.dispose();
    }
    super.dispose();
  }

  String _getOfficialTaxGuidanceUrl(String country) {
    switch (country.toLowerCase()) {
      case 'india':
        return 'https://cbic-gst.gov.in/hindi/gst-goods-services-rates.html';
      case 'united kingdom':
        return 'https://www.gov.uk/vat-rates';
      case 'australia':
        return 'https://www.ato.gov.au/businesses-and-organisations/gst-excise-and-indirect-taxes/gst';
      case 'united states':
        return 'https://www.taxjar.com/sales-tax';
      case 'canada':
        return 'https://www.canada.ca/en/revenue-agency/services/tax/businesses/topics/gst-hst-businesses/charge-collect-which-rate.html';
      default:
        return 'https://www.google.com/search?q=equipment+rental+tax+rate+$country';
    }
  }

  void _onHourlyChanged(String val) {
    final hourly = double.tryParse(val);
    if (hourly != null && hourly > 0) {
      final storeState = context.read<StoreCubit>().state;
      final store = storeState is StoreLoaded ? storeState.store : null;
      final workingHours = store != null ? (store.dailyWorkingHours <= 0 ? 8.0 : store.dailyWorkingHours.toDouble()) : 8.0;
      final daysPerWeek = store?.daysPerWeek ?? 6;
      final daysPerMonth = store?.effectiveDaysPerMonth ?? (store?.enableWeekendLease == true ? 28 : 24);

      final suggested = RateCalculator.suggestRates(
        hourly: hourly,
        workingHours: workingHours,
        daysPerWeek: daysPerWeek,
        daysPerMonth: daysPerMonth,
      );
      _dailyController.text = suggested['daily']!.toStringAsFixed(0);

      if (!_isWeeklyManuallyEdited) {
        _weeklyController.text = suggested['weekly']!.toStringAsFixed(0);
      }
      if (!_isMonthlyManuallyEdited) {
        _monthlyController.text = suggested['monthly']!.toStringAsFixed(0);
      }
    }
  }

  void _onDailyChanged(String val) {
    final daily = double.tryParse(val);
    if (daily != null && daily > 0) {
      final storeState = context.read<StoreCubit>().state;
      final store = storeState is StoreLoaded ? storeState.store : null;
      final workingHours = store != null ? (store.dailyWorkingHours <= 0 ? 8.0 : store.dailyWorkingHours.toDouble()) : 8.0;
      final daysPerWeek = store?.daysPerWeek ?? 6;
      final daysPerMonth = store?.effectiveDaysPerMonth ?? (store?.enableWeekendLease == true ? 28 : 24);

      final suggested = RateCalculator.suggestRates(
        daily: daily,
        workingHours: workingHours,
        daysPerWeek: daysPerWeek,
        daysPerMonth: daysPerMonth,
      );
      _hourlyController.text = suggested['hourly']!.toStringAsFixed(0);

      if (!_isWeeklyManuallyEdited) {
        _weeklyController.text = suggested['weekly']!.toStringAsFixed(0);
      }
      if (!_isMonthlyManuallyEdited) {
        _monthlyController.text = suggested['monthly']!.toStringAsFixed(0);
      }
    }
  }

  void _openRateConfigModal(BuildContext context, StoreModel? store) {
    if (store == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    int hours = store.dailyWorkingHours <= 0 ? 8 : store.dailyWorkingHours;
    bool enableSundays = store.enableWeekendLease;
    int monthDays = store.effectiveDaysPerMonth;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
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
                  Row(
                    children: [
                      Icon(Icons.tune, color: isDark ? AppColors.primaryLight : AppColors.primary),
                      const SizedBox(width: 10),
                      const Text('Rate Calculator Rules', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Customize daily shift hours, Sunday/weekend rules, and monthly days multiplier for rate calculations.',
                    style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                  ),
                  const SizedBox(height: 20),

                  // 1. Daily Shift Hours
                  Text('Daily Working Shift Length', style: Theme.of(ctx).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [8, 10, 12, 24].map((h) {
                      final isSelected = hours == h;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setModalState(() => hours = h),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.primary : (isDark ? AppColors.darkSurfaceLow : Colors.grey.shade100),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: isSelected ? AppColors.primary : (isDark ? AppColors.darkBorder : AppColors.lightBorder)),
                            ),
                            child: Text(
                              '${h}h Shift',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87)),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 16),

                  // 2. Include Sundays/Weekends Switch
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: SwitchListTile(
                        value: enableSundays,
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: AppColors.primary,
                        title: const Text('Include Sundays / Weekends in Weekly Rate', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          enableSundays ? '1 Week = 7 Rental Days (Includes Sundays)' : '1 Week = 6 Rental Days (Excludes Sundays)',
                          style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                        ),
                        onChanged: (val) {
                          setModalState(() => enableSundays = val);
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 3. Days per Month
                  Text('Days Per Monthly Lease', style: Theme.of(ctx).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [22, 28, 30].map((d) {
                      final isSelected = monthDays == d;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setModalState(() => monthDays = d),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.primary : (isDark ? AppColors.darkSurfaceLow : Colors.grey.shade100),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: isSelected ? AppColors.primary : (isDark ? AppColors.darkBorder : AppColors.lightBorder)),
                            ),
                            child: Text(
                              '$d Days',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87)),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final updatedStore = store.copyWith(
                          dailyWorkingHours: hours,
                          enableWeekendLease: enableSundays,
                          daysPerMonth: monthDays,
                          updatedAt: DateTime.now(),
                        );
                        await context.read<StoreCubit>().updateStore(updatedStore);
                        if (!modalCtx.mounted) return;
                        Navigator.pop(modalCtx);
                        if (_hourlyController.text.isNotEmpty) {
                          _onHourlyChanged(_hourlyController.text);
                        } else if (_dailyController.text.isNotEmpty) {
                          _onDailyChanged(_dailyController.text);
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 12)),
                      child: const Text('Save & Apply Rate Rules', style: TextStyle(fontWeight: FontWeight.bold)),
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

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80,
      );
      if (picked != null) {
        setState(() {
          _pickedImage = File(picked.path);
        });
      }
    } catch (e) {
      debugPrint('Image picker error: $e');
    }
  }

  void _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final inventoryCubit = context.read<InventoryCubit>();
    final storeCubit = context.read<StoreCubit>();

    try {
      if (_pickedImage != null) {
        setState(() => _isUploading = true);
        final filename = '${DateTime.now().millisecondsSinceEpoch}_item.webp';
        final uploadedUrl = await R2StorageService.instance.uploadImage(
          file: _pickedImage!,
          folder: 'items',
          filename: filename,
        );
        if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
          _imageUrl = uploadedUrl;
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⚠️ Photo upload to Cloudflare R2 failed. Item saved without cloud image.'),
                backgroundColor: AppColors.errorRed,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }

      final storeState = storeCubit.state;
      final storeId = storeState is StoreLoaded ? storeState.store.id : 'demo_store_1';
      final itemId = widget.initialItem?.id ?? UuidGenerator.generateV4();

      final item = InventoryItemModel(
        id: itemId,
        storeId: storeId,
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        sku: _skuController.text.trim().isNotEmpty
            ? _skuController.text.trim().toUpperCase()
            : 'SKU-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
        category: _selectedCategory,
        totalQuantity: int.tryParse(_quantityController.text) ?? 1,
        depositAmount: double.tryParse(_depositController.text) ?? 0.0,
        rateHourly: double.tryParse(_hourlyController.text) ?? 0.0,
        rateDaily: double.tryParse(_dailyController.text) ?? 0.0,
        rateWeekly: double.tryParse(_weeklyController.text) ?? 0.0,
        rateMonthly: double.tryParse(_monthlyController.text) ?? 0.0,
        imageR2Url: _imageUrl,
        taxType: _taxType,
        taxRate: _taxType == 'No Tax' ? 0.0 : (double.tryParse(_taxRateController.text) ?? 0.0),
        isTaxInclusive: _isTaxInclusive,
        taxEffectiveDate: widget.initialItem?.taxEffectiveDate ?? DateTime.now(),
        taxLastVerifiedDate: DateTime.now(),
        isTaxConfirmed: _isTaxConfirmed,
        createdAt: widget.initialItem?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await inventoryCubit.saveItem(item, isPro: widget.isPro);

      // Save Sub-Items / Serial Numbers (with auto-generated serials if empty)
      final subItemRepo = SubItemRepository();
      for (int i = 0; i < _subItemInputs.length; i++) {
        final input = _subItemInputs[i];
        final subName = input.nameCtrl.text.trim().isNotEmpty
            ? input.nameCtrl.text.trim()
            : '${_nameController.text.trim()} #${i + 1}';

        final autoSerial = 'SN-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}-${i + 1}';
        final subSerial = input.serialCtrl.text.trim().isNotEmpty
            ? input.serialCtrl.text.trim()
            : autoSerial;

        final subItem = SubItemModel(
          id: '${itemId}_sub_${i + 1}',
          parentItemId: itemId,
          storeId: storeId,
          name: subName,
          serialNumber: subSerial,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await subItemRepo.saveSubItem(subItem);
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.initialItem == null ? 'Equipment added to fleet!' : 'Item updated successfully!',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (e.toString().contains('FREE_ITEM_LIMIT_REACHED')) {
        _showUpgradePaywallDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error saving item: $e',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            backgroundColor: AppColors.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isUploading = false;
        });
      }
    }
  }

  void _showUpgradePaywallDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Free Tier Fleet Limit Reached'),
        content: const Text(
          'Free tier is limited to 10 fleet items. Upgrade to Pro for unlimited inventory management.',
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final storeState = context.watch<StoreCubit>().state;
    final store = storeState is StoreLoaded ? storeState.store : null;
    final currency = store?.currencySymbol ?? '₹';
    final country = store?.country ?? 'India';

    final workingHours = store != null ? (store.dailyWorkingHours <= 0 ? 8 : store.dailyWorkingHours) : 8;
    final daysPerWeek = store?.daysPerWeek ?? 6;
    final daysPerMonth = store?.effectiveDaysPerMonth ?? (store?.enableWeekendLease == true ? 28 : 24);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: Text(widget.initialItem == null ? 'Add Inventory Item' : 'Edit Equipment Item'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo Picker Card
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    width: double.infinity,
                    height: 140,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCard : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: _pickedImage != null
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.file(_pickedImage!, fit: BoxFit.cover),
                              ),
                              Positioned(
                                bottom: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.edit, size: 14, color: Colors.white),
                                      SizedBox(width: 4),
                                      Text('Change Photo', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : (_imageUrl != null && _imageUrl!.isNotEmpty
                            ? Stack(
                                fit: StackFit.expand,
                                children: [
                                  AppImageView(
                                    imagePathOrUrl: _imageUrl,
                                    fit: BoxFit.cover,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  Positioned(
                                    bottom: 8,
                                    right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.7),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.edit, size: 14, color: Colors.white),
                                          SizedBox(width: 4),
                                          Text('Change Photo', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_a_photo_outlined, size: 36, color: isDark ? AppColors.primaryLight : AppColors.primary),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Upload Equipment Photo',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Tap to select image from gallery',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isDark ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.6) : AppColors.secondary.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              )),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Item Basics
              Text('Item Name', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: 'e.g. Sony FX3 Cinema Camera',
                  prefixIcon: Icon(Icons.handyman_outlined),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
              ),

              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SKU / Asset Tag', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _skuController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            hintText: 'CAM-001',
                            prefixIcon: Icon(Icons.qr_code),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Quantity in Depot', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _quantityController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            hintText: '1',
                            prefixIcon: Icon(Icons.inventory_2_outlined),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) return 'Required';
                            final qty = int.tryParse(val.trim());
                            if (qty == null || qty < 1) return 'Min 1';
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              Text('Description (Optional)', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              TextFormField(
                controller: _descController,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Key specs, lens mounts, serial numbers, accessories included...',
                ),
              ),

              const SizedBox(height: 14),

              // Equipment Category Inline Selector (No "General" default)
              BlocBuilder<CategoryCubit, CategoryState>(
                builder: (context, catState) {
                  List<String> categories = [];
                  if (catState is CategoryLoaded && catState.categories.isNotEmpty) {
                    categories = catState.categories.map((c) => c.name.trim()).where((n) => n.isNotEmpty && n.toLowerCase() != 'general').toList();
                  }
                  if (categories.isEmpty) {
                    categories = ['Cameras', 'Lenses', 'Lighting', 'Audio', 'Tools', 'Accessories'];
                  }

                  if (!categories.contains(_selectedCategory) && categories.isNotEmpty) {
                    _selectedCategory = categories.first;
                  }

                  final displayCategoryText = _selectedCategory;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Equipment Category', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _isCategoryDropdownExpanded = !_isCategoryDropdownExpanded;
                          });
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkCard : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _isCategoryDropdownExpanded
                                  ? AppColors.primary
                                  : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                              width: _isCategoryDropdownExpanded ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.category_outlined,
                                    size: 20,
                                    color: isDark ? AppColors.primaryLight : AppColors.primary,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    displayCategoryText,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              Icon(
                                _isCategoryDropdownExpanded
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                color: isDark ? AppColors.primaryLight : AppColors.primary,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Inline Dropdown Panel
                      if (_isCategoryDropdownExpanded) ...[
                        const SizedBox(height: 4),
                        Container(
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkCard : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ...categories.map((c) {
                                final isSelected = c == _selectedCategory;
                                return InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedCategory = c;
                                      _isCategoryDropdownExpanded = false;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? (isDark ? AppColors.primaryLight.withValues(alpha: 0.15) : AppColors.primary.withValues(alpha: 0.08))
                                          : Colors.transparent,
                                      border: Border(
                                        bottom: BorderSide(
                                          color: isDark ? AppColors.darkBorder.withValues(alpha: 0.5) : AppColors.lightBorder.withValues(alpha: 0.5),
                                          width: 0.5,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          c,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                            color: isSelected
                                                ? (isDark ? AppColors.primaryLight : AppColors.primary)
                                                : (isDark ? Colors.white : Colors.black87),
                                          ),
                                        ),
                                        if (isSelected)
                                          Icon(
                                            Icons.check_circle,
                                            size: 18,
                                            color: isDark ? AppColors.primaryLight : AppColors.primary,
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                              InkWell(
                                onTap: () async {
                                  setState(() => _isCategoryDropdownExpanded = false);
                                  final categoryCubit = context.read<CategoryCubit>();
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const CategoryListScreen()),
                                  );
                                  categoryCubit.loadCategories();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  child: Row(
                                    children: [
                                      Icon(Icons.add_circle_outline, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
                                      const SizedBox(width: 8),
                                      Text(
                                        '+ Add / Configure Categories',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? AppColors.primaryLight : AppColors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),

              const SizedBox(height: 14),

              Text('Default Security Deposit ($currency)', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              TextFormField(
                controller: _depositController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  prefixText: '$currency ',
                  hintText: '2500',
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
              ),

              const SizedBox(height: 20),

              // Sub-Items & Serial Numbers Card
              _buildSubItemsCard(context, isDark),

              const SizedBox(height: 20),

              // Equipment Tax Configuration Card
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
                        Expanded(
                          child: Row(
                            children: [
                              Icon(Icons.receipt_long, color: isDark ? AppColors.primaryLight : AppColors.primary, size: 20),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Equipment Tax Config',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        TextButton.icon(
                          onPressed: () async {
                            final url = Uri.parse(_getOfficialTaxGuidanceUrl(country));
                            if (await canLaunchUrl(url)) {
                              await launchUrl(url, mode: LaunchMode.externalApplication);
                            }
                          },
                          icon: const Icon(Icons.open_in_new, size: 13),
                          label: const Text('Find Tax Rate', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Tax Type', style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                initialValue: _taxType,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                  isDense: true,
                                ),
                                items: ['No Tax', 'GST', 'VAT', 'Sales Tax', 'Other'].map((t) {
                                  return DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13)));
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _taxType = val;
                                      if (val == 'No Tax') {
                                        _taxRateController.text = '0.0';
                                      }
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Tax Percentage (%)', style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _taxRateController,
                                enabled: _taxType != 'No Tax',
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  suffixText: '%',
                                  hintText: '18.0',
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                  isDense: true,
                                  filled: _taxType == 'No Tax',
                                  fillColor: _taxType == 'No Tax' ? (isDark ? Colors.grey.shade900 : Colors.grey.shade200) : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    if (_taxType != 'No Tax') ...[
                      const SizedBox(height: 14),
                      Text('Is Tax Included in Rental Price?', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => setState(() => _isTaxInclusive = false),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: !_isTaxInclusive
                                      ? AppColors.primary
                                      : (isDark ? AppColors.darkSurfaceLow : Colors.grey.shade100),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: !_isTaxInclusive ? AppColors.primary : (isDark ? AppColors.darkBorder : AppColors.lightBorder)),
                                ),
                                child: Text(
                                  'No — add tax on top',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: !_isTaxInclusive ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InkWell(
                              onTap: () => setState(() => _isTaxInclusive = true),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _isTaxInclusive
                                      ? AppColors.primary
                                      : (isDark ? AppColors.darkSurfaceLow : Colors.grey.shade100),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: _isTaxInclusive ? AppColors.primary : (isDark ? AppColors.darkBorder : AppColors.lightBorder)),
                                ),
                                child: Text(
                                  'Yes — tax is included',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _isTaxInclusive ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Smart Rates Section Card
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
                        Expanded(
                          child: Text(
                            'Smart Rate Calculator',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => _openRateConfigModal(context, store),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF3B2E15) : AppColors.tertiaryFixed,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Shift: ${workingHours}h/day • ${daysPerWeek}d/wk • ${daysPerMonth}d/mo',
                                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.tertiary),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.tune, size: 10, color: AppColors.tertiary),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Hourly Rate', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              TextFormField(
                                controller: _hourlyController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(prefixText: '$currency '),
                                onChanged: _onHourlyChanged,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Daily Rate (${workingHours}h shift)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              TextFormField(
                                controller: _dailyController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(prefixText: '$currency '),
                                onChanged: _onDailyChanged,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Weekly Rate ($daysPerWeek Days)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              TextFormField(
                                controller: _weeklyController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(prefixText: '$currency '),
                                onChanged: (_) => _isWeeklyManuallyEdited = true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Monthly Rate ($daysPerMonth Days)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              TextFormField(
                                controller: _monthlyController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(prefixText: '$currency '),
                                onChanged: (_) => _isMonthlyManuallyEdited = true,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              ElevatedButton(
                onPressed: (_isSaving || _isUploading) ? null : _handleSave,
                child: (_isSaving || _isUploading)
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                      )
                    : Text(widget.initialItem == null ? 'Add Equipment to Inventory' : 'Save Equipment Changes'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubItemsCard(BuildContext context, bool isDark) {
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
                  Icon(Icons.format_list_bulleted, color: isDark ? AppColors.primaryLight : AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  const Text('Sub-Items', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _subItemInputs.add(SubItemInput(
                      name: 'Unit ${_subItemInputs.length + 1}',
                      serial: '',
                    ));
                    _quantityController.text = _subItemInputs.length.toString();
                  });
                },
                icon: const Icon(Icons.add_circle_outline, size: 16),
                label: const Text('Add Sub-Item', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Track individual unit names and optional serial numbers for serialized depot equipment.',
            style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
          ),
          const SizedBox(height: 12),

          if (_subItemInputs.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: isDark ? AppColors.primaryLight : AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No sub-items added yet. Tap "+ Add Sub-Item" to add serial numbers or unit names.',
                      style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                    ),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _subItemInputs.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final input = _subItemInputs[index];
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Sub-Item #${index + 1}',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                            tooltip: 'Remove Sub-Item',
                            onPressed: () {
                              setState(() {
                                input.dispose();
                                _subItemInputs.removeAt(index);
                                if (_subItemInputs.isNotEmpty) {
                                  _quantityController.text = _subItemInputs.length.toString();
                                }
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Full-width Sub-Item Name Field
                      TextFormField(
                        controller: input.nameCtrl,
                        decoration: InputDecoration(
                          labelText: 'Sub-Item Name',
                          hintText: 'e.g. Unit #${index + 1} or Camera Body A',
                          prefixIcon: const Icon(Icons.label_outlined, size: 20),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Optional Serial Number Field
                      TextFormField(
                        controller: input.serialCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Serial Number (Optional - Auto Generated if empty)',
                          hintText: 'e.g. SN-489102 or leave blank to auto-generate',
                          prefixIcon: Icon(Icons.qr_code, size: 20),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
