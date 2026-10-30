import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/config/app_theme.dart';
import '../../core/services/r2_storage_service.dart';
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
import '../profile/subscription_paywall_screen.dart';

class ComponentDefinitionInput {
  final TextEditingController nameCtrl;
  final TextEditingController qtyCtrl;
  bool isRequired;

  ComponentDefinitionInput({String name = '', int qty = 1, this.isRequired = true})
      : nameCtrl = TextEditingController(text: name),
        qtyCtrl = TextEditingController(text: '$qty');

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
  }
}

class PhysicalSetInput {
  String assetCode;
  Map<String, int> componentQuantities; // componentName -> qty

  PhysicalSetInput({required this.assetCode, required this.componentQuantities});
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
    _componentDefInputs.addAll([
      ComponentDefinitionInput(name: 'Main Body', qty: 1, isRequired: true),
      ComponentDefinitionInput(name: 'Battery', qty: 1, isRequired: true),
      ComponentDefinitionInput(name: 'Charger', qty: 1, isRequired: true),
      ComponentDefinitionInput(name: 'Bag', qty: 1, isRequired: false),
    ]);
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
                name: d.componentName,
                qty: d.defaultQuantity,
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
    for (final c in _componentDefInputs) {
      c.dispose();
    }
    super.dispose();
  }

  void _autoCalculateRates(String dailyText) {
    final dailyRate = double.tryParse(dailyText) ?? 0.0;
    if (dailyRate <= 0) return;

    if (!_isWeeklyManuallyEdited) {
      final calculatedWeekly = dailyRate * 6.0;
      _weeklyController.text = calculatedWeekly.toStringAsFixed(0);
    }

    if (!_isMonthlyManuallyEdited) {
      final calculatedMonthly = dailyRate * 22.0;
      _monthlyController.text = calculatedMonthly.toStringAsFixed(0);
    }
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
                  title: const Text('Take Photo with Camera'),
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

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: sourceOption == 'camera' ? ImageSource.camera : ImageSource.gallery,
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
      debugPrint('Error picking image: $e');
    }
  }

  void _proceedToStep2() async {
    if (!_formKey.currentState!.validate()) return;

    final int setsCount = int.tryParse(_setsCountController.text) ?? 1;
    final tag = _skuController.text.trim().isNotEmpty
        ? _skuController.text.trim().toUpperCase()
        : 'UNIT';

    // Generate physical set cards initially with standard component quantities
    _physicalSetInputs.clear();

    final repo = InventoryUnitRepository();

    for (int i = 1; i <= setsCount; i++) {
      final assetCode = await repo.generateAssetCode(tag, 'physical_unit');

      final Map<String, int> compMap = {};
      for (final comp in _componentDefInputs) {
        final name = comp.nameCtrl.text.trim();
        final qty = int.tryParse(comp.qtyCtrl.text.trim()) ?? 1;
        if (name.isNotEmpty && qty > 0) {
          compMap[name] = qty;
        }
      }

      _physicalSetInputs.add(
        PhysicalSetInput(assetCode: assetCode, componentQuantities: compMap),
      );
    }

    setState(() {
      _currentStep = 2;
    });
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
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
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
        final name = comp.nameCtrl.text.trim();
        final qty = int.tryParse(comp.qtyCtrl.text.trim()) ?? 1;
        if (name.isNotEmpty) {
          defModels.add(SubItemDefinitionModel(
            id: UuidGenerator.generateV4(),
            parentItemId: itemId,
            storeId: store.id,
            componentName: name,
            defaultQuantity: qty,
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
        final unitId = UuidGenerator.generateV4();

        final List<InventoryComponentUnitModel> compUnits = [];

        for (final entry in setInput.componentQuantities.entries) {
          final compName = entry.key;
          final qty = entry.value;

          final defModel = defModels.where((d) => d.componentName == compName).firstOrNull;

          for (int piece = 1; piece <= qty; piece++) {
            final compPrefix = compName.substring(0, compName.length >= 3 ? 3 : compName.length);
            final compCode = await repo.generateAssetCode(compPrefix, 'component_unit');

            compUnits.add(InventoryComponentUnitModel(
              id: UuidGenerator.generateV4(),
              inventoryUnitId: unitId,
              inventoryItemId: itemId,
              componentDefinitionId: defModel?.id,
              storeId: store.id,
              componentName: compName,
              assetCode: compCode,
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

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
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
            onPressed: _proceedToStep2,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Row(
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

                  ...setInput.componentQuantities.entries.map((entry) {
                    final compName = entry.key;
                    final currentQty = entry.value;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(compName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
                                    if (currentQty > 0) {
                                      setInput.componentQuantities[compName] = currentQty - 1;
                                    }
                                  });
                                },
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
                onPressed: () {
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

  Widget _buildCategoryCard(bool isDark) {
    final categoryState = context.watch<CategoryCubit>().state;
    final categories = categoryState is CategoryLoaded ? categoryState.categories : <String>['Cameras', 'Lenses', 'Lighting', 'Audio', 'Drones', 'General'];

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

          DropdownButtonFormField<String>(
            initialValue: categories.contains(_selectedCategory) ? _selectedCategory : (categories.firstOrNull as String? ?? 'General'),
            isExpanded: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.category_outlined),
              isDense: true,
            ),
            items: categories.map((cat) {
              final String catStr = cat.toString();
              return DropdownMenuItem<String>(
                value: catStr,
                child: Text(catStr, style: const TextStyle(fontSize: 13)),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedCategory = val);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildComponentDefinitionsCard(bool isDark) {
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
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Default Component Templates', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    Text('Standard accessories included in 1 physical set', style: TextStyle(fontSize: 10, color: AppColors.secondary)),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _componentDefInputs.add(ComponentDefinitionInput(name: '', qty: 1, isRequired: true));
                  });
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('+ Add Component', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 10),

          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _componentDefInputs.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final comp = _componentDefInputs[index];

              return Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: comp.nameCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Component Name (e.g. Battery)',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 60,
                    child: TextFormField(
                      controller: comp.qtyCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Checkbox(
                    value: comp.isRequired,
                    activeColor: AppColors.primary,
                    onChanged: (val) {
                      setState(() {
                        comp.isRequired = val ?? true;
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                    onPressed: () {
                      setState(() {
                        _componentDefInputs.removeAt(index);
                      });
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRatesAndDepositCard(bool isDark, String currency) {
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
              Icon(Icons.sell_outlined, size: 18, color: isDark ? AppColors.primaryLight : AppColors.primary),
              const SizedBox(width: 6),
              const Text('Rental Rates & Security Deposit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
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
                  onChanged: _autoCalculateRates,
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
                  onChanged: (_) => _isWeeklyManuallyEdited = true,
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
                  onChanged: (_) => _isMonthlyManuallyEdited = true,
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
