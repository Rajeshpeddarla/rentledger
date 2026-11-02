import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/config/app_theme.dart';
import '../../core/services/r2_storage_service.dart';
import '../../core/utils/rate_calculator.dart';
import '../../core/utils/uuid_generator.dart';
import '../../core/widgets/app_image_view.dart';
import '../../data/models/inventory_component_unit_model.dart';
import '../../data/models/inventory_item_model.dart';
import '../../data/models/inventory_unit_model.dart';
import '../../data/models/sub_item_definition_model.dart';
import '../../data/repositories/inventory_unit_repository.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../../viewmodels/category/category_cubit.dart';
import '../../viewmodels/category/category_state.dart';
import '../../viewmodels/inventory/inventory_cubit.dart';
import '../profile/category_list_screen.dart';
import '../profile/edit_store_profile_screen.dart';
import '../profile/subscription_paywall_screen.dart';
import '../lease/in_app_camera_screen.dart';

class ComponentDefinitionInput {
  final String id;
  final TextEditingController nameCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController costCtrl;
  bool isRequired;

  ComponentDefinitionInput({
    String? id,
    String name = '',
    int qty = 1,
    double cost = 0.0,
    this.isRequired = true,
  })  : id = id ?? UuidGenerator.generateV4(),
        nameCtrl = TextEditingController(text: name),
        qtyCtrl = TextEditingController(text: '$qty'),
        costCtrl = TextEditingController(text: cost > 0 ? cost.toStringAsFixed(0) : '');

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
    costCtrl.dispose();
  }
}

class PhysicalSetInput {
  String? unitId;
  String assetCode;
  int unitNumber;
  Map<String, int> componentQuantities; // componentName -> qty

  PhysicalSetInput({
    this.unitId,
    required this.assetCode,
    required this.unitNumber,
    required this.componentQuantities,
  });
}

class AddEditItemScreen extends StatefulWidget {
  final InventoryItemModel? initialItem;
  final bool isPro;

  const AddEditItemScreen({super.key, this.initialItem, required this.isPro});

  @override
  State<AddEditItemScreen> createState() => _AddEditItemScreenState();
}

class _AddEditItemScreenState extends State<AddEditItemScreen> {
  int _currentStep = 1; // 1 = General Details & Definitions, 2 = Physical Sets & Component Config

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  late final TextEditingController _skuController;
  late final TextEditingController _depositController;

  late final TextEditingController _hourlyController;
  late final TextEditingController _dailyController;
  late final TextEditingController _weeklyController;
  late final TextEditingController _monthlyController;

  // Equipment Tax Configuration Fields
  String _taxType = 'No Tax';
  late final TextEditingController _taxRateController;
  bool _isTaxInclusive = false;

  // Component Definitions list
  final List<ComponentDefinitionInput> _componentDefInputs = [];

  // Physical Sets Config (Step 2)
  late TextEditingController _setsCountController;
  final List<PhysicalSetInput> _physicalSetInputs = [];

  String _selectedCategory = 'Cameras';
  bool _isCategoryDropdownExpanded = false;

  File? _pickedImage;
  String? _imageUrl;
  bool _isSaving = false;

  // Rate calculation mode: 'auto' vs 'manual'
  String _rateMode = 'auto';

  // Component Form Input Controllers
  final TextEditingController _formCompNameController = TextEditingController();
  final TextEditingController _formCompQtyController = TextEditingController(text: '1');
  final TextEditingController _formCompCostController = TextEditingController();
  int? _editingCompIndex;


  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;

    _nameController = TextEditingController(text: item?.name ?? '');
    _descController = TextEditingController(text: item?.description ?? '');
    _skuController = TextEditingController(text: item?.sku ?? '');
    _depositController = TextEditingController(text: item != null ? '${item.depositAmount.toInt()}' : '2500');

    _hourlyController = TextEditingController(text: item != null ? '${item.rateHourly.toInt()}' : '150');
    _dailyController = TextEditingController(text: item != null ? '${item.rateDaily.toInt()}' : '1200');
    _weeklyController = TextEditingController(text: item != null ? '${item.rateWeekly.toInt()}' : '7200');
    _monthlyController = TextEditingController(text: item != null ? '${item.rateMonthly.toInt()}' : '26400');

    _taxType = item?.taxType ?? 'No Tax';
    _taxRateController = TextEditingController(text: item != null ? item.taxRate.toStringAsFixed(1) : '0.0');
    _isTaxInclusive = item?.isTaxInclusive ?? false;

    _selectedCategory = item?.category ?? 'Cameras';
    _imageUrl = item?.imageR2Url;

    _setsCountController = TextEditingController(text: '${item?.totalQuantity ?? 1}');

    // Load existing component definitions or default templates
    if (item != null) {
      _loadExistingDefinitions(item.id);
    } else {
      _addDefaultComponentTemplates();
    }
  }

  void _addDefaultComponentTemplates() {
    // Empty by default - user explicitly adds components using the form below
  }

  Future<void> _loadExistingDefinitions(String productId) async {
    try {
      final defs = await InventoryUnitRepository().getDefinitionsForProduct(productId);
      if (mounted && defs.isNotEmpty) {
        setState(() {
          _componentDefInputs.clear();
          for (final d in defs) {
            _componentDefInputs.add(
              ComponentDefinitionInput(
                id: d.id,
                name: d.componentName,
                qty: d.defaultQuantity,
                cost: d.replacementCost,
                isRequired: d.isRequired,
              ),
            );
          }
        });
      } else if (mounted && _componentDefInputs.isEmpty) {
        _addDefaultComponentTemplates();
      }
    } catch (e) {
      debugPrint('Error loading existing component definitions: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _skuController.dispose();
    _depositController.dispose();
    _hourlyController.dispose();
    _dailyController.dispose();
    _weeklyController.dispose();
    _monthlyController.dispose();
    _taxRateController.dispose();
    _setsCountController.dispose();
    _formCompNameController.dispose();
    _formCompQtyController.dispose();
    _formCompCostController.dispose();
    for (final c in _componentDefInputs) {
      c.dispose();
    }
    super.dispose();
  }

  void _recalculateRatesFromMode({double? hourly, double? daily, double? weekly, double? monthly}) {
    if (_rateMode != 'auto') return;

    final storeState = context.read<StoreCubit>().state;
    final store = storeState is StoreLoaded ? storeState.store : null;

    final workingHours = store != null ? (store.dailyWorkingHours <= 0 ? 8.0 : store.dailyWorkingHours.toDouble()) : 8.0;
    final daysPerWeek = store?.daysPerWeek ?? 6;
    final daysPerMonth = store?.effectiveDaysPerMonth ?? 28;

    final rates = RateCalculator.suggestRates(
      hourly: hourly,
      daily: daily,
      weekly: weekly,
      monthly: monthly,
      workingHours: workingHours,
      daysPerWeek: daysPerWeek,
      daysPerMonth: daysPerMonth,
    );

    if (hourly == null) _hourlyController.text = rates['hourly']!.toStringAsFixed(0);
    if (daily == null) _dailyController.text = rates['daily']!.toStringAsFixed(0);
    if (weekly == null) _weeklyController.text = rates['weekly']!.toStringAsFixed(0);
    if (monthly == null) _monthlyController.text = rates['monthly']!.toStringAsFixed(0);
  }

  void _onHourlyChanged(String val) {
    final h = double.tryParse(val);
    _recalculateRatesFromMode(hourly: h);
  }

  void _onDailyChanged(String val) {
    final d = double.tryParse(val);
    _recalculateRatesFromMode(daily: d);
  }

  void _onWeeklyChanged(String val) {
    final w = double.tryParse(val);
    _recalculateRatesFromMode(weekly: w);
  }

  void _onMonthlyChanged(String val) {
    final m = double.tryParse(val);
    _recalculateRatesFromMode(monthly: m);
  }

  Future<void> _pickImage() async {
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
                const Text('Choose Equipment Photo Source', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
          _pickedImage = capturedFile;
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
            _pickedImage = File(picked.path);
          });
        }
      } catch (e) {
        debugPrint('Error picking gallery photo: $e');
      }
    }
  }

  String _capitalizeFirstLetter(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.length == 1) return trimmed.toUpperCase();
    return '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
  }

  bool _isGeneratingSets = false;

  void _proceedToStep2() async {
    if (!_formKey.currentState!.validate()) return;

    if (_componentDefInputs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Please add at least 1 default component before configuring physical sets.',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.errorRed,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _isGeneratingSets = true);

    try {
      final int setsCount = int.tryParse(_setsCountController.text) ?? 1;
      final tag = _skuController.text.trim().isNotEmpty
          ? _skuController.text.trim().toUpperCase()
          : 'UNIT';

      final repo = InventoryUnitRepository();
      _physicalSetInputs.clear();

      // Load existing physical sets if editing an existing equipment item
      List<InventoryUnitModel> existingUnits = [];
      if (widget.initialItem != null) {
        existingUnits = await repo.getUnitsForProduct(widget.initialItem!.id);
      }

      // Build standard template component map from Step 1 inputs
      final Map<String, int> defaultCompMap = {};
      for (final comp in _componentDefInputs) {
        final name = _capitalizeFirstLetter(comp.nameCtrl.text);
        final qty = int.tryParse(comp.qtyCtrl.text.trim()) ?? 1;
        if (name.isNotEmpty) {
          defaultCompMap[name] = qty;
        }
      }

      for (int i = 0; i < setsCount; i++) {
        final setNum = i + 1;
        if (i < existingUnits.length) {
          // Reuse existing physical unit asset code and saved component piece counts!
          final existing = existingUnits[i];

          final Map<String, int> savedCompMap = {};

          // 1. Initialize ALL template component names with 0
          for (final entry in defaultCompMap.entries) {
            savedCompMap[entry.key] = 0;
          }

          // 2. Count existing component units for this physical set
          for (final compUnit in existing.components) {
            savedCompMap[compUnit.componentName] =
                (savedCompMap[compUnit.componentName] ?? 0) + 1;
          }

          _physicalSetInputs.add(
            PhysicalSetInput(
              unitId: existing.id,
              assetCode: existing.assetCode,
              unitNumber: existing.unitNumber > 0 ? existing.unitNumber : setNum,
              componentQuantities: savedCompMap,
            ),
          );
        } else {
          // Newly added physical set (format asset code sequentially starting from 0001 per equipment item)
          final assetCode = '$tag-${setNum.toString().padLeft(4, '0')}';
          _physicalSetInputs.add(
            PhysicalSetInput(
              assetCode: assetCode,
              unitNumber: setNum,
              componentQuantities: Map<String, int>.from(defaultCompMap),
            ),
          );
        }
      }

      if (mounted) {
        setState(() {
          _currentStep = 2;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Unable to configure physical sets: $e',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.errorRed,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingSets = false);
      }
    }
  }

  Future<void> _handleFinalSave() async {
    setState(() => _isSaving = true);

    try {
      final storeState = context.read<StoreCubit>().state;
      final store = storeState is StoreLoaded ? storeState.store : null;
      if (store == null) throw Exception('Store not found');

      // 1. Upload photo to Cloudflare R2 if picked
      String? uploadedUrl = _imageUrl;
      if (_pickedImage != null) {
        final itemId = widget.initialItem?.id ?? UuidGenerator.generateV4();
        uploadedUrl = await R2StorageService.instance.uploadImage(
          file: _pickedImage!,
          folder: 'inventory/$itemId',
          filename: 'product.webp',
        );
      }

      final itemId = widget.initialItem?.id ?? UuidGenerator.generateV4();
      final totalSetsCount = _physicalSetInputs.length;

      // 2. Save Inventory Item Product Definition
      final itemModel = InventoryItemModel(
        id: itemId,
        storeId: store.id,
        name: _capitalizeFirstLetter(_nameController.text),
        description: _capitalizeFirstLetter(_descController.text),
        sku: _skuController.text.trim().toUpperCase(),
        category: _selectedCategory,
        imageR2Url: uploadedUrl,
        depositAmount: double.tryParse(_depositController.text) ?? 0.0,
        rateHourly: double.tryParse(_hourlyController.text) ?? 0.0,
        rateDaily: double.tryParse(_dailyController.text) ?? 0.0,
        rateWeekly: double.tryParse(_weeklyController.text) ?? 0.0,
        rateMonthly: double.tryParse(_monthlyController.text) ?? 0.0,
        totalQuantity: totalSetsCount,
        taxType: _taxType,
        taxRate: double.tryParse(_taxRateController.text) ?? 0.0,
        isTaxInclusive: _isTaxInclusive,
        createdAt: widget.initialItem?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await context.read<InventoryCubit>().saveItem(itemModel, isPro: widget.isPro);

      // 3. Save Component Definitions Template
      final List<SubItemDefinitionModel> defModels = [];
      for (final comp in _componentDefInputs) {
        final name = _capitalizeFirstLetter(comp.nameCtrl.text);
        final qty = int.tryParse(comp.qtyCtrl.text.trim()) ?? 1;
        final cost = double.tryParse(comp.costCtrl.text.trim()) ?? 0.0;
        if (name.isNotEmpty) {
          defModels.add(SubItemDefinitionModel(
            id: UuidGenerator.generateV4(),
            parentItemId: itemId,
            storeId: store.id,
            componentName: name,
            defaultQuantity: qty,
            replacementCost: cost,
            isRequired: comp.isRequired,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ));
        }
      }

      final repo = InventoryUnitRepository();
      await repo.saveDefinitions(productId: itemId, definitions: defModels);

      // 4. Save Physical Set Units & Physical Component Units
      final List<InventoryUnitModel> unitModels = [];

      for (final setInput in _physicalSetInputs) {
        final unitId = setInput.unitId ?? UuidGenerator.generateV4();

        final List<InventoryComponentUnitModel> compUnits = [];

        for (final entry in setInput.componentQuantities.entries) {
          final compName = entry.key;
          final qty = entry.value;

          final defModel = defModels.where((d) => d.componentName == compName).firstOrNull;

          for (int piece = 1; piece <= qty; piece++) {
            final compPrefix = compName.substring(0, compName.length >= 3 ? 3 : compName.length).toUpperCase();
            final compCode = '$compPrefix-${setInput.unitNumber.toString().padLeft(2, '0')}-${piece.toString().padLeft(2, '0')}';

            compUnits.add(InventoryComponentUnitModel(
              id: UuidGenerator.generateV4(),
              inventoryUnitId: unitId,
              inventoryItemId: itemId,
              componentDefinitionId: defModel?.id,
              storeId: store.id,
              componentName: compName,
              assetCode: compCode,
              replacementCost: defModel?.replacementCost ?? 0.0,
              status: 'available',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ));
          }
        }

        unitModels.add(InventoryUnitModel(
          id: unitId,
          inventoryItemId: itemId,
          storeId: store.id,
          assetCode: setInput.assetCode,
          unitNumber: setInput.unitNumber,
          status: 'available',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          components: compUnits,
        ));
      }

      await repo.savePhysicalSets(productId: itemId, units: unitModels);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Equipment "${itemModel.name}" with $totalSetsCount physical set(s) saved successfully!',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.primary,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      if (e.toString().contains('FREE_ITEM_LIMIT_REACHED')) {
        _showUpgradePaywallDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving inventory: $e'),
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
        title: const Text('Free Inventory Limit Reached'),
        content: const Text(
          'Free tier allows up to 10 active equipment items. Upgrade to Pro for unlimited equipment inventory, dynamic asset code tracking, and GST invoicing.',
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEdit = widget.initialItem != null;

    return PopScope(
      canPop: _currentStep == 1,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentStep == 2) {
          setState(() {
            _currentStep = 1;
          });
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (_currentStep == 2) {
                setState(() {
                  _currentStep = 1;
                });
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: Text(_currentStep == 1
              ? (isEdit ? 'Edit Equipment' : 'Add New Equipment')
              : 'Configure Physical Sets'),
          elevation: 0,
          backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: _currentStep == 1 ? _buildStep1GeneralDetails(context, isDark) : _buildStep2PhysicalSetsConfig(context, isDark),
        ),
      ),
    );
  }

  Widget _buildStep1GeneralDetails(BuildContext context, bool isDark) {
    final storeState = context.watch<StoreCubit>().state;
    final currency = storeState is StoreLoaded ? storeState.store.currencySymbol : '₹';

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Photo Intake Tile
          _buildPhotoTile(isDark),
          const SizedBox(height: 16),

          // 2. Product Name & SKU/Tag
          _buildBasicDetailsCard(isDark),
          const SizedBox(height: 16),

          // 3. Category Dropdown
          _buildCategoryCard(isDark),
          const SizedBox(height: 16),

          // 4. Default Component Definitions Template Card
          _buildComponentDefinitionsCard(isDark),
          const SizedBox(height: 16),

          // 5. Rates & Deposit Card
          _buildRatesAndDepositCard(isDark, currency),
          const SizedBox(height: 16),

          // 6. Tax Details Card
          _buildTaxDetailsCard(isDark),
          const SizedBox(height: 16),

          // 7. Quantity of Sets
          TextFormField(
            controller: _setsCountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'How Many Physical Sets Do You Own?',
              hintText: 'e.g. 4',
              prefixIcon: Icon(Icons.inventory_2_outlined),
            ),
            validator: (val) {
              final v = int.tryParse(val ?? '');
              if (v == null || v <= 0) return 'Enter a valid number of sets (>= 1)';
              return null;
            },
          ),
          const SizedBox(height: 24),

          // Next Step CTA
          ElevatedButton(
            onPressed: (_isSaving || _isGeneratingSets) ? null : _proceedToStep2,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isGeneratingSets
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Continue to Configure Physical Sets', style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 18),
                    ],
                  ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildStep2PhysicalSetsConfig(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.handyman, color: AppColors.primary, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_physicalSetInputs.length} Physical Set(s) Generated',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Customize actual component piece quantities for each physical set below.',
                      style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _physicalSetInputs.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final setInput = _physicalSetInputs[index];

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
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          setInput.assetCode,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      Text(
                        'Set #${index + 1}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  const Text('Component Quantities in this Set:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
                  const SizedBox(height: 8),

                  ...setInput.componentQuantities.entries.toList().asMap().entries.map((compEntry) {
                    final compIndex = compEntry.key;
                    final entry = compEntry.value;
                    final compName = entry.key;
                    final currentQty = entry.value;

                    final isMainComponent = compIndex == 0;
                    final canDecrease = isMainComponent ? currentQty > 1 : currentQty > 0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              compName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isMainComponent ? FontWeight.bold : FontWeight.w600,
                              ),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.remove_circle_outline,
                                  size: 20,
                                  color: canDecrease ? null : Colors.grey.shade400,
                                ),
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(4),
                                onPressed: canDecrease
                                    ? () {
                                        setState(() {
                                          setInput.componentQuantities[compName] = currentQty - 1;
                                        });
                                      }
                                    : null,
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: currentQty > 0
                                      ? AppColors.primary.withValues(alpha: 0.12)
                                      : (isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$currentQty Pcs',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: currentQty > 0 ? AppColors.primary : Colors.grey,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline, size: 20),
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(4),
                                onPressed: () {
                                  setState(() {
                                    setInput.componentQuantities[compName] = currentQty + 1;
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isSaving ? null : () {
                  setState(() => _currentStep = 1);
                },
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back to Step 1'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _handleFinalSave,
                icon: _isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(_isSaving ? 'Saving...' : 'Save Inventory'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildPhotoTile(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _pickImage,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
              ),
              child: _pickedImage != null
                  ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(_pickedImage!, fit: BoxFit.cover))
                  : (_imageUrl != null && _imageUrl!.isNotEmpty
                      ? ClipRRect(borderRadius: BorderRadius.circular(12), child: AppImageView(imagePathOrUrl: _imageUrl, fit: BoxFit.cover))
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt_outlined, size: 24, color: isDark ? AppColors.primaryLight : AppColors.primary),
                            const SizedBox(height: 2),
                            const Text('+ Photo', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        )),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Equipment Photo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  'Add high-res product photo for digital receipts & client invoices.',
                  style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicDetailsCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
      ),
      child: Column(
        children: [
          TextFormField(
            controller: _nameController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Equipment Name *',
              hintText: 'e.g. Sony FX3 Cinema Camera Set',
              prefixIcon: Icon(Icons.handyman_outlined),
            ),
            validator: (val) => val == null || val.trim().isEmpty ? 'Equipment name is required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _skuController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'SKU / Asset Tag Prefix',
              hintText: 'e.g. CAM',
              prefixIcon: Icon(Icons.qr_code),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _descController,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Description & Features (Optional)',
              hintText: 'Full frame, 4K 120fps, includes dual audio handle...',
              prefixIcon: Icon(Icons.notes),
            ),
          ),
        ],
      ),
    );
  }

  void _openCategoryPickerModal(BuildContext context, List<String> categoryNames, bool isDark) {
    FocusManager.instance.primaryFocus?.unfocus();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      builder: (ctx) {
        return Container(
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Select Category',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppColors.lightOnSurface,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CategoryListScreen()),
                      );
                    },
                    child: const Text('Manage', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: categoryNames.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final cat = categoryNames[index];
                    final isSelected = cat == _selectedCategory;

                    return InkWell(
                      onTap: () {
                        setState(() {
                          _selectedCategory = cat;
                        });
                        Navigator.pop(ctx);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isDark ? AppColors.primaryLight.withValues(alpha: 0.15) : AppColors.primary.withValues(alpha: 0.08))
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              cat,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected
                                    ? (isDark ? AppColors.primaryLight : AppColors.primary)
                                    : (isDark ? Colors.white : AppColors.lightOnSurface),
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle, color: AppColors.primary, size: 18),
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
  }

  Widget _buildCategoryCard(bool isDark) {
    final categoryState = context.watch<CategoryCubit>().state;
    final List<String> categoryNames = categoryState is CategoryLoaded
        ? categoryState.categoryNames
        : <String>['Cameras', 'Lenses', 'Lighting', 'Audio', 'Drones', 'General'];

    final String effectiveValue = categoryNames.contains(_selectedCategory)
        ? _selectedCategory
        : (categoryNames.isNotEmpty ? categoryNames.first : 'General');

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
              const Text('Category Classification', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CategoryListScreen()),
                  );
                },
                child: const Text('Manage Categories', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          InkWell(
            onTap: () => _openCategoryPickerModal(context, categoryNames, isDark),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.category_outlined, size: 20, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      effectiveValue,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_down, size: 20, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleAddOrUpdateComponent() {
    final name = _capitalizeFirstLetter(_formCompNameController.text);
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a component name.')),
      );
      return;
    }

    final qty = int.tryParse(_formCompQtyController.text.trim()) ?? 1;
    final cost = double.tryParse(_formCompCostController.text.trim()) ?? 0.0;

    setState(() {
      if (_editingCompIndex != null && _editingCompIndex! < _componentDefInputs.length) {
        // Update existing component in place
        final existing = _componentDefInputs[_editingCompIndex!];
        existing.nameCtrl.text = name;
        existing.qtyCtrl.text = '$qty';
        existing.costCtrl.text = cost > 0 ? cost.toStringAsFixed(0) : '';
        _editingCompIndex = null;
      } else {
        // Add new component to list
        _componentDefInputs.add(
          ComponentDefinitionInput(
            name: name,
            qty: qty,
            cost: cost,
            isRequired: true,
          ),
        );
      }

      // Reset form input fields
      _formCompNameController.clear();
      _formCompQtyController.text = '1';
      _formCompCostController.clear();
    });
  }

  void _startEditingComponent(int index) {
    final comp = _componentDefInputs[index];
    setState(() {
      _editingCompIndex = index;
      _formCompNameController.text = comp.nameCtrl.text;
      _formCompQtyController.text = comp.qtyCtrl.text;
      _formCompCostController.text = comp.costCtrl.text;
    });
  }

  Widget _buildComponentDefinitionsCard(bool isDark) {
    final storeState = context.watch<StoreCubit>().state;
    final currency = storeState is StoreLoaded ? storeState.store.currencySymbol : '₹';

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
          const Text('Default Components', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(
            'Standard accessories included in 1 physical set',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
            ),
          ),
          const SizedBox(height: 14),

          // Component Input Form Container
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurfaceLow : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? AppColors.darkBorder : Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _editingCompIndex != null ? 'Edit Component Details' : 'Add Component Details',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
                const SizedBox(height: 8),

                // Field 1: Component Name
                Text(
                  'Component / Accessory Name',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _formCompNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: 'e.g. 18V Battery, Fast Charger, Lens Cap',
                    hintStyle: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black38),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    fillColor: isDark ? AppColors.darkCard : Colors.white,
                    filled: true,
                  ),
                ),
                const SizedBox(height: 10),

                // Row 2: Default Quantity & Damage/Loss Fee per Piece
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Default Qty',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                          ),
                          const SizedBox(height: 4),
                          TextFormField(
                            controller: _formCompQtyController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              hintText: '1',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              fillColor: isDark ? AppColors.darkCard : Colors.white,
                              filled: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Damage/Loss Fee per Piece ($currency)',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                          ),
                          const SizedBox(height: 4),
                          TextFormField(
                            controller: _formCompCostController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              prefixText: '$currency ',
                              hintText: '1500',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              fillColor: isDark ? AppColors.darkCard : Colors.white,
                              filled: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Form Action Button (Placed below damage/loss fee text field)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _handleAddOrUpdateComponent,
                    icon: Icon(_editingCompIndex != null ? Icons.save_outlined : Icons.add, size: 16),
                    label: Text(
                      _editingCompIndex != null ? 'Update Component' : 'Add Component',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Added Components List (Rendered BELOW form & button)
          Text(
            'Configured Component List (${_componentDefInputs.length})',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _componentDefInputs.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final comp = _componentDefInputs[index];
              final isEditingThis = _editingCompIndex == index;

              return Container(
                key: ValueKey(comp.id),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isEditingThis
                      ? AppColors.primary.withValues(alpha: 0.1)
                      : (isDark ? AppColors.darkCard : Colors.white),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isEditingThis
                        ? AppColors.primary
                        : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    width: isEditingThis ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Accessory #${index + 1}',
                                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.primary),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  comp.nameCtrl.text.isNotEmpty ? comp.nameCtrl.text : 'Component',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Qty: ${comp.qtyCtrl.text} • Damage/Loss Fee: $currency${comp.costCtrl.text.isNotEmpty ? comp.costCtrl.text : "0"}',
                            style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                          ),
                        ],
                      ),
                    ),

                    // Actions: Edit (All items) + Delete (Only for index > 0)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: AppColors.primary, size: 20),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                      tooltip: 'Edit Component',
                      onPressed: () => _startEditingComponent(index),
                    ),
                    if (index > 0) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                        tooltip: 'Remove Component',
                        onPressed: () {
                          setState(() {
                            if (_editingCompIndex == index) {
                              _editingCompIndex = null;
                              _formCompNameController.clear();
                              _formCompQtyController.text = '1';
                              _formCompCostController.clear();
                            }
                            _componentDefInputs.removeAt(index);
                          });
                        },
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRatesAndDepositCard(bool isDark, String currency) {
    final storeState = context.watch<StoreCubit>().state;
    final store = storeState is StoreLoaded ? storeState.store : null;

    final workingHours = store != null ? (store.dailyWorkingHours <= 0 ? 8 : store.dailyWorkingHours) : 8;
    final daysPerWeek = store?.daysPerWeek ?? 6;
    final daysPerMonth = store?.effectiveDaysPerMonth ?? 28;

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
                  Icon(Icons.sell_outlined, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
                  const SizedBox(width: 6),
                  const Text('Rental Rates & Security Deposit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Rate Calculation Mode Selector: Auto vs Manual
          Row(
            children: [
              _buildRateModeChip(
                label: 'Auto Calculate Rates',
                mode: 'auto',
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _buildRateModeChip(
                label: 'Manual Rates',
                mode: 'manual',
                isDark: isDark,
              ),
            ],
          ),

          // Info Banner Container explaining Store Rules
          if (_rateMode == 'auto') ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF142E24) : const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? AppColors.primary : const Color(0xFFA7F3D0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: isDark ? AppColors.primaryLight : AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rates auto-calculate using Store Rules (${workingHours}h/shift, ${daysPerWeek}d/wk, ${daysPerMonth}d/mo).',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.primaryLight : AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        InkWell(
                          onTap: () {
                            if (store != null) {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => EditStoreProfileScreen(store: store),
                                ),
                              );
                            }
                          },
                          child: Text(
                            'Configure Shift Length & Operating Days in Store Profile & Settings ➔',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                              color: isDark ? AppColors.primaryLight : AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _hourlyController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Hourly Rate ($currency)',
                    prefixText: '$currency ',
                  ),
                  onChanged: _onHourlyChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _dailyController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Daily Rate ($currency) *',
                    prefixText: '$currency ',
                  ),
                  onChanged: _onDailyChanged,
                  validator: (val) => val == null || val.trim().isEmpty ? 'Daily rate required' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _weeklyController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Weekly Rate ($currency)',
                    prefixText: '$currency ',
                  ),
                  onChanged: _onWeeklyChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _monthlyController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Monthly Rate ($currency)',
                    prefixText: '$currency ',
                  ),
                  onChanged: _onMonthlyChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          TextFormField(
            controller: _depositController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Security Deposit ($currency) *',
              prefixText: '$currency ',
              helperText: 'Collected upfront per physical set handed over',
            ),
            validator: (val) => val == null || val.trim().isEmpty ? 'Security deposit required' : null,
          ),
        ],
      ),
    );
  }

  Widget _buildRateModeChip({
    required String label,
    required String mode,
    required bool isDark,
  }) {
    final bool isSelected = _rateMode == mode;

    return InkWell(
      onTap: () {
        setState(() {
          _rateMode = mode;
          if (mode == 'auto') {
            _onDailyChanged(_dailyController.text);
          }
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : (isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 14,
              color: isSelected ? Colors.white : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? Colors.white : (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaxDetailsCard(bool isDark) {
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
              Icon(Icons.receipt_long_outlined, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
              const SizedBox(width: 6),
              const Text('Tax Configuration', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _taxType,
                  decoration: const InputDecoration(labelText: 'Tax Type', isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'No Tax', child: Text('No Tax')),
                    DropdownMenuItem(value: 'GST', child: Text('GST')),
                    DropdownMenuItem(value: 'VAT', child: Text('VAT')),
                    DropdownMenuItem(value: 'Sales Tax', child: Text('Sales Tax')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _taxType = val;
                        if (val == 'No Tax') _taxRateController.text = '0.0';
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _taxRateController,
                  enabled: _taxType != 'No Tax',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Tax Rate (%)',
                    suffixText: '%',
                  ),
                ),
              ),
            ],
          ),
          if (_taxType != 'No Tax') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: _isTaxInclusive,
                  activeColor: AppColors.primary,
                  onChanged: (val) => setState(() => _isTaxInclusive = val ?? false),
                ),
                const Text('Tax Inclusive Rates', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
