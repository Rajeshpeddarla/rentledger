import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/config/app_theme.dart';
import '../../core/services/r2_storage_service.dart';
import '../../core/utils/country_currency.dart';
import '../../data/models/store_model.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import 'subscription_paywall_screen.dart';

class EditStoreProfileScreen extends StatefulWidget {
  final StoreModel store;

  const EditStoreProfileScreen({super.key, required this.store});

  @override
  State<EditStoreProfileScreen> createState() => _EditStoreProfileScreenState();
}

class _EditStoreProfileScreenState extends State<EditStoreProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _businessNameCtrl;
  late final String _selectedCountry;
  late final TextEditingController _workingHoursCtrl;
  late bool _enableWeekendLease;
  late final TextEditingController _daysPerMonthCtrl;

  late final TextEditingController _storePhoneCtrl;
  late final TextEditingController _storeAddressCtrl;
  late final TextEditingController _upiIdCtrl;
  late final TextEditingController _termsCtrl;

  late final TextEditingController _ownerNameCtrl;
  late final TextEditingController _ownerPhoneCtrl;
  late final TextEditingController _ownerEmailCtrl;
  late final TextEditingController _ownerDobCtrl;
  String _ownerGender = 'Prefer not to say';

  File? _pickedLogo;
  String? _logoR2Url;
  bool _isUploadingLogo = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final store = widget.store;

    _businessNameCtrl = TextEditingController(text: store.businessName);
    _selectedCountry = store.country ?? 'India';
    _workingHoursCtrl = TextEditingController(text: (store.dailyWorkingHours <= 0 ? 8 : store.dailyWorkingHours).toString());
    _enableWeekendLease = store.enableWeekendLease;
    _daysPerMonthCtrl = TextEditingController(text: store.daysPerMonth.toString());

    _storePhoneCtrl = TextEditingController(text: store.phone ?? '');
    _storeAddressCtrl = TextEditingController(text: store.address ?? '');
    _upiIdCtrl = TextEditingController(text: store.upiId ?? '');
    _termsCtrl = TextEditingController(text: store.termsAndConditions);

    _ownerNameCtrl = TextEditingController(text: store.ownerName ?? '');
    _ownerPhoneCtrl = TextEditingController(text: store.ownerPhone ?? '');
    _ownerEmailCtrl = TextEditingController(text: store.ownerEmail ?? '');
    _ownerDobCtrl = TextEditingController(text: store.ownerDob ?? '');
    _ownerGender = store.ownerGender ?? 'Prefer not to say';

    _logoR2Url = store.logoR2Url;
  }

  @override
  void dispose() {
    _businessNameCtrl.dispose();
    _workingHoursCtrl.dispose();
    _daysPerMonthCtrl.dispose();
    _storePhoneCtrl.dispose();
    _storeAddressCtrl.dispose();
    _upiIdCtrl.dispose();
    _termsCtrl.dispose();
    _ownerNameCtrl.dispose();
    _ownerPhoneCtrl.dispose();
    _ownerEmailCtrl.dispose();
    _ownerDobCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    if (!widget.store.isPro) {
      _showLogoSubscriptionLockDialog();
      return;
    }

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked != null) {
        setState(() {
          _pickedLogo = File(picked.path);
        });
      }
    } catch (e) {
      debugPrint('Logo pick error: $e');
    }
  }

  void _showLogoSubscriptionLockDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.workspace_premium, color: AppColors.tertiaryAmber),
            SizedBox(width: 8),
            Text('Pro Subscription Required'),
          ],
        ),
        content: const Text(
          'Adding a custom Store Logo for PDF receipts and invoices unlocks exclusively with RentLedger Pro Subscription.',
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

  void _selectDob() async {
    final now = DateTime.now();
    final initialDate = DateTime(1990, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1940),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _ownerDobCtrl.text = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  void _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final storeCubit = context.read<StoreCubit>();

    try {
      if (_pickedLogo != null && widget.store.isPro) {
        setState(() => _isUploadingLogo = true);
        final filename = 'logo_${widget.store.id}_${DateTime.now().millisecondsSinceEpoch}.webp';
        _logoR2Url = await R2StorageService.instance.uploadImage(
          file: _pickedLogo!,
          folder: 'logos',
          filename: filename,
        );
      }

      final derivedCurrency = CountryCurrency.getCurrencySymbolForCountry(_selectedCountry);
      final workingHours = int.tryParse(_workingHoursCtrl.text.trim()) ?? 8;
      final daysPerMonth = int.tryParse(_daysPerMonthCtrl.text.trim()) ?? 28;

      final updatedStore = widget.store.copyWith(
        businessName: _businessNameCtrl.text.trim(),
        country: _selectedCountry,
        currencySymbol: derivedCurrency,
        dailyWorkingHours: workingHours,
        enableWeekendLease: _enableWeekendLease,
        daysPerMonth: daysPerMonth,
        phone: _storePhoneCtrl.text.trim(),
        address: _storeAddressCtrl.text.trim(),
        upiId: _upiIdCtrl.text.trim(),
        termsAndConditions: _termsCtrl.text.trim(),
        ownerName: _ownerNameCtrl.text.trim(),
        ownerPhone: _ownerPhoneCtrl.text.trim(),
        ownerEmail: _ownerEmailCtrl.text.trim(),
        ownerGender: _ownerGender,
        ownerDob: _ownerDobCtrl.text.trim(),
        logoR2Url: _logoR2Url,
        updatedAt: DateTime.now(),
      );

      await storeCubit.updateStore(updatedStore);

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Store & Owner profile updated successfully!',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppColors.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error updating profile: $e',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppColors.errorRed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isUploadingLogo = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPro = widget.store.isPro;
    final selectedCountryInfo = CountryCurrency.getCountryByName(_selectedCountry);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('Store & Owner Profile'),
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
              // 1. Store Details Section Card
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
                        Icon(Icons.store, color: isDark ? AppColors.primaryLight : AppColors.primary),
                        const SizedBox(width: 8),
                        const Text('Store & Business Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Store Logo Upload Widget
                    GestureDetector(
                      onTap: _pickLogo,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.darkSurface : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: _pickedLogo != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.file(_pickedLogo!, fit: BoxFit.cover),
                                    )
                                  : (_logoR2Url != null && _logoR2Url!.isNotEmpty
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: Image.network(_logoR2Url!, fit: BoxFit.cover),
                                        )
                                      : Icon(
                                          isPro ? Icons.add_a_photo_outlined : Icons.lock_outlined,
                                          color: isPro ? AppColors.primary : AppColors.secondary,
                                        )),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text('Store Branding Logo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                      const SizedBox(width: 6),
                                      if (!isPro)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.tertiaryFixed,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text('PRO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.tertiary)),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isPro
                                        ? 'Appears on PDF Receipts & Settlement Statements'
                                        : 'Unlocks with Subscription (PDF Receipts & Statements)',
                                    style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              isPro ? Icons.edit_outlined : Icons.lock,
                              size: 18,
                              color: isPro ? AppColors.primary : AppColors.tertiaryAmber,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Text('Business Name', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _businessNameCtrl,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Apex Equipment Rentals',
                        prefixIcon: Icon(Icons.business),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                    ),

                    const SizedBox(height: 14),

                    Text('Store Country / Location (Locked)', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),

                    // Locked Store Location Field
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurfaceLow : AppColors.lightSurfaceLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkCard : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              selectedCountryInfo.flag,
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      selectedCountryInfo.name,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isDark ? AppColors.darkCard : Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.lock, size: 10, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                          const SizedBox(width: 3),
                                          Text(
                                            'LOCKED',
                                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Default Currency: ${selectedCountryInfo.symbol} (${selectedCountryInfo.code}) • Fixed location',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.lock_outline,
                            size: 18,
                            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    Text('Store Contact Phone', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _storePhoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        hintText: '+91 9876543210',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),

                    const SizedBox(height: 14),

                    Text('Physical Store Address', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _storeAddressCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: '123 Commercial Market, Station Road',
                        prefixIcon: Icon(Icons.location_city_outlined),
                      ),
                    ),

                    const SizedBox(height: 14),

                    Text('UPI ID for Payment QR Code', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _upiIdCtrl,
                      decoration: const InputDecoration(
                        hintText: 'e.g. storename@okaxis',
                        prefixIcon: Icon(Icons.qr_code_2),
                      ),
                    ),

                    const SizedBox(height: 14),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Rental Terms on PDF Receipts', style: Theme.of(context).textTheme.titleSmall),
                        const Text('Max 300 chars', style: TextStyle(fontSize: 10, color: AppColors.secondary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _termsCtrl,
                      maxLines: 3,
                      maxLength: 300,
                      decoration: const InputDecoration(
                        hintText: 'Terms and conditions for customer leases (Max 300 characters to fit on single-page PDF receipts)...',
                        helperText: 'Max 300 characters to fit on single-page PDF receipts',
                      ),
                      validator: (val) {
                        if (val != null && val.length > 300) {
                          return 'Rental terms cannot exceed 300 characters';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 2. Rental Shift & Rate Calculation Rules Card
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
                        Icon(Icons.tune, color: isDark ? AppColors.primaryLight : AppColors.primary),
                        const SizedBox(width: 8),
                        const Text('Rental Shift & Rate Rules', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Text('Daily Working Shift Length (Hours/Day)', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _workingHoursCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: '8 (Default)',
                        prefixIcon: Icon(Icons.access_time_outlined),
                        helperText: 'Shift length used to auto-calculate hourly <-> daily rates',
                      ),
                      validator: (val) {
                        if (val != null && val.trim().isNotEmpty) {
                          final hours = int.tryParse(val.trim());
                          if (hours == null || hours < 1 || hours > 24) {
                            return 'Shift length must be between 1 and 24 hours';
                          }
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 14),

                    // Enable Weekend / Sundays Lease Switch
                    Material(
                      color: Colors.transparent,
                      child: SwitchListTile(
                        value: _enableWeekendLease,
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: AppColors.primary,
                        title: const Text('Include Sundays / Weekends in Weekly Rate', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          _enableWeekendLease ? '1 Week = 7 Rental Days (Includes Sundays)' : '1 Week = 6 Rental Days (Excludes Sundays)',
                          style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary),
                        ),
                        onChanged: (val) {
                          setState(() => _enableWeekendLease = val);
                        },
                      ),
                    ),

                    const SizedBox(height: 10),

                    Text('Days Per Monthly Lease', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _daysPerMonthCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: '28 (Default)',
                        prefixIcon: Icon(Icons.calendar_view_month_outlined),
                        helperText: 'Days multiplier used when auto-calculating monthly rates',
                      ),
                      validator: (val) {
                        if (val != null && val.trim().isNotEmpty) {
                          final days = int.tryParse(val.trim());
                          if (days == null || days < 15 || days > 31) {
                            return 'Days per month must be between 15 and 31';
                          }
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 3. Owner Details Section Card
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
                        Icon(Icons.person_outline, color: isDark ? AppColors.primaryLight : AppColors.primary),
                        const SizedBox(width: 8),
                        const Text('Owner Personal Details (Optional)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Text('Owner Full Name', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _ownerNameCtrl,
                      decoration: const InputDecoration(
                        hintText: 'John Doe',
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),

                    const SizedBox(height: 14),

                    Text('Owner Direct Phone Number', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _ownerPhoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        hintText: '+91 9999888877',
                        prefixIcon: Icon(Icons.phone_android_outlined),
                      ),
                    ),

                    const SizedBox(height: 14),

                    Text('Owner Email Address (Optional)', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _ownerEmailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        hintText: 'owner@example.com',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),

                    const SizedBox(height: 14),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Gender', style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                initialValue: _ownerGender,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                  isDense: true,
                                ),
                                items: ['Male', 'Female', 'Other', 'Prefer not to say'].map((g) {
                                  return DropdownMenuItem(
                                    value: g,
                                    child: Text(
                                      g,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _ownerGender = val);
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
                              Text('Date of Birth', style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _ownerDobCtrl,
                                readOnly: true,
                                onTap: _selectDob,
                                decoration: const InputDecoration(
                                  hintText: 'YYYY-MM-DD',
                                  prefixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                  isDense: true,
                                ),
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
                onPressed: (_isSaving || _isUploadingLogo) ? null : _handleSave,
                child: (_isSaving || _isUploadingLogo)
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                      )
                    : const Text('Save Profile Changes'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
