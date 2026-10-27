import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../core/config/app_theme.dart';
import '../../core/utils/uuid_generator.dart';
import '../../data/models/discount_model.dart';
import '../../data/models/inventory_item_model.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';
import '../../viewmodels/discount/discount_cubit.dart';
import '../../viewmodels/inventory/inventory_cubit.dart';
import '../../viewmodels/inventory/inventory_state.dart';

class CreateEditDiscountScreen extends StatefulWidget {
  final DiscountModel? existingDiscount;

  const CreateEditDiscountScreen({super.key, this.existingDiscount});

  @override
  State<CreateEditDiscountScreen> createState() => _CreateEditDiscountScreenState();
}

class _CreateEditDiscountScreenState extends State<CreateEditDiscountScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _codeCtrl;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _valueCtrl;
  late final TextEditingController _minDaysCtrl;
  late final TextEditingController _maxUsesCtrl;
  final TextEditingController _itemSearchCtrl = TextEditingController();

  late String _discountType;
  late DateTime _expiryDate;
  late List<String> _selectedItemIds;
  bool _selectAllItems = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.existingDiscount;

    _codeCtrl = TextEditingController(text: d?.code ?? '');
    _titleCtrl = TextEditingController(text: d?.title ?? '');
    _valueCtrl = TextEditingController(text: d?.discountValue.toStringAsFixed(0) ?? '');
    _minDaysCtrl = TextEditingController(text: d?.minRentalDays.toString() ?? '1');
    _maxUsesCtrl = TextEditingController(text: d?.maxUses?.toString() ?? '');

    _discountType = d?.discountType ?? 'percentage';
    _expiryDate = d?.expiryDate ?? DateTime.now().add(const Duration(days: 30));
    _selectedItemIds = List<String>.from(d?.eligibleItemIds ?? []);
    _selectAllItems = d == null || _selectedItemIds.isEmpty;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _titleCtrl.dispose();
    _valueCtrl.dispose();
    _minDaysCtrl.dispose();
    _maxUsesCtrl.dispose();
    _itemSearchCtrl.dispose();
    super.dispose();
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.green.shade700,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red.shade700,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _selectExpiryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _expiryDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      });
    }
  }

  void _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final code = _codeCtrl.text.trim().toUpperCase();
    final title = _titleCtrl.text.trim();
    final val = double.tryParse(_valueCtrl.text.trim()) ?? 0.0;
    final minDays = int.tryParse(_minDaysCtrl.text.trim()) ?? 1;
    final maxUses = _maxUsesCtrl.text.trim().isNotEmpty ? int.tryParse(_maxUsesCtrl.text.trim()) : null;

    if (code.isEmpty) {
      _showErrorSnackBar('Please enter coupon code');
      return;
    }
    if (title.isEmpty) {
      _showErrorSnackBar('Please enter coupon title');
      return;
    }
    if (val <= 0) {
      _showErrorSnackBar('Please enter a valid discount value');
      return;
    }
    if (!_selectAllItems && _selectedItemIds.isEmpty) {
      _showErrorSnackBar('Please select at least one equipment item or check "All Fleet Equipment"');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final storeState = context.read<StoreCubit>().state;
      final storeId = storeState is StoreLoaded ? storeState.store.id : 'demo_store_1';

      final discount = DiscountModel(
        id: widget.existingDiscount?.id ?? UuidGenerator.generateV4(),
        storeId: storeId,
        code: code,
        title: title,
        discountType: _discountType,
        discountValue: val,
        eligibleItemIds: _selectAllItems ? [] : _selectedItemIds,
        minRentalDays: minDays,
        expiryDate: _expiryDate,
        maxUses: maxUses,
        usedCount: widget.existingDiscount?.usedCount ?? 0,
        isActive: widget.existingDiscount?.isActive ?? true,
        createdAt: widget.existingDiscount?.createdAt ?? DateTime.now(),
      );

      await context.read<DiscountCubit>().saveDiscount(discount);
      if (!mounted) return;
      Navigator.pop(context);
      _showSuccessSnackBar(
        widget.existingDiscount == null
            ? 'Discount Coupon "$code" created successfully!'
            : 'Discount Coupon "$code" updated successfully!',
      );
    } catch (e) {
      _showErrorSnackBar('Failed to save discount coupon: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inventoryState = context.watch<InventoryCubit>().state;
    final allItems = inventoryState is InventoryLoaded ? inventoryState.allItems : <InventoryItemModel>[];

    final searchQuery = _itemSearchCtrl.text.trim().toLowerCase();
    final filteredItems = allItems.where((it) {
      if (searchQuery.isEmpty) return true;
      return it.name.toLowerCase().contains(searchQuery) || it.displaySku.toLowerCase().contains(searchQuery);
    }).toList();

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: Text(widget.existingDiscount == null ? 'Create Discount Coupon' : 'Edit Discount Coupon'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Coupon Basic Info Card
              Container(
                padding: const EdgeInsets.all(16),
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
                        Icon(Icons.confirmation_number_outlined, color: isDark ? AppColors.primaryLight : AppColors.primary),
                        const SizedBox(width: 8),
                        const Text('Coupon Identification & Value', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _codeCtrl,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Coupon Code',
                              hintText: 'e.g. SUMMER10',
                              prefixIcon: Icon(Icons.sell_outlined),
                            ),
                            validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _discountType,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Discount Type',
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem<String>(value: 'percentage', child: Text('Percentage (%)')),
                              DropdownMenuItem<String>(value: 'flat', child: Text('Flat Amount')),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _discountType = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _titleCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Discount Title',
                        hintText: 'e.g. 10% Off Summer Rentals',
                        prefixIcon: Icon(Icons.discount_outlined),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _valueCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: _discountType == 'percentage' ? 'Discount Value (%)' : 'Flat Discount Amount',
                        hintText: _discountType == 'percentage' ? 'e.g. 10 for 10% off' : 'e.g. 500',
                        prefixIcon: Icon(_discountType == 'percentage' ? Icons.percent_outlined : Icons.monetization_on_outlined),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _minDaysCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Minimum Rental Duration (Days)',
                        hintText: 'e.g. 1 day',
                        helperText: 'Rental must be at least this many days for coupon to apply',
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 2. Expiry & Usage Limits Card
              Container(
                padding: const EdgeInsets.all(16),
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
                        Icon(Icons.event_outlined, color: isDark ? AppColors.primaryLight : AppColors.primary),
                        const SizedBox(width: 8),
                        const Text('Expiry Date & Usage Limit', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Full Width Expiry Date Selector
                    InkWell(
                      onTap: _selectExpiryDate,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_month, size: 20, color: isDark ? AppColors.primaryLight : AppColors.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Coupon Expiry Date (Default 30 Days)',
                                    style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    DateFormat('dd MMM yyyy (EEEE)').format(_expiryDate),
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              'Change Date',
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

                    const SizedBox(height: 14),

                    // Full Width Max Uses Field
                    TextFormField(
                      controller: _maxUsesCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Maximum Number of Uses (Optional)',
                        hintText: 'e.g. 10 (or leave blank for unlimited redemptions)',
                        helperText: 'Leave blank for unlimited redemptions across all customers',
                        helperMaxLines: 2,
                        prefixIcon: Icon(Icons.numbers_outlined),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 3. Multi-Select Inventory Items Card
              Container(
                padding: const EdgeInsets.all(16),
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
                            Icon(Icons.handyman_outlined, color: isDark ? AppColors.primaryLight : AppColors.primary),
                            const SizedBox(width: 8),
                            const Text('Eligible Inventory Items', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Text(
                          _selectAllItems ? 'All Items Selected' : '${_selectedItemIds.length} Selected',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.primaryLight : AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // "Select All Fleet Equipment" Checkbox Tile
                    Material(
                      color: Colors.transparent,
                      child: CheckboxListTile(
                        value: _selectAllItems,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('All Fleet Equipment (Global Coupon)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: const Text('Coupon applies to every item in your rental fleet', style: TextStyle(fontSize: 11)),
                        activeColor: AppColors.primary,
                        onChanged: (val) {
                          setState(() {
                            _selectAllItems = val ?? false;
                            if (_selectAllItems) {
                              _selectedItemIds.clear();
                            }
                          });
                        },
                      ),
                    ),

                    if (!_selectAllItems) ...[
                      const Divider(height: 16),
                      // Search Bar for Inventory Items
                      TextField(
                        controller: _itemSearchCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search equipment by name or SKU...',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          suffixIcon: _itemSearchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    _itemSearchCtrl.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (filteredItems.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                          child: Center(
                            child: Text(
                              allItems.isEmpty
                                  ? 'No equipment items in inventory yet.\nSelect "All Fleet Equipment" above to create a store-wide coupon.'
                                  : 'No equipment items match search filter.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12, color: AppColors.secondary),
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filteredItems.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = filteredItems[index];
                            final isSelected = _selectedItemIds.contains(item.id);

                            return Material(
                              color: Colors.transparent,
                              child: CheckboxListTile(
                                value: isSelected,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                activeColor: AppColors.primary,
                                title: Text(item.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                subtitle: Text('${item.displaySku} • ${item.category}', style: const TextStyle(fontSize: 11)),
                                secondary: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.handyman, size: 18, color: AppColors.primary),
                                ),
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedItemIds.add(item.id);
                                    } else {
                                      _selectedItemIds.remove(item.id);
                                    }
                                  });
                                },
                              ),
                            );
                          },
                        ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _handleSave,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                        )
                      : Text(
                          widget.existingDiscount == null ? 'Save Discount Coupon' : 'Update Discount Coupon',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
