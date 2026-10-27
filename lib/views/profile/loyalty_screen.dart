import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../core/config/app_theme.dart';
import '../../data/models/store_model.dart';
import '../../viewmodels/auth_store/store_cubit.dart';
import '../../viewmodels/auth_store/store_state.dart';

class LoyaltyScreen extends StatefulWidget {
  const LoyaltyScreen({super.key});

  @override
  State<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends State<LoyaltyScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _hourlyRateCtrl;
  late final TextEditingController _dailyRateCtrl;
  late final TextEditingController _expiryDaysCtrl;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final storeState = context.read<StoreCubit>().state;
    final store = storeState is StoreLoaded ? storeState.store : null;

    final hourly = (store != null) ? (store.loyaltyEarnRatePerHour <= 0 ? 1.0 : store.loyaltyEarnRatePerHour) : 1.0;
    final daily = (store != null) ? (store.loyaltyEarnRatePerDay <= 0 ? 10.0 : store.loyaltyEarnRatePerDay) : 10.0;
    final expiry = (store != null) ? (store.loyaltyExpiryDays <= 0 ? 90 : store.loyaltyExpiryDays) : 90;

    _hourlyRateCtrl = TextEditingController(text: hourly.toStringAsFixed(0));
    _dailyRateCtrl = TextEditingController(text: daily.toStringAsFixed(0));
    _expiryDaysCtrl = TextEditingController(text: expiry.toString());
  }

  @override
  void dispose() {
    _hourlyRateCtrl.dispose();
    _dailyRateCtrl.dispose();
    _expiryDaysCtrl.dispose();
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

  void _confirmAndSaveLoyaltySettings(StoreModel store) async {
    if (!_formKey.currentState!.validate()) return;

    final newExpiryDays = int.tryParse(_expiryDaysCtrl.text.trim()) ?? store.loyaltyExpiryDays;
    final isExpiryDaysChanged = newExpiryDays != store.loyaltyExpiryDays;

    if (isExpiryDaysChanged && store.isLoyaltyExpiryLocked) {
      final lockedUntilStr = store.loyaltyExpiryLockedUntil != null
          ? DateFormat('dd MMM yyyy').format(store.loyaltyExpiryLockedUntil!)
          : '30 days';
      _showErrorSnackBar(
        'Points Expiry Days setting is locked for another ${store.remainingLoyaltyLockDays} days (until $lockedUntilStr) and cannot be changed.',
      );
      return;
    }

    if (isExpiryDaysChanged) {
      final lockUntilDate = DateTime.now().add(const Duration(days: 30));
      final dateStr = DateFormat('dd MMM yyyy').format(lockUntilDate);

      final confirm = await showDialog<bool>(
        context: context,
        builder: (dCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Confirm Expiry Lock',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.3)),
                ),
                child: Text(
                  'IMPORTANT: Updating your Loyalty Points Expiry Days will LOCK this setting for 30 days.\n\nYou cannot alter expiry days again until $dateStr.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.amber.shade900),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Are you sure you want to set point expiry to $newExpiryDays days and activate the 30-day lock?',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dCtx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Confirm & Lock for 30 Days'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    if (!mounted) return;

    setState(() => _isSaving = true);

    try {
      final hourlyRate = double.tryParse(_hourlyRateCtrl.text.trim()) ?? store.loyaltyEarnRatePerHour;
      final dailyRate = double.tryParse(_dailyRateCtrl.text.trim()) ?? store.loyaltyEarnRatePerDay;

      DateTime? newLockedUntil = store.loyaltyExpiryLockedUntil;
      if (isExpiryDaysChanged) {
        newLockedUntil = DateTime.now().add(const Duration(days: 30));
      }

      final updatedStore = store.copyWith(
        loyaltyEarnRatePerHour: hourlyRate,
        loyaltyEarnRatePerDay: dailyRate,
        loyaltyExpiryDays: newExpiryDays,
        loyaltyExpiryLockedUntil: newLockedUntil,
        updatedAt: DateTime.now(),
      );

      final storeCubit = context.read<StoreCubit>();
      await storeCubit.updateStore(updatedStore);

      if (!mounted) return;
      _showSuccessSnackBar('Loyalty program rules updated successfully!');
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('Failed to update loyalty settings: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final storeState = context.watch<StoreCubit>().state;
    final store = storeState is StoreLoaded ? storeState.store : null;
    final currency = store?.currencySymbol ?? '₹';

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      appBar: AppBar(
        title: const Text('Customer Loyalty Program'),
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
              // Program Summary Card
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
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text('🪙', style: TextStyle(fontSize: 24)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Loyalty Conversion Value',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '10 Points = 1 $currency (1 Point = $currency 0.10)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? AppColors.primaryLight : AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Clients earn loyalty points when renting equipment. Accumulated points can be redeemed during checkout or settlement to reduce bill totals.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Points Earning Rules Card
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
                        Icon(Icons.stars_outlined, color: isDark ? AppColors.primaryLight : AppColors.primary),
                        const SizedBox(width: 8),
                        const Text('Points Earning Rates', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Hourly Rental Earning Rate', style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _hourlyRateCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  hintText: '1',
                                  suffixText: 'Pts / Hour',
                                  prefixIcon: Icon(Icons.access_time_outlined),
                                ),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) return 'Required';
                                  final num = double.tryParse(val.trim());
                                  if (num == null || num < 0) return 'Invalid';
                                  return null;
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
                              Text('Daily Rental Earning Rate', style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _dailyRateCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  hintText: '10',
                                  suffixText: 'Pts / Day',
                                  prefixIcon: Icon(Icons.wb_sunny_outlined),
                                ),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) return 'Required';
                                  final num = double.tryParse(val.trim());
                                  if (num == null || num < 0) return 'Invalid';
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Points Expiry & 30-Day Lock Rule Card
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
                        Icon(Icons.timer_outlined, color: isDark ? AppColors.primaryLight : AppColors.primary),
                        const SizedBox(width: 8),
                        const Text('Points Expiry & Lock Rule', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (store != null && store.isLoyaltyExpiryLocked) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF3B2A15) : Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.lock, size: 20, color: Colors.amber.shade800),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Expiry Days Setting Locked',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Locked for another ${store.remainingLoyaltyLockDays} days (until ${DateFormat("dd MMM yyyy").format(store.loyaltyExpiryLockedUntil!)})',
                                    style: TextStyle(fontSize: 11, color: isDark ? Colors.amber.shade200 : Colors.amber.shade900),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    Text('Points Expiry Period (Days)', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _expiryDaysCtrl,
                      enabled: store != null ? !store.isLoyaltyExpiryLocked : true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: '90',
                        suffixText: 'Days',
                        prefixIcon: Icon(Icons.history_toggle_off),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Required';
                        final num = int.tryParse(val.trim());
                        if (num == null || num < 7 || num > 365) return 'Enter 7 to 365 days';
                        return null;
                      },
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 14,
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            store != null && store.isLoyaltyExpiryLocked
                                ? 'Locked for 30 days after last update.'
                                : 'Updating this setting will lock expiry days for 30 days.',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_isSaving || store == null) ? null : () => _confirmAndSaveLoyaltySettings(store),
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
                      : const Text('Save Loyalty Settings', style: TextStyle(fontWeight: FontWeight.bold)),
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
