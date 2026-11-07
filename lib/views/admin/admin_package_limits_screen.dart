import 'package:flutter/material.dart';
import '../../core/config/app_theme.dart';
import '../../data/repositories/admin_repository.dart';

class AdminPackageLimitsScreen extends StatefulWidget {
  const AdminPackageLimitsScreen({super.key});

  @override
  State<AdminPackageLimitsScreen> createState() => _AdminPackageLimitsScreenState();
}

class _AdminPackageLimitsScreenState extends State<AdminPackageLimitsScreen> {
  final AdminRepository _repo = AdminRepository();
  final _formKey = GlobalKey<FormState>();

  final _priceController = TextEditingController();
  final _itemsLimitController = TextEditingController();
  final _leasesLimitController = TextEditingController();
  final _freePhotosLimitController = TextEditingController();
  final _proPhotosLimitController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadLimits();
  }

  @override
  void dispose() {
    _priceController.dispose();
    _itemsLimitController.dispose();
    _leasesLimitController.dispose();
    _freePhotosLimitController.dispose();
    _proPhotosLimitController.dispose();
    super.dispose();
  }

  Future<void> _loadLimits() async {
    setState(() => _isLoading = true);
    final limits = await _repo.getPackageLimits();
    if (mounted) {
      setState(() {
        _priceController.text = limits.proMonthlyPrice;
        _itemsLimitController.text = limits.freeItemsLimit.toString();
        _leasesLimitController.text = limits.freeMonthlyLeasesLimit.toString();
        _freePhotosLimitController.text = limits.freePhotosLimit.toString();
        _proPhotosLimitController.text = limits.proPhotosLimit.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSaveLimits() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final updated = PackageLimitsModel(
        proMonthlyPrice: _priceController.text.trim(),
        freeItemsLimit: int.tryParse(_itemsLimitController.text.trim()) ?? 10,
        freeMonthlyLeasesLimit: int.tryParse(_leasesLimitController.text.trim()) ?? 100,
        freePhotosLimit: int.tryParse(_freePhotosLimitController.text.trim()) ?? 3,
        proPhotosLimit: int.tryParse(_proPhotosLimitController.text.trim()) ?? 6,
      );

      await _repo.updatePackageLimits(updated);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Package limits and pricing saved! Reflecting across the app.'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving limits: $e'),
          backgroundColor: AppColors.errorRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('Package Limits & Pricing Settings'),
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkSurfaceLow : const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.workspace_premium, color: Color(0xFF92400E)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Pro Pricing & Limits Manager',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Updates set here control paywall display and enforce feature limits across all store users.',
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
                      const SizedBox(height: 24),

                      // Pro Monthly Price
                      const Text('Pro Monthly Price (Display & Billing)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _priceController,
                        decoration: const InputDecoration(
                          hintText: 'e.g. ₹349 or \$4.99',
                          prefixIcon: Icon(Icons.attach_money),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return 'Enter Pro Monthly Price';
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),

                      // Free Active Items Limit
                      const Text('Free Plan Active Items Limit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _itemsLimitController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: 'Default: 10',
                          prefixIcon: Icon(Icons.inventory_2_outlined),
                        ),
                        validator: (val) {
                          if (val == null || int.tryParse(val.trim()) == null) return 'Enter valid items count';
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),

                      // Free Monthly Leases Quota
                      const Text('Free Plan Monthly Leases Quota', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _leasesLimitController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: 'Default: 100',
                          prefixIcon: Icon(Icons.assignment_outlined),
                        ),
                        validator: (val) {
                          if (val == null || int.tryParse(val.trim()) == null) return 'Enter valid leases quota';
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),

                      // Free Condition Photos Limit
                      const Text('Free Plan Condition Photos Limit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _freePhotosLimitController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: 'Default: 3',
                          prefixIcon: Icon(Icons.photo_camera_outlined),
                        ),
                        validator: (val) {
                          if (val == null || int.tryParse(val.trim()) == null) return 'Enter valid photos limit';
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),

                      // Pro Condition Photos Limit
                      const Text('Pro Plan Condition Photos Limit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _proPhotosLimitController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: 'Default: 6',
                          prefixIcon: Icon(Icons.photo_camera),
                        ),
                        validator: (val) {
                          if (val == null || int.tryParse(val.trim()) == null) return 'Enter valid photos limit';
                          return null;
                        },
                      ),
                      const SizedBox(height: 28),

                      // Save Action Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _handleSaveLimits,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.save_outlined, size: 18),
                          label: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                                )
                              : const Text('Save & Apply Limits System-Wide', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
